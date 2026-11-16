#!/usr/bin/env python3
"""D6 item-2 drill (Issue #73, GPT D5 review 6887615694, item 2).

Two fault injections, with SHA evidence:

  A SHA-check -> bridge-rename race (in-process, deterministic):
    seed clean v1, then run pool.bridge_sync with a hook that
    rewrites the SERVED file AFTER the snapshot was taken and BEFORE
    the bridge rename. The bridge must still receive ONLY the
    verified snapshot bytes (bridge SHA == clean14); the run fails
    rc=1 (served_changed_after_bridge_copy) because the served
    tamper was detected and contained (quarantine + restore + STOP).
  B legacy $OLD copy failure (real gate-sync.sh wrapper):
    seed clean, sync once (bridge == clean14), then point the legacy
    manifest at a nonexistent directory and run gate-sync.sh. The
    run must fail rc=1 (legacy_copy_failed), the bridge must be
    rolled back to its pre-run bytes (bridge SHA == clean14), the
    legacy file must not exist, and the run must never claim success.

Scratch layout (tempdir, never production). All fixtures synthetic
(TEST-NET, password TEST-ONLY-NOT-A-REAL-NODE). Output is one JSON
object with a per-step file/SHA/rc/error table; --out writes it.

Usage: python3 drills/d6_item2_bridge_race.py
       [--out docs/d6-item2-drill-log.json]
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
import time

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FIX = os.path.join(HERE, "fixtures")
sys.path.insert(0, HERE)

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

from pool.bridge_sync import run_bridge_sync  # noqa: E402
from pool.phone_gate import fingerprint_of, parse_surge_line  # noqa: E402
from pool.publish import run_publish  # noqa: E402
from pool.recovery import OWNER_ACK_INIT, gate_check, init_recovery_state  # noqa: E402
from pool.sync import run_sync  # noqa: E402

CLEAN_LINES = 14


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def sha_lines(lines):
    return hashlib.sha256(("\n".join(lines) + "\n").encode("utf-8")).hexdigest()


def read_lines(path):
    with open(path, encoding="utf-8") as f:
        return [l.rstrip("\n") for l in f if l.strip()]


def write_lines(path, lines):
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")


def fp_of_line(line):
    name, proto, host, port, params = parse_surge_line(line)
    return fingerprint_of(proto, host, port, params)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=None)
    args = ap.parse_args()
    root = tempfile.mkdtemp(prefix="d6-item2-")
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

    try:
        pool44 = read_lines(os.path.join(FIX, "pool_44_fixture.txt"))
        clean14 = read_lines(os.path.join(FIX, "clean_14_fixture.txt"))
        clean_fps = {fp_of_line(l) for l in clean14}
        clean_sha = sha_lines(clean14)
        failed_lines = [l for l in pool44 if fp_of_line(l) not in clean_fps]
        record_path = os.path.join(FIX, "native_results_fixture.json")
        probe_db = os.path.join(FIX, "p0_fixture.db")
        record = json.load(open(record_path))
        version_sha = record["runs"][0]["version_sha"]
        now = record["runs"][0]["tested_at"] + 3600

        def sha_of(path):
            return sha256_file(path)[:12] if os.path.exists(path) else ""

        # ================= A: race injection (in-process) =================
        workdir = os.path.join(root, "wd-a")
        os.makedirs(workdir, exist_ok=True)
        rc, out = init_recovery_state(workdir, OWNER_ACK_INIT)
        check("a_init_rc0", rc == 0, str(out)[:120])
        rc, res = run_publish(workdir, clean14, record_path, version_sha,
                              probe_db=probe_db, now=now,
                              source_file=os.path.join(
                                  FIX, "pool_44_fixture.txt"))
        check("a_publish_rc0", rc == 0, str(res.get("error")))
        rc, res = run_sync(workdir, record_path, version_sha,
                           probe_db=probe_db, now=now)
        check("a_sync_rc0", rc == 0, str(res.get("error")))
        served_a = os.path.join(workdir, "served", "pool-new.txt")
        bridge_a = os.path.join(root, "bridge-a")
        os.makedirs(bridge_a, exist_ok=True)

        def _rewrite_served(_tmp_path):
            with open(served_a, "a", encoding="utf-8") as f:
                f.write(failed_lines[0] + "\n")

        rc, res = run_bridge_sync(
            workdir, bridge_a, native_record_path=record_path,
            probe_db=probe_db, now=now,
            pre_bridge_rename_hook=_rewrite_served)
        check("a_race_rc1_served_changed",
              rc == 1 and res.get("error") == "served_changed_after_bridge_copy",
              "rc=%d error=%s" % (rc, res.get("error")))
        check("a_bridge_got_verified_snapshot_only",
              sha_of(bridge_a + "/pool-new.txt") == clean_sha[:12]
              and res.get("served_snapshot_sha") == clean_sha,
              "bridge_sha=%s snapshot=%s"
              % (sha_of(bridge_a + "/pool-new.txt"),
                 (res.get("served_snapshot_sha") or "")[:12]))
        check("a_served_quarantined_and_restored",
              res.get("served_restored") is True
              and sha_of(served_a) == clean_sha[:12],
              "served_sha=%s restored=%s"
              % (sha_of(served_a), res.get("served_restored")))
        allowed, err, _st = gate_check(workdir)
        check("a_pool_stopped", not allowed and err == "pool_stopped",
              "gate_check err=%s" % err)
        step("A race injection",
             "served rewritten between snapshot and bridge rename; "
             "bridge still got only verified bytes",
             bridge_sha=sha_of(bridge_a + "/pool-new.txt"),
             served_sha=sha_of(served_a), rc=rc,
             error=res.get("error", ""))

        # ================= B: legacy failure (real wrapper) ===============
        prog = os.path.join(root, "prog")
        gate = os.path.join(root, "gate")
        bridge = os.path.join(root, "bridge")
        for d in [prog + "/publish", prog + "/gate", prog + "/config",
                  prog + "/venv/bin", gate + "/state", gate + "/logs",
                  bridge, root + "/versions"]:
            os.makedirs(d, exist_ok=True)
        shutil.copytree(os.path.join(HERE, "pool"), gate + "/pool")
        for f in ["gate-publish.sh", "gate-sync.sh",
                  "validate-native-record.py"]:
            shutil.copy(os.path.join(HERE, "systemd", f), gate + "/" + f)
            os.chmod(gate + "/" + f, 0o755)
        v2 = [l for l in pool44 if l != failed_lines[0]]
        write_lines(root + "/versions/v1.txt", pool44)
        write_lines(root + "/versions/v2.txt", v2)
        sha1 = sha256_file(root + "/versions/v1.txt")
        stub = '''#!/usr/bin/env python3
import os, shutil, sys
root = os.environ["REHEARSAL_ROOT"]
mode = open(os.path.join(root, "prog", ".asm_mode")).read().strip()
dst = os.path.join(root, "prog", "publish", "pool-new.txt")
if mode == "2":
    shutil.copyfile(os.path.join(root, "versions", "v2.txt"), dst)
    print("{\\"ok\\": true}")
else:
    print("unknown mode", file=sys.stderr)
    sys.exit(1)
'''
        stub_path = prog + "/venv/bin/python"
        with open(stub_path, "w") as _f:
            _f.write(stub)
        os.chmod(stub_path, 0o755)
        with open(prog + "/.asm_mode", "w") as _f:
            _f.write("2")
        shutil.copyfile(root + "/versions/v1.txt",
                        prog + "/publish/pool-new.txt")
        now_wall = int(time.time())
        v1_results = record["runs"][0]["results"]
        rec = {"format": "native-results-v1", "runs": [{
            "version_sha": sha1,
            "tested_at": now_wall - 3600,
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
            "PROBE_DB": probe_db, "BRIDGE_DIR": bridge,
            "GATE_PY": sys.executable, "PROD_PY": stub_path,
        })

        def run_wrapper(name):
            p = subprocess.run(["bash", gate + "/" + name],
                               capture_output=True, text=True, env=env,
                               timeout=120)
            return p.returncode, (p.stdout + p.stderr).strip()

        p = subprocess.run(
            [sys.executable, "-m", "pool.recovery", "init",
             "--workdir", gate + "/state",
             "--owner-ack", OWNER_ACK_INIT],
            capture_output=True, text=True, cwd=gate, timeout=60)
        check("b_init_rc0", p.returncode == 0, p.stdout.strip()[:200])
        rc, _out = run_wrapper("gate-publish.sh")
        check("b_publish_rc0", rc == 0, "rc=%d" % rc)
        rc, _out = run_wrapper("gate-sync.sh")
        check("b_sync_rc0", rc == 0, "rc=%d" % rc)
        check("b_bridge_clean_before_break",
              sha_of(bridge + "/pool-new.txt") == clean_sha[:12]
              and sha_of(bridge + "/old-pool.txt") == clean_sha[:12],
              "bridge_sha=%s legacy_sha=%s"
              % (sha_of(bridge + "/pool-new.txt"),
                 sha_of(bridge + "/old-pool.txt")))
        step("B baseline", "publish + sync serve verified v1 to both targets",
             bridge_sha=sha_of(bridge + "/pool-new.txt"),
             legacy_sha=sha_of(bridge + "/old-pool.txt"), rc=rc, error="")
        with open(prog + "/config/old-pool-file.txt", "w") as f:
            f.write(bridge + "/no-such-dir/old-pool.txt")
        rc, _out = run_wrapper("gate-sync.sh")
        slog = open(gate + "/logs/gate-sync.log").read()
        check("b_legacy_failure_rc1",
              rc == 1 and "legacy_copy_failed" in slog,
              "rc=%d" % rc)
        check("b_bridge_rolled_back_to_pre_run",
              sha_of(bridge + "/pool-new.txt") == clean_sha[:12],
              "bridge_sha=%s" % sha_of(bridge + "/pool-new.txt"))
        check("b_legacy_never_written",
              not os.path.exists(bridge + "/no-such-dir/old-pool.txt"),
              "legacy_absent=True")
        check("b_no_fake_success_log",
              slog.count("synced served_sha") == 1,
              "synced lines=%d (only the first, successful run)"
              % slog.count("synced served_sha"))
        step("B legacy copy failure",
             "rc=1 legacy_copy_failed; bridge rolled back, legacy "
             "absent, no success claimed",
             bridge_sha=sha_of(bridge + "/pool-new.txt"), rc=rc,
             error="legacy_copy_failed")

        ok = all(c["ok"] for c in checks)
        log = {"drill": "d6_item2_bridge_race",
               "sha": {"clean14": clean_sha[:12]},
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
