"""D5 tests for the GPT D3 review (Issue #73 comment 6886420557).

Three items, all in this file (unittest style, same harness as
tests/test_d3.py -- stubbed crawler/geo modules, synthetic fixtures
only, TEST-NET hosts, password TEST-ONLY-NOT-A-REAL-NODE):

  1. NON-ROOT UNREADABLE SCENARIOS (GPT item 1). test_d3.py's chmod-000
     test SKIPS under root (the kernel lets root read through chmod
     000). These tests do the same for the state file, the anchor
     file, the workdir, and the served dir -- plus direct EACCES /
     write-denied injections -- and they SKIP under root with an
     explicit reason. Run them as a non-root user via
     drills/run_nonroot_tests.sh; under root they report skipped,
     never silently green.
  2. EXPLICIT-INIT TRUST BOUNDARY (GPT item 2). Negative: a fresh
     init does NOT make publish pass without a fresh native gate
     (negative A); losing BOTH records on an existing installation
     does NOT auto-recover (negative B). Positive: a genuinely fresh
     workdir still inits, and the human-review path (allow flag +
     owner ack) inits with a records-loss-recovery audit event.
  3. ANCHOR WRITE ORDER / CRASH WINDOW (GPT item 3). Deterministic
     crashes via the test-only _TEST_CRASH_POINT hook in
     pool/recovery.py ("after-state" / "after-anchor"): a torn write
     must refuse (never rebuild ok), a completed anchor write must
     keep any recorded STOP. The random SIGKILL sweep lives in
     drills/crash_window_drill.py.

Run: python3 -m unittest tests.test_d5_d3 -v   (from the D5 root)
As non-root: drills/run_nonroot_tests.sh
"""

import errno
import hashlib
import json
import os
import stat
import sys
import tempfile
import time
import unittest

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

import pool.recovery as recovery_mod  # noqa: E402
from pool.native_gate import load_native_allowlist  # noqa: E402
from pool.phone_gate import fingerprint_of, parse_surge_line  # noqa: E402
from pool.publish import run_publish  # noqa: E402
from pool.publish_lock import PublishLock, file_manifest  # noqa: E402
from pool.recovery import (  # noqa: E402
    OWNER_ACK_CLEAR, OWNER_ACK_INIT, _SimulatedCrash, _write_state,
    clear_stop, enter_degraded, gate_check, init_recovery_state,
    read_state, read_state_strict, status)
from pool.sync import run_sync  # noqa: E402

FIX = os.path.join(D5_ROOT, "fixtures")


def _read_lines(path):
    with open(path, encoding="utf-8") as f:
        return [l.rstrip("\n") for l in f if l.strip()]


def _sha(path):
    if not os.path.exists(path):
        return None
    with open(path, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


def _fp_of(line):
    name, proto, host, port, params = parse_surge_line(line)
    return fingerprint_of(proto, host, port, params)


def _make_record(lines, pass_fps, version_sha, tested_at, fail_fps=(),
                 slow_fps_ms=None):
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


class D5TestBase(unittest.TestCase):
    """Same fixtures as test_d3.py; tests control init explicitly."""

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
        self.now_stale = self.tested_at + 25 * 3600
        self.admitted = {_fp_of(l) for l in self.clean14}
        self.assertEqual(len(self.admitted), 14)
        self.pool44_path = os.path.join(FIX, "pool_44_fixture.txt")
        self.state_path = os.path.join(self.workdir, "recovery-state.json")
        self.anchor_path = os.path.join(self.workdir, "recovery-anchor.json")
        self.served_file = os.path.join(self.workdir, "served",
                                        "pool-new.txt")
        self.publish_file = os.path.join(self.workdir, "publish",
                                         "pool-new.txt")

    def tearDown(self):
        # Restore permissions first: several tests chmod things 000
        # and rmtree would otherwise fail to clean up as non-root.
        for path, mode in ((self.state_path, 0o600),
                           (self.anchor_path, 0o600),
                           (self.workdir, 0o700)):
            try:
                os.chmod(path, mode)
            except OSError:
                pass
        served_dir = os.path.join(self.workdir, "served")
        try:
            os.chmod(served_dir, 0o755)
        except OSError:
            pass
        recovery_mod._TEST_CRASH_POINT = None
        import shutil
        shutil.rmtree(self.workdir, ignore_errors=True)

    def _require_nonroot(self):
        """Skip with an explicit reason under root: the kernel lets
        root read through chmod 000, so a chmod-000 test run as root
        proves nothing. Run drills/run_nonroot_tests.sh instead."""
        if os.geteuid() == 0:
            self.skipTest(
                "running as root: chmod 000 does not block reads; "
                "run drills/run_nonroot_tests.sh as the d5test user")

    def _init(self):
        rc, out = init_recovery_state(self.workdir, OWNER_ACK_INIT)
        self.assertEqual(rc, 0, out)
        return out

    def _seed_clean_synced(self):
        self._init()
        rc, res = run_publish(
            self.workdir, self.clean14, self.record_path, self.version_sha,
            probe_db=self.probe_db, now=self.now,
            source_file=self.pool44_path)
        self.assertEqual(rc, 0, res)
        rc, res = run_sync(self.workdir, self.record_path, self.version_sha,
                           probe_db=self.probe_db, now=self.now)
        self.assertEqual(rc, 0, res)
        return res

    def _write_record(self, record, name="record.json"):
        path = os.path.join(self.workdir, name)
        with open(path, "w", encoding="utf-8") as f:
            json.dump(record, f)
        return path

    def _remove_if_exists(self, path):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass


class TestNonRootUnreadable(D5TestBase):
    """GPT item 1: chmod-000 / EACCES / write-denied cases, run for
    real only as a non-root user. Every test asserts the precise
    refusal code, rc=1 where an rc exists, and that the target file's
    SHA256 is unchanged by the refused operation."""

    def test_state_file_chmod000_refuses(self):
        self._require_nonroot()
        self._seed_clean_synced()
        served_before = _sha(self.served_file)
        os.chmod(self.state_path, 0)
        try:
            allowed, err, _st = gate_check(self.workdir)
            self.assertFalse(allowed)
            self.assertEqual(err, "recovery_state_unreadable")
            rc, res = run_publish(
                self.workdir, self.clean14, self.record_path,
                self.version_sha, probe_db=self.probe_db, now=self.now,
                source_file=self.pool44_path)
            self.assertEqual(rc, 1)
            self.assertEqual(res.get("error"), "recovery_state_unreadable")
            self.assertEqual(_sha(self.served_file), served_before)
        finally:
            os.chmod(self.state_path, 0o600)

    def test_anchor_file_chmod000_refuses(self):
        self._require_nonroot()
        self._seed_clean_synced()
        served_before = _sha(self.served_file)
        os.chmod(self.anchor_path, 0)
        try:
            allowed, err, _st = gate_check(self.workdir)
            self.assertFalse(allowed)
            self.assertEqual(err, "recovery_anchor_unreadable")
            rc, res = run_sync(self.workdir, self.record_path,
                               self.version_sha, probe_db=self.probe_db,
                               now=self.now)
            self.assertEqual(rc, 1)
            self.assertEqual(res.get("error"), "recovery_anchor_unreadable")
            self.assertEqual(_sha(self.served_file), served_before)
        finally:
            os.chmod(self.anchor_path, 0o600)

    def test_workdir_chmod000_refuses(self):
        self._require_nonroot()
        self._seed_clean_synced()
        served_before = _sha(self.served_file)
        os.chmod(self.workdir, 0)
        try:
            # NOTE on the actual code: _read_state_file() probes with
            # os.path.exists(), which returns False (not an exception)
            # when the directory is unreadable, so both records read
            # as "missing" and the gate reports
            # recovery_state_uninitialized -- NOT
            # recovery_state_unreadable. The gate still refuses
            # fail-closed (rc-equivalent: allowed=False); only the
            # code names the reader's view (missing) rather than the
            # underlying EACCES. That distinction is honest and is
            # asserted here as-is.
            allowed, err, _st = gate_check(self.workdir)
            self.assertFalse(allowed)
            self.assertEqual(err, "recovery_state_uninitialized")
        finally:
            os.chmod(self.workdir, 0o700)
        # The refusal must not have touched the served file.
        self.assertEqual(_sha(self.served_file), served_before)
        # And the gate opens again once permissions are restored.
        allowed, err, _st = gate_check(self.workdir)
        self.assertTrue(allowed, err)

    def test_served_dir_chmod000_is_unknown_not_qualified(self):
        self._require_nonroot()
        self._seed_clean_synced()
        served_before = _sha(self.served_file)
        served_dir = os.path.join(self.workdir, "served")
        os.chmod(served_dir, 0)
        try:
            # The served file cannot be read at all: its binding is
            # empty and status() reports unknown-no-evidence -- it is
            # NEVER reported qualified. (The recovery gate itself
            # does not consult served/, so it stays open; the
            # served verdict is what turns unknown.)
            from pool.recovery import _served_binding
            self.assertEqual(_served_binding(self.workdir), ("", 0, ""))
            st = status(self.workdir, self.record_path,
                        probe_db=self.probe_db, now=self.now)
            self.assertEqual(st.get("served_status_live"),
                             "unknown-no-evidence")
            # Sync cannot copy into the unreadable dir: it raises
            # PermissionError rather than returning rc=1 (no
            # PermissionError -> rc mapping exists in run_sync; the
            # served bytes are untouched either way).
            with self.assertRaises(PermissionError):
                run_sync(self.workdir, self.record_path, self.version_sha,
                         probe_db=self.probe_db, now=self.now)
        finally:
            os.chmod(served_dir, 0o755)
        self.assertEqual(_sha(self.served_file), served_before)

    def test_eacces_injection_open_unreadable_state(self):
        """Direct EACCES injection: as non-root, open() of a chmod-000
        state file raises PermissionError (errno EACCES); the gate
        refuses with the precise code and the served SHA is unchanged."""
        self._require_nonroot()
        self._seed_clean_synced()
        served_before = _sha(self.served_file)
        os.chmod(self.state_path, 0)
        try:
            with self.assertRaises(PermissionError) as ctx:
                open(self.state_path, encoding="utf-8")
            self.assertEqual(ctx.exception.errno, errno.EACCES)
            state, err = read_state_strict(self.workdir)
            self.assertIsNone(state)
            self.assertEqual(err, "recovery_state_unreadable")
            self.assertEqual(_sha(self.served_file), served_before)
        finally:
            os.chmod(self.state_path, 0o600)

    def test_write_denied_in_readonly_workdir(self):
        """Write-denied injection: the workdir is read-only, so a
        state write must fail and the old state file's SHA must not
        change. NOTE on errno: on Linux, creating a file in a
        directory without write permission raises EACCES, not EPERM;
        the test asserts PermissionError and records the actual
        errno (EACCES) rather than pretending EPERM was observed."""
        self._require_nonroot()
        self._seed_clean_synced()
        state_before = _sha(self.state_path)
        served_before = _sha(self.served_file)
        state = read_state(self.workdir)
        os.chmod(self.workdir, 0o555)
        try:
            with self.assertRaises(PermissionError) as ctx:
                _write_state(self.workdir, dict(state),
                             reason="write-denied drill")
            self.assertEqual(ctx.exception.errno, errno.EACCES)
        finally:
            os.chmod(self.workdir, 0o700)
        self.assertEqual(_sha(self.state_path), state_before)
        self.assertEqual(_sha(self.served_file), served_before)
        # The old state is intact and the gate still works on it.
        allowed, err, _st = gate_check(self.workdir)
        self.assertTrue(allowed, err)


class TestInitTrustBoundary(D5TestBase):
    """GPT item 2: explicit-init trust boundary.

    fresh init is a controlled HUMAN trust establishment ("this
    workdir may serve from now on"), never an automatic recovery.
    _served_binding() only takes the current served file's
    manifest/sidecar identity (SHA prefix + chain_id); it does NOT
    verify that native evidence is fresh -- so init must never be
    read as "the served version is qualified"."""

    def test_negative_a_fresh_init_still_needs_fresh_native_gate(self):
        """Fresh workdir -> init fresh rc=0 -> publish with STALE
        native evidence (25 h old) refuses with a GATE-class code
        (phone_gate_zero_qualified), never a recovery code, and no
        served file appears. The gate was open (init succeeded); the
        refusal comes from the native gate, not the recovery gate."""
        rc, out = init_recovery_state(self.workdir, OWNER_ACK_INIT)
        self.assertEqual(rc, 0, out)
        self.assertEqual(out.get("mode"), "fresh")
        allowed, err, _st = gate_check(self.workdir)
        self.assertTrue(allowed, err)
        self.assertFalse(os.path.exists(self.served_file))
        rc, res = run_publish(
            self.workdir, self.clean14, self.record_path, self.version_sha,
            probe_db=self.probe_db, now=self.now_stale,
            source_file=self.pool44_path)
        self.assertEqual(rc, 1, res)
        self.assertEqual(res.get("error"), "phone_gate_zero_qualified")
        self.assertFalse(res.get("error", "").startswith("recovery_"))
        self.assertFalse(os.path.exists(self.served_file))
        self.assertFalse(os.path.exists(self.publish_file))

    def test_negative_b_double_records_loss_no_auto_recovery(self):
        """Existing installation (served + publish + history) with a
        STOP recorded: delete BOTH records -> gate refuses
        recovery_state_uninitialized; plain init (no allow flag)
        refuses init_refused_existing_install_records_lost; the gate
        NEVER silently returns to ok."""
        self._seed_clean_synced()
        rc, _out = enter_degraded(self.workdir, "d5 negative B",
                                  now=self.now)
        self.assertEqual(rc, 0)
        self._remove_if_exists(self.state_path)
        self._remove_if_exists(self.anchor_path)
        allowed, err, _st = gate_check(self.workdir)
        self.assertFalse(allowed)
        self.assertEqual(err, "recovery_state_uninitialized")
        rc, out = init_recovery_state(self.workdir, OWNER_ACK_INIT)
        self.assertEqual(rc, 1, out)
        self.assertEqual(out.get("error"),
                         "init_refused_existing_install_records_lost")
        allowed, err, _st = gate_check(self.workdir)
        self.assertFalse(allowed)
        self.assertEqual(err, "recovery_state_uninitialized")
        state, err2 = read_state_strict(self.workdir)
        self.assertIsNone(state)
        self.assertEqual(err2, "recovery_state_uninitialized")

    def test_positive_fresh_init_on_truly_fresh_workdir(self):
        """A genuinely fresh workdir (no served, no publish, no
        history) still inits with the owner ack alone, and does NOT
        carry a records-loss-recovery event."""
        rc, out = init_recovery_state(self.workdir, OWNER_ACK_INIT)
        self.assertEqual(rc, 0, out)
        self.assertEqual(out.get("mode"), "fresh")
        self.assertFalse(out.get("records_loss_recovery"))
        state = read_state(self.workdir)
        self.assertEqual(state["state"], "ok")
        self.assertFalse(state["stopped"])
        self.assertFalse(state["requires_fresh_native_retest"])
        events = [e.get("event") for e in state.get("history", [])]
        self.assertNotIn("records-loss-recovery", events)

    def test_positive_records_loss_recovery_with_allow(self):
        """Existing installation, both records lost, allow flag +
        owner ack -> init succeeds (mode fresh) AND the history
        carries a records-loss-recovery audit event naming the served
        SHA prefix; served_status stays unknown-no-evidence and a
        fresh native re-test is required."""
        self._seed_clean_synced()
        served_sha = _sha(self.served_file)
        self.assertIsNotNone(served_sha)
        self._remove_if_exists(self.state_path)
        self._remove_if_exists(self.anchor_path)
        rc, out = init_recovery_state(
            self.workdir, OWNER_ACK_INIT,
            allow_fresh_after_records_loss=True)
        self.assertEqual(rc, 0, out)
        self.assertEqual(out.get("mode"), "fresh")
        self.assertTrue(out.get("records_loss_recovery"))
        state = read_state(self.workdir)
        self.assertEqual(state["state"], "ok")
        self.assertEqual(state["served_status"], "unknown-no-evidence")
        self.assertTrue(state["requires_fresh_native_retest"])
        events = [e for e in state.get("history", [])
                  if e.get("event") == "records-loss-recovery"]
        self.assertEqual(len(events), 1)
        self.assertIn(served_sha[:12], events[0].get("detail", ""))


class TestCrashPoint(D5TestBase):
    """GPT item 3: deterministic crash points in _write_state() via
    the test-only _TEST_CRASH_POINT hook (default None, production
    path never sets it)."""

    def test_crash_hook_defaults_off(self):
        self.assertIsNone(recovery_mod._TEST_CRASH_POINT)

    def _write_with_crash(self, state, point):
        """Write `state` under the shared lock with the crash hook
        set; expect _SimulatedCrash and reset the hook afterwards."""
        lock = PublishLock(os.path.join(self.workdir, "lock",
                                        "publish.lock"),
                           owner="d5-crash-test", timeout=30)
        lock.acquire()
        try:
            recovery_mod._TEST_CRASH_POINT = point
            with self.assertRaises(_SimulatedCrash):
                _write_state(self.workdir, dict(state),
                             reason="d5 crash point %s" % point)
        finally:
            recovery_mod._TEST_CRASH_POINT = None
            lock.release()

    def test_crash_after_state_with_stop_refuses_and_keeps_stop(self):
        """(a) STOP recorded, crash after the state rename (state new,
        anchor old): the strict read must refuse with a code carrying
        the _stop_recorded suffix, and init must refuse
        init_refused_stop_recorded -- the historical STOP is NOT
        cleared by the torn write."""
        self._seed_clean_synced()
        rc, _out = enter_degraded(self.workdir, "d5 crash A",
                                  now=self.now)
        self.assertEqual(rc, 0)
        state = read_state(self.workdir)
        self.assertTrue(state["stopped"])
        self._write_with_crash(state, "after-state")
        state2, err = read_state_strict(self.workdir)
        self.assertIsNone(state2)
        self.assertTrue(err.endswith("_stop_recorded"), err)
        allowed, gerr, _st = gate_check(self.workdir)
        self.assertFalse(allowed)
        self.assertEqual(gerr, err)
        rc, out = init_recovery_state(self.workdir, OWNER_ACK_INIT)
        self.assertEqual(rc, 1, out)
        self.assertEqual(out.get("error"), "init_refused_stop_recorded")
        # The STOP is still on record afterwards: the read still
        # refuses with the _stop_recorded suffix.
        _state3, err3 = read_state_strict(self.workdir)
        self.assertTrue(err3.endswith("_stop_recorded"), err3)

    def test_crash_after_anchor_with_stop_keeps_stop(self):
        """(b) Crash after the anchor write (both records new and
        consistent): the strict read recovers the consistent state
        and the STOP is still present in it; the gate refuses
        pool_stopped."""
        self._seed_clean_synced()
        rc, _out = enter_degraded(self.workdir, "d5 crash B",
                                  now=self.now)
        self.assertEqual(rc, 0)
        state = read_state(self.workdir)
        self._write_with_crash(state, "after-anchor")
        state2, err = read_state_strict(self.workdir)
        self.assertIsNone(err, err)
        self.assertEqual(state2["state"], "degraded")
        self.assertTrue(state2["stopped"])
        allowed, gerr, _st = gate_check(self.workdir)
        self.assertFalse(allowed)
        self.assertEqual(gerr, "pool_stopped")

    def test_crash_after_state_on_ok_no_silent_rebuild(self):
        """(c) ok state, crash after the state rename: the read and
        the gate refuse (state/anchor mismatch, no STOP suffix --
        no STOP was recorded). Init must NOT silently rebuild ok:
        with the served file changed it refuses
        init_anchor_served_mismatch; only with the served binding
        intact does it rebuild, and then explicitly via
        rebuild-from-anchor -- never via a fresh init."""
        self._seed_clean_synced()
        # Record the served binding in the anchor first: publish/sync
        # do not rewrite the recovery state, so the anchor only
        # carries a served binding after a transition (enter-degraded
        # + clear-stop with fresh evidence). Without this step the
        # anchor's served_sha_prefix is empty and the tripwire below
        # cannot fire -- that is the D3 design, not a test shortcut
        # (see test_d3.test_init_refuses_when_served_changed).
        rc, _out = enter_degraded(self.workdir, "d5 crash C bind",
                                  now=self.now)
        self.assertEqual(rc, 0)
        fresh = _make_record(self.clean14, self.admitted,
                             self.version_sha, self.now)
        fresh_path = self._write_record(fresh, "fresh.json")
        rc, out = clear_stop(self.workdir, OWNER_ACK_CLEAR, fresh_path,
                             probe_db=self.probe_db, now=self.now + 60)
        self.assertEqual(rc, 0, out)
        state = read_state(self.workdir)
        self.assertEqual(state["state"], "ok")
        self._write_with_crash(state, "after-state")
        state2, err = read_state_strict(self.workdir)
        self.assertIsNone(state2)
        self.assertEqual(err, "recovery_state_anchor_mismatch")
        self.assertFalse(err.endswith("_stop_recorded"))
        allowed, gerr, _st = gate_check(self.workdir)
        self.assertFalse(allowed)
        self.assertEqual(gerr, "recovery_state_anchor_mismatch")
        # Served file changed outside the state machine: init must
        # refuse on the anchor binding tripwire.
        with open(self.served_file, "w", encoding="utf-8") as f:
            f.write("\n".join(self.pool44) + "\n")
        rc, out = init_recovery_state(self.workdir, OWNER_ACK_INIT)
        self.assertEqual(rc, 1, out)
        self.assertEqual(out.get("error"), "init_anchor_served_mismatch")
        # Served bytes restored: init rebuilds from the anchor, with
        # the binding checked -- mode is rebuild-from-anchor, NOT
        # fresh (a fresh init here would have washed the history).
        with open(self.served_file, "w", encoding="utf-8") as f:
            f.write("\n".join(self.clean14) + "\n")
        rc, out = init_recovery_state(self.workdir, OWNER_ACK_INIT)
        self.assertEqual(rc, 0, out)
        self.assertEqual(out.get("mode"), "rebuild-from-anchor")
        allowed, gerr, _st = gate_check(self.workdir)
        self.assertTrue(allowed, gerr)


if __name__ == "__main__":
    unittest.main(verbosity=2)
