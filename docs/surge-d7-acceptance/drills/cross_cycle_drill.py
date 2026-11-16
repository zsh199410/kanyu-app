#!/usr/bin/env python3
"""D5 cross-cycle drill (Issue #73, GPT D4 review 6887331723).

Proves, end to end with the REAL gate-publish.sh / gate-sync.sh
wrappers + the REAL D5 pool code + a stub assembler + synthetic
fixtures, that a native pass for one version NEVER authorizes the
next version:

  A baseline: v1 + fresh native record -> :07 publish rc=0
     (publish == clean14) -> :15 sync rc=0 (bridge == clean14).
  B v2 untested: stub assembly produces v2 ($SRC becomes v2) ->
     next :07 publish MUST rc=1 (native_version_mismatch) and the
     publish file SHA stays v1-clean; next :15 sync rc=0 still
     serving the verified v1 (recorded as such -- NOT a refusal).
  C adversarial sync admission: an ungated writer plants untested
     v2 straight into $STATE/publish/ (sync's read position) ->
     sync MUST rc=1, served/bridge stay v1. Red control: a plain
     cp of v2 to served/bridge (the old blind pool-sync.sh behaviour)
     DOES put v2 on the bridge (bridge SHA == v2), proving the hole
     exists without the gate. D7a (GPT D7 review 6912114134,
     item 1): the next gated sync does NOT silently restore v1 --
     gate-block refuses the divergence (rc=1, STOP latched,
     served/bridge stay v2); only the controlled repair
     (repair_targets) + owner-acknowledged clear_stop restores the
     verified v1, and the following gated sync is healthy.
  D assembler faults: (D1) torn write -- assembler crashes leaving
     a truncated $SRC -> next publish rc=1, served/bridge unchanged;
     (D2) atomic-assembly crash -- only a .tmp is left, $SRC still
     v1 -> next publish re-validates v1 normally, served/bridge
     unchanged.
  E final-byte verification (in-process fault injection): (E1) tmp
     tampered after write, before rename -> publish rc=1
     publish_postwrite_verify_failed, target SHA unchanged; (E2)
     tmp tampered AT the rename -> publish rc=1, previous bytes
     restored, target SHA unchanged; (E3) served tampered after the
     copy -> sync rc=1 sync_served_gate_failed + degraded state.

Scratch layout (tempdir, never production): same shape as
drills/switch_rehearsal.py. All fixtures synthetic (TEST-NET,
password TEST-ONLY-NOT-A-REAL-NODE). Output is one JSON object with
a per-step file/SHA/rc/error table; --out writes it to a file.

Usage: python3 drills/cross_cycle_drill.py
       [--out docs/cross-cycle-drill-log.json]
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
from unittest import mock

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FIX = os.path.join(HERE, "fixtures")
sys.path.insert(0, HERE)

from pool.bridge_sync import repair_targets, verify_targets  # noqa: E402
from pool.phone_gate import fingerprint_of, parse_surge_line  # noqa: E402
from pool.publish import run_publish  # noqa: E402
from pool.recovery import (  # noqa: E402
    OWNER_ACK_CLEAR, OWNER_ACK_INIT, clear_stop, gate_check)
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
    root = tempfile.mkdtemp(prefix="d5-cross-cycle-")
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
        # ---- layout ----
        prog = os.path.join(root, "prog")
        gate = os.path.join(root, "gate")
        bridge = os.path.join(root, "bridge")
        for d in [prog + "/publish", prog + "/gate", prog + "/config",
                  prog + "/venv/bin", gate + "/state", gate + "/logs",
                  bridge, root + "/versions", root + "/backup"]:
            os.makedirs(d, exist_ok=True)
        shutil.copytree(os.path.join(HERE, "pool"), gate + "/pool")
        for f in ["gate-publish.sh", "gate-sync.sh",
                  "validate-native-record.py"]:
            shutil.copy(os.path.join(HERE, "systemd", f), gate + "/" + f)
            os.chmod(gate + "/" + f, 0o755)
        probe_db = os.path.join(FIX, "p0_fixture.db")

        # ---- versions: v1 = pool44; v2/v3/v4 each remove one more
        # FAILED rotation line. The clean14 set is identical in all.
        pool44 = read_lines(os.path.join(FIX, "pool_44_fixture.txt"))
        clean14 = read_lines(os.path.join(FIX, "clean_14_fixture.txt"))
        clean_fps = {fp_of_line(l) for l in clean14}
        clean_sha = sha_lines(clean14)
        record = json.load(open(os.path.join(
            FIX, "native_results_fixture.json")))
        v1_results = record["runs"][0]["results"]
        failed_lines = [l for l in pool44
                        if fp_of_line(l) not in clean_fps]
        versions = [pool44]
        for i in range(3):
            versions.append([l for l in versions[-1]
                             if l != failed_lines[i]])
        shas = []
        for i, lines in enumerate(versions, start=1):
            write_lines(root + "/versions/v%d.txt" % i, lines)
            shas.append(sha256_file(root + "/versions/v%d.txt" % i))
        sha1, sha2, sha3, sha4 = shas
        check("versions_distinct_sha", len(set(shas)) == 4,
              "shas=%s" % ",".join(s[:8] for s in shas))

        # ---- stub assembler: mode file selects the behaviour ----
        stub = '''#!/usr/bin/env python3
import os, shutil, sys
root = os.environ["REHEARSAL_ROOT"]
mode = open(os.path.join(root, "prog", ".asm_mode")).read().strip()
dst = os.path.join(root, "prog", "publish", "pool-new.txt")
if mode in ("2", "3", "4"):
    shutil.copyfile(os.path.join(root, "versions", "v%s.txt" % mode), dst)
    print("{\\"ok\\": true, \\"assembled_version\\": %s}" % mode)
elif mode == "torn3":
    lines = open(os.path.join(root, "versions", "v3.txt")).read().splitlines()
    open(dst, "w").write("\\n".join(lines[:20]) + "\\n")
    print("torn write, crashing", file=sys.stderr)
    sys.exit(1)
elif mode == "atomictmp":
    shutil.copyfile(os.path.join(root, "versions", "v4.txt"), dst + ".tmp")
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

        # ---- initial source = v1; fresh native record for v1 only ----
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

        def last_gate_log():
            path = gate + "/logs/gate-publish.log"
            if not os.path.exists(path):
                return ""
            lines = [l for l in open(path) if "gate rc=" in l]
            return lines[-1] if lines else ""

        def _health():
            path = gate + "/logs/health.json"
            if not os.path.exists(path):
                return {}
            with open(path) as _f:
                return json.load(_f)

        def sha_of(path):
            return sha256_file(path)[:12] if os.path.exists(path) else ""

        def lines_of(path):
            return len(read_lines(path)) if os.path.exists(path) else 0

        pub_file = gate + "/state/publish/pool-new.txt"
        served_file = gate + "/state/served/pool-new.txt"
        bridge_file = bridge + "/pool-new.txt"
        src_file = prog + "/publish/pool-new.txt"

        # ---- init recovery state (manual, owner ack) ----
        p = subprocess.run(
            [sys.executable, "-m", "pool.recovery", "init",
             "--workdir", gate + "/state",
             "--owner-ack", OWNER_ACK_INIT],
            capture_output=True, text=True, cwd=gate, timeout=60)
        check("init_rc0", p.returncode == 0, p.stdout.strip()[:200])

        # ============ A: baseline v1 ============
        rc, _out = run_wrapper("gate-publish.sh")
        check("a_publish_rc0", rc == 0, "rc=%d" % rc)
        check("a_published_clean14",
              lines_of(pub_file) == CLEAN_LINES
              and sha_of(pub_file) == clean_sha[:12],
              "publish_sha=%s lines=%d" % (sha_of(pub_file),
                                           lines_of(pub_file)))
        check("a_source_now_v2", sha_of(src_file) == sha2[:12],
              "src_sha=%s" % sha_of(src_file))
        step("A1 :07 publish v1", "gate passes v1, assembly produces v2",
             src_sha_before=sha1[:12], src_sha_after=sha2[:12],
             publish_sha=sha_of(pub_file), publish_lines=lines_of(pub_file),
             rc=rc, error="")
        rc, _out = run_wrapper("gate-sync.sh")
        check("a_sync_rc0", rc == 0, "rc=%d" % rc)
        check("a_bridge_is_clean14",
              sha_of(bridge_file) == clean_sha[:12]
              and lines_of(bridge_file) == CLEAN_LINES,
              "bridge_sha=%s" % sha_of(bridge_file))
        step("A2 :15 sync v1", "sync serves verified v1 to bridge",
             served_sha=sha_of(served_file), bridge_sha=sha_of(bridge_file),
             bridge_lines=lines_of(bridge_file), rc=rc, error="")

        # ============ B: v2 untested ============
        set_mode("3")
        rc, _out = run_wrapper("gate-publish.sh")
        check("b_publish_refuses_untested_v2", rc == 1
              and "native_version_mismatch" in last_gate_log(),
              "rc=%d gate_error=native_version_mismatch" % rc)
        check("b_publish_sha_still_v1_clean",
              sha_of(pub_file) == clean_sha[:12],
              "publish_sha=%s" % sha_of(pub_file))
        check("b_source_now_v3", sha_of(src_file) == sha3[:12],
              "src_sha=%s" % sha_of(src_file))
        step("B1 :07 publish v2-untested",
             "gate refuses v2 (native_version_mismatch); publish stays v1",
             src_sha_before=sha2[:12], src_sha_after=sha3[:12],
             publish_sha=sha_of(pub_file), publish_lines=lines_of(pub_file),
             rc=rc, error="native_version_mismatch")
        rc, _out = run_wrapper("gate-sync.sh")
        check("b_sync_still_serves_v1_rc0", rc == 0, "rc=%d" % rc)
        check("b_bridge_still_v1_clean",
              sha_of(bridge_file) == clean_sha[:12],
              "bridge_sha=%s" % sha_of(bridge_file))
        step("B2 :15 sync after v2 refusal",
             "sync serves the still-verified v1 (NOT a refusal of v1)",
             served_sha=sha_of(served_file), bridge_sha=sha_of(bridge_file),
             bridge_lines=lines_of(bridge_file), rc=rc, error="")

        # ============ C: adversarial plant + blind-cp red control ====
        shutil.copyfile(pub_file, root + "/backup/publish-clean14.txt")
        shutil.copyfile(pub_file + ".meta.json",
                        root + "/backup/publish-clean14.txt.meta.json")
        write_lines(pub_file, versions[1])  # untested v2, no chain
        try:
            os.unlink(pub_file + ".meta.json")
        except OSError:
            pass
        step("C0 plant v2 in publish/",
             "ungated writer drops untested v2 at sync's read position",
             publish_sha_before=clean_sha[:12],
             publish_sha_after=sha_of(pub_file),
             publish_lines_after=lines_of(pub_file), rc=None, error="")
        rc, _out = run_wrapper("gate-sync.sh")
        check("c_sync_refuses_planted_v2", rc == 1, "rc=%d" % rc)
        check("c_served_bridge_still_v1",
              sha_of(served_file) == clean_sha[:12]
              and sha_of(bridge_file) == clean_sha[:12],
              "served=%s bridge=%s" % (sha_of(served_file),
                                       sha_of(bridge_file)))
        slog = ""
        spath = gate + "/logs/gate-sync.log"
        if os.path.exists(spath):
            slog = open(spath).read().splitlines()[-1]
        step("C1 :15 sync with planted v2",
             "sync refuses planted v2; served/bridge stay v1",
             served_sha=sha_of(served_file), bridge_sha=sha_of(bridge_file),
             rc=rc, error=slog[-160:])
        # Restore the gated publish file, re-sync to v1.
        shutil.copyfile(root + "/backup/publish-clean14.txt", pub_file)
        shutil.copyfile(root + "/backup/publish-clean14.txt.meta.json",
                        pub_file + ".meta.json")
        rc, _out = run_wrapper("gate-sync.sh")
        check("c_sync_restores_v1_after_plant", rc == 0
              and sha_of(bridge_file) == clean_sha[:12], "rc=%d" % rc)
        # Red control: old blind behaviour (plain cp, no gate).
        shutil.copyfile(root + "/versions/v2.txt", served_file)
        shutil.copyfile(root + "/versions/v2.txt", bridge_file)
        os.chmod(bridge_file, 0o644)
        check("c_red_blind_cp_serves_v2",
              sha_of(bridge_file) == sha2[:12]
              and lines_of(bridge_file) == len(versions[1]),
              "bridge_sha=%s lines=%d" % (sha_of(bridge_file),
                                          lines_of(bridge_file)))
        step("C2 RED blind cp (no gate)",
             "plain cp puts untested v2 on the bridge -- the hole",
             served_sha=sha_of(served_file), bridge_sha=sha_of(bridge_file),
             bridge_lines=lines_of(bridge_file), rc=0,
             error="RED: ungated copy serves v2")
        # D7a (GPT D7 review 6912114134, item 1): the next gated sync
        # does NOT silently restore v1. The blind cp left served AND
        # bridge at untested v2, so gate-block refuses the divergence
        # (rc=1, STOP latched, both stay v2); only the controlled
        # repair + owner-acknowledged clear restores the verified v1.
        rc, _out = run_wrapper("gate-sync.sh")
        check("c_green_gated_sync_refuses_divergence", rc == 1
              and sha_of(served_file) == sha2[:12]
              and sha_of(bridge_file) == sha2[:12],
              "rc=%d served=%s bridge=%s" % (rc, sha_of(served_file),
                                             sha_of(bridge_file)))
        allowed, gerr, _st = gate_check(gate + "/state")
        check("c_green_stop_latched", not allowed and gerr == "pool_stopped",
              "gate_check err=%s" % gerr)
        step("C3 GREEN gated sync refuses blind cp (D7a)",
             "gate-block refuses divergence, STOP latched; served/bridge "
             "stay v2 (NOT silently overwritten)",
             served_sha=sha_of(served_file), bridge_sha=sha_of(bridge_file),
             rc=rc, error="targets_inconsistent")
        now_c3 = int(time.time())
        rc_r, res_r = repair_targets(
            gate + "/state", bridge, old_path=bridge + "/old-pool.txt",
            native_record_path=rec_path, probe_db=probe_db, now=now_c3,
            manifest_path=gate + "/logs/repair-manifest-c3.json")
        check("c_green_repair_targets_rc0", rc_r == 0,
              "rc=%d error=%s" % (rc_r, res_r.get("error")))
        vt = verify_targets(gate + "/state", bridge,
                            old_path=bridge + "/old-pool.txt")
        check("c_green_verify_targets_consistent",
              vt["consistent"] is True, "detail=%s" % vt["detail"])
        rc_c, res_c = clear_stop(gate + "/state", OWNER_ACK_CLEAR, rec_path,
                                 probe_db=probe_db, now=int(time.time()))
        check("c_green_clear_stop_rc0", rc_c == 0,
              "rc=%d error=%s" % (rc_c, res_c.get("error")))
        rc, _out = run_wrapper("gate-sync.sh")
        check("c_green_gated_sync_restores_v1", rc == 0
              and sha_of(bridge_file) == clean_sha[:12], "rc=%d" % rc)
        step("C4 GREEN repair + clear + gated sync",
             "controlled repair restores verified v1; clear_stop with "
             "fresh evidence; next gated sync healthy",
             served_sha=sha_of(served_file), bridge_sha=sha_of(bridge_file),
             rc=rc, error="")

        # ============ D1: torn assembly write ============
        set_mode("torn3")
        rc, _out = run_wrapper("gate-publish.sh")
        torn_sha = sha_of(src_file)
        check("d1_publish_refuses_torn_src", rc == 1
              and "native_version_mismatch" in last_gate_log(),
              "rc=%d gate_error=native_version_mismatch" % rc)
        check("d1_served_bridge_unchanged",
              sha_of(served_file) == clean_sha[:12]
              and sha_of(bridge_file) == clean_sha[:12],
              "served=%s bridge=%s" % (sha_of(served_file),
                                       sha_of(bridge_file)))
        step("D1 torn assembly write",
             "assembler crashes leaving truncated $SRC; publish refuses",
             src_sha_after=torn_sha, src_lines=lines_of(src_file),
             served_sha=sha_of(served_file), bridge_sha=sha_of(bridge_file),
             rc=rc, error="native_version_mismatch")
        # Drill reset: restore the full v3 source (operator re-freeze).
        shutil.copyfile(root + "/versions/v3.txt", src_file)

        # ============ D2: atomic-assembly crash, only .tmp left ====
        shutil.copyfile(root + "/versions/v1.txt", src_file)  # re-freeze v1
        set_mode("atomictmp")
        rc, _out = run_wrapper("gate-publish.sh")
        # D6 (GPT D5 review 6887615694, item 3): gate re-validated v1
        # (publish succeeded) but the assembly crashed, so the cycle
        # exits 2 (published_assembly_failed), NOT 0. D5 asserted
        # rc==0 here -- that was the masking GPT flagged.
        check("d2_publish_revalidates_v1_exit2", rc == 2, "rc=%d" % rc)
        check("d2_health_published_assembly_failed",
              _health()["health"] == "published_assembly_failed",
              "health=%s" % _health().get("health"))
        check("d2_src_still_v1", sha_of(src_file) == sha1[:12],
              "src_sha=%s" % sha_of(src_file))
        check("d2_only_tmp_left",
              os.path.exists(src_file + ".tmp")
              and lines_of(src_file) == len(pool44),
              "tmp_exists=%s" % os.path.exists(src_file + ".tmp"))
        check("d2_served_bridge_unchanged",
              sha_of(served_file) == clean_sha[:12]
              and sha_of(bridge_file) == clean_sha[:12])
        cycle_recs = []
        for f in sorted(os.listdir(gate + "/logs")):
            if f.startswith("cycle-") and f.endswith(".json"):
                with open(os.path.join(gate + "/logs", f)) as fh:
                    cycle_recs.append(json.load(fh))
        check("d2_cycle_record_marks_new_ungated",
              bool(cycle_recs) and cycle_recs[-1]["new_source_gated"] is False
              and cycle_recs[-1]["assembly_failed"] is True,
              "last_cycle=%s" % (cycle_recs[-1] if cycle_recs else None))
        step("D2 atomic assembly crash",
             "only .tmp left, $SRC still v1; publish re-validates v1",
             src_sha_after=sha_of(src_file), src_tmp_exists=True,
             served_sha=sha_of(served_file), bridge_sha=sha_of(bridge_file),
             rc=rc, error="assembly_failed, new_source_gated=false")

        # ============ E: final-byte fault injection (in-process) ====
        now_e = int(time.time())
        state_dir = gate + "/state"
        # D6 (baseline fix): the E section calls run_publish/run_sync
        # in-process with wall-clock `now`, but the checked-in fixture
        # record's tested_at ages past the 24 h TTL as calendar time
        # passes (stale by ~5 h on 2026-11-16). Refresh tested_at to
        # now_e minus 1 h at drill time (same version_sha + results).
        rec_e = {"format": "native-results-v1", "runs": [{
            "version_sha": sha1,
            "tested_at": now_e - 3600,
            "tested_at_cst": "",
            "network": "5G cellular pdp_ip0, no Wi-Fi",
            "surge": "6.100.0 build 4025",
            "results": v1_results}]}
        rec_e_path = os.path.join(root, "native-results-fresh.json")
        with open(rec_e_path, "w") as _f:
            json.dump(rec_e, _f)

        def _tamper_tmp(tmp_path):
            with open(tmp_path, "a", encoding="utf-8") as f:
                f.write(failed_lines[0] + "\n")

        rc_e, res_e = run_publish(
            state_dir, clean14, rec_e_path, sha1,
            probe_db=probe_db, now=now_e,
            source_file=root + "/versions/v1.txt",
            pre_rename_hook=_tamper_tmp)
        check("e1_tmp_tamper_refused", rc_e == 1
              and res_e.get("error") == "publish_postwrite_verify_failed",
              "rc=%d error=%s" % (rc_e, res_e.get("error")))
        check("e1_target_unchanged",
              sha_of(pub_file) == clean_sha[:12]
              and not os.path.exists(pub_file + ".tmp"),
              "publish_sha=%s" % sha_of(pub_file))
        step("E1 publish tmp tampered pre-rename",
             "final-byte check refuses; target SHA unchanged",
             publish_sha=sha_of(pub_file), rc=rc_e,
             error=res_e.get("error", ""))

        real_rename = os.rename
        tampered = []

        def _rename_once(src, dst):
            if (not tampered and isinstance(src, str)
                    and src.endswith(".tmp") and dst == pub_file):
                tampered.append(True)
                with open(src, "a", encoding="utf-8") as f:
                    f.write(failed_lines[0] + "\n")
            return real_rename(src, dst)

        with mock.patch("os.rename", side_effect=_rename_once):
            rc_e, res_e = run_publish(
                state_dir, clean14, rec_e_path, sha1,
                probe_db=probe_db, now=now_e,
                source_file=root + "/versions/v1.txt")
        check("e2_rename_tamper_refused", rc_e == 1
              and res_e.get("error") == "publish_postwrite_verify_failed",
              "rc=%d error=%s" % (rc_e, res_e.get("error")))
        check("e2_target_restored",
              bool(tampered) and sha_of(pub_file) == clean_sha[:12],
              "publish_sha=%s tampered=%s" % (sha_of(pub_file), tampered))
        step("E2 publish tmp tampered AT rename",
             "post-rename check refuses; previous bytes restored",
             publish_sha=sha_of(pub_file), rc=rc_e,
             error=res_e.get("error", ""))

        def _tamper_served(served_path):
            with open(served_path, "a", encoding="utf-8") as f:
                f.write(failed_lines[0] + "\n")

        rc_e, res_e = run_sync(
            state_dir, rec_e_path, sha1, probe_db=probe_db, now=now_e,
            post_copy_hook=_tamper_served)
        check("e3_served_tamper_refused", rc_e == 1
              and res_e.get("error") == "sync_served_gate_failed",
              "rc=%d error=%s" % (rc_e, res_e.get("error")))
        allowed, err, _st = gate_check(state_dir)
        check("e3_degraded_after_served_tamper",
              not allowed and err == "pool_stopped",
              "gate_check err=%s" % err)
        # D6 (GPT D5 review 6887615694, item 1): the polluted served
        # bytes no longer stay at the served path. They are quarantined
        # (mode 600) and the last verified version is restored; the
        # pool still stays STOP until manual recovery.
        _qr = res_e.get("served_quarantine") or {}
        _qdir = os.path.join(os.path.dirname(served_file), ".quarantine")
        # D7a: the C3 controlled repair already left one quarantine
        # file (the blind-copied v2 bytes), so pinpoint THIS run's
        # file by the quarantine_name the restore reported instead
        # of requiring exactly one file in the directory.
        _qname = _qr.get("quarantine_name") or ""
        _qpath = os.path.join(_qdir, _qname) if _qname else ""
        _qsha = sha_of(_qpath) if _qpath and os.path.exists(_qpath) else ""
        check("e3_served_quarantined_and_restored",
              res_e.get("served_restored") is True
              and sha_of(served_file) == clean_sha[:12]
              and _qname != ""
              and _qsha == (_qr.get("quarantined") or {}).get(
                  "sha_prefix", "")
              and (_qr.get("quarantined") or {}).get("lines") == 15,
              "served_sha=%s quarantine_name=%s restored=%s"
              % (sha_of(served_file), _qname, res_e.get("served_restored")))
        step("E3 sync served tampered post-copy",
             "served re-gate refuses; polluted bytes quarantined, "
             "last verified version restored, pool enters degraded",
             served_sha=sha_of(served_file), rc=rc_e,
             error=res_e.get("error", ""))

        ok = all(c["ok"] for c in checks)
        log = {"drill": "cross_cycle_drill",
               "sha": {"v1_source": sha1[:12], "v2_source": sha2[:12],
                       "v3_source": sha3[:12], "v4_source": sha4[:12],
                       "clean14_published": clean_sha[:12]},
               "steps": steps, "checks": checks,
               "passed": sum(1 for c in checks if c["ok"]),
               "total": len(checks), "ok": ok,
               "cycle_records": cycle_recs}
        print(json.dumps(log, indent=1, ensure_ascii=False))
        if args.out:
            with open(args.out, "w", encoding="utf-8") as f:
                json.dump(log, f, indent=1, ensure_ascii=False)
        return 0 if ok else 1
    finally:
        shutil.rmtree(root, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
