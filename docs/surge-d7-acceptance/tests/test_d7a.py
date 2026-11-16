"""D7a test suite (Issue #73, GPT D7 review 6912114134, item 1).

Dual-target inconsistency is now a SWITCHING GATE, not a detector
the next run silently repairs:

  * gate_block() (pool/bridge_sync.py, CLI --gate-block): called
    FIRST by gate-sync.sh, before pool.sync. On a concrete SHA
    divergence from the chain published_sha it latches STOP
    (reason targets_inconsistent:<detail>) and returns rc=1; the
    cycle runs no sync, touches no bridge/legacy, publishes
    nothing. The latch holds: publish.py already refuses while
    stopped (pool_stopped), and every later :07 / :15 cycle
    refuses the same way until a manual clear_stop (OWNER_ACK +
    fresh native evidence). "The next run repairs it" is no longer
    treated as zero risk during the fault window.
  * repair_targets() (CLI --repair-targets): the ONLY repair path
    for a latched divergence. Manual, under the shared lock:
    served re-verified (quarantine + restore from the
    chain-verified publish file when bad); the verified served
    bytes written to bridge + legacy from one in-memory snapshot;
    verify_targets must be consistent before rc=0; a repair
    manifest JSON is written (before/after SHAs, timestamp,
    repaired_by). Repair NEVER clears STOP by itself.
  * Boundary: when no chain exists yet (served_no_chain /
    chain_unreadable) gate_block passes through
    (skipped=no_chain_nothing_to_block) -- there is nothing to
    compare, and latching STOP there would deadlock the first
    sync. The sync/publish gates remain the authority for chain
    validity and fail closed on their own.

RED-ON-D7 DESIGN. These tests FAIL on the D7 tree (no gate_block /
repair_targets: ImportError / AttributeError) and PASS on the D7a
tree. See drills/d7a_redgreen.py.

Fixtures are SYNTHETIC (fixtures/build_fixtures.py): TEST-NET
hosts, password TEST-ONLY-NOT-A-REAL-NODE. Passing proves the code
paths, never that a real phone measured anything.

Run: python3 -m unittest tests.test_d7a -v   (from the D7a root)
"""

import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
D7A_ROOT = os.path.dirname(HERE)
sys.path.insert(0, D7A_ROOT)

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

from pool.bridge_sync import (  # noqa: E402
    gate_block, repair_targets, run_bridge_sync, verify_targets)
from pool.phone_gate import fingerprint_of, parse_surge_line  # noqa: E402
from pool.publish import run_publish  # noqa: E402
from pool.recovery import (  # noqa: E402
    OWNER_ACK_CLEAR, OWNER_ACK_INIT, clear_stop, gate_check,
    init_recovery_state)
from pool.sync import run_sync  # noqa: E402

FIX = os.path.join(D7A_ROOT, "fixtures")


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


class D7aTestBase(unittest.TestCase):
    def setUp(self):
        self.workdir = tempfile.mkdtemp(prefix="d7a-test-")
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

    def _seed_clean_synced_and_bridged(self):
        self._seed_clean_synced()
        root = tempfile.mkdtemp(prefix="d7a-bridge-")
        self.addCleanup(shutil.rmtree, root, ignore_errors=True)
        bridge = os.path.join(root, "bridge")
        os.makedirs(bridge, exist_ok=True)
        _write_lines(bridge + "/pool-new.txt", self.old_version)
        _write_lines(bridge + "/old-pool.txt", self.old_version)
        old_path = os.path.join(bridge, "old-pool.txt")
        rc, res = run_bridge_sync(
            self.workdir, bridge, old_path=old_path,
            native_record_path=self.record_path, probe_db=self.probe_db,
            now=self.now)
        self.assertEqual(rc, 0, res)
        return bridge, old_path

    def _served_path(self):
        return os.path.join(self.workdir, "served", "pool-new.txt")


class TestGateBlock(D7aTestBase):
    """gate_block(): the switching gate."""

    def test_gate_block_consistent_rc0(self):
        bridge, old_path = self._seed_clean_synced_and_bridged()
        rc, res = gate_block(self.workdir, bridge, old_path=old_path,
                             now=self.now)
        self.assertEqual(rc, 0, res)
        self.assertTrue(res.get("ok"))
        self.assertTrue(res["verify_targets"]["consistent"])
        allowed, _err, _state = gate_check(self.workdir)
        self.assertTrue(allowed)

    def test_gate_block_legacy_polluted_latches_stop(self):
        """Legacy holds polluted bytes (post-rename SHA failure left
        it there): gate-block rc=1 targets_inconsistent, STOP
        latched, publish refuses pool_stopped, served/bridge SHAs
        unchanged (the HTTP entry still serves the last verified
        version, not the polluted legacy)."""
        bridge, old_path = self._seed_clean_synced_and_bridged()
        with open(old_path, "a", encoding="utf-8") as f:
            f.write(self.failed_lines[0] + "\n")
        self.assertEqual(_sha_file(old_path), self.polluted_sha)
        rc, res = gate_block(self.workdir, bridge, old_path=old_path,
                             now=self.now)
        self.assertEqual(rc, 1, res)
        self.assertEqual(res.get("error"), "targets_inconsistent")
        self.assertEqual(res.get("detail"), "legacy_sha_mismatch")
        self.assertTrue(res.get("stop_latched"))
        self.assertEqual(res.get("stop_reason"),
                         "targets_inconsistent:legacy_sha_mismatch")
        # STOP is latched: publish refuses, served/bridge untouched.
        allowed, gerr, _state = gate_check(self.workdir)
        self.assertFalse(allowed)
        self.assertEqual(gerr, "pool_stopped")
        rc, pres = run_publish(
            self.workdir, self.clean14, self.record_path, self.version_sha,
            probe_db=self.probe_db, now=self.now,
            source_file=self.pool44_path)
        self.assertEqual(rc, 1, pres)
        self.assertEqual(pres.get("error"), "pool_stopped")
        self.assertEqual(_sha_file(self._served_path()), self.clean_sha)
        self.assertEqual(_sha_file(bridge + "/pool-new.txt"), self.clean_sha)
        self.assertEqual(_sha_file(old_path), self.polluted_sha)

    def test_gate_block_crash_divergence_latches_stop(self):
        """Crash between the two renames (bridge=new, legacy=old):
        gate-block detects legacy_sha_mismatch, latches STOP, and
        the next sync also refuses (pool_stopped) -- the divergence
        is not silently repaired by the next run."""
        self._seed_clean_synced()
        root = tempfile.mkdtemp(prefix="d7a-bridge-")
        self.addCleanup(shutil.rmtree, root, ignore_errors=True)
        bridge = os.path.join(root, "bridge")
        os.makedirs(bridge, exist_ok=True)
        _write_lines(bridge + "/pool-new.txt", self.old_version)
        _write_lines(bridge + "/old-pool.txt", self.old_version)
        old_path = os.path.join(bridge, "old-pool.txt")

        def _crash(_bridge_file):
            raise RuntimeError("simulated crash between renames (D7a)")

        with self.assertRaises(RuntimeError):
            run_bridge_sync(
                self.workdir, bridge, old_path=old_path,
                native_record_path=self.record_path, probe_db=self.probe_db,
                now=self.now, post_bridge_hook=_crash)
        self.assertEqual(_sha_file(bridge + "/pool-new.txt"), self.clean_sha)
        self.assertEqual(_sha_file(old_path), self.old_sha)
        rc, res = gate_block(self.workdir, bridge, old_path=old_path,
                             now=self.now)
        self.assertEqual(rc, 1, res)
        self.assertEqual(res.get("detail"), "legacy_sha_mismatch")
        self.assertTrue(res.get("stop_latched"))
        # The next sync refuses too: STOP is a latch, not a warning.
        rc, sres = run_sync(self.workdir, self.record_path,
                            self.version_sha, probe_db=self.probe_db,
                            now=self.now)
        self.assertEqual(rc, 1, sres)
        self.assertEqual(sres.get("error"), "pool_stopped")
        self.assertEqual(_sha_file(self._served_path()), self.clean_sha)
        self.assertEqual(_sha_file(bridge + "/pool-new.txt"), self.clean_sha)

    def test_gate_block_served_mismatch_latches_stop(self):
        """Served tampered after sync: gate-block flags
        served_sha_mismatch and latches STOP."""
        bridge, old_path = self._seed_clean_synced_and_bridged()
        with open(self._served_path(), "a", encoding="utf-8") as f:
            f.write(self.failed_lines[0] + "\n")
        rc, res = gate_block(self.workdir, bridge, old_path=old_path,
                             now=self.now)
        self.assertEqual(rc, 1, res)
        self.assertEqual(res.get("detail"), "served_sha_mismatch")
        self.assertTrue(res.get("stop_latched"))
        allowed, gerr, _state = gate_check(self.workdir)
        self.assertFalse(allowed)
        self.assertEqual(gerr, "pool_stopped")

    def test_gate_block_no_chain_passthrough(self):
        """Fresh workdir, state initialised but no publish/sync yet:
        no chain to compare against, gate-block passes through
        (skipped=no_chain_nothing_to_block) instead of deadlocking
        the first sync with a STOP that could never be cleared."""
        rc, res = gate_block(self.workdir, "/nonexistent-bridge",
                             now=self.now)
        self.assertEqual(rc, 0, res)
        self.assertTrue(res.get("ok"))
        self.assertEqual(res.get("skipped"), "no_chain_nothing_to_block")
        allowed, _err, _state = gate_check(self.workdir)
        self.assertTrue(allowed)


class TestRepairTargets(D7aTestBase):
    """repair_targets(): the only repair path for a latched STOP."""

    def _latch_legacy_polluted(self):
        bridge, old_path = self._seed_clean_synced_and_bridged()
        with open(old_path, "a", encoding="utf-8") as f:
            f.write(self.failed_lines[0] + "\n")
        rc, res = gate_block(self.workdir, bridge, old_path=old_path,
                             now=self.now)
        self.assertEqual(rc, 1, res)
        return bridge, old_path

    def test_repair_after_latch_three_targets_consistent(self):
        """After a latched legacy divergence: repair rc=0, all three
        targets hold clean14, verify_targets consistent, manifest
        records before/after SHAs. Repair does NOT clear STOP."""
        bridge, old_path = self._latch_legacy_polluted()
        mpath = os.path.join(self.workdir, "repair-manifest-test.json")
        rc, res = repair_targets(
            self.workdir, bridge, old_path=old_path,
            native_record_path=self.record_path, probe_db=self.probe_db,
            now=self.now, manifest_path=mpath)
        self.assertEqual(rc, 0, res)
        self.assertTrue(res.get("ok"))
        self.assertEqual(res["after"]["served_sha"], self.clean_sha)
        self.assertEqual(res["after"]["bridge_sha"], self.clean_sha)
        self.assertEqual(res["after"]["legacy_sha"], self.clean_sha)
        self.assertEqual(res["before"]["legacy_sha"], self.polluted_sha)
        self.assertEqual(res["before"]["bridge_sha"], self.clean_sha)
        vt = verify_targets(self.workdir, bridge, old_path=old_path)
        self.assertTrue(vt["consistent"])
        with open(mpath) as _f:
            man = json.load(_f)
        self.assertEqual(man["repaired_by"], "manual")
        self.assertEqual(man["published_sha"], self.clean_sha)
        self.assertEqual(man["before"]["legacy_sha"], self.polluted_sha)
        self.assertEqual(man["after"]["legacy_sha"], self.clean_sha)
        self.assertTrue(man["consistent"])
        # STOP is STILL latched: repair is not a clear.
        allowed, gerr, _state = gate_check(self.workdir)
        self.assertFalse(allowed)
        self.assertEqual(gerr, "pool_stopped")
        rc, sres = run_sync(self.workdir, self.record_path,
                            self.version_sha, probe_db=self.probe_db,
                            now=self.now)
        self.assertEqual(rc, 1, sres)
        self.assertEqual(sres.get("error"), "pool_stopped")

    def test_repair_then_clear_stop_restores_cycle(self):
        """Repair + clear_stop (OWNER_ACK + fresh native evidence)
        restores the cycle: gate-block rc=0 and publish rc=0 again."""
        bridge, old_path = self._latch_legacy_polluted()
        rc, res = repair_targets(
            self.workdir, bridge, old_path=old_path,
            native_record_path=self.record_path, probe_db=self.probe_db,
            now=self.now)
        self.assertEqual(rc, 0, res)
        rc, cres = clear_stop(self.workdir, OWNER_ACK_CLEAR,
                              self.record_path, probe_db=self.probe_db,
                              now=self.now)
        self.assertEqual(rc, 0, cres)
        allowed, _err, _state = gate_check(self.workdir)
        self.assertTrue(allowed)
        rc, res = gate_block(self.workdir, bridge, old_path=old_path,
                             now=self.now)
        self.assertEqual(rc, 0, res)
        rc, pres = run_publish(
            self.workdir, self.clean14, self.record_path, self.version_sha,
            probe_db=self.probe_db, now=self.now,
            source_file=self.pool44_path)
        self.assertEqual(rc, 0, pres)

    def test_repair_with_bad_served_quarantine_restore(self):
        """Served tampered (bad SHA) while publish holds the verified
        version: repair quarantines the polluted served file,
        restores it from publish, and all three targets end
        consistent."""
        bridge, old_path = self._seed_clean_synced_and_bridged()
        with open(self._served_path(), "a", encoding="utf-8") as f:
            f.write(self.failed_lines[0] + "\n")
        rc, res = gate_block(self.workdir, bridge, old_path=old_path,
                             now=self.now)
        self.assertEqual(rc, 1, res)
        self.assertEqual(res.get("detail"), "served_sha_mismatch")
        rc, res = repair_targets(
            self.workdir, bridge, old_path=old_path,
            native_record_path=self.record_path, probe_db=self.probe_db,
            now=self.now)
        self.assertEqual(rc, 0, res)
        self.assertTrue(res.get("served_restored"))
        self.assertEqual(_sha_file(self._served_path()), self.clean_sha)
        vt = verify_targets(self.workdir, bridge, old_path=old_path)
        self.assertTrue(vt["consistent"])
        qdir = os.path.join(self.workdir, "served", ".quarantine")
        self.assertTrue(os.path.isdir(qdir))
        self.assertTrue(any(n.startswith("pool-new-")
                            for n in os.listdir(qdir)))

    def test_repair_requires_native_record(self):
        bridge, old_path = self._seed_clean_synced_and_bridged()
        rc, res = repair_targets(self.workdir, bridge, old_path=old_path,
                                 native_record_path=None, now=self.now)
        self.assertEqual(rc, 1, res)
        self.assertEqual(res.get("error"), "repair_native_record_required")

    def test_repair_no_chain_refuses(self):
        rc, res = repair_targets(
            self.workdir, "/nonexistent-bridge",
            native_record_path=self.record_path, now=self.now)
        self.assertEqual(rc, 1, res)
        self.assertEqual(res.get("error"), "repair_served_missing")


class TestGateBlockCli(D7aTestBase):
    """CLI surface for the new modes."""

    def _cli(self, *argv):
        p = subprocess.run(
            [sys.executable, "-m", "pool.bridge_sync", *argv],
            capture_output=True, text=True, cwd=D7A_ROOT, timeout=60)
        try:
            return p.returncode, json.loads(p.stdout.strip() or "{}")
        except ValueError:
            return p.returncode, {"raw": p.stdout[:200] + p.stderr[:200]}

    def test_cli_gate_block_rc1_then_repair_rc0_then_gate_block_rc0(self):
        bridge, old_path = self._seed_clean_synced_and_bridged()
        with open(old_path, "a", encoding="utf-8") as f:
            f.write(self.failed_lines[0] + "\n")
        rc, out = self._cli("--gate-block", "--workdir", self.workdir,
                            "--bridge-dir", bridge,
                            "--old-path", old_path,
                            "--now", str(self.now))
        self.assertEqual(rc, 1, out)
        self.assertEqual(out.get("error"), "targets_inconsistent")
        rc, out = self._cli("--repair-targets", "--workdir", self.workdir,
                            "--bridge-dir", bridge,
                            "--old-path", old_path,
                            "--native-record", self.record_path,
                            "--probe-db", self.probe_db,
                            "--now", str(self.now))
        self.assertEqual(rc, 0, out)
        self.assertTrue(out.get("ok"))
        rc, out = self._cli("--gate-block", "--workdir", self.workdir,
                            "--bridge-dir", bridge,
                            "--old-path", old_path,
                            "--now", str(self.now))
        self.assertEqual(rc, 0, out)
        self.assertTrue(out.get("ok"))

    def test_cli_verify_targets_still_works(self):
        bridge, old_path = self._seed_clean_synced_and_bridged()
        rc, out = self._cli("--verify-targets", "--workdir", self.workdir,
                            "--bridge-dir", bridge,
                            "--old-path", old_path)
        self.assertEqual(rc, 0, out)
        self.assertTrue(out.get("consistent"))


class TestHttpRecheckParser(unittest.TestCase):
    """tools/http_recheck.py config parsing (D7a item 2)."""

    def test_entry_mapping_resolves_to_bridge_file(self):
        import tools.http_recheck as hr
        conf = ("location /m/ { alias /x/bridge/; }\n"
                "location / { return 404; }\n")
        mapping, violations = hr.check_config(
            conf, "/m/pool-new.txt", "/x/bridge/pool-new.txt",
            "/y/served/pool-new.txt")
        self.assertIsNotNone(mapping)
        self.assertTrue(mapping["resolves_to_bridge_file"])
        self.assertEqual(violations, [])

    def test_independent_alias_at_served_is_violation(self):
        import tools.http_recheck as hr
        conf = ("location /m/ { alias /x/bridge/; }\n"
                "location /alias-served/ { alias /y/served/; }\n")
        mapping, violations = hr.check_config(
            conf, "/m/pool-new.txt", "/x/bridge/pool-new.txt",
            "/y/served/pool-new.txt")
        self.assertTrue(mapping["resolves_to_bridge_file"])
        self.assertEqual(len(violations), 1)
        self.assertEqual(violations[0]["location"], "/alias-served/")
        self.assertEqual(violations[0]["reason"],
                         "alias_or_root_resolves_into_served_dir")

    def test_autoindex_is_violation(self):
        import tools.http_recheck as hr
        conf = ("location /m/ { alias /x/bridge/; autoindex on; }\n")
        _mapping, violations = hr.check_config(
            conf, "/m/pool-new.txt", "/x/bridge/pool-new.txt",
            "/y/served/pool-new.txt")
        self.assertTrue(any(v["reason"] == "autoindex_on"
                            for v in violations))

    def test_probe_set_has_seven_paths(self):
        import tools.http_recheck as hr
        probes = hr.build_probes("/m/pool-new.txt", "pool-new-x.txt")
        self.assertEqual(len(probes), 7)
        self.assertTrue(any(".." in p for p in probes))
        self.assertTrue(any(".quarantine" in p for p in probes))


class TestFreezeReal(D7aTestBase):
    """tools/freeze_real.py selection + evidence honesty (D7a item 3).

    Synthetic DBs only: a temp probe.db (probe_nodes), a temp
    pool.db (pinned + winner_reports), the fixture pool_44 as the
    "source" file. No real node URIs leave the test."""

    def _build_dbs(self, probe_rows=(), pinned_keys=()):
        import sqlite3
        probe_path = os.path.join(self.workdir, "probe.db")
        db = sqlite3.connect(probe_path)
        db.execute("CREATE TABLE probe_nodes (fingerprint TEXT, name TEXT,"
                   " state TEXT, last_phone_ts INTEGER, last_second_ms"
                   " INTEGER, last_success INTEGER, phone_ok INTEGER,"
                   " phone_fail INTEGER, last_seen_in_pool INTEGER)")
        for r in probe_rows:
            db.execute("INSERT INTO probe_nodes VALUES (?,?,?,?,?,?,?,?,?)",
                       r)
        db.commit()
        db.close()
        pool_path = os.path.join(self.workdir, "pool.db")
        db = sqlite3.connect(pool_path)
        db.execute("CREATE TABLE pinned (protocol TEXT, host TEXT,"
                   " port INTEGER, name TEXT, created INTEGER, by TEXT)")
        for k in pinned_keys:
            db.execute("INSERT INTO pinned VALUES (?,?,?,?,?,?)",
                       (k[0], k[1], k[2], k[3], 1, "test"))
        db.execute("CREATE TABLE winner_reports (ts INTEGER, name TEXT)")
        db.commit()
        db.close()
        return probe_path, pool_path

    def _fp_key(self, line):
        name, proto, host, port, params = parse_surge_line(line)
        return (proto, host, port, name), fingerprint_of(
            proto, host, port, params)

    def test_freeze_ranks_fresh_first_and_status_needs_retest(self):
        import tools.freeze_real as fr
        now = self.tested_at + 3600
        # A DIFFERENT source version than the fixture native record
        # (one line appended changes the SHA): the record's passes
        # are stale for this source, never fresh.
        alt_source = os.path.join(self.workdir, "source-alt.txt")
        _write_lines(alt_source, self.pool44 + [self.failed_lines[0]])
        self.assertNotEqual(_sha_file(alt_source), self.version_sha)
        # Probe: 2 clean14 lines verified fresh (<300ms, within TTL).
        probe_rows = []
        for line in self.clean14[:2]:
            (proto, host, port, name), fp = self._fp_key(line)
            probe_rows.append((fp, name, "verified", now - 3600, 200,
                               1, 3, 0, now - 3600))
        probe_path, pool_path = self._build_dbs(probe_rows=probe_rows)
        manifest, frozen = fr.freeze(
            alt_source, probe_path, pool_path,
            native_record_path=self.record_path, now=now)
        self.assertEqual(len(frozen), 14)
        cands = manifest["candidates"]["lines"]
        self.assertEqual(cands[0]["evidence"], "fresh")
        self.assertEqual(cands[1]["evidence"], "fresh")
        self.assertEqual(manifest["evidence_summary"]["fresh"], 2)
        self.assertEqual(manifest["status"], "needs_phone_retest")
        self.assertFalse(manifest["publishable"])
        self.assertIn("no_fresh_full_group_evidence_for_frozen_sha",
                      manifest["blockers"])
        # No pinned rows in this DB.
        self.assertEqual(manifest["pinned_check"]["pinned_table_rows"], 0)

    def test_freeze_evidence_fresh_on_full_group_run(self):
        import tools.freeze_real as fr
        now = self.tested_at + 3600
        source_sha = _sha_file(self.pool44_path)
        results = []
        for line in self.clean14:
            _key, fp = self._fp_key(line)
            _name, _p, _h, _po, _pa = parse_surge_line(line)
            results.append({"fingerprint": fp, "name": _name,
                            "success": True, "ms": 200})
        rec_path = os.path.join(self.workdir, "native.json")
        with open(rec_path, "w") as f:
            json.dump({"format": "native-results-v1",
                       "runs": [{"version_sha": source_sha,
                                 "tested_at": now - 100,
                                 "results": results}]}, f)
        probe_path, pool_path = self._build_dbs()
        manifest, frozen = fr.freeze(
            self.pool44_path, probe_path, pool_path,
            native_record_path=rec_path, now=now)
        self.assertEqual(manifest["status"], "evidence_fresh")
        self.assertTrue(manifest["publishable"])
        self.assertEqual(manifest["blockers"], [])

    def test_freeze_flags_pinned_candidates(self):
        import tools.freeze_real as fr
        now = self.tested_at + 3600
        pinned = []
        for line in self.clean14:
            (proto, host, port, name), _fp = self._fp_key(line)
            pinned.append((proto, host, port, name))
        probe_path, pool_path = self._build_dbs(pinned_keys=pinned)
        manifest, _frozen = fr.freeze(
            self.pool44_path, probe_path, pool_path,
            native_record_path=self.record_path, now=now)
        self.assertEqual(
            manifest["pinned_check"]["pinned_in_candidates"], 14)
        self.assertFalse(manifest["publishable"])
        self.assertIn("pinned_exemption_present_in_candidates",
                      manifest["blockers"])

    def test_freeze_manifest_contains_no_uris(self):
        import tools.freeze_real as fr
        now = self.tested_at + 3600
        probe_path, pool_path = self._build_dbs()
        manifest, _frozen = fr.freeze(
            self.pool44_path, probe_path, pool_path,
            native_record_path=self.record_path, now=now)
        text = json.dumps(manifest, ensure_ascii=False)
        self.assertNotIn("://", text)
        self.assertNotIn("TEST-ONLY-NOT-A-REAL-NODE", text)


if __name__ == "__main__":
    unittest.main()
