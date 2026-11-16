"""D2 sync path (GPT D1 review 6881291219, blockers 1 + 2 + 3).

Sync runs under the SAME shared flock as publish/rollback and re-runs
the DUAL gate on the source publish file before copying it to the
served directory. The served file must be EXACTLY the gated set:
  - zero admitted lines in the source -> refuse, served file untouched
  - source contains any line NOT in the native allowlist -> refuse,
    served file untouched (the source must have been produced by a gated
    publish; an ungated/legacy source must never reach the phone)
  - otherwise atomic copy (tmp + rename) + SHA verification.

D2 fixes:
  Blocker 2 -- the lock race: D1 computed result["source_manifest"]
  BEFORE acquiring the flock, then read/copied the source inside the
  lock and verified the served file against the PRE-LOCK SHA. If a
  legitimate publish updated the source while sync waited for the
  lock, sync copied the NEW file and then reported `sync_verify_failed`
  -- the file was fine, the error was wrong, and the reported status
  did not match the actually served version. Now EVERYTHING happens
  inside the held lock: source manifest, sidecar read, chain
  verification, gate, copy, and verification use SHAs computed IN THE
  LOCK, before AND after the copy (source_sha_before == served_sha ==
  source_sha_after). Success/failure always reflects the actually
  served version.
  Blocker 1 -- version/evidence binding: sync no longer trusts the
  caller-passed --source-version (now optional). The source file's
  .meta.json sidecar must carry a v2 version chain, and the chain is
  RE-VERIFIED against the actual source bytes + the native record
  (published_sha, chain_id, admitted set -- see
  pool/version_chain.py). A tampered sidecar, a swapped sidecar, or a
  replaced source file all refuse; a v1-only sidecar (no chain)
  refuses as well. When --source-version IS given it must equal the
  sidecar's source_sha.
  Blocker 3 -- failure isolation: if the post-copy verification ever
  fails (the served file is then NOT what was gated), sync records
  the ACTUAL served manifest, enters the degraded recovery state
  (STOP marker set, served file flagged not-qualified), and returns
  rc=1. The bad served version is never reported as success and never
  silently left serving: the next publish/sync refuses until manual
  recovery (see pool/recovery.py, docs/recovery-runbook.md).

D5 (cross-cycle, Issue #73 GPT D4 review 6887331723): after the copy
to served and BEFORE reporting success, sync re-reads the SERVED
file's actual bytes and re-checks them: (a) sha256 of the served
lines must equal the version chain's published_sha (not merely equal
to the source SHA), (b) the served lines must re-pass
gate_lines(served_lines, admitted) in full. A mismatch refuses with
`sync_served_gate_failed` and enters the degraded state, exactly like
the SHA-mismatch path; the served file is left as-is and never
claimed as success. This is what stops an ungated writer's version
from being served even if it lands in publish/ AND the copy itself
is interfered with after the rename.

This is what stops a legacy 21-pinned + 23-rotation publish from being
served even if it somehow lands in publish/: the sync gate refuses it
and the previously served clean file stays in place.

Usage (subprocess, as the :00/:15/:30/:45 timer would invoke it):
  python3 -m pool.sync --workdir <dir>
      --native-record <file> [--source-version <sha256>]
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
from .publish_lock import (
    PublishLock, _fsync_dir, copy_sidecar, file_manifest, sha256_file,
)
from .version_chain import read_chain_sidecar, sha256_lines, verify_version_chain

PUBLISH_FILENAME = "pool-new.txt"


def _read_lines(path):
    with open(path, encoding="utf-8") as f:
        return [l.rstrip("\n") for l in f if l.strip()]


def run_sync(workdir, native_record_path, source_version_sha=None,
             probe_db=None, lock_timeout=30, now=None, post_copy_hook=None):
    """Returns (rc, result_dict). rc 0 = synced, 1 = refused.

    source_version_sha is OPTIONAL (D2): when given it must equal the
    sidecar's source_sha; the binding is otherwise derived from the
    sidecar chain + actual bytes + native record, never from the
    caller's word alone.

    post_copy_hook is TEST-ONLY (D5 fault injection): called with the
    served target path after the copy + rename + fsync and before the
    served re-verification. Production callers pass None.
    """
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
        "binding": "version-chain-v1",
    }
    try:
        lock = PublishLock(lock_path, owner="sync", timeout=lock_timeout)
        lock.acquire()
    except Exception as e:
        result["error"] = "lock_timeout: %s" % type(e).__name__
        return 1, result
    try:
        # --- Blocker 2: EVERYTHING below is inside the held lock. ---
        # Manifests are taken here, not before acquire: a pre-lock
        # manifest can go stale while waiting for the lock.
        result["source_manifest"] = file_manifest(source)
        result["served_manifest_before"] = file_manifest(target)
        # Recovery gate (D3, fail-closed): while stopped, nothing
        # syncs; when the recovery state cannot be established,
        # sync refuses with the specific recovery_state_* /
        # recovery_anchor_* code.
        from .recovery import (  # local: no cycle
            DEFAULT_DEADLINE_HOURS, _enter_degraded_inner, gate_check)
        allowed, gerr, _gstate = gate_check(workdir)
        if not allowed:
            result["error"] = gerr
            return 1, result
        if not os.path.exists(source):
            result["error"] = "source_missing"
            return 1, result
        # --- Blocker 1: verify the sidecar CHAIN, not a bare claim. ---
        _meta, chain = read_chain_sidecar(publish_dir, PUBLISH_FILENAME)
        if chain is None:
            if _meta is None:
                result["error"] = "sync_sidecar_missing"
            else:
                result["error"] = "sync_sidecar_no_version_chain"
            return 1, result
        try:
            source_lines = _read_lines(source)
        except OSError as e:
            result["error"] = "source_unreadable: %s" % type(e).__name__
            return 1, result
        ok, err, csummary = verify_version_chain(
            chain, source_lines, native_record_path,
            probe_db=probe_db, now=now)
        result["version_chain_summary"] = csummary
        if not ok:
            result["error"] = "sync_chain_%s" % err
            return 1, result
        if (source_version_sha is not None
                and source_version_sha != chain["source_sha"]):
            result["error"] = "sync_source_version_mismatch"
            result["sidecar_source_sha_prefix"] = chain["source_sha"][:12]
            return 1, result
        admitted, conditional, gdiag = load_native_allowlist(
            native_record_path, chain["source_sha"],
            probe_db=probe_db, now=now)
        result["gate_diag"] = gdiag
        result["conditional_count"] = len(conditional)
        if gdiag.get("error"):
            result["error"] = "native_gate_%s" % gdiag["error"]
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
        # --- Blocker 2: in-lock SHA before AND after the copy. ---
        source_sha_before = sha256_file(source)
        tmp = target + ".tmp"
        shutil.copyfile(source, tmp)
        try:
            os.chmod(tmp, 0o644)
        except OSError:
            pass
        os.rename(tmp, target)
        _fsync_dir(served_dir)
        # D5: fault-injection point (test-only), then re-verify the
        # SERVED file's actual bytes before reporting success:
        # (a) sha256 of the served lines must equal the chain's
        # published_sha -- not merely equal to the source SHA;
        # (b) the served lines must re-pass the native allowlist gate
        # in full. This runs BEFORE the SHA-equality check below so a
        # served file carrying ungated lines gets the specific
        # sync_served_gate_failed code (and the degraded path), not
        # the generic sync_verify_failed.
        if post_copy_hook is not None:
            post_copy_hook(target)
        served_gate_ok = False
        served_gate_detail = ""
        try:
            served_lines = _read_lines(target)
            served_lines_sha = sha256_lines(served_lines)
            if served_lines_sha != chain["published_sha"]:
                served_gate_detail = (
                    "served_lines_sha_prefix=%s != published_sha_prefix=%s"
                    % (served_lines_sha[:12],
                       chain["published_sha"][:12]))
            else:
                re_kept, _ldiag = gate_lines(served_lines, admitted)
                if len(re_kept) != len(served_lines):
                    served_gate_detail = (
                        "served lines not fully admitted (%d/%d)"
                        % (len(re_kept), len(served_lines)))
                else:
                    served_gate_ok = True
        except OSError as e:
            served_gate_detail = "served_unreadable: %s" % type(e).__name__
        result["served_manifest_after_copy"] = file_manifest(target)
        if not served_gate_ok:
            result["error"] = "sync_served_gate_failed"
            result["served_gate_detail"] = served_gate_detail
            result["served_verified"] = False
            try:
                _enter_degraded_inner(
                    workdir,
                    "sync_served_gate_failed: %s" % served_gate_detail,
                    now, DEFAULT_DEADLINE_HOURS)
            except Exception:
                pass
            return 1, result
        served_after = file_manifest(target)
        source_sha_after = sha256_file(source)
        result["source_sha_before_prefix"] = source_sha_before[:12]
        result["source_sha_after_prefix"] = source_sha_after[:12]
        result["served_manifest_after"] = served_after
        if (served_after is None
                or served_after["sha256"] != source_sha_before
                or source_sha_after != source_sha_before):
            # The served file is NOT what was gated. Report the ACTUAL
            # served version (never claim success), and isolate: enter
            # degraded state so no further publish/sync can run until
            # manual recovery. The served bytes stay as they are --
            # this path means a lock-unaware writer changed the source
            # mid-copy; the runbook covers the manual fix.
            # NOTE: the lock-free inner variant is used here because
            # sync already holds the shared lock (the public
            # enter_degraded would self-deadlock on flock).
            result["error"] = "sync_verify_failed"
            try:
                _enter_degraded_inner(
                    workdir,
                    "sync_verify_failed: served sha_prefix=%s "
                    "source_before=%s source_after=%s" % (
                        served_after["sha_prefix"] if served_after else "",
                        source_sha_before[:12], source_sha_after[:12]),
                    now, DEFAULT_DEADLINE_HOURS)
            except Exception:
                pass
            return 1, result
        result.update({
            "ok": True,
            "served_verified": True,
            "served_version_sha": served_after["sha256"],
            "lock_owner": lock.owner_record(),
        })
        # The served file carries the same version chain as the publish
        # file, so its provenance stays verifiable in the served dir.
        copy_sidecar(publish_dir, PUBLISH_FILENAME, served_dir)
        return 0, result
    finally:
        lock.release()


def main(argv=None):
    ap = argparse.ArgumentParser(description="D2 gated sync (isolation)")
    ap.add_argument("--workdir", required=True)
    ap.add_argument("--native-record", required=True)
    ap.add_argument("--source-version", default=None,
                    help="optional: must equal the sidecar's source_sha "
                         "when given; the binding is otherwise derived "
                         "from the sidecar chain + actual bytes")
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
