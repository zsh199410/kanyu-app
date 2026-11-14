"""D1 dual gate for Issue #73 (GPT decision 6875033415, items 1 + 4).

The publish allowlist's SOLE criterion is the latest same-version phone
NATIVE test: success AND < 300 ms, with no subsequent native failure.
P0 (the probe-service HTTP probe) is ONLY a pre-screen / health signal:
it never admits and never rejects on its own.

Rules (GPT 6875033415 item 1):
  - For each fingerprint, take its LATEST native result among runs whose
    version_sha == the source_version_sha being published ("latest SAME
    version"). A fingerprint with no same-version evidence is REJECTED
    (fail closed). A pass measured on a different version does not admit
    this version.
  - That same-version result must be success == True with ms < 300.
    P0 < 280 but native failed / slow MUST be rejected: that is exactly
    what this rule does (native decides; P0 cannot rescue).
  - "No subsequent native failure": if ANY LATER run (any version,
    tested_at after the same-version pass) records a failure or a
    >= threshold result for the fingerprint, the pass is void and the
    fingerprint is REJECTED. A later pass on another version does NOT
    void it (it only confirms the node); only a later failure does.
  - The same-version pass must be fresh: sane ts (0 < ts <= now, ANY
    future ts rejected outright, mirroring the D0 strict timestamp
    rule) and within NATIVE_TTL_SECONDS (default 24 h) of now.
  - Native pass but P0 latest in (280, 297] is a CONDITIONAL candidate:
    admitted, but flagged "conditional" in the diagnostics so a reviewer
    can see the P0/native disagreement. P0 latest failed is flagged as a
    health warning only; it does not reject (P0 is not the criterion).

A fingerprint with no native evidence at all (never natively tested, or
only tested on a different version) is REJECTED (fail closed).

Native record format (native_results.json, format "native-results-v1"):
  {"format": "native-results-v1",
   "runs": [{"version_sha": "<sha256 of the subscription version tested>",
             "tested_at": <unix ts>, "tested_at_cst": "...",
             "network": "5G cellular pdp_ip0, no Wi-Fi",
             "surge": "6.100.0 build 4025",
             "results": [{"fingerprint": "<32 hex>",
                          "name": "<display name>",
                          "success": true/false,
                          "ms": <int ms or null>}]}]}
  Runs are ordered oldest-first; the gate takes the newest run per
  fingerprint (by tested_at, ties broken by list order, later wins).

Diagnostics use fingerprint prefixes (first 12 hex) and counts only.
No passwords, URIs, tokens, or subscription URLs are ever output.
"""

import json
import os
import sqlite3
import time

from .phone_gate import gate_lines as _gate_lines  # noqa: F401  (re-export)

NATIVE_THRESHOLD_MS = 300
NATIVE_TTL_SECONDS = 24 * 3600
# P0 conditional band (GPT 6875033415 item 1): native pass but P0 latest
# second_ms in (280, 297] is a conditional candidate, admitted + flagged.
P0_CONDITIONAL_LOW_MS = 280
P0_CONDITIONAL_HIGH_MS = 297


def load_native_record(record_path):
    """Load a native-results-v1 record. Returns (record, error).

    error is None on success, else a short machine-readable string.
    The record is untrusted input: malformed JSON, wrong format, missing
    runs, or per-result shape errors all fail closed (error set).
    """
    if not os.path.exists(record_path):
        return None, "native_record_missing"
    try:
        with open(record_path, encoding="utf-8") as f:
            record = json.load(f)
    except (OSError, ValueError):
        return None, "native_record_unreadable"
    if not isinstance(record, dict) or record.get("format") != "native-results-v1":
        return None, "native_record_bad_format"
    runs = record.get("runs")
    if not isinstance(runs, list):
        return None, "native_record_no_runs"
    for run in runs:
        if not isinstance(run, dict):
            return None, "native_record_bad_run"
        if not isinstance(run.get("version_sha"), str) or not run.get("version_sha"):
            return None, "native_record_bad_run"
        if not isinstance(run.get("tested_at"), int):
            return None, "native_record_bad_run"
        if not isinstance(run.get("results"), list):
            return None, "native_record_bad_run"
        for r in run["results"]:
            if not isinstance(r, dict):
                return None, "native_record_bad_result"
            if not isinstance(r.get("fingerprint"), str) or len(r["fingerprint"]) != 32:
                return None, "native_record_bad_result"
            if not isinstance(r.get("success"), bool):
                return None, "native_record_bad_result"
            ms = r.get("ms")
            if ms is not None and not isinstance(ms, int):
                return None, "native_record_bad_result"
    return record, None


def latest_native_by_fp(record):
    """Newest native result per fingerprint, across ALL runs.

    Returns {fp: (run, result)} where run is the newest run (by
    tested_at, ties: later in the list wins) containing a result for fp.
    Used by the subsequent-failure check (any later run, any version).
    """
    latest = {}
    for run in record.get("runs", []):
        for r in run.get("results", []):
            fp = r["fingerprint"]
            prev = latest.get(fp)
            if prev is None:
                latest[fp] = (run, r)
                continue
            prev_run = prev[0]
            if run["tested_at"] >= prev_run["tested_at"]:
                latest[fp] = (run, r)
    return latest


def latest_same_version_by_fp(record, source_version_sha):
    """Newest native result per fingerprint among runs for ONE version.

    Returns {fp: (run, result)} restricted to runs whose version_sha ==
    source_version_sha. A fingerprint absent here has no same-version
    native evidence and must be rejected.
    """
    latest = {}
    for run in record.get("runs", []):
        if run.get("version_sha") != source_version_sha:
            continue
        for r in run.get("results", []):
            fp = r["fingerprint"]
            prev = latest.get(fp)
            if prev is None:
                latest[fp] = (run, r)
                continue
            prev_run = prev[0]
            if run["tested_at"] >= prev_run["tested_at"]:
                latest[fp] = (run, r)
    return latest


def has_subsequent_native_failure(record, fingerprint, after_ts,
                                  threshold_ms=NATIVE_THRESHOLD_MS):
    """True when any run LATER than after_ts records a failure (or a
    >= threshold result) for the fingerprint. A later pass does not
    count; only a later failure voids an earlier pass."""
    for run in record.get("runs", []):
        if run.get("tested_at", 0) <= after_ts:
            continue
        for r in run.get("results", []):
            if r.get("fingerprint") != fingerprint:
                continue
            if not r.get("success"):
                return True
            ms = r.get("ms")
            if ms is None or ms >= threshold_ms:
                return True
    return False


def load_p0_health(probe_db_path):
    """Read-only P0 health signal: {fp: latest report dict}.

    Returns {} when the DB is absent/unreadable (health signal is
    optional; its absence never blocks the gate, it only removes the
    conditional/warning flags). Mirrors D0 phone_gate's most-recent
    report selection (ORDER BY ts DESC, id DESC).
    """
    health = {}
    if not probe_db_path or not os.path.exists(probe_db_path):
        return health
    uri = "file:" + probe_db_path + "?mode=ro"
    try:
        conn = sqlite3.connect(uri, uri=True, timeout=30)
    except sqlite3.Error:
        return health
    try:
        rows = conn.execute(
            "SELECT fingerprint, state FROM probe_nodes").fetchall()
        for fingerprint, state in rows:
            row = conn.execute(
                """SELECT ts, success, second_ms, second_status, interface
                   FROM probe_reports WHERE fingerprint=?
                   ORDER BY ts DESC, id DESC LIMIT 1""",
                (fingerprint,)).fetchone()
            if row is None:
                continue
            ts, success, second_ms, second_status, interface = row
            health[fingerprint] = {
                "state": state, "ts": ts, "success": bool(success),
                "second_ms": second_ms, "second_status": second_status,
                "interface": interface,
            }
    except sqlite3.Error:
        return {}
    finally:
        conn.close()
    return health


def load_native_allowlist(record_path, source_version_sha,
                          probe_db=None,
                          threshold_ms=NATIVE_THRESHOLD_MS,
                          ttl_seconds=NATIVE_TTL_SECONDS, now=None):
    """Return (admitted_fps, conditional_fps, diag).

    admitted_fps: set of 32-hex fingerprints admitted by the dual gate.
    conditional_fps: subset admitted with a P0 disagreement flag
        (native pass, P0 latest second_ms in (280, 297]).
    diag: counts, per-fingerprint rejection reasons (prefix-keyed), and
        P0 health warnings. No secrets, no URIs.
    """
    now = int(now if now is not None else time.time())
    diag = {
        "threshold_ms": threshold_ms,
        "ttl_seconds": ttl_seconds,
        "checked_at": now,
        "source_version_sha_prefix": (source_version_sha or "")[:12],
        "native_record": os.path.basename(record_path),
        "total_fingerprints": 0,
        "admitted": 0,
        "conditional": 0,
        "rejected": 0,
        "reasons": {},
        "rejected_prefixes": {},
        "conditional_prefixes": {},
        "p0_warnings": {},
    }
    admitted = set()
    conditional = set()
    record, error = load_native_record(record_path)
    if error is not None:
        diag["error"] = error
        return admitted, conditional, diag
    health = load_p0_health(probe_db)
    latest = latest_native_by_fp(record)
    diag["total_fingerprints"] = len(latest)
    # Admission is decided per fingerprint from its latest SAME-VERSION
    # result; a later failure in ANY run voids the pass.
    same_version = latest_same_version_by_fp(record, source_version_sha)
    for fingerprint, (run, result) in sorted(latest.items()):
        prefix = fingerprint[:12]
        sv = same_version.get(fingerprint)
        if sv is None:
            # No native evidence for THIS version at all.
            diag["rejected"] += 1
            diag["reasons"]["native_version_mismatch"] = diag["reasons"].get(
                "native_version_mismatch", 0) + 1
            diag["rejected_prefixes"][prefix] = "native_version_mismatch"
            continue
        run, result = sv
        tested_at = run["tested_at"]
        if not result["success"]:
            diag["rejected"] += 1
            diag["reasons"]["latest_native_failed"] = diag["reasons"].get(
                "latest_native_failed", 0) + 1
            diag["rejected_prefixes"][prefix] = "latest_native_failed"
            continue
        ms = result.get("ms")
        if ms is None or ms >= threshold_ms:
            diag["rejected"] += 1
            diag["reasons"]["latest_native_slow_or_missing_ms"] = diag["reasons"].get(
                "latest_native_slow_or_missing_ms", 0) + 1
            diag["rejected_prefixes"][prefix] = "latest_native_ms=%s" % (ms,)
            continue
        # "No subsequent native failure": any later run (any version)
        # failing this fingerprint voids the same-version pass.
        if has_subsequent_native_failure(record, fingerprint, tested_at,
                                         threshold_ms):
            diag["rejected"] += 1
            diag["reasons"]["subsequent_native_failed"] = diag["reasons"].get(
                "subsequent_native_failed", 0) + 1
            diag["rejected_prefixes"][prefix] = "subsequent_native_failed"
            continue
        # Timestamp sanity, STRICT (mirrors D0 phone_gate): 0 < ts <= now.
        if tested_at is None or tested_at <= 0 or tested_at > now:
            diag["rejected"] += 1
            diag["reasons"]["native_ts_invalid"] = diag["reasons"].get(
                "native_ts_invalid", 0) + 1
            diag["rejected_prefixes"][prefix] = "native_ts_invalid"
            continue
        if now - tested_at > ttl_seconds:
            diag["rejected"] += 1
            diag["reasons"]["native_stale"] = diag["reasons"].get(
                "native_stale", 0) + 1
            diag["rejected_prefixes"][prefix] = "native_age_s=%s" % (now - tested_at,)
            continue
        admitted.add(fingerprint)
        diag["admitted"] += 1
        # P0 health signal only: flag, never admit/reject.
        p0 = health.get(fingerprint)
        if p0 is not None:
            p0_ms = p0.get("second_ms")
            if p0_ms is not None and P0_CONDITIONAL_LOW_MS < p0_ms <= P0_CONDITIONAL_HIGH_MS:
                conditional.add(fingerprint)
                diag["conditional"] += 1
                diag["conditional_prefixes"][prefix] = "native_ms=%s p0_ms=%s" % (ms, p0_ms)
            if not p0.get("success"):
                diag["p0_warnings"][prefix] = "p0_latest_failed_health_only"
    return admitted, conditional, diag


def gate_lines(lines, admitted_fps):
    """Filter candidate subscription lines through the admitted set.

    Re-exports D0 phone_gate.gate_lines (same fingerprint algorithm,
    unparsable lines and non-whitelisted protocols dropped fail-closed).
    """
    return _gate_lines(lines, admitted_fps)
