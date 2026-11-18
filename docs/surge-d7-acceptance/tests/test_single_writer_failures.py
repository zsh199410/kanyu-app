#!/usr/bin/env python3
"""Failure-path tests for the single-writer lock (task G).

Every test here drives a refusal or a fault and asserts the fail-closed
outcome: no write, no partial file, no lost crawl/test data, lock
released. Complements tests/test_single_writer.py (main paths).

Run:
    cd ~/workspace/p2p3-dual/surge-d7-acceptance
    python3 -m pytest tests/test_single_writer_failures.py -v

Fixtures use only 192.0.2.0/24 and "test123" -- no real node URIs,
passwords, tokens, or egress IPs anywhere.
"""

import hashlib
import importlib.util
import multiprocessing as mp
import os
import sqlite3
import tempfile
import time
import unittest
from unittest.mock import patch

_HERE = os.path.dirname(os.path.abspath(__file__))
_MOD_PATH = os.path.normpath(
    os.path.join(_HERE, "..", "single-writer", "single_writer.py"))

_spec = importlib.util.spec_from_file_location("single_writer", _MOD_PATH)
sw = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(sw)

from test_single_writer import (  # noqa: E402
    FakeGate, PublishEnv, db_counts, make_payload, read_file, sha,
    _holding_worker)


class TestSingleWriterFailures(unittest.TestCase):
    def test_production_default_requires_masked_legacy_services(self):
        # Inject a failing proof, assert that the actual default publish
        # requests the stronger masked mode, never merely 'disabled'.
        with tempfile.TemporaryDirectory() as tmp:
            env = PublishEnv(tmp)
            gate = FakeGate()
            failure = (False, [{"check": "service_masked", "ok": False,
                                "detail": "disabled"}])
            with patch.object(sw, "legacy_ban_proof", return_value=failure) as proof:
                with self.assertRaises(sw.PublishRefused) as cm:
                    sw.publish(
                        lock_path=env.lock, served_path=env.served,
                        staging_path=env.staging,
                        candidate_bytes=make_payload("NEW"),
                        expected_current_sha=env.initial_sha,
                        db_path=env.db, guard_check=gate.guard_check,
                        stop_check=gate.stop_check)
            proof.assert_called_once_with(require_masked_services=True)
            self.assertIn("legacy_ban_unproven", cm.exception.reason)
            self.assertEqual(read_file(env.served), env.initial)

    # Lock contention with a short timeout refuses loudly (no silent queue).
    def test_f01_lock_timeout_is_fail_closed(self):
        with tempfile.TemporaryDirectory() as tmp:
            env = PublishEnv(tmp)
            gate = FakeGate()
            ctx = mp.get_context("fork")
            ready = ctx.Queue()
            release = ctx.Queue()
            holder = ctx.Process(target=_holding_worker,
                                 args=(env.lock, ready, release))
            holder.start()
            try:
                self.assertIsNotNone(ready.get(timeout=10))
                start = time.monotonic()
                with self.assertRaises(sw.PublishRefused) as cm:
                    sw.publish(lock_path=env.lock, served_path=env.served,
                               staging_path=env.staging,
                               candidate_bytes=make_payload("T"),
                               expected_current_sha=env.initial_sha,
                               db_path=env.db,
                               guard_check=gate.guard_check,
                               ban_proof_fn=gate.ban_proof_fn,
                               stop_check=gate.stop_check,
                               lock_timeout=0.5)
                elapsed = time.monotonic() - start
                self.assertEqual(cm.exception.reason, "lock_timeout")
                self.assertLess(elapsed, 5.0,
                                "timeout must bound the wait, not hang")
                self.assertEqual(read_file(env.served), env.initial)
                self.assertEqual(db_counts(env.db), (50, 50, 0))
            finally:
                try:
                    release.put("go")
                except Exception:  # noqa: BLE001 - holder may be gone
                    pass
                holder.join(timeout=10)
                if holder.is_alive():
                    holder.terminate()
                    holder.join(timeout=5)

    # Stale candidate (built against an old served version) is refused.
    def test_f02_stale_candidate_is_refused(self):
        with tempfile.TemporaryDirectory() as tmp:
            env = PublishEnv(tmp)
            gate = FakeGate()
            other = make_payload("OTHER")
            sw.publish(**env.kwargs(gate, other))
            stale = make_payload("STALE")
            with self.assertRaises(sw.PublishRefused) as cm:
                sw.publish(lock_path=env.lock, served_path=env.served,
                           staging_path=env.staging, candidate_bytes=stale,
                           expected_current_sha=env.initial_sha,
                           db_path=env.db,
                           guard_check=gate.guard_check,
                           ban_proof_fn=gate.ban_proof_fn,
                           stop_check=gate.stop_check)
            self.assertEqual(cm.exception.reason, "stale_current_version")
            self.assertEqual(read_file(env.served), other)
            self.assertEqual(db_counts(env.db), (50, 50, 1))

    # Legacy writer re-entering during the window: post-write re-check
    # restores the previous files and drops only the own record.
    def test_f03_legacy_reentry_after_write_is_rolled_back(self):
        with tempfile.TemporaryDirectory() as tmp:
            env = PublishEnv(tmp)

            class FlippingGate(FakeGate):
                def __init__(self):
                    super().__init__()
                    self.calls = 0

                def guard_check(self):
                    self.calls += 1
                    if self.calls == 1:
                        return True, "legacy_writers_drained", "system"
                    # The legacy writer came back between the pre-check
                    # and the post-write re-check.
                    return False, "legacy_writer_process_present", "pid:1234"

            gate = FlippingGate()
            cand = make_payload("NEW")
            with self.assertRaises(sw.PublishRefused) as cm:
                sw.publish(**env.kwargs(gate, cand))
            self.assertTrue(cm.exception.reason.startswith(
                "legacy_writer_reentered:"))
            self.assertEqual(read_file(env.served), env.initial)
            self.assertEqual(read_file(env.staging), env.initial)
            self.assertEqual(db_counts(env.db), (50, 50, 0))
            self.assertEqual(gate.calls, 2, "guard must run twice per publish")

    # Same re-entry, but caught by the ban proof on the post-write check.
    def test_f04_ban_proof_failure_after_write_is_rolled_back(self):
        with tempfile.TemporaryDirectory() as tmp:
            env = PublishEnv(tmp)

            class FlippingBan(FakeGate):
                def __init__(self):
                    super().__init__()
                    self.calls = 0

                def ban_proof_fn(self):
                    self.calls += 1
                    if self.calls == 1:
                        return True, []
                    return False, [{"check": "timer_disabled:pool-publish.timer",
                                    "ok": False, "detail": "enabled"}]

            gate = FlippingBan()
            with self.assertRaises(sw.PublishRefused) as cm:
                sw.publish(**env.kwargs(gate, make_payload("NEW")))
            self.assertTrue(cm.exception.reason.startswith(
                "legacy_writer_reentered:"))
            self.assertEqual(read_file(env.served), env.initial)
            self.assertEqual(db_counts(env.db), (50, 50, 0))

    # Guard module missing entirely: publish refuses, writes nothing.
    def test_f05_guard_unavailable_is_fail_closed(self):
        with tempfile.TemporaryDirectory() as tmp:
            env = PublishEnv(tmp)
            real_load = sw.load_guard
            sw.load_guard = lambda: None
            try:
                with self.assertRaises(sw.PublishRefused) as cm:
                    sw.publish(lock_path=env.lock, served_path=env.served,
                               staging_path=env.staging,
                               candidate_bytes=make_payload("N"),
                               expected_current_sha=env.initial_sha,
                               db_path=env.db)
                self.assertEqual(cm.exception.reason, "guard_unavailable")
            finally:
                sw.load_guard = real_load
            self.assertEqual(read_file(env.served), env.initial)
            self.assertEqual(db_counts(env.db), (50, 50, 0))

    # Ban proof: each broken link of the chain fails it (fail-closed).
    def test_f06_ban_proof_rejects_each_broken_link(self):
        base_timer = {
            "LoadState": "loaded", "UnitFileState": "disabled",
            "ActiveState": "inactive", "SubState": "dead",
            "MainPID": "0", "ControlPID": "0",
            "Result": "success", "Job": "",
        }
        base_service = dict(base_timer, UnitFileState="disabled")
        benign_ps = ["    1 /sbin/init",
                     "  900 /usr/bin/python3 /opt/free-node-program/pool.py"]

        def run(units, ps_rows):
            return sw.legacy_ban_proof(
                show=lambda u: dict(units[u]),
                processes=lambda: list(ps_rows))

        def good_units():
            units = {}
            for u in ("pool-publish.timer", "pool-sync.timer"):
                units[u] = dict(base_timer)
            for u in ("pool-publish.service", "pool-sync.service"):
                units[u] = dict(base_service)
            return units

        proven, _ = run(good_units(), benign_ps)
        self.assertTrue(proven, "fully drained + masked must prove the ban")

        cases = []
        units = good_units()
        units["pool-publish.timer"]["UnitFileState"] = "enabled"
        cases.append(("timer re-enabled", units))
        units = good_units()
        units["pool-sync.timer"]["ActiveState"] = "active"
        cases.append(("timer active", units))
        units = good_units()
        units["pool-publish.timer"]["Job"] = "42"
        cases.append(("timer has job", units))
        units = good_units()
        units["pool-sync.service"]["SubState"] = "running"
        units["pool-sync.service"]["ActiveState"] = "active"
        units["pool-sync.service"]["MainPID"] = "1234"
        cases.append(("service running", units))
        units = good_units()
        units["pool-publish.service"]["Result"] = "signal"
        cases.append(("service killed by signal", units))
        units = good_units()
        units["pool-sync.service"]["UnitFileState"] = "enabled"
        cases.append(("service re-enabled (not disabled)", units))
        units = good_units()
        units["pool-publish.service"]["LoadState"] = "not-found"
        cases.append(("service not loaded", units))
        units = good_units()
        units["pool-sync.service"]["UnitFileState"] = "masked"
        cases.append(("service masked (LoadState=masked, guard conflict)",
                      units))
        for name, units_case in cases:
            proven, evidence = run(units_case, benign_ps)
            self.assertFalse(proven, "ban must fail: %s" % name)
            self.assertTrue(any(not e["ok"] for e in evidence), name)

        # Legacy writer process visible in ps breaks the proof even when
        # every unit looks drained.
        proven, evidence = run(
            good_units(),
            benign_ps + [" 1234 /usr/bin/python3 "
                         "/opt/free-node-program/pool.cli publish"])
        self.assertFalse(proven)
        self.assertEqual(evidence[-1]["check"], "no_legacy_process")
        proven, _ = run(
            good_units(),
            benign_ps + [" 2345 /bin/bash /opt/free-node-program/pool-sync.sh"])
        self.assertFalse(proven)
        # Masked service: fails the DEFAULT chain at service_disabled
        # (on real systemd it additionally fails the verbatim guard's
        # LoadState check -- a masked unit reports LoadState=masked).
        units = good_units()
        units["pool-sync.service"]["UnitFileState"] = "masked"
        proven, evidence = run(units, benign_ps)
        self.assertFalse(proven)
        self.assertEqual([e["check"] for e in evidence if not e["ok"]],
                         ["service_disabled:pool-sync.service"])
        # ...but the opt-in masked variant accepts exactly that state
        # (for callers that do NOT run the verbatim guard alongside):
        # both services masked this time, since the variant requires it
        # of every service.
        units = good_units()
        for u in ("pool-publish.service", "pool-sync.service"):
            units[u]["UnitFileState"] = "masked"
        proven, _ = sw.legacy_ban_proof(
            show=lambda u: dict(units[u]),
            processes=lambda: list(benign_ps),
            require_masked_services=True)
        self.assertTrue(proven)
        # And the opt-in masked variant rejects a merely-disabled service.
        proven, _ = sw.legacy_ban_proof(
            show=lambda u: dict(good_units()[u]),
            processes=lambda: list(benign_ps),
            require_masked_services=True)
        self.assertFalse(proven)
        # Real systemd reports LoadState="masked" for a masked unit; the
        # opt-in variant must accept that as loaded (the verbatim guard
        # does not -- that is the documented S2e conflict).
        units = good_units()
        for u in ("pool-publish.service", "pool-sync.service"):
            units[u]["UnitFileState"] = "masked"
            units[u]["LoadState"] = "masked"
        proven, _ = sw.legacy_ban_proof(
            show=lambda u: dict(units[u]),
            processes=lambda: list(benign_ps),
            require_masked_services=True)
        self.assertTrue(proven)
        proven, _ = sw.legacy_ban_proof(
            show=lambda u: dict(units[u]),
            processes=lambda: list(benign_ps))
        self.assertFalse(proven, "default chain must refuse masked units")
        # Inspection failure (systemctl down) also fails the proof.
        proven, _ = sw.legacy_ban_proof(
            show=lambda u: (_ for _ in ()).throw(RuntimeError("command_failed")),
            processes=lambda: list(benign_ps))
        self.assertFalse(proven)

    # atomic_write: a failed write leaves the destination untouched and
    # no temp file behind.
    def test_f07_atomic_write_failure_leaves_destination_intact(self):
        with tempfile.TemporaryDirectory() as tmp:
            dest = os.path.join(tmp, "served.txt")
            original = make_payload("ORIG")
            with open(dest, "wb") as fh:
                fh.write(original)
            # Destination directory removed mid-call path: the temp file
            # cannot be created, so nothing is written at all.
            with self.assertRaises(FileNotFoundError):
                sw.atomic_write(os.path.join(tmp, "gone", "served.txt"),
                                make_payload("NEW"))
            self.assertEqual(read_file(dest), original)
            self.assertEqual([f for f in os.listdir(tmp)
                              if ".tmp-" in f], [])
            # A successful atomic write replaces content wholesale and
            # leaves no temp file.
            sw.atomic_write(dest, make_payload("NEW2"))
            self.assertEqual(read_file(dest), make_payload("NEW2"))
            self.assertEqual([f for f in os.listdir(tmp)
                              if ".tmp-" in f], [])

    # Double-acquire of the same lock object is refused, not deadlocked.
    def test_f08_reentrant_acquire_is_refused(self):
        with tempfile.TemporaryDirectory() as tmp:
            lock_path = os.path.join(tmp, "pool.lock")
            lock = sw.SingleWriterLock(lock_path, timeout=1.0)
            lock.acquire()
            try:
                with self.assertRaises(sw.PublishRefused) as cm:
                    lock.acquire()
                self.assertEqual(cm.exception.reason, "lock_already_held")
            finally:
                lock.release()
            # After release the same object can acquire again.
            lock.acquire()
            lock.release()

    # Rollback never deletes a pre-existing publish record or any
    # crawl/test row, even across repeated faults.
    def test_f09_repeated_faults_never_touch_other_rows(self):
        with tempfile.TemporaryDirectory() as tmp:
            env = PublishEnv(tmp)
            gate = FakeGate()
            good = make_payload("GOOD")
            receipt = sw.publish(**env.kwargs(gate, good))
            for i in range(3):
                with self.assertRaises(RuntimeError):
                    sw.publish(lock_path=env.lock, served_path=env.served,
                               staging_path=env.staging,
                               candidate_bytes=make_payload("BAD%d" % i),
                               expected_current_sha=receipt["payload_sha"],
                               db_path=env.db,
                               guard_check=gate.guard_check,
                               ban_proof_fn=gate.ban_proof_fn,
                               stop_check=gate.stop_check,
                               fault_after_staging=True)
            self.assertEqual(read_file(env.served), good)
            self.assertEqual(read_file(env.staging), good)
            self.assertEqual(db_counts(env.db), (50, 50, 1))
            conn = sqlite3.connect(env.db)
            rows = conn.execute(
                "SELECT payload_sha FROM publish_log").fetchall()
            conn.close()
            self.assertEqual(rows, [(sha(good),)])


if __name__ == "__main__":
    unittest.main(verbosity=2)
