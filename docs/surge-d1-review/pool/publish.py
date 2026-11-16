"""D1 publish path (GPT 6875033415 item 4).

Publish runs under the SHARED flock (same lock file as sync/rollback)
and through the DUAL gate (native allowlist). Pinned lines have NO
exemption: they are candidates like everything else and only publish
when their fingerprint is in the native allowlist.

Flow, all inside ONE held lock (no TOCTOU between gate and write):
  1. Acquire the shared lock.
  2. Load the native allowlist for source_version_sha (fail closed when
     the native record is missing/unreadable: refuse, rc=1).
  3. Gate the candidate lines (pinned included).
  4. Zero kept -> refuse (rc=1), old publish file untouched, emit
     zero_qualified_safe_state ("old subscription kept, not claimed
     compliant").
  5. Otherwise atomic write (snapshot + tmp + fsync + rename + verify)
     with a .meta.json sidecar carrying source_version_sha.

Usage (subprocess, as the :07 timer would invoke it):
  python3 -m pool.publish --workdir <dir> --candidates <file>
      --native-record <file> --source-version <sha256>
      [--probe-db <file>] [--lock-timeout 30]

Exit code 0 = published, 1 = refused (gate / lock / record), 2 = usage.
stdout is a single JSON object (desensitised: counts, SHA prefixes only).
"""

import argparse
import hashlib
import json
import os
import sys
import time

from .native_gate import gate_lines, load_native_allowlist
from .publish_lock import (
    PublishLock, PublishRefused, _atomic_write_inner, file_manifest,
    sha256_file,
)

PUBLISH_FILENAME = "pool-new.txt"


def _read_lines(path):
    with open(path, encoding="utf-8") as f:
        return [l.rstrip("\n") for l in f if l.strip()]


def run_publish(workdir, candidate_lines, native_record_path,
                source_version_sha, probe_db=None, lock_timeout=30,
                now=None):
    """Returns (rc, result_dict). rc 0 = published, 1 = refused."""
    now = int(now if now is not None else time.time())
    publish_dir = os.path.join(workdir, "publish")
    lock_path = os.path.join(workdir, "lock", "publish.lock")
    os.makedirs(publish_dir, exist_ok=True)
    target = os.path.join(publish_dir, PUBLISH_FILENAME)
    result = {
        "ok": False,
        "path": "publish",
        "checked_at": now,
        "source_version_sha_prefix": (source_version_sha or "")[:12],
        "old_manifest": file_manifest(target),
    }
    try:
        lock = PublishLock(lock_path, owner="publish", timeout=lock_timeout)
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
            result["zero_qualified_safe_state"] = (
                "old subscription kept, not claimed compliant")
            return 1, result
        kept, ldiag = gate_lines(candidate_lines, admitted)
        result["line_diag"] = ldiag
        if not kept:
            result["error"] = "phone_gate_zero_qualified"
            result["zero_qualified_safe_state"] = (
                "old subscription kept, not claimed compliant")
            return 1, result
        try:
            written = _atomic_write_inner(
                publish_dir, PUBLISH_FILENAME, kept,
                source_version_sha=source_version_sha)
        except PublishRefused as e:
            result["error"] = "publish_refused: %s" % e
            return 1, result
        result.update({
            "ok": True,
            "manifest": written["manifest"],
            "snapshot_manifest": written["snapshot_manifest"],
            "prev_manifest_after": written["prev_manifest_after"],
            "lock_owner": lock.owner_record(),
        })
        return 0, result
    finally:
        lock.release()


def main(argv=None):
    ap = argparse.ArgumentParser(description="D1 gated publish (isolation)")
    ap.add_argument("--workdir", required=True)
    ap.add_argument("--candidates", required=True,
                    help="file with candidate subscription lines")
    ap.add_argument("--native-record", required=True)
    ap.add_argument("--source-version", required=True,
                    help="sha256 of the subscription version natively tested")
    ap.add_argument("--probe-db", default=None)
    ap.add_argument("--lock-timeout", type=float, default=30)
    args = ap.parse_args(argv)
    try:
        candidates = _read_lines(args.candidates)
    except OSError as e:
        print(json.dumps({"ok": False, "error": "candidates_unreadable: %s"
                          % type(e).__name__}))
        return 2
    rc, result = run_publish(
        args.workdir, candidates, args.native_record,
        args.source_version, probe_db=args.probe_db,
        lock_timeout=args.lock_timeout)
    print(json.dumps(result, ensure_ascii=False))
    return rc


if __name__ == "__main__":
    sys.exit(main())
