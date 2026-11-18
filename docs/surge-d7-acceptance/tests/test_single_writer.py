#!/usr/bin/env python3
"""Local tests for the single-writer lock (task G, main paths).

Covers verification points 1-4 and 6-8 with real multi-process
concurrency (``multiprocessing``, fork): flock is a per-process kernel
lock, so thread-only tests could not prove cross-process exclusion.

Run:
    cd ~/workspace/p2p3-dual/surge-d7-acceptance
    python3 -m pytest tests/test_single_writer.py -v

Fixtures use only 192.0.2.0/24 and "test123" -- no real node URIs,
passwords, tokens, or egress IPs anywhere.
"""

import hashlib
import importlib.util
import multiprocessing as mp
import os
import signal
import sqlite3
import subprocess
import sys
import tempfile
import threading
import time
import unittest

_HERE = os.path.dirname(os.path.abspath(__file__))
_MOD_PATH = os.path.normpath(
    os.path.join(_HERE, "..", "single-writer", "single_writer.py"))
_GUARD_PATH = os.path.normpath(
    os.path.join(_HERE, "..", "legacy-writer-guard", "legacy-writer-guard.py"))

_spec = importlib.util.spec_from_file_location("single_writer", _MOD_PATH)
sw = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(sw)

_spec_g = importlib.util.spec_from_file_location("legacy_writer_guard",
                                                 _GUARD_PATH)
guard = importlib.util.module_from_spec(_spec_g)
_spec_g.loader.exec_module(guard)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def read_file(path):
    with open(path, "rb") as fh:
        return fh.read()


def make_payload(tag, lines=30):
    """Deterministic fake pool payload: 30 complete lines, no real URIs."""
    out = []
    for i in range(1, lines + 1):
        out.append("test-node-%s-%02d 192.0.2.%d test123"
                   % (tag, i, (i % 250) + 1))
    return ("\n".join(out) + "\n").encode("utf-8")


def seed_db(db_path, crawl=50, test=50):
    conn = sqlite3.connect(db_path)
    conn.execute("CREATE TABLE IF NOT EXISTS crawl_log"
                 " (id INTEGER PRIMARY KEY AUTOINCREMENT,"
                 "  source TEXT, detail TEXT)")
    conn.execute("CREATE TABLE IF NOT EXISTS test_log"
                 " (id INTEGER PRIMARY KEY AUTOINCREMENT,"
                 "  node_ref TEXT, detail TEXT)")
    for i in range(crawl):
        conn.execute("INSERT INTO crawl_log (source, detail) VALUES (?, ?)",
                     ("crawl-src-%d" % i, "crawl-detail-%d" % i))
    for i in range(test):
        conn.execute("INSERT INTO test_log (node_ref, detail) VALUES (?, ?)",
                     ("test-node-%d" % i, "test-detail-%d" % i))
    conn.commit()
    conn.close()


def db_counts(db_path):
    conn = sqlite3.connect(db_path)
    try:
        crawl = conn.execute("SELECT COUNT(*) FROM crawl_log").fetchone()[0]
        test = conn.execute("SELECT COUNT(*) FROM test_log").fetchone()[0]
        try:
            pub = conn.execute("SELECT COUNT(*) FROM publish_log").fetchone()[0]
        except sqlite3.OperationalError:
            pub = 0
        return crawl, test, pub
    finally:
        conn.close()


class FakeGate:
    """Injectable guard + ban-proof + STOP backend for the tests."""

    def __init__(self, guard_allowed=True, ban_proven=True, stopped=False):
        self.guard_allowed = guard_allowed
        self.ban_proven = ban_proven
        self.stopped = stopped
        self.guard_calls = 0
        self.ban_calls = 0

    def guard_check(self):
        self.guard_calls += 1
        if self.guard_allowed:
            return True, "legacy_writers_drained", "system"
        return False, "old_timer_not_disabled", "pool-publish.timer"

    def ban_proof_fn(self):
        self.ban_calls += 1
        if self.ban_proven:
            return True, [{"check": "timer_disabled:pool-publish.timer",
                           "ok": True, "detail": "disabled"}]
        return False, [{"check": "timer_disabled:pool-publish.timer",
                        "ok": False, "detail": "enabled"}]

    def stop_check(self):
        return self.stopped


class PublishEnv:
    """A throwaway publish workspace (lock + served + staging + db)."""

    def __init__(self, tmp):
        self.dir = tmp
        self.lock = os.path.join(tmp, "pool.lock")
        self.served = os.path.join(tmp, "served.txt")
        self.staging = os.path.join(tmp, "staging.txt")
        self.db = os.path.join(tmp, "pool.sqlite3")
        self.initial = make_payload("init")
        with open(self.served, "wb") as fh:
            fh.write(self.initial)
        with open(self.staging, "wb") as fh:
            fh.write(self.initial)
        seed_db(self.db)

    @property
    def initial_sha(self):
        return sha(self.initial)

    def kwargs(self, gate, candidate):
        return dict(lock_path=self.lock, served_path=self.served,
                    staging_path=self.staging, candidate_bytes=candidate,
                    expected_current_sha=self.initial_sha, db_path=self.db,
                    guard_check=gate.guard_check,
                    ban_proof_fn=gate.ban_proof_fn,
                    stop_check=gate.stop_check)


def _publish_worker(env_kwargs, candidate, expected_sha, queue):
    """Child-process worker: one publish attempt, result via queue."""
    try:
        receipt = sw.publish(candidate_bytes=candidate,
                             expected_current_sha=expected_sha,
                             **env_kwargs)
        queue.put(("ok", receipt["payload_sha"]))
    except sw.PublishRefused as exc:
        queue.put(("refused", exc.reason))
    except Exception as exc:  # noqa: BLE001 - reported to parent, asserted
        queue.put(("error", "%s: %s" % (type(exc).__name__, exc)))


def _holding_worker(lock_path, ready_queue, release_queue):
    """Child that acquires the lock and holds it until told to release."""
    lock = sw.SingleWriterLock(lock_path, timeout=30.0)
    lock.acquire()
    ready_queue.put(os.getpid())
    release_queue.get()  # block until parent says release
    lock.release()


class TestSingleWriter(unittest.TestCase):
    # 1. Two new publish tasks cannot write at the same time.
    def test_01_two_concurrent_publishes_serialize(self):
        with tempfile.TemporaryDirectory() as tmp:
            env = PublishEnv(tmp)
            gate = FakeGate()
            cand_a = make_payload("A")
            cand_b = make_payload("B")
            # Both candidates are built against the same initial version,
            # so exactly one may win; the loser must be refused (stale
            # current version), never interleave.
            ctx = mp.get_context("fork")
            queue = ctx.Queue()
            base = dict(lock_path=env.lock, served_path=env.served,
                        staging_path=env.staging, db_path=env.db,
                        guard_check=gate.guard_check,
                        ban_proof_fn=gate.ban_proof_fn,
                        stop_check=gate.stop_check)
            procs = [
                ctx.Process(target=_publish_worker,
                            args=(base, cand_a, env.initial_sha, queue)),
                ctx.Process(target=_publish_worker,
                            args=(base, cand_b, env.initial_sha, queue)),
            ]
            for p in procs:
                p.start()
            for p in procs:
                p.join(timeout=30)
            self.assertEqual([p.exitcode for p in procs], [0, 0])
            results = sorted([queue.get() for _ in range(2)])
            ok = [r for r in results if r[0] == "ok"]
            refused = [r for r in results if r[0] == "refused"]
            self.assertEqual(len(ok), 1, "exactly one publish must win: %r"
                             % (results,))
            self.assertEqual(len(refused), 1)
            self.assertEqual(refused[0][1], "stale_current_version")
            final = read_file(env.served)
            self.assertIn(final, (cand_a, cand_b),
                          "served must be exactly one complete payload")
            self.assertEqual(read_file(env.staging), final)
            self.assertEqual(sha(final), ok[0][1])
            self.assertEqual(
                [f for f in os.listdir(tmp) if ".tmp-" in f], [],
                "no temp files left behind")

    # 3. Multi-process check-pass != exclusive write permission.
    def test_02_guard_pass_alone_grants_no_write_permission(self):
        with tempfile.TemporaryDirectory() as tmp:
            env = PublishEnv(tmp)
            gate = FakeGate()
            ctx = mp.get_context("fork")
            queue = ctx.Queue()

            def _check_only(q):
                allowed, reason, _ = gate.guard_check()
                q.put((allowed, reason))

            procs = [ctx.Process(target=_check_only, args=(queue,))
                     for _ in range(2)]
            for p in procs:
                p.start()
            for p in procs:
                p.join(timeout=10)
            checks = [queue.get() for _ in range(2)]
            self.assertEqual(checks, [(True, "legacy_writers_drained")] * 2,
                             "both point-in-time checks pass -- the guard "
                             "alone serializes nothing")
            # ...but with one publisher holding the lock, the second
            # publish is refused (lock_timeout) even though its guard
            # check would pass. The lock, not the check, grants write
            # permission.
            ready = ctx.Queue()
            release = ctx.Queue()
            holder = ctx.Process(target=_holding_worker,
                                 args=(env.lock, ready, release))
            holder.start()
            try:
                self.assertIsNotNone(ready.get(timeout=10))
                with self.assertRaises(sw.PublishRefused) as cm:
                    sw.publish(lock_path=env.lock, served_path=env.served,
                               staging_path=env.staging,
                               candidate_bytes=make_payload("C"),
                               expected_current_sha=env.initial_sha,
                               db_path=env.db,
                               guard_check=gate.guard_check,
                               ban_proof_fn=gate.ban_proof_fn,
                               stop_check=gate.stop_check,
                               lock_timeout=0.5)
                self.assertEqual(cm.exception.reason, "lock_timeout")
            finally:
                try:
                    release.put("go")
                except Exception:  # noqa: BLE001 - holder may be gone
                    pass
                holder.join(timeout=10)
                if holder.is_alive():
                    holder.terminate()
                    holder.join(timeout=5)
            # After release the same publish succeeds: the lock was the
            # only thing standing in the way.
            receipt = sw.publish(lock_path=env.lock, served_path=env.served,
                                 staging_path=env.staging,
                                 candidate_bytes=make_payload("C"),
                                 expected_current_sha=env.initial_sha,
                                 db_path=env.db,
                                 guard_check=gate.guard_check,
                                 ban_proof_fn=gate.ban_proof_fn,
                                 stop_check=gate.stop_check)
            self.assertEqual(receipt["payload_sha"], sha(make_payload("C")))

    # 4. No uncontrolled race between check and write.
    def test_03_no_race_between_check_and_write(self):
        with tempfile.TemporaryDirectory() as tmp:
            env = PublishEnv(tmp)
            gate = FakeGate()
            # Eight processes race with distinct candidates, all built
            # against the initial version. Under the lock each loser
            # re-verifies the current version and must refuse stale --
            # none may overwrite the winner, and the winner's payload
            # must be complete.
            ctx = mp.get_context("fork")
            queue = ctx.Queue()
            base = dict(lock_path=env.lock, served_path=env.served,
                        staging_path=env.staging, db_path=env.db,
                        guard_check=gate.guard_check,
                        ban_proof_fn=gate.ban_proof_fn,
                        stop_check=gate.stop_check)
            cands = [make_payload("R%d" % i) for i in range(8)]
            procs = [ctx.Process(target=_publish_worker,
                                 args=(base, c, env.initial_sha, queue))
                     for c in cands]
            for p in procs:
                p.start()
            for p in procs:
                p.join(timeout=30)
            results = [queue.get() for _ in range(8)]
            ok = [r for r in results if r[0] == "ok"]
            refused = [r for r in results if r[0] == "refused"]
            self.assertEqual(len(ok), 1, "exactly one winner: %r" % (results,))
            self.assertEqual(len(refused), 7)
            self.assertTrue(all(r[1] == "stale_current_version"
                                for r in refused), results)
            final = read_file(env.served)
            self.assertIn(final, cands)
            self.assertEqual(sha(final), ok[0][1])
            crawl, test, pub = db_counts(env.db)
            self.assertEqual((crawl, test, pub), (50, 50, 1),
                             "exactly one own record, crawl/test untouched")

    # 6+7. Atomic writes + HTTP-served content never shows a partial write.
    def test_04_atomic_write_and_http_consistency(self):
        with tempfile.TemporaryDirectory() as tmp:
            env = PublishEnv(tmp)
            gate = FakeGate()
            cand_a = make_payload("A")
            cand_b = make_payload("B")
            allowed_hashes = {env.initial_sha, sha(cand_a), sha(cand_b)}
            allowed_bodies = {env.initial, cand_a, cand_b}
            seen = set()
            stop_reading = threading.Event()
            errors = []

            def _reader():
                # Simulates an HTTP reader (nginx serves the file as-is):
                # every snapshot must be one complete payload.
                while not stop_reading.is_set():
                    try:
                        with open(env.served, "rb") as fh:
                            body = fh.read()
                    except FileNotFoundError:
                        errors.append("served file vanished mid-publish")
                        return
                    h = sha(body)
                    seen.add(h)
                    if h not in allowed_hashes or body not in allowed_bodies:
                        errors.append("partial/corrupt snapshot: %s (%d bytes)"
                                      % (h[:12], len(body)))
                        return
                    time.sleep(0.001)

            readers = [threading.Thread(target=_reader) for _ in range(4)]
            for t in readers:
                t.start()
            try:
                current_sha = env.initial_sha
                for i in range(30):
                    cand = cand_a if i % 2 == 0 else cand_b
                    receipt = sw.publish(
                        lock_path=env.lock, served_path=env.served,
                        staging_path=env.staging, candidate_bytes=cand,
                        expected_current_sha=current_sha, db_path=env.db,
                        guard_check=gate.guard_check,
                        ban_proof_fn=gate.ban_proof_fn,
                        stop_check=gate.stop_check)
                    current_sha = receipt["payload_sha"]
            finally:
                stop_reading.set()
                for t in readers:
                    t.join(timeout=10)
            self.assertEqual(errors, [])
            self.assertTrue(seen, "readers must have observed snapshots")
            self.assertTrue(seen <= allowed_hashes, seen)
            self.assertEqual(
                [f for f in os.listdir(tmp) if ".tmp-" in f], [],
                "no temp files left behind")
            final = read_file(env.served)
            self.assertEqual(len(final.splitlines()), 30)
            self.assertEqual(final, cand_b)  # 30 publishes, last is B

    # 5. SIGKILL: the lock is released by the kernel, no half-product left.
    def test_05_sigkill_releases_lock_without_half_product(self):
        with tempfile.TemporaryDirectory() as tmp:
            env = PublishEnv(tmp)
            ctx = mp.get_context("fork")
            ready = ctx.Queue()
            release = ctx.Queue()
            holder = ctx.Process(target=_holding_worker,
                                 args=(env.lock, ready, release))
            holder.start()
            try:
                pid = ready.get(timeout=10)
                self.assertTrue(holder.is_alive())
                os.kill(pid, signal.SIGKILL)
                holder.join(timeout=10)
                self.assertEqual(holder.exitcode, -signal.SIGKILL)
            finally:
                if holder.is_alive():
                    holder.terminate()
                    holder.join(timeout=5)
            # The lock must be acquirable immediately afterwards, and
            # the served file must still be the complete old payload.
            self.assertEqual(read_file(env.served), env.initial)
            gate = FakeGate()
            receipt = sw.publish(lock_path=env.lock, served_path=env.served,
                                 staging_path=env.staging,
                                 candidate_bytes=make_payload("K"),
                                 expected_current_sha=env.initial_sha,
                                 db_path=env.db,
                                 guard_check=gate.guard_check,
                                 ban_proof_fn=gate.ban_proof_fn,
                                 stop_check=gate.stop_check,
                                 lock_timeout=5.0)
            self.assertEqual(receipt["payload_sha"], sha(make_payload("K")))
            self.assertEqual(
                [f for f in os.listdir(tmp) if ".tmp-" in f], [],
                "no temp files left behind after SIGKILL")

    # 2 (negative direction) + 8. Guard / ban refusal leaves files + DB alone.
    def test_06_guard_or_ban_refusal_writes_nothing(self):
        with tempfile.TemporaryDirectory() as tmp:
            env = PublishEnv(tmp)
            cand = make_payload("X")
            # (a) guard refuses inside the lock
            gate = FakeGate(guard_allowed=False)
            with self.assertRaises(sw.PublishRefused) as cm:
                sw.publish(**env.kwargs(gate, cand))
            self.assertTrue(cm.exception.reason.startswith("guard_refused:"))
            self.assertEqual(read_file(env.served), env.initial)
            self.assertEqual(read_file(env.staging), env.initial)
            self.assertEqual(db_counts(env.db), (50, 50, 0))
            # (b) ban proof fails inside the lock
            gate = FakeGate(ban_proven=False)
            with self.assertRaises(sw.PublishRefused) as cm:
                sw.publish(**env.kwargs(gate, cand))
            self.assertTrue(
                cm.exception.reason.startswith("legacy_ban_unproven:"))
            self.assertEqual(read_file(env.served), env.initial)
            self.assertEqual(db_counts(env.db), (50, 50, 0))
            # (c) STOP present
            gate = FakeGate(stopped=True)
            with self.assertRaises(sw.PublishRefused) as cm:
                sw.publish(**env.kwargs(gate, cand))
            self.assertEqual(cm.exception.reason, "stop_present")
            self.assertEqual(read_file(env.served), env.initial)
            self.assertEqual(db_counts(env.db), (50, 50, 0))
            # (d) the lock was released after each refusal: a good
            #     publish now succeeds.
            gate = FakeGate()
            receipt = sw.publish(**env.kwargs(gate, cand))
            self.assertEqual(receipt["payload_sha"], sha(cand))

    # 8. Rollback after a mid-publish fault removes only the own record.
    def test_07_rollback_keeps_crawl_and_test_data(self):
        with tempfile.TemporaryDirectory() as tmp:
            env = PublishEnv(tmp)
            gate = FakeGate()
            # First a successful publish, so there is a pre-existing own
            # record that a later rollback must NOT delete.
            good = make_payload("GOOD")
            receipt = sw.publish(**env.kwargs(gate, good))
            self.assertEqual(db_counts(env.db), (50, 50, 1))
            # Now a publish that faults after the staging write.
            bad = make_payload("BAD")
            with self.assertRaises(RuntimeError) as cm:
                sw.publish(lock_path=env.lock, served_path=env.served,
                           staging_path=env.staging, candidate_bytes=bad,
                           expected_current_sha=receipt["payload_sha"],
                           db_path=env.db,
                           guard_check=gate.guard_check,
                           ban_proof_fn=gate.ban_proof_fn,
                           stop_check=gate.stop_check,
                           fault_after_staging=True)
            self.assertIn("injected_fault_after_staging", str(cm.exception))
            # Served + staging are restored to the GOOD payload, the
            # failed publish's own record is gone, the GOOD record and
            # all crawl/test rows survive.
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
