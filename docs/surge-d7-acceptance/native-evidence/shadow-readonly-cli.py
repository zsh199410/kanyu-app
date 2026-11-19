#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Private-environment read-only CLI for Surge #73 shadow recommendations.

Input: one JSON object via standard input (no source/production file paths).
Output: deliberately redacted JSON summary, with no node names, URIs, IPs,
credentials, source subscription bytes, or raw evidence records.

No network I/O, file I/O, timer changes, API POST, or production writes.
Do not feed genuine secrets into the GitHub CI; use trusted local runner.
"""
from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path

MODULE = Path(__file__).resolve().with_name("shadow-selection-plan.py")
spec = importlib.util.spec_from_file_location("surge_shadow_selection", MODULE)
planner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(planner)
MAX_INPUT_BYTES = 4 * 1024 * 1024
REQUIRED = {"candidate_names", "pinned_names", "evidence_records",
            "frozen_payload_sha", "network_bearer", "stop_status"}


def summarize(payload):
    """Pure summary; never prints policy names or sensitive raw input fields."""
    if not isinstance(payload, dict) or not REQUIRED <= payload.keys():
        raise ValueError("missing_required_fields")
    x = planner.plan_shadow_selection(
        payload["candidate_names"], payload["pinned_names"],
        payload["evidence_records"], payload["frozen_payload_sha"],
        payload["network_bearer"], payload["stop_status"]
    )
    return {
        "mode": "READ_ONLY_SHADOW",
        "candidate_count": x["candidate_count"],
        "verified_observation_nodes": x["verified_observation_nodes"],
        "eligible_shadow_count": len(x["shadow_eligible_order"]),
        "proposed_active_exclusion_count": len(x["proposed_exclusion_only"]),
        "proposed_retest_count": len(x["proposed_retest"]),
        "no_verified_observation_count": len(x["no_verified_observations"]),
        "pinned_integrity": x["pinned_integrity"],
        "pinned_intact": x["pinned_intact"],
        "network_bearer": x["network_bearer"],
        "stop_status": x["stop_status"],
        "gate_reasons": x["gate_reasons"],
        "production_write_authorized": False,
        "production_delete_authorized": False,
        "decision": "SHADOW_ONLY_NO_PRODUCTION_ACTION",
    }


def main() -> int:
    # Deliberately no file argument: the operator chooses an offline/sanitized
    # JSON stream, avoiding accidental access to /etc and live pool paths.
    if len(sys.argv) != 1:
        print('{"error":"unsupported_arguments","decision":"NO_PRODUCTION_ACTION"}')
        return 2
    raw = sys.stdin.buffer.read(MAX_INPUT_BYTES + 1)
    if len(raw) > MAX_INPUT_BYTES:
        print('{"error":"input_too_large","decision":"NO_PRODUCTION_ACTION"}')
        return 2
    try:
        payload = json.loads(raw.decode("utf-8"))
        output = summarize(payload)
    except (ValueError, KeyError, TypeError, UnicodeError, json.JSONDecodeError):
        # Never echo the offending document, exception or node names.
        print('{"error":"invalid_or_unverified_input","decision":"NO_PRODUCTION_ACTION"}')
        return 2
    print(json.dumps(output, sort_keys=True, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
