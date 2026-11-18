"""Deterministic shadow-only stability tests (no phone, network, or production I/O)."""
from __future__ import annotations

from datetime import datetime, timedelta, timezone
import importlib.util
from pathlib import Path
import unittest

FILE = Path(__file__).resolve().parent.parent / "native-evidence" / "stability-ranker.py"
spec = importlib.util.spec_from_file_location("stability_ranker", str(FILE))
ranker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ranker)

NOW = datetime(2026, 11, 18, 12, 0, tzinfo=timezone.utc)
SHA = "a" * 64
NAME = "TEST-ROTATION-01"


def record(hours_ago, latency=None, *, fail=False, bearer="cellular",
           verified=True, node=NAME):
    raw = {"node_name": node}
    if fail:
        raw["status"] = "timeout"
    elif latency is not None:
        raw["status"] = "success"
        raw["latency_ms"] = latency
    return {
        "raw_result": raw,
        "network_bearer": bearer,
        "latency_ms": latency,
        "tested_at": (NOW - timedelta(hours=hours_ago)).isoformat(),
        "phone_loaded_sha": SHA,
        "payload_sha": SHA,
        "measurement_verified": verified,
        "calibration_verdict": "CALIBRATED",
        "loaded_proof_level": "BYTE_PROOF",
        "production_admission": "GRANTED",
    }


class StabilityTest(unittest.TestCase):
    def classify(self, records, **kwargs):
        return ranker.classify(records, NAME, "cellular", SHA, now=NOW, **kwargs)

    def test_six_fluctuations_all_connected_never_removed(self):
        samples = [record(6-i, ms) for i, ms in
                   enumerate([185, 342, 228, 318, 196, 244])]
        result = self.classify(samples)
        self.assertEqual(result["sample_count"], 6)
        self.assertEqual(result["successes"], 6)
        self.assertEqual(result["over_300ms_count"], 2)
        self.assertEqual(result["state"], "INSUFFICIENT_EVIDENCE")
        self.assertFalse(result["eligible_for_removal"])

    def test_eight_mixed_latency_successes_preferred(self):
        nums = [185, 342, 228, 318, 196, 244, 270, 330]
        samples = [record(8-i, ms) for i, ms in enumerate(nums)]
        result = self.classify(samples)
        self.assertEqual(result["state"], "PREFERRED")
        self.assertEqual(result["successes"], 8)
        self.assertEqual(result["over_300ms_count"], 3)
        self.assertFalse(result["eligible_for_removal"])

    def test_majority_connected_still_usable(self):
        samples = [record(10-i, 250 + i * 30, fail=(i % 4 == 0))
                   for i in range(10)]
        result = self.classify(samples)
        self.assertEqual(result["state"], "USABLE")
        self.assertEqual(result["successes"], 7)
        self.assertEqual(result["failures"], 3)
        self.assertFalse(result["eligible_for_removal"])

    def test_single_timeout_then_recovery_not_quarantined(self):
        samples = [record(9-i, 230) for i in range(8)]
        samples += [record(1, fail=True), record(0, 290)]
        result = self.classify(samples)
        self.assertIn(result["state"], ("PREFERRED", "USABLE"))
        self.assertFalse(result["eligible_for_removal"])

    def test_persistent_failures_only_for_review(self):
        samples = [record(9-i, fail=True) for i in range(9)]
        result = self.classify(samples)
        self.assertEqual(result["state"], "QUARANTINE_REVIEW")
        self.assertEqual(result["failures"], 9)
        self.assertFalse(result["eligible_for_removal"])

    def test_recovered_node_loses_quarantine_state(self):
        samples = [record(9-i, fail=True) for i in range(8)]
        samples += [record(0, 320)]
        result = self.classify(samples, previous_state="QUARANTINE_REVIEW")
        self.assertEqual(result["state"], "OBSERVE")
        self.assertFalse(result["eligible_for_removal"])

    def test_last_probe_recovery_blocks_quarantine_without_saved_state(self):
        # After a restart, previous_state may be unavailable. A newly
        # verified success still must keep the node out of quarantine.
        samples = [record(9-i, fail=True) for i in range(8)]
        samples.append(record(0, 360))
        result = self.classify(samples)
        self.assertEqual(result["state"], "OBSERVE")
        self.assertFalse(result["eligible_for_removal"])

    def test_mixed_bearers_and_unverified_not_counted(self):
        samples = [record(i, 180) for i in range(1, 4)]
        samples += [record(i + 4, 180, bearer="wifi") for i in range(5)]
        samples += [record(0, 180, verified=False)]
        result = self.classify(samples)
        self.assertEqual(result["sample_count"], 3)
        self.assertFalse(result["eligible_for_removal"])

    def test_repeated_fast_probes_cannot_inflate_sample_count(self):
        first = record(2, 100)
        second = record(2 - (1 / 3600), 350)
        result = self.classify([first, second])
        self.assertEqual(result["sample_count"], 1)

    def test_old_and_wrong_payload_excluded(self):
        old = record(49, 200)
        wrong = record(1, 200)
        wrong["phone_loaded_sha"] = "b" * 64
        result = self.classify([old, wrong])
        self.assertEqual(result["sample_count"], 0)

    def test_wrong_network_type_rejected(self):
        with self.assertRaises(ValueError):
            ranker.classify([], NAME, "UNKNOWN", SHA, now=NOW)


if __name__ == "__main__":
    unittest.main()
