"""Negative/positive isolation cases for unlocked old production writers."""
import importlib.util
import os
import unittest

ROOT = os.path.dirname(os.path.dirname(__file__))
PATH = os.path.join(ROOT, "systemd", "legacy-writer-guard.py")
SPEC = importlib.util.spec_from_file_location("legacy_writer_guard", PATH)
GUARD = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(GUARD)

def good(unit):
    common = {"LoadState": "loaded", "ActiveState": "inactive", "Job": ""}
    if unit.endswith(".timer"):
        return dict(common, UnitFileState="disabled")
    return dict(common, SubState="dead", MainPID="0",
                ControlPID="0", Result="success")

class LegacyWriterGuardTests(unittest.TestCase):
    def run_guard(self, overrides=None, rows=None, show_error=False,
                  process_error=False):
        overrides = overrides or {}
        def show(unit):
            if show_error:
                raise RuntimeError("systemctl inaccessible")
            return dict(good(unit), **overrides.get(unit, {}))
        def processes():
            if process_error:
                raise RuntimeError("ps inaccessible")
            return [] if rows is None else rows
        return GUARD.check(show, processes)

    def test_green_disabled_and_drained(self):
        self.assertEqual(self.run_guard(), (True, "legacy_writers_drained", "system"))

    def test_red_timer_still_enabled(self):
        allowed, reason, unit = self.run_guard({
            "pool-publish.timer": {"UnitFileState": "enabled"}})
        self.assertFalse(allowed)
        self.assertEqual((reason, unit),
                         ("old_timer_not_disabled", "pool-publish.timer"))

    def test_red_timer_active_even_if_disabled(self):
        allowed, reason, _ = self.run_guard({
            "pool-sync.timer": {"ActiveState": "active"}})
        self.assertFalse(allowed)
        self.assertEqual(reason, "old_timer_not_inactive")

    def test_red_old_writer_without_shared_flock(self):
        allowed, reason, _ = self.run_guard(rows=[
            "4711 /opt/free-node-program/venv/bin/python -m pool.cli publish"])
        self.assertFalse(allowed)
        self.assertEqual(reason, "legacy_writer_process_present")

    def test_red_old_sync_process_without_shared_flock(self):
        allowed, reason, _ = self.run_guard(rows=[
            "4712 /bin/bash /opt/free-node-program/pool-sync.sh"])
        self.assertFalse(allowed)
        self.assertEqual(reason, "legacy_writer_process_present")

    def test_red_inflight_service(self):
        allowed, reason, _ = self.run_guard({
            "pool-publish.service": {"ActiveState": "activating"}})
        self.assertFalse(allowed)
        self.assertEqual(reason, "old_service_not_drained")

    def test_red_nonzero_pid(self):
        allowed, reason, _ = self.run_guard({
            "pool-sync.service": {"MainPID": "981"}})
        self.assertFalse(allowed)
        self.assertEqual(reason, "old_service_pid_present")

    def test_red_sigkill_is_not_success(self):
        allowed, reason, _ = self.run_guard({
            "pool-publish.service": {"Result": "signal"}})
        self.assertFalse(allowed)
        self.assertEqual(reason, "old_service_result_not_success")

    def test_red_unknown_or_missing_unit(self):
        allowed, reason, _ = self.run_guard({
            "pool-sync.service": {"LoadState": "not-found"}})
        self.assertFalse(allowed)
        self.assertEqual(reason, "service_not_loaded")

    def test_red_queued_start(self):
        allowed, reason, _ = self.run_guard({
            "pool-publish.timer": {"Job": "124/start"}})
        self.assertFalse(allowed)
        self.assertEqual(reason, "old_timer_has_job")

    def test_red_inspection_failure(self):
        for kwargs in ({"show_error": True}, {"process_error": True}):
            with self.subTest(kwargs=kwargs):
                allowed, reason, _ = self.run_guard(**kwargs)
                self.assertFalse(allowed)
                self.assertEqual(reason, "preflight_inspection_failed")

if __name__ == "__main__":
    unittest.main()
