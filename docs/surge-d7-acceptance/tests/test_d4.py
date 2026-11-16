"""D4 pinned-wiring verification (Issue #73, GPT D2 review item 3).

Production fact (verified read-only 2026-11-15): the current publish
file is 65 lines = 21 pinned + 44 rotation; the pinned DB holds 25
rows (all trojan). In production `pool.cli publish` the exemption is
STRUCTURAL, not the config flag: pinned lines are concatenated into
the publish file unconditionally (only blocklist-filtered), and
`pinned_protected: true` in config.yaml is read by NO code. Winner
clean also never touches pinned ("只动轮换，钉选永不动").

These tests prove, at the real D3 publish/sync entry points, that a
pinned line is admitted ONLY on fresh same-version native evidence
(<300 ms, <24 h, no subsequent failure) -- exactly like a rotation
line. The fixture split mirrors production: 21 "pinned" lines (the
14 native-clean lines + 7 natively-failed lines) and 23 "rotation"
lines (the rest of the 44-line fixture pool).

Helpers _results/_run/_make_record mirror tests/test_d2.py (kept
local so this file runs standalone).
"""
import hashlib
import json
import os
import sys
import tempfile
import unittest

D4_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, D4_ROOT)

from pool.publish import run_publish  # noqa: E402
from pool.publish_lock import file_manifest  # noqa: E402
from pool.phone_gate import fingerprint_of, parse_surge_line  # noqa: E402
from pool.recovery import OWNER_ACK_INIT, init_recovery_state  # noqa: E402
from pool.sync import run_sync  # noqa: E402

FIX = os.path.join(D4_ROOT, "fixtures")


def _read_lines(path):
    with open(path, encoding="utf-8") as f:
        return [l.rstrip("\n") for l in f if l.strip()]


def _fp_of(line):
    name, proto, host, port, params = parse_surge_line(line)
    return fingerprint_of(proto, host, port, params)


def _results(lines, pass_fps, fail_fps=(), slow_fps_ms=None):
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
    return {"format": "native-results-v1",
            "runs": [_run(version_sha, tested_at,
                          _results(lines, pass_fps, fail_fps,
                                   slow_fps_ms))]}


class D4PinnedTestBase(unittest.TestCase):
    def setUp(self):
        self.workdir = tempfile.mkdtemp(prefix="d4-pinned-")
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
        self.pool44_path = os.path.join(FIX, "pool_44_fixture.txt")
        # Pinned split (mirrors production 21 pinned / 44 rotation):
        # pinned = 14 native-clean + 7 natively-failed; rotation = rest.
        self.clean_fps = {_fp_of(l) for l in self.clean14}
        self.assertEqual(len(self.clean_fps), 14)
        failed = [l for l in self.pool44
                  if _fp_of(l) not in self.clean_fps]
        self.pinned_lines = list(self.clean14) + failed[:7]
        self.pinned_fps = {_fp_of(l) for l in self.pinned_lines}
        self.rotation_lines = [l for l in self.pool44
                               if l not in self.pinned_lines]
        self.assertEqual(len(self.pinned_lines), 21)
        self.assertEqual(len(self.rotation_lines), 23)
        rc, out = init_recovery_state(self.workdir, OWNER_ACK_INIT)
        self.assertEqual(rc, 0, out)

    def tearDown(self):
        import shutil
        shutil.rmtree(self.workdir, ignore_errors=True)

    def _write_record(self, record, name="record.json"):
        path = os.path.join(self.workdir, name)
        with open(path, "w", encoding="utf-8") as f:
            json.dump(record, f)
        return path

    def _publish(self, candidates, record_path, now=None,
                 source_file=None):
        return run_publish(
            self.workdir, candidates, record_path, self.version_sha,
            probe_db=self.probe_db, now=self.now if now is None else now,
            source_file=source_file or self.pool44_path)

    def _published_fps(self):
        target = os.path.join(self.workdir, "publish", "pool-new.txt")
        if not os.path.exists(target):
            return None
        return {_fp_of(l) for l in _read_lines(target)}


class TestPinnedNoExemption(D4PinnedTestBase):
    def test_pinned_admitted_only_on_fresh_evidence(self):
        # Fresh fixture record: only the 14 clean fps pass.
        rc, res = self._publish(self.pool44, self.record_path)
        self.assertEqual(rc, 0, res)
        published = self._published_fps()
        self.assertEqual(published, self.clean_fps)
        # All 14 published lines are pinned; the 7 failed pinned and
        # all 23 rotation lines are refused.
        self.assertTrue(published <= self.pinned_fps)
        self.assertEqual(len(published & self.pinned_fps), 14)

    def test_pinned_refused_when_stale(self):
        rc, res = self._publish(self.pool44, self.record_path,
                                now=self.now_stale)
        self.assertEqual(rc, 1)
        self.assertEqual(res.get("error"), "phone_gate_zero_qualified")
        self.assertIsNone(self._published_fps())

    def test_pinned_refused_when_failed(self):
        # Flip the 14 clean pinned fps to failed: nothing may publish,
        # even though the lines are pinned.
        rec = _make_record(self.pool44, set(), self.version_sha,
                           self.tested_at,
                           fail_fps=set(self.clean_fps))
        path = self._write_record(rec)
        rc, res = self._publish(self.pool44, path)
        self.assertEqual(rc, 1)
        self.assertEqual(res.get("error"), "phone_gate_zero_qualified")
        self.assertIsNone(self._published_fps())

    def test_pinned_refused_when_no_evidence_for_version(self):
        rec = _make_record(self.pool44, self.clean_fps, "0" * 64,
                           self.tested_at)
        path = self._write_record(rec)
        rc, res = self._publish(self.pool44, path)
        self.assertEqual(rc, 1)
        self.assertEqual(res.get("error"), "phone_gate_zero_qualified")
        self.assertIsNone(self._published_fps())

    def test_pinned_mixed_partial_admission(self):
        # 10 of the 14 clean pinned pass, 4 fail: exactly those 10
        # publish; the 4 failed pinned and all rotation refuse.
        keep = set(list(self.clean_fps)[:10])
        fail = self.clean_fps - keep
        rec = _make_record(self.pool44, keep, self.version_sha,
                           self.tested_at, fail_fps=fail)
        path = self._write_record(rec)
        rc, res = self._publish(self.pool44, path)
        self.assertEqual(rc, 0, res)
        published = self._published_fps()
        self.assertEqual(published, keep)
        self.assertTrue(published <= self.pinned_fps)

    def test_pinned_line_with_no_result_row_refused(self):
        # Record omits result rows for 5 pinned fps entirely: those 5
        # are refused (no evidence = fail closed); the other 9 publish.
        keep = set(list(self.clean_fps)[:9])
        omitted = self.clean_fps - keep
        rows = [r for r in _results(self.pool44, keep)
                if r["fingerprint"] not in omitted]
        rec = {"format": "native-results-v1",
               "runs": [_run(self.version_sha, self.tested_at, rows)]}
        path = self._write_record(rec)
        rc, res = self._publish(self.pool44, path)
        self.assertEqual(rc, 0, res)
        self.assertEqual(self._published_fps(), keep)

    def test_sync_refuses_ungated_pinned_source(self):
        # Legacy behaviour: a full 44-line file (21 pinned inside) with
        # no version-chain sidecar lands in publish/. Sync must refuse
        # and leave the served file untouched.
        publish_dir = os.path.join(self.workdir, "publish")
        served_dir = os.path.join(self.workdir, "served")
        os.makedirs(publish_dir, exist_ok=True)
        os.makedirs(served_dir, exist_ok=True)
        with open(os.path.join(publish_dir, "pool-new.txt"), "w") as f:
            f.write("\n".join(self.pool44) + "\n")
        with open(os.path.join(served_dir, "pool-new.txt"), "w") as f:
            f.write("\n".join(self.clean14) + "\n")
        before = file_manifest(os.path.join(served_dir, "pool-new.txt"))
        rc, res = run_sync(self.workdir, self.record_path,
                           probe_db=self.probe_db, now=self.now)
        self.assertEqual(rc, 1, res)
        after = file_manifest(os.path.join(served_dir, "pool-new.txt"))
        self.assertEqual(after["sha256"], before["sha256"])


if __name__ == "__main__":
    unittest.main()
