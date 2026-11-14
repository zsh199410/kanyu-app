"""Phone gate for Issue #73 P2-P3 D0 (isolated implementation).

Decides which subscription lines are CURRENTLY phone-verified, using only
the P0 probe database, opened READ-ONLY. Never touches production files.

A fingerprint is admitted ONLY if its MOST RECENT probe report satisfies ALL:
  - success == 1
  - second_ms is not None and second_ms <= threshold_ms (default 280; this is
    a calibration margin, NOT an official standard and NOT a guarantee that
    the native Surge speed test will be < 300 ms)
  - second_status == 204 (the generate_204 probe URL returned 204)
  - interface starts with 'pdp_ip' (Chongqing Mobile cellular interface)
  - ts within TTL_SECONDS (default 24 h) of now, and ts sane
    (0 < ts <= now; ANY future ts is rejected outright -- no clock-skew
    allowance. GPT second review item 1, 2026-11-14: the old +600 s
    allowance mirrored P0 ingest, but the gate has no server-side
    receive-time to double-check against, so any future ts is
    untrustworthy and fails closed.)
  - the probe_nodes row for the fingerprint exists and its state is
    'verified' (cross-check; a mismatch fails closed for that fingerprint)

Rationale (GPT review, Issue #73 comment 6855262036, item 1):
  The stored 'verified' state alone is NOT proof of "currently < 300 ms on
  the phone". The gate must re-derive admission from the most recent report:
  if the most recent record is a failure or >= threshold, the fingerprint is
  rejected even if an older success exists. The stored state is only a
  consistency cross-check.

Any fingerprint whose mapping is unclear (no probe_nodes row, no reports,
unparsable line, protocol not in the whitelist) is REJECTED (fail closed).

All diagnostics use fingerprint prefixes (first 12 hex chars) and counts
only. No passwords, URIs, tokens, or subscription URLs are ever output.
"""

import hashlib
import os
import sqlite3
import time

# Tunables. threshold_ms=280 is the D0 calibration margin from the #73 plan;
# it is NOT an official standard and does NOT guarantee native < 300 ms.
DEFAULT_THRESHOLD_MS = 280
DEFAULT_TTL_SECONDS = 24 * 3600
# Timestamp rule (GPT second review item 1, 2026-11-14): STRICT.
# A report timestamp must satisfy 0 < ts <= now. ANY future ts is
# rejected outright -- there is NO clock-skew allowance. The old
# +600 s allowance mirrored P0 ingest, but the gate reads the DB
# directly and has no server-side receive-time to double-check a
# future ts against, so a future ts is untrustworthy by definition.
# If a skew allowance is ever needed again, it MUST come with a
# server-side receive-time double check and the reason written here;
# the default is no allowance.
# The probe URL is fixed in the phone probe script (generate_204). A 204
# status on the second request is the observable proof that the expected
# probe URL was used and answered.
EXPECTED_SECOND_STATUS = 204
CELLULAR_INTERFACE_PREFIX = "pdp_ip"
ALLOWED_PROTOCOLS = ("trojan", "vmess", "ss")


def fingerprint_of(proto, host, port, params):
    """IDENTICAL to /opt/probe-service/probe_service.py fingerprint_of.

    Stable identity from connection params, NOT the display name.
    params: dict of lower-cased keys -> raw values.
    """
    parts = [proto.lower(), host.lower().strip("[]"), str(int(port))]
    for k in sorted(params):
        parts.append(f"{k.lower()}={params[k]}")
    raw = "|".join(parts)
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()[:32]


def parse_surge_line(line):
    """IDENTICAL to /opt/probe-service/probe_service.py parse_surge_line.

    Returns (name, proto, host, port, params) or None.
    params: dict of lower-cased keys -> stripped values.
    """
    try:
        if " = " not in line:
            return None
        name, rest = line.split(" = ", 1)
        parts = [p.strip() for p in rest.split(",")]
        if len(parts) < 3:
            return None
        proto = parts[0].strip().lower()
        host = parts[1].strip().strip("[]").lower()
        port = int(parts[2].strip())
        params = {}
        for p in parts[3:]:
            if "=" in p:
                k, v = p.split("=", 1)
                params[k.strip().lower()] = v.strip()
        if proto not in ALLOWED_PROTOCOLS:
            return None
        if not host or port <= 0:
            return None
        return (name.strip(), proto, host, port, params)
    except Exception:
        return None


def _most_recent_report(conn, fingerprint):
    """Return the most recent probe report row for a fingerprint, or None.

    Row: (ts, success, second_ms, second_status, interface, error).
    Deterministic tie-break: ORDER BY ts DESC, id DESC. id is
    INTEGER PRIMARY KEY AUTOINCREMENT in probe_reports, so a larger id
    is always a later insertion. The production table also has
    UNIQUE(fingerprint, ts), so same-ts duplicates cannot occur there;
    the id tie-break is a defensive determinism guarantee (it also
    covers any future schema/import path that drops the UNIQUE bound).
    """
    row = conn.execute(
        """SELECT ts, success, second_ms, second_status, interface, error
           FROM probe_reports WHERE fingerprint=? ORDER BY ts DESC, id DESC LIMIT 1""",
        (fingerprint,),
    ).fetchone()
    return row


def load_verified(probe_db_path, threshold_ms=DEFAULT_THRESHOLD_MS,
                  ttl_seconds=DEFAULT_TTL_SECONDS, now=None):
    """Return (admitted_fps, diag).

    admitted_fps: set of 32-hex fingerprints admitted by the gate.
    diag: dict with counts and per-fingerprint rejection reasons, keyed by
    fingerprint prefix (first 12 hex). No secrets, no URIs.
    """
    now = int(now if now is not None else time.time())
    diag = {
        "threshold_ms": threshold_ms,
        "ttl_seconds": ttl_seconds,
        "checked_at": now,
        "probe_db": os.path.basename(probe_db_path),
        "total_nodes": 0,
        "admitted": 0,
        "rejected": 0,
        "reasons": {},
        "rejected_prefixes": {},
    }
    admitted = set()
    if not os.path.exists(probe_db_path):
        diag["error"] = "probe_db_missing"
        return admitted, diag
    # Read-only open: never writes, never upgrades the probe DB.
    uri = "file:" + probe_db_path + "?mode=ro"
    try:
        conn = sqlite3.connect(uri, uri=True, timeout=30)
    except sqlite3.Error as e:
        diag["error"] = "probe_db_open_failed: %s" % type(e).__name__
        return admitted, diag
    try:
        rows = conn.execute(
            "SELECT fingerprint, name, state FROM probe_nodes"
        ).fetchall()
    except sqlite3.Error:
        conn.close()
        diag["error"] = "probe_nodes_unreadable"
        return admitted, diag
    diag["total_nodes"] = len(rows)
    for fingerprint, _name, state in rows:
        prefix = fingerprint[:12]
        report = _most_recent_report(conn, fingerprint)
        if report is None:
            diag["rejected"] += 1
            diag["reasons"]["no_report"] = diag["reasons"].get("no_report", 0) + 1
            diag["rejected_prefixes"][prefix] = "no_report"
            continue
        ts, success, second_ms, second_status, interface, _error = report
        # The most recent report decides. Any failure/slow/stale report
        # rejects the fingerprint even if an older success exists.
        if state != "verified":
            diag["rejected"] += 1
            diag["reasons"]["state_not_verified"] = diag["reasons"].get("state_not_verified", 0) + 1
            diag["rejected_prefixes"][prefix] = "state_not_verified:%s" % state
            continue
        if not success:
            diag["rejected"] += 1
            diag["reasons"]["latest_failed"] = diag["reasons"].get("latest_failed", 0) + 1
            diag["rejected_prefixes"][prefix] = "latest_failed"
            continue
        if second_ms is None or second_ms > threshold_ms:
            diag["rejected"] += 1
            diag["reasons"]["latest_slow_or_missing_ms"] = diag["reasons"].get("latest_slow_or_missing_ms", 0) + 1
            diag["rejected_prefixes"][prefix] = "latest_second_ms=%s" % (second_ms,)
            continue
        if second_status != EXPECTED_SECOND_STATUS:
            diag["rejected"] += 1
            diag["reasons"]["latest_status_not_204"] = diag["reasons"].get("latest_status_not_204", 0) + 1
            diag["rejected_prefixes"][prefix] = "latest_status=%s" % (second_status,)
            continue
        if not interface or not str(interface).startswith(CELLULAR_INTERFACE_PREFIX):
            diag["rejected"] += 1
            diag["reasons"]["latest_interface_not_cellular"] = diag["reasons"].get("latest_interface_not_cellular", 0) + 1
            diag["rejected_prefixes"][prefix] = "latest_interface=%s" % (interface,)
            continue
        # Timestamp sanity, STRICT (fail closed). Without this, a
        # far-future ts passed the TTL test below (negative age) and was
        # admitted as "fresh" until TTL had elapsed after the future
        # instant -- up to TTL + the future offset of wrongful admission.
        # Rule (GPT second review item 1): 0 < ts <= now, no allowance.
        # A future ts is rejected even if it is only 1 second ahead.
        if ts is None or ts <= 0 or ts > now:
            diag["rejected"] += 1
            diag["reasons"]["latest_ts_invalid"] = diag["reasons"].get("latest_ts_invalid", 0) + 1
            diag["rejected_prefixes"][prefix] = "latest_ts_invalid"
            continue
        if now - ts > ttl_seconds:
            diag["rejected"] += 1
            diag["reasons"]["latest_stale"] = diag["reasons"].get("latest_stale", 0) + 1
            diag["rejected_prefixes"][prefix] = "latest_age_s=%s" % ((now - ts) if ts else None,)
            continue
        admitted.add(fingerprint)
        diag["admitted"] += 1
    conn.close()
    return admitted, diag


def gate_lines(lines, admitted_fps):
    """Filter candidate subscription lines through the admitted set.

    lines: iterable of Surge proxy lines (strings).
    admitted_fps: set of 32-hex fingerprints from load_verified().
    Returns (kept_lines, diag) where diag has counts and, for every dropped
    line, its fingerprint prefix and reason. Unparsable lines and lines whose
    protocol is not whitelisted are dropped (fail closed).
    """
    kept = []
    diag = {
        "total_lines": 0,
        "kept": 0,
        "dropped": 0,
        "reasons": {},
        "dropped_prefixes": {},
    }
    for line in lines:
        line = line.rstrip("\n")
        if not line.strip():
            continue
        diag["total_lines"] += 1
        parsed = parse_surge_line(line)
        if parsed is None:
            diag["dropped"] += 1
            diag["reasons"]["unparsable_or_protocol"] = diag["reasons"].get("unparsable_or_protocol", 0) + 1
            continue
        name, proto, host, port, params = parsed
        fp = fingerprint_of(proto, host, port, params)
        prefix = fp[:12]
        if fp not in admitted_fps:
            diag["dropped"] += 1
            diag["reasons"]["not_verified"] = diag["reasons"].get("not_verified", 0) + 1
            diag["dropped_prefixes"][prefix] = name
            continue
        kept.append(line)
        diag["kept"] += 1
    return kept, diag
