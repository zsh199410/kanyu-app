#!/usr/bin/env python3
"""D6 item-3 drill (Issue #73, GPT D5 review 6887615694, item 3).

Five consecutive :07 cycles with the REAL gate-publish.sh + a stub
assembler + synthetic fixtures. Proves the exit code and the health
file distinguish "this round's verified publish succeeded" from
"the next round's source assembly failed", and that the NEXT round
never misjudges the previous assembly failure:

  1 healthy: gate passes v1, assembly produces v2 -> exit 0,
     health=healthy.
  2 torn assembly: gate passes v1, assembler crashes leaving a
     truncated $SRC -> exit 2, health=published_assembly_failed.
     The phone still serves the verified v1.
  3 next cycle on the torn $SRC: gate refuses (no evidence for the
     torn version) -> exit 1, health=gate_refused; served/bridge
     unchanged. The assembly failure was NOT mistaken for a publish
     failure (the publish from cycle 2 is intact) and the gate
     refusal was NOT mistaken for an assembly problem.
  4 atomic assembly crash (only .tmp left, $SRC still v1): gate
     passes v1 again -> exit 2, health=published_assembly_failed.
  5 next cycle re-gates the same v1 source -> exit 0,
     health=healthy. The previous assembly failure did not poison
     the next cycle.

Scratch layout (tempdir, never production). All fixtures synthetic
(TEST-NET, password TEST-ONLY-NOT-A-REAL-NODE). Output is one JSON
object with a per-step file/SHA/rc/error table; --out writes it.

Usage: python3 drills/d6_item3_publish_exit.py
       [--out docs/d6-item3-drill-log.json]
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

from pool.phone_gate import fingerprint_of, parse_surge_line  # noqa: E402
from pool.recovery import OWNER_ACK_INIT  # noqa: E402

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
    root = tempfile.mkdtemp(prefix="d6-item3-")
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
        sha2 = sha256_file(root + "/versions/v2.txt")
        stub = '''#!/usr/bin/env python3
import os, shutil, sys
root = os.environ["REHEARSAL_ROOT"]
mode = open(os.path.join(root, "prog", ".asm_mode")).read().strip()
dst = os.path.join(root, "prog", "publish", "pool-new.txt")
if mode == "2":
    shutil.copyfile(os.path.join(root, "versions", "v2.txt"), dst)
    print("{\\"ok\\": true, \\"assembled_version\\": 2}")
elif mode == "torn":
    lines = open(os.path.join(root, "versions", "v2.txt")).read().splitlines()
    open(dst, "w").write("\\n".join(lines[:20]) + "\\n")
    print("torn write, crashing", file=sys.stderr)
    sys.exit(1)
elif mode == "atomictmp":
    shutil.copyfile(os.path.join(root, "versions", "v2.txt"), dst + ".tmp")
    print("atomic assembly crashed, only .tmp left", file=sys.stderr)
    sys.exit(1)
else:
    print("unknown mode", file=sys.stderr)
    sys.exit(1)
'''
        stub_path = prog + "/venv/bin/python"
        with open(stub_path, "w") as _f:
            _f.write(stub)
        os.chmod(stub_path, 0o755)

        def set_mode(mode):
            with open(prog + "/.asm_mode", "w") as _f:
                _f.write(mode)

        shutil.copyfile(root + "/versions/v1.txt",
                        prog + "/publish/pool-new.txt")
        set_mode("2")
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

        def health():
            path = gate + "/logs/health.json"
            if not os.path.exists(path):
                return {}
            with open(path) as _f:
                return json.load(_f)

        def last_cycle_log():
            path = gate + "/logs/gate-publish.log"
            if not os.path.exists(path):
                return ""
            ends = [l for l in open(path) if "cycle_end" in l]
            return ends[-1] if ends else ""

        served_file = gate + "/state/served/pool-new.txt"
        bridge_file = bridge + "/pool-new.txt"
        src_file = prog + "/publish/pool-new.txt"

        p = subprocess.run(
            [sys.executable, "-m", "pool.recovery", "init",
             "--workdir", gate + "/state",
             "--owner-ack", OWNER_ACK_INIT],
            capture_output=True, text=True, cwd=gate, timeout=60)
        check("init_rc0", p.returncode == 0, p.stdout.strip()[:200])

        # ---- Cycle 1: healthy ----
        rc, _out = run_wrapper("gate-publish.sh")
        check("c1_exit_0_healthy", rc == 0
              and health().get("health") == "healthy",
              "rc=%d health=%s" % (rc, health().get("health")))
        check("c1_published_clean14",
              sha_of(gate + "/state/publish/pool-new.txt") == clean_sha[:12],
              "publish_sha=%s" % sha_of(gate + "/state/publish/pool-new.txt"))
        check("c1_source_now_v2", sha_of(src_file) == sha2[:12],
              "src_sha=%s" % sha_of(src_file))
        step("C1 healthy", "gate passes v1, assembly produces v2",
             src_sha_after=sha2[:12], publish_sha=clean_sha[:12],
             rc=rc, error="", health=health().get("health"))
        rc, _out = run_wrapper("gate-sync.sh")
        check("c1_sync_rc0", rc == 0, "rc=%d" % rc)
        check("c1_bridge_clean", sha_of(bridge_file) == clean_sha[:12],
              "bridge_sha=%s" % sha_of(bridge_file))

        # ---- Cycle 2: torn assembly -> exit 2 ----
        set_mode("torn")
        # Re-freeze v1 as the source so the gate passes and only the
        # assembly fails (isolates the exit-2 case from a gate refusal).
        shutil.copyfile(root + "/versions/v1.txt", src_file)
        rc, _out = run_wrapper("gate-publish.sh")
        check("c2_exit_2_assembly_failed", rc == 2
              and health().get("health") == "published_assembly_failed",
              "rc=%d health=%s" % (rc, health().get("health")))
        check("c2_health_gate_rc_0_asm_rc_1",
              health().get("gate_rc") == 0
              and health().get("assembly_rc") == 1,
              "health=%s" % health())
        check("c2_publish_still_clean14",
              sha_of(gate + "/state/publish/pool-new.txt") == clean_sha[:12],
              "publish_sha=%s" % sha_of(gate + "/state/publish/pool-new.txt"))
        check("c2_log_names_exit_2",
              "health=published_assembly_failed exit=2" in last_cycle_log(),
              "log_tail=%s" % last_cycle_log()[-120:])
        step("C2 torn assembly", "gate passes v1, assembly crashes; "
             "exit 2, phone still serves verified v1",
             src_lines=lines_of(src_file),
             publish_sha=sha_of(gate + "/state/publish/pool-new.txt"),
             rc=rc, error="", health=health().get("health"))

        # ---- Cycle 3: next cycle on the torn $SRC -> exit 1 ----
        rc, _out = run_wrapper("gate-publish.sh")
        check("c3_exit_1_gate_refused", rc == 1
              and health().get("health") == "gate_refused",
              "rc=%d health=%s" % (rc, health().get("health")))
        check("c3_health_gate_rc_1",
              health().get("gate_rc") == 1,
              "health=%s" % health())
        check("c3_served_bridge_unchanged",
              sha_of(served_file) == clean_sha[:12]
              and sha_of(bridge_file) == clean_sha[:12],
              "served=%s bridge=%s" % (sha_of(served_file),
                                       sha_of(bridge_file)))
        step("C3 next cycle on torn source",
             "gate refuses torn version; served/bridge unchanged",
             served_sha=sha_of(served_file), bridge_sha=sha_of(bridge_file),
             rc=rc, error="gate_refused", health=health().get("health"))

        # ---- Cycle 4: atomic crash, $SRC still v1 -> exit 2 ----
        shutil.copyfile(root + "/versions/v1.txt", src_file)
        set_mode("atomictmp")
        rc, _out = run_wrapper("gate-publish.sh")
        check("c4_exit_2_atomic_crash", rc == 2
              and health().get("health") == "published_assembly_failed",
              "rc=%d health=%s" % (rc, health().get("health")))
        check("c4_src_still_v1", sha_of(src_file) == sha1[:12],
              "src_sha=%s" % sha_of(src_file))
        check("c4_only_tmp_left", os.path.exists(src_file + ".tmp"),
              "tmp_exists=True")
        step("C4 atomic assembly crash",
             "only .tmp left, $SRC still v1; exit 2",
             src_sha=sha_of(src_file), rc=rc, error="",
             health=health().get("health"))

        # ---- Cycle 5: re-gate the same v1 -> exit 0 healthy ----
        set_mode("2")
        rc, _out = run_wrapper("gate-publish.sh")
        check("c5_exit_0_healthy_again", rc == 0
              and health().get("health") == "healthy",
              "rc=%d health=%s" % (rc, health().get("health")))
        step("C5 re-gate v1", "previous assembly failure did not poison "
             "the next cycle; exit 0 healthy",
             src_sha_after=sha_of(src_file), rc=rc, error="",
             health=health().get("health"))

        ok = all(c["ok"] for c in checks)
        log = {"drill": "d6_item3_publish_exit",
               "sha": {"v1_source": sha1[:12], "v2_source": sha2[:12],
                       "clean14": clean_sha[:12]},
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
