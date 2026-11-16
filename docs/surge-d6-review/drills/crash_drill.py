"""D2 crash drill: SIGKILLed lock holder must release the flock
immediately (kernel property) and the publish file must be unchanged.

Standalone version of TestSharedLock.test_crash_recovery, producing a
JSON log for docs/crash-drill-log.json.

Usage:
  python3 drills/crash_drill.py --workdir <dir>
      --clean <14-line file> --native-record <file>
      --source-version <sha256> --source-file <file>
      [--probe-db <file>] [--log <file>]
"""

import argparse
import json
import os
import signal
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
D2_ROOT = os.path.dirname(HERE)
sys.path.insert(0, D2_ROOT)

from pool.publish import run_publish  # noqa: E402
from pool.publish_lock import PublishLock, file_manifest  # noqa: E402
from pool.recovery import OWNER_ACK_INIT, init_recovery_state  # noqa: E402


def main(argv=None):
    ap = argparse.ArgumentParser(description="D2 crash drill")
    ap.add_argument("--workdir", required=True)
    ap.add_argument("--clean", required=True)
    ap.add_argument("--native-record", required=True)
    ap.add_argument("--source-version", required=True)
    ap.add_argument("--source-file", required=True)
    ap.add_argument("--probe-db", default=None)
    ap.add_argument("--log", default=None)
    args = ap.parse_args(argv)
    workdir = args.workdir
    with open(args.native_record) as f:
        record = json.load(f)
    tested_at = record["runs"][0]["tested_at"]
    now = tested_at + 3600
    # D3: the workdir is UNINITIALIZED until the recovery state is
    # explicitly initialized.
    rc, out = init_recovery_state(workdir, OWNER_ACK_INIT)
    assert rc == 0, out
    with open(args.clean, encoding="utf-8") as f:
        clean14 = [l.rstrip("\n") for l in f if l.strip()]
    rc, res = run_publish(workdir, clean14, args.native_record,
                          args.source_version, probe_db=args.probe_db,
                          now=now, source_file=args.source_file)
    assert rc == 0, res
    target = os.path.join(workdir, "publish", "pool-new.txt")
    before = file_manifest(target)
    ready = os.path.join(workdir, "holder-ready.txt")
    holder = subprocess.Popen(
        [sys.executable, "drills/hold_lock.py", "--workdir", workdir,
         "--hold", "30", "--ready", ready],
        cwd=D2_ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    try:
        for _ in range(100):
            if os.path.exists(ready):
                break
            time.sleep(0.1)
        assert os.path.exists(ready), "holder never acquired"
        holder.send_signal(signal.SIGKILL)
        holder.wait(timeout=10)
        t0 = time.time()
        lock = PublishLock(os.path.join(workdir, "lock", "publish.lock"),
                           owner="after-crash", timeout=5)
        lock.acquire()
        dt = time.time() - t0
        lock.release()
        after = file_manifest(target)
        log = {
            "drill": "crash-recovery",
            "reacquire_seconds": round(dt, 3),
            "reacquire_under_2s": dt < 2.0,
            "file_sha_unchanged": after["sha256"] == before["sha256"],
            "file_lines": after["lines"],
            "before_sha_prefix": before["sha_prefix"],
            "after_sha_prefix": after["sha_prefix"],
            "ok": dt < 2.0 and after["sha256"] == before["sha256"],
            "at_cst": time.strftime("%Y-%m-%d %H:%M:%S CST", time.localtime()),
        }
    finally:
        if holder.poll() is None:
            holder.kill()
    if args.log:
        with open(args.log, "w", encoding="utf-8") as f:
            json.dump(log, f, ensure_ascii=False, indent=2)
    print("CRASH-DRILL: reacquire=%.3fs sha_unchanged=%s ok=%s" % (
        log["reacquire_seconds"], log["file_sha_unchanged"], log["ok"]))
    return 0 if log["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
