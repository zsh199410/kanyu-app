#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Surge #73 / PR #93 automatic failed-node pruning (isolate -> retest -> delete).

Pure decision engine plus a read-only evidence reader and an append-only
ledger. This module NEVER writes the pool files and NEVER touches the
bridge, credential issuance, or the old dual writers. Only
``single_writer.publish`` writes served/staging, under its existing
flock, guard, ban-proof and rollback. The old
``candidate_contract.assess_candidate`` is NOT modified: pruning is
admitted only through ``assess_candidate_with_prune`` below, which
allows exactly the authorized removal set and nothing else.

Rules (see AUTO_PRUNE_DESIGN.md for the full design):
  * Identity is (protocol, host, port). Display names are never a key.
  * VPS path: a node is ISOLATED after real connection failures; it
    stays in the pool. Deletion needs ALL of: >=3 distinct hour
    buckets of ``result='fail'`` + ``reason='curl-failed'`` spanning
    >=2 h, no ``pass`` in the last 24 h, no contemporaneous phone
    success, and a failure in a LATER independent round after
    isolation (retest).
  * ``pass`` at any latency (including >= 300 ms) is a success, never a
    failure. ``result='infra'`` (harness failure) never counts.
    "Winner not reported" is not failure. Absence of a test is not
    failure.
  * Caps (V2): at most 8 deletions per round (hard ceiling); the first
    V2 deletion round caps at 4 (warmup), then 8. Pins (21 canonical)
    are never deleted. Blocklist is append-only.
  * Any fail-closed trigger -> HOLD the whole cycle: no deletion, no
    publish, served/staging untouched, reason logged.
  * No full node URIs or credentials appear in any record, log or
    receipt produced here. Original pool line bytes are kept only in a
    0600 backup directory on the VPS, never in the JSONL ledger.

Self-contained: the pool parser below mirrors the strict parser in
``candidate_contract._parse_pool`` so this module can be tested and
run in isolation without importing the live publisher package.
PHONE-FIRST EXTENSION (2026-11-20) + DYNAMIC POOL V2 (2026-11-21):
a phone-failure evidence path is ADDED alongside the VPS-failure path.
A VPS pass no longer vetoes a deletion that is proven by phone
failures (the phone is the actual arbiter; the VPS is only a proxy).
The VPS path below is UNCHANGED. V2 phone path: a node is ISOLATED
after ONE credible phone-failure report, and DELETED only after a 2nd
independent phone failure >=15 min after the 1st arrives after the
isolation time (confirming retest), with no phone success since the
first phone failure. Re-isolation never resets the isolation clock.
Phone failures live in a ``phone_failures`` table (protocol, host,
port, reported_at, source, detail); a missing table means the phone
path is inactive (NOT a HOLD). Pins are never deleted by either path.
V2 pool-size target: 8-15 rotation nodes. Above 15, the worst excess
(most phone failures, fewest VPS passes, highest VPS median latency)
is trimmed without replenishment; rotation never drops below 8 by
trimming. Phone reports no millisecond latency, so VPS median ms
(24h pass rows) is the documented latency approximation.
"""
from __future__ import annotations

import hashlib
import json
import math
import os
import sqlite3
import time
from collections import Counter, defaultdict
from pathlib import Path
from urllib.parse import quote

# --- thresholds (hard requirements, see AUTO_PRUNE_DESIGN.md) ---
# V2 (2026-11-21, dynamic pool): hard ceiling 8/round; the first V2
# deletion round is capped at 4 (warmup), then 8 once a V2 deletion has
# been published (see prune-v2-meta.json). Env cap is the ceiling.
MAX_DELETE_PER_ROUND = 8
V2_WARMUP_CAP = 4
V2_STABLE_CAP = 8
MIN_FAIL_BUCKETS = 3
MIN_SPAN_HOURS = 2
NO_SUCCESS_WINDOW_S = 24 * 3600
EVIDENCE_WINDOW_S = 48 * 3600
MIN_TESTED_KEYS_24H = 10
MIN_TESTED_KEYS_LATEST_BUCKET = 10
MAX_FAIL_FRACTION_LATEST = 0.5
FRESH_EVIDENCE_MAX_AGE_S = 6 * 3600
MAX_FUTURE_SKEW_S = 300
MAX_ROW_AGE_S = 45 * 86400
MAX_ROWS = 100000
EXPECTED_PIN_COUNT = 21
MAX_BYTES = 2 * 1024 * 1024
MAX_REPLENISH_PER_COUNTRY = 2
PRUNE_MARKER_CONTENT = "PR93_APPROVED_AUTO_PRUNE"
REQUIRED_TABLES = {"nodes", "node_tests", "pinned", "blocklist"}
# --- phone-first thresholds (see PHONE_FIRST_PRUNE_DESIGN.md §3) ---
# V2 (2026-11-21): 1 credible phone failure -> isolate; a 2nd independent
# failure >=15 min after the 1st, arriving after isolation, -> delete.
PHONE_MIN_FAIL_BUCKETS_ISOLATE = 1
PHONE_MIN_SPAN_HOURS = 0
PHONE_MIN_DELETE_GAP_S = 900
PHONE_EVIDENCE_WINDOW_S = 48 * 3600
PHONE_FAILURE_SOURCES = {"surge-url-test", "user-report", "bridge-logbook"}
# --- V2 pool-size targets (rotation = pool minus 21 pins) ---
POOL_ROTATION_TARGET_MAX = 15
POOL_ROTATION_TARGET_MIN = 8


class PruneRefused(ValueError):
    """Fail-closed refusal: no deletion, and (for the cycle) no publish."""


# ---------------------------------------------------------------------------
# Identity + pool parsing (key = (protocol, host, port), never the name)
# ---------------------------------------------------------------------------

def validate_key(key):
    if (not isinstance(key, (tuple, list)) or len(key) != 3):
        raise PruneRefused("bad_node_key")
    proto, host, port = key
    if (not isinstance(proto, str) or not proto or
            not isinstance(host, str) or not host):
        raise PruneRefused("bad_node_key")
    if isinstance(port, bool) or not isinstance(port, int) or not 0 < port < 65536:
        raise PruneRefused("bad_node_key")
    return proto, host, port


def key_id(key):
    """Stable, desensitized ledger id for a key (no URI material)."""
    proto, host, port = validate_key(key)
    return "%s|%s|%d" % (proto, host, port)


def host_prefix(host, n=12):
    return host[:n] if len(host) > n else host


def parse_surge_line(line):
    """Parse one Surge proxy declaration line -> (protocol, host, port).

    Authoritative parser in production is the legacy crawler's
    ``parse_surge_line``; this fallback implements the same Surge
    ``name = proto, host, port, ...`` shape for isolated use.
    """
    if "=" not in line:
        raise PruneRefused("not_a_proxy_declaration")
    name, _, definition = line.partition("=")
    name, definition = name.strip(), definition.strip()
    if not name or not definition:
        raise PruneRefused("not_a_proxy_declaration")
    parts = [p.strip() for p in definition.split(",")]
    if len(parts) < 3:
        raise PruneRefused("not_a_proxy_declaration")
    proto = parts[0].lower()
    if not proto or not parts[1]:
        raise PruneRefused("not_a_proxy_declaration")
    if proto in ("direct", "reject"):
        raise PruneRefused("direct_or_reject_line")
    try:
        port = int(parts[2])
    except ValueError as exc:
        raise PruneRefused("bad_proxy_port") from exc
    return name, validate_key((proto, parts[1], port))


def parse_pool(raw):
    """Parse pool bytes -> (by_key, by_name). Raises PruneRefused."""
    if not isinstance(raw, bytes) or not 0 < len(raw) <= MAX_BYTES:
        raise PruneRefused("invalid_pool_size")
    try:
        text = raw.decode("utf-8", errors="strict")
    except UnicodeDecodeError as exc:
        raise PruneRefused("pool_invalid_utf8") from exc
    by_key, by_name = {}, {}
    for line in text.splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        if "=" not in line:
            raise PruneRefused("not_a_proxy_declaration")
        name, key = parse_surge_line(line)
        if name in ("DIRECT", "REJECT"):
            raise PruneRefused("direct_or_reject_line")
        if name in by_name:
            raise PruneRefused("duplicate_node_name")
        if key in by_key:
            raise PruneRefused("duplicate_node_key")
        by_key[key] = {"name": name, "line": line}
        by_name[name] = key
    if not by_key:
        raise PruneRefused("empty_node_pool")
    return by_key, by_name


# ---------------------------------------------------------------------------
# Read-only evidence reader (pool.db is opened mode=ro, never written)
# ---------------------------------------------------------------------------

def _sqlite_readonly(path):
    p = Path(path)
    if not p.is_absolute() or not p.is_file():
        raise PruneRefused("db_invalid_or_missing")
    uri = "file:" + quote(str(p.resolve()), safe="/") + "?mode=ro"
    conn = sqlite3.connect(uri, uri=True, timeout=8.0)
    conn.execute("PRAGMA query_only=ON")
    conn.execute("BEGIN")
    return conn


def _is_trusted_phone_failure(source, detail):
    """G10 consumer gate (integration-01): only a surge-url-test row whose
    detail proves control_verified=1 + probe method 'external_policy_id' +
    bearer 'cellular' counts as credible phone failure evidence. Manual
    reports, bridge logbook rows and legacy imports without provenance are
    diagnostic history and must not move any prune verdict. Accepts both
    the JSON detail written by the v2 importer and the key=value detail
    written by the legacy importer. Returns True/False; never raises on
    malformed detail (fail-closed: malformed detail is unverified, not
    trusted)."""
    if source != "surge-url-test":
        return False
    if not isinstance(detail, str) or not detail:
        return False
    data = {}
    text = detail.strip()
    if text.startswith("{"):
        try:
            data = json.loads(text)
        except ValueError:
            return False
        if not isinstance(data, dict):
            return False
    else:
        for part in text.split():
            if "=" in part:
                key, _, value = part.partition("=")
                data[key] = value
    cv = data.get("control_verified")
    if cv not in (1, "1", True, "true"):
        return False
    method = data.get("method", data.get("probe_mode"))
    if method != "external_policy_id":
        return False
    if data.get("bearer") != "cellular":
        return False
    return True


def read_failure_evidence(db_path, pool_keys, now):
    """Read failure/pass/phone evidence for exactly the pool keys.

    Returns a desensitized evidence dict (keys + timestamps + counts,
    no URIs). Raises PruneRefused on any integrity problem, so the
    caller HOLDs instead of deleting on partial evidence.
    """
    if type(now) not in (int, float) or isinstance(now, bool) or not math.isfinite(now):
        raise PruneRefused("clock_invalid")
    pool_keys = {validate_key(k) for k in pool_keys}
    conn = _sqlite_readonly(db_path)
    try:
        names = {r[0] for r in conn.execute(
            "SELECT name FROM sqlite_master WHERE type='table'")}
        if not REQUIRED_TABLES <= names:
            raise PruneRefused("db_missing_required_tables")
        window_from = int(now) - EVIDENCE_WINDOW_S
        rows = conn.execute(
            "SELECT protocol,host,port,tested_at,result,reason,ms "
            "FROM node_tests WHERE tested_at > ?",
            (window_from,)).fetchmany(MAX_ROWS + 1)
        if len(rows) > MAX_ROWS:
            raise PruneRefused("db_excessive_rows")
        per_key = {k: {"fail_buckets": defaultdict(list),
                       "passes_24h": 0, "last_pass_at": None,
                       "latest": None, "fail_count": 0,
                       "pass_count": 0,
                       "latency_ms_24h": []} for k in pool_keys}
        newest_tested_at = None
        for proto, host, port, tested_at, result, reason, ms in rows:
            try:
                k = validate_key((proto, host, port))
            except PruneRefused:
                raise PruneRefused("db_invalid_key")
            if type(tested_at) not in (int, float) or not math.isfinite(tested_at):
                raise PruneRefused("db_bad_timestamp")
            if tested_at > now + MAX_FUTURE_SKEW_S:
                raise PruneRefused("db_future_timestamp_clock_skew")
            if tested_at < now - MAX_ROW_AGE_S:
                raise PruneRefused("db_absurdly_old_timestamp")
            if type(ms) not in (int, float, type(None)) or (
                    isinstance(ms, float) and not math.isfinite(ms)):
                raise PruneRefused("db_bad_latency")
            if newest_tested_at is None or tested_at > newest_tested_at:
                newest_tested_at = tested_at
            if k not in per_key:
                continue
            rec = per_key[k]
            if rec["latest"] is None or tested_at > rec["latest"][0]:
                rec["latest"] = (tested_at, result, reason)
            if result == "fail" and reason == "curl-failed":
                rec["fail_buckets"][int(tested_at) // 3600].append(int(tested_at))
                rec["fail_count"] += 1
            elif result == "pass":
                rec["pass_count"] += 1
                if tested_at > now - NO_SUCCESS_WINDOW_S:
                    rec["passes_24h"] += 1
                    # V2: VPS latency samples for the high-latency rank.
                    # Phone reports no millisecond latency; VPS ms is the
                    # documented approximation, never presented as phone ms.
                    if isinstance(ms, (int, float)) and math.isfinite(ms):
                        rec["latency_ms_24h"].append(ms)
                if rec["last_pass_at"] is None or tested_at > rec["last_pass_at"]:
                    rec["last_pass_at"] = int(tested_at)
            elif result == "infra":
                pass  # harness failure: never node evidence
            else:
                raise PruneRefused("db_unknown_test_result")
        # Phone evidence, both sources, in the same window.
        phone_keyed = {}  # key -> [reported_at, ...]
        if "scheme_a_winners" in names:
            for proto, host, port, reported_at in conn.execute(
                    "SELECT protocol,host,port,reported_at FROM "
                    "scheme_a_winners WHERE reported_at > ?",
                    (window_from,)).fetchall():
                k = validate_key((proto, host, port))
                if k in per_key:
                    phone_keyed.setdefault(k, []).append(int(reported_at))
        phone_by_name = {}  # winner name -> [ts, ...]
        if "winner_reports" in names:
            for ts, wname in conn.execute(
                    "SELECT ts,name FROM winner_reports WHERE ts > ?",
                    (window_from,)).fetchall():
                phone_by_name.setdefault(wname, []).append(int(ts))
        # PHONE-FIRST: phone-failure evidence (new table). A missing
        # table means the phone path is inactive, NOT a HOLD.
        # G10 (integration-01): only trusted phone failures enter the
        # verdict path. Rows without provenance (legacy imports, manual
        # reports, logbook) are counted separately as diagnostic history
        # and never move a verdict. History rows pre-dating the
        # control_verified detail field therefore do not count as credible
        # failures under the new rule.
        phone_failures = {}  # key -> [(reported_at, source), ...] (trusted only)
        phone_failures_unverified = {}  # key -> count (diagnostic history)
        if "phone_failures" in names:
            for proto, host, port, reported_at, source, detail in conn.execute(
                    "SELECT protocol,host,port,reported_at,source,detail FROM "
                    "phone_failures WHERE reported_at > ?",
                    (window_from,)).fetchall():
                k = validate_key((proto, host, port))
                if type(reported_at) not in (int, float) or \
                        not math.isfinite(reported_at):
                    raise PruneRefused("db_bad_timestamp")
                if reported_at > now + MAX_FUTURE_SKEW_S:
                    raise PruneRefused("db_future_timestamp_clock_skew")
                if reported_at < now - MAX_ROW_AGE_S:
                    raise PruneRefused("db_absurdly_old_timestamp")
                if source not in PHONE_FAILURE_SOURCES:
                    raise PruneRefused("db_unknown_phone_failure_source")
                if k in per_key:
                    if _is_trusted_phone_failure(source, detail):
                        phone_failures.setdefault(k, []).append(
                            (int(reported_at), source))
                    else:
                        phone_failures_unverified[k] = phone_failures_unverified.get(k, 0) + 1
        # V2: per-key VPS latency median (24h pass rows).
        for rec in per_key.values():
            samples = sorted(rec["latency_ms_24h"])
            if samples:
                mid = len(samples) // 2
                rec["latency_ms_median_24h"] = (
                    samples[mid] if len(samples) % 2 == 1
                    else (samples[mid - 1] + samples[mid]) / 2)
            else:
                rec["latency_ms_median_24h"] = None
            rec["latency_samples_24h"] = len(samples)
        return {
            "per_key": per_key,
            "phone_keyed": phone_keyed,
            "phone_by_name": phone_by_name,
            "phone_failures": phone_failures,
            "phone_failures_unverified": phone_failures_unverified,
            "newest_tested_at": newest_tested_at,
            "now": int(now),
            "window_from": window_from,
        }
    except sqlite3.Error as exc:
        raise PruneRefused("db_schema_or_query_mismatch") from exc
    finally:
        try:
            conn.rollback()
        finally:
            conn.close()


def latest_bucket_stats(evidence, pool_keys):
    """Fail fraction among pool keys tested in the latest hour bucket."""
    per_key = evidence["per_key"]
    buckets = defaultdict(list)  # bucket -> [(key, result)]
    for k in pool_keys:
        rec = per_key.get(k)
        if not rec or not rec["latest"]:
            continue
        ts, result, _reason = rec["latest"]
        # Only rows in the newest bucket count as "the latest round".
        buckets[int(ts) // 3600].append((k, result))
    if not buckets:
        return {"tested": 0, "failing": 0, "fraction": 0.0, "bucket": None}
    latest_bucket = max(buckets)
    # Recompute from full history would need bucket rows; use latest-test
    # rows as the round snapshot: a key counts as tested in the latest
    # bucket iff its most recent test falls in it.
    tested = buckets[latest_bucket]
    failing = [k for k, r in tested if r == "fail"]
    return {"tested": len(tested), "failing": len(failing),
            "fraction": (len(failing) / len(tested)) if tested else 0.0,
            "bucket": latest_bucket}


# ---------------------------------------------------------------------------
# Decision engine
# ---------------------------------------------------------------------------

def _phone_veto(evidence, by_name, key, first_fail_ts, now):
    """True if contemporaneous verified phone success exists for key."""
    for ts in evidence["phone_keyed"].get(key, []):
        if first_fail_ts <= ts <= now:
            return True, "scheme_a_winners"
    name = by_name and next(
        (nm for nm, kk in by_name.items() if kk == key), None)
    if name:
        for ts in evidence["phone_by_name"].get(name, []):
            if first_fail_ts <= ts <= now:
                return True, "winner_reports"
    return False, None


def phone_path_verdict(evidence, by_name, key, prior, now):
    """Phone-path verdict for one key (PHONE-FIRST extension).

    prior: the prior prune-state record for this key, or None.
    Returns a dict with fail_buckets, fail_count, first_fail_ts,
    verdict (PHONE_KEEP / PHONE_ISOLATE / PHONE_DELETE /
    PHONE_KEEP_VETO), veto_source, and retest_ts.
    A single phone-failure report never isolates or deletes. A VPS
    pass is deliberately NOT consulted here: the phone is the arbiter.
    """
    reports = evidence.get("phone_failures", {}).get(key, [])
    if not reports:
        return {"fail_buckets": [], "fail_count": 0, "first_fail_ts": None,
                "verdict": "PHONE_KEEP", "veto_source": None,
                "retest_ts": None}
    buckets = sorted({int(ts) // 3600 for ts, _ in reports})
    first_fail_ts = min(ts for ts, _ in reports)
    veto, source = _phone_veto(evidence, by_name, key, first_fail_ts, now)
    if veto:
        return {"fail_buckets": buckets, "fail_count": len(reports),
                "first_fail_ts": first_fail_ts,
                "verdict": "PHONE_KEEP_VETO", "veto_source": source,
                "retest_ts": None}
    if len(buckets) < PHONE_MIN_FAIL_BUCKETS_ISOLATE:
        return {"fail_buckets": buckets, "fail_count": len(reports),
                "first_fail_ts": first_fail_ts,
                "verdict": "PHONE_KEEP", "veto_source": None,
                "retest_ts": None}
    if buckets[-1] - buckets[0] < PHONE_MIN_SPAN_HOURS:
        return {"fail_buckets": buckets, "fail_count": len(reports),
                "first_fail_ts": first_fail_ts,
                "verdict": "PHONE_KEEP", "veto_source": None,
                "retest_ts": None}
    # Threshold met for isolation. Delete only if the key is already
    # ISOLATED (either path) and a phone failure arrived after the
    # isolation time AND >=15 min after the first failure (a 2nd
    # independent failure, confirming retest in a later round).
    if prior and prior.get("state") == "ISOLATED":
        isolated_at = prior.get("isolated_at", now)
        retest = [ts for ts, _ in reports
                  if ts > isolated_at
                  and ts - first_fail_ts >= PHONE_MIN_DELETE_GAP_S]
        if retest:
            return {"fail_buckets": buckets, "fail_count": len(reports),
                    "first_fail_ts": first_fail_ts,
                    "verdict": "PHONE_DELETE", "veto_source": None,
                    "retest_ts": min(retest)}
    return {"fail_buckets": buckets, "fail_count": len(reports),
            "first_fail_ts": first_fail_ts,
            "verdict": "PHONE_ISOLATE", "veto_source": None,
            "retest_ts": None}


def decide(evidence, *, by_key, by_name, pins, blocked, prior_state, cap, now):
    """Decide deletions / isolations / fail-closed HOLD.

    pins / blocked: sets of keys. prior_state: {key_id: record}.
    Returns a decision dict with desensitized per-key evidence.
    """
    now = int(now)
    decision = {"action": "NO_CHANGE", "delete_keys": [], "isolate_keys": [],
                "recover_keys": [], "fail_closed_reason": None,
                "per_key": {}, "new_state": {}}
    pool_keys = set(by_key)
    if not pool_keys:
        decision.update(action="HOLD_FAIL_CLOSED",
                        fail_closed_reason="empty_pool")
        return decision
    pin_keys = {validate_key(k) for k in pins}
    blocked_keys = {validate_key(k) for k in blocked}
    if len(pin_keys) != EXPECTED_PIN_COUNT:
        decision.update(action="HOLD_FAIL_CLOSED",
                        fail_closed_reason="canonical_pin_count_not_21")
        return decision
    if not pin_keys <= pool_keys:
        decision.update(action="HOLD_FAIL_CLOSED",
                        fail_closed_reason="pinned_key_missing_from_pool")
        return decision
    if blocked_keys & pool_keys:
        decision.update(action="HOLD_FAIL_CLOSED",
                        fail_closed_reason="blocked_key_in_pool")
        return decision
    # --- fail-closed: evidence freshness / thinness (F2, F5) ---
    newest = evidence.get("newest_tested_at")
    if newest is None or now - newest > FRESH_EVIDENCE_MAX_AGE_S:
        decision.update(action="HOLD_FAIL_CLOSED",
                        fail_closed_reason="evidence_stale_no_recent_pool_test")
        return decision
    tested_24h = sum(
        1 for k in pool_keys
        if evidence["per_key"].get(k, {}).get("latest") and
        evidence["per_key"][k]["latest"][0] > now - NO_SUCCESS_WINDOW_S)
    if tested_24h < MIN_TESTED_KEYS_24H:
        decision.update(action="HOLD_FAIL_CLOSED",
                        fail_closed_reason="evidence_thin_few_pool_keys_tested_24h")
        return decision
    # --- fail-closed: network-wide anomaly (F3) ---
    stats = latest_bucket_stats(evidence, pool_keys)
    if stats["tested"] < MIN_TESTED_KEYS_LATEST_BUCKET:
        decision.update(action="HOLD_FAIL_CLOSED",
                        fail_closed_reason="evidence_thin_latest_round")
        return decision
    if stats["fraction"] > MAX_FAIL_FRACTION_LATEST:
        decision.update(action="HOLD_FAIL_CLOSED",
                        fail_closed_reason="network_anomaly_many_pool_keys_failing")
        return decision
    # --- per-key evaluation ---
    candidates = []  # (first_fail_bucket, key, per-key evidence)
    new_state = {}
    for k in sorted(pool_keys):
        rec = evidence["per_key"].get(k)
        if rec is None:
            continue  # never tested: absence of tests is not evidence
        name = by_key[k]["name"]
        pk = {"name": name, "protocol": k[0], "port": k[2],
              "host_prefix": host_prefix(k[1]),
              "fail_buckets": sorted(rec["fail_buckets"]),
              "fail_count": rec["fail_count"],
              "passes_24h": rec["passes_24h"],
              "last_pass_at": rec["last_pass_at"],
              "latency_ms_median_24h": rec.get("latency_ms_median_24h"),
              "latency_samples_24h": rec.get("latency_samples_24h", 0)}
        decision["per_key"][key_id(k)] = pk
        if k in pin_keys:
            pk["verdict"] = "KEEP_PINNED"
            continue
        buckets = sorted(rec["fail_buckets"])
        if len(buckets) < MIN_FAIL_BUCKETS:
            if buckets and rec["passes_24h"] == 0:
                # Failing but below threshold: isolate, keep in pool.
                new_state[key_id(k)] = {
                    "state": "ISOLATED", "isolated_at": now,
                    "first_fail_bucket": buckets[0],
                    "fail_buckets": buckets}
                decision["isolate_keys"].append(k)
                pk["verdict"] = "ISOLATE_BELOW_THRESHOLD"
            else:
                pk["verdict"] = "KEEP"
                if key_id(k) in prior_state:
                    decision["recover_keys"].append(k)
            continue
        span = buckets[-1] - buckets[0]
        if span < MIN_SPAN_HOURS:
            new_state[key_id(k)] = {
                "state": "ISOLATED", "isolated_at": now,
                "first_fail_bucket": buckets[0], "fail_buckets": buckets}
            decision["isolate_keys"].append(k)
            pk["verdict"] = "ISOLATE_SPAN_TOO_SHORT"
            continue
        if rec["passes_24h"] > 0:
            pk["verdict"] = "KEEP_RECOVERED_PASS_IN_24H"
            if key_id(k) in prior_state:
                decision["recover_keys"].append(k)
            continue
        first_fail_ts = min(min(v) for v in
                            (rec["fail_buckets"][b] for b in buckets))
        veto, source = _phone_veto(evidence, by_name, k, first_fail_ts, now)
        if veto:
            pk["verdict"] = "KEEP_PHONE_SUCCESS_" + source
            pk["phone_veto_source"] = source
            if key_id(k) in prior_state:
                decision["recover_keys"].append(k)
            continue
        prior = prior_state.get(key_id(k))
        if not prior or prior.get("state") != "ISOLATED":
            # First time the full threshold is met: isolate only. The
            # retest must be a failure in a LATER independent round.
            new_state[key_id(k)] = {
                "state": "ISOLATED", "isolated_at": now,
                "first_fail_bucket": buckets[0], "fail_buckets": buckets}
            decision["isolate_keys"].append(k)
            pk["verdict"] = "ISOLATE_FIRST_THRESHOLD_MET"
            continue
        isolated_at = prior.get("isolated_at", now)
        retest = [ts for b in buckets for ts in rec["fail_buckets"][b]
                  if ts > isolated_at]
        if not retest:
            new_state[key_id(k)] = {
                "state": "ISOLATED", "isolated_at": isolated_at,
                "first_fail_bucket": buckets[0], "fail_buckets": buckets}
            decision["isolate_keys"].append(k)
            pk["verdict"] = "ISOLATE_AWAITING_RETEST"
            continue
        pk["verdict"] = "DELETE_CANDIDATE"
        pk["path"] = "vps"
        pk["retest_at"] = min(retest)
        pk["first_fail_ts"] = first_fail_ts
        candidates.append((buckets[0], k))
    # --- PHONE-FIRST second pass (additive; VPS loop above untouched) ---
    # A VPS pass no longer vetoes a deletion proven by phone failures.
    # The phone path can upgrade KEEP -> ISOLATE/DELETE and ISOLATE ->
    # DELETE. It never touches a pin, never overrides a VPS DELETE, and
    # its deletions share the same cap and healthy-remainder check below.
    _vps_delete_set = {k for _, k in candidates}
    for k in sorted(pool_keys):
        pk = decision["per_key"].get(key_id(k))
        if pk is None:
            continue  # never tested and no VPS record: no phone verdict
        pv = phone_path_verdict(evidence, by_name, k,
                                prior_state.get(key_id(k)), now)
        pk["phone_fail_buckets"] = pv["fail_buckets"]
        pk["phone_fail_count"] = pv["fail_count"]
        pk["phone_first_fail_ts"] = pv["first_fail_ts"]
        pk["phone_verdict"] = pv["verdict"]
        if pv["veto_source"]:
            pk["phone_veto_source"] = pv["veto_source"]
        if k in pin_keys:
            continue  # pins: record phone evidence, never isolate/delete
        if pv["verdict"] == "PHONE_DELETE":
            if k not in _vps_delete_set:
                pk["verdict"] = "DELETE_CANDIDATE_PHONE"
                pk["path"] = "phone"
                pk["retest_at"] = pv["retest_ts"]
                pk["first_fail_ts"] = pv["first_fail_ts"]
                candidates.append((pv["fail_buckets"][0], k))
                _vps_delete_set.add(k)
                if k in decision["recover_keys"]:
                    decision["recover_keys"].remove(k)
        elif pv["verdict"] == "PHONE_ISOLATE":
            if (k not in decision["isolate_keys"]
                    and k not in _vps_delete_set
                    and key_id(k) not in new_state):
                # V2: never reset the isolation clock on re-isolation.
                # The delete retest needs a failure AFTER the ORIGINAL
                # isolation time; resetting it every cycle would make
                # deletion unreachable.
                prior_rec = prior_state.get(key_id(k))
                if prior_rec and prior_rec.get("state") == "ISOLATED":
                    isolated_at = prior_rec.get("isolated_at", now)
                    first_bucket = prior_rec.get(
                        "first_fail_bucket", pv["fail_buckets"][0])
                else:
                    isolated_at = now
                    first_bucket = pv["fail_buckets"][0]
                decision["isolate_keys"].append(k)
                new_state[key_id(k)] = {
                    "state": "ISOLATED", "isolated_at": isolated_at,
                    "path": "phone",
                    "first_fail_bucket": first_bucket,
                    "fail_buckets": pv["fail_buckets"]}
                pk["verdict"] = "ISOLATE_PHONE"
                if k in decision["recover_keys"]:
                    decision["recover_keys"].remove(k)
    # Preserve isolation records for keys still isolated but not
    # re-evaluated above (e.g. untested this cycle): keep prior state.
    pool_ids = {key_id(k) for k in pool_keys}
    delete_ids = {key_id(k) for _, k in candidates}
    recover_ids = {key_id(k) for k in decision["recover_keys"]}
    for kid, prec in prior_state.items():
        if (kid in pool_ids and kid not in new_state
                and kid not in delete_ids and kid not in recover_ids):
            new_state[kid] = prec
    decision["new_state"] = new_state
    # --- V2 over-target trim: rotation > 15 -> remove worst excess ---
    # Worst = most phone failures, then highest VPS median latency,
    # then fewest VPS passes in 24h. Trim shares the round cap, never
    # replenishes (we are shrinking toward 15), never drops rotation
    # below 8. Phone reports no millisecond latency; VPS ms is the
    # documented approximation.
    trim_keys = []
    rotation_keys = [k for k in pool_keys if k not in pin_keys]
    rotation_after_fail = len(rotation_keys) - len(
        {k for _, k in candidates if k not in pin_keys})
    if rotation_after_fail > POOL_ROTATION_TARGET_MAX:
        excess = rotation_after_fail - POOL_ROTATION_TARGET_MAX
        remaining_cap = cap - len(candidates)
        max_trim_by_floor = rotation_after_fail - POOL_ROTATION_TARGET_MIN
        trim_budget = max(0, min(excess, remaining_cap, max_trim_by_floor))
        if trim_budget > 0:
            failure_set = {k for _, k in candidates}

            def _worst_rank(k):
                pk = decision["per_key"].get(key_id(k), {})
                pf = pk.get("phone_fail_count", 0)
                passes = pk.get("passes_24h", 0)
                ms = pk.get("latency_ms_median_24h")
                ms_val = ms if isinstance(ms, (int, float)) else 0
                # Worst first: most phone failures, then highest VPS
                # median latency, then fewest VPS passes in 24h.
                return (-pf, -ms_val, passes)

            trim_pool = [k for k in rotation_keys if k not in failure_set]
            # V2 guards: never trim a node with exactly 1 phone failure
            # (1st failure -> isolate only; it is awaiting the 2nd
            # failure to confirm), and never trim a node whose latest
            # phone failure is inside the 15-min independence window
            # (it may be a transient). Nodes with >=2 established
            # phone failures, and nodes with no phone failure at all
            # (slow on VPS), are eligible; the trim accelerates what
            # the failure path would do, it does not invent evidence.
            def _recent_phone_fail(k):
                reps = evidence.get("phone_failures", {}).get(k, [])
                if not reps:
                    return False
                return now - max(ts for ts, _ in reps) < PHONE_MIN_DELETE_GAP_S

            def _trim_eligible(k):
                pk = decision["per_key"].get(key_id(k), {})
                # Exactly 1 phone failure: awaiting the 2nd to confirm.
                if pk.get("phone_fail_count", 0) == 1:
                    return False
                return not _recent_phone_fail(k)

            trim_pool = [k for k in trim_pool if _trim_eligible(k)]
            trim_pool.sort(key=_worst_rank)
            for k in trim_pool[:trim_budget]:
                pk = decision["per_key"][key_id(k)]
                pk["verdict"] = "DELETE_OVER_TARGET"
                pk["path"] = "overtarget"
                # Sort key 10**9: failure deletes (for cause) sort first.
                candidates.append((10 ** 9, k))
                trim_keys.append(k)
    decision["trim_keys"] = [key_id(k) for k in trim_keys]
    # --- fail-closed: healthy remainder (F1) ---
    deletable = [k for _, k in sorted(candidates)]
    remaining = len(pool_keys) - min(len(deletable), cap)
    if deletable and (remaining < EXPECTED_PIN_COUNT or
                      remaining * 2 < len(pool_keys)):
        decision.update(action="HOLD_FAIL_CLOSED",
                        fail_closed_reason="no_healthy_pool_would_remain",
                        delete_keys=[], new_state=new_state)
        return decision
    if len(deletable) > cap:
        deletable = deletable[:cap]
    if deletable:
        trim_set = {k for k in trim_keys}
        decision.update(
            action="DELETE", delete_keys=deletable,
            failure_delete_keys=[k for k in deletable
                                 if k not in trim_set])
        # A deleted node is gone: drop it from the isolation lists and
        # state so the ledger and prune-state never claim it is both
        # deleted and isolated.
        delete_ids = {key_id(k) for k in deletable}
        decision["isolate_keys"] = [k for k in decision["isolate_keys"]
                                    if key_id(k) not in delete_ids]
        for kid in delete_ids:
            decision["new_state"].pop(kid, None)
    elif decision["isolate_keys"] or decision["recover_keys"]:
        decision.update(action="ISOLATE_ONLY")
    return decision


# ---------------------------------------------------------------------------
# Candidate construction + prune-aware admission (old gate untouched)
# ---------------------------------------------------------------------------

def apply_prune(current_bytes, delete_keys, replenish_lines=()):
    """Return candidate bytes: current minus deleted keys, plus
    replenishment lines appended. Non-proxy lines are kept verbatim."""
    by_key, _ = parse_pool(current_bytes)
    delete_set = {validate_key(k) for k in delete_keys}
    out_lines = []
    for raw_line in current_bytes.decode("utf-8").splitlines():
        if not raw_line.strip() or raw_line.lstrip().startswith("#"):
            out_lines.append(raw_line)
            continue
        _name, key = parse_surge_line(raw_line)
        if key in delete_set:
            continue
        out_lines.append(raw_line)
    for line in replenish_lines:
        _name, _key = parse_surge_line(line)
        out_lines.append(line)
    return ("\n".join(out_lines) + "\n").encode("utf-8")


def assess_candidate_with_prune(current, candidate, *, canonical_pin_names,
                                blocklisted_names, authorized_removed_keys,
                                authorized_added_keys, max_delete):
    """Admit a pruned candidate: EXACTLY the authorized removals.

    Does not modify or call ``assess_candidate``: the old gate still
    refuses every other removal. Pins must be present and byte-identical
    in both; blocked names must be absent; no line may be modified; added
    keys must be within the authorized addition set; removed keys must
    equal the authorized removal set exactly.
    """
    current_by_key, current_by_name = parse_pool(current)
    cand_by_key, cand_by_name = parse_pool(candidate)
    pins = set(canonical_pin_names)
    blocked = set(blocklisted_names)
    if len(pins) != EXPECTED_PIN_COUNT or len(set(pins)) != EXPECTED_PIN_COUNT:
        raise PruneRefused("canonical_pin_count_not_21")
    if pins & blocked:
        raise PruneRefused("blocked_pin_conflict")
    if not pins <= set(current_by_name):
        raise PruneRefused("missing_pins_in_current_pool")
    if not pins <= set(cand_by_name):
        raise PruneRefused("missing_pins_in_candidate")
    for n in pins:
        if current_by_key[current_by_name[n]]["line"] != \
                cand_by_key[cand_by_name[n]]["line"]:
            raise PruneRefused("pinned_definition_modified")
    if blocked & set(cand_by_name):
        raise PruneRefused("blocklisted_node_present")
    removed_keys = set(current_by_key) - set(cand_by_key)
    added_keys = set(cand_by_key) - set(current_by_key)
    authorized_removed = {validate_key(k) for k in authorized_removed_keys}
    authorized_added = {validate_key(k) for k in authorized_added_keys}
    if removed_keys != authorized_removed:
        raise PruneRefused("removal_set_not_exactly_authorized")
    if len(removed_keys) > max_delete:
        raise PruneRefused("delete_cap_exceeded")
    if not added_keys <= authorized_added:
        raise PruneRefused("unauthorized_addition")
    modified = [k for k in set(current_by_key) & set(cand_by_key)
                if current_by_key[k]["line"] != cand_by_key[k]["line"]]
    if modified:
        raise PruneRefused("existing_definition_changed")
    return {
        "decision": "PRUNE_ADMITTED",
        "candidate_count": len(cand_by_key),
        "pin_count": len(pins),
        "removed_count": len(removed_keys),
        "added_count": len(added_keys),
        "candidate_sha256": hashlib.sha256(candidate).hexdigest(),
        "identical_bytes": current == candidate,
        "production_delete_authorized": True,
    }


def build_replenishment(preview_addition_lines, deleted_count, country_fn,
                        max_per_country=MAX_REPLENISH_PER_COUNTRY):
    """Pick replenishment lines from the preview's safe_overlay additions.

    At most ``deleted_count`` lines, at most 2 per country, deterministic
    name order. Returns (lines, kept_count, dropped_count). Never invents
    a line: input lines must already be authorized safe_overlay output.
    """
    if deleted_count <= 0:
        return [], 0, len(preview_addition_lines)
    ordered = sorted(preview_addition_lines,
                     key=lambda ln: ln.split("=", 1)[0].strip())
    counts, kept = Counter(), []
    for line in ordered:
        if len(kept) >= deleted_count:
            break
        name = line.split("=", 1)[0].strip()
        country = (country_fn(name) or "unknown") if callable(country_fn) else "unknown"
        if counts[country] >= max_per_country:
            continue
        counts[country] += 1
        kept.append(line)
    return kept, len(kept), len(preview_addition_lines) - len(kept)


# ---------------------------------------------------------------------------
# Authorization, ledger, state, backups
# ---------------------------------------------------------------------------

def check_prune_authorization(env, marker_path):
    """All three must hold or prune mode is off (old path runs)."""
    if env.get("P2P3_ALLOW_AUTO_PRUNE") != "YES_EXPLICITLY":
        return {"enabled": False, "cap": 0, "replenish": False,
                "reason": "auto_prune_not_enabled"}
    try:
        cap = int(str(env.get("P2P3_AUTO_PRUNE_MAX_PER_ROUND", "")).strip())
    except (TypeError, ValueError):
        return {"enabled": False, "cap": 0, "replenish": False,
                "reason": "auto_prune_cap_invalid"}
    if not 1 <= cap <= MAX_DELETE_PER_ROUND:
        return {"enabled": False, "cap": 0, "replenish": False,
                "reason": "auto_prune_cap_out_of_range"}
    replenish = env.get("P2P3_AUTO_PRUNE_REPLENISH", "NO")
    if replenish not in ("YES", "NO"):
        return {"enabled": False, "cap": 0, "replenish": False,
                "reason": "auto_prune_replenish_invalid"}
    p = Path(marker_path)
    try:
        if (not p.is_absolute() or p.is_symlink() or not p.is_file()
                or p.stat().st_size > 128):
            return {"enabled": False, "cap": 0, "replenish": False,
                    "reason": "auto_prune_marker_missing"}
        if p.read_text(encoding="utf-8").strip() != PRUNE_MARKER_CONTENT:
            return {"enabled": False, "cap": 0, "replenish": False,
                    "reason": "auto_prune_marker_mismatch"}
    except OSError:
        return {"enabled": False, "cap": 0, "replenish": False,
                "reason": "auto_prune_marker_unreadable"}
    return {"enabled": True, "cap": cap,
            "replenish": replenish == "YES", "reason": "authorized"}


def load_prune_state(path):
    p = Path(path)
    if not p.exists():
        return {}
    try:
        data = json.loads(p.read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        raise PruneRefused("prune_state_unreadable") from exc
    if not isinstance(data, dict):
        raise PruneRefused("prune_state_malformed")
    for kid, rec in data.items():
        if not isinstance(rec, dict) or rec.get("state") != "ISOLATED":
            raise PruneRefused("prune_state_malformed")
    return data


def load_v2_meta(path):
    """V2 warmup flag. Missing/malformed means not warmed up (cap 4)."""
    p = Path(path)
    if not p.exists():
        return {"warmup_done": False}
    try:
        data = json.loads(p.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {"warmup_done": False}
    if not isinstance(data, dict):
        return {"warmup_done": False}
    return {"warmup_done": bool(data.get("warmup_done", False))}


def save_v2_meta_atomic(path, meta):
    p = Path(path)
    p.parent.mkdir(parents=True, exist_ok=True)
    tmp = p.with_name(p.name + ".tmp")
    tmp.write_text(json.dumps(meta, sort_keys=True, ensure_ascii=True),
                   encoding="utf-8")
    os.chmod(tmp, 0o600)
    os.replace(tmp, p)


def save_prune_state_atomic(path, state):
    p = Path(path)
    p.parent.mkdir(parents=True, exist_ok=True)
    tmp = p.with_name(p.name + ".tmp")
    tmp.write_text(json.dumps(state, sort_keys=True, ensure_ascii=True),
                   encoding="utf-8")
    os.chmod(tmp, 0o600)
    os.replace(tmp, p)


def append_ledger(path, record):
    """Append one desensitized JSON record (0600, no URIs, no lines)."""
    p = Path(path)
    p.parent.mkdir(parents=True, exist_ok=True)
    blob = (json.dumps(record, sort_keys=True, ensure_ascii=True) + "\n").encode("utf-8")
    fd = os.open(p, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
    try:
        os.write(fd, blob)
        os.fsync(fd)
    finally:
        os.close(fd)


def write_deletion_backup(backup_root, pre_bytes, evidence_records, now):
    """Keep pre-deletion pool bytes + evidence under a 0600 dir.

    ``evidence_records`` may contain the original pool line bytes for
    the deleted keys; this directory lives on the VPS only and is never
    copied to GitHub or into any report.
    """
    digest = hashlib.sha256(pre_bytes).hexdigest()[:8]
    dest = Path(backup_root) / ("%d-%s" % (int(now), digest))
    dest.mkdir(parents=True, exist_ok=True)
    os.chmod(dest, 0o700)
    (dest / "pool.before").write_bytes(pre_bytes)
    os.chmod(dest / "pool.before", 0o600)
    (dest / "evidence.json").write_text(
        json.dumps(evidence_records, sort_keys=True, ensure_ascii=True,
                   indent=2), encoding="utf-8")
    os.chmod(dest / "evidence.json", 0o600)
    return str(dest)


def preview_prune_decision(*, current_bytes, db_snapshot, db_path,
                           state_path, now):
    """Read-only: what prune WOULD do this cycle. No state/ledger writes.

    Used by --preview so the retest clock is never advanced by a dry run.
    Raises PruneRefused on integrity problems (reported, not published).
    """
    by_key, by_name = parse_pool(current_bytes)
    pins = {k for k, n in db_snapshot["db_pins"].items()
            if k not in db_snapshot["blocked_keys"]}
    blocked = set(db_snapshot["blocked_keys"])
    if len(pins) != EXPECTED_PIN_COUNT:
        raise PruneRefused("canonical_pin_count_not_21")
    prior_state = load_prune_state(state_path)
    evidence = read_failure_evidence(db_path, set(by_key), now)
    # V2 warmup: first V2 deletion round caps at 4, then 8.
    meta_path = Path(state_path).with_name("prune-v2-meta.json")
    warmup_done = load_v2_meta(meta_path).get("warmup_done", False)
    effective_cap = min(MAX_DELETE_PER_ROUND,
                        V2_STABLE_CAP if warmup_done else V2_WARMUP_CAP)
    decision = decide(evidence, by_key=by_key, by_name=by_name,
                      pins=pins, blocked=blocked,
                      prior_state=prior_state, cap=effective_cap,
                      now=now)
    return {"action": decision["action"],
            "would_delete": [key_id(k) for k in decision["delete_keys"]],
            "would_isolate": [key_id(k) for k in decision["isolate_keys"]],
            "fail_closed_reason": decision["fail_closed_reason"],
            "per_key": decision["per_key"]}


# ---------------------------------------------------------------------------
# One-cycle overlay: called by production_cycle AFTER build_preview
# ---------------------------------------------------------------------------

def prune_overlay(*, current_bytes, preview_bytes, db_snapshot, db_path,
                  state_path, ledger_path, backup_root, cap, replenish,
                  country_fn, now, parse_fn=None):
    """Compute the pruned candidate for this cycle.

    Returns a dict: action NO_PRUNE | DELETE | ISOLATE_ONLY |
    HOLD_FAIL_CLOSED, plus candidate_bytes when a publish should proceed
    with the pruned candidate. Raises PruneRefused only for integrity
    problems that must HOLD the cycle (the caller converts that to a
    HOLD decision, never to a deletion).
    """
    by_key, by_name = parse_pool(current_bytes)
    pins = {k: n for k, n in db_snapshot["db_pins"].items()
            if k not in db_snapshot["blocked_keys"]}
    blocked = set(db_snapshot["blocked_keys"])
    if len(pins) != EXPECTED_PIN_COUNT:
        raise PruneRefused("canonical_pin_count_not_21")
    prior_state = load_prune_state(state_path)
    evidence = read_failure_evidence(db_path, set(by_key), now)
    # V2 warmup: first V2 deletion round caps at 4, then 8.
    meta_path = Path(state_path).with_name("prune-v2-meta.json")
    warmup_done = load_v2_meta(meta_path).get("warmup_done", False)
    effective_cap = min(cap, V2_STABLE_CAP if warmup_done else V2_WARMUP_CAP)
    decision = decide(evidence, by_key=by_key, by_name=by_name,
                      pins=set(pins), blocked=blocked,
                      prior_state=prior_state, cap=effective_cap, now=now)
    # Persist isolation state + ledger every prune-enabled cycle, even
    # when nothing is deleted: the retest clock depends on it.
    save_prune_state_atomic(state_path, decision["new_state"])
    ledger_record = {
        "ts": int(now), "action": decision["action"],
        "fail_closed_reason": decision["fail_closed_reason"],
        "delete_keys": [key_id(k) for k in decision["delete_keys"]],
        "isolate_keys": [key_id(k) for k in decision["isolate_keys"]],
        "recover_keys": [key_id(k) for k in decision["recover_keys"]],
        "pool_count": len(by_key), "cap": effective_cap,
        "v2": True, "warmup_done": warmup_done,
        "trim_keys": decision.get("trim_keys", []),
        "per_key": decision["per_key"],
    }
    append_ledger(ledger_path, ledger_record)
    if decision["action"] == "HOLD_FAIL_CLOSED":
        raise PruneRefused(decision["fail_closed_reason"] or "fail_closed")
    if decision["action"] != "DELETE":
        return {"action": decision["action"],
                "candidate_bytes": None, "decision": decision,
                "evidence": evidence}
    # Replenishment: only from the preview's safe_overlay additions.
    preview_by_key, _ = parse_pool(preview_bytes)
    addition_lines = [preview_by_key[k]["line"] for k in preview_by_key
                      if k not in by_key]
    repl_lines, kept, dropped = ([], 0, len(addition_lines))
    if replenish:
        # V2: only failure-based deletions are backfilled; over-target
        # trims shrink the pool toward 15 and are NOT replenished.
        repl_lines, kept, dropped = build_replenishment(
            addition_lines,
            len(decision.get("failure_delete_keys",
                             decision["delete_keys"])), country_fn)
    candidate = apply_prune(current_bytes, decision["delete_keys"], repl_lines)
    added_keys = []
    for line in repl_lines:
        _name, k = parse_surge_line(line)
        added_keys.append(k)
    admission = assess_candidate_with_prune(
        current_bytes, candidate,
        canonical_pin_names=[pins[k] for k in sorted(pins)],
        blocklisted_names=[by_key[k]["name"] for k in blocked
                           if k in by_key] +
                          [n for k, n in db_snapshot["db_pins"].items()
                           if k in blocked],
        authorized_removed_keys=decision["delete_keys"],
        authorized_added_keys=added_keys,
        max_delete=cap)
    # Backup BEFORE the publish attempt (publish keeps its own too).
    ev_records = []
    for k in decision["delete_keys"]:
        pk = decision["per_key"][key_id(k)]
        ev_records.append({
            "key": key_id(k), "name": by_key[k]["name"],
            "path": pk.get("path", "vps"),
            "verdict": pk.get("verdict"),
            "fail_buckets": pk["fail_buckets"],
            "passes_24h": pk["passes_24h"],
            "latency_ms_median_24h": pk.get("latency_ms_median_24h"),
            "retest_at": pk.get("retest_at"),
            "first_fail_ts": pk.get("first_fail_ts"),
            "phone_fail_buckets": pk.get("phone_fail_buckets", []),
            "phone_fail_count": pk.get("phone_fail_count", 0),
            "phone_first_fail_ts": pk.get("phone_first_fail_ts"),
            "original_line": by_key[k]["line"],
            "deleted_at": int(now)})
    backup_dir = write_deletion_backup(backup_root, current_bytes,
                                       ev_records, now)
    return {"action": "DELETE", "candidate_bytes": candidate,
            "decision": decision, "evidence": evidence,
            "admission": admission, "backup_dir": backup_dir,
            "replenished": kept, "replenish_dropped": dropped}


def confirm_prune_publish(*, ledger_path, delete_keys, now, published,
                          candidate_sha=None, fail_reason=None):
    """Append the publish outcome so a failed publish is never recorded
    as a deletion. On success the deleted keys leave ISOLATED state."""
    append_ledger(ledger_path, {
        "ts": int(now),
        "action": "PRUNE_PUBLISHED" if published else "PRUNE_PUBLISH_FAILED",
        "delete_keys": [key_id(k) for k in delete_keys],
        "candidate_sha256": candidate_sha,
        "fail_reason": fail_reason,
        "v2": True,
    })
    # V2 warmup: the first successfully published V2 deletion round
    # lifts the cap from 4 to 8 for subsequent rounds.
    if published and delete_keys:
        try:
            meta_path = Path(ledger_path).parent / "prune-v2-meta.json"
            save_v2_meta_atomic(meta_path, {"warmup_done": True})
        except OSError:
            pass

# ---------------------------------------------------------------------------
# Owner-allowlist controlled removal (Issue #73 comment 7062123606 / GPT-6)
# ---------------------------------------------------------------------------
# Narrow one-shot path: deletes ONLY the identity keys listed in an explicit
# owner allowlist file, each re-verified fresh against the staging phone
# observations at execution time. It NEVER enables global auto-prune, NEVER
# touches a pin, NEVER deletes on display-name match, and NEVER lets the
# pool drop below ALLOWLIST_POOL_FLOOR_TOTAL (22: receiver.py::parse_pool
# and the phone probe both refuse pools shorter than 22).
# Evidence binds to (protocol, host, port) + observation nonce + pool_sha:
# a new node that reuses a display name inherits no failure record, and a
# failure observed under one pool SHA is never applied to a different
# identity. A trusted phone SUCCESS for the same key at any time vetoes.
# All 15 keys here were already ISOLATED by the V2 phone path (1st
# failure); the allowlist admits the 2nd independent failure after
# isolation as the delete trigger, under the explicit owner decision,
# instead of flipping the global P2P3_ALLOW_AUTO_PRUNE switch.

ALLOWLIST_DECISION_REF = "zsh199410/kanyu-app#73:7062123606"
ALLOWLIST_POOL_FLOOR_TOTAL = 22
ALLOWLIST_MAX_ENTRIES = 15
_HEX = set("0123456789abcdef")


def _is_hex(s, n):
    return (isinstance(s, str) and len(s) == n
            and all(c in _HEX for c in s))


def load_allowlist(path):
    """Load + validate an owner allowlist file (0600, absolute, no symlink).

    File JSON: {"decision_ref": ALLOWLIST_DECISION_REF,
                "pool_sha": "<64 hex, the SHA the failures were observed under>",
                "entries": [{"key": [proto, host, port], "name": "...",
                             "nonce": "<32 hex>", "received_at": <epoch int>}]}
    Raises PruneRefused on any defect: no partial allowlist is ever used.
    """
    p = Path(path)
    if (not p.is_absolute() or p.is_symlink() or not p.is_file()
            or p.stat().st_size > 65536):
        raise PruneRefused("allowlist_file_invalid")
    try:
        if p.stat().st_mode & 0o077:
            raise PruneRefused("allowlist_file_permissions")
    except OSError as exc:
        raise PruneRefused("allowlist_file_invalid") from exc
    try:
        data = json.loads(p.read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        raise PruneRefused("allowlist_unreadable") from exc
    if not isinstance(data, dict):
        raise PruneRefused("allowlist_malformed")
    if data.get("decision_ref") != ALLOWLIST_DECISION_REF:
        raise PruneRefused("allowlist_decision_ref_mismatch")
    pool_sha = data.get("pool_sha")
    if not _is_hex(pool_sha, 64):
        raise PruneRefused("allowlist_pool_sha_invalid")
    entries = data.get("entries")
    if (not isinstance(entries, list)
            or not 1 <= len(entries) <= ALLOWLIST_MAX_ENTRIES):
        raise PruneRefused("allowlist_entry_count_invalid")
    out = []
    for e in entries:
        if not isinstance(e, dict):
            raise PruneRefused("allowlist_entry_malformed")
        key = validate_key(e.get("key"))
        nonce = e.get("nonce")
        if not _is_hex(nonce, 32):
            raise PruneRefused("allowlist_nonce_invalid")
        ts = e.get("received_at")
        if type(ts) is not int or isinstance(ts, bool):
            raise PruneRefused("allowlist_timestamp_invalid")
        if any(k == key for k, _, _ in out):
            raise PruneRefused("allowlist_duplicate_key")
        out.append((key, nonce, ts))
    return {"decision_ref": ALLOWLIST_DECISION_REF,
            "pool_sha": pool_sha, "entries": out}


def _staging_phone_check(staging_conn, key, nonce, received_at, pool_sha):
    """Re-verify ONE failure row in staging + veto on any trusted success."""
    rows = staging_conn.execute(
        "SELECT received_at, status, trusted, control_verified, bearer, "
        "pool_sha, reason, probe_mode FROM phone_observations "
        "WHERE protocol=? AND host=? AND port=? AND nonce=?",
        (key[0], key[1], key[2], nonce)).fetchall()
    if len(rows) != 1:
        raise PruneRefused("allowlist_evidence_not_unique")
    (ts, status, trusted, control, bearer, psha, reason, mode) = rows[0]
    if ts != received_at:
        raise PruneRefused("allowlist_evidence_time_mismatch")
    if (status != "failure" or trusted != 1 or control != 1
            or bearer != "cellular" or psha != pool_sha
            or reason != "dual_transport_failure"
            or mode != "external_policy_id"):
        raise PruneRefused("allowlist_evidence_criteria_mismatch")
    succ = staging_conn.execute(
        "SELECT COUNT(*) FROM phone_observations WHERE protocol=? AND host=? "
        "AND port=? AND status='success' AND trusted=1",
        (key[0], key[1], key[2])).fetchone()[0]
    if succ:
        raise PruneRefused("allowlist_phone_success_veto")
    return ts


def verify_allowlist(*, staging_db_path, db_path, allowlist, current_keys,
                     pins, blocked, prior_state, now):
    """Verify every allowlisted key fresh. Any failure refuses the whole round."""
    by_key = set(current_keys)
    evidence = read_failure_evidence(db_path, by_key, now)
    staging = _sqlite_readonly(staging_db_path)
    verified = []
    per_key = {}
    try:
        for key, nonce, received_at in allowlist["entries"]:
            if key not in by_key:
                raise PruneRefused("allowlist_key_not_in_pool")
            if key in pins:
                raise PruneRefused("allowlist_key_is_pinned")
            if key in blocked:
                raise PruneRefused("allowlist_key_blocked")
            prior = prior_state.get(key_id(key))
            if not prior or prior.get("state") != "ISOLATED":
                raise PruneRefused("allowlist_not_previously_isolated")
            isolated_at = prior.get("isolated_at", now)
            if (not isinstance(isolated_at, (int, float))
                    or received_at <= isolated_at):
                raise PruneRefused("allowlist_failure_not_after_isolation")
            _staging_phone_check(staging, key, nonce, received_at,
                                 allowlist["pool_sha"])
            reports = evidence.get("phone_failures", {}).get(key, [])
            imported = [ts for ts, src in reports
                        if ts == received_at and src == "surge-url-test"]
            if not imported:
                raise PruneRefused("allowlist_failure_not_imported")
            first_fail_ts = min(ts for ts, _ in reports)
            if received_at - first_fail_ts < PHONE_MIN_DELETE_GAP_S:
                raise PruneRefused("allowlist_second_failure_gap_short")
            verified.append(key)
            per_key[key_id(key)] = {
                "verdict": "ALLOWLIST_DELETE", "path": "phone",
                "phone_fail_count": len(reports),
                "phone_fail_buckets": sorted({int(ts) // 3600
                                              for ts, _ in reports}),
                "phone_first_fail_ts": first_fail_ts,
                "retest_ts": received_at, "first_fail_ts": first_fail_ts,
                "nonce": nonce,
                "pool_sha_prefix": allowlist["pool_sha"][:12],
                "isolated_at": isolated_at,
            }
    finally:
        try:
            staging.rollback()
        finally:
            staging.close()
    return verified, per_key


def allowlist_overlay(*, current_bytes, db_snapshot, staging_db_path, db_path,
                      allowlist, state_path, ledger_path, backup_root, cap,
                      now, commit=True):
    """Build the allowlist pruned candidate (mirror of prune_overlay).

    commit=False is a dry run: verifies + computes the candidate and
    admission, writes no backup, ledger or state. commit=True persists
    backup + ledger + prunes the deleted keys out of the isolation state.
    Raises PruneRefused (fail-closed, no deletion) on any integrity issue.
    """
    by_key, by_name = parse_pool(current_bytes)
    pins = {k: n for k, n in db_snapshot["db_pins"].items()
            if k not in db_snapshot["blocked_keys"]}
    blocked = set(db_snapshot["blocked_keys"])
    if len(pins) != EXPECTED_PIN_COUNT:
        raise PruneRefused("canonical_pin_count_not_21")
    if blocked & set(by_key):
        raise PruneRefused("blocked_key_in_pool")
    prior_state = load_prune_state(state_path)
    verified, per_key = verify_allowlist(
        staging_db_path=staging_db_path, db_path=db_path, allowlist=allowlist,
        current_keys=set(by_key), pins=set(pins), blocked=blocked,
        prior_state=prior_state, now=now)
    if len(verified) > cap:
        raise PruneRefused("allowlist_cap_exceeded")
    if len(by_key) - len(verified) < ALLOWLIST_POOL_FLOOR_TOTAL:
        raise PruneRefused("allowlist_pool_floor_22")
    candidate = apply_prune(current_bytes, verified)
    admission = assess_candidate_with_prune(
        current_bytes, candidate,
        canonical_pin_names=[pins[k] for k in sorted(pins)],
        blocklisted_names=[by_key[k]["name"] for k in blocked if k in by_key] +
                          [n for k, n in db_snapshot["db_pins"].items()
                           if k in blocked],
        authorized_removed_keys=verified, authorized_added_keys=[],
        max_delete=cap)
    gone = {key_id(k) for k in verified}
    decision = {"action": "DELETE", "delete_keys": verified, "isolate_keys": [],
                "recover_keys": [], "fail_closed_reason": None,
                "per_key": per_key,
                "new_state": {k: v for k, v in prior_state.items()
                              if k not in gone},
                "allowlist_decision_ref": ALLOWLIST_DECISION_REF}
    backup_dir = None
    if commit:
        ev_records = []
        for k in verified:
            pk = per_key[key_id(k)]
            ev_records.append({
                "key": key_id(k), "name": by_key[k]["name"], "path": "phone",
                "verdict": "ALLOWLIST_DELETE",
                "decision_ref": ALLOWLIST_DECISION_REF,
                "nonce": pk["nonce"], "pool_sha_prefix": pk["pool_sha_prefix"],
                "phone_fail_buckets": pk["phone_fail_buckets"],
                "phone_fail_count": pk["phone_fail_count"],
                "phone_first_fail_ts": pk["phone_first_fail_ts"],
                "retest_ts": pk["retest_ts"],
                "first_fail_ts": pk["first_fail_ts"],
                "isolated_at": pk["isolated_at"],
                "original_line": by_key[k]["line"],
                "deleted_at": int(now)})
        backup_dir = write_deletion_backup(backup_root, current_bytes,
                                           ev_records, now)
        append_ledger(ledger_path, {
            "ts": int(now), "action": "ALLOWLIST_DELETE",
            "decision_ref": ALLOWLIST_DECISION_REF,
            "delete_keys": [key_id(k) for k in verified],
            "pool_count": len(by_key), "cap": cap,
            "pool_floor_total": ALLOWLIST_POOL_FLOOR_TOTAL,
            "candidate_sha256": hashlib.sha256(candidate).hexdigest(),
            "backup_dir": backup_dir, "per_key": per_key})
        save_prune_state_atomic(state_path, decision["new_state"])
    return {"action": "DELETE", "candidate_bytes": candidate,
            "decision": decision, "admission": admission,
            "backup_dir": backup_dir}
