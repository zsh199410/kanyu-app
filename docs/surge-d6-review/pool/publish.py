"""D2 publish path (GPT D1 review 6881291219, blocker 1 + 3).

D1 publish ran under the SHARED flock (same lock file as sync/rollback)
and through the DUAL gate (native allowlist). Pinned lines have NO
exemption: they are candidates like everything else and only publish
when their fingerprint is in the native allowlist.

D2 fixes (blocker 1 -- version/evidence binding):
  The caller-passed source_version_sha is NO LONGER trusted on its own.
  run_publish now REQUIRES source_file: the full subscription file whose
  bytes were natively tested. Inside the held lock it verifies, from
  ACTUAL BYTES:
    1. sha256(source_file bytes) == caller-passed source_version_sha,
       else refuse `source_version_sha_mismatch` (old evidence pasted
       onto a new version can no longer pass);
    2. every candidate line is a byte-identical member of the source
       file (no smuggled lines), else refuse `candidate_not_in_source`;
       duplicate candidate lines are refused as well;
    3. the gate is then run for the VERIFIED version sha (never for a
       caller assertion alone);
    4. the published file gets a v2 version chain sidecar
       (source_sha + published_sha + admitted fingerprint set +
       chain_id -- see pool/version_chain.py), so sync/rollback can
       re-verify the binding instead of trusting the sidecar.
  The STOP marker (pool/recovery.py) is honoured: while the pool is
  stopped, publish refuses with `pool_stopped` and writes nothing.

Flow, all inside ONE held lock (no TOCTOU between gate and write):
  1. Acquire the shared lock.
  2. Refuse when stopped (recovery state).
  3. Verify source-file bytes vs claimed source_version_sha.
  4. Verify candidates are a subset of the source file.
  5. Load the native allowlist for the VERIFIED sha (fail closed when
     the native record is missing/unreadable: refuse, rc=1).
  6. Gate the candidate lines (pinned included).
  7. Zero kept -> refuse (rc=1), old publish file untouched, emit
     zero_qualified_safe_state ("old subscription kept, not claimed
     compliant").
  8. Otherwise atomic write (snapshot + tmp + fsync + rename + verify)
     with a v2 version-chain sidecar.
  D5 (cross-cycle, Issue #73 GPT D4 review 6887331723): the gate
  verifies the FINAL bytes that will be served, not only the
  in-memory candidate lines. Before the rename, the tmp file's actual
  bytes are re-checked: (a) its SHA must equal the version chain's
  published_sha, (b) its actual lines must re-pass the native
  allowlist gate. After the write, the target file is re-read and
  re-checked the same way. Any mismatch refuses with
  `publish_postwrite_verify_failed`, the tmp file is deleted, and the
  target keeps its previous bytes (SHA unchanged). The result carries
  postwrite_verified=true and published_manifest_after (the manifest
  actually on disk after the write).

Usage (subprocess, as the :07 timer would invoke it):
  python3 -m pool.publish --workdir <dir> --candidates <file>
      --source-file <file> --native-record <file>
      --source-version <sha256>
      [--probe-db <file>] [--lock-timeout 30]

Exit code 0 = published, 1 = refused (gate / lock / record / binding),
2 = usage.
stdout is a single JSON object (desensitised: counts, SHA prefixes only;
the full chain lives in the 600 sidecar, not in stdout).
"""

import argparse
import json
import os
import sys
import time

from .native_gate import gate_lines, load_native_allowlist
from .publish_lock import (
    PublishLock, PublishRefused, _atomic_write_inner, file_manifest,
    sha256_file,
)
from .version_chain import build_version_chain, sha256_lines

PUBLISH_FILENAME = "pool-new.txt"


def _read_lines(path):
    with open(path, encoding="utf-8") as f:
        return [l.rstrip("\n") for l in f if l.strip()]


def run_publish(workdir, candidate_lines, native_record_path,
                source_version_sha, probe_db=None, lock_timeout=30,
                now=None, source_file=None, pre_rename_hook=None):
    """Returns (rc, result_dict). rc 0 = published, 1 = refused.

    source_file is REQUIRED (D2): the full subscription file whose
    bytes were natively tested. Its SHA must equal source_version_sha
    and every candidate line must be a byte-identical member of it.
    Passing source_file=None refuses with `source_file_required`: there
    is no unbound publish path anymore.

    pre_rename_hook is TEST-ONLY (D5 fault injection): called on the
    tmp file after it is written and before the pre-rename final-byte
    verification. Production callers pass None.
    """
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
        "binding": "version-chain-v1",
    }
    if source_file is None:
        result["error"] = "source_file_required"
        return 1, result
    try:
        lock = PublishLock(lock_path, owner="publish", timeout=lock_timeout)
        lock.acquire()
    except Exception as e:
        result["error"] = "lock_timeout: %s" % type(e).__name__
        return 1, result
    try:
        # Manifests are taken INSIDE the lock (D2, blocker 2 class):
        # a pre-lock manifest can go stale while waiting for the lock.
        result["old_manifest"] = file_manifest(target)
        # Recovery gate (D3, fail-closed): while stopped, nothing
        # publishes; when the recovery state cannot be established
        # (missing/corrupt/unreadable/illegal state or anchor,
        # checksum mismatch, uninitialized), publish refuses with the
        # specific recovery_state_*/recovery_anchor_* code.
        from .recovery import gate_check  # local import: no cycle
        allowed, gerr, _gstate = gate_check(workdir)
        if not allowed:
            result["error"] = gerr
            return 1, result
        # --- Blocker 1: bind the CLAIMED version to ACTUAL BYTES. ---
        try:
            actual_source_sha = sha256_file(source_file)
        except OSError:
            result["error"] = "source_file_unreadable"
            return 1, result
        result["actual_source_sha_prefix"] = actual_source_sha[:12]
        if actual_source_sha != source_version_sha:
            # Old evidence pasted onto a new version (or vice versa).
            result["error"] = "source_version_sha_mismatch"
            return 1, result
        try:
            source_lines = _read_lines(source_file)
        except OSError:
            result["error"] = "source_file_unreadable"
            return 1, result
        if len(set(candidate_lines)) != len(candidate_lines):
            result["error"] = "candidate_duplicate_lines"
            return 1, result
        source_set = set(source_lines)
        if not set(candidate_lines).issubset(source_set):
            result["error"] = "candidate_not_in_source"
            return 1, result
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
            chain = build_version_chain(source_version_sha, kept, admitted)
        except ValueError as e:
            result["error"] = "version_chain_build_failed: %s" % e
            return 1, result

        def _verify_final_bytes(tmp_path):
            """D5: re-verify the ACTUAL bytes about to be served.

            (a) tmp SHA must equal the chain's published_sha;
            (b) tmp's actual lines must re-pass the native allowlist
            gate, fully (same allowlist the gate used). Raises
            PublishRefused with publish_postwrite_verify_failed on
            any mismatch; _atomic_write_inner then deletes the tmp
            file and leaves the target untouched.
            """
            try:
                tmp_sha = sha256_file(tmp_path)
            except OSError:
                raise PublishRefused(
                    "publish_postwrite_verify_failed: tmp unreadable")
            if tmp_sha != chain["published_sha"]:
                raise PublishRefused(
                    "publish_postwrite_verify_failed: tmp sha_prefix=%s "
                    "!= published_sha_prefix=%s"
                    % (tmp_sha[:12], chain["published_sha"][:12]))
            try:
                tmp_lines = _read_lines(tmp_path)
            except OSError:
                raise PublishRefused(
                    "publish_postwrite_verify_failed: tmp unreadable")
            re_kept, _ldiag = gate_lines(tmp_lines, admitted)
            if len(re_kept) != len(tmp_lines):
                raise PublishRefused(
                    "publish_postwrite_verify_failed: tmp lines not "
                    "fully admitted (%d/%d)"
                    % (len(re_kept), len(tmp_lines)))

        try:
            written = _atomic_write_inner(
                publish_dir, PUBLISH_FILENAME, kept,
                source_version_sha=source_version_sha,
                version_chain=chain,
                verify=_verify_final_bytes,
                pre_rename_hook=pre_rename_hook)
        except PublishRefused as e:
            # D5: a final-byte verification failure is its own error
            # code; the target file was left untouched (tmp deleted
            # pre-rename, or previous bytes restored post-rename).
            if "publish_postwrite_verify_failed" in str(e):
                result["error"] = "publish_postwrite_verify_failed"
                result["postwrite_verified"] = False
                result["published_manifest_after"] = file_manifest(target)
                return 1, result
            result["error"] = "publish_refused: %s" % e
            return 1, result
        # D5: post-write re-verification -- re-read the TARGET file's
        # actual bytes (not the in-memory lines) and re-check them
        # against the chain + the allowlist. A mismatch here means the
        # rename itself was interfered with; refuse and restore the
        # previous bytes from the snapshot so the served file never
        # holds unverified bytes.
        published_after = file_manifest(target)
        postwrite_ok = False
        try:
            after_lines = _read_lines(target)
            after_sha = sha256_lines(after_lines)
            re_kept, _ldiag = gate_lines(after_lines, admitted)
            postwrite_ok = (
                published_after is not None
                and after_sha == chain["published_sha"]
                and len(re_kept) == len(after_lines))
        except OSError:
            postwrite_ok = False
        if not postwrite_ok:
            snap_path = written.get("snapshot_path")
            try:
                import shutil
                if snap_path and os.path.exists(snap_path):
                    restore_tmp = target + ".restore.tmp"
                    shutil.copyfile(snap_path, restore_tmp)
                    os.chmod(restore_tmp, 0o600)
                    os.rename(restore_tmp, target)
                    snap_meta = snap_path + ".meta.json"
                    if os.path.exists(snap_meta):
                        shutil.copyfile(snap_meta, target + ".meta.json")
                else:
                    for _p in (target, target + ".meta.json"):
                        try:
                            os.unlink(_p)
                        except OSError:
                            pass
            except OSError:
                pass
            result["error"] = "publish_postwrite_verify_failed"
            result["postwrite_verified"] = False
            result["published_manifest_after"] = file_manifest(target)
            return 1, result
        result.update({
            "ok": True,
            "postwrite_verified": True,
            "published_manifest_after": published_after,
            "manifest": written["manifest"],
            "snapshot_manifest": written["snapshot_manifest"],
            "prev_manifest_after": written["prev_manifest_after"],
            "version_chain_summary": {
                "source_sha_prefix": chain["source_sha"][:12],
                "published_sha_prefix": chain["published_sha"][:12],
                "admitted_count": len(chain["admitted_fingerprints"]),
                "published_count": len(chain["published_fingerprints"]),
                "chain_id_prefix": chain["chain_id"][:12],
            },
            "lock_owner": lock.owner_record(),
        })
        return 0, result
    finally:
        lock.release()


def main(argv=None):
    ap = argparse.ArgumentParser(description="D2 gated publish (isolation)")
    ap.add_argument("--workdir", required=True)
    ap.add_argument("--candidates", required=True,
                    help="file with candidate subscription lines")
    ap.add_argument("--source-file", required=True,
                    help="full subscription file whose bytes were "
                         "natively tested; its SHA must equal "
                         "--source-version")
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
        lock_timeout=args.lock_timeout, source_file=args.source_file)
    print(json.dumps(result, ensure_ascii=False))
    return rc


if __name__ == "__main__":
    sys.exit(main())
