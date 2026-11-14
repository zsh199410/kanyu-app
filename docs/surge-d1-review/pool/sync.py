"""D1 sync path (GPT 6875033415 item 4).

Sync runs under the SAME shared flock as publish/rollback and re-runs
the DUAL gate on the source publish file before copying it to the
served directory. The served file must be EXACTLY the gated set:
  - zero admitted lines in the source -> refuse, served file untouched
  - source contains any line NOT in the native allowlist -> refuse,
    served file untouched (the source must have been produced by a gated
    publish; an ungated/legacy source must never reach the phone)
  - otherwise atomic copy (tmp + rename) + SHA verification.

This is what stops a legacy 21-pinned + 23-rotation publish from being
served even if it somehow lands in publish/: the sync gate rejects it
and the previously served clean file stays in place.

Usage (subprocess, as the :00/:15/:30/:45 timer would invoke it):
  python3 -m pool.sync --workdir <dir>
      --native-record <file> --source-version <sha256>
      [--probe-db <file>] [--lock-timeout 30]

Exit code 0 = synced, 1 = refused, 2 = usage.
stdout is a single JSON object (desensitised: counts, SHA prefixes only).
"""

import argparse
import json
import os
import shutil
import sys
import time

from .native_gate import gate_lines, load_native_allowlist
from .publish_lock import PublishLock, _fsync_dir, file_manifest

PUBLISH_FILENAME = "pool-new.txt"


def _read_lines(path):
    with open(path, encoding="utf-8") as f:
        return [l.rstrip("\n") for l in f if l.strip()]


def run_sync(workdir, native_record_path, source_version_sha,
             probe_db=None, lock_timeout=30, now=None):
    """Returns (rc, result_dict). rc 0 = synced, 1 = refused."""
    now = int(now if now is not None else time.time())
    publish_dir = os.path.join(workdir, "publish")
    served_dir = os.path.join(workdir, "served")
    lock_path = os.path.join(workdir, "lock", "publish.lock")
    os.makedirs(served_dir, exist_ok=True)
    source = os.path.join(publish_dir, PUBLISH_FILENAME)
    target = os.path.join(served_dir, PUBLISH_FILENAME)
    result = {
        "ok": False,
        "path": "sync",
        "checked_at": now,
        "source_version_sha_prefix": (source_version_sha or "")[:12],
        "source_manifest": file_manifest(source),
        "served_manifest_before": file_manifest(target),
    }
    if not os.path.exists(source):
        result["error"] = "source_missing"
        return 1, result
    try:
        lock = PublishLock(lock_path, owner="sync", timeout=lock_timeout)
        lock.acquire()
    except Exception as e:
        result["error"] = "lock_timeout: %s" % type(e).__name__
        return 1, result
    try:
        admitted, conditional, gdiag = load_native_allowlist(
            native_record_path, source_version_sha,
            probe_db=probe_db, now=now)
        result["gate_diag"] = gdiag
        result["conditional_count"] = len(conditional)
        if gdiag.get("error"):
            result["error"] = "native_gate_%s" % gdiag["error"]
            return 1, result
        try:
            source_lines = _read_lines(source)
        except OSError as e:
            result["error"] = "source_unreadable: %s" % type(e).__name__
            return 1, result
        kept, ldiag = gate_lines(source_lines, admitted)
        result["line_diag"] = ldiag
        if not kept:
            result["error"] = "sync_gate_zero_qualified"
            return 1, result
        if len(kept) != len(source_lines):
            # Source has lines the gate does not admit (e.g. a legacy
            # ungated publish). Refuse: the served file must stay clean.
            result["error"] = "sync_gate_source_not_fully_admitted"
            result["source_lines"] = len(source_lines)
            result["kept_lines"] = len(kept)
            return 1, result
        tmp = target + ".tmp"
        shutil.copyfile(source, tmp)
        try:
            os.chmod(tmp, 0o644)
        except OSError:
            pass
        os.rename(tmp, target)
        _fsync_dir(served_dir)
        got = file_manifest(target)
        if got is None or got["sha256"] != result["source_manifest"]["sha256"]:
            result["error"] = "sync_verify_failed"
            result["served_manifest_after"] = got
            return 1, result
        result.update({
            "ok": True,
            "served_manifest_after": got,
            "lock_owner": lock.owner_record(),
        })
        return 0, result
    finally:
        lock.release()


def main(argv=None):
    ap = argparse.ArgumentParser(description="D1 gated sync (isolation)")
    ap.add_argument("--workdir", required=True)
    ap.add_argument("--native-record", required=True)
    ap.add_argument("--source-version", required=True,
                    help="sha256 of the subscription version natively tested")
    ap.add_argument("--probe-db", default=None)
    ap.add_argument("--lock-timeout", type=float, default=30)
    args = ap.parse_args(argv)
    rc, result = run_sync(
        args.workdir, args.native_record, args.source_version,
        probe_db=args.probe_db, lock_timeout=args.lock_timeout)
    print(json.dumps(result, ensure_ascii=False))
    return rc


if __name__ == "__main__":
    sys.exit(main())
