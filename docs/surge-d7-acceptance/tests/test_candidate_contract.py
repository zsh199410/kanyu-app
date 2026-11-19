"""Source-independent candidate safety checks (no production side effects)."""
from __future__ import annotations

import importlib.util
from pathlib import Path
import unittest

PATH = (Path(__file__).resolve().parent.parent /
        "single-writer" / "candidate_contract.py")
spec = importlib.util.spec_from_file_location("candidate_contract", PATH)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

PINS = [f"美国{i}" for i in range(1, 14)] + [
    "香港", "香港2", "香港8", "香港24", "香港25",
    "香港34", "香港36", "香港39"
]
assert len(PINS) == 21


def line(name, host="192.0.2.5"):
    return f"{name} = trojan, {host}, 443, password=test123\n"


def payload(extra=()):
    return "".join(line(n) for n in [*PINS, "测试旧节点", *extra]).encode("utf-8")


class CandidateContractTests(unittest.TestCase):
    def assess(self, candidate, *, current=None, generator_verified=False,
               pins=None, blocked=()):
        return module.assess_candidate(
            payload() if current is None else current,
            candidate, PINS if pins is None else pins, blocked,
            generator_verified=generator_verified
        )

    def test_same_bytes_hold_safe_even_without_proof(self):
        d = self.assess(payload())
        self.assertEqual(d["decision"], "HOLD_NO_CHANGE")
        self.assertEqual(d["pin_count"], 21)
        self.assertEqual(d["candidate_count"], 22)
        self.assertTrue(d["identical_bytes"])
        self.assertFalse(d["production_write_authorized"])

    def test_missing_pin_fails(self):
        wrong = payload().decode().replace(line("香港39"), "")
        with self.assertRaisesRegex(ValueError, "missing_pins_in_candidate"):
            self.assess(wrong.encode())

    def test_modified_pin_fails(self):
        wrong = payload().decode().replace(
            line("美国1"), line("美国1", host="192.0.2.8"))
        with self.assertRaisesRegex(ValueError, "pinned_definition_modified"):
            self.assess(wrong.encode())

    def test_modified_existing_nonpin_fails(self):
        wrong = payload().decode().replace(
            line("测试旧节点"), line("测试旧节点", host="192.0.2.8"))
        with self.assertRaisesRegex(ValueError, "existing_definition_changed"):
            self.assess(wrong.encode())

    def test_existing_nonpin_cannot_be_automatically_deleted(self):
        with self.assertRaisesRegex(ValueError, "automatic_removal_not_authorized"):
            self.assess("".join(line(n) for n in PINS).encode())

    def test_blocklisted_cannot_come_back(self):
        candidate = payload(["香港11"])
        with self.assertRaisesRegex(ValueError, "blocklisted_node_present"):
            self.assess(candidate, blocked=["香港11"])

    def test_wrong_pin_count_fails(self):
        with self.assertRaisesRegex(ValueError, "canonical_pin_count_not_21"):
            self.assess(payload(), pins=PINS[:-1])

    def test_unknown_pin_fails_on_old_pool(self):
        wrong = PINS[:-1] + ["NOT-OLD-PIN"]
        with self.assertRaisesRegex(ValueError, "missing_pins_in_current_pool"):
            self.assess(payload(), pins=wrong)

    def test_duplicate_name_fails(self):
        with self.assertRaisesRegex(ValueError, "invalid_or_duplicate_node_name"):
            self.assess(payload() + line("美国1").encode())

    def test_empty_pool_fails(self):
        with self.assertRaisesRegex(ValueError, "invalid_payload_size_or_type"):
            self.assess(b"")

    def test_malformed_and_not_proxy_fails(self):
        for body in (b"[Proxy]\n", b"DIRECT = DIRECT\n",
                     "节点 = DIRECT\n".encode("utf-8")):
            with self.subTest(body=body):
                with self.assertRaisesRegex(ValueError, "not_a_proxy_declaration"):
                    self.assess(body)

    def test_unverified_addition_fails(self):
        with self.assertRaisesRegex(ValueError, "unverified_new_nodes"):
            self.assess(payload(["新节点1"]))

    def test_generator_verified_flag_is_never_release_authorization(self):
        d = self.assess(payload(["新节点1"]), generator_verified=True)
        self.assertEqual(d["decision"], "REVIEW_GENERATED_CHANGES")
        self.assertEqual(d["added_count"], 1)
        self.assertFalse(d["source_independently_verified"])
        self.assertFalse(d["production_write_authorized"])
        self.assertFalse(d["production_delete_authorized"])

    def test_new_nodes_capped_at_four(self):
        with self.assertRaisesRegex(ValueError, "new_node_cap_exceeded"):
            self.assess(payload([f"新节点{i}" for i in range(5)]),
                        generator_verified=True)

    def test_no_invalid_encoding(self):
        with self.assertRaisesRegex(ValueError, "invalid_utf8"):
            self.assess(b"\xff" + payload())

    def test_blocked_pin_conflict_fails(self):
        with self.assertRaisesRegex(ValueError, "blocked_pin_conflict"):
            self.assess(payload(), blocked=["香港"])

    def test_different_byte_representation_not_auto_published(self):
        d = self.assess(payload() + b"\n")
        self.assertFalse(d["identical_bytes"])
        self.assertFalse(d["production_write_authorized"])
        self.assertEqual(d["decision"], "REVIEW_GENERATED_CHANGES")


if __name__ == "__main__":
    unittest.main()
