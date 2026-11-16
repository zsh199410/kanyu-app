"""D5 test suite (GPT D4 review 6887331723, cross-cycle timing).

D4's gate-publish.sh gates the CURRENT source, then assembles the NEXT
version; a pass for v1 must never authorize v2's publish or its sync
admission. D5 closes the remaining final-byte gaps:

  * publish re-verifies the ACTUAL tmp bytes before the rename
    (SHA vs the chain's published_sha + native allowlist re-gate) and
    re-reads the target after the write. A mismatch refuses with
    `publish_postwrite_verify_failed`, deletes the tmp file, and
    leaves the target's previous bytes in place (SHA unchanged).
  * sync re-reads the SERVED file's actual bytes after the copy and
    re-checks them against the chain's published_sha + the allowlist
    gate. A mismatch refuses with `sync_served_gate_failed` and
    enters the degraded state; the served file is never claimed as
    success.
  * gate-publish.sh writes a cycle binding record after the assembly
    step (pass or fail) stating new_source_gated=false.
  * gate-sync.sh checks the served_version_sha sync REPORTED against
    the served file's actual SHA before copying to the bridge.

RED-ON-D4 DESIGN. The fault-injection tests (tmp tamper, rename-time
tamper) FAIL on the D4 tree -- D4 leaves renamed-but-unverified bytes
in the target (publish) and has no served re-gate step (sync) -- and
PASS on the D5 tree. The wrapper tests assert the new cycle record
and the pre-bridge check, which do not exist at all on D4.
Run the red check with this file copied into the D4 tree's tests/
directory: python3 -m unittest tests.test_d5_cycle -v (expect
failures), then in the D5 tree: python3 -m unittest tests.test_d5_cycle
-v (expect all green).

HONEST BOUNDARY -- fixtures are SYNTHETIC (fixtures/build_fixtures.py):
TEST-NET hosts, password TEST-ONLY-NOT-A-REAL-NODE. A fixture run
passing the gate proves the CODE paths, never that a real phone
measured anything.

Run: python3 -m unittest tests.test_d5_cycle -v   (from the D5 root)
"""

import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
from unittest import mock

HERE = os.path.dirname(os.path.abspath(__file__))
D5_ROOT = os.path.dirname(HERE)
sys.path.insert(0, D5_ROOT)

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

from pool.phone_gate import fingerprint_of, parse_surge_line  # noqa: E402
from pool.publish import run_publish  # noqa: E402
from pool.publish_lock import file_manifest  # noqa: E402
from pool.recovery import OWNER_ACK_INIT, gate_check, init_recovery_state  # noqa: E402
from pool.sync import run_sync  # noqa: E402

FIX = os.path.join(D5_ROOT, "fixtures")


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


class D5TestBase(unittest.TestCase):
    def setUp(self):
        self.workdir = tempfile.mkdtemp(prefix="d5-test-")
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


class TestPublishPostwriteVerify(D5TestBase):
    """publish verifies the FINAL bytes, not only in-memory lines."""

    def test_publish_success_carries_postwrite_proof(self):
        rc, res = run_publish(
            self.workdir, self.clean14, self.record_path, self.version_sha,
            probe_db=self.probe_db, now=self.now,
            source_file=self.pool44_path)
        self.assertEqual(rc, 0, res)
        self.assertTrue(res.get("postwrite_verified"))
        after = res.get("published_manifest_after")
        self.assertIsNotNone(after)
        self.assertEqual(after["sha256"], self.clean_sha)
        self.assertEqual(after["lines"], 14)
        self.assertEqual(_sha_file(self._publish_target()), self.clean_sha)

    def test_publish_tmp_tamper_refuses_and_target_unchanged(self):
        """A torn write landing in the tmp file (pre-rename) must be
        caught by the final-byte check: rc=1, target SHA unchanged,
        no tmp file left behind."""
        self._seed_clean_synced()
        before = file_manifest(self._publish_target())
        self.assertEqual(before["sha256"], self.clean_sha)

        def _tamper(tmp_path):
            with open(tmp_path, "a", encoding="utf-8") as f:
                f.write(self.failed_lines[0] + "\n")

        rc, res = run_publish(
            self.workdir, self.clean14, self.record_path, self.version_sha,
            probe_db=self.probe_db, now=self.now,
            source_file=self.pool44_path, pre_rename_hook=_tamper)
        self.assertEqual(rc, 1, res)
        self.assertEqual(res.get("error"), "publish_postwrite_verify_failed")
        self.assertFalse(res.get("postwrite_verified"))
        after = file_manifest(self._publish_target())
        self.assertEqual(after["sha256"], self.clean_sha)
        self.assertEqual(after["lines"], 14)
        self.assertFalse(os.path.exists(self._publish_target() + ".tmp"))
        self.assertEqual(res.get("published_manifest_after")["sha256"],
                         self.clean_sha)

    def test_publish_rename_time_tamper_restores_target(self):
        """Tamper injected AT the rename (after the pre-rename check
        passed) must still be caught by the post-rename check, and the
        previous bytes restored -- D4 leaves the corrupted bytes in
        the target, D5 does not."""
        self._seed_clean_synced()
        before = file_manifest(self._publish_target())
        self.assertEqual(before["sha256"], self.clean_sha)
        real_rename = os.rename
        tampered = []

        def _rename_once(src, dst):
            if (not tampered and isinstance(src, str)
                    and src.endswith(".tmp")
                    and dst == self._publish_target()):
                tampered.append(True)
                with open(src, "a", encoding="utf-8") as f:
                    f.write(self.failed_lines[0] + "\n")
            return real_rename(src, dst)

        with mock.patch("os.rename", side_effect=_rename_once):
            rc, res = run_publish(
                self.workdir, self.clean14, self.record_path,
                self.version_sha, probe_db=self.probe_db, now=self.now,
                source_file=self.pool44_path)
        self.assertTrue(tampered, "rename hook never fired")
        self.assertEqual(rc, 1, res)
        self.assertEqual(res.get("error"), "publish_postwrite_verify_failed")
        after = file_manifest(self._publish_target())
        self.assertEqual(after["sha256"], self.clean_sha)
        self.assertEqual(after["lines"], 14)


class TestSyncServedVerify(D5TestBase):
    """sync re-verifies the SERVED file's actual bytes."""

    def test_sync_success_carries_served_proof(self):
        self._seed_clean_synced()
        rc, res = run_sync(self.workdir, self.record_path, self.version_sha,
                           probe_db=self.probe_db, now=self.now)
        self.assertEqual(rc, 0, res)
        self.assertTrue(res.get("served_verified"))
        self.assertEqual(res.get("served_version_sha"), self.clean_sha)

    def test_sync_served_tamper_refuses_and_degrades(self):
        """Served bytes tampered after the copy must be refused with
        sync_served_gate_failed (not claimed as success) and the pool
        must enter the degraded state."""
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
        self.assertIsNotNone(res.get("served_manifest_after_copy"))
        # Degraded: the gate now refuses everything until recovery.
        allowed, err, _st = gate_check(self.workdir)
        self.assertFalse(allowed)
        self.assertEqual(err, "pool_stopped")
        # The tampered served bytes are recorded, never claimed ok.
        self.assertFalse(res.get("ok"))


class TestWrapperCycleBinding(D5TestBase):
    """gate-publish.sh cycle record + gate-sync.sh pre-bridge check,
    run against the REAL wrapper scripts with a stub assembler."""

    def _build_wrapper_root(self, stub_mode="2"):
        root = tempfile.mkdtemp(prefix="d5-wrap-")
        self.addCleanup(shutil.rmtree, root, ignore_errors=True)
        prog = os.path.join(root, "prog")
        gate = os.path.join(root, "gate")
        bridge = os.path.join(root, "bridge")
        for d in [prog + "/publish", prog + "/gate", prog + "/config",
                  prog + "/venv/bin", gate + "/state", gate + "/logs",
                  bridge, root + "/versions"]:
            os.makedirs(d, exist_ok=True)
        shutil.copytree(os.path.join(D5_ROOT, "pool"), gate + "/pool")
        for f in ["gate-publish.sh", "gate-sync.sh",
                  "validate-native-record.py"]:
            shutil.copy(os.path.join(D5_ROOT, "systemd", f),
                        gate + "/" + f)
            os.chmod(gate + "/" + f, 0o755)
        # v1 = pool44, v2 = pool44 minus one failed line (new SHA,
        # no native evidence for v2).
        v2 = [l for l in self.pool44 if l != self.failed_lines[0]]
        _write_lines(root + "/versions/v1.txt", self.pool44)
        _write_lines(root + "/versions/v2.txt", v2)
        self.sha1 = _sha_lines(self.pool44)
        self.sha2 = _sha_lines(v2)
        # Stub assembler: mode file selects the behaviour.
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
        # Fresh native record for v1 only (tested 1h ago, wall clock).
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

    def _run_wrapper(self, ctx, name):
        p = subprocess.run(["bash", ctx["gate"] + "/" + name],
                           capture_output=True, text=True, env=ctx["env"],
                           timeout=120)
        return p.returncode

    def _cycle_records(self, ctx):
        logs = os.path.join(ctx["gate"], "logs")
        out = []
        for f in sorted(os.listdir(logs)):
            if f.startswith("cycle-") and f.endswith(".json"):
                with open(os.path.join(logs, f)) as fh:
                    out.append(json.load(fh))
        return out

    def test_gate_publish_writes_cycle_binding_record(self):
        ctx = self._build_wrapper_root(stub_mode="2")
        rc = self._run_wrapper(ctx, "gate-publish.sh")
        self.assertEqual(rc, 0, "gate should pass v1")
        # Assembly advanced the source to v2.
        self.assertEqual(_sha_file(ctx["prog"] + "/publish/pool-new.txt"),
                         self.sha2)
        recs = self._cycle_records(ctx)
        self.assertEqual(len(recs), 1, recs)
        rec = recs[0]
        self.assertEqual(rec["gated_source_sha"], self.sha1[:12])
        self.assertEqual(rec["published_sha"], self.clean_sha[:12])
        self.assertEqual(rec["new_source_sha"], self.sha2[:12])
        self.assertIs(rec["new_source_gated"], False)
        self.assertEqual(rec["assembly_rc"], 0)
        self.assertIs(rec["assembly_failed"], False)
        self.assertIs(rec["src_changed"], True)
        with open(ctx["gate"] + "/logs/gate-publish.log") as _f:
            log = _f.read()
        self.assertIn("new_source_gated=false", log)
        # D6: healthy cycle writes health=healthy and exits 0.
        with open(ctx["gate"] + "/logs/health.json") as _f:
            health = json.load(_f)
        self.assertEqual(health["health"], "healthy")
        self.assertEqual(health["gate_rc"], 0)
        self.assertEqual(health["assembly_rc"], 0)

    def test_gate_publish_cycle_record_on_assembly_failure(self):
        ctx = self._build_wrapper_root(stub_mode="torn")
        rc = self._run_wrapper(ctx, "gate-publish.sh")
        # D6 (GPT D5 review 6887615694, item 3): gate passed v1 but the
        # assembly failed afterwards. D5 exited 0 here (exit "$GATE_RC")
        # and masked the assembly failure; D6 exits 2
        # (published_assembly_failed) and writes health.json.
        self.assertEqual(rc, 2, "gate passed, assembly failed -> exit 2")
        recs = self._cycle_records(ctx)
        self.assertEqual(len(recs), 1, recs)
        rec = recs[0]
        self.assertEqual(rec["gated_source_sha"], self.sha1[:12])
        self.assertIs(rec["new_source_gated"], False)
        self.assertEqual(rec["assembly_rc"], 1)
        self.assertIs(rec["assembly_failed"], True)
        self.assertIs(rec["src_changed"], True)
        with open(ctx["gate"] + "/logs/health.json") as _f:
            health = json.load(_f)
        self.assertEqual(health["health"], "published_assembly_failed")
        self.assertEqual(health["gate_rc"], 0)
        self.assertEqual(health["assembly_rc"], 1)
        self.assertEqual(health["gated_source_sha"], self.sha1[:12])
        self.assertIs(health["new_source_gated"], False)
        # The torn source is still on disk (truncated v2), not v1.
        self.assertNotEqual(
            _sha_file(ctx["prog"] + "/publish/pool-new.txt"), self.sha1)
        with open(ctx["gate"] + "/logs/gate-publish.log") as _f:
            log = _f.read()
        self.assertIn("new_source_gated=false", log)

    def test_gate_sync_prebridge_mismatch_refuses(self):
        ctx = self._build_wrapper_root(stub_mode="2")
        rc = self._run_wrapper(ctx, "gate-publish.sh")
        self.assertEqual(rc, 0)
        rc = self._run_wrapper(ctx, "gate-sync.sh")
        self.assertEqual(rc, 0)
        bridge_file = ctx["bridge"] + "/pool-new.txt"
        bridge_before = _sha_file(bridge_file)
        self.assertEqual(bridge_before, self.clean_sha)
        served_before = _sha_file(ctx["gate"] + "/state/served/pool-new.txt")
        self.assertEqual(served_before, self.clean_sha)
        # GATE_PY shim: run the real sync, then lie about the
        # served_version_sha in its JSON output.
        shim = '''#!/usr/bin/env python3
import json, os, subprocess, sys
real = os.environ["REAL_PY"]
if "pool.sync" in sys.argv:
    p = subprocess.run([real] + sys.argv[1:], capture_output=True,
                       text=True)
    try:
        d = json.loads(p.stdout)
        d["served_version_sha"] = "0" * 64
        print(json.dumps(d))
    except Exception:
        print(p.stdout, end="")
    sys.exit(p.returncode)
os.execv(real, [real] + sys.argv[1:])
'''
        shim_path = os.path.join(ctx["root"], "shim.py")
        with open(shim_path, "w") as _f:
            _f.write(shim)
        os.chmod(shim_path, 0o755)
        env = dict(ctx["env"])
        env["GATE_PY"] = shim_path
        env["REAL_PY"] = sys.executable
        ctx["env"] = env
        rc = self._run_wrapper(ctx, "gate-sync.sh")
        self.assertEqual(rc, 1, "pre-bridge SHA check must refuse")
        with open(ctx["gate"] + "/logs/gate-sync.log") as _f:
            log = _f.read()
        self.assertIn("served_sha_mismatch_before_bridge_copy", log)
        # Served and bridge both untouched by the refused copy.
        self.assertEqual(_sha_file(bridge_file), bridge_before)
        self.assertEqual(
            _sha_file(ctx["gate"] + "/state/served/pool-new.txt"),
            served_before)


if __name__ == "__main__":
    unittest.main()
