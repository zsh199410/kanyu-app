"""D1 timer simulation drill (GPT 6875033415 item 4).

Simulates the production timers against the D1 paths, as separate
PROCESSES (like systemd would spawn them):
  - :07 publish  (python3 -m pool.publish, gated, shared lock)
  - :00/:15/:30/:45 sync (python3 -m pool.sync, gated, SAME lock)
fired concurrently with jitter, over N cycles, plus:
  - lock-contention probe: while a holder owns the lock, a publish
    with a 1 s timeout MUST fail with lock_timeout (mutual exclusion
    for lock-aware writers)
  - legacy-writer backstop: a lock-UNAWARE legacy write drops the
    ungated 44-line file directly into publish/ (exactly what the old
    production code would do -- it does not know the lock); the next
    sync MUST refuse it and the served file MUST stay clean. This is
    the honest threat model: the lock serialises lock-aware writers;
    the sync gate is the backstop for lock-unaware writers.
  - next-:07 check: one more publish cycle after everything, the file
    MUST still be the clean 14-line set (no 21+23 restore).

Exit code 0 = all checks passed, 1 = any failed.
Writes a JSON log (desensitised: counts, SHA prefixes only).

Usage:
  python3 drills/sim_timers.py --workdir <dir> --cycles 3
      --candidates <44-line file> --clean <14-line file>
      --native-record <file> --source-version <sha256>
      [--probe-db <file>] [--log <file>]
"""

import argparse
import hashlib
import json
import os
import random
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
D1_ROOT = os.path.dirname(HERE)
sys.path.insert(0, D1_ROOT)

from pool.publish_lock import file_manifest  # noqa: E402


def _sha_prefix(path):
    m = file_manifest(path)
    return m["sha_prefix"] if m else None


def _run(cmd, cwd):
    t0 = time.time()
    p = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True,
                       timeout=120)
    try:
        out = json.loads(p.stdout.strip().splitlines()[-1]) if p.stdout.strip() else {}
    except (ValueError, IndexError):
        out = {"unparsable_stdout": p.stdout[:200], "stderr": p.stderr[:200]}
    return {"rc": p.returncode, "elapsed_s": round(time.time() - t0, 2),
            "out": out}


def main(argv=None):
    ap = argparse.ArgumentParser(description="D1 timer simulation drill")
    ap.add_argument("--workdir", required=True)
    ap.add_argument("--cycles", type=int, default=3)
    ap.add_argument("--candidates", required=True)
    ap.add_argument("--clean", required=True)
    ap.add_argument("--native-record", required=True)
    ap.add_argument("--source-version", required=True)
    ap.add_argument("--probe-db", default=None)
    ap.add_argument("--log", default=None)
    args = ap.parse_args(argv)
    random.seed(20261114)
    workdir = args.workdir
    publish_file = os.path.join(workdir, "publish", "pool-new.txt")
    served_file = os.path.join(workdir, "served", "pool-new.txt")
    clean_bytes = open(args.clean, "rb").read()
    clean_sha = hashlib.sha256(clean_bytes).hexdigest()
    checks = []

    def check(name, ok, detail=""):
        checks.append({"check": name, "ok": bool(ok), "detail": detail})
        print("[%s] %s %s" % ("PASS" if ok else "FAIL", name, detail))
        return ok

    # Cycle 0: seed with a gated publish of the clean 14 lines.
    r = _run([sys.executable, "-m", "pool.publish",
              "--workdir", workdir, "--candidates", args.clean,
              "--native-record", args.native_record,
              "--source-version", args.source_version]
             + (["--probe-db", args.probe_db] if args.probe_db else []),
            cwd=D1_ROOT)
    check("seed-gated-publish", r["rc"] == 0 and r["out"].get("ok") is True,
          "rc=%s lines=%s" % (r["rc"], (r["out"].get("manifest") or {}).get("lines")))
    r = _run([sys.executable, "-m", "pool.sync",
              "--workdir", workdir,
              "--native-record", args.native_record,
              "--source-version", args.source_version]
             + (["--probe-db", args.probe_db] if args.probe_db else []),
            cwd=D1_ROOT)
    check("seed-gated-sync", r["rc"] == 0 and r["out"].get("ok") is True,
          "rc=%s" % r["rc"])
    check("seed-served-is-clean", _sha_prefix(served_file) == clean_sha[:12],
          "served_prefix=%s" % _sha_prefix(served_file))

    # Lock-contention probe: holder owns the lock 3 s; a publish with a
    # 1 s timeout must fail, then a normal publish must succeed.
    ready = os.path.join(workdir, "holder-ready.txt")
    holder = subprocess.Popen(
        [sys.executable, "drills/hold_lock.py", "--workdir", workdir,
         "--hold", "3", "--ready", ready], cwd=D1_ROOT,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    for _ in range(50):
        if os.path.exists(ready):
            break
        time.sleep(0.1)
    r = _run([sys.executable, "-m", "pool.publish",
              "--workdir", workdir, "--candidates", args.clean,
              "--native-record", args.native_record,
              "--source-version", args.source_version,
              "--lock-timeout", "1"]
             + (["--probe-db", args.probe_db] if args.probe_db else []),
            cwd=D1_ROOT)
    check("lock-contention-timeout",
          r["rc"] == 1 and r["out"].get("error", "").startswith("lock_timeout"),
          "rc=%s error=%s" % (r["rc"], r["out"].get("error")))
    holder.wait(timeout=30)
    r = _run([sys.executable, "-m", "pool.publish",
              "--workdir", workdir, "--candidates", args.clean,
              "--native-record", args.native_record,
              "--source-version", args.source_version]
             + (["--probe-db", args.probe_db] if args.probe_db else []),
            cwd=D1_ROOT)
    check("publish-after-holder-releases",
          r["rc"] == 0 and r["out"].get("ok") is True, "rc=%s" % r["rc"])

    # Concurrent cycles: publish (:07) + sync (:00/:15/:30/:45) together.
    for i in range(args.cycles):
        jitter = random.uniform(0, 0.3)
        time.sleep(jitter)
        pub = subprocess.Popen(
            [sys.executable, "-m", "pool.publish",
             "--workdir", workdir, "--candidates", args.clean,
             "--native-record", args.native_record,
             "--source-version", args.source_version]
            + (["--probe-db", args.probe_db] if args.probe_db else []),
            cwd=D1_ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True)
        syn = subprocess.Popen(
            [sys.executable, "-m", "pool.sync",
             "--workdir", workdir,
             "--native-record", args.native_record,
             "--source-version", args.source_version]
            + (["--probe-db", args.probe_db] if args.probe_db else []),
            cwd=D1_ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True)
        pub_out, _ = pub.communicate(timeout=120)
        syn_out, _ = syn.communicate(timeout=120)
        try:
            pub_json = json.loads(pub_out.strip().splitlines()[-1])
        except (ValueError, IndexError):
            pub_json = {}
        try:
            syn_json = json.loads(syn_out.strip().splitlines()[-1])
        except (ValueError, IndexError):
            syn_json = {}
        ok_pub = pub.returncode == 0 and pub_json.get("ok") is True
        ok_syn = syn.returncode == 0 and syn_json.get("ok") is True
        ok_files = (_sha_prefix(publish_file) == clean_sha[:12]
                    and _sha_prefix(served_file) == clean_sha[:12])
        check("cycle-%d-concurrent-publish-sync" % (i + 1),
              ok_pub and ok_syn and ok_files,
              "pub_rc=%s syn_rc=%s publish_prefix=%s served_prefix=%s" % (
                  pub.returncode, syn.returncode,
                  _sha_prefix(publish_file), _sha_prefix(served_file)))

    # Legacy-writer backstop: ungated 44-line file dropped straight into
    # publish/ (lock-unaware old code). Next sync MUST refuse; served
    # file MUST stay clean. Then restore via a gated publish.
    legacy_bytes = open(args.candidates, "rb").read()
    with open(publish_file, "wb") as f:
        f.write(legacy_bytes)
    legacy_prefix = hashlib.sha256(legacy_bytes).hexdigest()[:12]
    r = _run([sys.executable, "-m", "pool.sync",
              "--workdir", workdir,
              "--native-record", args.native_record,
              "--source-version", args.source_version]
             + (["--probe-db", args.probe_db] if args.probe_db else []),
            cwd=D1_ROOT)
    check("sync-refuses-legacy-ungated-source",
          r["rc"] == 1 and r["out"].get("error") == "sync_gate_source_not_fully_admitted",
          "rc=%s error=%s publish_prefix=%s" % (
              r["rc"], r["out"].get("error"), _sha_prefix(publish_file)))
    check("served-stays-clean-after-legacy-write",
          _sha_prefix(served_file) == clean_sha[:12],
          "served_prefix=%s legacy_prefix=%s" % (
              _sha_prefix(served_file), legacy_prefix))
    r = _run([sys.executable, "-m", "pool.publish",
              "--workdir", workdir, "--candidates", args.clean,
              "--native-record", args.native_record,
              "--source-version", args.source_version]
             + (["--probe-db", args.probe_db] if args.probe_db else []),
            cwd=D1_ROOT)
    check("gated-publish-restores-clean",
          r["rc"] == 0 and _sha_prefix(publish_file) == clean_sha[:12],
          "rc=%s" % r["rc"])
    r = _run([sys.executable, "-m", "pool.sync",
              "--workdir", workdir,
              "--native-record", args.native_record,
              "--source-version", args.source_version]
             + (["--probe-db", args.probe_db] if args.probe_db else []),
            cwd=D1_ROOT)
    check("sync-after-restore",
          r["rc"] == 0 and _sha_prefix(served_file) == clean_sha[:12],
          "rc=%s" % r["rc"])

    # Next-:07 check: one more publish cycle; the file must still be
    # the clean 14-line set (no 21+23 restore).
    r = _run([sys.executable, "-m", "pool.publish",
              "--workdir", workdir, "--candidates", args.clean,
              "--native-record", args.native_record,
              "--source-version", args.source_version]
             + (["--probe-db", args.probe_db] if args.probe_db else []),
            cwd=D1_ROOT)
    check("next-07-keeps-clean",
          r["rc"] == 0 and _sha_prefix(publish_file) == clean_sha[:12]
          and (file_manifest(publish_file) or {}).get("lines") == 14,
          "rc=%s lines=%s prefix=%s" % (
              r["rc"], (file_manifest(publish_file) or {}).get("lines"),
              _sha_prefix(publish_file)))

    passed = sum(1 for c in checks if c["ok"])
    log = {
        "drill": "sim_timers",
        "cycles": args.cycles,
        "clean_sha256": clean_sha,
        "clean_lines": 14,
        "checks": checks,
        "passed": passed,
        "total": len(checks),
        "ok": passed == len(checks),
        "at_cst": time.strftime("%Y-%m-%d %H:%M:%S CST", time.localtime()),
    }
    if args.log:
        with open(args.log, "w", encoding="utf-8") as f:
            json.dump(log, f, ensure_ascii=False, indent=2)
    print("SIM-TIMERS: %d/%d checks passed" % (passed, len(checks)))
    return 0 if log["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
