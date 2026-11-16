"""D2 test suite (GPT D1 review 6881291219: 3 code-level blockers +
dual-gate counterexample tests).

Blocker 1 -- version/evidence binding (TestVersionChain,
TestPublishBinding, TestSyncBinding): SHA mismatch, sidecar tampering,
source replaced, sidecar swapped, v1-only sidecar, caller-version
mismatch; the chain re-verifies from actual bytes + native record.
Blocker 2 -- sync lock race (TestSyncLockRace): publish updating
while sync queues; no false sync_verify_failed; success/failure
reflects the actually served version.
Blocker 3 -- rollback vs recovery (TestRecovery): TTL-expired,
missing native results, production-broken-but-rollback-refused;
enter-degraded / manual-restore / clear-stop; served status is never
reported qualified when its evidence is stale.
Blocker 4 -- dual-gate counterexamples (TestDualGateCounterexamples):
same-fingerprint parameter change, multiple results at the same
timestamp, source version change; the D2 >= subsequent-failure rule.

HONEST BOUNDARY -- fixtures are SYNTHETIC (fixtures/build_fixtures.py):
TEST-NET hosts, password TEST-ONLY-NOT-A-REAL-NODE, and the native
record's tested_at is generated at fixture-build time (now). A fixture
run passing the gate proves the CODE paths, never that a real phone
measured anything: synthetic tested_at=now is NOT real phone evidence.
No test here claims otherwise; the D2 report states it explicitly.

Run: python3 -m unittest discover -s tests -v   (from the D2 root)
"""

import hashlib
import json
import os
import subprocess
import sys
import tempfile
import time
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
D2_ROOT = os.path.dirname(HERE)
sys.path.insert(0, D2_ROOT)

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
from pool.version_chain import (  # noqa: E402
    build_version_chain, read_chain_sidecar, sha256_lines,
    verify_version_chain)

FIX = os.path.join(D2_ROOT, "fixtures")


def _read_lines(path):
    with open(path, encoding="utf-8") as f:
        return [l.rstrip("\n") for l in f if l.strip()]


def _fp_of(line):
    name, proto, host, port, params = parse_surge_line(line)
    return fingerprint_of(proto, host, port, params)


def _results(lines, pass_fps, fail_fps=(), slow_fps_ms=None):
    """Native result rows for `lines` (one row per line)."""
    slow_fps_ms = slow_fps_ms or {}
    out = []
    for line in lines:
        fp = _fp_of(line)
        name = line.split(" = ", 1)[0]
        if fp in fail_fps:
            out.append({"fingerprint": fp, "name": name,
                        "success": False, "ms": None})
        elif fp in slow_fps_ms:
            out.append({"fingerprint": fp, "name": name,
                        "success": True, "ms": slow_fps_ms[fp]})
        elif fp in pass_fps:
            out.append({"fingerprint": fp, "name": name,
                        "success": True, "ms": 150})
        else:
            out.append({"fingerprint": fp, "name": name,
                        "success": False, "ms": None})
    return out


def _run(version_sha, tested_at, results):
    return {"version_sha": version_sha, "tested_at": tested_at,
            "network": "5G cellular pdp_ip0, no Wi-Fi",
            "surge": "6.100.0 build 4025",
            "results": results}


def _make_record(lines, pass_fps, version_sha, tested_at, fail_fps=(),
                 slow_fps_ms=None):
    """Build a native-results-v1 record dict for arbitrary lines."""
    return {"format": "native-results-v1",
            "runs": [_run(version_sha, tested_at,
                          _results(lines, pass_fps, fail_fps, slow_fps_ms))]}


class D2TestBase(unittest.TestCase):
    def setUp(self):
        self.workdir = tempfile.mkdtemp(prefix="d2-test-")
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

    def tearDown(self):
        import shutil
        shutil.rmtree(self.workdir, ignore_errors=True)

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
        """v1 clean (publish+sync), then v2 13-line subset publish.

        Returns (subset, subset_sha, subset_record_path, subset_path).
        After this: publish file = 13 lines; history holds the v1
        snapshot; .prev is the v1 clean file.
        """
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


class TestVersionChain(D2TestBase):
    def test_chain_roundtrip_verifies(self):
        chain = build_version_chain(
            self.version_sha, self.clean14, self.admitted)
        ok, err, summary = verify_version_chain(
            chain, self.clean14, self.record_path,
            probe_db=self.probe_db, now=self.now)
        self.assertTrue(ok, err)
        self.assertEqual(summary["admitted_count"], 14)
        self.assertEqual(summary["published_count"], 14)
        self.assertEqual(chain["published_sha"], self.clean_sha)

    def test_chain_mutation_breaks_chain_id(self):
        chain = build_version_chain(
            self.version_sha, self.clean14, self.admitted)
        for field, bad in (
                ("source_sha", "0" * 64),
                ("published_sha", "0" * 64),
                ("chain_id", "0" * 64)):
            mutated = dict(chain)
            mutated[field] = bad
            ok, err, _s = verify_version_chain(
                mutated, self.clean14, self.record_path,
                probe_db=self.probe_db, now=self.now)
            self.assertFalse(ok)
            self.assertEqual(err, "chain_id_mismatch", field)

    def test_chain_recomputed_id_cannot_fake_admitted_set(self):
        # Attacker edits the admitted list AND recomputes chain_id:
        # the chain is internally consistent, but the native record
        # still says 14 -- the admitted-set cross-check catches it.
        from pool.version_chain import _canonical_chain_bytes
        chain = build_version_chain(
            self.version_sha, self.clean14, self.admitted)
        mutated = dict(chain)
        mutated["admitted_fingerprints"] = sorted(self.admitted)[:13]
        mutated["chain_id"] = hashlib.sha256(_canonical_chain_bytes(
            mutated["source_sha"], mutated["published_sha"],
            set(mutated["admitted_fingerprints"]),
            set(mutated["published_fingerprints"]))).hexdigest()
        ok, err, _s = verify_version_chain(
            mutated, self.clean14, self.record_path,
            probe_db=self.probe_db, now=self.now)
        self.assertFalse(ok)
        self.assertEqual(err, "chain_admitted_set_mismatch")

    def test_chain_published_lines_mismatch(self):
        chain = build_version_chain(
            self.version_sha, self.clean14, self.admitted)
        ok, err, _s = verify_version_chain(
            chain, self.clean14[:13], self.record_path,
            probe_db=self.probe_db, now=self.now)
        self.assertFalse(ok)
        self.assertEqual(err, "chain_published_sha_mismatch")

    def test_chain_build_rejects_unadmitted_line(self):
        slow = self.pool44[10]  # T11: native 320, not admitted
        with self.assertRaises(ValueError):
            build_version_chain(
                self.version_sha, self.clean14 + [slow], self.admitted)

    def test_chain_verification_ignores_ttl(self):
        # Binding (bytes <-> evidence version) holds even after the
        # TTL expired: freshness is the gate's job, not the chain's.
        # Without this, a TTL-expired anchor could never be classified
        # last-verified-safe and recovery would be impossible.
        chain = build_version_chain(
            self.version_sha, self.clean14, self.admitted)
        ok, err, _s = verify_version_chain(
            chain, self.clean14, self.record_path,
            probe_db=self.probe_db, now=self.now_stale)
        self.assertTrue(ok, err)
        admitted, _cond, diag = load_native_allowlist(
            self.record_path, self.version_sha,
            probe_db=self.probe_db, now=self.now_stale)
        self.assertEqual(len(admitted), 0, "gate must still refuse stale")
        self.assertEqual(diag["reasons"].get("native_stale"), 14)


class TestPublishBinding(D2TestBase):
    def test_publish_sha_mismatch_refuses(self):
        self._seed_clean()
        target = os.path.join(self.workdir, "publish", "pool-new.txt")
        before = file_manifest(target)
        mod_lines = list(self.pool44)
        mod_lines[0] = mod_lines[0].replace(
            "TEST-ONLY-NOT-A-REAL-NODE", "TEST-ONLY-CHANGED")
        mod_path = self._write_lines(mod_lines, "modified.txt")
        rc, res = run_publish(
            self.workdir, self.clean14, self.record_path, self.version_sha,
            probe_db=self.probe_db, now=self.now, source_file=mod_path)
        self.assertEqual(rc, 1)
        self.assertEqual(res.get("error"), "source_version_sha_mismatch")
        self.assertEqual(file_manifest(target)["sha256"], before["sha256"])

    def test_old_evidence_on_new_version_refuses(self):
        # GPT attack scenario: old qualified evidence pasted onto a
        # new version whose identical-fingerprint lines would pass.
        self._seed_clean()
        target = os.path.join(self.workdir, "publish", "pool-new.txt")
        before = file_manifest(target)
        v2_lines = list(self.pool44)
        v2_lines[0] = v2_lines[0].replace(
            "TEST-ONLY-NOT-A-REAL-NODE", "TEST-ONLY-CHANGED")
        v2_path = self._write_lines(v2_lines, "v2.txt")
        v2_sha = hashlib.sha256(
            ("\n".join(v2_lines) + "\n").encode("utf-8")).hexdigest()
        # (a) caller claims the OLD version sha for the NEW bytes.
        rc, res = run_publish(
            self.workdir, v2_lines, self.record_path, self.version_sha,
            probe_db=self.probe_db, now=self.now, source_file=v2_path)
        self.assertEqual(rc, 1)
        self.assertEqual(res.get("error"), "source_version_sha_mismatch")
        # (b) caller claims the NEW sha: binding passes, but there is
        # no native evidence for v2 at all.
        rc, res = run_publish(
            self.workdir, v2_lines, self.record_path, v2_sha,
            probe_db=self.probe_db, now=self.now, source_file=v2_path)
        self.assertEqual(rc, 1)
        self.assertEqual(res.get("error"), "phone_gate_zero_qualified")
        self.assertEqual(res["gate_diag"]["reasons"].get(
            "native_version_mismatch"), 44)
        self.assertEqual(file_manifest(target)["sha256"], before["sha256"])

    def test_publish_candidate_not_in_source_refuses(self):
        self._seed_clean()
        target = os.path.join(self.workdir, "publish", "pool-new.txt")
        before = file_manifest(target)
        smuggled = self.clean14[0].replace(
            "TEST-ONLY-NOT-A-REAL-NODE", "TEST-ONLY-CHANGED")
        rc, res = run_publish(
            self.workdir, self.clean14 + [smuggled], self.record_path,
            self.version_sha, probe_db=self.probe_db, now=self.now,
            source_file=self.pool44_path)
        self.assertEqual(rc, 1)
        self.assertEqual(res.get("error"), "candidate_not_in_source")
        self.assertEqual(file_manifest(target)["sha256"], before["sha256"])

    def test_publish_duplicate_candidates_refuses(self):
        rc, res = run_publish(
            self.workdir, self.clean14 + [self.clean14[0]],
            self.record_path, self.version_sha,
            probe_db=self.probe_db, now=self.now,
            source_file=self.pool44_path)
        self.assertEqual(rc, 1)
        self.assertEqual(res.get("error"), "candidate_duplicate_lines")

    def test_publish_without_source_file_refuses(self):
        rc, res = run_publish(
            self.workdir, self.clean14, self.record_path, self.version_sha,
            probe_db=self.probe_db, now=self.now, source_file=None)
        self.assertEqual(rc, 1)
        self.assertEqual(res.get("error"), "source_file_required")
        target = os.path.join(self.workdir, "publish", "pool-new.txt")
        self.assertFalse(os.path.exists(target))

    def test_publish_writes_verifiable_chain(self):
        self._seed_clean()
        publish_dir = os.path.join(self.workdir, "publish")
        _meta, chain = read_chain_sidecar(publish_dir, "pool-new.txt")
        self.assertIsNotNone(chain)
        ok, err, summary = verify_version_chain(
            chain, self.clean14, self.record_path,
            probe_db=self.probe_db, now=self.now)
        self.assertTrue(ok, err)
        self.assertEqual(summary["published_sha_prefix"],
                         self.clean_sha[:12])
        self.assertEqual(summary["source_sha_prefix"],
                         self.version_sha[:12])

    def test_publish_subset_chain(self):
        subset = self.clean14[:13]
        subset_sha = hashlib.sha256(
            ("\n".join(subset) + "\n").encode("utf-8")).hexdigest()
        record2 = _make_record(subset, {_fp_of(l) for l in subset},
                               subset_sha, self.tested_at)
        path2 = self._write_record(record2, "record2.json")
        rc, res, _p = self._publish_subset(subset, path2, subset_sha)
        self.assertEqual(rc, 0, res)
        self.assertEqual(res["manifest"]["sha256"], subset_sha)
        publish_dir = os.path.join(self.workdir, "publish")
        _meta, chain = read_chain_sidecar(publish_dir, "pool-new.txt")
        ok, err, summary = verify_version_chain(
            chain, subset, path2, probe_db=self.probe_db, now=self.now)
        self.assertTrue(ok, err)
        self.assertEqual(summary["published_count"], 13)


class TestSyncBinding(D2TestBase):
    def _tamper_sidecar(self, mutate):
        sidecar = os.path.join(
            self.workdir, "publish", "pool-new.txt.meta.json")
        with open(sidecar) as _f:
            meta = json.load(_f)
        mutate(meta["version_chain"])
        with open(sidecar, "w", encoding="utf-8") as f:
            json.dump(meta, f)

    def test_sync_sidecar_tampered_refuses(self):
        self._seed_clean_synced()
        served = os.path.join(self.workdir, "served", "pool-new.txt")
        before = file_manifest(served)
        # Naive tamper: published_sha changed, chain_id stale.
        self._tamper_sidecar(
            lambda c: c.update(published_sha="0" * 64))
        rc, res = run_sync(self.workdir, self.record_path, self.version_sha,
                           probe_db=self.probe_db, now=self.now)
        self.assertEqual(rc, 1)
        self.assertEqual(res.get("error"), "sync_chain_chain_id_mismatch")
        self.assertEqual(file_manifest(served)["sha256"], before["sha256"])

    def test_sync_sidecar_smart_tamper_refuses(self):
        # Attacker recomputes chain_id for the tampered admitted list.
        from pool.version_chain import _canonical_chain_bytes
        self._seed_clean_synced()
        served = os.path.join(self.workdir, "served", "pool-new.txt")
        before = file_manifest(served)

        def _smart(c):
            c["admitted_fingerprints"] = sorted(self.admitted)[:13]
            c["chain_id"] = hashlib.sha256(_canonical_chain_bytes(
                c["source_sha"], c["published_sha"],
                set(c["admitted_fingerprints"]),
                set(c["published_fingerprints"]))).hexdigest()
        self._tamper_sidecar(_smart)
        rc, res = run_sync(self.workdir, self.record_path, self.version_sha,
                           probe_db=self.probe_db, now=self.now)
        self.assertEqual(rc, 1)
        self.assertEqual(res.get("error"),
                         "sync_chain_chain_admitted_set_mismatch")
        self.assertEqual(file_manifest(served)["sha256"], before["sha256"])

    def test_sync_source_replaced_refuses(self):
        self._seed_clean_synced()
        served = os.path.join(self.workdir, "served", "pool-new.txt")
        before = file_manifest(served)
        with open(os.path.join(self.workdir, "publish", "pool-new.txt"),
                  "w", encoding="utf-8") as f:
            f.write("\n".join(self.pool44) + "\n")
        rc, res = run_sync(self.workdir, self.record_path, self.version_sha,
                           probe_db=self.probe_db, now=self.now)
        self.assertEqual(rc, 1)
        self.assertEqual(res.get("error"),
                         "sync_chain_chain_published_sha_mismatch")
        self.assertEqual(file_manifest(served)["sha256"], before["sha256"])
        self.assertEqual(file_manifest(served)["lines"], 14)

    def test_sync_sidecar_swapped_refuses(self):
        self._seed_v1_v2()
        served = os.path.join(self.workdir, "served", "pool-new.txt")
        # v1's snapshot sidecar (clean 14) swapped onto the v2 file.
        snap = self._history_snapshot()
        import shutil
        shutil.copyfile(snap + ".meta.json", os.path.join(
            self.workdir, "publish", "pool-new.txt.meta.json"))
        rc, res = run_sync(self.workdir, self.record_path, self.version_sha,
                           probe_db=self.probe_db, now=self.now)
        self.assertEqual(rc, 1)
        self.assertEqual(res.get("error"),
                         "sync_chain_chain_published_sha_mismatch")
        self.assertEqual(file_manifest(served)["lines"], 14)

    def test_sync_v1_only_sidecar_refuses(self):
        self._seed_clean_synced()
        served = os.path.join(self.workdir, "served", "pool-new.txt")
        before = file_manifest(served)
        sidecar = os.path.join(
            self.workdir, "publish", "pool-new.txt.meta.json")
        with open(sidecar) as _f:
            meta = json.load(_f)
        del meta["version_chain"]
        with open(sidecar, "w", encoding="utf-8") as f:
            json.dump(meta, f)
        rc, res = run_sync(self.workdir, self.record_path, self.version_sha,
                           probe_db=self.probe_db, now=self.now)
        self.assertEqual(rc, 1)
        self.assertEqual(res.get("error"), "sync_sidecar_no_version_chain")
        self.assertEqual(file_manifest(served)["sha256"], before["sha256"])

    def test_sync_missing_sidecar_refuses(self):
        self._seed_clean_synced()
        os.unlink(os.path.join(
            self.workdir, "publish", "pool-new.txt.meta.json"))
        rc, res = run_sync(self.workdir, self.record_path, self.version_sha,
                           probe_db=self.probe_db, now=self.now)
        self.assertEqual(rc, 1)
        self.assertEqual(res.get("error"), "sync_sidecar_missing")

    def test_sync_caller_version_mismatch_refuses(self):
        self._seed_clean_synced()
        rc, res = run_sync(self.workdir, self.record_path, "c" * 64,
                           probe_db=self.probe_db, now=self.now)
        self.assertEqual(rc, 1)
        self.assertEqual(res.get("error"), "sync_source_version_mismatch")

    def test_sync_without_caller_version_ok(self):
        # Binding comes from the sidecar chain + actual bytes alone.
        self._seed_clean_synced()
        rc, res = run_sync(self.workdir, self.record_path, None,
                           probe_db=self.probe_db, now=self.now)
        self.assertEqual(rc, 0, res)
        served = os.path.join(self.workdir, "served", "pool-new.txt")
        self.assertEqual(file_manifest(served)["sha256"], self.clean_sha)


if __name__ == "__main__":
    unittest.main(verbosity=2)


class TestSyncLockRace(D2TestBase):
    def test_sync_queues_behind_publish_lock(self):
        """Sync waits for the lock (lock_timeout), then succeeds and
        reports the version it actually served (in-lock manifest)."""
        self._seed_clean_synced()
        publish_file = os.path.join(self.workdir, "publish", "pool-new.txt")
        served_file = os.path.join(self.workdir, "served", "pool-new.txt")
        ready = os.path.join(self.workdir, "holder-ready.txt")
        holder = subprocess.Popen(
            [sys.executable, "drills/hold_lock.py", "--workdir",
             self.workdir, "--hold", "3", "--ready", ready],
            cwd=D2_ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            for _ in range(100):
                if os.path.exists(ready):
                    break
                time.sleep(0.1)
            self.assertTrue(os.path.exists(ready), "holder never acquired")
            rc, res = run_sync(self.workdir, self.record_path,
                               self.version_sha, probe_db=self.probe_db,
                               now=self.now, lock_timeout=1)
            self.assertEqual(rc, 1)
            self.assertTrue(res.get("error", "").startswith("lock_timeout"))
            holder.wait(timeout=30)
            rc, res = run_sync(self.workdir, self.record_path,
                               self.version_sha, probe_db=self.probe_db,
                               now=self.now)
            self.assertEqual(rc, 0, res)
            # Success reflects the actually served version: the
            # in-lock source manifest equals the served manifest.
            self.assertEqual(res["source_manifest"]["sha256"],
                             res["served_manifest_after"]["sha256"])
            self.assertEqual(file_manifest(served_file)["sha256"],
                             file_manifest(publish_file)["sha256"])
        finally:
            if holder.poll() is None:
                holder.kill()

    def test_concurrent_publish_sync_no_false_verify_failure(self):
        """D1 race, fixed: while sync waits for the lock, a legitimate
        gated publish updates the source. Sync must copy the NEW file
        and succeed -- never report sync_verify_failed for a file that
        is actually fine, whichever order wins the lock."""
        self._seed_clean_synced()
        subset = self.clean14[:13]
        subset_sha = hashlib.sha256(
            ("\n".join(subset) + "\n").encode("utf-8")).hexdigest()
        subset_path = self._write_lines(subset, "subset.txt")
        with open(self.record_path) as _f:
            rec1 = json.load(_f)
        rec2 = _make_record(subset, {_fp_of(l) for l in subset},
                            subset_sha, self.tested_at)
        combined = {"format": "native-results-v1",
                    "runs": rec1["runs"] + rec2["runs"]}
        combined_path = self._write_record(combined, "combined.json")
        publish_file = os.path.join(self.workdir, "publish", "pool-new.txt")
        served_file = os.path.join(self.workdir, "served", "pool-new.txt")
        v2_sha = subset_sha
        ready = os.path.join(self.workdir, "holder-ready.txt")
        holder = subprocess.Popen(
            [sys.executable, "drills/hold_lock.py", "--workdir",
             self.workdir, "--hold", "3", "--ready", ready],
            cwd=D2_ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            for _ in range(100):
                if os.path.exists(ready):
                    break
                time.sleep(0.1)
            self.assertTrue(os.path.exists(ready), "holder never acquired")
            pub = subprocess.Popen(
                [sys.executable, "-m", "pool.publish",
                 "--workdir", self.workdir, "--candidates", subset_path,
                 "--source-file", subset_path,
                 "--native-record", combined_path,
                 "--source-version", subset_sha,
                 "--probe-db", self.probe_db],
                cwd=D2_ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                text=True)
            syn = subprocess.Popen(
                [sys.executable, "-m", "pool.sync",
                 "--workdir", self.workdir,
                 "--native-record", combined_path,
                 "--probe-db", self.probe_db],
                cwd=D2_ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                text=True)
            pub_out, _ = pub.communicate(timeout=120)
            syn_out, _ = syn.communicate(timeout=120)
            pub_json = json.loads(pub_out.strip().splitlines()[-1])
            syn_json = json.loads(syn_out.strip().splitlines()[-1])
            self.assertEqual(pub.returncode, 0, pub_out)
            self.assertEqual(syn.returncode, 0, syn_out)
            self.assertNotEqual(syn_json.get("error"), "sync_verify_failed")
            # Internal consistency: served == what sync read in-lock.
            self.assertEqual(
                syn_json["served_manifest_after"]["sha256"],
                syn_json["source_manifest"]["sha256"])
            # Served is one of the two valid gated versions.
            served_sha = file_manifest(served_file)["sha256"]
            self.assertIn(served_sha, (self.clean_sha, v2_sha))
            # A follow-up sync converges served to the published v2.
            rc, res = run_sync(self.workdir, combined_path, None,
                               probe_db=self.probe_db, now=self.now)
            self.assertEqual(rc, 0, res)
            self.assertEqual(file_manifest(served_file)["sha256"], v2_sha)
            self.assertEqual(file_manifest(publish_file)["sha256"], v2_sha)
        finally:
            if holder.poll() is None:
                holder.kill()

    def test_sync_reports_actually_served_version(self):
        """Each sync result's served_version_sha is the version that
        is actually on disk after that sync (v1, then v2)."""
        self._seed_clean_synced()
        served_file = os.path.join(self.workdir, "served", "pool-new.txt")
        rc, res = run_sync(self.workdir, self.record_path, self.version_sha,
                           probe_db=self.probe_db, now=self.now)
        self.assertEqual(rc, 0, res)
        self.assertEqual(res["served_version_sha"], self.clean_sha)
        subset, subset_sha, path2, _sp = self._seed_v1_v2()
        rc, res = run_sync(self.workdir, path2, None,
                           probe_db=self.probe_db, now=self.now)
        self.assertEqual(rc, 0, res)
        self.assertEqual(res["served_version_sha"], subset_sha)
        self.assertEqual(file_manifest(served_file)["sha256"], subset_sha)


class TestRecovery(D2TestBase):
    def test_rollback_ttl_expired_refuses_with_recovery_plan(self):
        """The real emergency shape: evidence is past TTL, rollback
        refuses -- but the result now names the last-verified-safe
        anchor and the recommended action instead of just failing."""
        self._seed_v1_v2()
        target = os.path.join(self.workdir, "publish", "pool-new.txt")
        rc, res = run_rollback(self.workdir, "latest-history",
                               self.record_path, probe_db=self.probe_db,
                               now=self.now_stale)
        self.assertEqual(rc, 1)
        self.assertEqual(res.get("error"), "rollback_gate_zero_qualified")
        self.assertEqual(file_manifest(target)["lines"], 13)
        recovery = res.get("recovery", {})
        self.assertEqual(recovery.get("recommended_action"),
                         "manual-recovery")
        last_safe = recovery.get("last_verified_safe")
        self.assertIsNotNone(last_safe)
        self.assertEqual(last_safe["status"], "last_verified_safe")
        self.assertEqual(last_safe["lines"], 14)
        self.assertEqual(last_safe["last_verified_at"], self.tested_at)

    def test_rollback_missing_native_record(self):
        """No evidence at all: nothing is restorable; the plan says
        rebuild from a fresh native test (not 'keep the old file')."""
        self._seed_v1_v2()
        rc, res = run_rollback(
            self.workdir, "latest-history",
            os.path.join(self.workdir, "no-such.json"),
            probe_db=self.probe_db, now=self.now)
        self.assertEqual(rc, 1)
        self.assertTrue(res.get("error", "").startswith("rollback_chain_"))
        recovery = res.get("recovery", {})
        self.assertEqual(recovery.get("recommended_action"),
                         "rebuild-from-fresh-native-test")
        self.assertIsNone(recovery.get("last_verified_safe"))

    def test_enter_degraded_blocks_publish_sync(self):
        self._seed_clean_synced()
        publish_file = os.path.join(self.workdir, "publish", "pool-new.txt")
        served_file = os.path.join(self.workdir, "served", "pool-new.txt")
        before_pub = file_manifest(publish_file)
        before_srv = file_manifest(served_file)
        rc, out = enter_degraded(self.workdir, "test reason", now=self.now)
        self.assertEqual(rc, 0, out)
        self.assertTrue(is_stopped(self.workdir))
        state = read_state(self.workdir)
        self.assertEqual(state["state"], "degraded")
        self.assertEqual(state["served_status"], "stale-not-qualified")
        rc, res = run_publish(
            self.workdir, self.clean14, self.record_path, self.version_sha,
            probe_db=self.probe_db, now=self.now,
            source_file=self.pool44_path)
        self.assertEqual(rc, 1)
        self.assertEqual(res.get("error"), "pool_stopped")
        rc, res = run_sync(self.workdir, self.record_path, self.version_sha,
                           probe_db=self.probe_db, now=self.now)
        self.assertEqual(rc, 1)
        self.assertEqual(res.get("error"), "pool_stopped")
        self.assertEqual(file_manifest(publish_file)["sha256"],
                         before_pub["sha256"])
        self.assertEqual(file_manifest(served_file)["sha256"],
                         before_srv["sha256"])

    def test_manual_restore_flow(self):
        """TTL-expired -> degraded -> manual restore (ack) -> fresh
        evidence -> clear stop -> ok. The restored version is never
        claimed qualified before the fresh re-test."""
        self._seed_v1_v2()
        anchor = self._history_snapshot()
        rc, out = enter_degraded(self.workdir, "ttl expired",
                                 now=self.now_stale)
        self.assertEqual(rc, 0, out)
        rc, out = manual_restore(self.workdir, anchor, self.record_path,
                                 "WRONG-ACK", probe_db=self.probe_db,
                                 now=self.now_stale)
        self.assertEqual(rc, 1)
        self.assertEqual(out.get("error"), "owner_ack_required")
        rc, out = manual_restore(self.workdir, anchor, self.record_path,
                                 OWNER_ACK_RESTORE, probe_db=self.probe_db,
                                 now=self.now_stale)
        self.assertEqual(rc, 0, out)
        state = read_state(self.workdir)
        self.assertEqual(state["state"], "manual-restored")
        self.assertTrue(state["stopped"])
        self.assertTrue(state["requires_fresh_native_retest"])
        served_file = os.path.join(self.workdir, "served", "pool-new.txt")
        self.assertEqual(file_manifest(served_file)["sha256"],
                         self.clean_sha)
        # Still stopped: publish refuses until the fresh re-test.
        rc, res = run_publish(
            self.workdir, self.clean14, self.record_path, self.version_sha,
            probe_db=self.probe_db, now=self.now_stale,
            source_file=self.pool44_path)
        self.assertEqual(rc, 1)
        self.assertEqual(res.get("error"), "pool_stopped")
        # Clear-stop without fresh evidence refuses.
        rc, out = clear_stop(self.workdir, OWNER_ACK_CLEAR,
                             self.record_path, probe_db=self.probe_db,
                             now=self.now_stale)
        self.assertEqual(rc, 1)
        self.assertEqual(out.get("error"), "served_not_currently_qualified")
        # Fresh native evidence (new run for the v1 version, fresh ts).
        now3 = self.now_stale + 60
        fresh = _make_record(self.clean14, self.admitted,
                             self.version_sha, self.now_stale)
        fresh_path = self._write_record(fresh, "fresh.json")
        rc, out = clear_stop(self.workdir, OWNER_ACK_CLEAR, fresh_path,
                             probe_db=self.probe_db, now=now3)
        self.assertEqual(rc, 0, out)
        state = read_state(self.workdir)
        self.assertEqual(state["state"], "ok")
        self.assertFalse(state["stopped"])
        rc, res = run_publish(
            self.workdir, self.clean14, fresh_path, self.version_sha,
            probe_db=self.probe_db, now=now3, source_file=self.pool44_path)
        self.assertEqual(rc, 0, res)

    def test_production_broken_rollback_refused_then_manual_restore(self):
        """Production is ALREADY broken (legacy 44 lines served) and
        rollback refuses (TTL expired): degraded, manual restore of
        the last-verified-safe anchor, served is clean again but
        flagged unverified until a fresh re-test."""
        subset, subset_sha, path2, _sp = self._seed_v1_v2()
        publish_file = os.path.join(self.workdir, "publish", "pool-new.txt")
        served_file = os.path.join(self.workdir, "served", "pool-new.txt")
        # Break production AFTER the v1 snapshot exists: legacy writer
        # overwrites both publish/ and served/ with ungated 44 lines.
        legacy = "\n".join(self.pool44) + "\n"
        with open(publish_file, "w", encoding="utf-8") as f:
            f.write(legacy)
        with open(served_file, "w", encoding="utf-8") as f:
            f.write(legacy)
        rc, res = run_rollback(self.workdir, "latest-history",
                               self.record_path, probe_db=self.probe_db,
                               now=self.now_stale)
        self.assertEqual(rc, 1)
        self.assertEqual(res.get("error"), "rollback_gate_zero_qualified")
        self.assertEqual(res["recovery"]["recommended_action"],
                         "manual-recovery")
        rc, out = enter_degraded(self.workdir, "production broken",
                                 now=self.now_stale)
        self.assertEqual(rc, 0, out)
        st = status(self.workdir, self.record_path,
                    probe_db=self.probe_db, now=self.now_stale)
        self.assertEqual(st["served_status_live"], "broken-unqualified")
        anchor = self._history_snapshot()
        rc, out = manual_restore(self.workdir, anchor, self.record_path,
                                 OWNER_ACK_RESTORE, probe_db=self.probe_db,
                                 now=self.now_stale)
        self.assertEqual(rc, 0, out)
        self.assertEqual(file_manifest(served_file)["sha256"],
                         self.clean_sha)
        st = status(self.workdir, self.record_path,
                    probe_db=self.probe_db, now=self.now_stale)
        self.assertEqual(st["served_status_live"],
                         "manual-restored-unverified")
        self.assertTrue(st["stopped"])

    def test_status_stale_vs_broken(self):
        """Same file, two verdicts: evidence stale -> stale-not-
        qualified; file replaced by ungated lines -> broken-unqualified.
        Neither is ever reported as qualified."""
        self._seed_clean_synced()
        st = status(self.workdir, self.record_path,
                    probe_db=self.probe_db, now=self.now)
        self.assertEqual(st["served_status_live"], "qualified")
        st = status(self.workdir, self.record_path,
                    probe_db=self.probe_db, now=self.now_stale)
        self.assertEqual(st["served_status_live"], "stale-not-qualified")
        served_file = os.path.join(self.workdir, "served", "pool-new.txt")
        with open(served_file, "w", encoding="utf-8") as f:
            f.write("\n".join(self.pool44) + "\n")
        st = status(self.workdir, self.record_path,
                    probe_db=self.probe_db, now=self.now_stale)
        self.assertEqual(st["served_status_live"], "broken-unqualified")

    def test_keeping_old_file_not_claimed_qualified(self):
        """A refused publish keeps the old file -- and the wording
        says so plainly ('not claimed compliant'); once its evidence
        goes stale the status reports it stale, never qualified."""
        self._seed_clean_synced()
        record = _make_record(self.pool44, set(), self.version_sha,
                              self.tested_at)
        path = self._write_record(record, "allfail.json")
        rc, res = run_publish(self.workdir, self.pool44, path,
                              self.version_sha, probe_db=self.probe_db,
                              now=self.now, source_file=self.pool44_path)
        self.assertEqual(rc, 1)
        self.assertIn("not claimed compliant",
                      res.get("zero_qualified_safe_state", ""))
        st = status(self.workdir, self.record_path,
                    probe_db=self.probe_db, now=self.now_stale)
        self.assertEqual(st["served_status_live"], "stale-not-qualified")

    def test_assess_anchors(self):
        assessment = assess_anchors(self.workdir, self.record_path,
                                    probe_db=self.probe_db, now=self.now)
        self.assertEqual(assessment["recommended_action"],
                         "rebuild-from-fresh-native-test")
        self._seed_v1_v2()
        assessment = assess_anchors(self.workdir, self.record_path,
                                    probe_db=self.probe_db, now=self.now)
        self.assertEqual(assessment["recommended_action"], "rollback")
        self.assertEqual(assessment["verified_safe_count"], 2)
        assessment = assess_anchors(self.workdir, self.record_path,
                                    probe_db=self.probe_db,
                                    now=self.now_stale)
        self.assertEqual(assessment["recommended_action"],
                         "manual-recovery")
        self.assertEqual(assessment["last_verified_safe_count"], 2)


class TestDualGateCounterexamples(D2TestBase):
    def test_param_change_new_fingerprint_not_admitted(self):
        """Same node, one parameter changed (password) == a DIFFERENT
        fingerprint == NO evidence. The gate must not admit it, and
        publish must not let it in via the old source file either."""
        changed = self.clean14[0].replace(
            "TEST-ONLY-NOT-A-REAL-NODE", "TEST-ONLY-CHANGED")
        self.assertNotEqual(_fp_of(changed), _fp_of(self.clean14[0]))
        admitted, _c, _d = load_native_allowlist(
            self.record_path, self.version_sha,
            probe_db=self.probe_db, now=self.now)
        self.assertNotIn(_fp_of(changed), admitted)
        # As a candidate against the OLD source file it is not even a
        # member of the tested version.
        rc, res = run_publish(
            self.workdir, [changed], self.record_path, self.version_sha,
            probe_db=self.probe_db, now=self.now,
            source_file=self.pool44_path)
        self.assertEqual(rc, 1)
        self.assertEqual(res.get("error"), "candidate_not_in_source")

    def test_display_name_is_not_identity(self):
        """Display name is excluded from the fingerprint: same params
        + different name == same fingerprint (admitted); same name +
        different params == different fingerprint (not admitted)."""
        renamed = self.clean14[0].replace("T01 ", "T01-renamed ", 1)
        self.assertEqual(_fp_of(renamed), _fp_of(self.clean14[0]))
        admitted, _c, _d = load_native_allowlist(
            self.record_path, self.version_sha,
            probe_db=self.probe_db, now=self.now)
        self.assertIn(_fp_of(renamed), admitted)
        reparam = self.clean14[0].replace(
            "sni=test.invalid", "sni=other.invalid")
        self.assertNotEqual(_fp_of(reparam), _fp_of(self.clean14[0]))
        self.assertNotIn(_fp_of(reparam), admitted)

    def test_same_timestamp_pass_then_fail(self):
        """Two runs, SAME timestamp, SAME version, contradictory
        results for one fingerprint: the gate FAILS CLOSED either
        way. List order does NOT rescue a same-timestamp failure:
        pass-then-fail rejects (latest = fail), and fail-then-pass
        ALSO rejects (the D2 >= subsequent-failure rule voids the
        pass: a failure at the same timestamp as the pass counts).
        Control: two same-timestamp runs that BOTH pass admit."""
        t01_fp = _fp_of(self.pool44[0])
        run_pass = _run(self.version_sha, self.tested_at,
                        _results(self.pool44, self.admitted))
        run_fail_t01 = _run(
            self.version_sha, self.tested_at,
            _results(self.pool44, self.admitted - {t01_fp},
                     fail_fps={t01_fp}))
        rec = {"format": "native-results-v1", "runs": [run_pass, run_fail_t01]}
        path = self._write_record(rec, "samets-pf.json")
        admitted, _c, diag = load_native_allowlist(
            path, self.version_sha, probe_db=self.probe_db, now=self.now)
        self.assertNotIn(t01_fp, admitted)
        self.assertIn(_fp_of(self.clean14[1]), admitted)
        # Fail-then-pass: same timestamp, opposite list order -- the
        # same-timestamp failure still voids the pass (fail-closed).
        rec2 = {"format": "native-results-v1",
                "runs": [run_fail_t01, run_pass]}
        path2 = self._write_record(rec2, "samets-fp.json")
        admitted2, _c2, diag2 = load_native_allowlist(
            path2, self.version_sha, probe_db=self.probe_db, now=self.now)
        self.assertNotIn(t01_fp, admitted2)
        self.assertEqual(diag2["reasons"].get("subsequent_native_failed"), 1)
        # Control: two same-timestamp runs, both passing -> admitted.
        rec3 = {"format": "native-results-v1", "runs": [run_pass, run_pass]}
        path3 = self._write_record(rec3, "samets-pp.json")
        admitted3, _c3, _d3 = load_native_allowlist(
            path3, self.version_sha, probe_db=self.probe_db, now=self.now)
        self.assertIn(t01_fp, admitted3)
        self.assertEqual(len(admitted3), 14)

    def test_same_timestamp_cross_version_fail_voids(self):
        """D2 >= rule: a v2 run at the SAME timestamp as the v1 pass,
        failing the fingerprint, VOIDS the v1 pass (fail-closed).
        A same-timestamp v2 PASS does not void it."""
        t01_fp = _fp_of(self.pool44[0])
        v2_sha = "b" * 64
        run_v1 = _run(self.version_sha, self.tested_at,
                      _results(self.pool44, self.admitted))
        run_v2_fail = _run(
            v2_sha, self.tested_at,
            _results(self.pool44, self.admitted - {t01_fp},
                     fail_fps={t01_fp}))
        rec = {"format": "native-results-v1", "runs": [run_v1, run_v2_fail]}
        path = self._write_record(rec, "samets-xfail.json")
        admitted, _c, diag = load_native_allowlist(
            path, self.version_sha, probe_db=self.probe_db, now=self.now)
        self.assertNotIn(t01_fp, admitted)
        self.assertEqual(diag["reasons"].get("subsequent_native_failed"), 1)
        run_v2_pass = _run(v2_sha, self.tested_at,
                           _results(self.pool44, self.admitted))
        rec2 = {"format": "native-results-v1", "runs": [run_v1, run_v2_pass]}
        path2 = self._write_record(rec2, "samets-xpass.json")
        admitted2, _c2, _d2 = load_native_allowlist(
            path2, self.version_sha, probe_db=self.probe_db, now=self.now)
        self.assertIn(t01_fp, admitted2)
        self.assertEqual(len(admitted2), 14)

    def test_later_version_pass_keeps_old_admission_with_conditions(self):
        """'A later pass on another version does not void the old
        pass' holds ONLY when the old evidence is still fresh AND the
        target source SHA matches. Three pins:
        (a) fresh v1 + v2 pass -> v1 admitted;
        (b) same, but the source FILE is v2 bytes claimed as v1 ->
            source_version_sha_mismatch;
        (c) stale v1 + v2 pass -> v1 refused (freshness condition)."""
        v2_sha = "b" * 64
        run_v1 = _run(self.version_sha, self.tested_at,
                      _results(self.pool44, self.admitted))
        run_v2 = _run(v2_sha, self.tested_at + 7200,
                      _results(self.pool44, self.admitted))
        rec = {"format": "native-results-v1", "runs": [run_v1, run_v2]}
        path = self._write_record(rec, "v2pass.json")
        admitted, _c, _d = load_native_allowlist(
            path, self.version_sha, probe_db=self.probe_db, now=self.now)
        self.assertEqual(len(admitted), 14)
        # (b) source file changed to v2 bytes, still claiming v1.
        v2_lines = list(self.pool44)
        v2_lines[0] = v2_lines[0].replace(
            "TEST-ONLY-NOT-A-REAL-NODE", "TEST-ONLY-CHANGED")
        v2_path = self._write_lines(v2_lines, "v2b.txt")
        rc, res = run_publish(
            self.workdir, self.clean14, path, self.version_sha,
            probe_db=self.probe_db, now=self.now, source_file=v2_path)
        self.assertEqual(rc, 1)
        self.assertEqual(res.get("error"), "source_version_sha_mismatch")
        # (c) v1 evidence stale at now_stale although v2 passed fresh.
        admitted3, _c3, diag3 = load_native_allowlist(
            path, self.version_sha, probe_db=self.probe_db,
            now=self.now_stale)
        self.assertEqual(len(admitted3), 0)
        self.assertEqual(diag3["reasons"].get("native_stale"), 14)

    def test_timestamp_boundary_now(self):
        """tested_at == now is admitted (0 < ts <= now); now+1 is
        rejected outright. The boundary is inclusive on the past side."""
        record = _make_record(self.clean14, self.admitted,
                              self.version_sha, self.now)
        path = self._write_record(record, "ts-now.json")
        admitted, _c, _d = load_native_allowlist(
            path, self.version_sha, now=self.now)
        self.assertEqual(len(admitted), 14)
        record2 = _make_record(self.clean14, self.admitted,
                               self.version_sha, self.now + 1)
        path2 = self._write_record(record2, "ts-future.json")
        admitted2, _c2, diag2 = load_native_allowlist(
            path2, self.version_sha, now=self.now)
        self.assertEqual(len(admitted2), 0)
        self.assertEqual(diag2["reasons"].get("native_ts_invalid"), 14)

    def test_evidence_set_ignores_freshness(self):
        """evidence_admitted_fps is the TTL-independent evidence set
        the chain uses: 14 even when the gate admits 0 (stale)."""
        with open(self.record_path) as _f:
            record = json.load(_f)
        ev = evidence_admitted_fps(record, self.version_sha)
        self.assertEqual(len(ev), 14)
        self.assertEqual(ev, self.admitted)


if __name__ == "__main__":
    unittest.main(verbosity=2)
