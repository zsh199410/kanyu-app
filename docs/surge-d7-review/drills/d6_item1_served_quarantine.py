#!/usr/bin/env python3
"""D6 item-1 drill (Issue #73, GPT D5 review 6887615694, item 1).

Negative example, end to end with the REAL gate-sync.sh + REAL D6
pool code + a stub assembler + synthetic fixtures:

  A baseline: v1 + fresh native record -> :07 publish rc=0 ->
     :15 sync rc=0, bridge == clean14 (the HTTP subscription entry).
  B a lock-unaware writer tampers the SERVED file directly between
     two :15 runs (appends one unadmitted line: served
     6074082847c3 -> polluted 15 lines). The next sync re-serves
     the chain-verified publish file and overwrites the tamper
     (rc=0 is CORRECT here); the exposure window is bounded by the
     sync interval and the served path must not be HTTP-readable
     (gate-sync.sh exposure guard + runbook pre-switch check).
  C the D5 E3 case, post-copy: the tamper lands after run_sync
     copied the verified bytes to served and before its post-copy
     re-verification. The sync must rc=1 (sync_served_gate_failed)
     AND:
       - bridge / HTTP entry bytes UNCHANGED (still clean14);
       - the polluted bytes are NOT readable at the served path
         (served now holds the restored verified bytes) nor at the
         bridge path (bridge was never touched);
       - the polluted bytes live only in served/.quarantine/
         (mode 600, with the recorded manifest);
       - the pool enters degraded (STOP) until manual recovery.
  D the STOP holds: the next :15 run refuses and re-serves
     nothing.

Scratch layout (tempdir, never production). All fixtures synthetic
(TEST-NET, password TEST-ONLY-NOT-A-REAL-NODE). Output is one JSON
object with a per-step file/SHA/rc/error table; --out writes it.

Usage: python3 drills/d6_item1_served_quarantine.py
       [--out docs/d6-item1-drill-log.json]
Exit 0 = all checks pass. Stdout: one JSON object (the log).
"""
import argparse
import hashlib
import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FIX = os.path.join(HERE, "fixtures")
sys.path.insert(0, HERE)

from pool.phone_gate import fingerprint_of, parse_surge_line  # noqa: E402
from pool.recovery import OWNER_ACK_INIT, gate_check  # noqa: E402
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
    root = tempfile.mkdtemp(prefix="d6-item1-")
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
        probe_db = os.path.join(FIX, "p0_fixture.db")
        pool44 = read_lines(os.path.join(FIX, "pool_44_fixture.txt"))
        clean14 = read_lines(os.path.join(FIX, "clean_14_fixture.txt"))
        clean_fps = {fp_of_line(l) for l in clean14}
        clean_sha = sha_lines(clean14)
        failed_lines = [l for l in pool44 if fp_of_line(l) not in clean_fps]
        record = json.load(open(os.path.join(
            FIX, "native_results_fixture.json")))
        v1_results = record["runs"][0]["results"]
        v2 = [l for l in pool44 if l != failed_lines[0]]
        write_lines(root + "/versions/v1.txt", pool44)
        write_lines(root + "/versions/v2.txt", v2)
        sha1 = sha256_file(root + "/versions/v1.txt")
        polluted_sha = sha_lines(clean14 + [failed_lines[0]])
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

        def sha_of(path):
            return sha256_file(path)[:12] if os.path.exists(path) else ""

        def lines_of(path):
            return len(read_lines(path)) if os.path.exists(path) else 0

        served_file = gate + "/state/served/pool-new.txt"
        bridge_file = bridge + "/pool-new.txt"

        p = subprocess.run(
            [sys.executable, "-m", "pool.recovery", "init",
             "--workdir", gate + "/state",
             "--owner-ack", OWNER_ACK_INIT],
            capture_output=True, text=True, cwd=gate, timeout=60)
        check("init_rc0", p.returncode == 0, p.stdout.strip()[:200])

        # ---- A: baseline ----
        rc, _out = run_wrapper("gate-publish.sh")
        check("a_publish_rc0", rc == 0, "rc=%d" % rc)
        rc, _out = run_wrapper("gate-sync.sh")
        check("a_sync_rc0", rc == 0, "rc=%d" % rc)
        check("a_bridge_is_clean14",
              sha_of(bridge_file) == clean_sha[:12]
              and lines_of(bridge_file) == CLEAN_LINES,
              "bridge_sha=%s" % sha_of(bridge_file))
        check("a_served_is_clean14",
              sha_of(served_file) == clean_sha[:12],
              "served_sha=%s" % sha_of(served_file))
        step("A baseline", "publish + sync serve verified v1",
             served_sha=sha_of(served_file), bridge_sha=sha_of(bridge_file),
             rc=rc, error="")
        http_before = open(bridge_file, "rb").read()

        # ---- B: tamper BETWEEN cycles ----
        # A lock-unaware writer tampers served between two :15 runs.
        # The next sync re-serves the chain-verified publish file and
        # overwrites the tamper (rc=0 is CORRECT here: the served path
        # is re-written from verified bytes on every sync). The
        # exposure window is therefore bounded by the sync interval,
        # and the served path must not be HTTP-readable at all (see
        # the gate-sync.sh exposure guard + runbook pre-switch check).
        with open(served_file, "a", encoding="utf-8") as f:
            f.write(failed_lines[0] + "\n")
        check("b_served_now_polluted",
              sha_of(served_file) == polluted_sha[:12]
              and lines_of(served_file) == 15,
              "served_sha=%s lines=%d" % (sha_of(served_file),
                                          lines_of(served_file)))
        step("B tamper served between cycles",
             "lock-unaware writer appends 1 bad line",
             served_sha=sha_of(served_file),
             served_lines=lines_of(served_file), rc=None, error="")
        rc, _out = run_wrapper("gate-sync.sh")
        check("b_next_sync_overwrites_tamper_rc0", rc == 0, "rc=%d" % rc)
        check("b_served_clean_again",
              sha_of(served_file) == clean_sha[:12]
              and lines_of(served_file) == CLEAN_LINES,
              "served_sha=%s" % sha_of(served_file))
        step("B next sync", "sync re-serves verified publish, tamper "
             "overwritten (rc=0 is correct)",
             served_sha=sha_of(served_file),
             bridge_sha=sha_of(bridge_file), rc=rc, error="")

        # ---- C: POST-COPY tamper (the D5 E3 case) ----
        # The tamper lands after run_sync copied the verified bytes to
        # served and before its post-copy re-verification. This is the
        # window GPT item 1 asks about: the sync must refuse AND the
        # polluted bytes must not stay readable at the served path.
        state_dir = gate + "/state"

        def _tamper_served_post_copy(served_path):
            with open(served_path, "a", encoding="utf-8") as f:
                f.write(failed_lines[0] + "\n")

        rc, res = run_sync(state_dir, rec_path, sha1,
                           probe_db=probe_db, now=int(time.time()),
                           post_copy_hook=_tamper_served_post_copy)
        check("c_sync_refuses", rc == 1
              and res.get("error") == "sync_served_gate_failed",
              "rc=%d error=%s" % (rc, res.get("error")))
        # HTTP entry bytes unchanged (what the phone fetches).
        check("c_bridge_http_entry_unchanged",
              open(bridge_file, "rb").read() == http_before
              and sha_of(bridge_file) == clean_sha[:12],
              "bridge_sha=%s" % sha_of(bridge_file))
        # Served path no longer exposes polluted bytes.
        check("c_served_restored_to_clean14",
              sha_of(served_file) == clean_sha[:12]
              and lines_of(served_file) == CLEAN_LINES
              and failed_lines[0] not in read_lines(served_file),
              "served_sha=%s lines=%d" % (sha_of(served_file),
                                          lines_of(served_file)))
        # Polluted bytes live only in quarantine, mode 600.
        qdir = os.path.join(os.path.dirname(served_file), ".quarantine")
        qtxt = [f for f in (os.listdir(qdir) if os.path.isdir(qdir) else [])
                if f.endswith(".txt")]
        q_ok = (len(qtxt) == 1
                and sha_of(os.path.join(qdir, qtxt[0])) == polluted_sha[:12]
                and stat.S_IMODE(os.stat(
                    os.path.join(qdir, qtxt[0])).st_mode) == 0o600)
        check("c_polluted_quarantined_only",
              q_ok, "quarantine=%s" % qtxt)
        # Pool degraded until manual recovery.
        allowed, err, _st = gate_check(state_dir)
        check("c_pool_stopped", not allowed and err == "pool_stopped",
              "gate_check err=%s" % err)
        step("C sync after post-copy served tamper",
             "refused; bridge unchanged, served restored, polluted "
             "quarantined, pool STOP",
             served_sha=sha_of(served_file), bridge_sha=sha_of(bridge_file),
             quarantine=qtxt, rc=rc, error="sync_served_gate_failed")

        # ---- D: STOP holds: the next :15 run must not re-serve ----
        rc, _out = run_wrapper("gate-sync.sh")
        check("d_stop_holds_next_sync_refuses", rc == 1, "rc=%d" % rc)
        check("d_bridge_still_clean_after_stop",
              sha_of(bridge_file) == clean_sha[:12],
              "bridge_sha=%s" % sha_of(bridge_file))
        step("D next sync while STOP",
             "refused; bridge still clean, nothing re-served",
             bridge_sha=sha_of(bridge_file), rc=rc, error="pool_stopped")

        ok = all(c["ok"] for c in checks)
        log = {"drill": "d6_item1_served_quarantine",
               "sha": {"clean14": clean_sha[:12],
                       "polluted15": polluted_sha[:12]},
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
