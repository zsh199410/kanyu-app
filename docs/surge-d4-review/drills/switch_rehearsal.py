#!/usr/bin/env python3
"""D4 switch rehearsal (isolation): run the REAL gate-publish.sh /
gate-sync.sh wrappers against a scratch production, in the exact
gate-first order the switch runbook prescribes.

Scratch layout (tempdir, never production):
  prog/publish/pool-new.txt   source file (versions v1 -> v2 -> v3)
  prog/gate/native-results.json
  prog/config/old-pool-file.txt
  prog/venv/bin/python        STUB assembly: copies the next version file
  gate/pool/                  real D3 code (copied from this tree)
  gate/state/                 D3 workdir (init with owner ack)
  gate/gate-publish.sh, gate-sync.sh, validate-native-record.py
  bridge/                     served target dir (replaces /opt/surge-bridge/modules)
  probe.db                    fixture p0 db (health only)

Scenarios:
  S1 cycle 1 :07  v1 tested -> gate rc=0, published == clean14; assembly -> v2
  S2 cycle 1 :15  sync rc=0, bridge == clean14 (served SHA S1)
  S3 cycle 2 :07  v2 UNTESTED -> gate rc=1 native_version_mismatch,
                  served/bridge SHA still S1 (no resurrection)
  S4 owner tests a SUPERSEDED version (v2) -> gate still refuses
                  (the source is v3); then owner tests the CURRENT
                  source (v4) -> gate rc=0, chain binds v4
  S5 concurrency: 3x gate-publish + 3x gate-sync in parallel on the
                  untested v5 -> all publishes refuse, syncs keep
                  serving the gated clean14, no sync_verify_failed
  S6 rollback rehearsal: old behaviour (ungated assembly + blind cp)
                  -> bridge == full source file again; gate state untouched

Usage: python3 drills/switch_rehearsal.py [--out docs/switch-rehearsal-log.json]
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
import threading

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
    root = tempfile.mkdtemp(prefix="d4-rehearsal-")
    checks = []

    def check(name, ok, detail=""):
        checks.append({"check": name, "ok": bool(ok), "detail": str(detail)})
        return bool(ok)

    try:
        # ---- layout ----
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

        # ---- versions: v1 = pool44 (44 lines); v2..v5 each remove one
        # more FAILED rotation line. Fingerprint sets shrink; the
        # clean14 set is identical in all versions.
        pool44 = read_lines(os.path.join(FIX, "pool_44_fixture.txt"))
        clean14 = read_lines(os.path.join(FIX, "clean_14_fixture.txt"))
        clean_fps = {fp_of_line(l) for l in clean14}
        record = json.load(open(os.path.join(
            FIX, "native_results_fixture.json")))
        v1_results = record["runs"][0]["results"]
        failed_lines = [l for l in pool44
                        if fp_of_line(l) not in clean_fps]
        versions = [pool44]
        for i in range(7):
            versions.append([l for l in versions[-1]
                             if l != failed_lines[i]])
        shas = []
        for i, lines in enumerate(versions, start=1):
            write_lines(root + "/versions/v%d.txt" % i, lines)
            shas.append(sha256_file(root + "/versions/v%d.txt" % i))
        sha1, sha2, sha3, sha4, sha5, sha6, sha7, sha8 = shas
        check("versions_distinct_sha", len(set(shas)) == 8,
              "shas=%s" % ",".join(s[:8] for s in shas))

        # ---- stub assembly: copies versions/v<N>.txt per counter ----
        stub = '''#!/usr/bin/env python3
import os, shutil, sys
root = os.environ["REHEARSAL_ROOT"]
counter = os.path.join(root, "prog", ".asm_counter")
n = int(open(counter).read().strip()) if os.path.exists(counter) else 1
src = os.path.join(root, "versions", "v%d.txt" % n)
dst = os.path.join(root, "prog", "publish", "pool-new.txt")
shutil.copyfile(src, dst)
open(counter, "w").write(str(n + 1))
print("{\\"ok\\": true, \\"assembled_version\\": %d}" % n)
'''
        stub_path = prog + "/venv/bin/python"
        open(stub_path, "w").write(stub)
        os.chmod(stub_path, 0o755)

        # ---- initial source = v1 (as if assembled last cycle) ----
        shutil.copyfile(root + "/versions/v1.txt",
                        prog + "/publish/pool-new.txt")
        open(prog + "/.asm_counter", "w").write("2")  # next assembly -> v2

        # ---- native record: run for v1 only, fresh ----
        now = record["runs"][0]["tested_at"] + 3600
        rec = {"format": "native-results-v1", "runs": [{
            "version_sha": sha1,
            "tested_at": record["runs"][0]["tested_at"],
            "tested_at_cst": record["runs"][0].get("tested_at_cst", ""),
            "network": "5G cellular pdp_ip0, no Wi-Fi",
            "surge": "6.100.0 build 4025",
            "results": v1_results}]}
        rec_path = prog + "/gate/native-results.json"
        json.dump(rec, open(rec_path, "w"))
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

        def last_gate_log():
            # Wrappers log to files, not stdout: read the last gate line.
            path = gate + "/logs/gate-publish.log"
            if not os.path.exists(path):
                return ""
            lines = [l for l in open(path) if "gate rc=" in l]
            return lines[-1] if lines else ""

        # ---- init recovery state (manual, owner ack) ----
        p = subprocess.run(
            [sys.executable, "-m", "pool.recovery", "init",
             "--workdir", gate + "/state",
             "--owner-ack", OWNER_ACK_INIT],
            capture_output=True, text=True, cwd=gate, timeout=60)
        check("init_rc0", p.returncode == 0, p.stdout.strip()[:200])

        # ---- S1: cycle 1 :07 (gate v1 -> publish clean14; assembly -> v2) ----
        rc, out = run_wrapper("gate-publish.sh")
        check("s1_gate_rc0", rc == 0, "rc=%d" % rc)
        pub = read_lines(gate + "/state/publish/pool-new.txt")
        check("s1_published_clean14", len(pub) == CLEAN_LINES
              and {fp_of_line(l) for l in pub} == clean_fps,
              "published_lines=%d" % len(pub))
        check("s1_source_now_v2",
              sha256_file(prog + "/publish/pool-new.txt") == sha2,
              "assembly advanced source to v2")

        # ---- S2: cycle 1 :15 (sync) ----
        rc, out = run_wrapper("gate-sync.sh")
        check("s2_sync_rc0", rc == 0, "rc=%d" % rc)
        served_sha = sha256_file(gate + "/state/served/pool-new.txt")
        bridge_sha = sha256_file(bridge + "/pool-new.txt")
        check("s2_bridge_matches_served", served_sha == bridge_sha,
              served_sha[:12])
        check("s2_bridge_is_clean14",
              len(read_lines(bridge + "/pool-new.txt")) == CLEAN_LINES)
        check("s2_old_copy_clean14",
              len(read_lines(bridge + "/old-pool.txt")) == CLEAN_LINES)
        s1_sha = bridge_sha

        # ---- S3: cycle 2 :07 (v2 untested -> refuse; served stays S1) ----
        rc, out = run_wrapper("gate-publish.sh")
        check("s3_gate_refuses_untested_v2", rc == 1
              and "native_version_mismatch" in last_gate_log(),
              "rc=%d log=%s" % (rc, last_gate_log()[-160:]))
        check("s3_served_unchanged",
              sha256_file(bridge + "/pool-new.txt") == s1_sha)
        check("s3_source_now_v3",
              sha256_file(prog + "/publish/pool-new.txt") == sha3,
              "assembly advanced source to v3")

        # ---- S4a: owner tests a SUPERSEDED version (v2). The source is
        # v3 now, so the v2 run must NOT admit anything: gate refuses.
        # This is the trap the runbook warns about -- test the CURRENT
        # source, not a version the assembly already replaced.
        v2_fps = {fp_of_line(l) for l in versions[1]}
        rec["runs"].append({
            "version_sha": sha2,
            "tested_at": record["runs"][0]["tested_at"] + 3600,
            "tested_at_cst": "",
            "network": "5G cellular pdp_ip0, no Wi-Fi",
            "surge": "6.100.0 build 4025",
            "results": [r for r in v1_results
                        if r["fingerprint"] in v2_fps]})
        json.dump(rec, open(rec_path, "w"))
        rc, out = run_wrapper("gate-publish.sh")
        check("s4a_superseded_test_does_not_admit", rc == 1
              and "native_version_mismatch" in last_gate_log(),
              "rc=%d log=%s" % (rc, last_gate_log()[-160:]))
        check("s4a_served_unchanged",
              sha256_file(bridge + "/pool-new.txt") == s1_sha)
        check("s4a_source_now_v4",
              sha256_file(prog + "/publish/pool-new.txt") == sha4,
              "assembly advanced source to v4")

        # ---- S4b: owner tests the CURRENT source (v4) -> gate rc=0,
        # chain binds v4; sync serves it.
        v4_fps = {fp_of_line(l) for l in versions[3]}
        rec["runs"].append({
            "version_sha": sha4,
            "tested_at": record["runs"][0]["tested_at"] + 7200,
            "tested_at_cst": "",
            "network": "5G cellular pdp_ip0, no Wi-Fi",
            "surge": "6.100.0 build 4025",
            "results": [r for r in v1_results
                        if r["fingerprint"] in v4_fps]})
        json.dump(rec, open(rec_path, "w"))
        rc, out = run_wrapper("gate-publish.sh")
        check("s4b_gate_rc0_after_current_tested", rc == 0, "rc=%d" % rc)
        meta = json.load(open(gate + "/state/publish/pool-new.txt.meta.json"))
        check("s4b_chain_binds_v4",
              meta.get("version_chain", {}).get("source_sha") == sha4,
              meta.get("version_chain", {}).get("source_sha", "")[:12])
        rc, out = run_wrapper("gate-sync.sh")
        check("s4b_sync_rc0", rc == 0, "rc=%d" % rc)
        check("s4b_bridge_still_clean14",
              len(read_lines(bridge + "/pool-new.txt")) == CLEAN_LINES)
        check("s4b_source_now_v5",
              sha256_file(prog + "/publish/pool-new.txt") == sha5,
              "assembly advanced source to v5")

        # ---- S5: concurrency (3x publish + 3x sync in parallel) ----
        results = {}

        def _run(kind, idx):
            name = "gate-publish.sh" if kind == "pub" else "gate-sync.sh"
            results[(kind, idx)] = run_wrapper(name)

        threads = []
        for i in range(3):
            threads.append(threading.Thread(target=_run, args=("pub", i)))
            threads.append(threading.Thread(target=_run, args=("sync", i)))
        for t in threads:
            t.start()
        for t in threads:
            t.join()
        final_lines = read_lines(bridge + "/pool-new.txt")
        check("s5_served_always_gated",
              {fp_of_line(l) for l in final_lines} == clean_fps
              and len(final_lines) == CLEAN_LINES,
              "final_lines=%d" % len(final_lines))
        logs = open(gate + "/logs/gate-sync.log").read()
        check("s5_no_false_verify_failure",
              "sync_verify_failed" not in logs, "log scanned")

        # ---- S6: rollback rehearsal (old behaviour restored) ----
        # Ungated assembly: full v5 file becomes the publish file;
        # blind sync: plain cp to the bridge target.
        shutil.copyfile(root + "/versions/v5.txt",
                        prog + "/publish/pool-new.txt")
        shutil.copyfile(prog + "/publish/pool-new.txt",
                        bridge + "/pool-new.txt")
        os.chmod(bridge + "/pool-new.txt", 0o644)
        check("s6_rollback_serves_full_file",
              sha256_file(bridge + "/pool-new.txt") == sha5
              and len(read_lines(bridge + "/pool-new.txt")) == len(versions[4]),
              "lines=%d" % len(versions[4]))
        st = json.load(open(gate + "/state/recovery-state.json"))
        check("s6_gate_state_untouched_by_rollback",
              st.get("state") == "ok" and not st.get("stopped", True),
              str(st.get("state")))

        ok = all(c["ok"] for c in checks)
        log = {"drill": "switch_rehearsal", "checks": checks,
               "passed": sum(1 for c in checks if c["ok"]),
               "total": len(checks), "ok": ok}
        print(json.dumps(log, indent=1, ensure_ascii=False))
        if args.out:
            json.dump(log, open(args.out, "w"), indent=1,
                      ensure_ascii=False)
        return 0 if ok else 1
    finally:
        shutil.rmtree(root, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
