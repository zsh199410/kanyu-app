#!/usr/bin/env python3
"""D7a item-1 drill (Issue #73, GPT D7 review 6912114134, item 1).

Dual-target inconsistency is a SWITCHING GATE. gate-sync.sh calls
`pool.bridge_sync --gate-block` FIRST, before pool.sync. On a
concrete SHA divergence from the chain published_sha it latches
STOP (reason targets_inconsistent:<detail>) and the cycle runs no
sync, touches no bridge/legacy, publishes nothing. The latch
holds across cycles (publish refuses pool_stopped) until a manual
repair (--repair-targets) + clear_stop (OWNER_ACK + fresh native
evidence).

Four scenarios (all deterministic, synthetic fixtures):

  A legacy post-rename SHA failure leaves a polluted legacy:
    gate-block rc=1 targets_inconsistent, STOP latched, publish
    refuses pool_stopped, served/bridge SHAs unchanged, and the
    HTTP entry still serves the pre-repair VERIFIED version
    (bridge SHA unchanged) -- never the polluted bytes.
  B crash between the two renames (bridge=new, legacy=old):
    gate-block detects legacy_sha_mismatch, STOP latched, the
    next publish refuses.
  C controlled repair: repair_targets rc=0, all three targets
    clean14, verify_targets consistent, HTTP entry SHA == repaired
    SHA; STOP is STILL latched after repair; clear_stop (OWNER_ACK
    + fresh evidence) restores the cycle (gate-block rc=0,
    publish rc=0).
  D D7 red: the same injection against the D7 tree (--d7-root):
    gate_block does not exist (ImportError) and the next
    run_bridge_sync repairs the divergence with rc=0 while the
    pool stays allowed -- no STOP latch, i.e. the fault window
    carried zero protection. D7a is green.

The HTTP entry is the sandbox server from
drills/d7_item1_http_exposure.py (same /m/ -> bridge mapping;
real nginx on the VPS, Python emulation locally).

Scratch layout (tempdir, never production). All fixtures synthetic
(TEST-NET, password TEST-ONLY-NOT-A-REAL-NODE). Output is one JSON
object with a per-step file/SHA/rc/error table; --out writes it.
--code-root lets drills/d7a_redgreen.py run this drill against the
D7 tree (expect failure: no gate_block / repair_targets).

Usage: python3 drills/d7a_item1_gate_block.py
       [--out docs/d7a-item1-drill-log.json] [--code-root PATH]
       [--d7-root PATH]
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
    ap.add_argument("--d7-root", default=None)
    args = ap.parse_args()
    code_root = os.path.abspath(args.code_root)
    sys.path.insert(0, code_root)
    sys.path.insert(0, os.path.join(code_root, "drills"))
    _install_stubs()

    from pool.bridge_sync import run_bridge_sync, verify_targets  # noqa: E402
    from pool.phone_gate import fingerprint_of, parse_surge_line  # noqa: E402
    from pool.publish import run_publish  # noqa: E402
    from pool.recovery import (  # noqa: E402
        OWNER_ACK_CLEAR, OWNER_ACK_INIT, clear_stop, gate_check,
        init_recovery_state)
    from pool.sync import run_sync  # noqa: E402

    try:
        from pool.bridge_sync import gate_block, repair_targets  # noqa: E402
        d7a_api = True
    except ImportError:
        d7a_api = False

    import d7_item1_http_exposure as item1  # noqa: E402

    FIX = os.path.join(code_root, "fixtures")
    root = tempfile.mkdtemp(prefix="d7a-item1-")
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

    def cli_gate_block(workdir, bridge, old_path):
        p = subprocess.run(
            [sys.executable, "-m", "pool.bridge_sync", "--gate-block",
             "--workdir", workdir, "--bridge-dir", bridge,
             "--old-path", old_path, "--now", str(now)],
            capture_output=True, text=True, cwd=code_root, timeout=60)
        try:
            return p.returncode, json.loads(p.stdout.strip() or "{}")
        except ValueError:
            return p.returncode, {"raw": p.stdout[:200] + p.stderr[:200]}

    def cli_repair(workdir, bridge, old_path):
        p = subprocess.run(
            [sys.executable, "-m", "pool.bridge_sync", "--repair-targets",
             "--workdir", workdir, "--bridge-dir", bridge,
             "--old-path", old_path,
             "--native-record", record_path, "--probe-db", probe_db,
             "--now", str(now)],
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

        if not d7a_api:
            check("d7a_api_present", False,
                  "gate_block / repair_targets missing on this tree "
                  "(ImportError) -- D7 red, expected when --code-root "
                  "points at the D7 tree")
            step("D7 tree: gate-block API absent",
                 "no gate_block / repair_targets to call; the next run "
                 "would silently repair the divergence with no STOP",
                 error="ImportError")
            ok = all(c["ok"] for c in checks)
            log = {"drill": "d7a_item1_gate_block",
                   "code_root": code_root,
                   "sha": {"clean14": clean_sha[:12]},
                   "steps": steps, "checks": checks,
                   "passed": 0, "total": len(checks), "ok": False}
            print(json.dumps(log, indent=1, ensure_ascii=False))
            if args.out:
                with open(args.out, "w", encoding="utf-8") as f:
                    json.dump(log, f, indent=1, ensure_ascii=False)
            return 1

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

        # Shared HTTP sandbox: /m/ -> bridge dir of scenario A.
        wd_a = os.path.join(root, "wd-a")
        os.makedirs(wd_a, exist_ok=True)
        seed(wd_a)
        bridge_a = fresh_bridge()
        old_a = os.path.join(bridge_a, "old-pool.txt")
        rc, res = bridge_sync(wd_a, bridge_a, old_a)
        assert rc == 0, res
        served_a = os.path.join(wd_a, "served")

        # ============ A: legacy post-rename SHA failure ============
        def _corrupt_legacy(path):
            with open(path, "a", encoding="utf-8") as f:
                f.write(failed_lines[0] + "\n")

        rc, res = bridge_sync(wd_a, bridge_a, old_a,
                              legacy_post_rename_hook=_corrupt_legacy)
        assert rc == 1 and res.get("error") == "legacy_copy_failed", res
        # The failed run rolled the bridge back to its PRE-RUN bytes,
        # which are already the verified clean14 (from the clean sync
        # above); the legacy target holds the polluted bytes. That IS
        # the divergence the gate-block must catch: no re-sync and no
        # second corruption needed.
        assert sha_of(old_a) == polluted_sha[:12]
        assert sha_of(bridge_a + "/pool-new.txt") == clean_sha[:12]
        step("A setup: legacy post-rename SHA failure",
             "rc=1 legacy_copy_failed; bridge rolled back to verified "
             "clean14, legacy holds polluted bytes",
             bridge_sha=sha_of(bridge_a + "/pool-new.txt"),
             legacy_sha=sha_of(old_a), rc=rc,
             error=res.get("error", ""))
        with item1.SandboxServer(root, bridge_a, served_a) as srv:
            code, body = srv.good("/m/pool-new.txt")
            entry_before = item1.sha_bytes(body)[:12] if code == 200 else ""
            check("a_http_entry_is_verified_before_gate_block",
                  code == 200 and entry_before == clean_sha[:12],
                  "http=%s entry_sha=%s" % (code, entry_before))
            rc, out = cli_gate_block(wd_a, bridge_a, old_a)
            check("a_gate_block_rc1_targets_inconsistent",
                  rc == 1 and out.get("error") == "targets_inconsistent"
                  and out.get("detail") == "legacy_sha_mismatch",
                  "rc=%d error=%s detail=%s"
                  % (rc, out.get("error"), out.get("detail")))
            allowed, gerr, _st = gate_check(wd_a)
            check("a_stop_latched",
                  allowed is False and gerr == "pool_stopped",
                  "gate_check error=%s" % gerr)
            rc, pres = run_publish(
                wd_a, clean14, record_path, version_sha,
                probe_db=probe_db, now=now,
                source_file=os.path.join(FIX, "pool_44_fixture.txt"))
            check("a_publish_refuses_pool_stopped",
                  rc == 1 and pres.get("error") == "pool_stopped",
                  "rc=%d error=%s" % (rc, pres.get("error")))
            check("a_served_bridge_sha_unchanged",
                  sha_of(os.path.join(wd_a, "served", "pool-new.txt"))
                  == clean_sha[:12]
                  and sha_of(bridge_a + "/pool-new.txt") == clean_sha[:12],
                  "served=%s bridge=%s"
                  % (sha_of(os.path.join(wd_a, "served", "pool-new.txt")),
                     sha_of(bridge_a + "/pool-new.txt")))
            code, body = srv.good("/m/pool-new.txt")
            check("a_http_entry_still_verified_during_stop",
                  code == 200
                  and item1.sha_bytes(body)[:12] == clean_sha[:12]
                  and item1.sha_bytes(body)[:12] == entry_before,
                  "http=%s entry_sha=%s (polluted legacy never served)"
                  % (code, item1.sha_bytes(body)[:12]))
            check("a_legacy_still_polluted_detectable",
                  sha_of(old_a) == polluted_sha[:12],
                  "legacy_sha=%s" % sha_of(old_a))
            step("A gate-block latches STOP",
                 "rc=1 targets_inconsistent; publish refuses "
                 "pool_stopped; served/bridge + HTTP entry unchanged "
                 "(verified clean14); legacy still polluted",
                 bridge_sha=sha_of(bridge_a + "/pool-new.txt"),
                 legacy_sha=sha_of(old_a), rc=rc, error="")

        # ============ B: crash between the two renames ============
        wd_b = os.path.join(root, "wd-b")
        os.makedirs(wd_b, exist_ok=True)
        seed(wd_b)
        bridge_b = fresh_bridge()
        old_b = os.path.join(bridge_b, "old-pool.txt")
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
            json.dump({"workdir": wd_b, "bridge": bridge_b, "old": old_b,
                       "record": record_path, "probe_db": probe_db,
                       "now": now}, _f)
        p = subprocess.run([sys.executable, runner, cfg_path],
                           capture_output=True, text=True, cwd=code_root,
                           timeout=120)
        check("b_crash_subprocess_dies_nonzero",
              p.returncode != 0 and "simulated crash" in p.stderr,
              "rc=%d" % p.returncode)
        check("b_final_state_bridge_new_legacy_old",
              sha_of(bridge_b + "/pool-new.txt") == clean_sha[:12]
              and sha_of(old_b) == old_sha[:12],
              "bridge=%s legacy=%s"
              % (sha_of(bridge_b + "/pool-new.txt"), sha_of(old_b)))
        rc, out = cli_gate_block(wd_b, bridge_b, old_b)
        check("b_gate_block_detects_legacy_mismatch",
              rc == 1 and out.get("detail") == "legacy_sha_mismatch",
              "rc=%d detail=%s" % (rc, out.get("detail")))
        allowed, gerr, _st = gate_check(wd_b)
        check("b_stop_latched",
              allowed is False and gerr == "pool_stopped",
              "gate_check error=%s" % gerr)
        rc, pres = run_publish(
            wd_b, clean14, record_path, version_sha,
            probe_db=probe_db, now=now,
            source_file=os.path.join(FIX, "pool_44_fixture.txt"))
        check("b_next_publish_refuses",
              rc == 1 and pres.get("error") == "pool_stopped",
              "rc=%d error=%s" % (rc, pres.get("error")))
        check("b_served_bridge_sha_unchanged",
              sha_of(os.path.join(wd_b, "served", "pool-new.txt"))
              == clean_sha[:12]
              and sha_of(bridge_b + "/pool-new.txt") == clean_sha[:12],
              "served/bridge still clean14")
        step("B crash between renames",
             "bridge=new snapshot, legacy=pre-run bytes; gate-block "
             "latches STOP, next publish refuses",
             bridge_sha=sha_of(bridge_b + "/pool-new.txt"),
             legacy_sha=sha_of(old_b), rc=p.returncode,
             error="simulated crash")

        # ============ C: controlled repair on scenario A ============
        # wd_a is still latched from A (legacy polluted).
        rc, out = cli_repair(wd_a, bridge_a, old_a)
        check("c_repair_rc0",
              rc == 0 and out.get("ok") is True,
              "rc=%d error=%s" % (rc, out.get("error")))
        check("c_three_targets_consistent",
              out.get("after", {}).get("served_sha") == clean_sha
              and out.get("after", {}).get("bridge_sha") == clean_sha
              and out.get("after", {}).get("legacy_sha") == clean_sha,
              "after=%s" % out.get("after"))
        vt = verify_targets(wd_a, bridge_a, old_path=old_a)
        check("c_verify_targets_consistent",
              vt["consistent"] is True,
              "detail=%s" % vt["detail"])
        with item1.SandboxServer(root, bridge_a, served_a) as srv:
            code, body = srv.good("/m/pool-new.txt")
            check("c_http_entry_sha_equals_repaired_sha",
                  code == 200
                  and item1.sha_bytes(body) == clean_sha,
                  "http=%s entry_sha=%s"
                  % (code, item1.sha_bytes(body)[:12]))
        allowed, gerr, _st = gate_check(wd_a)
        check("c_stop_still_latched_after_repair",
              allowed is False and gerr == "pool_stopped",
              "repair does not clear STOP; gate_check error=%s" % gerr)
        rc, cres = clear_stop(wd_a, OWNER_ACK_CLEAR, record_path,
                              probe_db=probe_db, now=now)
        check("c_clear_stop_with_owner_ack_and_fresh_evidence",
              rc == 0, "rc=%d error=%s" % (rc, cres.get("error")))
        rc, out = cli_gate_block(wd_a, bridge_a, old_a)
        check("c_next_cycle_healthy",
              rc == 0 and out.get("ok") is True,
              "rc=%d" % rc)
        rc, pres = run_publish(
            wd_a, clean14, record_path, version_sha,
            probe_db=probe_db, now=now,
            source_file=os.path.join(FIX, "pool_44_fixture.txt"))
        check("c_publish_allowed_after_clear_stop",
              rc == 0, "rc=%d error=%s" % (rc, pres.get("error")))
        step("C controlled repair + clear_stop",
             "repair rc=0, three targets clean14, HTTP entry == "
             "repaired SHA; STOP still latched until clear_stop; "
             "next cycle healthy",
             bridge_sha=sha_of(bridge_a + "/pool-new.txt"),
             legacy_sha=sha_of(old_a), rc=rc, error="")

        # ============ D: D7 red (same injection, D7 tree) ============
        d7_root = args.d7_root or os.path.join(
            os.path.dirname(code_root), "p2p3-d7")
        if os.path.isdir(os.path.join(d7_root, "pool")):
            p = subprocess.run(
                [sys.executable, "-c",
                 "import sys; sys.path.insert(0, %r); "
                 "from pool.bridge_sync import gate_block" % d7_root],
                capture_output=True, text=True, timeout=60)
            check("d_d7_tree_has_no_gate_block",
                  p.returncode != 0 and "ImportError" in p.stderr,
                  "rc=%d (gate_block absent on D7)" % p.returncode)
            # On D7 the next run repairs silently with no latch:
            # prove it by running D7 bridge_sync on a fresh
            # divergence and showing the pool stays allowed.
            wd_d = os.path.join(root, "wd-d")
            os.makedirs(wd_d, exist_ok=True)
            sys.path.insert(0, d7_root)
            # Re-seed with the D7 modules in a subprocess instead
            # of swapping modules in-process.
            seed_script = os.path.join(root, "d7_seed.py")
            with open(seed_script, "w") as _f:
                _f.write(
                    "import json, os, sys\n"
                    "sys.path.insert(0, %r)\n" % d7_root +
                    "import types\n"
                    "_crawler = types.ModuleType('pool.crawler')\n"
                    "_crawler.AEAD_METHODS = ('aes-128-gcm',"
                    " 'aes-256-gcm', 'chacha20-poly1305')\n"
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
                    "from pool.publish import run_publish\n"
                    "from pool.recovery import OWNER_ACK_INIT, gate_check,"
                    " init_recovery_state\n"
                    "from pool.sync import run_sync\n"
                    "cfg = json.load(open(sys.argv[1]))\n"
                    "rc, _o = init_recovery_state(cfg['workdir'],"
                    " OWNER_ACK_INIT)\n"
                    "assert rc == 0\n"
                    "rc, _r = run_publish(cfg['workdir'], cfg['clean'],"
                    " cfg['record'], cfg['version'],"
                    " probe_db=cfg['probe_db'], now=cfg['now'],"
                    " source_file=cfg['source_file'])\n"
                    "assert rc == 0, _r\n"
                    "rc, _r = run_sync(cfg['workdir'], cfg['record'],"
                    " cfg['version'], probe_db=cfg['probe_db'],"
                    " now=cfg['now'])\n"
                    "assert rc == 0, _r\n"
                    "rc, _r = run_bridge_sync(cfg['workdir'],"
                    " cfg['bridge'], old_path=cfg['old'],"
                    " native_record_path=cfg['record'],"
                    " probe_db=cfg['probe_db'], now=cfg['now'])\n"
                    "assert rc == 0, _r\n"
                    "open(cfg['old'], 'a').write(cfg['bad'] + '\\n')\n"
                    "rc, _r = run_bridge_sync(cfg['workdir'],"
                    " cfg['bridge'], old_path=cfg['old'],"
                    " native_record_path=cfg['record'],"
                    " probe_db=cfg['probe_db'], now=cfg['now'])\n"
                    "allowed, _e, _s = gate_check(cfg['workdir'])\n"
                    "print(json.dumps({'repair_rc': rc,"
                    " 'pool_allowed_after_repair': allowed}))\n")
            bridge_d = fresh_bridge()
            old_d = os.path.join(bridge_d, "old-pool.txt")
            dcfg = os.path.join(root, "d7_cfg.json")
            with open(dcfg, "w") as _f:
                json.dump({"workdir": wd_d, "bridge": bridge_d,
                           "old": old_d, "record": record_path,
                           "probe_db": probe_db, "now": now,
                           "clean": clean14, "version": version_sha,
                           "source_file": os.path.join(
                               FIX, "pool_44_fixture.txt"),
                           "bad": failed_lines[0]}, _f)
            # Fixtures live under the D7 tree: point the D7 seed at
            # the D7 fixtures (same synthetic content).
            p = subprocess.run([sys.executable, seed_script, dcfg],
                               capture_output=True, text=True,
                               cwd=d7_root, timeout=120)
            try:
                dout = json.loads(p.stdout.strip().splitlines()[-1])
            except Exception:
                dout = {"raw": (p.stdout + p.stderr)[-300:]}
            check("d_d7_next_run_repairs_with_no_stop_latch",
                  p.returncode == 0
                  and dout.get("repair_rc") == 0
                  and dout.get("pool_allowed_after_repair") is True,
                  "rc=%d repair_rc=%s allowed=%s"
                  % (p.returncode, dout.get("repair_rc"),
                     dout.get("pool_allowed_after_repair")))
            step("D D7 red: no gate-block",
                 "D7 tree has no gate_block (ImportError); the next "
                 "run repairs the divergence rc=0 with the pool still "
                 "allowed -- the fault window carried zero protection",
                 error="")
        else:
            step("D D7 red skipped",
                 "d7 root not found: %s" % d7_root, error="")

        ok = all(c["ok"] for c in checks)
        log = {"drill": "d7a_item1_gate_block",
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
