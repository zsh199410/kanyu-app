"""Offline redacted shadow CLI checks."""
from __future__ import annotations

import importlib.util
import json
import unittest
from pathlib import Path

FILE = Path(__file__).resolve().parent.parent / "native-evidence" / "shadow-readonly-cli.py"
spec = importlib.util.spec_from_file_location("surge_shadow_cli", FILE)
cli = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cli)
PINS = [f"TEST-PIN-{i:02}" for i in range(1, 22)]
NAME = "PRIVATE-POLICY-NAME-NOT-FOR-PUBLIC-OUTPUT"
SHA = "a" * 64


def payload():
    return {
        "candidate_names": PINS + [NAME],
        "pinned_names": PINS,
        "evidence_records": [],
        "frozen_payload_sha": SHA,
        "network_bearer": "cellular",
        "stop_status": "RUNNING",
    }


class ShadowCLITests(unittest.TestCase):
    def test_empty_verified_data_emits_no_prod_authorization(self):
        x = cli.summarize(payload())
        self.assertEqual(x["candidate_count"], 22)
        self.assertEqual(x["eligible_shadow_count"], 0)
        self.assertEqual(x["no_verified_observation_count"], 22)
        self.assertFalse(x["production_write_authorized"])
        self.assertFalse(x["production_delete_authorized"])

    def test_output_never_emits_raw_policy_names_or_sha(self):
        p = payload()
        p["unused_secret"] = "trojan://mysecret@192.0.2.1"
        x = cli.summarize(p)
        text = json.dumps(x)
        self.assertNotIn(NAME, text)
        self.assertNotIn("mysecret", text)
        self.assertNotIn(SHA, text)
        self.assertNotIn("TEST-PIN", text)

    def test_stop_unknown_is_blocker(self):
        p = payload()
        p["stop_status"] = "UNKNOWN"
        x = cli.summarize(p)
        self.assertIn("STOP_UNKNOWN", x["gate_reasons"])
        self.assertFalse(x["production_write_authorized"])

    def test_missing_one_pin_is_blocker(self):
        p = payload()
        p["pinned_names"] = PINS[:-1]
        x = cli.summarize(p)
        self.assertEqual(x["pinned_integrity"], "20/21")
        self.assertIn("PINNED_SET_NOT_VERIFIED", x["gate_reasons"])

    def test_missing_fields_refuses_without_invented_defaults(self):
        p = payload()
        p.pop("network_bearer")
        with self.assertRaisesRegex(ValueError, "missing_required_fields"):
            cli.summarize(p)

    def test_bad_evidence_refuses(self):
        p = payload()
        p["evidence_records"] = "not_a_list"
        with self.assertRaises(ValueError):
            cli.summarize(p)


if __name__ == "__main__":
    unittest.main()
