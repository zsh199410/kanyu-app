"""D3 test suite (GPT D2 review 6884522235, P0 -- recovery-state
fail-open).

D2's read_state() returned a DEFAULT OK state when
recovery-state.json was missing, corrupt, unreadable, or held an
illegal value, so deleting the state file silently reset a recorded
STOP. D3 closes it: strict reads, a persistent anchor, explicit init
only, and a gate that publish/sync/rollback all consult.

RED-ON-D2 DESIGN. Every test in this file is written to FAIL on the
D2 tree and PASS on the D3 tree, so the red->green evidence is real
and re-runnable:
  * The behavioural tests (missing/corrupt/unreadable/illegal/torn/
    checksum/anchor-missing/stop-survives/rollback-gate/uninitialized)
    use only the D2 API (run_publish/run_sync/run_rollback/read_state/
    is_stopped/status). On D2 they fail because publish/sync/rollback
    SUCCEED where D3 refuses; on D3 they pass.
  * The tests that need D3-only API (init, gate_check,
    RecoveryStateError) import it optionally and assert HAS_D3 first:
    on D2 the import fails and the test fails (the capability is
    absent); on D3 it proceeds.
Run the red check with this file copied into the D2 tree's tests/
directory: python3 -m unittest tests.test_d3 -v (expect failures),
then in the D3 tree: python3 -m unittest tests.test_d3 -v (expect
all green). The red log is kept in docs/redgreen-d3-log.txt.

HONEST BOUNDARY -- fixtures are SYNTHETIC (fixtures/build_fixtures.py):
TEST-NET hosts, password TEST-ONLY-NOT-A-REAL-NODE, and the native
record's tested_at is generated at fixture-build time (now). A fixture
run passing the gate proves the CODE paths, never that a real phone
measured anything: synthetic tested_at=now is NOT real phone evidence.
No test here claims otherwise; the D3 report states it explicitly.

Run: python3 -m unittest tests.test_d3 -v   (from the D3 root)
"""

import hashlib
import json
import os
import stat
import sys
import tempfile
import time
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
D3_ROOT = os.path.dirname(HERE)
sys.path.insert(0, D3_ROOT)

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
    evidence_admitted_fps, load_native_allowlist)
from pool.phone_gate import fingerprint_of, parse_surge_line  # noqa: E402
from pool.publish import run_publish  # noqa: E402
from pool.publish_lock import file_manifest  # noqa: E402
from pool.recovery import (  # noqa: E402
    OWNER_ACK_CLEAR, OWNER_ACK_RESTORE, assess_anchors, clear_stop,
    enter_degraded, is_stopped, manual_restore, read_state, status)
from pool.rollback import run_rollback  # noqa: E402
from pool.sync import run_sync  # noqa: E402

# D3-only API: optional so this file can be RUN against the D2 tree
# for the red check (where the import fails and HAS_D3 is False).
try:
    from pool.recovery import (  # noqa: E402
        OWNER_ACK_INIT, RecoveryStateError, gate_check,
        init_recovery_state, read_state_strict)
    HAS_D3 = True
except ImportError:
    HAS_D3 = False
    OWNER_ACK_INIT = "OWNER-ACK-INIT-RECOVERY-STATE"

    class RecoveryStateError(Exception):
        pass

    gate_check = None
    init_recovery_state = None
    read_state_strict = None

FIX = os.path.join(D3_ROOT, "fixtures")


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


class D3TestBase(unittest.TestCase):
    """Same fixtures as D2TestBase, but NO auto-init: D3 tests control
    initialization explicitly (many of them test the uninitialized
    state itself). Tests that need a working gate call _maybe_init()
    first -- a no-op on the D2 tree (where no init exists), an init
    on the D3 tree."""

    def setUp(self):
        self.workdir = tempfile.mkdtemp(prefix="d3-test-")
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
        self.clean_sha = hashlib.sha256(
            ("\n".join(self.clean14) + "\n").encode("utf-8")).hexdigest()
        self.admitted = set()
        for line in self.clean14:
            self.admitted.add(_fp_of(line))
        self.assertEqual(len(self.admitted), 14)
        self.pool44_path = os.path.join(FIX, "pool_44_fixture.txt")
        self.clean14_path = os.path.join(FIX, "clean_14_fixture.txt")
        self.state_path = os.path.join(self.workdir, "recovery-state.json")
        self.anchor_path = os.path.join(self.workdir, "recovery-anchor.json")

    def tearDown(self):
        import shutil
        shutil.rmtree(self.workdir, ignore_errors=True)

    def _maybe_init(self):
        """Init when the D3 API exists; no-op on the D2 tree."""
        if HAS_D3:
            rc, out = init_recovery_state(self.workdir, OWNER_ACK_INIT)
            self.assertEqual(rc, 0, out)
            return out
        return None

    def _write_record(self, record, name="record.json"):
        path = os.path.join(self.workdir, name)
        with open(path, "w", encoding="utf-8") as f:
            json.dump(record, f)
        return path

    def _write_lines(self, lines, name="source.txt"):
        path = os.path.join(self.workdir, name)
        with open(path, "w", encoding="utf-8") as f:
            f.write("\n".join(lines) + "\n")
        return path

    def _seed_clean(self):
        rc, res = run_publish(
            self.workdir, self.clean14, self.record_path, self.version_sha,
            probe_db=self.probe_db, now=self.now,
            source_file=self.pool44_path)
        self.assertEqual(rc, 0, res)
        return res

    def _seed_clean_synced(self):
        self._seed_clean()
        rc, res = run_sync(self.workdir, self.record_path, self.version_sha,
                           probe_db=self.probe_db, now=self.now)
        self.assertEqual(rc, 0, res)
        return res

    def _publish_subset(self, subset, record, sha, name="subset.txt"):
        subset_path = self._write_lines(subset, name)
        rc, res = run_publish(
            self.workdir, subset, record, sha, probe_db=self.probe_db,
            now=self.now, source_file=subset_path)
        return rc, res, subset_path

    def _seed_v1_v2(self):
        """v1 clean (publish+sync), then v2 13-line subset publish."""
        self._seed_clean_synced()
        subset = self.clean14[:13]
        subset_sha = hashlib.sha256(
            ("\n".join(subset) + "\n").encode("utf-8")).hexdigest()
        record2 = _make_record(subset, {_fp_of(l) for l in subset},
                               subset_sha, self.tested_at)
        path2 = self._write_record(record2, "record2.json")
        rc, res, subset_path = self._publish_subset(
            subset, path2, subset_sha)
        self.assertEqual(rc, 0, res)
        return subset, subset_sha, path2, subset_path

    def _history_snapshot(self):
        hist = os.path.join(self.workdir, "publish", "history")
        snaps = sorted(f for f in os.listdir(hist) if f.endswith(".txt"))
        self.assertTrue(snaps, "no history snapshot")
        return os.path.join(hist, snaps[-1])

    def _remove_if_exists(self, path):
        """Unlink when present. Needed for the red-on-D2 run: on the
        D2 tree several tests never create a state file (no init),
        so a bare os.unlink would ERROR instead of failing cleanly."""
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass

    def _ensure_state_file(self):
        """Write a minimal valid state file when none exists. On the
        D3 tree this is a no-op (init already created the real state
        + anchor); on the D2 tree it gives the tests below a file to
        break, so their red is a clean assertion failure."""
        if not os.path.exists(self.state_path):
            with open(self.state_path, "w", encoding="utf-8") as f:
                json.dump({"state": "ok", "stopped": False, "seq": 1,
                           "reason": "", "served_status": "unknown",
                           "served_sha_prefix": "", "served_lines": 0,
                           "deadline_iso": "",
                           "requires_fresh_native_retest": False,
                           "history": []}, f)

    def _publish_sync_rollback_all_refuse(self, error):
        """publish, sync and rollback must ALL refuse with `error`
        (and leave publish/served files untouched)."""
        publish_file = os.path.join(self.workdir, "publish", "pool-new.txt")
        served_file = os.path.join(self.workdir, "served", "pool-new.txt")
        before_pub = file_manifest(publish_file)
        before_srv = file_manifest(served_file)
        before_pub_sha = before_pub["sha256"] if before_pub else None
        before_srv_sha = before_srv["sha256"] if before_srv else None
        rc, res = run_publish(
            self.workdir, self.clean14, self.record_path, self.version_sha,
            probe_db=self.probe_db, now=self.now,
            source_file=self.pool44_path)
        self.assertEqual(rc, 1, res)
        self.assertEqual(res.get("error"), error)
        rc, res = run_sync(self.workdir, self.record_path, self.version_sha,
                           probe_db=self.probe_db, now=self.now)
        self.assertEqual(rc, 1, res)
        self.assertEqual(res.get("error"), error)
        rc, res = run_rollback(self.workdir, "latest-history",
                               self.record_path, probe_db=self.probe_db,
                               now=self.now)
        self.assertEqual(rc, 1, res)
        self.assertEqual(res.get("error"), error)
        after_pub = file_manifest(publish_file)
        after_srv = file_manifest(served_file)
        self.assertEqual(after_pub["sha256"] if after_pub else None,
                         before_pub_sha)
        self.assertEqual(after_srv["sha256"] if after_srv else None,
                         before_srv_sha)


class TestFailClosedModes(D3TestBase):
    """One test per failure mode in the D3 spec (1): every mode must
    refuse publish, sync AND rollback, and leave the files untouched.
    All of these FAIL on D2 (publish succeeds, or the error is wrong)
    and PASS on D3."""

    def test_missing_state_file_refuses_all_three(self):
        self._maybe_init()
        self._seed_clean_synced()
        self._remove_if_exists(self.state_path)
        self._publish_sync_rollback_all_refuse("recovery_state_missing")

    def test_corrupt_state_file_refuses_all_three(self):
        self._maybe_init()
        self._seed_clean_synced()
        with open(self.state_path, "w", encoding="utf-8") as f:
            f.write("{not json, torn")
        self._publish_sync_rollback_all_refuse("recovery_state_corrupt")

    def test_unreadable_state_file_refuses_all_three(self):
        """The state file replaced by a directory: open() raises
        IsADirectoryError (an OSError) for every uid, unlike chmod
        000 which root can still read through (see the chmod test)."""
        self._maybe_init()
        self._seed_clean_synced()
        self._remove_if_exists(self.state_path)
        os.mkdir(self.state_path)
        self._publish_sync_rollback_all_refuse("recovery_state_unreadable")

    def test_unreadable_state_file_chmod000_refuses(self):
        """chmod 000 must refuse -- except when the test runs as root,
        where the kernel lets root read through it. That case is
        skipped (the directory-replacement test above is the
        deterministic proof for every uid)."""
        if os.geteuid() == 0:
            self.skipTest("running as root: chmod 000 does not block reads")
        self._maybe_init()
        self._seed_clean_synced()
        self._ensure_state_file()
        os.chmod(self.state_path, 0)
        try:
            self._publish_sync_rollback_all_refuse(
                "recovery_state_unreadable")
        finally:
            os.chmod(self.state_path, 0o600)

    def test_illegal_state_value_refuses_all_three(self):
        self._maybe_init()
        self._seed_clean_synced()
        with open(self.state_path, "w", encoding="utf-8") as f:
            json.dump({"state": "explode", "stopped": False, "seq": 99,
                       "reason": "tampered"}, f)
        self._publish_sync_rollback_all_refuse("recovery_state_illegal")

    def test_torn_write_refuses_all_three(self):
        """Interrupted atomic write: the state file is gone but a
        .tmp with partial content is left behind (the rename never
        happened)."""
        self._maybe_init()
        self._seed_clean_synced()
        self._remove_if_exists(self.state_path)
        with open(self.state_path + ".tmp", "w", encoding="utf-8") as f:
            f.write('{"state": "ok", "stopped": fa')
        self._publish_sync_rollback_all_refuse(
            "recovery_state_write_interrupted")

    def test_checksum_mismatch_refuses_all_three(self):
        """Tamper the state file (valid JSON, valid shape, different
        content): the anchor's sha256 no longer matches."""
        self._maybe_init()
        self._seed_clean_synced()
        self._ensure_state_file()
        with open(self.state_path, encoding="utf-8") as f:
            state = json.load(f)
        state["reason"] = "tampered by hand"
        with open(self.state_path, "w", encoding="utf-8") as f:
            json.dump(state, f)
        self._publish_sync_rollback_all_refuse(
            "recovery_state_checksum_mismatch")

    def test_anchor_missing_refuses_all_three(self):
        """The state file is intact but its anchor is gone: the state
        cannot be proven to be the one the anchor vouched for."""
        self._maybe_init()
        self._seed_clean_synced()
        self._remove_if_exists(self.anchor_path)
        self._publish_sync_rollback_all_refuse("recovery_anchor_missing")

    def test_stale_state_file_replaced_by_older_copy_refuses(self):
        """A state file replaced by an OLDER copy (rollback of the
        state file itself): the anchor's seq is newer, so the
        cross-check refuses."""
        self._maybe_init()
        self._seed_clean_synced()
        rc, _out = enter_degraded(self.workdir, "test", now=self.now)
        self.assertEqual(rc, 0)
        with open(self.state_path, "rb") as f:
            old_state_bytes = f.read()
        fresh = _make_record(self.clean14, self.admitted,
                             self.version_sha, self.now)
        fresh_path = self._write_record(fresh, "fresh.json")
        rc, out = clear_stop(self.workdir, OWNER_ACK_CLEAR, fresh_path,
                             probe_db=self.probe_db, now=self.now + 60)
        self.assertEqual(rc, 0, out)
        with open(self.state_path, "wb") as f:
            f.write(old_state_bytes)
        # The restored file is the old DEGRADED copy, so it records a
        # STOP: the mismatch code carries the _stop_recorded suffix
        # (the operator must not just re-init; a STOP is on record).
        self._publish_sync_rollback_all_refuse(
            "recovery_state_anchor_mismatch_stop_recorded")

    def test_stop_survives_state_file_deletion(self):
        """The P0 itself: STOP recorded, state file deleted, the gate
        must still refuse -- and say a STOP was recorded, not just
        that a file is missing. status() must report unknown-unsafe."""
        self._maybe_init()
        self._seed_clean_synced()
        rc, _out = enter_degraded(self.workdir, "test stop",
                                  now=self.now)
        self.assertEqual(rc, 0)
        os.unlink(self.state_path)
        self._publish_sync_rollback_all_refuse(
            "recovery_state_missing_stop_recorded")
        st = status(self.workdir, self.record_path,
                    probe_db=self.probe_db, now=self.now)
        self.assertEqual(st["state"], "unknown-unsafe")
        self.assertTrue(st["stopped"])
        self.assertEqual(st["state_error"],
                         "recovery_state_missing_stop_recorded")

    def test_rollback_consults_gate(self):
        """D2 rollback never consulted the recovery state at all: with
        fresh evidence it would restore an anchor even while stopped
        or while the state is unreadable. D3 refuses first."""
        self._maybe_init()
        self._seed_v1_v2()
        # State file deleted: rollback refuses on the gate, not on
        # the anchor.
        self._remove_if_exists(self.state_path)
        rc, res = run_rollback(self.workdir, "latest-history",
                               self.record_path, probe_db=self.probe_db,
                               now=self.now)
        self.assertEqual(rc, 1)
        self.assertEqual(res.get("error"), "recovery_state_missing")
        # STOP recorded: rollback refuses with pool_stopped.
        self._maybe_init()
        rc, _out = enter_degraded(self.workdir, "test stop",
                                  now=self.now)
        self.assertEqual(rc, 0)
        rc, res = run_rollback(self.workdir, "latest-history",
                               self.record_path, probe_db=self.probe_db,
                               now=self.now)
        self.assertEqual(rc, 1)
        self.assertEqual(res.get("error"), "pool_stopped")

    def test_is_stopped_is_fail_closed(self):
        """Unknown counts as stopped: a fresh workdir (no state, no
        anchor) reports stopped, an initialized one does not, a
        degraded one does."""
        self.assertTrue(is_stopped(self.workdir))
        self._maybe_init()
        self.assertFalse(is_stopped(self.workdir))
        rc, _out = enter_degraded(self.workdir, "test", now=self.now)
        self.assertEqual(rc, 0)
        self.assertTrue(is_stopped(self.workdir))

    def test_read_state_raises_on_missing(self):
        """read_state() must RAISE on an unestablishable state, never
        return a default ok dict (that was the D2 hole)."""
        with self.assertRaises(RecoveryStateError) as ctx:
            read_state(self.workdir)
        self.assertEqual(ctx.exception.error,
                         "recovery_state_uninitialized")
        self._maybe_init()
        state = read_state(self.workdir)
        self.assertEqual(state["state"], "ok")


class TestExplicitInit(D3TestBase):
    """Explicit initialization only (spec 2 + 3). These tests need the
    D3 API and assert HAS_D3 first: on the D2 tree they fail there
    (the capability is absent) -- red. On D3 they exercise init."""

    def test_uninitialized_fresh_deployment_refuses(self):
        """A fresh workdir (no state, no anchor) refuses everything
        until init runs. On D2 this fails at the first publish
        assertion (publish succeeds with no state at all)."""
        self._publish_sync_rollback_all_refuse(
            "recovery_state_uninitialized")
        st = status(self.workdir, self.record_path,
                    probe_db=self.probe_db, now=self.now)
        self.assertEqual(st["state"], "unknown-unsafe")
        self.assertTrue(st["stopped"])
        self.assertEqual(st["state_error"],
                         "recovery_state_uninitialized")

    def test_init_requires_owner_ack(self):
        self.assertTrue(HAS_D3, "D3 API missing")
        rc, out = init_recovery_state(self.workdir, "WRONG-ACK")
        self.assertEqual(rc, 1)
        self.assertEqual(out.get("error"), "owner_ack_required")
        allowed, err, _st = gate_check(self.workdir)
        self.assertFalse(allowed)
        self.assertEqual(err, "recovery_state_uninitialized")
        rc, out = init_recovery_state(self.workdir, OWNER_ACK_INIT)
        self.assertEqual(rc, 0, out)
        self.assertEqual(out.get("mode"), "fresh")
        state = read_state(self.workdir)
        self.assertEqual(state["state"], "ok")
        self.assertFalse(state["stopped"])
        self.assertTrue(any(e.get("event") == "init"
                            for e in state.get("history", [])))
        allowed, err, _st = gate_check(self.workdir)
        self.assertTrue(allowed)
        self.assertIsNone(err)
        self._seed_clean_synced()

    def test_init_audit_entry(self):
        """Init writes an audit entry naming the mode and the served
        binding, and the anchor agrees with the state (seq +
        state_sha256)."""
        self.assertTrue(HAS_D3, "D3 API missing")
        rc, out = init_recovery_state(self.workdir, OWNER_ACK_INIT)
        self.assertEqual(rc, 0, out)
        state = read_state(self.workdir)
        anchor, aerr = None, None
        from pool.recovery import _read_anchor
        anchor, aerr = _read_anchor(self.workdir)
        self.assertIsNone(aerr)
        self.assertEqual(anchor["state"], state["state"])
        self.assertEqual(anchor["stopped"], state["stopped"])
        self.assertEqual(anchor["seq"], state["seq"])
        from pool.recovery import _canonical_json, _sha256_text
        self.assertEqual(anchor["state_sha256"],
                         _sha256_text(_canonical_json(state)))
        init_events = [e for e in state.get("history", [])
                       if e.get("event") == "init"]
        self.assertEqual(len(init_events), 1)
        self.assertIn("fresh", init_events[0].get("detail", ""))

    def test_init_cannot_launder_stop(self):
        """STOP recorded, state file deleted, init with the correct
        ack must STILL refuse: the anchor survives and says stopped.
        The gate keeps refusing afterwards."""
        self.assertTrue(HAS_D3, "D3 API missing")
        self._maybe_init()
        self._seed_clean_synced()
        rc, _out = enter_degraded(self.workdir, "test stop",
                                  now=self.now)
        self.assertEqual(rc, 0)
        self._remove_if_exists(self.state_path)
        rc, out = init_recovery_state(self.workdir, OWNER_ACK_INIT)
        self.assertEqual(rc, 1)
        self.assertEqual(out.get("error"), "init_refused_stop_recorded")
        allowed, err, _st = gate_check(self.workdir)
        self.assertFalse(allowed)
        self.assertEqual(err, "recovery_state_missing_stop_recorded")

    def test_init_rebuild_from_anchor(self):
        """State file lost, anchor intact, served file unchanged
        since init (anchor records no served version): re-init
        rebuilds the state file from the anchor and the gate opens."""
        self.assertTrue(HAS_D3, "D3 API missing")
        self._maybe_init()
        self._seed_clean_synced()
        self._remove_if_exists(self.state_path)
        rc, out = init_recovery_state(self.workdir, OWNER_ACK_INIT)
        self.assertEqual(rc, 0, out)
        self.assertEqual(out.get("mode"), "rebuild-from-anchor")
        allowed, err, _st = gate_check(self.workdir)
        self.assertTrue(allowed)
        self.assertIsNone(err)
        self._seed_clean_synced()

    def test_init_refuses_when_served_changed(self):
        """The anchor's served binding is a tripwire: when the served
        file changed since the anchor was written, re-init refuses
        and the operator must use the fresh-evidence + clear-stop
        path instead. Restoring the served bytes lets re-init pass."""
        self.assertTrue(HAS_D3, "D3 API missing")
        self._maybe_init()
        self._seed_clean_synced()
        # Record a served version in the anchor via a transition.
        rc, _out = enter_degraded(self.workdir, "test", now=self.now)
        self.assertEqual(rc, 0)
        fresh = _make_record(self.clean14, self.admitted,
                             self.version_sha, self.now)
        fresh_path = self._write_record(fresh, "fresh.json")
        rc, out = clear_stop(self.workdir, OWNER_ACK_CLEAR, fresh_path,
                             probe_db=self.probe_db, now=self.now + 60)
        self.assertEqual(rc, 0, out)
        # Break the served file outside the state machine.
        served_file = os.path.join(self.workdir, "served", "pool-new.txt")
        with open(served_file, "w", encoding="utf-8") as f:
            f.write("\n".join(self.pool44) + "\n")
        self._remove_if_exists(self.state_path)
        rc, out = init_recovery_state(self.workdir, OWNER_ACK_INIT)
        self.assertEqual(rc, 1)
        self.assertEqual(out.get("error"), "init_anchor_served_mismatch")
        # Restoring the served bytes lets re-init pass.
        with open(served_file, "w", encoding="utf-8") as f:
            f.write("\n".join(self.clean14) + "\n")
        rc, out = init_recovery_state(self.workdir, OWNER_ACK_INIT)
        self.assertEqual(rc, 0, out)
        self.assertEqual(out.get("mode"), "rebuild-from-anchor")

    def test_init_rebuild_anchor_when_anchor_lost(self):
        """Anchor lost, state file intact and not stopped: init
        rebuilds the anchor from the state and the gate opens."""
        self.assertTrue(HAS_D3, "D3 API missing")
        self._maybe_init()
        self._seed_clean_synced()
        self._remove_if_exists(self.anchor_path)
        allowed, err, _st = gate_check(self.workdir)
        self.assertFalse(allowed)
        self.assertEqual(err, "recovery_anchor_missing")
        rc, out = init_recovery_state(self.workdir, OWNER_ACK_INIT)
        self.assertEqual(rc, 0, out)
        self.assertEqual(out.get("mode"), "rebuild-anchor")
        allowed, err, _st = gate_check(self.workdir)
        self.assertTrue(allowed)
        self.assertIsNone(err)
        self._seed_clean_synced()

    def test_init_refuses_unreadable_state(self):
        """A state file that exists but cannot be parsed must not be
        guessed about: init refuses until the operator removes it
        deliberately (then the anchor governs)."""
        self.assertTrue(HAS_D3, "D3 API missing")
        self._maybe_init()
        self._seed_clean_synced()
        with open(self.state_path, "w", encoding="utf-8") as f:
            f.write("{corrupt")
        rc, out = init_recovery_state(self.workdir, OWNER_ACK_INIT)
        self.assertEqual(rc, 1)
        self.assertEqual(out.get("error"),
                         "init_refused_unreadable_state")
        # Deliberate removal, then the anchor governs: rebuild.
        self._remove_if_exists(self.state_path)
        rc, out = init_recovery_state(self.workdir, OWNER_ACK_INIT)
        self.assertEqual(rc, 0, out)
        self.assertEqual(out.get("mode"), "rebuild-from-anchor")


class TestGateCheck(D3TestBase):
    """gate_check() precision: the refusal code must name the mode,
    and a recorded STOP keeps its own code (pool_stopped)."""

    def test_gate_check_reports_precise_errors(self):
        self.assertTrue(HAS_D3, "D3 API missing")
        allowed, err, state = gate_check(self.workdir)
        self.assertFalse(allowed)
        self.assertEqual(err, "recovery_state_uninitialized")
        self.assertIsNone(state)
        self._maybe_init()
        allowed, err, state = gate_check(self.workdir)
        self.assertTrue(allowed)
        self.assertIsNone(err)
        self.assertEqual(state["state"], "ok")
        rc, _out = enter_degraded(self.workdir, "test", now=self.now)
        self.assertEqual(rc, 0)
        allowed, err, state = gate_check(self.workdir)
        self.assertFalse(allowed)
        self.assertEqual(err, "pool_stopped")
        self.assertEqual(state["state"], "degraded")

    def test_read_state_strict_reports_modes(self):
        self.assertTrue(HAS_D3, "D3 API missing")
        state, err = read_state_strict(self.workdir)
        self.assertIsNone(state)
        self.assertEqual(err, "recovery_state_uninitialized")
        self._maybe_init()
        self._seed_clean_synced()
        state, err = read_state_strict(self.workdir)
        self.assertIsNone(err)
        self.assertEqual(state["state"], "ok")
        with open(self.state_path, "w", encoding="utf-8") as f:
            f.write("{corrupt")
        state, err = read_state_strict(self.workdir)
        self.assertIsNone(state)
        self.assertEqual(err, "recovery_state_corrupt")
