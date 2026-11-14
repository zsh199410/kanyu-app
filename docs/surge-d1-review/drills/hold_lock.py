"""Drill helper: acquire the shared lock, signal readiness, hold it.

Used by the crash-recovery drill: the parent SIGKILLs this process
while it holds the lock, then verifies the next acquirer proceeds
immediately (flock is released by the kernel on holder death).

Usage:
  python3 drills/hold_lock.py --workdir <dir> --hold 10 --ready <file>
"""

import argparse
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from pool.publish_lock import PublishLock  # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--workdir", required=True)
    ap.add_argument("--hold", type=float, default=10)
    ap.add_argument("--ready", required=True)
    ap.add_argument("--owner", default="drill-holder")
    args = ap.parse_args()
    lock_path = os.path.join(args.workdir, "lock", "publish.lock")
    lock = PublishLock(lock_path, owner=args.owner, timeout=30)
    lock.acquire()
    with open(args.ready, "w", encoding="utf-8") as f:
        f.write("held pid=%d\n" % os.getpid())
    time.sleep(args.hold)
    lock.release()
    return 0


if __name__ == "__main__":
    sys.exit(main())
