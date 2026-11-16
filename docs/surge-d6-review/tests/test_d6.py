"""D6 test suite (Issue #73, GPT D5 review 6887615694).

Closes the three D5 residual risks with minimal fixes:

  Item 1 -- served pollution: D5's sync_served_gate_failed left the
  polluted served bytes IN PLACE at the canonical served path (E3:
  6074082847c3 -> 7737d85e5d1e, 15 lines, only recorded). D6
  quarantines the polluted file (served/.quarantine/, mode 600) and
  restores the last chain-verified version from the publish file,
  in-lock, before entering degraded (STOP). The pool still stays
  STOP until manual recovery. The served path must be a regular file,
  never a symlink (served_symlink_refused).
  Item 2 -- bridge race: D5's gate-sync.sh checked served's SHA and
  copied to the bridge AFTER pool.sync released the lock (check ->
  copy window), and a legacy $OLD failure only logged while exiting
  rc=0. D6 does the bridge step in pool.bridge_sync under the SAME
  shared lock, from ONE in-memory immutable snapshot of the verified
  served bytes, with bridge + legacy verified after the rename and
  bridge rolled back to its pre-run bytes on legacy failure.
  Item 3 -- publish exit codes: D5's gate-publish.sh always exited
  "$GATE_RC", so gate=0 + assembly!=0 exited 0 and masked the
  assembly failure. D6 exits 0 (healthy), 1 (gate refused /
  pre-check failed), 2 (gate passed, assembly failed), and writes
  $GATE/logs/health.json every cycle.

RED-ON-D5 DESIGN. The fault-injection tests FAIL on the D5 tree
(served keeps polluted bytes; bridge receives unverified bytes on a
mid-copy served rewrite; gate-publish exits 0 on assembly failure)
and PASS on the D6 tree. Run the red check with this file copied
into the D5 tree's tests/ directory: python3 -m unittest
tests.test_d6 -v (expect failures), then in the D6 tree:
python3 -m unittest tests.test_d6 -v (expect all green).

HONEST BOUNDARY -- fixtures are SYNTHETIC (fixtures/build_fixtures.py):
TEST-NET hosts, password TEST-ONLY-NOT-A-REAL-NODE. A fixture run
passing the gate proves the CODE paths, never that a real phone
measured anything.

Run: python3 -m unittest tests.test_d6 -v   (from the D6 root)
"""

import hashlib
import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import time
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
D6_ROOT = os.path.dirname(HERE)
sys.path.insert(0, D6_ROOT)

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

from pool.bridge_sync import run_bridge_sync  # noqa: E402
from pool.native_gate import load_native_allowlist  # noqa: E402
from pool.phone_gate import fingerprint_of, parse_surge_line  # noqa: E402
from pool.publish import run_publish  # noqa: E402
from pool.publish_lock import file_manifest  # noqa: E402
from pool.recovery import OWNER_ACK_INIT, gate_check, init_recovery_state  # noqa: E402
from pool.sync import _quarantine_and_restore_served, run_sync  # noqa: E402
from pool.version_chain import read_chain_sidecar  # noqa: E402

FIX = os.path.join(D6_ROOT, "fixtures")


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


class D6TestBase(unittest.TestCase):
    def setUp(self):
        self.workdir = tempfile.mkdtemp(prefix="d6-test-")
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

    def _publish_target(self):
        return os.path.join(self.workdir, "publish", "pool-new.txt")

    def _served_target(self):
        return os.path.join(self.workdir, "served", "pool-new.txt")

    def _admitted(self):
        _meta, chain = read_chain_sidecar(
            os.path.join(self.workdir, "publish"), "pool-new.txt")
        self.assertIsNotNone(chain)
        admitted, _cond, gdiag = load_native_allowlist(
            self.record_path, chain["source_sha"],
            probe_db=self.probe_db, now=self.now)
        self.assertFalse(gdiag.get("error"))
        return chain, admitted


class TestItem1ServedQuarantine(D6TestBase):
    """D6 item 1: served pollution is quarantined + restored, never
    left at the served path; the pool still stays STOP."""

    def test_served_tamper_quarantines_and_restores(self):
        """E3 on D6: served tampered post-copy -> rc=1
        sync_served_gate_failed + degraded, BUT the served path now
        holds the restored verified bytes and the polluted bytes live
        only in served/.quarantine/ (mode 600)."""
        self._seed_clean_synced()
        before = file_manifest(self._served_target())
        self.assertEqual(before["sha256"], self.clean_sha)

        def _tamper(served_path):
            with open(served_path, "a", encoding="utf-8") as f:
                f.write(self.failed_lines[0] + "\n")

        rc, res = run_sync(self.workdir, self.record_path, self.version_sha,
                           probe_db=self.probe_db, now=self.now,
                           post_copy_hook=_tamper)
        self.assertEqual(rc, 1, res)
        self.assertEqual(res.get("error"), "sync_served_gate_failed")
        self.assertFalse(res.get("served_verified"))
        # The served path no longer exposes the polluted bytes.
        after = file_manifest(self._served_target())
        self.assertEqual(after["sha256"], self.clean_sha)
        self.assertEqual(after["lines"], 14)
        # The polluted bytes are quarantined, mode 600, with the
        # recorded manifest.
        qr = res.get("served_quarantine") or {}
        self.assertTrue(res.get("served_restored"))
        self.assertEqual(
            (qr.get("quarantined") or {}).get("sha256"), self.polluted_sha)
        self.assertEqual((qr.get("quarantined") or {}).get("lines"), 15)
        self.assertEqual(
            (res.get("served_restored_manifest") or {}).get("sha256"),
            self.clean_sha)
        qdir = os.path.join(os.path.dirname(self._served_target()),
                            ".quarantine")
        qtxt = [f for f in os.listdir(qdir) if f.endswith(".txt")]
        self.assertEqual(len(qtxt), 1, qtxt)
        qpath = os.path.join(qdir, qtxt[0])
        self.assertEqual(_sha_file(qpath), self.polluted_sha)
        self.assertEqual(stat.S_IMODE(os.stat(qpath).st_mode), 0o600)
        # Degraded: the gate still refuses everything until recovery.
        allowed, err, _st = gate_check(self.workdir)
        self.assertFalse(allowed)
        self.assertEqual(err, "pool_stopped")
        rc, res2 = run_sync(self.workdir, self.record_path,
                            self.version_sha, probe_db=self.probe_db,
                            now=self.now)
        self.assertEqual(rc, 1)
        self.assertEqual(res2.get("error"), "pool_stopped")

    def test_served_symlink_refuses(self):
        """A served path that is a symlink refuses before any byte is
        read or written (the link could point at the bridge dir)."""
        self._seed_clean_synced()
        served = self._served_target()
        decoy = os.path.join(self.workdir, "decoy.txt")
        _write_lines(decoy, self.clean14)
        os.unlink(served)
        os.symlink(decoy, served)
        rc, res = run_sync(self.workdir, self.record_path, self.version_sha,
                           probe_db=self.probe_db, now=self.now)
        self.assertEqual(rc, 1, res)
        self.assertEqual(res.get("error"), "served_symlink_refused")
        # The symlink itself is untouched, no quarantine was created.
        self.assertTrue(os.path.islink(served))
        self.assertFalse(os.path.exists(
            os.path.join(os.path.dirname(served), ".quarantine")))

    def test_quarantine_restore_failure_leaves_served_absent(self):
        """Direct helper test: when the publish file itself is no
        longer restorable (SHA != chain published_sha), the served
        path is left ABSENT -- never with unverified bytes -- and
        restored=False, while the polluted bytes are still
        quarantined."""
        self._seed_clean_synced()
        chain, admitted = self._admitted()
        # Corrupt the publish file, then tamper served.
        _write_lines(self._publish_target(), ["garbage line"])
        with open(self._served_target(), "a", encoding="utf-8") as f:
            f.write(self.failed_lines[0] + "\n")
        qr = _quarantine_and_restore_served(
            self.workdir, chain, admitted, self.now)
        self.assertEqual((qr.get("quarantined") or {}).get("sha256"),
                         self.polluted_sha)
        self.assertFalse(qr["restored"])
        self.assertIsNone(qr["restored_manifest"])
        self.assertFalse(os.path.exists(self._served_target()))
        qdir = os.path.join(os.path.dirname(self._served_target()),
                            ".quarantine")
        qtxt = [f for f in os.listdir(qdir) if f.endswith(".txt")]
        self.assertEqual(len(qtxt), 1)
        self.assertEqual(_sha_file(os.path.join(qdir, qtxt[0])),
                         self.polluted_sha)


class TestItem2BridgeSync(D6TestBase):
    """D6 item 2: one lock + one immutable snapshot + dual-target
    atomicity for the bridge step."""

    def _bridge_root(self):
        root = tempfile.mkdtemp(prefix="d6-bridge-")
        self.addCleanup(shutil.rmtree, root, ignore_errors=True)
        bridge = os.path.join(root, "bridge")
        os.makedirs(bridge, exist_ok=True)
        return root, bridge

    def test_bridge_sync_success(self):
        self._seed_clean_synced()
        _root, bridge = self._bridge_root()
        old_path = os.path.join(bridge, "old-pool.txt")
        rc, res = run_bridge_sync(
            self.workdir, bridge, old_path=old_path,
            native_record_path=self.record_path, probe_db=self.probe_db,
            now=self.now)
        self.assertEqual(rc, 0, res)
        self.assertTrue(res.get("ok"))
        self.assertTrue(res.get("bridge_updated_verified"))
        self.assertEqual(_sha_file(bridge + "/pool-new.txt"), self.clean_sha)
        self.assertEqual(_sha_file(old_path), self.clean_sha)
        self.assertEqual(stat.S_IMODE(
            os.stat(bridge + "/pool-new.txt").st_mode), 0o644)
        self.assertEqual(res.get("served_snapshot_sha"), self.clean_sha)

    def test_bridge_sync_served_tampered_before_bridge(self):
        """Served rewritten between sync and bridge: the bridge step
        re-verifies the actual bytes in-lock, refuses, quarantines +
        restores served, and the bridge keeps its previous bytes."""
        self._seed_clean_synced()
        _root, bridge = self._bridge_root()
        old_version = [l for l in self.pool44 if l != self.failed_lines[0]]
        _write_lines(bridge + "/pool-new.txt", old_version)
        old_sha = _sha_lines(old_version)
        with open(self._served_target(), "a", encoding="utf-8") as f:
            f.write(self.failed_lines[0] + "\n")
        rc, res = run_bridge_sync(
            self.workdir, bridge, native_record_path=self.record_path,
            probe_db=self.probe_db, now=self.now)
        self.assertEqual(rc, 1, res)
        self.assertTrue(str(res.get("error", "")).startswith(
            "bridge_served_chain_"), res)
        self.assertFalse(res.get("ok"))
        # Bridge untouched (previous bytes), served restored.
        self.assertEqual(_sha_file(bridge + "/pool-new.txt"), old_sha)
        self.assertEqual(_sha_file(self._served_target()), self.clean_sha)
        self.assertTrue(res.get("served_restored"))
        # Degraded: the next sync refuses until manual recovery.
        allowed, err, _st = gate_check(self.workdir)
        self.assertFalse(allowed)
        self.assertEqual(err, "pool_stopped")

    def test_bridge_sync_served_rewritten_during_rename(self):
        """The D6 race injection: served is rewritten AFTER the
        snapshot was taken and BEFORE the bridge rename. The bridge
        must still receive ONLY the verified snapshot bytes."""
        self._seed_clean_synced()
        _root, bridge = self._bridge_root()

        def _rewrite_served(_tmp_path):
            with open(self._served_target(), "a", encoding="utf-8") as f:
                f.write(self.failed_lines[0] + "\n")

        rc, res = run_bridge_sync(
            self.workdir, bridge, native_record_path=self.record_path,
            probe_db=self.probe_db, now=self.now,
            pre_bridge_rename_hook=_rewrite_served)
        # The bridge got the verified snapshot bytes; the run still
        # fails (rc=1) because the served tamper was detected and
        # contained, and the pool enters degraded.
        self.assertEqual(rc, 1, res)
        self.assertEqual(res.get("error"), "served_changed_after_bridge_copy")
        self.assertTrue(res.get("bridge_updated_verified"))
        self.assertEqual(_sha_file(bridge + "/pool-new.txt"), self.clean_sha)
        self.assertEqual(res.get("served_snapshot_sha"), self.clean_sha)
        # Served was quarantined + restored, not left polluted.
        self.assertTrue(res.get("served_restored"))
        self.assertEqual(_sha_file(self._served_target()), self.clean_sha)
        qdir = os.path.join(os.path.dirname(self._served_target()),
                            ".quarantine")
        qtxt = [f for f in os.listdir(qdir) if f.endswith(".txt")]
        self.assertEqual(len(qtxt), 1)
        self.assertEqual(_sha_file(os.path.join(qdir, qtxt[0])),
                         self.polluted_sha)
        allowed, err, _st = gate_check(self.workdir)
        self.assertFalse(allowed)
        self.assertEqual(err, "pool_stopped")

    def test_bridge_sync_legacy_failure_rolls_back_bridge(self):
        """Legacy $OLD write failure: rc=1 legacy_copy_failed, the
        bridge is rolled back to its pre-run bytes, and the run never
        claims success."""
        self._seed_clean_synced()
        _root, bridge = self._bridge_root()
        old_version = [l for l in self.pool44 if l != self.failed_lines[0]]
        _write_lines(bridge + "/pool-new.txt", old_version)
        old_sha = _sha_lines(old_version)
        bad_old = os.path.join(bridge, "no-such-dir", "old-pool.txt")
        rc, res = run_bridge_sync(
            self.workdir, bridge, old_path=bad_old,
            native_record_path=self.record_path, probe_db=self.probe_db,
            now=self.now)
        self.assertEqual(rc, 1, res)
        self.assertEqual(res.get("error"), "legacy_copy_failed")
        self.assertFalse(res.get("ok"))
        self.assertFalse(res.get("bridge_updated_verified"))
        self.assertTrue(res.get("bridge_rolled_back"))
        # Bridge holds its pre-run bytes, legacy was never written.
        self.assertEqual(_sha_file(bridge + "/pool-new.txt"), old_sha)
        self.assertFalse(os.path.exists(bad_old))
        self.assertEqual(
            (res.get("bridge_manifest_after_rollback") or {}).get("sha256"),
            old_sha)

    def test_bridge_sync_served_symlink_refuses(self):
        self._seed_clean_synced()
        _root, bridge = self._bridge_root()
        served = self._served_target()
        decoy = os.path.join(self.workdir, "decoy.txt")
        _write_lines(decoy, self.clean14)
        os.unlink(served)
        os.symlink(decoy, served)
        rc, res = run_bridge_sync(
            self.workdir, bridge, native_record_path=self.record_path,
            probe_db=self.probe_db, now=self.now)
        self.assertEqual(rc, 1, res)
        self.assertEqual(res.get("error"), "served_symlink_refused")
        self.assertFalse(os.path.exists(bridge + "/pool-new.txt"))


class TestWrapperBridgeAndExit(D6TestBase):
    """gate-sync.sh / gate-publish.sh end to end with the REAL wrapper
    scripts, a stub assembler, and synthetic fixtures (same harness
    shape as test_d5_cycle.py)."""

    def _build_wrapper_root(self, stub_mode="2"):
        root = tempfile.mkdtemp(prefix="d6-wrap-")
        self.addCleanup(shutil.rmtree, root, ignore_errors=True)
        prog = os.path.join(root, "prog")
        gate = os.path.join(root, "gate")
        bridge = os.path.join(root, "bridge")
        for d in [prog + "/publish", prog + "/gate", prog + "/config",
                  prog + "/venv/bin", gate + "/state", gate + "/logs",
                  bridge, root + "/versions"]:
            os.makedirs(d, exist_ok=True)
        shutil.copytree(os.path.join(D6_ROOT, "pool"), gate + "/pool")
        for f in ["gate-publish.sh", "gate-sync.sh",
                  "validate-native-record.py"]:
            shutil.copy(os.path.join(D6_ROOT, "systemd", f),
                        gate + "/" + f)
            os.chmod(gate + "/" + f, 0o755)
        v2 = [l for l in self.pool44 if l != self.failed_lines[0]]
        _write_lines(root + "/versions/v1.txt", self.pool44)
        _write_lines(root + "/versions/v2.txt", v2)
        self.sha1 = _sha_lines(self.pool44)
        self.sha2 = _sha_lines(v2)
        stub = '''#!/usr/bin/env python3
import os, shutil, sys
root = os.environ["REHEARSAL_ROOT"]
mode = open(os.path.join(root, "prog", ".asm_mode")).read().strip()
dst = os.path.join(root, "prog", "publish", "pool-new.txt")
if mode == "2":
    shutil.copyfile(os.path.join(root, "versions", "v2.txt"), dst)
    print("{\\"ok\\": true, \\"assembled_version\\": 2}")
elif mode == "torn":
    lines = open(os.path.join(root, "versions", "v2.txt")).read().splitlines()
    open(dst, "w").write("\\n".join(lines[:20]) + "\\n")
    print("torn write, crashing", file=sys.stderr)
    sys.exit(1)
elif mode == "atomictmp":
    shutil.copyfile(os.path.join(root, "versions", "v2.txt"), dst + ".tmp")
    print("atomic assembly crashed, only .tmp left", file=sys.stderr)
    sys.exit(1)
else:
    print("unknown mode", file=sys.stderr)
    sys.exit(1)
'''
        stub_path = prog + "/venv/bin/python"
        with open(stub_path, "w") as _f:
            _f.write(stub)
        os.chmod(stub_path, 0o755)
        with open(prog + "/.asm_mode", "w") as _f:
            _f.write(stub_mode)
        shutil.copyfile(root + "/versions/v1.txt",
                        prog + "/publish/pool-new.txt")
        now = int(time.time())
        with open(self.record_path) as _f:
            record = json.load(_f)
        v1_results = record["runs"][0]["results"]
        rec = {"format": "native-results-v1", "runs": [{
            "version_sha": self.sha1,
            "tested_at": now - 3600,
            "tested_at_cst": "",
            "network": "5G cellular pdp_ip0, no Wi-Fi",
            "surge": "6.100.0 build 4025",
            "results": v1_results}]}
        rec_path = prog + "/gate/native-results.json"
        with open(rec_path, "w") as _f:
            json.dump(rec, _f)
        with open(prog + "/config/old-pool-file.txt", "w") as f:
            f.write(bridge + "/old-pool.txt")
        env = dict(os.environ)
        env.update({
            "REHEARSAL_ROOT": root,
            "PROG": prog, "GATE": gate, "RECORD": rec_path,
            "PROBE_DB": os.path.join(FIX, "p0_fixture.db"),
            "BRIDGE_DIR": bridge,
            "GATE_PY": sys.executable, "PROD_PY": stub_path,
        })
        ctx = {"root": root, "prog": prog, "gate": gate, "bridge": bridge,
               "env": env, "rec_path": rec_path}
        p = subprocess.run(
            [sys.executable, "-m", "pool.recovery", "init",
             "--workdir", gate + "/state",
             "--owner-ack", OWNER_ACK_INIT],
            capture_output=True, text=True, cwd=gate, timeout=60)
        self.assertEqual(p.returncode, 0, p.stdout + p.stderr)
        return ctx

    def _run_wrapper(self, ctx, name, env=None):
        p = subprocess.run(["bash", ctx["gate"] + "/" + name],
                           capture_output=True, text=True,
                           env=env or ctx["env"], timeout=120)
        return p.returncode

    def _health(self, ctx):
        path = ctx["gate"] + "/logs/health.json"
        if not os.path.exists(path):
            return {}
        with open(path) as _f:
            return json.load(_f)

    def _gate_sync_log(self, ctx):
        path = ctx["gate"] + "/logs/gate-sync.log"
        if not os.path.exists(path):
            return ""
        with open(path) as _f:
            return _f.read()

    def test_wrapper_bridge_sync_happy_path(self):
        ctx = self._build_wrapper_root(stub_mode="2")
        self.assertEqual(self._run_wrapper(ctx, "gate-publish.sh"), 0)
        self.assertEqual(self._run_wrapper(ctx, "gate-sync.sh"), 0)
        self.assertEqual(_sha_file(ctx["bridge"] + "/pool-new.txt"),
                         self.clean_sha)
        self.assertEqual(_sha_file(ctx["bridge"] + "/old-pool.txt"),
                         self.clean_sha)
        self.assertEqual(
            _sha_file(ctx["gate"] + "/state/served/pool-new.txt"),
            self.clean_sha)

    def test_wrapper_legacy_failure_fails_and_rolls_back(self):
        ctx = self._build_wrapper_root(stub_mode="2")
        self.assertEqual(self._run_wrapper(ctx, "gate-publish.sh"), 0)
        self.assertEqual(self._run_wrapper(ctx, "gate-sync.sh"), 0)
        self.assertEqual(_sha_file(ctx["bridge"] + "/pool-new.txt"),
                         self.clean_sha)
        # Break the legacy target: manifest now points into a
        # nonexistent directory, so the legacy copy must fail.
        with open(ctx["prog"] + "/config/old-pool-file.txt", "w") as f:
            f.write(ctx["bridge"] + "/no-such-dir/old-pool.txt")
        rc = self._run_wrapper(ctx, "gate-sync.sh")
        self.assertEqual(rc, 1, "legacy failure must fail the run")
        self.assertIn("legacy_copy_failed", self._gate_sync_log(ctx))
        # Bridge rolled back to its pre-run (verified) bytes.
        self.assertEqual(_sha_file(ctx["bridge"] + "/pool-new.txt"),
                         self.clean_sha)
        self.assertFalse(os.path.exists(
            ctx["bridge"] + "/no-such-dir/old-pool.txt"))

    def test_wrapper_served_inside_bridge_dir_refuses(self):
        ctx = self._build_wrapper_root(stub_mode="2")
        self.assertEqual(self._run_wrapper(ctx, "gate-publish.sh"), 0)
        env = dict(ctx["env"])
        env["BRIDGE_DIR"] = ctx["gate"] + "/state/served"
        rc = self._run_wrapper(ctx, "gate-sync.sh", env=env)
        self.assertEqual(rc, 1, "served inside bridge dir must refuse")
        self.assertIn("served_path_exposure_check",
                      self._gate_sync_log(ctx))
        # Nothing was copied anywhere.
        self.assertFalse(os.path.exists(
            ctx["gate"] + "/state/served/pool-new.txt"))

    def test_wrapper_publish_healthy_exit_0(self):
        ctx = self._build_wrapper_root(stub_mode="2")
        rc = self._run_wrapper(ctx, "gate-publish.sh")
        self.assertEqual(rc, 0)
        self.assertEqual(self._health(ctx)["health"], "healthy")
        self.assertEqual(self._health(ctx)["gate_rc"], 0)
        self.assertEqual(self._health(ctx)["assembly_rc"], 0)

    def test_wrapper_publish_assembly_failure_exit_2(self):
        ctx = self._build_wrapper_root(stub_mode="torn")
        rc = self._run_wrapper(ctx, "gate-publish.sh")
        self.assertEqual(rc, 2, "gate ok + assembly failed -> exit 2")
        self.assertEqual(self._health(ctx)["health"],
                         "published_assembly_failed")
        self.assertEqual(self._health(ctx)["gate_rc"], 0)
        self.assertEqual(self._health(ctx)["assembly_rc"], 1)

    def test_wrapper_next_cycle_on_torn_source_refuses(self):
        """Next round does not misjudge: after a torn assembly
        (exit 2), the next :07 gates the TORN source, refuses
        (exit 1, health gate_refused), and served/bridge stay clean."""
        ctx = self._build_wrapper_root(stub_mode="torn")
        self.assertEqual(self._run_wrapper(ctx, "gate-publish.sh"), 2)
        self.assertEqual(self._run_wrapper(ctx, "gate-sync.sh"), 0)
        self.assertEqual(_sha_file(ctx["bridge"] + "/pool-new.txt"),
                         self.clean_sha)
        # Next cycle: same torn $SRC, no new evidence -> gate refuses.
        rc = self._run_wrapper(ctx, "gate-publish.sh")
        self.assertEqual(rc, 1)
        self.assertEqual(self._health(ctx)["health"], "gate_refused")
        self.assertEqual(self._health(ctx)["gate_rc"], 1)
        self.assertEqual(_sha_file(ctx["bridge"] + "/pool-new.txt"),
                         self.clean_sha)
        self.assertEqual(
            _sha_file(ctx["gate"] + "/state/served/pool-new.txt"),
            self.clean_sha)

    def test_wrapper_next_cycle_atomic_crash_revalidates(self):
        """Atomic assembly crash (only .tmp left, $SRC still v1):
        first cycle exits 2, the NEXT cycle re-gates the same v1
        source and exits 0 healthy -- the assembly failure was not
        mistaken for a publish failure."""
        ctx = self._build_wrapper_root(stub_mode="atomictmp")
        rc = self._run_wrapper(ctx, "gate-publish.sh")
        self.assertEqual(rc, 2)
        self.assertEqual(self._health(ctx)["health"],
                         "published_assembly_failed")
        self.assertEqual(_sha_file(ctx["prog"] + "/publish/pool-new.txt"),
                         self.sha1)
        with open(ctx["prog"] + "/.asm_mode", "w") as _f:
            _f.write("2")
        rc = self._run_wrapper(ctx, "gate-publish.sh")
        self.assertEqual(rc, 0)
        self.assertEqual(self._health(ctx)["health"], "healthy")

    def test_wrapper_gate_refused_and_assembly_failed_exit_1(self):
        """Gate refused dominates: gate=1 + assembly=1 exits 1
        (health gate_refused), never 2."""
        ctx = self._build_wrapper_root(stub_mode="torn")
        # Point $SRC at untested v2 before the first publish.
        shutil.copyfile(ctx["root"] + "/versions/v2.txt",
                        ctx["prog"] + "/publish/pool-new.txt")
        rc = self._run_wrapper(ctx, "gate-publish.sh")
        self.assertEqual(rc, 1)
        self.assertEqual(self._health(ctx)["health"], "gate_refused")
        self.assertEqual(self._health(ctx)["gate_rc"], 1)
        self.assertEqual(self._health(ctx)["assembly_rc"], 1)


if __name__ == "__main__":
    unittest.main()
