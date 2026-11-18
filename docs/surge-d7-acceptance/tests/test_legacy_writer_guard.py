#!/usr/bin/env python3
"""Isolated verification for the reused PR #80 legacy-writer-guard (task C).

Covers the 8 supplementary checks required by the execution order, section 4.
All systemctl / ps outputs are MOCKED - nothing here stops a real service,
kills a real process, or touches production. The guard under test is the
verbatim PR #80 copy at ../legacy-writer-guard/legacy-writer-guard.py
(head eaa520232af4336e03e83dd4d2f98cac3d8f2d4b); its check() accepts
injected `show` / `processes` backends, which is what every test below uses.

Run:
    cd ~/workspace/p2p3-dual/surge-d7-acceptance
    python3 -m pytest tests/test_legacy_writer_guard.py -v

No real node URIs, passwords, tokens or egress IPs appear anywhere here.
"""

import hashlib
import importlib.util
import os
import sys
import tempfile
import threading
import time
import unittest

_HERE = os.path.dirname(os.path.abspath(__file__))
_GUARD_PATH = os.path.normpath(
    os.path.join(_HERE, "..", "legacy-writer-guard", "legacy-writer-guard.py")
)

_spec = importlib.util.spec_from_file_location("legacy_writer_guard", _GUARD_PATH)
guard = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(guard)

TIMERS = ("pool-publish.timer", "pool-sync.timer")
SERVICES = ("pool-publish.service", "pool-sync.service")

# Benign ps rows that must never trip the guard (no legacy writer in them).
BENIGN_PS_ROWS = [
    "    1 /sbin/init",
    "  412 /usr/lib/systemd/systemd-journald",
    "  900 /usr/bin/python3 /opt/free-node-program/pool.py",
    "  901 /usr/bin/nginx -g daemon off;",
]


def drained_timer_state():
    return {
        "LoadState": "loaded",
        "UnitFileState": "disabled",
        "ActiveState": "inactive",
        "SubState": "dead",
        "MainPID": "0",
        "ControlPID": "0",
        "Result": "success",
        "Job": "",
    }


def drained_service_state():
    return {
        "LoadState": "loaded",
        "UnitFileState": "disabled",
        "ActiveState": "inactive",
        "SubState": "dead",
        "MainPID": "0",
        "ControlPID": "0",
        "Result": "success",
        "Job": "",
    }


def drained_units():
    units = {}
    for unit in TIMERS:
        units[unit] = drained_timer_state()
    for unit in SERVICES:
        units[unit] = drained_service_state()
    return units


class FakeSystem:
    """Injectable mock backend for systemctl show + ps.

    `show(unit)` mimics the parsed dict of `systemctl show --property=...`.
    `processes()` mimics `ps -eo pid=,args=` lines. Either side can be made
    to fail (raising like the real guard's _command does on non-zero exit)
    or to change state between calls, to simulate restarts / races.
    """

    def __init__(self, units=None, ps_rows=None):
        self.units = units if units is not None else drained_units()
        self.ps_rows = list(ps_rows) if ps_rows is not None else list(BENIGN_PS_ROWS)
        self.fail_show_with = None   # exception instance to raise from show()
        self.fail_ps_with = None     # exception instance to raise from processes()
        self.show_calls = 0
        self.ps_calls = 0

    def show(self, unit):
        self.show_calls += 1
        if self.fail_show_with is not None:
            raise self.fail_show_with
        return dict(self.units[unit])

    def processes(self):
        self.ps_calls += 1
        if self.fail_ps_with is not None:
            raise self.fail_ps_with
        return list(self.ps_rows)


def sha256_file(path):
    with open(path, "rb") as fh:
        return hashlib.sha256(fh.read()).hexdigest()


def publish_if_allowed(check_fn, served_path, new_content):
    """Test-side simulation of the production wrapper contract.

    The real wrapper must call the guard first and write the served file
    ONLY when the guard allows. Returns (allowed, reason, subject).
    """
    allowed, reason, subject = check_fn()
    if allowed:
        with open(served_path, "w", encoding="utf-8") as fh:
            fh.write(new_content)
    return allowed, reason, subject


class TestLegacyWriterGuard(unittest.TestCase):
    # 1. Old unlocked writer present -> refuse.
    def test_01_legacy_writer_present_is_refused(self):
        # (a) Writer process visible in ps while units look drained.
        fake = FakeSystem(ps_rows=BENIGN_PS_ROWS + [
            " 1234 /usr/bin/python3 /opt/free-node-program/pool.cli publish",
        ])
        allowed, reason, subject = guard.check(show=fake.show, processes=fake.processes)
        self.assertFalse(allowed)
        self.assertEqual(reason, "legacy_writer_process_present")
        self.assertEqual(subject, "pid:1234")

        # (b) Old syncer process visible.
        fake = FakeSystem(ps_rows=BENIGN_PS_ROWS + [
            " 2345 /bin/bash /opt/free-node-program/pool-sync.sh",
        ])
        allowed, reason, subject = guard.check(show=fake.show, processes=fake.processes)
        self.assertFalse(allowed)
        self.assertEqual(reason, "legacy_writer_process_present")
        self.assertEqual(subject, "pid:2345")

        # (c) Old service still running (unit state, no ps row needed).
        units = drained_units()
        units["pool-publish.service"].update({
            "ActiveState": "active", "SubState": "running",
            "MainPID": "1234", "ControlPID": "0",
        })
        fake = FakeSystem(units=units)
        allowed, reason, subject = guard.check(show=fake.show, processes=fake.processes)
        self.assertFalse(allowed)
        self.assertEqual(reason, "old_service_not_drained")
        self.assertEqual(subject, "pool-publish.service")

    # 2. Old writer stopped and drained -> allow.
    def test_02_drained_writers_are_allowed(self):
        fake = FakeSystem()
        allowed, reason, subject = guard.check(show=fake.show, processes=fake.processes)
        self.assertTrue(allowed)
        self.assertEqual(reason, "legacy_writers_drained")
        self.assertEqual(subject, "system")
        # All four units were inspected plus one ps scan.
        self.assertEqual(fake.show_calls, 4)
        self.assertEqual(fake.ps_calls, 1)

    # 3. SIGTERM / SIGKILL negative cases (writer killed by signal -> refuse).
    def test_03_signal_terminated_writer_is_refused(self):
        # (a) SIGTERM: systemd records Result=signal, SubState=failed.
        #     The process is gone from ps, but the unit state still refuses.
        units = drained_units()
        units["pool-publish.service"].update({
            "ActiveState": "inactive", "SubState": "failed",
            "MainPID": "0", "ControlPID": "0",
            "Result": "signal", "Job": "",
        })
        fake = FakeSystem(units=units)
        allowed, reason, subject = guard.check(show=fake.show, processes=fake.processes)
        self.assertFalse(allowed)
        self.assertEqual(reason, "old_service_not_drained")
        self.assertEqual(subject, "pool-publish.service")

        # (b) SIGKILL: same signal result, on the sync service this time.
        units = drained_units()
        units["pool-sync.service"].update({
            "ActiveState": "inactive", "SubState": "failed",
            "MainPID": "0", "ControlPID": "0",
            "Result": "signal", "Job": "",
        })
        fake = FakeSystem(units=units)
        allowed, reason, subject = guard.check(show=fake.show, processes=fake.processes)
        self.assertFalse(allowed)
        self.assertEqual(reason, "old_service_not_drained")

        # (c) Subtle case: SubState back to dead but Result still signal
        #     (e.g. unit reset without a clean run). Must still refuse,
        #     via the Result check, not via the drain check.
        units = drained_units()
        units["pool-publish.service"].update({
            "ActiveState": "inactive", "SubState": "dead",
            "MainPID": "0", "ControlPID": "0",
            "Result": "signal", "Job": "",
        })
        fake = FakeSystem(units=units)
        allowed, reason, subject = guard.check(show=fake.show, processes=fake.processes)
        self.assertFalse(allowed)
        self.assertEqual(reason, "old_service_result_not_success")
        self.assertEqual(subject, "pool-publish.service")

        # (d) A clean exit (Result=success, dead, no PIDs) is the only
        #     signal-free terminal state that passes - covered by test 2;
        #     here assert a non-success Result never passes even with dead PIDs.
        for bad_result in ("signal", "exit-code", "timeout"):
            units = drained_units()
            units["pool-sync.service"]["Result"] = bad_result
            fake = FakeSystem(units=units)
            allowed, reason, _ = guard.check(show=fake.show, processes=fake.processes)
            self.assertFalse(allowed, "Result=%s must refuse" % bad_result)
            self.assertEqual(reason, "old_service_result_not_success")

    # 4. A systemd Job queued -> refuse.
    def test_04_pending_systemd_job_is_refused(self):
        # (a) Job pending on a timer.
        units = drained_units()
        units["pool-sync.timer"]["Job"] = "1234"
        fake = FakeSystem(units=units)
        allowed, reason, subject = guard.check(show=fake.show, processes=fake.processes)
        self.assertFalse(allowed)
        self.assertEqual(reason, "old_timer_has_job")
        self.assertEqual(subject, "pool-sync.timer")

        # (b) Job pending on a service.
        units = drained_units()
        units["pool-publish.service"]["Job"] = "5678"
        fake = FakeSystem(units=units)
        allowed, reason, subject = guard.check(show=fake.show, processes=fake.processes)
        self.assertFalse(allowed)
        self.assertEqual(reason, "old_service_has_job")
        self.assertEqual(subject, "pool-publish.service")

    # 5. systemctl / ps failure -> refuse (fail closed).
    def test_05_inspection_failure_is_refused(self):
        # (a) systemctl fails (non-zero exit -> RuntimeError in real guard).
        fake = FakeSystem()
        fake.fail_show_with = RuntimeError("command_failed")
        allowed, reason, subject = guard.check(show=fake.show, processes=fake.processes)
        self.assertFalse(allowed)
        self.assertEqual(reason, "preflight_inspection_failed")
        self.assertEqual(subject, "system")

        # (b) systemctl binary missing / OSError.
        fake = FakeSystem()
        fake.fail_show_with = OSError("systemctl not found")
        allowed, reason, _ = guard.check(show=fake.show, processes=fake.processes)
        self.assertFalse(allowed)
        self.assertEqual(reason, "preflight_inspection_failed")

        # (c) systemctl times out.
        import subprocess
        fake = FakeSystem()
        fake.fail_show_with = subprocess.TimeoutExpired(cmd="systemctl", timeout=8)
        allowed, reason, _ = guard.check(show=fake.show, processes=fake.processes)
        self.assertFalse(allowed)
        self.assertEqual(reason, "preflight_inspection_failed")

        # (d) ps fails after units looked drained - still refuse.
        fake = FakeSystem()
        fake.fail_ps_with = RuntimeError("command_failed")
        allowed, reason, _ = guard.check(show=fake.show, processes=fake.processes)
        self.assertFalse(allowed)
        self.assertEqual(reason, "preflight_inspection_failed")

        # (e) ps returns a non-list (corrupt output) - refuse.
        allowed, reason, subject = guard.check(
            show=FakeSystem().show, processes=lambda: "not-a-list")
        self.assertFalse(allowed)
        self.assertEqual(reason, "process_scan_invalid")

    # 6. Negative case: writer manually restarted after drain -> re-check refuses.
    def test_06_manual_restart_after_drain_is_refused_on_recheck(self):
        fake = FakeSystem()
        allowed, _, _ = guard.check(show=fake.show, processes=fake.processes)
        self.assertTrue(allowed, "first check after drain must pass")

        # Administrator manually restarts the old writer: timer re-enabled
        # and active again, writer process back in ps.
        fake.units["pool-publish.timer"].update({
            "UnitFileState": "enabled", "ActiveState": "active",
        })
        fake.ps_rows = list(BENIGN_PS_ROWS) + [
            " 1234 /usr/bin/python3 /opt/free-node-program/pool.cli publish",
        ]
        allowed, reason, subject = guard.check(show=fake.show, processes=fake.processes)
        self.assertFalse(allowed)
        self.assertEqual(reason, "old_timer_not_disabled")
        self.assertEqual(subject, "pool-publish.timer")

        # Variant: only the process comes back (timer state untouched).
        # The ps scan alone must catch it on re-check.
        fake2 = FakeSystem()
        self.assertTrue(guard.check(show=fake2.show, processes=fake2.processes)[0])
        fake2.ps_rows = list(BENIGN_PS_ROWS) + [
            " 2345 /bin/bash /opt/free-node-program/pool-sync.sh",
        ]
        allowed, reason, subject = guard.check(show=fake2.show, processes=fake2.processes)
        self.assertFalse(allowed)
        self.assertEqual(reason, "legacy_writer_process_present")

    # 7. On guard refusal the HTTP served SHA is unchanged (no write happens).
    def test_07_refusal_leaves_served_sha_unchanged(self):
        with tempfile.TemporaryDirectory() as tmp:
            served = os.path.join(tmp, "served.txt")
            original_content = "served-snapshot v1 (mock content, no real nodes)\n"
            with open(served, "w", encoding="utf-8") as fh:
                fh.write(original_content)
            sha_before = sha256_file(served)

            # (a) Guard refuses (legacy writer present): wrapper must not write.
            fake = FakeSystem(ps_rows=BENIGN_PS_ROWS + [
                " 1234 /usr/bin/python3 /opt/free-node-program/pool.cli publish",
            ])
            allowed, reason, _ = publish_if_allowed(
                lambda: guard.check(show=fake.show, processes=fake.processes),
                served, "served-snapshot v2 (must NOT land)\n")
            self.assertFalse(allowed)
            self.assertEqual(reason, "legacy_writer_process_present")
            self.assertEqual(sha256_file(served), sha_before,
                             "served SHA must be unchanged after refusal")
            with open(served, encoding="utf-8") as fh:
                self.assertEqual(fh.read(), original_content)

            # (b) Guard refuses (inspection failure): also no write.
            fake = FakeSystem()
            fake.fail_show_with = RuntimeError("command_failed")
            allowed, reason, _ = publish_if_allowed(
                lambda: guard.check(show=fake.show, processes=fake.processes),
                served, "served-snapshot v3 (must NOT land)\n")
            self.assertFalse(allowed)
            self.assertEqual(reason, "preflight_inspection_failed")
            self.assertEqual(sha256_file(served), sha_before)

            # (c) Positive control: drained guard allows, and then the
            #     write lands and the SHA changes. Proves the harness can
            #     tell a write from a non-write.
            fake = FakeSystem()
            allowed, reason, _ = publish_if_allowed(
                lambda: guard.check(show=fake.show, processes=fake.processes),
                served, "served-snapshot v2 (allowed write)\n")
            self.assertTrue(allowed)
            self.assertEqual(reason, "legacy_writers_drained")
            self.assertNotEqual(sha256_file(served), sha_before)
            with open(served, encoding="utf-8") as fh:
                self.assertEqual(fh.read(), "served-snapshot v2 (allowed write)\n")

    # 8. No old/new dual-write under concurrent contention.
    def test_08_concurrent_contention_allows_only_one_writer(self):
        # (a) Guard alone is a point-in-time check: two concurrent checks
        #     against the same drained mock BOTH pass. This documents the
        #     guard's limit - it cannot by itself serialize writers.
        #     (Deterministic: the mock has no shared state to flip.)
        fake = FakeSystem()
        results = []
        barrier = threading.Barrier(2)

        def _check_only():
            barrier.wait(timeout=5)
            results.append(guard.check(show=fake.show, processes=fake.processes)[0])

        threads = [threading.Thread(target=_check_only) for _ in range(2)]
        for t in threads:
            t.start()
        for t in threads:
            t.join(timeout=10)
        self.assertEqual(results, [True, True],
                         "point-in-time guard alone passes concurrently - "
                         "a lock/gate is required, see part (b)")

        # (b) With a single-writer gate held across guard-check + publish,
        #     concurrent attempts serialize: at most one writer is ever
        #     active at the same instant, and every publish that runs does
        #     so under the gate. The gate models the production wrapper's
        #     lock (ExecStartPre + wrapper); the guard supplies the
        #     drain evidence, the gate supplies the serialization.
        gate = threading.Lock()
        active = {"count": 0, "max": 0}
        active_lock = threading.Lock()
        publishes = []
        publish_lock = threading.Lock()
        errors = []

        def _gated_attempt(worker_id):
            try:
                with gate:
                    fake_local = FakeSystem()
                    allowed, reason, _ = guard.check(
                        show=fake_local.show, processes=fake_local.processes)
                    self.assertTrue(allowed, reason)
                    with active_lock:
                        active["count"] += 1
                        active["max"] = max(active["max"], active["count"])
                    try:
                        time.sleep(0.01)  # simulate the write window
                    finally:
                        with active_lock:
                            active["count"] -= 1
                    with publish_lock:
                        publishes.append(worker_id)
            except Exception as exc:  # noqa: BLE001 - collected, asserted below
                with publish_lock:
                    errors.append(exc)

        workers = [threading.Thread(target=_gated_attempt, args=(i,)) for i in range(8)]
        for t in workers:
            t.start()
        for t in workers:
            t.join(timeout=15)
        self.assertEqual(errors, [])
        self.assertEqual(sorted(publishes), list(range(8)),
                         "all 8 gated attempts must publish exactly once")
        self.assertEqual(active["max"], 1,
                         "at most one writer may be active at any instant")
        self.assertEqual(active["count"], 0, "no writer left active")

        # (c) Race inside a single check: the writer starts AFTER the unit
        #     checks but BEFORE the ps scan. The ps scan must still catch it.
        fake = FakeSystem()

        def _racing_processes():
            fake.ps_rows = list(BENIGN_PS_ROWS) + [
                " 1234 /usr/bin/python3 /opt/free-node-program/pool.cli publish",
            ]
            return list(fake.ps_rows)

        allowed, reason, subject = guard.check(show=fake.show, processes=_racing_processes)
        self.assertFalse(allowed)
        self.assertEqual(reason, "legacy_writer_process_present")
        self.assertEqual(subject, "pid:1234")


if __name__ == "__main__":
    unittest.main(verbosity=2)
