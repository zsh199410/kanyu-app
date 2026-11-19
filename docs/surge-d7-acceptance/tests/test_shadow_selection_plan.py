"""Read-only shadow selection planner tests: no phone, filesystem writes or network."""
from __future__ import annotations

import importlib.util
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path

PLAN_PATH = Path(__file__).resolve().parent.parent / "native-evidence" / "shadow-selection-plan.py"
spec = importlib.util.spec_from_file_location("shadow_selection_plan", PLAN_PATH)
planner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(planner)

NOW = datetime(2026, 11, 19, 4, 0, tzinfo=timezone.utc)
SHA = "a" * 64
PINS = [f"TEST-PIN-{n:02d}" for n in range(1, 22)]
FAST = "TEST-FAST"
FAIL = "TEST-FAIL"
SLOW = "TEST-SLOW"
CANDIDATES = PINS + [FAST, FAIL, SLOW]


def evidence(node, hours_ago, latency=200, *, fail=False,
             network="cellular", trusted=True, payload=SHA):
    raw = {"node_name": node}
    if fail:
        raw["status"] = "timeout"
        latency = None
    else:
        raw["status"] = "success"
        raw["latency_ms"] = latency
    return {
        "raw_result": raw,
        "network_bearer": network,
        "latency_ms": latency,
        "tested_at": (NOW - timedelta(hours=hours_ago)).isoformat(),
        "phone_loaded_sha": payload,
        "payload_sha": payload,
        "measurement_verified": trusted,
        "calibration_verdict": "CALIBRATED" if trusted else "UNCALIBRATED",
        "loaded_proof_level": "BYTE_PROOF" if trusted else "MEMBERS_VERIFIED",
        "production_admission": "GRANTED" if trusted else "PENDING_REVIEW",
    }


class ShadowSelectionPlanTests(unittest.TestCase):
    def plan(self, records, *, pins=None, candidates=None,
             stop="RUNNING", bearer="cellular", sha=SHA):
        return planner.plan_shadow_selection(
            CANDIDATES if candidates is None else candidates,
            PINS if pins is None else pins,
            records, sha, bearer, stop, now=NOW
        )

    def test_zero_verified_evidence_no_one_shadow_selectable(self):
        x = self.plan([])
        self.assertEqual(x["verified_observation_nodes"], 0)
        self.assertEqual(x["shadow_eligible_order"], [])
        self.assertEqual(x["proposed_exclusion_only"], [])
        self.assertEqual(x["no_verified_observations"], sorted(CANDIDATES))
        self.assertFalse(x["production_write_authorized"])

    def test_trusted_failure_excludes_only_from_active(self):
        x = self.plan([evidence(FAIL, 0, fail=True)])
        self.assertEqual(x["proposed_exclusion_only"], [FAIL])
        self.assertNotIn(FAIL, x["shadow_eligible_order"])
        self.assertFalse(x["production_delete_authorized"])
        self.assertEqual(next(v for v in x["node_summaries"] if v["node_name"] == FAIL)["state"],
                         "FAILED_EXCLUDED")

    def test_slow_connected_only_retest(self):
        x = self.plan([evidence(SLOW, 0, 746)])
        self.assertEqual(x["proposed_retest"], [SLOW])
        self.assertEqual(x["proposed_exclusion_only"], [])
        self.assertFalse(x["production_write_authorized"])

    def test_prior_failure_recovered_clears_exclusion(self):
        x = self.plan([evidence(FAIL, 2, fail=True), evidence(FAIL, 0, 180)])
        self.assertEqual(x["proposed_exclusion_only"], [])
        self.assertNotIn(FAIL, x["shadow_eligible_order"])

    def test_verified_eight_successes_can_rank_but_cannot_publish(self):
        samples = [evidence(FAST, 10-i, 180+i) for i in range(8)]
        x = self.plan(samples)
        self.assertEqual(x["shadow_eligible_order"], [FAST])
        self.assertFalse(x["publishable"])
        self.assertFalse(x["production_delete_authorized"])

    def test_missing_one_pin_suppresses_all_shadow_selection(self):
        samples = [evidence(FAST, 10-i, 180+i) for i in range(8)]
        x = self.plan(samples, pins=PINS[:-1])
        self.assertEqual(x["shadow_eligible_order"], [])
        self.assertIn("PINNED_SET_NOT_VERIFIED", x["gate_reasons"])

    def test_stopped_or_unknown_suppresses_shadow_selection(self):
        samples = [evidence(FAST, 10-i, 180+i) for i in range(8)]
        for status in ("STOP", None, "unknown", True):
            with self.subTest(status=status):
                x = self.plan(samples, stop=status)
                self.assertEqual(x["shadow_eligible_order"], [])
                self.assertTrue(x["gate_reasons"])
                self.assertFalse(x["production_write_authorized"])

    def test_wifi_failure_does_not_exclude_cellular(self):
        x = self.plan([evidence(FAIL, 0, fail=True, network="wifi"),
                       evidence(FAIL, 1, latency=180, network="cellular")])
        self.assertEqual(x["proposed_exclusion_only"], [])
        self.assertEqual(x["verified_observation_nodes"], 1)

    def test_unverified_phone_result_cannot_trigger_exclusion(self):
        unverified = evidence(FAIL, 0, fail=True, trusted=False)
        x = self.plan([unverified])
        self.assertEqual(x["proposed_exclusion_only"], [])
        self.assertIn(FAIL, x["no_verified_observations"])

    def test_wrong_frozen_version_cannot_trigger_exclusion(self):
        x = self.plan([evidence(FAIL, 0, fail=True, payload="b" * 64)])
        self.assertEqual(x["proposed_exclusion_only"], [])

    def test_duplicate_or_broken_identifiers_refused(self):
        for candidates, pins in ((CANDIDATES + [FAST], PINS),
                                 (CANDIDATES, PINS + [PINS[0]]),
                                 ([" TEST"], PINS)):
            with self.subTest(candidates=candidates, pins=pins):
                with self.assertRaises(ValueError):
                    self.plan([], candidates=candidates, pins=pins)

    def test_bad_sha_or_unknown_bearer_refused(self):
        with self.assertRaises(ValueError):
            self.plan([], sha="UNKNOWN")
        with self.assertRaises(ValueError):
            self.plan([], bearer="UNKNOWN")

    def test_protected_pin_can_be_shadow_excluded_but_never_deleted(self):
        x = self.plan([evidence(PINS[0], 0, fail=True)])
        self.assertIn(PINS[0], x["proposed_exclusion_only"])
        row = next(i for i in x["node_summaries"] if i["node_name"] == PINS[0])
        self.assertTrue(row["pinned"])
        self.assertFalse(row["eligible_for_removal"])
        self.assertFalse(x["production_delete_authorized"])


if __name__ == "__main__":
    unittest.main()
