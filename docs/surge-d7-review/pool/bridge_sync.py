"""D6 bridge sync (Issue #73, GPT D5 review 6887615694, item 2).

Replaces the shell copy block of gate-sync.sh (D4/D5), which had a
check -> copy race: `pool.sync` released the shared lock, then the
shell read served, checked its SHA, and copied it to the bridge.
A lock-unaware writer rewriting served AFTER the SHA check and
BEFORE/DURING the copy could put unverified bytes on the bridge
(the post-copy bridge SHA check caught the mismatch but only AFTER
the polluted bytes had already been renamed onto the HTTP entry),
and a legacy $OLD write failure was only logged while the script
still exited rc=0 (fake success).

D6 design -- one lock, one immutable snapshot, dual-target atomicity:
  1. The whole step runs under the SAME shared flock as publish /
     sync / rollback. Served is re-read and re-verified INSIDE the
     held lock (SHA == chain published_sha + native allowlist re-gate
     on the actual bytes), never trusting a reported SHA.
  2. The verified served bytes are read ONCE into memory. That
     in-memory snapshot is immutable: every downstream write (bridge
     and legacy) writes THOSE bytes, never re-reads the served file.
     A writer rewriting served mid-flight cannot change what lands
     on the bridge.
  3. Bridge and legacy are updated by TWO CONSECUTIVE atomic
     renames under one lock -- NOT a true cross-file atomic
     transaction (D7, GPT D6 review 6904538782: the D6 docstring's
     "ONE atomic unit" wording was wrong and is corrected here).
     Both get the snapshot bytes and both are re-read and
     SHA-verified after the rename. If either write FAILS
     (detected: non-zero return / post-write SHA mismatch), the
     other is restored to its pre-run bytes (rollback, verified)
     and the run fails loudly (rc=1, error legacy_copy_failed /
     bridge_copy_failed / bridge_sha_mismatch). A CRASH between
     the two renames (process killed after the bridge rename,
     before the legacy write) leaves bridge=new / legacy=old:
     that state is DETECTABLE (verify_targets() below; bridge SHA
     != legacy SHA) and the NEXT run repairs it from the verified
     snapshot. A critical-target failure never exits 0, and a
     crash never leaves a false success.

D7 additions (GPT D6 review 6904538782, item 2):
  - verify_targets(workdir, bridge_dir, old_path): read-only
    consistency check -- served / bridge / legacy SHAs against
    the chain published_sha. Also available as
    `python3 -m pool.bridge_sync --verify-targets ...` for the
    switch-window manual check (see switch-runbook.md 11.5).
  - TEST-ONLY hooks: bridge_post_rename_hook / legacy_post_rename_
    hook (corrupt the just-renamed file to prove the post-write
    SHA check catches it) and post_bridge_hook (raise after the
    bridge rename verified, before the legacy write, to simulate
    a process crash between the two renames). Production callers
    pass None for all hooks.
  4. After the bridge + legacy writes, served is re-read once more
     under the same lock. If it changed after the snapshot, the bridge
     already holds verified bytes (recorded as such), but the served
     tamper is contained: the polluted file is quarantined and the
     last verified version restored (pool/sync.py helper), the pool
     enters degraded (STOP), and the run returns rc=1
     `served_changed_after_bridge_copy`.

Usage (subprocess, as gate-sync.sh invokes it):
  python3 -m pool.bridge_sync --workdir <dir> --bridge-dir <dir>
      --native-record <file> [--old-path <file>] [--probe-db <file>]
      [--lock-timeout 30]

Exit code 0 = bridge (+ legacy) updated with verified bytes,
1 = refused/failed (bridge rolled back to pre-run bytes when the
failure happened after the bridge write), 2 = usage.
stdout is a single JSON object (desensitised: counts, SHA prefixes;
the full snapshot SHA is carried, as D5 sync does for
served_version_sha, so the caller can compare it byte-for-byte).
"""

import argparse
import hashlib
import json
import os
import sys
import time

from .native_gate import gate_lines, load_native_allowlist
from .publish_lock import (
    PublishLock, _fsync_dir, file_manifest, sha256_file,
)
from .sync import _quarantine_and_restore_served
from .version_chain import read_chain_sidecar, verify_version_chain

PUBLISH_FILENAME = "pool-new.txt"


def _read_lines(path):
    with open(path, encoding="utf-8") as f:
        return [l.rstrip("\n") for l in f if l.strip()]


def _write_bytes_verified(path, data, expect_sha, mode=0o644,
                          post_rename_hook=None):
    """Write `data` to `path` via tmp + rename + fsync, then re-read
    and verify the SHA. Returns (ok, manifest_or_None). On a pre-rename
    failure the tmp file is removed and the target is untouched; on a
    post-rename mismatch the caller must roll back (see
    run_bridge_sync). Never raises.

    post_rename_hook is TEST-ONLY (D7 fault injection): called with
    the target path just after rename + dir fsync, before the re-read
    verify, so a test can corrupt the just-renamed file and prove the
    post-write SHA check catches it. A hook exception is treated as a
    write failure (ok=False). Production passes None."""
    tmp = path + ".tmp"
    try:
        with open(tmp, "wb") as f:
            f.write(data)
            f.flush()
            os.fsync(f.fileno())
        try:
            os.chmod(tmp, mode)
        except OSError:
            pass
        os.rename(tmp, path)
        _fsync_dir(os.path.dirname(path) or ".")
    except OSError:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        return False, file_manifest(path)
    if post_rename_hook is not None:
        try:
            post_rename_hook(path)
        except Exception:
            return False, file_manifest(path)
    got = file_manifest(path)
    if got is None or got["sha256"] != expect_sha:
        return False, got
    return True, got


def _restore_bytes(path, data, expect_sha, mode=0o644):
    """Best-effort restore of `path` to `data` (pre-run bytes).
    Returns (ok, manifest_or_None). When the pre-run state was
    "absent" (data is None), the path is removed instead."""
    if data is None:
        try:
            os.unlink(path)
        except OSError:
            pass
        _fsync_dir(os.path.dirname(path) or ".")
        return (not os.path.exists(path)), file_manifest(path)
    return _write_bytes_verified(path, data, expect_sha, mode=mode)


def verify_targets(workdir, bridge_dir, old_path=None):
    """Read-only dual-target consistency check (D7, GPT D6 review).

    Compares the served file, the bridge file and (when given) the
    legacy file against the chain's published_sha. Returns a dict;
    never raises. consistent=True only when every target holds
    exactly the chain-verified bytes. A crash between the two
    renames shows up here as bridge_sha == published_sha while
    legacy_sha == the previous version (detail legacy_sha_mismatch).
    """
    served_dir = os.path.join(workdir, "served")
    served_file = os.path.join(served_dir, PUBLISH_FILENAME)
    bridge_file = os.path.join(bridge_dir, PUBLISH_FILENAME)
    out = {"served_sha": None, "bridge_sha": None, "legacy_sha": None,
           "published_sha": None, "consistent": False, "detail": ""}
    try:
        _meta, chain = read_chain_sidecar(served_dir, PUBLISH_FILENAME)
    except Exception:
        out["detail"] = "chain_unreadable"
        return out
    if chain is None:
        out["detail"] = "served_no_chain"
        return out
    published = chain.get("published_sha")
    out["published_sha"] = published
    for key, path in (("served_sha", served_file),
                      ("bridge_sha", bridge_file),
                      ("legacy_sha", old_path)):
        if path is None:
            continue
        try:
            out[key] = sha256_file(path)
        except OSError:
            out[key] = None
    if out["served_sha"] != published:
        out["detail"] = "served_sha_mismatch"
    elif out["bridge_sha"] != published:
        out["detail"] = "bridge_sha_mismatch"
    elif old_path is not None and out["legacy_sha"] != published:
        out["detail"] = "legacy_sha_mismatch"
    else:
        out["consistent"] = True
        out["detail"] = "all_targets_match_published_sha"
    return out


def run_bridge_sync(workdir, bridge_dir, old_path=None,
                    native_record_path=None, probe_db=None, lock_timeout=30,
                    now=None, pre_bridge_rename_hook=None,
                    bridge_post_rename_hook=None,
                    legacy_post_rename_hook=None,
                    post_bridge_hook=None):
    """Returns (rc, result_dict). rc 0 = bridge (+ legacy) updated
    with verified bytes, 1 = refused/failed (see module docstring).

    pre_bridge_rename_hook is TEST-ONLY (D6 fault injection): called
    with the bridge tmp path just before its rename, so a test can
    rewrite the SERVED file at that exact moment and prove the bridge
    still receives only the immutable snapshot bytes. Production
    callers pass None.

    bridge_post_rename_hook / legacy_post_rename_hook are TEST-ONLY
    (D7): called with the target path just after its rename, before
    the post-write SHA verify, so a test can corrupt the just-renamed
    file and prove the verify catches it. Production passes None.

    post_bridge_hook is TEST-ONLY (D7 crash injection): called after
    the bridge rename verified, before the legacy write. An exception
    here PROPAGATES out of run_bridge_sync (the drill subprocess
    dies mid-run, simulating a process crash between the two
    renames): bridge holds the new snapshot, legacy still holds its
    pre-run bytes. The flock is released by the kernel on process
    death, so the next run can still acquire the lock and repair.
    Production passes None.
    """
    now = int(now if now is not None else time.time())
    served_dir = os.path.join(workdir, "served")
    lock_path = os.path.join(workdir, "lock", "publish.lock")
    served_file = os.path.join(served_dir, PUBLISH_FILENAME)
    bridge_file = os.path.join(bridge_dir, PUBLISH_FILENAME)
    result = {
        "ok": False,
        "path": "bridge_sync",
        "checked_at": now,
        "bridge_updated_verified": False,
    }
    if native_record_path is None:
        result["error"] = "bridge_native_record_required"
        return 1, result
    try:
        lock = PublishLock(lock_path, owner="bridge_sync",
                           timeout=lock_timeout)
        lock.acquire()
    except Exception as e:
        result["error"] = "lock_timeout: %s" % type(e).__name__
        return 1, result
    try:
        # D6: served must be a regular file inside this workdir's
        # served dir, never a symlink (same guard as pool.sync).
        if os.path.islink(served_dir) or (
                os.path.lexists(served_file)
                and os.path.islink(served_file)):
            result["error"] = "served_symlink_refused"
            return 1, result
        if not os.path.exists(served_file):
            result["error"] = "bridge_served_missing"
            return 1, result
        _meta, chain = read_chain_sidecar(served_dir, PUBLISH_FILENAME)
        if chain is None:
            result["error"] = "bridge_served_no_chain"
            return 1, result
        # --- Step 1+2 (in-lock): re-verify served actual bytes, then
        # snapshot them ONCE into memory. Everything downstream
        # writes these bytes, never re-reads served.
        try:
            with open(served_file, "rb") as _f:
                served_bytes = _f.read()
        except OSError as e:
            result["error"] = "bridge_served_unreadable: %s" % type(e).__name__
            return 1, result
        snapshot_sha = hashlib.sha256(served_bytes).hexdigest()
        result["served_snapshot_sha"] = snapshot_sha
        result["served_snapshot_sha_prefix"] = snapshot_sha[:12]
        served_lines = [l for l in served_bytes.decode(
            "utf-8", errors="ignore").splitlines() if l.strip()]
        ok, err, csummary = verify_version_chain(
            chain, served_lines, native_record_path,
            probe_db=probe_db, now=now)
        result["version_chain_summary"] = csummary
        if not ok:
            result["error"] = "bridge_served_chain_%s" % err
            qr = _quarantine_and_restore_served(
                workdir, chain, _admitted_for(workdir, chain,
                                              native_record_path,
                                              probe_db, now), now)
            result["served_quarantine"] = qr
            result["served_restored"] = qr["restored"]
            _enter_degraded_quiet(workdir, now,
                                  "bridge_served_chain_%s; %s"
                                  % (err, qr["detail"]))
            return 1, result
        admitted, _cond, gdiag = load_native_allowlist(
            native_record_path, chain["source_sha"],
            probe_db=probe_db, now=now)
        if gdiag.get("error"):
            result["error"] = "bridge_native_gate_%s" % gdiag["error"]
            return 1, result
        if snapshot_sha != chain["published_sha"]:
            result["error"] = "bridge_served_gate_failed"
            result["served_gate_detail"] = (
                "served sha_prefix=%s != published_sha_prefix=%s"
                % (snapshot_sha[:12], chain["published_sha"][:12]))
            qr = _quarantine_and_restore_served(
                workdir, chain, admitted, now)
            result["served_quarantine"] = qr
            result["served_restored"] = qr["restored"]
            _enter_degraded_quiet(workdir, now,
                                  "bridge_served_gate_failed; %s"
                                  % qr["detail"])
            return 1, result
        re_kept, _ldiag = gate_lines(served_lines, admitted)
        if len(re_kept) != len(served_lines):
            result["error"] = "bridge_served_gate_failed"
            result["served_gate_detail"] = (
                "served lines not fully admitted (%d/%d)"
                % (len(re_kept), len(served_lines)))
            qr = _quarantine_and_restore_served(
                workdir, chain, admitted, now)
            result["served_quarantine"] = qr
            result["served_restored"] = qr["restored"]
            _enter_degraded_quiet(workdir, now,
                                  "bridge_served_gate_failed; %s"
                                  % qr["detail"])
            return 1, result
        result["served_verified"] = True
        # --- Step 3: bridge write from the immutable snapshot.
        os.makedirs(bridge_dir, exist_ok=True)
        try:
            with open(bridge_file, "rb") as f:
                bridge_before_bytes = f.read()
            bridge_before_sha = hashlib.sha256(
                bridge_before_bytes).hexdigest()
        except OSError:
            bridge_before_bytes = None
            bridge_before_sha = None
        result["bridge_manifest_before"] = file_manifest(bridge_file)
        bridge_tmp = bridge_file + ".tmp"
        try:
            with open(bridge_tmp, "wb") as f:
                f.write(served_bytes)
                f.flush()
                os.fsync(f.fileno())
            try:
                os.chmod(bridge_tmp, 0o644)
            except OSError:
                pass
            if pre_bridge_rename_hook is not None:
                try:
                    pre_bridge_rename_hook(bridge_tmp)
                except Exception:
                    # A failing injection hook must not crash the
                    # bridge step into an unhandled exception: treat
                    # it as a bridge copy failure (tmp removed, bridge
                    # untouched, rc=1 below).
                    try:
                        os.unlink(bridge_tmp)
                    except OSError:
                        pass
                    result["error"] = "bridge_copy_failed: hook_failed"
                    result["bridge_manifest_after"] = file_manifest(
                        bridge_file)
                    return 1, result
            os.rename(bridge_tmp, bridge_file)
            _fsync_dir(bridge_dir)
        except OSError as e:
            try:
                os.unlink(bridge_tmp)
            except OSError:
                pass
            result["error"] = "bridge_copy_failed: %s" % type(e).__name__
            result["bridge_manifest_after"] = file_manifest(bridge_file)
            return 1, result
        if bridge_post_rename_hook is not None:
            try:
                bridge_post_rename_hook(bridge_file)
            except Exception:
                # The post-rename SHA verify below is the arbiter: if
                # the hook corrupted the file it fails there and the
                # bridge is restored; a hook bug that left the bytes
                # intact still passes the verify.
                pass
        bridge_after = file_manifest(bridge_file)
        result["bridge_manifest_after"] = bridge_after
        if bridge_after is None or bridge_after["sha256"] != snapshot_sha:
            # Post-rename mismatch: the bytes on the bridge are not
            # the verified snapshot. Restore the pre-run bridge bytes
            # (verified) and fail loudly -- never leave unverified
            # bytes on the HTTP entry.
            rb_ok, rb_manifest = _restore_bytes(
                bridge_file, bridge_before_bytes, bridge_before_sha)
            result["error"] = "bridge_sha_mismatch"
            result["bridge_rolled_back"] = rb_ok
            result["bridge_manifest_after_rollback"] = rb_manifest
            return 1, result
        result["bridge_updated_verified"] = True
        # D7 TEST-ONLY crash injection: an exception here propagates
        # out of run_bridge_sync (simulated process crash between the
        # two renames). The finally block below still releases the
        # flock for the in-process case; a real SIGKILL relies on the
        # kernel releasing the flock on process death.
        if post_bridge_hook is not None:
            post_bridge_hook(bridge_file)
        # --- Step 4: legacy target, same snapshot bytes, same
        # verification. On failure the bridge is rolled back to its
        # pre-run bytes so the two targets never diverge silently.
        legacy_manifest = None
        if old_path:
            try:
                with open(old_path, "rb") as f:
                    legacy_before_bytes = f.read()
                legacy_before_sha = hashlib.sha256(
                    legacy_before_bytes).hexdigest()
            except OSError:
                legacy_before_bytes = None
                legacy_before_sha = None
            result["legacy_manifest_before"] = file_manifest(old_path)
            # No makedirs for the legacy parent: a missing parent dir
            # must FAIL the legacy copy (legacy_copy_failed +
            # bridge rollback), never silently create directories.
            leg_ok, leg_manifest = _write_bytes_verified(
                old_path, served_bytes, snapshot_sha,
                post_rename_hook=legacy_post_rename_hook)
            legacy_manifest = leg_manifest
            result["legacy_manifest_after"] = leg_manifest
            if not leg_ok:
                rb_ok, rb_manifest = _restore_bytes(
                    bridge_file, bridge_before_bytes, bridge_before_sha)
                result["error"] = "legacy_copy_failed"
                result["bridge_rolled_back"] = rb_ok
                result["bridge_manifest_after_rollback"] = rb_manifest
                result["bridge_updated_verified"] = False
                return 1, result
        result["legacy_manifest"] = legacy_manifest
        # --- Step 5: post-copy served re-check, still under the lock.
        # The bridge already holds verified bytes; if served changed
        # after the snapshot, contain the tamper (quarantine +
        # restore + STOP) and fail the run -- the next sync refuses
        # until manual recovery.
        try:
            served_now_sha = sha256_file(served_file)
        except OSError as e:
            served_now_sha = "unreadable:%s" % type(e).__name__
        if served_now_sha != snapshot_sha:
            qr = _quarantine_and_restore_served(
                workdir, chain, admitted, now)
            result["served_quarantine"] = qr
            result["served_restored"] = qr["restored"]
            result["error"] = "served_changed_after_bridge_copy"
            result["served_gate_detail"] = (
                "served sha_prefix=%s after bridge copy != snapshot "
                "sha_prefix=%s"
                % (str(served_now_sha)[:12], snapshot_sha[:12]))
            _enter_degraded_quiet(workdir, now,
                                  "served_changed_after_bridge_copy; %s"
                                  % qr["detail"])
            return 1, result
        result.update({
            "ok": True,
            "served_snapshot_lines": len(served_lines),
            "bridge_manifest": bridge_after,
            "lock_owner": lock.owner_record(),
        })
        return 0, result
    finally:
        lock.release()


def _admitted_for(workdir, chain, native_record_path, probe_db, now):
    """Allowlist for the chain's source version (best-effort; empty
    set when the record cannot be loaded -- the quarantine helper
    then cannot restore, which it reports instead of raising)."""
    try:
        admitted, _cond, gdiag = load_native_allowlist(
            native_record_path, chain["source_sha"],
            probe_db=probe_db, now=now)
        if gdiag.get("error"):
            return set()
        return admitted
    except Exception:
        return set()


def _enter_degraded_quiet(workdir, now, reason):
    """Enter degraded (STOP) without ever raising out of the caller:
    a failed containment must still be recorded, never crash the
    bridge step into an unhandled exception."""
    try:
        from .recovery import (  # local: no cycle
            DEFAULT_DEADLINE_HOURS, _enter_degraded_inner)
        _enter_degraded_inner(workdir, reason, now,
                              DEFAULT_DEADLINE_HOURS)
    except Exception:
        pass


def main(argv=None):
    ap = argparse.ArgumentParser(description="D6 gated bridge sync "
                                            "(isolation)")
    ap.add_argument("--workdir", required=True)
    ap.add_argument("--bridge-dir", required=True)
    ap.add_argument("--old-path", default=None)
    ap.add_argument("--native-record", default=None)
    ap.add_argument("--probe-db", default=None)
    ap.add_argument("--lock-timeout", type=float, default=30)
    ap.add_argument("--verify-targets", action="store_true",
                    help="D7: read-only consistency check of served / "
                         "bridge / legacy SHAs against the chain "
                         "published_sha; rc 0 = consistent, 1 = mismatch")
    args = ap.parse_args(argv)
    if args.verify_targets:
        res = verify_targets(args.workdir, args.bridge_dir,
                             old_path=args.old_path)
        print(json.dumps(res, ensure_ascii=False))
        return 0 if res["consistent"] else 1
    if args.native_record is None:
        ap.error("--native-record is required unless --verify-targets")
    rc, result = run_bridge_sync(
        args.workdir, args.bridge_dir, old_path=args.old_path,
        native_record_path=args.native_record, probe_db=args.probe_db,
        lock_timeout=args.lock_timeout)
    print(json.dumps(result, ensure_ascii=False))
    return rc


if __name__ == "__main__":
    sys.exit(main())
