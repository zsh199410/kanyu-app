"""D1 test suite (GPT 6875033415 item 4).

Covers: shared-flock contention + crash recovery, dual-gate admission
(native decides, P0 is health signal only), pinned NO exemption, gate
spanning publish / sync / rollback, all-fail / empty / single-node, and
the :07 timer simulation (separate drill, invoked as a subprocess).

Fixtures are SYNTHETIC (fixtures/build_fixtures.py): TEST-NET hosts,
password TEST-ONLY-NOT-A-REAL-NODE, mirroring the 13:24 native-test
decision structure (14 pass / 4 P0-fast-but-native-slow / 26 fail).

Run: python3 -m unittest discover -s tests -v   (from the D1 root)
"""

import hashlib
import json
import os
import signal
import sqlite3
import subprocess
import sys
import tempfile
import threading
import time
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
D1_ROOT = os.path.dirname(HERE)
sys.path.insert(0, D1_ROOT)

# rules.py imports pool.crawler / pool.geo (production fetch + geo
# lookup). The D1 tests only exercise select_publish's gate behaviour,
# so those two modules are stubbed with deterministic fakes.
import types  # noqa: E402

_crawler = types.ModuleType("pool.crawler")
_crawler.AEAD_METHODS = ("aes-128-gcm", "aes-256-gcm", "chacha20-poly1305")
_crawler.parse_surge_line = lambda line: None  # unused on this path
sys.modules["pool.crawler"] = _crawler

_geo = types.ModuleType("pool.geo")
_CN = {"US": ("美国", "\U0001f1fa\U0001f1f8"),
       "HK": ("香港", "\U0001f1ed\U0001f1f0"),
       "IR": ("伊朗", "\U0001f1ee\U0001f1f7")}


def _hint_to_code(hint):
    for cn, code in (("美国", "US"), ("香港", "HK"), ("伊朗", "IR")):
        if cn in (hint or ""):
            return code
    return ""


_geo.hint_to_code = _hint_to_code
_geo.display_name = lambda code, english="": _CN.get(code, ("未知", ""))
_geo.code_to_flag = lambda code: _CN.get(code, ("", ""))[1]
_geo.is_cf_or_reserved = lambda host: False


class _FakeIpApi:
    def country(self, host):
        return ("US", "")


_geo.IpApi = _FakeIpApi
sys.modules["pool.geo"] = _geo

from pool.native_gate import (  # noqa: E402
    gate_lines, load_native_allowlist, load_native_record,
    latest_native_by_fp)
from pool.phone_gate import fingerprint_of, parse_surge_line  # noqa: E402
from pool.publish import run_publish  # noqa: E402
from pool.publish_lock import (  # noqa: E402
    LockTimeout, PublishLock, PublishRefused, _atomic_write_inner,
    atomic_publish_locked, file_manifest)
from pool.rollback import run_rollback  # noqa: E402
from pool.rules import select_publish  # noqa: E402
from pool.sync import run_sync  # noqa: E402

FIX = os.path.join(D1_ROOT, "fixtures")


def _read_lines(path):
    with open(path, encoding="utf-8") as f:
        return [l.rstrip("\n") for l in f if l.strip()]


def _fp_of(line):
    name, proto, host, port, params = parse_surge_line(line)
    return fingerprint_of(proto, host, port, params)


def _make_record(lines, pass_fps, version_sha, tested_at, fail_fps=(),
                 slow_fps_ms=None):
    """Build a native-results-v1 record dict for arbitrary lines."""
    slow_fps_ms = slow_fps_ms or {}
    results = []
    for line in lines:
        fp = _fp_of(line)
        name = line.split(" = ", 1)[0]
        if fp in fail_fps:
            results.append({"fingerprint": fp, "name": name,
                            "success": False, "ms": None})
        elif fp in slow_fps_ms:
            results.append({"fingerprint": fp, "name": name,
                            "success": True, "ms": slow_fps_ms[fp]})
        elif fp in pass_fps:
            results.append({"fingerprint": fp, "name": name,
                            "success": True, "ms": 150})
        else:
            results.append({"fingerprint": fp, "name": name,
                            "success": False, "ms": None})
    return {"format": "native-results-v1",
            "runs": [{"version_sha": version_sha, "tested_at": tested_at,
                      "network": "5G cellular pdp_ip0, no Wi-Fi",
                      "surge": "6.100.0 build 4025",
                      "results": results}]}


class D1TestBase(unittest.TestCase):
    def setUp(self):
        self.workdir = tempfile.mkdtemp(prefix="d1-test-")
        self.pool44 = _read_lines(os.path.join(FIX, "pool_44_fixture.txt"))
        self.clean14 = _read_lines(os.path.join(FIX, "clean_14_fixture.txt"))
        self.record_path = os.path.join(FIX, "native_results_fixture.json")
        self.probe_db = os.path.join(FIX, "p0_fixture.db")
        record = json.load(open(self.record_path))
        self.version_sha = record["runs"][0]["version_sha"]
        self.tested_at = record["runs"][0]["tested_at"]
        self.now = self.tested_at + 3600
        self.clean_sha = hashlib.sha256(
            ("\n".join(self.clean14) + "\n").encode("utf-8")).hexdigest()
        self.admitted = set()
        for line in self.clean14:
            self.admitted.add(_fp_of(line))
        self.assertEqual(len(self.admitted), 14)

    def tearDown(self):
        import shutil
        shutil.rmtree(self.workdir, ignore_errors=True)

    def _write_record(self, record, name="record.json"):
        path = os.path.join(self.workdir, name)
        with open(path, "w", encoding="utf-8") as f:
            json.dump(record, f)
        return path


class TestSharedLock(D1TestBase):
    def test_lock_contention_timeout(self):
        """Second acquirer times out while the lock is held."""
        lock_path = os.path.join(self.workdir, "lock", "publish.lock")
        lock1 = PublishLock(lock_path, owner="holder", timeout=30)
        lock1.acquire()
        try:
            lock2 = PublishLock(lock_path, owner="waiter", timeout=1)
            with self.assertRaises(LockTimeout):
                lock2.acquire()
        finally:
            lock1.release()

    def test_lock_contention_waits_then_succeeds(self):
        """Second acquirer succeeds after the holder releases."""
        lock_path = os.path.join(self.workdir, "lock", "publish.lock")
        lock1 = PublishLock(lock_path, owner="holder", timeout=30)
        lock1.acquire()

        def _release():
            time.sleep(1)
            lock1.release()
        t = threading.Thread(target=_release)
        t.start()
        lock2 = PublishLock(lock_path, owner="waiter", timeout=5)
        lock2.acquire()
        lock2.release()
        t.join()

    def test_crash_recovery(self):
        """SIGKILLed holder: next acquirer proceeds immediately, file intact."""
        # Seed a clean publish file first.
        rc, res = run_publish(
            self.workdir, self.clean14, self.record_path, self.version_sha,
            probe_db=self.probe_db, now=self.now)
        self.assertEqual(rc, 0)
        target = os.path.join(self.workdir, "publish", "pool-new.txt")
        before = file_manifest(target)
        ready = os.path.join(self.workdir, "holder-ready.txt")
        holder = subprocess.Popen(
            [sys.executable, "drills/hold_lock.py", "--workdir", self.workdir,
             "--hold", "30", "--ready", ready],
            cwd=D1_ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            for _ in range(100):
                if os.path.exists(ready):
                    break
                time.sleep(0.1)
            self.assertTrue(os.path.exists(ready), "holder never acquired")
            holder.send_signal(signal.SIGKILL)
            holder.wait(timeout=10)
            t0 = time.time()
            lock = PublishLock(os.path.join(self.workdir, "lock", "publish.lock"),
                               owner="after-crash", timeout=5)
            lock.acquire()
            dt = time.time() - t0
            lock.release()
            self.assertLess(dt, 2.0, "lock not released promptly after SIGKILL")
            after = file_manifest(target)
            self.assertEqual(after["sha256"], before["sha256"],
                             "publish file changed by the crash")
            self.assertEqual(after["lines"], 14)
        finally:
            if holder.poll() is None:
                holder.kill()


class TestDualGate(D1TestBase):
    def test_native_pass_admitted(self):
        admitted, cond, diag = load_native_allowlist(
            self.record_path, self.version_sha, probe_db=self.probe_db,
            now=self.now)
        self.assertEqual(diag["admitted"], 14)
        self.assertEqual(admitted, self.admitted)

    def test_p0_fast_native_slow_rejected(self):
        """P0 <280 but native 320-1018: the 4 mirror cases MUST be rejected."""
        admitted, _cond, diag = load_native_allowlist(
            self.record_path, self.version_sha, probe_db=self.probe_db,
            now=self.now)
        slow_tags = {"T11", "T15", "T16", "T17"}
        for line in self.pool44:
            tag = line.split(" ", 1)[0]
            if tag in slow_tags:
                self.assertNotIn(_fp_of(line), admitted, tag)
        self.assertEqual(
            diag["reasons"].get("latest_native_slow_or_missing_ms"), 4)

    def test_native_pass_p0_conditional_admitted(self):
        """Native pass + P0 281-297: admitted AND flagged conditional."""
        admitted, cond, diag = load_native_allowlist(
            self.record_path, self.version_sha, probe_db=self.probe_db,
            now=self.now)
        for line in self.pool44:
            tag = line.split(" ", 1)[0]
            if tag in ("T09", "T12", "T13"):
                self.assertIn(_fp_of(line), admitted, tag)
                self.assertIn(_fp_of(line), cond, tag)
        self.assertEqual(diag["conditional"], 3)

    def test_native_failed_rejected(self):
        admitted, _cond, diag = load_native_allowlist(
            self.record_path, self.version_sha, probe_db=self.probe_db,
            now=self.now)
        self.assertEqual(diag["reasons"].get("latest_native_failed"), 26)

    def test_version_mismatch_rejected(self):
        """Native evidence for a DIFFERENT version admits nothing."""
        admitted, _cond, diag = load_native_allowlist(
            self.record_path, "b" * 64, probe_db=self.probe_db, now=self.now)
        self.assertEqual(len(admitted), 0)
        self.assertEqual(diag["reasons"].get("native_version_mismatch"), 44)

    def test_superseded_native_evidence(self):
        """Run2 (newer version) fails T01: publishing run1's version
        must reject T01 even though run1 passed it."""
        sup_path = os.path.join(FIX, "native_results_supersede_fixture.json")
        admitted, _cond, diag = load_native_allowlist(
            sup_path, self.version_sha, probe_db=self.probe_db,
            now=self.tested_at + 7200)
        t01_fp = None
        for line in self.pool44:
            if line.startswith("T01 "):
                t01_fp = _fp_of(line)
        self.assertNotIn(t01_fp, admitted)
        self.assertEqual(diag["admitted"], 13)

    def test_native_future_ts_rejected(self):
        record = _make_record(self.clean14, self.admitted,
                              self.version_sha, self.now + 3600)
        path = self._write_record(record, "future.json")
        admitted, _cond, diag = load_native_allowlist(
            path, self.version_sha, now=self.now)
        self.assertEqual(len(admitted), 0)
        self.assertEqual(diag["reasons"].get("native_ts_invalid"), 14)

    def test_native_stale_ttl(self):
        record = _make_record(self.clean14, self.admitted,
                              self.version_sha, self.now - 25 * 3600)
        path = self._write_record(record, "stale.json")
        admitted, _cond, diag = load_native_allowlist(
            path, self.version_sha, now=self.now)
        self.assertEqual(len(admitted), 0)
        self.assertEqual(diag["reasons"].get("native_stale"), 14)

    def test_native_record_missing(self):
        admitted, _cond, diag = load_native_allowlist(
            os.path.join(self.workdir, "no-such.json"), self.version_sha,
            now=self.now)
        self.assertEqual(len(admitted), 0)
        self.assertEqual(diag.get("error"), "native_record_missing")

    def test_gate_lines_unparsable_dropped(self):
        kept, ldiag = gate_lines(
            self.clean14 + ["this is not a surge line", ""],
            self.admitted)
        self.assertEqual(len(kept), 14)
        self.assertEqual(ldiag["reasons"].get("unparsable_or_protocol"), 1)


class TestPinnedNoExemption(D1TestBase):
    def test_pinned_without_native_pass_is_rejected(self):
        """Pinned lines go through the SAME gate: no exemption."""
        pinned_lines = []
        for line in self.pool44[:5]:
            name, proto, host, port, _p = parse_surge_line(line)
            pinned_lines.append((name, proto, host, port, line))
        # First 5 pool lines: T01 pass, T02 pass, T03 pass, T04 pass,
        # T05 pass -- all admitted. Add a pinned slow line (T11).
        slow = self.pool44[10]
        name, proto, host, port, _p = parse_surge_line(slow)
        pinned_lines.append((name, proto, host, port, slow))
        lines, stats = select_publish(
            pinned_lines, [], set(), set(), 5, 150, _FakeIpApi(),
            allowed_fingerprints=self.admitted)
        self.assertEqual(stats["pinned"], 5)
        self.assertEqual(stats["gate_skipped"], 1)
        self.assertEqual(len(lines), 5)
        self.assertNotIn(slow, lines)

    def test_pinned_with_native_pass_is_kept(self):
        pinned_lines = []
        for line in self.clean14[:3]:
            name, proto, host, port, _p = parse_surge_line(line)
            pinned_lines.append((name, proto, host, port, line))
        lines, stats = select_publish(
            pinned_lines, [], set(), set(), 5, 150, _FakeIpApi(),
            allowed_fingerprints=self.admitted)
        self.assertEqual(stats["pinned"], 3)
        self.assertEqual(len(lines), 3)


class TestPublishSyncRollback(D1TestBase):
    def test_publish_all_native_fail_refuses(self):
        record = _make_record(self.pool44, set(), self.version_sha,
                              self.tested_at)
        path = self._write_record(record, "allfail.json")
        # Seed a clean file first so we can prove it is kept.
        rc, _ = run_publish(self.workdir, self.clean14, self.record_path,
                            self.version_sha, probe_db=self.probe_db,
                            now=self.now)
        self.assertEqual(rc, 0)
        target = os.path.join(self.workdir, "publish", "pool-new.txt")
        before = file_manifest(target)
        rc, res = run_publish(self.workdir, self.pool44, path,
                              self.version_sha, probe_db=self.probe_db,
                              now=self.now)
        self.assertEqual(rc, 1)
        self.assertEqual(res.get("error"), "phone_gate_zero_qualified")
        after = file_manifest(target)
        self.assertEqual(after["sha256"], before["sha256"])
        self.assertEqual(after["lines"], 14)

    def test_publish_empty_candidates_refuses(self):
        rc, res = run_publish(self.workdir, [], self.record_path,
                              self.version_sha, probe_db=self.probe_db,
                              now=self.now)
        self.assertEqual(rc, 1)
        target = os.path.join(self.workdir, "publish", "pool-new.txt")
        self.assertFalse(os.path.exists(target))

    def test_publish_single_node(self):
        rc, res = run_publish(self.workdir, self.clean14[:1],
                              self.record_path, self.version_sha,
                              probe_db=self.probe_db, now=self.now)
        self.assertEqual(rc, 0)
        self.assertEqual(res["manifest"]["lines"], 1)

    def test_publish_missing_record_refuses(self):
        rc, res = run_publish(
            self.workdir, self.clean14,
            os.path.join(self.workdir, "no-such.json"), self.version_sha,
            now=self.now)
        self.assertEqual(rc, 1)
        self.assertTrue(res.get("error", "").startswith("native_gate_"))

    def test_sync_refuses_ungated_source(self):
        # Seed clean via gated publish + sync.
        rc, _ = run_publish(self.workdir, self.clean14, self.record_path,
                            self.version_sha, probe_db=self.probe_db,
                            now=self.now)
        self.assertEqual(rc, 0)
        rc, _ = run_sync(self.workdir, self.record_path, self.version_sha,
                         probe_db=self.probe_db, now=self.now)
        self.assertEqual(rc, 0)
        served = os.path.join(self.workdir, "served", "pool-new.txt")
        before = file_manifest(served)
        # Legacy writer drops the ungated 44-line file into publish/.
        with open(os.path.join(self.workdir, "publish", "pool-new.txt"),
                  "w", encoding="utf-8") as f:
            f.write("\n".join(self.pool44) + "\n")
        rc, res = run_sync(self.workdir, self.record_path, self.version_sha,
                           probe_db=self.probe_db, now=self.now)
        self.assertEqual(rc, 1)
        self.assertEqual(res.get("error"),
                         "sync_gate_source_not_fully_admitted")
        after = file_manifest(served)
        self.assertEqual(after["sha256"], before["sha256"])
        self.assertEqual(after["lines"], 14)

    def test_sync_accepts_gated_source(self):
        rc, _ = run_publish(self.workdir, self.clean14, self.record_path,
                            self.version_sha, probe_db=self.probe_db,
                            now=self.now)
        self.assertEqual(rc, 0)
        rc, res = run_sync(self.workdir, self.record_path, self.version_sha,
                           probe_db=self.probe_db, now=self.now)
        self.assertEqual(rc, 0)
        served = os.path.join(self.workdir, "served", "pool-new.txt")
        self.assertEqual(file_manifest(served)["sha256"], self.clean_sha)
        self.assertEqual(file_manifest(served)["lines"], 14)

    def test_rollback_accepts_gated_snapshot(self):
        # v1: clean 14. v2: 13-line subset with its own native record.
        rc, _ = run_publish(self.workdir, self.clean14, self.record_path,
                            self.version_sha, probe_db=self.probe_db,
                            now=self.now)
        self.assertEqual(rc, 0)
        subset = self.clean14[:13]
        subset_sha = hashlib.sha256(
            ("\n".join(subset) + "\n").encode("utf-8")).hexdigest()
        subset_fps = {_fp_of(l) for l in subset}
        record2 = _make_record(subset, subset_fps, subset_sha, self.tested_at)
        path2 = self._write_record(record2, "record2.json")
        rc, _ = run_publish(self.workdir, subset, path2, subset_sha,
                            probe_db=self.probe_db, now=self.now)
        self.assertEqual(rc, 0)
        target = os.path.join(self.workdir, "publish", "pool-new.txt")
        self.assertEqual(file_manifest(target)["lines"], 13)
        rc, res = run_rollback(self.workdir, "latest-history",
                               self.record_path, probe_db=self.probe_db,
                               now=self.now)
        self.assertEqual(rc, 0, res)
        self.assertEqual(file_manifest(target)["lines"], 14)
        self.assertEqual(file_manifest(target)["sha256"], self.clean_sha)
        served = os.path.join(self.workdir, "served", "pool-new.txt")
        self.assertEqual(file_manifest(served)["sha256"], self.clean_sha)

    def test_rollback_refuses_anchor_without_version_meta(self):
        rc, _ = run_publish(self.workdir, self.clean14, self.record_path,
                            self.version_sha, probe_db=self.probe_db,
                            now=self.now)
        self.assertEqual(rc, 0)
        # Strip the history sidecar: anchor can no longer be gate-checked.
        hist = os.path.join(self.workdir, "publish", "history")
        # First publish has no history yet (nothing to snapshot); publish
        # a second version so a snapshot exists, then strip its meta.
        subset = self.clean14[:13]
        subset_sha = hashlib.sha256(
            ("\n".join(subset) + "\n").encode("utf-8")).hexdigest()
        record2 = _make_record(subset, {_fp_of(l) for l in subset},
                               subset_sha, self.tested_at)
        path2 = self._write_record(record2, "record2.json")
        rc, _ = run_publish(self.workdir, subset, path2, subset_sha,
                            probe_db=self.probe_db, now=self.now)
        self.assertEqual(rc, 0)
        for f in os.listdir(hist):
            if f.endswith(".meta.json"):
                os.unlink(os.path.join(hist, f))
        rc, res = run_rollback(self.workdir, "latest-history",
                               self.record_path, probe_db=self.probe_db,
                               now=self.now)
        self.assertEqual(rc, 1)
        self.assertEqual(res.get("error"), "anchor_no_version_meta")
        target = os.path.join(self.workdir, "publish", "pool-new.txt")
        self.assertEqual(file_manifest(target)["lines"], 13)


class TestTimerSimulation(D1TestBase):
    def test_sim_timers_keeps_clean(self):
        """End-to-end: concurrent :07 publish + :15 sync cycles."""
        log_path = os.path.join(self.workdir, "sim-log.json")
        p = subprocess.run(
            [sys.executable, "drills/sim_timers.py",
             "--workdir", self.workdir, "--cycles", "2",
             "--candidates", os.path.join(FIX, "pool_44_fixture.txt"),
             "--clean", os.path.join(FIX, "clean_14_fixture.txt"),
             "--native-record", self.record_path,
             "--source-version", self.version_sha,
             "--probe-db", self.probe_db,
             "--log", log_path],
            cwd=D1_ROOT, capture_output=True, text=True, timeout=300)
        self.assertEqual(p.returncode, 0, p.stdout + p.stderr)
        log = json.load(open(log_path))
        self.assertTrue(log["ok"])
        self.assertEqual(log["passed"], log["total"])
        self.assertEqual(log["clean_lines"], 14)


if __name__ == "__main__":
    unittest.main(verbosity=2)
