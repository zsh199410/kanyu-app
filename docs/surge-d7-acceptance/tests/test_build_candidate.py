"""Pure legacy candidate-preview test; never reads DB/network/production."""
from __future__ import annotations

import importlib.util
from pathlib import Path
import unittest

PATH = Path(__file__).resolve().parent.parent / "single-writer" / "build_candidate.py"
spec = importlib.util.spec_from_file_location("surge_build_candidate", PATH)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

NOW = 1800000000
PINS = [("trojan", f"192.0.2.{i}", 443 + i) for i in range(1, 22)]
OLD = ("trojan", "198.51.100.10", 443)
NEW = ("trojan", "198.51.100.20", 443)


def line(name, k):
    return f"{name} = trojan, {k[1]}, {k[2]}, password=test123"


def parse(line_text):
    _, body = line_text.split("=", 1)
    parts = [x.strip() for x in body.split(",")]
    return parts[0], parts[1], int(parts[2])


def render(record, name):
    return line(name, record["key"])


def names(records, reserved):
    return {key: f"新-{i}" for i, (key, record) in enumerate(records)}


def country(name):
    return "US" if name.startswith(("美国", "旧-", "新-")) else "HK"


def node(key, rate=1.0, *, age=60, first=1):
    return {
        "key": key, "last_result": "pass",
        "last_test_at": NOW - age, "pass_count": int(10 * rate),
        "test_count": 10, "first_seen": first
    }


def test_input():
    return {
        "current_pool": ("\n".join(
            [line(f"美国{i}", k) for i, k in enumerate(PINS, start=1)]
            + [line("旧-1", OLD)]) + "\n").encode(),
        "config": {"publish_max_lines": 150, "per_country_cap": 40,
                   "publish_fresh_hours": 24, "publish_max_vps_ms": 300,
                   "publish_min_pass_rate": 0.5,
                   "winner_clean_enabled": False},
        "node_rows": [node(OLD), node(NEW)],
        "latest_pass_ms": {OLD: 200, NEW: 180},
        "fresh_records": {NEW: {"key": NEW}},
        "pinned_file_lines": [line(f"美国{i}", k)
                              for i, k in enumerate(PINS, start=1)],
        "db_pins": {},
        "blocked_keys": set(),
        "parse_fn": parse, "prefilter_fn": lambda rec: True,
        "render_fn": render, "name_fn": names,
        "country_fn": country, "now": NOW,
    }


class BuildCandidateTests(unittest.TestCase):
    def run_candidate(self, **overrides):
        cfg = test_input()
        cfg.update(overrides)
        return mod.build_candidate(**cfg)

    def test_pinned_kept_old_new_order_and_no_write_authority(self):
        x = self.run_candidate()
        self.assertEqual(x["canonical_pin_count"], 21)
        self.assertEqual(x["kept_old_count"], 1)
        self.assertEqual(x["new_count"], 1)
        self.assertEqual(x["proposed_count"], 23)
        text = x["proposed_bytes"].decode()
        self.assertLess(text.index("美国21"), text.index("旧-1"))
        self.assertLess(text.index("旧-1"), text.index("新-0"))
        self.assertFalse(x["production_write_authorized"])
        self.assertFalse(x["production_delete_authorized"])
        self.assertTrue(x["preview_only"])

    def test_vps_gate_excludes_slow_new_node(self):
        inp = test_input()
        inp["latest_pass_ms"][NEW] = 300.1
        result = self.run_candidate(**inp)
        self.assertEqual(result["new_count"], 0)

    def test_old_rotation_not_kept_without_fresh_pass(self):
        inp = test_input()
        inp["node_rows"][0]["last_test_at"] = NOW - 25 * 3600
        result = self.run_candidate(**inp)
        self.assertEqual(result["kept_old_count"], 0)
        self.assertEqual(result["canonical_pin_count"], 21)
        self.assertFalse(result["production_write_authorized"])

    def test_missing_pinned_line_refuses(self):
        inp = test_input()
        inp["pinned_file_lines"].pop()
        with self.assertRaisesRegex(mod.CandidateRefused, "canonical_21"):
            self.run_candidate(**inp)

    def test_pinned_blocklist_refuses(self):
        inp = test_input()
        inp["blocked_keys"] = {PINS[0]}
        with self.assertRaisesRegex(mod.CandidateRefused, "canonical_21"):
            self.run_candidate(**inp)

    def test_real_25_db_pins_minus_four_blocklisted_yield_21(self):
        inp = test_input()
        blocked = [
            ("trojan", f"203.0.113.{i}", 8000 + i)
            for i in range(1, 5)
        ]
        inp["db_pins"] = {
            **{k: f"美国{i}" for i, k in enumerate(PINS, start=1)},
            **{k: f"封禁{i}" for i, k in enumerate(blocked, start=1)}
        }
        inp["blocked_keys"] = set(blocked)
        inp["pinned_file_lines"] += [
            line(f"封禁{i}", k) for i, k in enumerate(blocked, start=1)
        ]
        out = self.run_candidate(**inp)
        self.assertEqual(out["canonical_pin_count"], 21)
        self.assertFalse(any("封禁" in line for line in
                             out["proposed_bytes"].decode().splitlines()))

    def test_duplicate_key_in_pinned_refuses(self):
        inp = test_input()
        inp["pinned_file_lines"].append(inp["pinned_file_lines"][0])
        with self.assertRaisesRegex(mod.CandidateRefused, "duplicate_pinned_entry"):
            self.run_candidate(**inp)

    def test_wrong_callback_refuses(self):
        with self.assertRaisesRegex(mod.CandidateRefused, "unverified_legacy_callback"):
            self.run_candidate(parse_fn=None)

    def test_winner_clean_requires_verified_legacy_adapter(self):
        inp = test_input()
        inp["config"]["winner_clean_enabled"] = True
        with self.assertRaisesRegex(mod.CandidateRefused, "winner_clean_callback_required"):
            self.run_candidate(**inp)

    def test_winner_clean_affects_only_rotation(self):
        inp = test_input()
        inp["config"]["winner_clean_enabled"] = True
        result = self.run_candidate(**inp, winner_clean_fn=lambda rotation: [])
        self.assertEqual(result["canonical_pin_count"], 21)
        self.assertEqual(result["proposed_count"], 21)

    def test_generator_never_writes_even_when_candidate_differs(self):
        inp = test_input()
        old_bytes = inp["current_pool"]
        result = self.run_candidate(**inp)
        self.assertEqual(inp["current_pool"], old_bytes)
        self.assertNotEqual(result["proposed_bytes"], old_bytes)
        self.assertEqual(result["decision"], "PREVIEW_ONLY_NOT_ADMITTED")
        self.assertFalse(result["production_write_authorized"])

    def test_duplicate_old_name_refuses(self):
        inp = test_input()
        inp["current_pool"] += ("\n" + line("美国1", OLD)).encode()
        with self.assertRaisesRegex(mod.CandidateRefused, "duplicate_name"):
            self.run_candidate(**inp)

    def test_bad_result_cannot_make_new_candidate(self):
        inp = test_input()
        inp["node_rows"][1]["last_result"] = "fail"
        self.assertEqual(self.run_candidate(**inp)["new_count"], 0)

    def test_bad_pass_ratio_excludes_node(self):
        inp = test_input()
        inp["node_rows"][1] = node(NEW, 0.4)
        self.assertEqual(self.run_candidate(**inp)["new_count"], 0)

    def test_invalid_clock_rejected(self):
        with self.assertRaisesRegex(mod.CandidateRefused, "invalid_clock"):
            self.run_candidate(now=float("nan"))


if __name__ == "__main__":
    unittest.main()
