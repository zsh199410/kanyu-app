# -*- coding: utf-8 -*-
"""Surge Issue #73: pure, read-only shadow selection planning.

This code never performs API calls, routing changes, file writes, node
deletions, or timer changes. It composes existing *strictly verified*
stability decisions into a transparent, non-deployable candidate report.
Production admission and releases are separate independent processes.
"""
from __future__ import annotations

import importlib.util
from datetime import datetime, timezone
from pathlib import Path

_RANKER = Path(__file__).resolve().with_name("stability-ranker.py")
_spec = importlib.util.spec_from_file_location("_surge_shadow_ranker", _RANKER)
_ranker = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_ranker)

EXPECTED_PIN_COUNT = 21
SHA_CHARS = set("0123456789abcdef")


def _names(values, label):
    if not isinstance(values, (tuple, list)):
        raise ValueError(label + " must be list/tuple")
    if any(not isinstance(n, str) or not n.strip() or n != n.strip()
           for n in values):
        raise ValueError(label + " must contain nonempty, unpadded names")
    if len(values) != len(set(values)):
        raise ValueError(label + " contains duplicate names")
    return list(values)


def plan_shadow_selection(candidate_names, pinned_names, evidence_records,
                          frozen_payload_sha, network_bearer, stop_status,
                          *, now=None):
    """Return a shadow-only recommendation with explicit hard safety gates.

    At zero or insufficient verified phone evidence, no member is marked as
    active-selectable. A verified failed probe is proposed for immediate
    exclusion from active selection, NEVER for permanent deletion. A slow
    yet connected node is merely recommended for retest, not excluded.

    This is NOT a publishable configuration. No consumer may treat it as
    approval for a production write, even if all classifications are green.
    """
    candidates = _names(candidate_names, "candidate_names")
    pinned = _names(pinned_names, "pinned_names")
    if not (isinstance(frozen_payload_sha, str)
            and len(frozen_payload_sha) == 64
            and set(frozen_payload_sha) <= SHA_CHARS):
        raise ValueError("frozen_payload_sha must be lowercase 64-digit hex")
    if network_bearer not in ("wifi", "cellular"):
        raise ValueError("network_bearer must be wifi or cellular")
    if not isinstance(evidence_records, (tuple, list)):
        raise ValueError("evidence_records must be a list or tuple")
    ref = now if now is not None else datetime.now(timezone.utc)
    if not isinstance(ref, datetime) or ref.tzinfo is None:
        raise ValueError("now must be timezone-aware datetime")

    pinned_ok = (len(pinned) == EXPECTED_PIN_COUNT
                 and set(pinned).issubset(set(candidates)))
    stopped = stop_status is True or (
        isinstance(stop_status, str)
        and stop_status.strip().upper() in ("STOP", "STOPPED", "HALT")
    )
    # Unknown STOP state MUST NOT be interpreted as RUNNING.
    stop_known_running = (stop_status is False or
                          (isinstance(stop_status, str)
                           and stop_status.strip().upper() == "RUNNING"))
    gate_reasons = []
    if not pinned_ok:
        gate_reasons.append("PINNED_SET_NOT_VERIFIED")
    if stopped:
        gate_reasons.append("STOP_ACTIVE")
    elif not stop_known_running:
        gate_reasons.append("STOP_UNKNOWN")
    summaries = []
    for node in candidates:
        decision = _ranker.classify(
            evidence_records, node, network_bearer, frozen_payload_sha,
            now=ref
        )
        # Never report unverified/insufficient evidence as healthy.
        complete = decision["sample_count"] >= _ranker.MIN_SAMPLES
        selectable = bool(
            pinned_ok and stop_known_running and complete
            and decision["state"] in ("PREFERRED", "USABLE")
            and not decision["exclude_from_active_selection"]
        )
        summaries.append({
            "node_name": node,
            "pinned": node in pinned,
            "state": decision["state"],
            "sample_count": decision["sample_count"],
            "success_rate": decision["success_rate"],
            "median_latency_ms": decision["median_latency_ms"],
            "exclude_from_active_selection": decision["exclude_from_active_selection"],
            "retest_high_latency": decision["retest_high_latency"],
            "shadow_selectable": selectable,
            "eligible_for_removal": False,
        })
    selected = sorted(
        (x for x in summaries if x["shadow_selectable"]),
        key=lambda x: (-x["success_rate"],
                       x["median_latency_ms"] if x["median_latency_ms"] is not None
                       else float("inf"), x["node_name"])
    )
    exclusions = sorted(x["node_name"] for x in summaries
                        if x["exclude_from_active_selection"])
    retests = sorted(x["node_name"] for x in summaries
                     if x["retest_high_latency"])
    no_evidence = sorted(x["node_name"] for x in summaries
                         if not x["sample_count"])
    return {
        "mode": "READ_ONLY_SHADOW",
        "network_bearer": network_bearer,
        "frozen_payload_sha": frozen_payload_sha,
        "pinned_integrity": f"{len(set(pinned) & set(candidates))}/{EXPECTED_PIN_COUNT}",
        "pinned_intact": pinned_ok,
        "stop_status": "STOP" if stopped else "RUNNING" if stop_known_running
                       else "UNKNOWN",
        "gate_reasons": gate_reasons,
        "candidate_count": len(candidates),
        "verified_observation_nodes": sum(bool(x["sample_count"]) for x in summaries),
        "shadow_eligible_order": [x["node_name"] for x in selected],
        "proposed_exclusion_only": exclusions,
        "proposed_retest": retests,
        "no_verified_observations": no_evidence,
        "node_summaries": summaries,
        "production_write_authorized": False,
        "production_delete_authorized": False,
        "publishable": False,
        "decision": "SHADOW_ONLY_NO_PRODUCTION_ACTION",
    }
