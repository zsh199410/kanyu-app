#!/usr/bin/env python3
"""D6 red->green demo (Issue #73, GPT D5 review 6887615694).

Runs the SAME fault injections on the OLD D5 tree and the NEW D6
tree, and records the actual exit codes + SHAs on both sides.

What is red on D5 (demonstrated, not asserted):
  R1 served post-copy tamper (in-process driver): on D5 the sync
     refuses with sync_served_gate_failed + STOP, but the polluted
     15 lines STAY at the canonical served path (only recorded).
     On D6 the same injection is refused the same way, but the
     polluted bytes are quarantined out of the served path (mode
     600) and the last chain-verified version is restored, so the
     served path never exposes polluted bytes again.
  R2a legacy $OLD copy failure (real gate-sync.sh): on D5 the run
     logs old_copy_failed and still exits rc=0 (fake success). On
     D6 the run exits rc=1 (legacy_copy_failed) and the bridge is
     rolled back to its pre-run bytes. On D7a the same break is
     intercepted one step earlier by gate-block
     (legacy_sha_mismatch -> targets_inconsistent, STOP latched);
     rc=1 and the bridge keeps its pre-run bytes.
  R2b SHA-check -> bridge-rename race (in-process driver): on D5
     pool.bridge_sync does not exist at all -- the bridge copy is a
     shell cp after the lock was released, so a served rewrite
     between the SHA check and the rename lands on the bridge
     unchecked. On D6 the same injection (hook rewrites served
     after the snapshot, before the bridge rename) still delivers
     only the verified snapshot bytes to the bridge, and the run
     fails rc=1 (served_changed_after_bridge_copy) with the served
     file quarantined + restored.
  R3 torn assembly exit code (real gate-publish.sh): on D5
     gate=0 + assembly=1 still exits 0, so a failed next-round
     assembly is indistinguishable from a healthy cycle. On D6
     the same run exits 2 with health=published_assembly_failed.

Old tree is READ-ONLY (~/workspace/p2p3-d5 or --d5-root; on the VPS
/opt/p2p3-d5). Nothing is written into it; the drivers run against
copies of its pool code in a tempdir.

Usage: python3 drills/d6_redgreen.py
       [--d5-root <path>] [--out docs/d6-redgreen-log.json]
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
# TREE=<tree root> and MODE=served|bridge. It seeds a clean v1
# publish+sync in a tempdir, then injects the fault.
DRIVER = r'''
import hashlib, json, os, sys, tempfile, types
TREE = os.environ["TREE"]
MODE = os.environ.get("MODE", "served")
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
def _sha_lines(lines):
    return hashlib.sha256(("\n".join(lines) + "\n").encode("utf-8")).hexdigest()
def _fp_of(line):
    from pool.phone_gate import parse_surge_line, fingerprint_of
    name, proto, host, port, params = parse_surge_line(line)
    return fingerprint_of(proto, host, port, params)
pool44 = _read_lines(os.path.join(FIX, "pool_44_fixture.txt"))
clean14 = _read_lines(os.path.join(FIX, "clean_14_fixture.txt"))
clean_fps = {_fp_of(l) for l in clean14}
failed_lines = [l for l in pool44 if _fp_of(l) not in clean_fps]
clean_sha = _sha_lines(clean14)
polluted_sha = _sha_lines(clean14 + [failed_lines[0]])
record = json.load(open(os.path.join(FIX, "native_results_fixture.json")))
version_sha = record["runs"][0]["version_sha"]
now = record["runs"][0]["tested_at"] + 3600
probe_db = os.path.join(FIX, "p0_fixture.db")
workdir = tempfile.mkdtemp(prefix="d6-rg-driver-")
rc, out = init_recovery_state(workdir, OWNER_ACK_INIT)
assert rc == 0, out
rc, res = run_publish(workdir, clean14, os.path.join(FIX, "native_results_fixture.json"), version_sha, probe_db=probe_db, now=now, source_file=os.path.join(FIX, "pool_44_fixture.txt"))
assert rc == 0, res
rc, res = run_sync(workdir, os.path.join(FIX, "native_results_fixture.json"), version_sha, probe_db=probe_db, now=now)
assert rc == 0, res
served = os.path.join(workdir, "served", "pool-new.txt")
if MODE == "served":
    def _tamper_served(p):
        with open(p, "a", encoding="utf-8") as f:
            f.write(failed_lines[0] + "\n")
    rc, res = run_sync(workdir, os.path.join(FIX, "native_results_fixture.json"), version_sha, probe_db=probe_db, now=now, post_copy_hook=_tamper_served)
    qdir = os.path.join(workdir, "served", ".quarantine")
    qtxt = [f for f in (os.listdir(qdir) if os.path.isdir(qdir) else []) if f.endswith(".txt")]
    qsha = _sha_file(os.path.join(qdir, qtxt[0]))[:12] if qtxt else ""
    allowed, err, _st = gate_check(workdir)
    print(json.dumps({"mode": "served", "rc": rc, "error": res.get("error"),
                      "served_sha_after": _sha_file(served)[:12],
                      "served_lines_after": len(_read_lines(served)),
                      "served_is_polluted": _sha_file(served)[:12] == polluted_sha[:12],
                      "served_is_clean": _sha_file(served)[:12] == clean_sha[:12],
                      "quarantine_files": qtxt, "quarantine_sha": qsha,
                      "quarantine_holds_polluted": qsha == polluted_sha[:12],
                      "degraded": (not allowed and err == "pool_stopped")}))
elif MODE == "bridge":
    try:
        from pool.bridge_sync import run_bridge_sync
    except ImportError as e:
        print(json.dumps({"mode": "bridge", "module_missing": True,
                          "import_error": str(e)[:160]}))
        sys.exit(0)
    bridge = os.path.join(workdir, "bridge")
    os.makedirs(bridge, exist_ok=True)
    def _rewrite_served(_tmp_path):
        with open(served, "a", encoding="utf-8") as f:
            f.write(failed_lines[0] + "\n")
    rc, res = run_bridge_sync(workdir, bridge,
                              native_record_path=os.path.join(FIX, "native_results_fixture.json"),
                              probe_db=probe_db, now=now,
                              pre_bridge_rename_hook=_rewrite_served)
    print(json.dumps({"mode": "bridge", "module_missing": False, "rc": rc,
                      "error": res.get("error"),
                      "bridge_sha": _sha_file(os.path.join(bridge, "pool-new.txt"))[:12] if os.path.exists(os.path.join(bridge, "pool-new.txt")) else "",
                      "bridge_is_clean": _sha_file(os.path.join(bridge, "pool-new.txt"))[:12] == clean_sha[:12] if os.path.exists(os.path.join(bridge, "pool-new.txt")) else False,
                      "served_is_clean": _sha_file(served)[:12] == clean_sha[:12],
                      "served_restored": res.get("served_restored")}))
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
                               "d6-rg-driver-%d.py" % os.getpid())
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


def _build_wrapper_root(tree, root):
    """Copy one tree's pool + systemd scripts into a temp wrapper
    root (the tree itself is only read). Returns the env dict."""
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
    failed_lines = [l for l in pool44 if fp_of_line(l) not in clean_fps]
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
else:
    print("unknown mode", file=sys.stderr)
    sys.exit(1)
'''
    stub_path = prog + "/venv/bin/python"
    with open(stub_path, "w") as _f:
        _f.write(stub)
    os.chmod(stub_path, 0o755)
    shutil.copyfile(root + "/versions/v1.txt",
                    prog + "/publish/pool-new.txt")
    with open(prog + "/.asm_mode", "w") as _f:
        _f.write("2")
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
    return {"root": root, "prog": prog, "gate": gate, "bridge": bridge,
            "env": env, "clean_sha": clean_sha, "sha1": sha1, "sha2": sha2}


def wrapper_legacy(tree, label):
    """Publish+sync clean, then break the legacy manifest and run
    gate-sync.sh again. Returns rcs + SHAs + log markers."""
    root = tempfile.mkdtemp(prefix="d6-rg-legacy-")
    try:
        ctx = _build_wrapper_root(tree, root)
        gate, bridge, env = ctx["gate"], ctx["bridge"], ctx["env"]

        def run_wrapper(name):
            p = subprocess.run(["bash", gate + "/" + name],
                               capture_output=True, text=True, env=env,
                               timeout=120)
            return p.returncode

        def sha_of(path):
            return sha256_file(path)[:12] if os.path.exists(path) else ""

        p = subprocess.run(
            [sys.executable, "-m", "pool.recovery", "init",
             "--workdir", gate + "/state",
             "--owner-ack", OWNER_ACK_INIT],
            capture_output=True, text=True, cwd=gate, timeout=60)
        out = {"tree": label, "init_rc": p.returncode}
        out["publish_rc"] = run_wrapper("gate-publish.sh")
        out["sync_rc"] = run_wrapper("gate-sync.sh")
        out["bridge_before_break"] = sha_of(bridge + "/pool-new.txt")
        out["legacy_before_break"] = sha_of(bridge + "/old-pool.txt")
        with open(ctx["prog"] + "/config/old-pool-file.txt", "w") as f:
            f.write(bridge + "/no-such-dir/old-pool.txt")
        out["sync_after_break_rc"] = run_wrapper("gate-sync.sh")
        slog = open(gate + "/logs/gate-sync.log").read()
        out["log_has_old_copy_failed"] = "old_copy_failed" in slog
        out["log_has_legacy_copy_failed"] = "legacy_copy_failed" in slog
        out["log_has_gate_block_refused"] = "gate_block_refused" in slog
        out["bridge_after_break"] = sha_of(bridge + "/pool-new.txt")
        out["legacy_written"] = os.path.exists(
            bridge + "/no-such-dir/old-pool.txt")
        out["clean_sha"] = ctx["clean_sha"][:12]
        return out
    finally:
        shutil.rmtree(root, ignore_errors=True)


def wrapper_publish_exit(tree, label):
    """Gate passes v1, assembler crashes with a torn $SRC. Returns
    the exit code + health file + publish SHA."""
    root = tempfile.mkdtemp(prefix="d6-rg-pubexit-")
    try:
        ctx = _build_wrapper_root(tree, root)
        gate, env = ctx["gate"], ctx["env"]
        prog = ctx["prog"]

        def run_wrapper(name):
            p = subprocess.run(["bash", gate + "/" + name],
                               capture_output=True, text=True, env=env,
                               timeout=120)
            return p.returncode

        def sha_of(path):
            return sha256_file(path)[:12] if os.path.exists(path) else ""

        p = subprocess.run(
            [sys.executable, "-m", "pool.recovery", "init",
             "--workdir", gate + "/state",
             "--owner-ack", OWNER_ACK_INIT],
            capture_output=True, text=True, cwd=gate, timeout=60)
        out = {"tree": label, "init_rc": p.returncode}
        with open(prog + "/.asm_mode", "w") as _f:
            _f.write("torn")
        shutil.copyfile(root + "/versions/v1.txt",
                        prog + "/publish/pool-new.txt")
        out["publish_rc"] = run_wrapper("gate-publish.sh")
        hpath = gate + "/logs/health.json"
        out["health"] = json.load(open(hpath)) if os.path.exists(hpath) \
            else None
        out["publish_sha"] = sha_of(gate + "/state/publish/pool-new.txt")
        out["clean_sha"] = ctx["clean_sha"][:12]
        return out
    finally:
        shutil.rmtree(root, ignore_errors=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--d5-root", default=os.path.join(
        os.path.dirname(HERE), "p2p3-d5"))
    ap.add_argument("--out", default=None)
    args = ap.parse_args()
    d5_root = args.d5_root
    checks = []
    phases = {}

    def check(name, ok, detail=""):
        checks.append({"check": name, "ok": bool(ok), "detail": str(detail)})
        return bool(ok)

    # ---- R1: served post-copy tamper, old vs new ----
    old_r1 = run_driver(d5_root, "served")
    new_r1 = run_driver(HERE, "served")
    phases["r1_served_tamper_old"] = old_r1
    phases["r1_served_tamper_new"] = new_r1
    check("r1_old_served_keeps_polluted_RED",
          old_r1.get("rc") == 1
          and old_r1.get("error") == "sync_served_gate_failed"
          and old_r1.get("served_is_polluted") is True
          and old_r1.get("quarantine_files") == [],
          "rc=%s error=%s served_sha=%s lines=%s quarantine=%s"
          % (old_r1.get("rc"), old_r1.get("error"),
             old_r1.get("served_sha_after"),
             old_r1.get("served_lines_after"),
             old_r1.get("quarantine_files")))
    check("r1_new_served_quarantined_and_restored_GREEN",
          new_r1.get("rc") == 1
          and new_r1.get("error") == "sync_served_gate_failed"
          and new_r1.get("served_is_clean") is True
          and new_r1.get("quarantine_holds_polluted") is True
          and new_r1.get("degraded") is True,
          "rc=%s error=%s served_sha=%s quarantine=%s degraded=%s"
          % (new_r1.get("rc"), new_r1.get("error"),
             new_r1.get("served_sha_after"),
             new_r1.get("quarantine_files"), new_r1.get("degraded")))

    # ---- R2b: bridge race, old vs new ----
    old_r2b = run_driver(d5_root, "bridge")
    new_r2b = run_driver(HERE, "bridge")
    phases["r2b_bridge_race_old"] = old_r2b
    phases["r2b_bridge_race_new"] = new_r2b
    check("r2b_old_no_bridge_sync_module_RED",
          old_r2b.get("module_missing") is True,
          "import_error=%s" % old_r2b.get("import_error", ""))
    check("r2b_new_snapshot_only_verified_bytes_GREEN",
          new_r2b.get("module_missing") is False
          and new_r2b.get("rc") == 1
          and new_r2b.get("error") == "served_changed_after_bridge_copy"
          and new_r2b.get("bridge_is_clean") is True
          and new_r2b.get("served_restored") is True,
          "rc=%s error=%s bridge_clean=%s served_restored=%s"
          % (new_r2b.get("rc"), new_r2b.get("error"),
             new_r2b.get("bridge_is_clean"),
             new_r2b.get("served_restored")))

    # ---- R2a: legacy copy failure, old vs new (real wrappers) ----
    old_r2a = wrapper_legacy(d5_root, "d5-old")
    new_r2a = wrapper_legacy(HERE, "d6-new")
    phases["r2a_legacy_failure_old"] = old_r2a
    phases["r2a_legacy_failure_new"] = new_r2a
    check("r2a_old_legacy_failure_exits_0_RED",
          old_r2a.get("sync_after_break_rc") == 0
          and old_r2a.get("log_has_old_copy_failed") is True,
          "rc=%s old_copy_failed=%s"
          % (old_r2a.get("sync_after_break_rc"),
             old_r2a.get("log_has_old_copy_failed")))
    # D7a (GPT D7 review 6912114134, item 1): the missing legacy
    # target is intercepted by gate-block (targets_inconsistent)
    # BEFORE the copy is attempted, so the D6 legacy_copy_failed
    # marker no longer appears; the invariants (rc=1, bridge keeps
    # pre-run verified bytes, legacy never written, no fake
    # success) are unchanged.
    check("r2a_new_legacy_failure_exits_1_and_rolls_back_GREEN",
          new_r2a.get("sync_after_break_rc") == 1
          and new_r2a.get("log_has_gate_block_refused") is True
          and new_r2a.get("bridge_after_break") == new_r2a.get("clean_sha")
          and new_r2a.get("legacy_written") is False,
          "rc=%s gate_block_refused=%s bridge=%s legacy_written=%s"
          % (new_r2a.get("sync_after_break_rc"),
             new_r2a.get("log_has_gate_block_refused"),
             new_r2a.get("bridge_after_break"),
             new_r2a.get("legacy_written")))

    # ---- R3: torn assembly exit code, old vs new (real wrappers) ----
    old_r3 = wrapper_publish_exit(d5_root, "d5-old")
    new_r3 = wrapper_publish_exit(HERE, "d6-new")
    phases["r3_publish_exit_old"] = old_r3
    phases["r3_publish_exit_new"] = new_r3
    check("r3_old_torn_assembly_exits_0_RED",
          old_r3.get("publish_rc") == 0 and old_r3.get("health") is None,
          "rc=%s health=%s" % (old_r3.get("publish_rc"),
                               old_r3.get("health")))
    check("r3_new_torn_assembly_exits_2_GREEN",
          new_r3.get("publish_rc") == 2
          and (new_r3.get("health") or {}).get("health")
          == "published_assembly_failed"
          and new_r3.get("publish_sha") == new_r3.get("clean_sha"),
          "rc=%s health=%s publish_sha=%s"
          % (new_r3.get("publish_rc"), new_r3.get("health"),
             new_r3.get("publish_sha")))

    # ---- Grep: code-level presence/absence ----
    grep = {
        "old_bridge_sync_module":
            os.path.exists(os.path.join(d5_root, "pool", "bridge_sync.py")),
        "new_bridge_sync_module":
            os.path.exists(os.path.join(HERE, "pool", "bridge_sync.py")),
        "old_sync_quarantine":
            grep_count(os.path.join(d5_root, "pool", "sync.py"),
                       "served_quarantine"),
        "new_sync_quarantine":
            grep_count(os.path.join(HERE, "pool", "sync.py"),
                       "served_quarantine"),
        "old_publish_assembly_failed":
            grep_count(os.path.join(d5_root, "systemd", "gate-publish.sh"),
                       "published_assembly_failed"),
        "new_publish_assembly_failed":
            grep_count(os.path.join(HERE, "systemd", "gate-publish.sh"),
                       "published_assembly_failed"),
        "old_sync_legacy_copy_failed":
            grep_count(os.path.join(d5_root, "pool", "bridge_sync.py"),
                       "legacy_copy_failed"),
        "new_sync_legacy_copy_failed":
            grep_count(os.path.join(HERE, "pool", "bridge_sync.py"),
                       "legacy_copy_failed"),
    }
    phases["grep"] = grep
    check("grep_old_has_no_d6_markers",
          grep["old_bridge_sync_module"] is False
          and grep["old_sync_quarantine"] == 0
          and grep["old_publish_assembly_failed"] == 0
          and grep["old_sync_legacy_copy_failed"] <= 0,
          str(grep))
    check("grep_new_has_d6_markers",
          grep["new_bridge_sync_module"] is True
          and grep["new_sync_quarantine"] > 0
          and grep["new_publish_assembly_failed"] > 0
          and grep["new_sync_legacy_copy_failed"] > 0,
          str(grep))

    ok = all(c["ok"] for c in checks)
    log = {"drill": "d6_redgreen", "d5_root": d5_root,
           "d6_root": HERE, "phases": phases, "checks": checks,
           "passed": sum(1 for c in checks if c["ok"]),
           "total": len(checks), "ok": ok}
    print(json.dumps(log, indent=1, ensure_ascii=False))
    if args.out:
        with open(args.out, "w", encoding="utf-8") as f:
            json.dump(log, f, indent=1, ensure_ascii=False)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
