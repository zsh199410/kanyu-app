# -*- coding: utf-8 -*-
"""Read-only native node stability classification for Surge Issue #73.

This module NEVER authorizes deletion. 300 ms is a preference, not a
connectivity-failure threshold. It uses independent verified observations
from one network bearer and one frozen payload, without mixing Wi-Fi and
cellular samples. Production deletion requires a separate gate.
"""
from __future__ import annotations

from datetime import datetime, timezone
from math import isfinite
from statistics import median

WINDOW_SECONDS = 48 * 3600
SAMPLE_BUCKET_SECONDS = 15 * 60
MIN_SAMPLES = 8
TARGET_MS = 300
QUARANTINE_MIN_SPAN_SECONDS = 6 * 3600
STATES = ("INSUFFICIENT_EVIDENCE", "PREFERRED", "USABLE",
          "OBSERVE", "QUARANTINE_REVIEW")


def _time(value):
    if not isinstance(value, str):
        return None
    try:
        d = datetime.fromisoformat(value.replace("Z", "+00:00"))
        if d.tzinfo is None:
            return None
        return d.astimezone(timezone.utc)
    except ValueError:
        return None


def _connection(record):
    """True for a witnessed successful native probe, False for failure.

    Numbers without explicit failures indicate a completed latency test;
    values >=300 are still successes, never connectivity failures.
    """
    raw = record.get("raw_result")
    if not isinstance(raw, dict):
        return None
    status = str(raw.get("status") or "").strip().lower()
    if status in ("timeout", "timed_out", "failed", "failure", "error"):
        return False
    if raw.get("timeout") is True or raw.get("error"):
        return False
    latency = record.get("latency_ms")
    if (isinstance(latency, (int, float)) and not isinstance(latency, bool)
            and isfinite(latency) and latency >= 0):
        return True
    if status in ("ok", "success", "connected"):
        return True
    return None


def classify(records, node_name, bearer, expected_payload_sha, *,
             now=None, min_samples=MIN_SAMPLES, target_ms=TARGET_MS,
             previous_state=None):
    """Return a shadow-only state; eligible_for_removal is always False.

    Requires 8 independent observations by default; de-duplicates all
    probes inside a 15-minute bucket for a single node and network type.
    Only explicitly calibrated byte-bound records are considered.
    """
    if bearer not in ("wifi", "cellular"):
        raise ValueError("bearer must be wifi or cellular")
    if not (isinstance(expected_payload_sha, str)
            and len(expected_payload_sha) == 64
            and all(ch in "0123456789abcdef" for ch in expected_payload_sha)):
        raise ValueError("expected_payload_sha must be 64 lowercase hex")
    if min_samples < 2:
        raise ValueError("min_samples must be >= 2")
    ref = now or datetime.now(timezone.utc)
    if ref.tzinfo is None:
        raise ValueError("now must include timezone")
    ref = ref.astimezone(timezone.utc)
    by_bucket = {}
    for r in records or []:
        if not isinstance(r, dict) or r.get("network_bearer") != bearer:
            continue
        raw = r.get("raw_result")
        if not isinstance(raw, dict) or raw.get("node_name") != node_name:
            continue
        if not (r.get("measurement_verified") is True
                and r.get("calibration_verdict") == "CALIBRATED"
                and r.get("loaded_proof_level") == "BYTE_PROOF"
                and r.get("production_admission") == "GRANTED"
                and r.get("phone_loaded_sha") == expected_payload_sha
                and r.get("payload_sha") == expected_payload_sha):
            continue
        tested = _time(r.get("tested_at"))
        if tested is None:
            continue
        age = (ref - tested).total_seconds()
        if age < 0 or age > WINDOW_SECONDS:
            continue
        connected = _connection(r)
        if connected is None:
            continue
        # One observation per quarter-hour; latest wins, no rapid
        # retries can artificially inflate reliability estimates.
        key = int(tested.timestamp() // SAMPLE_BUCKET_SECONDS)
        old = by_bucket.get(key)
        if old is None or tested > old[0]:
            by_bucket[key] = (tested, connected, r.get("latency_ms"))

    observations = sorted(by_bucket.values(), key=lambda p: p[0])
    count = len(observations)
    successes = sum(1 for _, ok, _ in observations if ok)
    failures = count - successes
    ratio = successes / count if count else 0.0
    success_latencies = [v for _, ok, v in observations if ok
                         and isinstance(v, (int, float)) and not isinstance(v, bool)
                         and isfinite(v) and v >= 0]
    med = median(success_latencies) if success_latencies else None
    over_target = sum(v >= target_ms for v in success_latencies)
    span = (observations[-1][0] - observations[0][0]).total_seconds() if count else 0.0
    recovered = bool(previous_state == "QUARANTINE_REVIEW"
                     and observations and observations[-1][1])
    if count < min_samples:
        state = "INSUFFICIENT_EVIDENCE"
    elif recovered:
        state = "OBSERVE"
    elif ratio >= 0.8 and med is not None and med < target_ms:
        state = "PREFERRED"
    elif ratio >= 0.6:
        state = "USABLE"
    elif ratio >= 0.2:
        state = "OBSERVE"
    elif span >= QUARANTINE_MIN_SPAN_SECONDS and failures >= min_samples:
        state = "QUARANTINE_REVIEW"
    else:
        state = "OBSERVE"
    return {
        "state": state,
        "bearer": bearer,
        "node_name": node_name,
        "sample_count": count,
        "successes": successes,
        "failures": failures,
        "success_rate": ratio,
        "median_latency_ms": med,
        "over_300ms_count": over_target,
        "recovered": recovered,
        "eligible_for_removal": False,
        "decision": "RETAIN_OR_REVIEW_ONLY",
    }
