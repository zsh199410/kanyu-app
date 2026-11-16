#!/usr/bin/env python3
"""D7a STOP-latch cross-cycle drill (Issue #73, GPT D7 review
6912114134, item 4 -- pre-launch acceptance, "at least consecutive
cross-cycle gate / refuse / rollback evidence").

A 5-cycle :07 (gate-publish) / :15 (gate-sync + bridge) sequence
with a latched STOP in the middle, on synthetic fixtures:

  C1 :07 publish v1 -> :15 sync + bridge: healthy, served /
     bridge / legacy all clean14.
  C2 :07 publish v1 -> :15 sync + bridge: healthy again
     (idempotent re-run).
  C3 inject a legacy divergence (polluted legacy) -> :15
     gate-block rc=1 targets_inconsistent, STOP latched; the NEXT
     :07 publish refuses pool_stopped; the NEXT :15 gate-block
     refuses again and sync refuses pool_stopped; served / bridge
     SHAs are unchanged through the whole latched window, and the
     HTTP entry keeps serving the last verified version.
  C4 controlled repair (repair_targets rc=0, verify_targets
     consistent, HTTP entry SHA == repaired SHA) + HTTP recheck
     green -> clear_stop (OWNER_ACK + fresh evidence) -> :07
     publish rc=0, :15 gate-block rc=0 + sync + bridge rc=0.
  C5 :07 publish -> :15 sync + bridge: healthy, proving the
     cycle is stable after recovery.

The STOP latch is the point: a divergence does not get silently
repaired by the next run; every later cycle refuses until a manual
repair + owner-acknowledged clear. The HTTP entry is the sandbox
server from drills/d7_item1_http_exposure.py (same /m/ -> bridge
mapping; real nginx on the VPS, Python emulation locally).

Scratch layout (tempdir, never production). All fixtures synthetic
(TEST-NET, password TEST-ONLY-NOT-A-REAL-NODE). Output is one JSON
object; --out writes it.

Usage: python3 drills/d7a_cycles_latch.py
       [--out docs/d7a-cycles-latch-log.json]
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
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "drills"))

import types  # noqa: E402

_crawler = types.ModuleType("pool.crawler")
_crawler.AEAD_METHODS = ("aes-128-gcm", "aes-256-gcm", "chacha20-poly1305")
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

from pool.bridge_sync import (  # noqa: E402
    gate_block, repair_targets, run_bridge_sync, verify_targets)
from pool.phone_gate import fingerprint_of, parse_surge_line  # noqa: E402
from pool.publish import run_publish  # noqa: E402
from pool.recovery import (  # noqa: E402
    OWNER_ACK_CLEAR, OWNER_ACK_INIT, clear_stop, gate_check,
    init_recovery_state)
from pool.sync import run_sync  # noqa: E402

import d7_item1_http_exposure as item1  # noqa: E402
import tools.http_recheck as hr  # noqa: E402

FIX = os.path.join(HERE, "fixtures")


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


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=None)
    args = ap.parse_args()
    root = tempfile.mkdtemp(prefix="d7a-cycles-")
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

    def sha_of(path):
        return _sha_file(path)[:12] if os.path.exists(path) else ""

    try:
        pool44 = _read_lines(os.path.join(FIX, "pool_44_fixture.txt"))
        clean14 = _read_lines(os.path.join(FIX, "clean_14_fixture.txt"))
        clean_fps = {_fp_of(l) for l in clean14}
        clean_sha = _sha_lines(clean14)
        failed_lines = [l for l in pool44 if _fp_of(l) not in clean_fps]
        polluted_sha = _sha_lines(clean14 + [failed_lines[0]])
        old_version = [l for l in pool44 if l != failed_lines[0]]
        record_path = os.path.join(FIX, "native_results_fixture.json")
        probe_db = os.path.join(FIX, "p0_fixture.db")
        record = json.load(open(record_path))
        version_sha = record["runs"][0]["version_sha"]
        now = record["runs"][0]["tested_at"] + 3600
        pool44_path = os.path.join(FIX, "pool_44_fixture.txt")

        workdir = os.path.join(root, "wd")
        os.makedirs(workdir, exist_ok=True)
        rc, out = init_recovery_state(workdir, OWNER_ACK_INIT)
        assert rc == 0, out
        bridge = os.path.join(root, "bridge")
        os.makedirs(bridge, exist_ok=True)
        _write_lines(bridge + "/pool-new.txt", old_version)
        _write_lines(bridge + "/old-pool.txt", old_version)
        old_path = os.path.join(bridge, "old-pool.txt")
        served_file = os.path.join(workdir, "served", "pool-new.txt")
        served_dir = os.path.join(workdir, "served")

        def publish_07():
            return run_publish(workdir, clean14, record_path, version_sha,
                               probe_db=probe_db, now=now,
                               source_file=pool44_path)

        def sync_15():
            rc1, res1 = run_sync(workdir, record_path, version_sha,
                                 probe_db=probe_db, now=now)
            if rc1 != 0:
                return rc1, res1, None
            rc2, res2 = run_bridge_sync(
                workdir, bridge, old_path=old_path,
                native_record_path=record_path, probe_db=probe_db, now=now)
            return rc2, res2, res1

        def gate_block_15():
            return gate_block(workdir, bridge, old_path=old_path, now=now)

        # ---- C1: healthy cycle ----
        rc, res = publish_07()
        check("c1_07_publish_rc0", rc == 0, "rc=%d" % rc)
        rc, res, _ = sync_15()
        check("c1_15_sync_bridge_rc0", rc == 0, "rc=%d" % rc)
        check("c1_all_targets_clean14",
              sha_of(served_file) == clean_sha[:12]
              and sha_of(bridge + "/pool-new.txt") == clean_sha[:12]
              and sha_of(old_path) == clean_sha[:12],
              "served=%s bridge=%s legacy=%s"
              % (sha_of(served_file),
                 sha_of(bridge + "/pool-new.txt"), sha_of(old_path)))
        step("C1 healthy cycle",
             ":07 publish rc=0, :15 sync+bridge rc=0, all targets "
             "clean14", error="")

        # ---- C2: healthy again ----
        rc, res = publish_07()
        check("c2_07_publish_rc0", rc == 0, "rc=%d" % rc)
        rc, res, _ = sync_15()
        check("c2_15_sync_bridge_rc0", rc == 0, "rc=%d" % rc)
        step("C2 healthy again",
             "second consecutive cycle healthy (idempotent)", error="")

        # ---- C3: inject divergence, latch STOP ----
        with open(old_path, "a", encoding="utf-8") as f:
            f.write(failed_lines[0] + "\n")
        assert sha_of(old_path) == polluted_sha[:12]
        latched_served = sha_of(served_file)
        latched_bridge = sha_of(bridge + "/pool-new.txt")
        with item1.SandboxServer(root, bridge, served_dir) as srv:
            code, body = srv.good("/m/pool-new.txt")
            entry_latched = item1.sha_bytes(body)[:12] if code == 200 else ""
            check("c3_http_entry_verified_at_latch",
                  code == 200 and entry_latched == clean_sha[:12],
                  "http=%s entry_sha=%s" % (code, entry_latched))
            rc, out = gate_block_15()
            check("c3_15_gate_block_rc1",
                  rc == 1 and out.get("error") == "targets_inconsistent",
                  "rc=%d error=%s detail=%s"
                  % (rc, out.get("error"), out.get("detail")))
            allowed, gerr, _st = gate_check(workdir)
            check("c3_stop_latched",
                  allowed is False and gerr == "pool_stopped",
                  "gate_check error=%s" % gerr)
            # Next :07 publish refuses.
            rc, pres = publish_07()
            check("c3_next_07_publish_refuses",
                  rc == 1 and pres.get("error") == "pool_stopped",
                  "rc=%d error=%s" % (rc, pres.get("error")))
            # Next :15 gate-block refuses again, sync refuses too.
            rc, out = gate_block_15()
            check("c3_next_15_gate_block_refuses_again",
                  rc == 1 and out.get("error") == "targets_inconsistent",
                  "rc=%d" % rc)
            rc, sres = run_sync(workdir, record_path, version_sha,
                                probe_db=probe_db, now=now)
            check("c3_next_15_sync_refuses_pool_stopped",
                  rc == 1 and sres.get("error") == "pool_stopped",
                  "rc=%d error=%s" % (rc, sres.get("error")))
            check("c3_served_bridge_sha_unchanged_through_latch",
                  sha_of(served_file) == latched_served
                  and sha_of(bridge + "/pool-new.txt") == latched_bridge
                  and latched_served == clean_sha[:12]
                  and latched_bridge == clean_sha[:12],
                  "served=%s bridge=%s"
                  % (sha_of(served_file),
                     sha_of(bridge + "/pool-new.txt")))
            code, body = srv.good("/m/pool-new.txt")
            check("c3_http_entry_still_verified_during_stop",
                  code == 200
                  and item1.sha_bytes(body)[:12] == clean_sha[:12],
                  "http=%s entry_sha=%s"
                  % (code, item1.sha_bytes(body)[:12]))
            step("C3 STOP latched across cycles",
                 "gate-block rc=1, next :07 refuses pool_stopped, next "
                 ":15 refuses again; served/bridge + HTTP entry "
                 "unchanged (verified clean14)",
                 bridge_sha=sha_of(bridge + "/pool-new.txt"),
                 legacy_sha=sha_of(old_path), error="")

        # ---- C4: repair + HTTP recheck + clear_stop ----
        rc, res = repair_targets(
            workdir, bridge, old_path=old_path,
            native_record_path=record_path, probe_db=probe_db, now=now)
        check("c4_repair_rc0", rc == 0, "rc=%d error=%s"
              % (rc, res.get("error")))
        vt = verify_targets(workdir, bridge, old_path=old_path)
        check("c4_verify_targets_consistent",
              vt["consistent"] is True, "detail=%s" % vt["detail"])
        # HTTP recheck (in-process): good-only config + entry == repaired.
        good_conf = ("events { worker_connections 16; }\nhttp {\n"
                     "  access_log off;\n  server {\n"
                     "    listen 127.0.0.1:18091;\n"
                     "    location /m/ { alias %s/; default_type "
                     "text/plain; }\n    location / { return 404; }\n"
                     "  }\n}\n" % bridge)
        conf_path = os.path.join(root, "good.conf")
        with open(conf_path, "w") as f:
            f.write(good_conf)
        qname = "pool-new-20261116-000000-abcdef123456.txt"
        os.makedirs(os.path.join(served_dir, ".quarantine"), exist_ok=True)
        _write_lines(os.path.join(served_dir, ".quarantine", qname),
                     clean14 + [failed_lines[0]])
        with item1.SandboxServer(root, bridge, served_dir) as srv:
            p = subprocess.run(
                [sys.executable, os.path.join(HERE, "tools",
                                              "http_recheck.py"),
                 "--config-dump", conf_path,
                 "--entry-url", "http://127.0.0.1:18091/m/pool-new.txt",
                 "--expected-sha", clean_sha,
                 "--bridge-file", bridge + "/pool-new.txt",
                 "--legacy-file", old_path,
                 "--served-file", served_file,
                 "--quarantine-name", qname],
                capture_output=True, text=True, cwd=HERE, timeout=120)
            try:
                rout = json.loads(p.stdout.strip() or "{}")
            except ValueError:
                rout = {"raw": (p.stdout + p.stderr)[:300]}
            check("c4_http_recheck_green_after_repair",
                  p.returncode == 0 and rout.get("ok") is True,
                  "rc=%d ok=%s" % (p.returncode, rout.get("ok")))
        allowed, gerr, _st = gate_check(workdir)
        check("c4_stop_still_latched_before_clear",
              allowed is False and gerr == "pool_stopped",
              "repair alone does not clear STOP")
        rc, cres = clear_stop(workdir, OWNER_ACK_CLEAR, record_path,
                              probe_db=probe_db, now=now)
        check("c4_clear_stop_rc0", rc == 0,
              "rc=%d error=%s" % (rc, cres.get("error")))
        rc, res = publish_07()
        check("c4_07_publish_rc0_after_clear", rc == 0, "rc=%d" % rc)
        rc, out = gate_block_15()
        check("c4_15_gate_block_rc0_after_clear",
              rc == 0 and out.get("ok") is True, "rc=%d" % rc)
        rc, res, _ = sync_15()
        check("c4_15_sync_bridge_rc0_after_clear", rc == 0, "rc=%d" % rc)
        step("C4 repair + recheck + clear_stop",
             "repair rc=0, HTTP recheck green, STOP still latched "
             "until clear_stop; cycle healthy again", error="")

        # ---- C5: stable healthy cycle ----
        rc, res = publish_07()
        check("c5_07_publish_rc0", rc == 0, "rc=%d" % rc)
        rc, res, _ = sync_15()
        check("c5_15_sync_bridge_rc0", rc == 0, "rc=%d" % rc)
        check("c5_all_targets_still_clean14",
              sha_of(served_file) == clean_sha[:12]
              and sha_of(bridge + "/pool-new.txt") == clean_sha[:12]
              and sha_of(old_path) == clean_sha[:12],
              "served=%s bridge=%s legacy=%s"
              % (sha_of(served_file),
                 sha_of(bridge + "/pool-new.txt"), sha_of(old_path)))
        step("C5 stable healthy cycle",
             "one more full cycle healthy after recovery", error="")

        ok = all(c["ok"] for c in checks)
        log = {"drill": "d7a_cycles_latch",
               "sha": {"clean14": clean_sha[:12],
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
