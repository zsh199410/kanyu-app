"""D7 test suite (Issue #73, GPT D6 review 6904538782).

Minimal launch-acceptance evidence, no new feature scope:

  Item 2 -- dual-target rollback fault injection. D6 proved the
  legacy-parent-missing failure and the pre-rename race. D7 proves
  the three failures GPT named for the post-rename window:
    * legacy rename succeeded but the post-write SHA fails
      (corrupted just after rename) -> rc=1 legacy_copy_failed,
      bridge rolled back, no false success; the next run repairs
      the legacy target from the verified snapshot.
    * bridge rename succeeded but the post-write SHA fails ->
      rc=1 bridge_sha_mismatch, bridge restored to pre-run bytes.
    * fsync failure on the legacy write -> rc=1 legacy_copy_failed,
      bridge rolled back.
    * process crash between the two renames (bridge=new,
      legacy=old) -> the state is DETECTABLE via the new read-only
      verify_targets() (bridge SHA != legacy SHA) and the NEXT run
      repairs it; the lock is free (flock released by the kernel).
  D7 also corrects the D6 docstring: bridge_sync is TWO
  CONSECUTIVE atomic renames under one lock, NOT a true cross-file
  atomic transaction. verify_targets() is the detector.

  Item 1 -- HTTP exposure guard limit (in-process part). The live
  nginx audit + HTTP probes are in drills/d7_item1_http_exposure.py.
  These tests pin the guard's exact behaviour: the realpath guard
  in gate-sync.sh refuses served-inside-bridge, but it does NOT
  cover an independent HTTP alias pointing at the served dir --
  that case is caught only by the audit + probes, never by the
  guard. The test asserts the guard returns "ok" for the aliased
  layout (documenting the limit, not a failure).

RED-ON-D6 DESIGN. These tests FAIL on the D6 tree (no
bridge_post_rename_hook / legacy_post_rename_hook / post_bridge_hook
/ verify_targets: TypeError / AttributeError) and PASS on the D7
tree. See drills/d7_redgreen.py.

Fixtures are SYNTHETIC (fixtures/build_fixtures.py): TEST-NET
hosts, password TEST-ONLY-NOT-A-REAL-NODE. Passing proves the code
paths, never that a real phone measured anything.

Run: python3 -m unittest tests.test_d7 -v   (from the D7 root)
"""

import hashlib
import json
import os
import shutil
import stat
import sys
import tempfile
import unittest
from unittest import mock

HERE = os.path.dirname(os.path.abspath(__file__))
D7_ROOT = os.path.dirname(HERE)
sys.path.insert(0, D7_ROOT)

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

from pool.bridge_sync import run_bridge_sync, verify_targets  # noqa: E402
from pool.phone_gate import fingerprint_of, parse_surge_line  # noqa: E402
from pool.publish import run_publish  # noqa: E402
from pool.recovery import OWNER_ACK_INIT, init_recovery_state  # noqa: E402
from pool.sync import run_sync  # noqa: E402

FIX = os.path.join(D7_ROOT, "fixtures")


def _read_lines(path):
    with open(path, encoding="utf-8") as f:
        return [l.rstrip("\n") for l in f if l.strip()]


def _write_lines(path, lines):
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")


def _sha_lines(lines):
    return hashlib.sha256(("\n".join(lines) + "\n").encode("utf-8")).hexdigest()


def _sha_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def _fp_of(line):
    name, proto, host, port, params = parse_surge_line(line)
    return fingerprint_of(proto, host, port, params)


def _guard_result(served_dir, bridge_dir):
    """The exact realpath expression from systemd/gate-sync.sh."""
    s = os.path.realpath(served_dir)
    b = os.path.realpath(bridge_dir)
    return "exposed" if s == b or s.startswith(b + os.sep) else "ok"


class D7TestBase(unittest.TestCase):
    def setUp(self):
        self.workdir = tempfile.mkdtemp(prefix="d7-test-")
        self.pool44 = _read_lines(os.path.join(FIX, "pool_44_fixture.txt"))
        self.clean14 = _read_lines(os.path.join(FIX, "clean_14_fixture.txt"))
        self.record_path = os.path.join(FIX, "native_results_fixture.json")
        self.probe_db = os.path.join(FIX, "p0_fixture.db")
        with open(self.record_path) as _f:
            record = json.load(_f)
        self.version_sha = record["runs"][0]["version_sha"]
        self.tested_at = record["runs"][0]["tested_at"]
        self.now = self.tested_at + 3600
        self.clean_sha = _sha_lines(self.clean14)
        self.clean_fps = {_fp_of(l) for l in self.clean14}
        self.failed_lines = [l for l in self.pool44
                             if _fp_of(l) not in self.clean_fps]
        self.assertEqual(len(self.failed_lines), 30)
        self.pool44_path = os.path.join(FIX, "pool_44_fixture.txt")
        self.polluted_sha = _sha_lines(self.clean14 + [self.failed_lines[0]])
        # "Old" bytes for both targets before the run under test.
        self.old_version = [l for l in self.pool44
                            if l != self.failed_lines[0]]
        self.old_sha = _sha_lines(self.old_version)
        rc, out = init_recovery_state(self.workdir, OWNER_ACK_INIT)
        self.assertEqual(rc, 0, out)

    def tearDown(self):
        shutil.rmtree(self.workdir, ignore_errors=True)

    def _seed_clean_synced(self):
        rc, res = run_publish(
            self.workdir, self.clean14, self.record_path, self.version_sha,
            probe_db=self.probe_db, now=self.now,
            source_file=self.pool44_path)
        self.assertEqual(rc, 0, res)
        rc, res = run_sync(self.workdir, self.record_path, self.version_sha,
                           probe_db=self.probe_db, now=self.now)
        self.assertEqual(rc, 0, res)
        return res

    def _served_target(self):
        return os.path.join(self.workdir, "served", "pool-new.txt")

    def _bridge_root(self, seed_old=True):
        root = tempfile.mkdtemp(prefix="d7-bridge-")
        self.addCleanup(shutil.rmtree, root, ignore_errors=True)
        bridge = os.path.join(root, "bridge")
        os.makedirs(bridge, exist_ok=True)
        if seed_old:
            _write_lines(bridge + "/pool-new.txt", self.old_version)
            _write_lines(bridge + "/old-pool.txt", self.old_version)
        return root, bridge


class TestItem2PostRename(D7TestBase):
    """D7 item 2: failures AFTER a successful rename."""

    def test_legacy_post_rename_sha_mismatch(self):
        """Legacy renamed, then its bytes are corrupted before the
        post-write verify: rc=1 legacy_copy_failed, bridge rolled
        back to pre-run bytes, legacy holds the corrupted bytes
        (detectable, SHA != snapshot), no success claimed. The NEXT
        run repairs the legacy target from the snapshot."""
        self._seed_clean_synced()
        _root, bridge = self._bridge_root()
        old_path = os.path.join(bridge, "old-pool.txt")

        def _corrupt_legacy(path):
            with open(path, "a", encoding="utf-8") as f:
                f.write(self.failed_lines[0] + "\n")

        rc, res = run_bridge_sync(
            self.workdir, bridge, old_path=old_path,
            native_record_path=self.record_path, probe_db=self.probe_db,
            now=self.now, legacy_post_rename_hook=_corrupt_legacy)
        self.assertEqual(rc, 1, res)
        self.assertEqual(res.get("error"), "legacy_copy_failed")
        self.assertFalse(res.get("ok"))
        self.assertTrue(res.get("bridge_rolled_back"))
        # Bridge holds its pre-run bytes; legacy holds corrupted
        # bytes: the snapshot bytes (clean14) plus one appended failed
        # line, i.e. the polluted 15-line SHA -- detectable.
        self.assertEqual(_sha_file(bridge + "/pool-new.txt"), self.old_sha)
        self.assertEqual(_sha_file(old_path), self.polluted_sha)
        # Detector sees the divergence (bridge first: it was rolled
        # back to pre-run bytes, which differ from published).
        vt = verify_targets(self.workdir, bridge, old_path=old_path)
        self.assertFalse(vt["consistent"])
        self.assertEqual(vt["detail"], "bridge_sha_mismatch")
        self.assertEqual(vt["bridge_sha"], self.old_sha)
        self.assertEqual(vt["legacy_sha"], self.polluted_sha)
        # Next run repairs the legacy target; both targets verified.
        rc, res = run_bridge_sync(
            self.workdir, bridge, old_path=old_path,
            native_record_path=self.record_path, probe_db=self.probe_db,
            now=self.now)
        self.assertEqual(rc, 0, res)
        self.assertEqual(_sha_file(bridge + "/pool-new.txt"), self.clean_sha)
        self.assertEqual(_sha_file(old_path), self.clean_sha)
        vt = verify_targets(self.workdir, bridge, old_path=old_path)
        self.assertTrue(vt["consistent"])
        self.assertEqual(vt["detail"], "all_targets_match_published_sha")

    def test_bridge_post_rename_sha_mismatch(self):
        """Bridge renamed, then its bytes are corrupted before the
        post-write verify: rc=1 bridge_sha_mismatch, bridge restored
        to pre-run bytes, legacy untouched, no success claimed."""
        self._seed_clean_synced()
        _root, bridge = self._bridge_root()
        old_path = os.path.join(bridge, "old-pool.txt")

        def _corrupt_bridge(path):
            with open(path, "a", encoding="utf-8") as f:
                f.write(self.failed_lines[0] + "\n")

        rc, res = run_bridge_sync(
            self.workdir, bridge, old_path=old_path,
            native_record_path=self.record_path, probe_db=self.probe_db,
            now=self.now, bridge_post_rename_hook=_corrupt_bridge)
        self.assertEqual(rc, 1, res)
        self.assertEqual(res.get("error"), "bridge_sha_mismatch")
        self.assertFalse(res.get("ok"))
        self.assertTrue(res.get("bridge_rolled_back"))
        self.assertEqual(_sha_file(bridge + "/pool-new.txt"), self.old_sha)
        # Legacy was never written in this run.
        self.assertEqual(_sha_file(old_path), self.old_sha)
        self.assertEqual(
            (res.get("bridge_manifest_after_rollback") or {}).get("sha256"),
            self.old_sha)
        # Next run succeeds and both targets verify.
        rc, res = run_bridge_sync(
            self.workdir, bridge, old_path=old_path,
            native_record_path=self.record_path, probe_db=self.probe_db,
            now=self.now)
        self.assertEqual(rc, 0, res)
        self.assertEqual(_sha_file(bridge + "/pool-new.txt"), self.clean_sha)
        self.assertEqual(_sha_file(old_path), self.clean_sha)

    def test_legacy_fsync_failure(self):
        """os.fsync raises on the legacy tmp write: rc=1
        legacy_copy_failed, bridge rolled back, legacy untouched.
        fsync call order in run_bridge_sync: 1 lock acquire, 2 bridge
        tmp, 3 bridge dir, 4 legacy tmp -> raise only on #4."""
        self._seed_clean_synced()
        _root, bridge = self._bridge_root()
        old_path = os.path.join(bridge, "old-pool.txt")
        real_fsync = os.fsync
        calls = {"n": 0}

        def _fsync_maybe_fail(fd):
            calls["n"] += 1
            if calls["n"] == 4:
                raise OSError("simulated fsync failure (D7)")
            return real_fsync(fd)

        with mock.patch("os.fsync", side_effect=_fsync_maybe_fail):
            rc, res = run_bridge_sync(
                self.workdir, bridge, old_path=old_path,
                native_record_path=self.record_path, probe_db=self.probe_db,
                now=self.now)
        self.assertEqual(rc, 1, res)
        self.assertEqual(res.get("error"), "legacy_copy_failed")
        self.assertFalse(res.get("ok"))
        self.assertTrue(res.get("bridge_rolled_back"))
        self.assertEqual(_sha_file(bridge + "/pool-new.txt"), self.old_sha)
        self.assertEqual(_sha_file(old_path), self.old_sha)
        # Next run (real fsync) succeeds.
        rc, res = run_bridge_sync(
            self.workdir, bridge, old_path=old_path,
            native_record_path=self.record_path, probe_db=self.probe_db,
            now=self.now)
        self.assertEqual(rc, 0, res)
        self.assertEqual(_sha_file(old_path), self.clean_sha)

    def test_crash_between_renames_detectable_and_repaired(self):
        """Process crash after the bridge rename, before the legacy
        write (hook raises): the exception propagates (simulated
        crash), bridge holds the NEW snapshot, legacy still holds
        its PRE-RUN bytes. verify_targets() flags the divergence,
        and the next run repairs it. The lock is free afterwards
        (the next run acquires it)."""
        self._seed_clean_synced()
        _root, bridge = self._bridge_root()
        old_path = os.path.join(bridge, "old-pool.txt")

        def _crash(_bridge_file):
            raise RuntimeError("simulated crash between renames (D7)")

        with self.assertRaises(RuntimeError):
            run_bridge_sync(
                self.workdir, bridge, old_path=old_path,
                native_record_path=self.record_path, probe_db=self.probe_db,
                now=self.now, post_bridge_hook=_crash)
        # Final state: bridge=new snapshot, legacy=pre-run bytes.
        self.assertEqual(_sha_file(bridge + "/pool-new.txt"), self.clean_sha)
        self.assertEqual(_sha_file(old_path), self.old_sha)
        vt = verify_targets(self.workdir, bridge, old_path=old_path)
        self.assertFalse(vt["consistent"])
        self.assertEqual(vt["detail"], "legacy_sha_mismatch")
        self.assertEqual(vt["bridge_sha"], self.clean_sha)
        self.assertEqual(vt["legacy_sha"], self.old_sha)
        self.assertEqual(vt["published_sha"], self.clean_sha)
        # Next run repairs the legacy target (lock is free).
        rc, res = run_bridge_sync(
            self.workdir, bridge, old_path=old_path,
            native_record_path=self.record_path, probe_db=self.probe_db,
            now=self.now)
        self.assertEqual(rc, 0, res)
        self.assertEqual(_sha_file(old_path), self.clean_sha)
        vt = verify_targets(self.workdir, bridge, old_path=old_path)
        self.assertTrue(vt["consistent"])


class TestVerifyTargets(D7TestBase):
    """The read-only detector (D7)."""

    def test_verify_targets_consistent(self):
        self._seed_clean_synced()
        _root, bridge = self._bridge_root(seed_old=False)
        old_path = os.path.join(bridge, "old-pool.txt")
        rc, res = run_bridge_sync(
            self.workdir, bridge, old_path=old_path,
            native_record_path=self.record_path, probe_db=self.probe_db,
            now=self.now)
        self.assertEqual(rc, 0, res)
        vt = verify_targets(self.workdir, bridge, old_path=old_path)
        self.assertTrue(vt["consistent"])
        self.assertEqual(vt["served_sha"], self.clean_sha)
        self.assertEqual(vt["bridge_sha"], self.clean_sha)
        self.assertEqual(vt["legacy_sha"], self.clean_sha)
        self.assertEqual(vt["published_sha"], self.clean_sha)
        self.assertEqual(vt["detail"], "all_targets_match_published_sha")

    def test_verify_targets_divergent_legacy(self):
        self._seed_clean_synced()
        _root, bridge = self._bridge_root()
        old_path = os.path.join(bridge, "old-pool.txt")
        vt = verify_targets(self.workdir, bridge, old_path=old_path)
        self.assertFalse(vt["consistent"])
        # Bridge is checked before legacy: it holds pre-run bytes,
        # so the first divergence named is the bridge.
        self.assertEqual(vt["detail"], "bridge_sha_mismatch")
        self.assertEqual(vt["served_sha"], self.clean_sha)
        self.assertEqual(vt["bridge_sha"], self.old_sha)
        self.assertEqual(vt["legacy_sha"], self.old_sha)

    def test_verify_targets_missing_legacy(self):
        self._seed_clean_synced()
        _root, bridge = self._bridge_root(seed_old=False)
        old_path = os.path.join(bridge, "old-pool.txt")
        rc, res = run_bridge_sync(
            self.workdir, bridge, old_path=old_path,
            native_record_path=self.record_path, probe_db=self.probe_db,
            now=self.now)
        self.assertEqual(rc, 0, res)
        os.unlink(old_path)
        vt = verify_targets(self.workdir, bridge, old_path=old_path)
        self.assertFalse(vt["consistent"])
        self.assertEqual(vt["detail"], "legacy_sha_mismatch")
        self.assertIsNone(vt["legacy_sha"])

    def test_verify_targets_no_chain(self):
        vt = verify_targets(self.workdir, "/nonexistent-bridge")
        self.assertFalse(vt["consistent"])
        self.assertEqual(vt["detail"], "served_no_chain")


class TestItem1GuardLimit(D7TestBase):
    """D7 item 1 (in-process pin): the gate-sync.sh realpath guard
    covers served-inside-bridge ONLY. An independent HTTP alias
    pointing at the served dir is NOT caught by the guard -- the
    guard returns "ok" for that layout. The live audit + probes
    (drills/d7_item1_http_exposure.py) are the control that catches
    it. These tests pin the limit so nobody later mistakes the guard
    for full coverage."""

    def test_guard_catches_served_inside_bridge(self):
        served_dir = os.path.join(self.workdir, "served")
        bridge_dir = os.path.join(self.workdir, "bridge")
        os.makedirs(served_dir, exist_ok=True)
        os.makedirs(bridge_dir, exist_ok=True)
        # Served nested inside the bridge dir: guard must refuse.
        nested_served = os.path.join(bridge_dir, "served")
        os.makedirs(nested_served, exist_ok=True)
        self.assertEqual(_guard_result(nested_served, bridge_dir), "exposed")
        self.assertEqual(_guard_result(bridge_dir, bridge_dir), "exposed")

    def test_guard_does_not_cover_independent_alias(self):
        # Served OUTSIDE the bridge dir, but hypothetically exposed
        # by an independent HTTP alias (e.g. location /alias/ ->
        # alias <served dir>): the guard sees only realpath
        # containment and returns "ok". This is the documented limit
        # (GPT D6 review item 1): the audit + probes must catch it.
        served_dir = os.path.join(self.workdir, "served")
        bridge_dir = os.path.join(self.workdir, "bridge")
        os.makedirs(served_dir, exist_ok=True)
        os.makedirs(bridge_dir, exist_ok=True)
        self.assertEqual(_guard_result(served_dir, bridge_dir), "ok")


if __name__ == "__main__":
    unittest.main()
