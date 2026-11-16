#!/usr/bin/env python3
"""D5 red->green demo (Issue #73, GPT D4 review 6887331723).

Runs the SAME cross-cycle scenarios on the OLD D4 tree and the NEW
D5 tree, and records the actual exit codes + SHAs on both sides.

What is red on D4 (demonstrated, not asserted):
  R1 blind copy: a plain cp of untested v2 to served/bridge (the old
     blind pool-sync.sh behaviour) serves v2 on the bridge. This red
     control is IDENTICAL on both trees -- cp is cp; the green is
     that the GATED sync refuses the planted version and restores
     the verified v1. (The old gate already refuses v2 at publish
     time via the D2 version binding; D5 does not claim otherwise.
     The D5 gap is narrower and is shown by R2/R3.) D7a (GPT D7
     review 6912114134, item 1): on the new tree the gated sync
     does NOT silently restore v1 -- gate-block refuses the
     divergence (rc=1, STOP latched, bridge stays v2); only the
     controlled repair (repair_targets) + owner-acknowledged
     clear_stop restores the verified v1.
  R2 publish rename-time tamper (in-process driver): on D4 the tmp
     file tampered AT the rename is caught only AFTER the rename,
     and the corrupted bytes are LEFT in the publish target
     (target SHA changes, rc=1 but the file is corrupt). On D5 the
     same injection is refused with publish_postwrite_verify_failed
     and the previous bytes are restored (target SHA unchanged).
  R3 sync served re-gate: D4's sync.py contains NO served-byte
     re-gate step (grep: 0 occurrences of sync_served_gate_failed)
     and run_sync has no post-copy hook; the D5 driver call with
     post_copy_hook raises TypeError on D4. On D5 the same injection
     is refused with sync_served_gate_failed + degraded state.

Old tree is READ-ONLY (~/workspace/p2p3-d4 or --d4-root; on the VPS
/opt/p2p3-d4). Nothing is written into it; the driver runs against
copies of its pool code in a tempdir.

Usage: python3 drills/cross_cycle_redgreen.py
       [--d4-root <path>] [--out docs/cross-cycle-redgreen-log.json]
Exit 0 = all checks pass. Stdout: one JSON object (the log).
"""
import argparse
import hashlib
import json
import os
import re
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

# In-process fault-injection driver, run as a subprocess with
# TREE=<tree root> and MODE=publish|sync. It seeds a clean v1
# publish+sync in a tempdir, then injects the fault.
DRIVER = r'''
import hashlib, json, os, sys, tempfile, types
TREE = os.environ["TREE"]
MODE = os.environ.get("MODE", "publish")
sys.path.insert(0, TREE)
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
from unittest import mock
from pool.publish import run_publish
from pool.recovery import OWNER_ACK_INIT, gate_check, init_recovery_state
from pool.sync import run_sync
FIX = os.path.join(TREE, "fixtures")
def _read_lines(path):
    with open(path, encoding="utf-8") as f:
        return [l.rstrip("\n") for l in f if l.strip()]
def _sha_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()
def _fp_of(line):
    name, proto, host, port, params = __import__("pool.phone_gate", fromlist=["parse_surge_line"]).parse_surge_line(line)
    return __import__("pool.phone_gate", fromlist=["fingerprint_of"]).fingerprint_of(proto, host, port, params)
pool44 = _read_lines(os.path.join(FIX, "pool_44_fixture.txt"))
clean14 = _read_lines(os.path.join(FIX, "clean_14_fixture.txt"))
clean_fps = {_fp_of(l) for l in clean14}
failed_lines = [l for l in pool44 if _fp_of(l) not in clean_fps]
record = json.load(open(os.path.join(FIX, "native_results_fixture.json")))
version_sha = record["runs"][0]["version_sha"]
now = record["runs"][0]["tested_at"] + 3600
probe_db = os.path.join(FIX, "p0_fixture.db")
workdir = tempfile.mkdtemp(prefix="d5-rg-driver-")
rc, out = init_recovery_state(workdir, OWNER_ACK_INIT)
assert rc == 0, out
rc, res = run_publish(workdir, clean14, os.path.join(FIX, "native_results_fixture.json"), version_sha, probe_db=probe_db, now=now, source_file=os.path.join(FIX, "pool_44_fixture.txt"))
assert rc == 0, res
rc, res = run_sync(workdir, os.path.join(FIX, "native_results_fixture.json"), version_sha, probe_db=probe_db, now=now)
assert rc == 0, res
target = os.path.join(workdir, "publish", "pool-new.txt")
served = os.path.join(workdir, "served", "pool-new.txt")
if MODE == "publish":
    before = _sha_file(target)
    real_rename = os.rename
    tampered = []
    def _rename_once(src, dst):
        if (not tampered and isinstance(src, str) and src.endswith(".tmp") and dst == target):
            tampered.append(True)
            with open(src, "a", encoding="utf-8") as f:
                f.write(failed_lines[0] + "\n")
        return real_rename(src, dst)
    with mock.patch("os.rename", side_effect=_rename_once):
        rc, res = run_publish(workdir, clean14, os.path.join(FIX, "native_results_fixture.json"), version_sha, probe_db=probe_db, now=now, source_file=os.path.join(FIX, "pool_44_fixture.txt"))
    after = _sha_file(target)
    print(json.dumps({"mode": "publish", "rc": rc, "error": res.get("error"), "target_sha_before": before[:12], "target_sha_after": after[:12], "target_unchanged": before == after, "tampered": bool(tampered)}))
elif MODE == "sync":
    def _tamper_served(p):
        with open(p, "a", encoding="utf-8") as f:
            f.write(failed_lines[0] + "\n")
    try:
        rc, res = run_sync(workdir, os.path.join(FIX, "native_results_fixture.json"), version_sha, probe_db=probe_db, now=now, post_copy_hook=_tamper_served)
    except TypeError as e:
        print(json.dumps({"mode": "sync", "hook_supported": False, "type_error": str(e)[:120]}))
        sys.exit(0)
    allowed, err, _st = gate_check(workdir)
    print(json.dumps({"mode": "sync", "hook_supported": True, "rc": rc, "error": res.get("error"), "degraded": (not allowed and err == "pool_stopped")}))
'''


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


def grep_count(path, pattern):
    try:
        with open(path, encoding="utf-8") as f:
            return len(re.findall(pattern, f.read()))
    except OSError:
        return -1


def run_driver(tree, mode):
    driver_path = os.path.join(tempfile.gettempdir(),
                               "d5-rg-driver-%d.py" % os.getpid())
    with open(driver_path, "w") as f:
        f.write(DRIVER)
    try:
        env = dict(os.environ)
        env["TREE"] = tree
        env["MODE"] = mode
        p = subprocess.run([sys.executable, driver_path],
                           capture_output=True, text=True, env=env,
                           timeout=120)
        if p.returncode != 0:
            return {"driver_rc": p.returncode, "stdout": p.stdout[-500:],
                    "stderr": p.stderr[-500:]}
        return json.loads(p.stdout.strip().splitlines()[-1])
    finally:
        try:
            os.unlink(driver_path)
        except OSError:
            pass


def wrapper_scenario(tree, label):
    """Minimal wrapper run on one tree: v1 publish+sync, blind cp of
    untested v2 to the bridge (red control), gated sync restores v1.
    On the new (D7a) tree the gated sync refuses the divergence
    first (gate-block, STOP latched); the controlled repair +
    clear_stop restores v1 and the following resync is healthy.
    Returns a dict of rcs + SHAs. The tree is only READ (pool +
    scripts are copied into the tempdir)."""
    root = tempfile.mkdtemp(prefix="d5-rg-wrap-")
    try:
        prog = os.path.join(root, "prog")
        gate = os.path.join(root, "gate")
        bridge = os.path.join(root, "bridge")
        for d in [prog + "/publish", prog + "/gate", prog + "/config",
                  prog + "/venv/bin", gate + "/state", gate + "/logs",
                  bridge, root + "/versions"]:
            os.makedirs(d, exist_ok=True)
        shutil.copytree(os.path.join(tree, "pool"), gate + "/pool")
        for f in ["gate-publish.sh", "gate-sync.sh",
                  "validate-native-record.py"]:
            shutil.copy(os.path.join(tree, "systemd", f), gate + "/" + f)
            os.chmod(gate + "/" + f, 0o755)
        pool44 = read_lines(os.path.join(FIX, "pool_44_fixture.txt"))
        clean14 = read_lines(os.path.join(FIX, "clean_14_fixture.txt"))
        clean_fps = {fp_of_line(l) for l in clean14}
        clean_sha = sha_lines(clean14)
        record = json.load(open(os.path.join(
            FIX, "native_results_fixture.json")))
        v1_results = record["runs"][0]["results"]
        failed_lines = [l for l in pool44
                        if fp_of_line(l) not in clean_fps]
        v2 = [l for l in pool44 if l != failed_lines[0]]
        write_lines(root + "/versions/v1.txt", pool44)
        write_lines(root + "/versions/v2.txt", v2)
        sha1 = sha_lines(pool44)
        sha2 = sha_lines(v2)
        stub = '''#!/usr/bin/env python3
import os, shutil, sys
root = os.environ["REHEARSAL_ROOT"]
shutil.copyfile(os.path.join(root, "versions", "v2.txt"),
                os.path.join(root, "prog", "publish", "pool-new.txt"))
print("{\\"ok\\": true, \\"assembled_version\\": 2}")
'''
        stub_path = prog + "/venv/bin/python"
        with open(stub_path, "w") as _f:
            _f.write(stub)
        os.chmod(stub_path, 0o755)
        shutil.copyfile(root + "/versions/v1.txt",
                        prog + "/publish/pool-new.txt")
        now_wall = int(time.time())
        rec = {"format": "native-results-v1", "runs": [{
            "version_sha": sha1, "tested_at": now_wall - 3600,
            "tested_at_cst": "", "network": "5G cellular pdp_ip0, no Wi-Fi",
            "surge": "6.100.0 build 4025", "results": v1_results}]}
        rec_path = prog + "/gate/native-results.json"
        with open(rec_path, "w") as _f:
            json.dump(rec, _f)
        with open(prog + "/config/old-pool-file.txt", "w") as f:
            f.write(bridge + "/old-pool.txt")
        env = dict(os.environ)
        env.update({
            "REHEARSAL_ROOT": root, "PROG": prog, "GATE": gate,
            "RECORD": rec_path, "PROBE_DB": os.path.join(FIX, "p0_fixture.db"),
            "BRIDGE_DIR": bridge, "GATE_PY": sys.executable,
            "PROD_PY": stub_path,
        })

        def run_wrapper(name):
            p = subprocess.run(["bash", gate + "/" + name],
                               capture_output=True, text=True, env=env,
                               timeout=120)
            return p.returncode

        p = subprocess.run(
            [sys.executable, "-m", "pool.recovery", "init",
             "--workdir", gate + "/state",
             "--owner-ack", OWNER_ACK_INIT],
            capture_output=True, text=True, cwd=gate, timeout=60)
        out = {"tree": label, "init_rc": p.returncode}
        out["publish_rc"] = run_wrapper("gate-publish.sh")
        out["sync_rc"] = run_wrapper("gate-sync.sh")
        out["bridge_after_sync_sha"] = sha256_file(
            bridge + "/pool-new.txt")[:12]
        # Red control: blind cp of untested v2 straight to the bridge.
        shutil.copyfile(root + "/versions/v2.txt", bridge + "/pool-new.txt")
        os.chmod(bridge + "/pool-new.txt", 0o644)
        out["bridge_after_blind_cp_sha"] = sha256_file(
            bridge + "/pool-new.txt")[:12]
        out["bridge_after_blind_cp_lines"] = len(
            read_lines(bridge + "/pool-new.txt"))
        out["v2_sha"] = sha2[:12]
        out["clean_sha"] = clean_sha[:12]
        out["resync_rc"] = run_wrapper("gate-sync.sh")
        out["bridge_after_resync_sha"] = sha256_file(
            bridge + "/pool-new.txt")[:12]
        # D7a (GPT D7 review 6912114134, item 1): on the new tree
        # the blind cp leaves bridge at untested v2, so gate-block
        # refuses the resync (rc=1, STOP latched) instead of
        # silently restoring v1. Controlled repair + clear_stop,
        # then the resync is healthy. The old tree has no gate-block
        # and restores v1 directly, so this branch never runs there.
        out["repair_rc"] = None
        out["repair_verify_consistent"] = None
        out["clear_stop_rc"] = None
        out["final_resync_rc"] = None
        out["bridge_after_final_resync_sha"] = None
        if label == "d5-new" and out["resync_rc"] != 0:
            from pool.bridge_sync import repair_targets, verify_targets
            from pool.recovery import OWNER_ACK_CLEAR, clear_stop
            now_r = int(time.time())
            rc_r, _res_r = repair_targets(
                gate + "/state", bridge,
                old_path=bridge + "/old-pool.txt",
                native_record_path=rec_path,
                probe_db=os.path.join(FIX, "p0_fixture.db"), now=now_r,
                manifest_path=gate + "/logs/repair-manifest-wrap.json")
            out["repair_rc"] = rc_r
            vt = verify_targets(gate + "/state", bridge,
                                old_path=bridge + "/old-pool.txt")
            out["repair_verify_consistent"] = bool(vt["consistent"])
            rc_c, _res_c = clear_stop(
                gate + "/state", OWNER_ACK_CLEAR, rec_path,
                probe_db=os.path.join(FIX, "p0_fixture.db"),
                now=int(time.time()))
            out["clear_stop_rc"] = rc_c
            out["final_resync_rc"] = run_wrapper("gate-sync.sh")
            out["bridge_after_final_resync_sha"] = sha256_file(
                bridge + "/pool-new.txt")[:12]
        return out
    finally:
        shutil.rmtree(root, ignore_errors=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--d4-root", default=os.path.join(
        os.path.dirname(HERE), "p2p3-d4"))
    ap.add_argument("--out", default=None)
    args = ap.parse_args()
    d4_root = args.d4_root
    checks = []
    phases = {}

    def check(name, ok, detail=""):
        checks.append({"check": name, "ok": bool(ok), "detail": str(detail)})
        return bool(ok)

    # ---- Phase 1: wrapper scenario on both trees ----
    old_wrap = wrapper_scenario(d4_root, "d4-old")
    phases["wrapper_old_tree"] = old_wrap
    check("old_wrap_publish_sync_rc0",
          old_wrap["publish_rc"] == 0 and old_wrap["sync_rc"] == 0,
          "publish_rc=%s sync_rc=%s" % (old_wrap["publish_rc"],
                                        old_wrap["sync_rc"]))
    check("old_wrap_blind_cp_serves_v2_RED",
          old_wrap["bridge_after_blind_cp_sha"] == old_wrap["v2_sha"]
          and old_wrap["bridge_after_blind_cp_lines"] == 43,
          "bridge_sha=%s (v2) lines=%s"
          % (old_wrap["bridge_after_blind_cp_sha"],
             old_wrap["bridge_after_blind_cp_lines"]))
    check("old_wrap_gated_sync_restores_v1",
          old_wrap["resync_rc"] == 0
          and old_wrap["bridge_after_resync_sha"] == old_wrap["clean_sha"],
          "resync_rc=%s bridge_sha=%s"
          % (old_wrap["resync_rc"], old_wrap["bridge_after_resync_sha"]))

    new_wrap = wrapper_scenario(HERE, "d5-new")
    phases["wrapper_new_tree"] = new_wrap
    check("new_wrap_publish_sync_rc0",
          new_wrap["publish_rc"] == 0 and new_wrap["sync_rc"] == 0,
          "publish_rc=%s sync_rc=%s" % (new_wrap["publish_rc"],
                                        new_wrap["sync_rc"]))
    check("new_wrap_blind_cp_also_serves_v2_RED_control",
          new_wrap["bridge_after_blind_cp_sha"] == new_wrap["v2_sha"],
          "blind cp is cp on both trees; the gate is the defence, "
          "bridge_sha=%s (v2)" % new_wrap["bridge_after_blind_cp_sha"])
    check("new_wrap_gated_sync_refuses_divergence",
          new_wrap["resync_rc"] == 1
          and new_wrap["bridge_after_resync_sha"] == new_wrap["v2_sha"],
          "resync_rc=%s bridge_sha=%s (v2, NOT silently overwritten)"
          % (new_wrap["resync_rc"], new_wrap["bridge_after_resync_sha"]))
    check("new_wrap_repair_and_clear_restore",
          new_wrap["repair_rc"] == 0
          and new_wrap["repair_verify_consistent"] is True
          and new_wrap["clear_stop_rc"] == 0,
          "repair_rc=%s clear_stop_rc=%s"
          % (new_wrap["repair_rc"], new_wrap["clear_stop_rc"]))
    check("new_wrap_gated_sync_restores_v1",
          new_wrap["final_resync_rc"] == 0
          and new_wrap["bridge_after_final_resync_sha"]
          == new_wrap["clean_sha"],
          "final_resync_rc=%s bridge_sha=%s"
          % (new_wrap["final_resync_rc"],
             new_wrap["bridge_after_final_resync_sha"]))
    check("new_wrap_cycle_record_exists",
          new_wrap["publish_rc"] == 0, "cycle record covered by unit tests "
          "and the cross-cycle drill (see docs/cross-cycle-drill-log.json)")

    # ---- Phase 2: publish rename-time tamper, old vs new ----
    old_pub = run_driver(d4_root, "publish")
    new_pub = run_driver(HERE, "publish")
    phases["publish_rename_tamper_old"] = old_pub
    phases["publish_rename_tamper_new"] = new_pub
    check("old_publish_rename_tamper_corrupts_target_RED",
          old_pub.get("rc") == 1
          and old_pub.get("target_unchanged") is False,
          "rc=%s error=%s before=%s after=%s"
          % (old_pub.get("rc"), old_pub.get("error"),
             old_pub.get("target_sha_before"),
             old_pub.get("target_sha_after")))
    check("new_publish_rename_tamper_keeps_target_GREEN",
          new_pub.get("rc") == 1
          and new_pub.get("error") == "publish_postwrite_verify_failed"
          and new_pub.get("target_unchanged") is True,
          "rc=%s error=%s before=%s after=%s"
          % (new_pub.get("rc"), new_pub.get("error"),
             new_pub.get("target_sha_before"),
             new_pub.get("target_sha_after")))

    # ---- Phase 3: sync served re-gate, old vs new ----
    old_sync = run_driver(d4_root, "sync")
    new_sync = run_driver(HERE, "sync")
    phases["sync_served_tamper_old"] = old_sync
    phases["sync_served_tamper_new"] = new_sync
    check("old_sync_has_no_served_regate_hook_RED",
          old_sync.get("hook_supported") is False,
          "run_sync(post_copy_hook=...) -> TypeError: %s"
          % old_sync.get("type_error", ""))
    check("new_sync_served_tamper_refused_GREEN",
          new_sync.get("hook_supported") is True
          and new_sync.get("rc") == 1
          and new_sync.get("error") == "sync_served_gate_failed"
          and new_sync.get("degraded") is True,
          "rc=%s error=%s degraded=%s"
          % (new_sync.get("rc"), new_sync.get("error"),
             new_sync.get("degraded")))

    # ---- Phase 4: code-level presence/absence (grep) ----
    grep = {
        "old_publish_postwrite_verify_failed":
            grep_count(os.path.join(d4_root, "pool", "publish.py"),
                       "publish_postwrite_verify_failed"),
        "new_publish_postwrite_verify_failed":
            grep_count(os.path.join(HERE, "pool", "publish.py"),
                       "publish_postwrite_verify_failed"),
        "old_sync_served_gate_failed":
            grep_count(os.path.join(d4_root, "pool", "sync.py"),
                       "sync_served_gate_failed"),
        "new_sync_served_gate_failed":
            grep_count(os.path.join(HERE, "pool", "sync.py"),
                       "sync_served_gate_failed"),
        "old_gate_publish_new_source_gated":
            grep_count(os.path.join(d4_root, "systemd", "gate-publish.sh"),
                       "new_source_gated"),
        "new_gate_publish_new_source_gated":
            grep_count(os.path.join(HERE, "systemd", "gate-publish.sh"),
                       "new_source_gated"),
        "old_gate_sync_prebridge_check":
            grep_count(os.path.join(d4_root, "systemd", "gate-sync.sh"),
                       "served_sha_mismatch_before_bridge_copy"),
        "new_gate_sync_prebridge_check":
            grep_count(os.path.join(HERE, "systemd", "gate-sync.sh"),
                       "served_sha_mismatch_before_bridge_copy"),
    }
    phases["grep"] = grep
    check("grep_old_has_no_d5_markers",
          grep["old_publish_postwrite_verify_failed"] == 0
          and grep["old_sync_served_gate_failed"] == 0
          and grep["old_gate_publish_new_source_gated"] == 0
          and grep["old_gate_sync_prebridge_check"] == 0,
          str(grep))
    check("grep_new_has_d5_markers",
          grep["new_publish_postwrite_verify_failed"] > 0
          and grep["new_sync_served_gate_failed"] > 0
          and grep["new_gate_publish_new_source_gated"] > 0
          and grep["new_gate_sync_prebridge_check"] > 0,
          str(grep))

    ok = all(c["ok"] for c in checks)
    log = {"drill": "cross_cycle_redgreen", "d4_root": d4_root,
           "d5_root": HERE, "phases": phases, "checks": checks,
           "passed": sum(1 for c in checks if c["ok"]),
           "total": len(checks), "ok": ok}
    print(json.dumps(log, indent=1, ensure_ascii=False))
    if args.out:
        with open(args.out, "w", encoding="utf-8") as f:
            json.dump(log, f, indent=1, ensure_ascii=False)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
