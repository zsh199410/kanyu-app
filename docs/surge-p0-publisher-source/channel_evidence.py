"""Non-native, per-bearer diagnostic probe classifier for Issue #73.

This module is intentionally NOT a publisher allowlist or native gate.
Surge script reports have client-declared network_type, not independently
verified physical-bearer evidence. Do not import this module to bypass the
native_results-v1 gate in PR #77.
"""

from collections import Counter
import math
import re

FP_RE = re.compile(r"[0-9a-f]{32}")
NETWORKS = ("wifi", "cellular")


def evaluate(rows, fingerprints, source_sha, now, ttl_seconds=86400, threshold_ms=300):
    """Compute diagnostic classifications independently for each bearer.

    rows: iterable of mappings {fingerprint, source_version_sha, network_type,
    ts, success(bool), second_ms(number or None)}. Only same-source records
    are considered. Newest timestamp per (fp, network) wins; a same-timestamp
    failure wins over success. Missing/malformed records are ignored.

    Returns only counts and classification names, no host/URI/secret. A Wi-Fi
    success is never revoked by a subsequent *cellular* slow result.
    """
    fps = set(fingerprints)
    if any(not isinstance(fp, str) or not FP_RE.fullmatch(fp) for fp in fps):
        raise ValueError("invalid fingerprint set")
    if not isinstance(source_sha, str) or not re.fullmatch(r"[0-9a-f]{64}", source_sha):
        raise ValueError("source SHA must be full sha256")
    if not isinstance(now, int) or now <= 0:
        raise ValueError("invalid current timestamp")
    if ttl_seconds <= 0 or threshold_ms <= 0:
        raise ValueError("invalid threshold")
    latest = {}
    for row in rows:
        if not isinstance(row, dict):
            continue
        fp = row.get("fingerprint")
        net = row.get("network_type")
        ts = row.get("ts")
        success = row.get("success")
        ms = row.get("second_ms")
        if fp not in fps or net not in NETWORKS or row.get("source_version_sha") != source_sha:
            continue
        if not isinstance(ts, int) or isinstance(ts, bool) or ts <= 0 or ts > now:
            continue
        if not isinstance(success, bool):
            continue
        if ms is not None and (not isinstance(ms, (int, float)) or isinstance(ms, bool) or not math.isfinite(ms) or ms < 0):
            continue
        key = (fp, net)
        passed = success and ms is not None and ms < threshold_ms
        previous = latest.get(key)
        # If two reports share the same timestamp, the failure dominates.
        if previous is None or ts > previous[0] or (ts == previous[0] and not passed):
            latest[key] = (ts, passed)
    summary = {}
    for net in NETWORKS:
        counts = Counter()
        for fp in fps:
            item = latest.get((fp, net))
            if item is None:
                counts["no_evidence"] += 1
            elif now - item[0] > ttl_seconds:
                counts["stale"] += 1
            else:
                counts["qualified_diagnostic" if item[1] else "failed_diagnostic"] += 1
        summary[net] = dict(sorted(counts.items()))
    return {"kind": "client_declared_diagnostic_only", "source_sha_prefix": source_sha[:12],
            "total_fingerprints": len(fps), "by_network": summary}
