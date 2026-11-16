#!/usr/bin/env python3
"""D7 item-2 drill (Issue #73, GPT D6 review 6904538782, item 2).

GPT: legacy already renamed, but the post-write SHA fails, or
fsync / the process crashes -- verify the bridge + legacy final
state and the next-round repair strategy. bridge_sync is TWO
CONSECUTIVE atomic renames under one lock, NOT a true cross-file
atomic transaction: prove the failure state is detectable and
never returns a false success. No architecture rewrite.

Four injections (all deterministic, synthetic fixtures):

  A legacy post-rename SHA failure: the legacy file is corrupted
    just after its rename, before the post-write verify.
    Expect: rc=1 legacy_copy_failed, bridge rolled back to
    pre-run bytes, legacy holds corrupted bytes (SHA recorded),
    verify_targets CLI reports mismatch (rc=1); the NEXT run
    repairs the legacy target from the verified snapshot (rc=0,
    both targets clean14, verify_targets rc=0 consistent).
  B bridge post-rename SHA failure: the bridge file is corrupted
    just after its rename. Expect: rc=1 bridge_sha_mismatch,
    bridge restored to pre-run bytes, legacy untouched; next run
    repairs (rc=0, both clean14).
  C process crash between the two renames: a SUBPROCESS runs
    bridge_sync with a hook that raises right after the bridge
    rename verified (simulated crash). Expect: subprocess rc != 0,
    bridge holds the NEW snapshot bytes, legacy still holds its
    PRE-RUN bytes; verify_targets CLI flags legacy_sha_mismatch
    (rc=1); the next run repairs (rc=0, both clean14).
  D fsync failure on the legacy write: covered by the unit test
    tests/test_d7.py::test_legacy_fsync_failure, re-run here as a
    subprocess and recorded (mock os.fsync raises on the legacy
    tmp write; rc=1 legacy_copy_failed, bridge rolled back).

Scratch layout (tempdir, never production). All fixtures synthetic
(TEST-NET, password TEST-ONLY-NOT-A-REAL-NODE). Output is one JSON
object with a per-step file/SHA/rc/error table; --out writes it.
--code-root lets drills/d7_redgreen.py run this drill against the
D6 tree (expect failure: no new hooks / verify_targets) and the D7
tree (expect pass).

Usage: python3 drills/d7_item2_legacy_postwrite.py
       [--out docs/d7-item2-drill-log.json] [--code-root PATH]
Exit 0 = all checks pass. Stdout: one JSON object (the log).
"""
import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def _install_stubs():
    import types
    _crawler = types.ModuleType("pool.crawler")
    _crawler.AEAD_METHODS = ("aes-128-gcm", "aes-256-gcm",
                             "chacha20-poly1305")
    _crawler.parse_surge_line = lambda line: None
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


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=None)
    ap.add_argument("--code-root", default=HERE)
    args = ap.parse_args()
    code_root = os.path.abspath(args.code_root)
    sys.path.insert(0, code_root)
    _install_stubs()

    from pool.bridge_sync import run_bridge_sync, verify_targets  # noqa: E402
    from pool.phone_gate import fingerprint_of, parse_surge_line  # noqa: E402
    from pool.publish import run_publish  # noqa: E402
    from pool.recovery import OWNER_ACK_INIT, init_recovery_state  # noqa: E402
    from pool.sync import run_sync  # noqa: E402

    FIX = os.path.join(code_root, "fixtures")
    root = tempfile.mkdtemp(prefix="d7-item2-")
    steps = []
    checks = []

    def step(name, detail, **kw):
        rec = {"step": name, "detail": str(detail)}
        rec.update(kw)
        steps.append(rec)
        return rec

    def check(name, ok, detail=""):
        checks.append({"check": name, "ok": bool(ok), "detail": str(detail)})
        return bool(ok)

    def sha256_file(path):
        h = hashlib.sha256()
        with open(path, "rb") as f:
            for chunk in iter(lambda: f.read(65536), b""):
                h.update(chunk)
        return h.hexdigest()

    def sha_lines(lines):
        return hashlib.sha256(
            ("\n".join(lines) + "\n").encode("utf-8")).hexdigest()

    def read_lines(path):
        with open(path, encoding="utf-8") as f:
            return [l.rstrip("\n") for l in f if l.strip()]

    def write_lines(path, lines):
        with open(path, "w", encoding="utf-8") as f:
            f.write("\n".join(lines) + "\n")

    def fp_of_line(line):
        name, proto, host, port, params = parse_surge_line(line)
        return fingerprint_of(proto, host, port, params)

    def sha_of(path):
        return sha256_file(path)[:12] if os.path.exists(path) else ""

    def verify_cli(workdir, bridge, old_path):
        p = subprocess.run(
            [sys.executable, "-m", "pool.bridge_sync", "--verify-targets",
             "--workdir", workdir, "--bridge-dir", bridge,
             "--old-path", old_path],
            capture_output=True, text=True, cwd=code_root, timeout=60)
        try:
            return p.returncode, json.loads(p.stdout.strip() or "{}")
        except ValueError:
            return p.returncode, {"raw": p.stdout[:200] + p.stderr[:200]}

    try:
        pool44 = read_lines(os.path.join(FIX, "pool_44_fixture.txt"))
        clean14 = read_lines(os.path.join(FIX, "clean_14_fixture.txt"))
        clean_fps = {fp_of_line(l) for l in clean14}
        clean_sha = sha_lines(clean14)
        failed_lines = [l for l in pool44 if fp_of_line(l) not in clean_fps]
        polluted_sha = sha_lines(clean14 + [failed_lines[0]])
        old_version = [l for l in pool44 if l != failed_lines[0]]
        old_sha = sha_lines(old_version)
        record_path = os.path.join(FIX, "native_results_fixture.json")
        probe_db = os.path.join(FIX, "p0_fixture.db")
        record = json.load(open(record_path))
        version_sha = record["runs"][0]["version_sha"]
        now = record["runs"][0]["tested_at"] + 3600

        def seed(workdir):
            rc, out = init_recovery_state(workdir, OWNER_ACK_INIT)
            assert rc == 0, out
            rc, res = run_publish(
                workdir, clean14, record_path, version_sha,
                probe_db=probe_db, now=now,
                source_file=os.path.join(FIX, "pool_44_fixture.txt"))
            assert rc == 0, res
            rc, res = run_sync(workdir, record_path, version_sha,
                               probe_db=probe_db, now=now)
            assert rc == 0, res

        def fresh_bridge(seed_old=True):
            bdir = os.path.join(root, "bridge-%d" % fresh_bridge.n)
            fresh_bridge.n += 1
            os.makedirs(bdir, exist_ok=True)
            if seed_old:
                write_lines(bdir + "/pool-new.txt", old_version)
                write_lines(bdir + "/old-pool.txt", old_version)
            return bdir
        fresh_bridge.n = 0

        def bridge_sync(workdir, bridge, old_path, **kw):
            return run_bridge_sync(
                workdir, bridge, old_path=old_path,
                native_record_path=record_path, probe_db=probe_db,
                now=now, **kw)

        # ============ A: legacy post-rename SHA failure ============
        wd_a = os.path.join(root, "wd-a")
        os.makedirs(wd_a, exist_ok=True)
        seed(wd_a)
        bridge_a = fresh_bridge()
        old_a = os.path.join(bridge_a, "old-pool.txt")

        def _corrupt_legacy(path):
            with open(path, "a", encoding="utf-8") as f:
                f.write(failed_lines[0] + "\n")

        rc, res = bridge_sync(wd_a, bridge_a, old_a,
                              legacy_post_rename_hook=_corrupt_legacy)
        check("a_legacy_postrename_rc1",
              rc == 1 and res.get("error") == "legacy_copy_failed",
              "rc=%d error=%s" % (rc, res.get("error")))
        check("a_bridge_rolled_back",
              sha_of(bridge_a + "/pool-new.txt") == old_sha[:12]
              and res.get("bridge_rolled_back") is True,
              "bridge_sha=%s" % sha_of(bridge_a + "/pool-new.txt"))
        check("a_legacy_holds_corrupted_bytes",
              sha_of(old_a) == polluted_sha[:12],
              "legacy_sha=%s (polluted 15-line)" % sha_of(old_a))
        vrc, vt = verify_cli(wd_a, bridge_a, old_a)
        check("a_verify_targets_flags_mismatch",
              vrc == 1 and vt.get("consistent") is False,
              "rc=%d detail=%s" % (vrc, vt.get("detail")))
        step("A legacy post-rename SHA failure",
             "rc=1 legacy_copy_failed; bridge rolled back, legacy holds "
             "corrupted bytes, detector flags it",
             bridge_sha=sha_of(bridge_a + "/pool-new.txt"),
             legacy_sha=sha_of(old_a), rc=rc,
             error=res.get("error", ""))
        rc, res = bridge_sync(wd_a, bridge_a, old_a)
        check("a_next_run_repairs",
              rc == 0 and sha_of(bridge_a + "/pool-new.txt") == clean_sha[:12]
              and sha_of(old_a) == clean_sha[:12],
              "rc=%d bridge=%s legacy=%s"
              % (rc, sha_of(bridge_a + "/pool-new.txt"), sha_of(old_a)))
        vrc, vt = verify_cli(wd_a, bridge_a, old_a)
        check("a_verify_targets_consistent_after_repair",
              vrc == 0 and vt.get("consistent") is True,
              "rc=%d detail=%s" % (vrc, vt.get("detail")))
        step("A next run repairs",
             "rc=0, both targets clean14, verify_targets consistent",
             bridge_sha=sha_of(bridge_a + "/pool-new.txt"),
             legacy_sha=sha_of(old_a), rc=rc, error="")

        # ============ B: bridge post-rename SHA failure ============
        wd_b = os.path.join(root, "wd-b")
        os.makedirs(wd_b, exist_ok=True)
        seed(wd_b)
        bridge_b = fresh_bridge()
        old_b = os.path.join(bridge_b, "old-pool.txt")

        def _corrupt_bridge(path):
            with open(path, "a", encoding="utf-8") as f:
                f.write(failed_lines[0] + "\n")

        rc, res = bridge_sync(wd_b, bridge_b, old_b,
                              bridge_post_rename_hook=_corrupt_bridge)
        check("b_bridge_postrename_rc1",
              rc == 1 and res.get("error") == "bridge_sha_mismatch",
              "rc=%d error=%s" % (rc, res.get("error")))
        check("b_bridge_restored_legacy_untouched",
              sha_of(bridge_b + "/pool-new.txt") == old_sha[:12]
              and sha_of(old_b) == old_sha[:12],
              "bridge=%s legacy=%s"
              % (sha_of(bridge_b + "/pool-new.txt"), sha_of(old_b)))
        step("B bridge post-rename SHA failure",
             "rc=1 bridge_sha_mismatch; bridge restored, legacy untouched",
             bridge_sha=sha_of(bridge_b + "/pool-new.txt"),
             legacy_sha=sha_of(old_b), rc=rc,
             error=res.get("error", ""))
        rc, res = bridge_sync(wd_b, bridge_b, old_b)
        check("b_next_run_repairs",
              rc == 0 and sha_of(bridge_b + "/pool-new.txt") == clean_sha[:12]
              and sha_of(old_b) == clean_sha[:12],
              "rc=%d" % rc)

        # ============ C: crash between the two renames ============
        wd_c = os.path.join(root, "wd-c")
        os.makedirs(wd_c, exist_ok=True)
        seed(wd_c)
        bridge_c = fresh_bridge()
        old_c = os.path.join(bridge_c, "old-pool.txt")
        runner = os.path.join(root, "crash_runner.py")
        with open(runner, "w") as _f:
            _f.write(
                "import json, sys\n"
                "sys.path.insert(0, %r)\n" % code_root +
                "import types\n"
                "_crawler = types.ModuleType('pool.crawler')\n"
                "_crawler.AEAD_METHODS = ('aes-128-gcm', 'aes-256-gcm',"
                " 'chacha20-poly1305')\n"
                "_crawler.parse_surge_line = lambda line: None\n"
                "sys.modules['pool.crawler'] = _crawler\n"
                "_geo = types.ModuleType('pool.geo')\n"
                "_CN = {'US': ('\\u7f8e\\u56fd', '\\U0001f1fa\\U0001f1f8'),"
                " 'HK': ('\\u9999\\u6e2f', '\\U0001f1ed\\U0001f1f0'),"
                " 'IR': ('\\u4f0a\\u6717', '\\U0001f1ee\\U0001f1f7')}\n"
                "_geo.hint_to_code = lambda h: next((c for c, (n, f) in"
                " _CN.items() if n in (h or '')), '')\n"
                "_geo.display_name = lambda c, e='': _CN.get(c, ('\\u672a\\u77e5', ''))\n"
                "_geo.code_to_flag = lambda c: _CN.get(c, ('', ''))[1]\n"
                "_geo.is_cf_or_reserved = lambda h: False\n"
                "class _FakeIpApi:\n"
                "    def country(self, host):\n"
                "        return ('US', '')\n"
                "_geo.IpApi = _FakeIpApi\n"
                "sys.modules['pool.geo'] = _geo\n"
                "from pool.bridge_sync import run_bridge_sync\n"
                "cfg = json.load(open(sys.argv[1]))\n"
                "def _crash(_p):\n"
                "    raise RuntimeError('simulated crash between renames')\n"
                "run_bridge_sync(cfg['workdir'], cfg['bridge'],"
                " old_path=cfg['old'], native_record_path=cfg['record'],"
                " probe_db=cfg['probe_db'], now=cfg['now'],"
                " post_bridge_hook=_crash)\n")
        cfg_path = os.path.join(root, "crash_cfg.json")
        with open(cfg_path, "w") as _f:
            json.dump({"workdir": wd_c, "bridge": bridge_c, "old": old_c,
                       "record": record_path, "probe_db": probe_db,
                       "now": now}, _f)
        p = subprocess.run([sys.executable, runner, cfg_path],
                           capture_output=True, text=True, cwd=code_root,
                           timeout=120)
        check("c_crash_subprocess_dies_nonzero",
              p.returncode != 0 and "simulated crash" in p.stderr,
              "rc=%d stderr_tail=%s"
              % (p.returncode, p.stderr.strip().splitlines()[-1][:120]
                 if p.stderr.strip() else ""))
        check("c_final_state_bridge_new_legacy_old",
              sha_of(bridge_c + "/pool-new.txt") == clean_sha[:12]
              and sha_of(old_c) == old_sha[:12],
              "bridge=%s legacy=%s"
              % (sha_of(bridge_c + "/pool-new.txt"), sha_of(old_c)))
        vrc, vt = verify_cli(wd_c, bridge_c, old_c)
        check("c_verify_targets_flags_legacy_mismatch",
              vrc == 1 and vt.get("consistent") is False
              and vt.get("detail") == "legacy_sha_mismatch"
              and vt.get("bridge_sha") == clean_sha
              and vt.get("legacy_sha") == old_sha,
              "rc=%d detail=%s" % (vrc, vt.get("detail")))
        step("C crash between renames",
             "subprocess died after bridge rename; bridge=new snapshot, "
             "legacy=pre-run bytes; detector flags legacy_sha_mismatch",
             bridge_sha=sha_of(bridge_c + "/pool-new.txt"),
             legacy_sha=sha_of(old_c), rc=p.returncode,
             error="simulated crash")
        rc, res = bridge_sync(wd_c, bridge_c, old_c)
        check("c_next_run_repairs_lock_free",
              rc == 0 and sha_of(bridge_c + "/pool-new.txt") == clean_sha[:12]
              and sha_of(old_c) == clean_sha[:12],
              "rc=%d (lock acquirable after crash)" % rc)
        vrc, vt = verify_cli(wd_c, bridge_c, old_c)
        check("c_verify_targets_consistent_after_repair",
              vrc == 0 and vt.get("consistent") is True,
              "rc=%d" % vrc)

        # ============ D: fsync failure (unit test, subprocess) ============
        p = subprocess.run(
            [sys.executable, "-m", "unittest",
             "tests.test_d7.TestItem2PostRename.test_legacy_fsync_failure",
             "-v"],
            capture_output=True, text=True, cwd=code_root, timeout=120)
        check("d_fsync_failure_unit_test_passes",
              p.returncode == 0 and "OK" in (p.stderr + p.stdout),
              "rc=%d tail=%s" % (p.returncode,
                                 (p.stderr + p.stdout).strip()
                                 .splitlines()[-1][:120]
                                 if (p.stderr + p.stdout).strip() else ""))
        step("D fsync failure on legacy write",
             "unit test (mock os.fsync raises on legacy tmp write): "
             "rc=1 legacy_copy_failed, bridge rolled back; next run ok",
             rc=p.returncode, error="")

        ok = all(c["ok"] for c in checks)
        log = {"drill": "d7_item2_legacy_postwrite",
               "code_root": code_root,
               "sha": {"clean14": clean_sha[:12],
                       "old_version": old_sha[:12],
                       "polluted": polluted_sha[:12]},
               "steps": steps, "checks": checks,
               "passed": sum(1 for c in checks if c["ok"]),
               "total": len(checks), "ok": ok}
        print(json.dumps(log, indent=1, ensure_ascii=False))
        if args.out:
            with open(args.out, "w", encoding="utf-8") as f:
                json.dump(log, f, indent=1, ensure_ascii=False)
        return 0 if ok else 1
    finally:
        shutil.rmtree(root, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
