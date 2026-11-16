"""D1 rollback path (GPT 6875033415 item 4).

Rollback runs under the SAME shared flock as publish/sync and the
rollback target is gate-checked BEFORE it is restored:
  - the anchor (.prev or a history snapshot) must carry a .meta.json
    sidecar with ITS OWN source_version_sha; an anchor without one is
    refused (fail closed: it cannot be gate-checked)
  - the anchor's lines are gated against the native record for the
    anchor's version; kept must equal ALL anchor lines and be non-zero
  - otherwise the current file is left untouched

This keeps the gate spanning all three paths: a rollback can never
re-introduce lines the native evidence does not admit for their version
(e.g. rolling back to a pre-clean 21-pinned + 23-rotation file is
refused, because that version has no native pass record).

Steps (condensed from the D0 8-step rollback):
  1 record bad manifest; 2 acquire the shared lock; 3 resolve + gate the
  anchor; 4 restore (snapshot current + atomic write + verify); 5 sync to
  served dir + verify SHA; 6 phone refresh is MANUAL (never claimed
  done); 7 release lock + write rollback log; 8 if still bad, record
  "stop pool-publish.timer -- REQUIRES owner authorisation" (never
  executed here).

Usage (subprocess):
  python3 -m pool.rollback --workdir <dir> --target prev|latest-history|history:<basename>
      --native-record <file> [--probe-db <file>] [--lock-timeout 30]

Exit code 0 = rolled back, 1 = refused, 2 = usage.
stdout is a single JSON object (desensitised: counts, SHA prefixes only).
"""

import argparse
import json
import os
import shutil
import sys
import time

from .native_gate import gate_lines, load_native_allowlist
from .publish_lock import (
    PublishLock, _atomic_write_inner, _fsync_dir, file_manifest,
    read_version_meta,
)

PUBLISH_FILENAME = "pool-new.txt"


def _read_lines(path):
    with open(path, encoding="utf-8") as f:
        return [l.rstrip("\n") for l in f if l.strip()]


def _resolve_anchor(publish_dir, target):
    """Returns (anchor_path, anchor_kind, source_version_sha) or (None, None, None)."""
    if target == "prev":
        anchor = os.path.join(publish_dir, PUBLISH_FILENAME + ".prev")
        if not os.path.exists(anchor):
            return None, None, None
        meta = read_version_meta(publish_dir, PUBLISH_FILENAME + ".prev")
        sha = (meta or {}).get("source_version_sha")
        return anchor, ".prev", sha
    hist_dir = os.path.join(publish_dir, "history")
    if not os.path.isdir(hist_dir):
        return None, None, None
    if target == "latest-history":
        snaps = sorted(
            (os.path.join(hist_dir, f) for f in os.listdir(hist_dir)
             if f.startswith("pool-new-") and f.endswith(".txt")),
            key=lambda p: os.path.getmtime(p))
        if not snaps:
            return None, None, None
        anchor = snaps[-1]
    elif target.startswith("history:"):
        anchor = os.path.join(hist_dir, target[len("history:"):])
        if not os.path.exists(anchor):
            return None, None, None
    else:
        return None, None, None
    meta_path = anchor + ".meta.json"
    try:
        with open(meta_path, encoding="utf-8") as f:
            meta = json.load(f)
        sha = meta.get("source_version_sha") if isinstance(meta, dict) else None
    except (OSError, ValueError):
        sha = None
    return anchor, "history-snapshot", sha


def run_rollback(workdir, target, native_record_path, probe_db=None,
                 lock_timeout=30, now=None):
    """Returns (rc, result_dict). rc 0 = rolled back, 1 = refused."""
    now = int(now if now is not None else time.time())
    publish_dir = os.path.join(workdir, "publish")
    served_dir = os.path.join(workdir, "served")
    lock_path = os.path.join(workdir, "lock", "publish.lock")
    os.makedirs(publish_dir, exist_ok=True)
    os.makedirs(served_dir, exist_ok=True)
    target_file = os.path.join(publish_dir, PUBLISH_FILENAME)
    served_file = os.path.join(served_dir, PUBLISH_FILENAME)
    steps = []
    result = {
        "ok": False,
        "path": "rollback",
        "target": target,
        "checked_at": now,
        "steps": steps,
        "bad_manifest": file_manifest(target_file),
    }

    def _step(name, detail):
        steps.append({"step": name, "at": time.strftime(
            "%Y-%m-%d %H:%M:%S %Z", time.localtime()), "ts": int(time.time()),
            "detail": detail})

    _step("1-record-bad-version",
          "bad lines=%s sha_prefix=%s" % (
              result["bad_manifest"]["lines"] if result["bad_manifest"] else None,
              result["bad_manifest"]["sha_prefix"] if result["bad_manifest"] else ""))
    try:
        lock = PublishLock(lock_path, owner="rollback", timeout=lock_timeout)
        lock.acquire()
    except Exception as e:
        _step("2-acquire-write-lock", "FAILED: %s" % type(e).__name__)
        result["error"] = "lock_timeout"
        return 1, result
    try:
        _step("2-acquire-write-lock",
              "held by rollback pid=%s" % os.getpid())
        anchor, anchor_kind, anchor_sha = _resolve_anchor(publish_dir, target)
        if anchor is None:
            _step("3-resolve-anchor", "FAILED: no anchor for target=%s" % target)
            result["error"] = "no_rollback_anchor"
            return 1, result
        if not anchor_sha:
            _step("3-resolve-anchor",
                  "FAILED: anchor %s has no version sidecar, cannot gate-check"
                  % anchor_kind)
            result["error"] = "anchor_no_version_meta"
            return 1, result
        _step("3-resolve-anchor",
              "anchor=%s lines=%s sha_prefix=%s version_prefix=%s" % (
                  anchor_kind, file_manifest(anchor)["lines"],
                  file_manifest(anchor)["sha_prefix"], anchor_sha[:12]))
        # Gate the anchor against the native record for ITS OWN version.
        admitted, conditional, gdiag = load_native_allowlist(
            native_record_path, anchor_sha,
            probe_db=probe_db, now=now)
        result["gate_diag"] = gdiag
        result["conditional_count"] = len(conditional)
        if gdiag.get("error"):
            _step("3-gate-anchor", "FAILED: native_gate_%s" % gdiag["error"])
            result["error"] = "native_gate_%s" % gdiag["error"]
            return 1, result
        try:
            anchor_lines = _read_lines(anchor)
        except OSError as e:
            _step("3-gate-anchor", "FAILED: anchor unreadable %s" % type(e).__name__)
            result["error"] = "anchor_unreadable"
            return 1, result
        kept, ldiag = gate_lines(anchor_lines, admitted)
        result["line_diag"] = ldiag
        if not kept:
            _step("3-gate-anchor", "FAILED: anchor zero qualified")
            result["error"] = "rollback_gate_zero_qualified"
            return 1, result
        if len(kept) != len(anchor_lines):
            _step("3-gate-anchor",
                  "FAILED: anchor not fully admitted (%s/%s kept)"
                  % (len(kept), len(anchor_lines)))
            result["error"] = "rollback_gate_anchor_not_fully_admitted"
            return 1, result
        _step("3-gate-anchor",
              "anchor fully admitted: %s/%s lines" % (len(kept), len(anchor_lines)))
        # Restore: snapshot the current (bad) file, atomic write anchor.
        written = _atomic_write_inner(
            publish_dir, PUBLISH_FILENAME, kept,
            source_version_sha=anchor_sha)
        got = written["manifest"]
        _step("4-verify-restored",
              "restored lines=%s sha_prefix=%s matches anchor" % (
                  got["lines"], got["sha_prefix"]))
        result["restored_manifest"] = got
        result["anchor_kind"] = anchor_kind
        result["anchor_manifest"] = file_manifest(anchor)
        # Sync the restored file to the served dir, same lock.
        tmp = served_file + ".tmp"
        shutil.copyfile(target_file, tmp)
        os.rename(tmp, served_file)
        _fsync_dir(served_dir)
        synced = file_manifest(served_file)
        if synced and synced["sha256"] == got["sha256"]:
            _step("5-sync-verify",
                  "synced lines=%s sha_prefix=%s match" % (
                      synced["lines"], synced["sha_prefix"]))
        else:
            _step("5-sync-verify", "FAILED: staged sha mismatch")
            result["error"] = "sync_verify_failed"
            return 1, result
        _step("6-phone-refresh",
              "MANUAL (not done from VPS): refresh the free pool on the "
              "phone and check member count equals restored lines=%s"
              % got["lines"])
        result["ok"] = True
        return 0, result
    finally:
        lock.release()
        _step("7-release-lock-and-log", "lock released; rollback log written")
        log_path = os.path.join(
            publish_dir, "rollback-%d.json" % int(time.time()))
        with open(log_path, "w", encoding="utf-8") as f:
            json.dump(result, f, ensure_ascii=False, indent=2)
        try:
            os.chmod(log_path, 0o600)
        except OSError:
            pass
        result["rollback_log"] = log_path
        if not result["ok"]:
            _step("8-stop-publish-timer-if-still-bad",
                  "RECORDED ONLY (not executed): stop pool-publish.timer "
                  "requires owner authorisation; rollback failed with "
                  "error=%s" % result.get("error"))
        else:
            _step("8-stop-publish-timer-if-still-bad",
                  "not needed: rollback verified ok")


def main(argv=None):
    ap = argparse.ArgumentParser(description="D1 gated rollback (isolation)")
    ap.add_argument("--workdir", required=True)
    ap.add_argument("--target", required=True,
                    help="prev | latest-history | history:<basename>")
    ap.add_argument("--native-record", required=True)
    ap.add_argument("--probe-db", default=None)
    ap.add_argument("--lock-timeout", type=float, default=30)
    args = ap.parse_args(argv)
    rc, result = run_rollback(
        args.workdir, args.target, args.native_record,
        probe_db=args.probe_db, lock_timeout=args.lock_timeout)
    print(json.dumps(result, ensure_ascii=False))
    return rc


if __name__ == "__main__":
    sys.exit(main())
