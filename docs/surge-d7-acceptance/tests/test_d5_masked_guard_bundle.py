"""D5 regression: the deployed guard must be the approved masked-aware copy.

No systemd operations, production files, network calls or real node secrets.
"""
from __future__ import annotations

import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parent.parent
BUNDLED = ROOT / "single-writer" / "legacy-writer-guard.py"
CANONICAL = ROOT / "legacy-writer-guard" / "legacy-writer-guard.py"
WRITER = ROOT / "single-writer" / "single_writer.py"


def load(module_name, path):
    spec = importlib.util.spec_from_file_location(module_name, str(path))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def drained_masked_units():
    units = {}
    for name in ("pool-publish.timer", "pool-sync.timer"):
        units[name] = {
            "LoadState": "loaded", "UnitFileState": "disabled",
            "ActiveState": "inactive", "Job": "",
        }
    for name in ("pool-publish.service", "pool-sync.service"):
        units[name] = {
            "LoadState": "masked", "UnitFileState": "masked",
            "ActiveState": "inactive", "SubState": "dead",
            "MainPID": "0", "ControlPID": "0",
            "Job": "", "Result": "signal",  # stale historical result is irrelevant
        }
    return units


class TestDeployGuardBundle(unittest.TestCase):
    def setUp(self):
        self.guard = load("d5_guard", BUNDLED)
        self.writer = load("d5_writer", WRITER)

    def check(self, units, rows=()):
        return self.guard.check(show=lambda name: dict(units[name]),
                                processes=lambda: list(rows))

    def test_exact_approved_guard_is_bundled(self):
        self.assertEqual(BUNDLED.read_bytes(), CANONICAL.read_bytes())
        self.assertIsNotNone(self.writer.load_guard())
        self.assertEqual(Path(self.writer.load_guard().__file__).resolve(),
                         BUNDLED.resolve())

    def test_real_masked_systemd_state_passes_both_gates(self):
        units = drained_masked_units()
        self.assertEqual(self.check(units),
                         (True, "legacy_writers_drained", "system"))
        proven, evidence = self.writer.legacy_ban_proof(
            show=lambda name: dict(units[name]),
            processes=lambda: [],
            require_masked_services=True)
        self.assertTrue(proven, evidence)

    def test_service_not_masked_still_refused(self):
        units = drained_masked_units()
        units["pool-publish.service"].update(
            {"LoadState": "loaded", "UnitFileState": "static"})
        self.assertFalse(self.check(units)[0])
        self.assertFalse(self.writer.legacy_ban_proof(
            show=lambda name: dict(units[name]),
            processes=lambda: [], require_masked_services=True)[0])

    def test_inconsistent_mask_refused(self):
        units = drained_masked_units()
        units["pool-publish.service"]["UnitFileState"] = "disabled"
        self.assertEqual(self.check(units)[1], "service_mask_inconsistent")

    def test_masked_but_active_pid_or_job_refused(self):
        for changes in (
            {"ActiveState": "active", "SubState": "running"},
            {"MainPID": "1234"},
            {"ControlPID": "4321"},
            {"Job": "22"},
        ):
            with self.subTest(changes=changes):
                units = drained_masked_units()
                units["pool-sync.service"].update(changes)
                self.assertFalse(self.check(units)[0])
                self.assertFalse(self.writer.legacy_ban_proof(
                    show=lambda name: dict(units[name]),
                    processes=lambda: [], require_masked_services=True)[0])

    def test_timer_or_legacy_writer_running_refused(self):
        units = drained_masked_units()
        units["pool-publish.timer"]["ActiveState"] = "active"
        self.assertFalse(self.check(units)[0])
        units = drained_masked_units()
        self.assertEqual(
            self.check(units, ["1234 /usr/bin/python3 -m pool.cli publish"])[1],
            "legacy_writer_process_present")


if __name__ == "__main__":
    unittest.main()
