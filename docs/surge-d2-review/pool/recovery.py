"""D2 failure recovery (GPT D1 review 6881291219, blocker 3).

Problem (D1): run_rollback depended on the old version's native results
still being inside the 24 h TTL and all passing. A real emergency
usually happens AFTER the TTL expired or after a new failing round, so
rollback could refuse exactly when it was needed most -- and the only
fallback ("keep the old served file") was presented as if it were a
qualified state. It is not: a served file whose evidence is stale is
STALE, not qualified.

Model (explicit states, never implicit):
  ok               normal operation; publish/sync/rollback run gated.
  degraded         STOP marker set: publish and sync refuse with
                   `pool_stopped`; the served file is whatever it was
                   and is explicitly flagged NOT qualified
                   (stale-not-qualified / broken-unqualified). A
                   deadline (default 24 h) for manual action is
                   recorded; the state never auto-heals.
  manual-restored  STOP marker STILL set; the served file was restored
                   to the last-verified-safe anchor by the controlled
                   manual path (owner ack required). The restored
                   version is flagged "restored-unverified-current":
                   it is the best known-good version, it is NOT
                   claimed currently qualified, and a fresh native
                   re-test is REQUIRED before the pool can return to ok.

Transitions:
  ok -> degraded            enter_degraded() (operator, or the runbook
                            after a refused rollback on broken prod)
  degraded -> manual-restored
                            manual_restore() with OWNER_ACK and an
                            anchor classified last_verified_safe
  manual-restored -> ok     clear_stop() with OWNER_ACK AND a fresh
                            native gate pass for the served version
  degraded -> ok            clear_stop() with OWNER_ACK AND a fresh
                            native gate pass (fresh evidence can also
                            come from a brand-new publish cycle, which
                            itself requires the stop to be cleared
                            first -- so the operator clears the stop
                            only after a fresh native test exists)
  Any state -> degraded     enter_degraded() is idempotent.

The STOP marker and the state file live in <workdir>/recovery-state.json
(600). All state writes happen under the SHARED flock, so a state
transition can never race a publish/sync: publish/sync check the
marker INSIDE their held lock, and recovery transitions take the lock
to write.

Owner acks are explicit typed confirmations, not secrets:
  OWNER_ACK_RESTORE = "OWNER-ACK-RESTORE-LAST-VERIFIED-SAFE"
  OWNER_ACK_CLEAR   = "OWNER-ACK-CLEAR-STOP"
They exist so a manual restore / stop-clear can never happen by
accident or by a timer: a human must type the acknowledgement.

assess_anchors() classifies every rollback anchor (.prev + history):
  verified_safe       chain verifies AND native evidence for the
                      anchor's version is fresh (TTL) and fully
                      admits the anchor's lines
  last_verified_safe  chain verifies AND the anchor's lines were fully
                      admitted by evidence that has since gone STALE
                      (TTL expired) with no subsequent failure -- the
                      best restorable version, manual path only
  unrecoverable       no sidecar / chain fails / no evidence for the
                      version / evidence says fail-or-slow / a
                      subsequent native failure voided the pass

"Keeping the old served file" is NEVER reported as qualified: status()
computes served_status from the native record at `now` -- qualified /
stale-not-qualified / broken-unqualified / manual-restored-unverified /
unknown-no-evidence -- and says so in plain words.

All output is desensitised: counts, SHA prefixes, timestamps, state
names. No passwords, URIs, tokens, or subscription URLs.
"""

import json
import os
import time

from .native_gate import (
    has_subsequent_native_failure, latest_same_version_by_fp,
    load_native_allowlist, load_native_record, NATIVE_TTL_SECONDS,
    NATIVE_THRESHOLD_MS,
)
from .publish_lock import (
    PublishLock, _atomic_write_inner, _fsync_dir, _iso, copy_sidecar,
    file_manifest, read_version_meta, sha256_file,
)
from .version_chain import (
    fingerprints_of_lines, read_chain_sidecar, verify_version_chain,
)

STATE_FILENAME = "recovery-state.json"
PUBLISH_FILENAME = "pool-new.txt"
OWNER_ACK_RESTORE = "OWNER-ACK-RESTORE-LAST-VERIFIED-SAFE"
OWNER_ACK_CLEAR = "OWNER-ACK-CLEAR-STOP"
DEFAULT_DEADLINE_HOURS = 24


def _state_path(workdir):
    return os.path.join(workdir, STATE_FILENAME)


def _default_state(now):
    return {
        "state": "ok",
        "stopped": False,
        "since": now,
        "since_iso": _iso(now),
        "reason": "",
        "served_status": "unknown-no-evidence",
        "served_sha_prefix": "",
        "served_lines": 0,
        "deadline_iso": "",
        "requires_fresh_native_retest": False,
        "history": [],
    }


def read_state(workdir):
    """Current recovery state, or the default ok-state when absent."""
    path = _state_path(workdir)
    try:
        with open(path, encoding="utf-8") as f:
            state = json.load(f)
        if isinstance(state, dict) and state.get("state") in (
                "ok", "degraded", "manual-restored"):
            return state
    except (OSError, ValueError):
        pass
    return _default_state(int(time.time()))


def is_stopped(workdir):
    """True when the STOP marker is set (publish/sync must refuse)."""
    return bool(read_state(workdir).get("stopped"))


def _write_state(workdir, state):
    state["updated_at"] = int(time.time())
    state["updated_at_iso"] = _iso()
    path = _state_path(workdir)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(state, f, ensure_ascii=False, indent=2)
    try:
        os.chmod(tmp, 0o600)
    except OSError:
        pass
    os.rename(tmp, path)
    _fsync_dir(workdir)
    return state


def _history_append(state, event, detail=""):
    state.setdefault("history", []).append({
        "event": event, "at": int(time.time()), "at_iso": _iso(),
        "detail": detail,
    })


def _read_lines(path):
    with open(path, encoding="utf-8") as f:
        return [l.rstrip("\n") for l in f if l.strip()]


def _anchor_candidates(publish_dir):
    """All rollback anchors: .prev first, then history newest-first."""
    out = []
    prev = os.path.join(publish_dir, PUBLISH_FILENAME + ".prev")
    if os.path.exists(prev):
        out.append((prev, ".prev"))
    hist_dir = os.path.join(publish_dir, "history")
    if os.path.isdir(hist_dir):
        snaps = sorted(
            (os.path.join(hist_dir, f) for f in os.listdir(hist_dir)
             if f.startswith("pool-new-") and f.endswith(".txt")),
            key=lambda p: os.path.getmtime(p), reverse=True)
        for snap in snaps:
            out.append((snap, "history-snapshot"))
    return out


def _classify_anchor(anchor_path, anchor_kind, native_record_path,
                     probe_db, now):
    """Classify one anchor. Returns a dict (never raises)."""
    info = {
        "kind": anchor_kind,
        "path": os.path.basename(anchor_path),
        "status": "unrecoverable",
        "reason": "",
        "lines": 0,
        "sha_prefix": "",
        "source_version_sha_prefix": "",
        "last_verified_at": None,
        "age_s": None,
    }
    manifest = file_manifest(anchor_path)
    if manifest is None:
        info["reason"] = "anchor_unreadable"
        return info
    info["lines"] = manifest["lines"]
    info["sha_prefix"] = manifest["sha_prefix"]
    try:
        anchor_lines = _read_lines(anchor_path)
    except OSError:
        info["reason"] = "anchor_unreadable"
        return info
    meta, chain = read_chain_sidecar(
        os.path.dirname(anchor_path),
        os.path.basename(anchor_path))
    if chain is None:
        # D1 v1-only sidecar: source_version_sha without a chain.
        # Chain verification is impossible, so the anchor cannot be
        # proven to match its evidence -- unrecoverable in D2.
        if meta is not None and meta.get("source_version_sha"):
            info["reason"] = "anchor_sidecar_v1_no_chain"
        else:
            info["reason"] = "anchor_no_version_meta"
        return info
    source_sha = chain.get("source_sha")
    info["source_version_sha_prefix"] = (source_sha or "")[:12]
    ok, err, _summary = verify_version_chain(
        chain, anchor_lines, native_record_path, probe_db=probe_db, now=now)
    if not ok:
        info["reason"] = "chain_%s" % err
        return info
    # Chain verifies: the anchor bytes match the evidence version.
    # Now classify the EVIDENCE for that version.
    record, rec_err = load_native_record(native_record_path)
    if rec_err is not None:
        info["reason"] = "native_record_%s" % rec_err
        return info
    same = latest_same_version_by_fp(record, source_sha)
    fps, unparsable = fingerprints_of_lines(anchor_lines)
    if unparsable:
        info["reason"] = "anchor_lines_unparsable"
        return info
    if not fps:
        info["reason"] = "anchor_empty"
        return info
    if any(fp not in same for fp in fps):
        info["reason"] = "no_same_version_evidence"
        return info
    # Newest same-version tested_at across the anchor's fingerprints.
    tested_at = max(same[fp][0]["tested_at"] for fp in fps)
    info["last_verified_at"] = tested_at
    info["age_s"] = now - tested_at
    # Any same-version failure/slow for these fingerprints?
    for fp in fps:
        _run, result = same[fp]
        if not result["success"]:
            info["reason"] = "same_version_native_failed"
            return info
        ms = result.get("ms")
        if ms is None or ms >= NATIVE_THRESHOLD_MS:
            info["reason"] = "same_version_native_slow"
            return info
    # Any subsequent failure at-or-after the pass (D2 >= rule)?
    for fp in fps:
        if has_subsequent_native_failure(record, fp, tested_at):
            info["reason"] = "subsequent_native_failed"
            return info
    if tested_at <= 0 or tested_at > now:
        info["reason"] = "evidence_ts_invalid"
        return info
    if now - tested_at > NATIVE_TTL_SECONDS:
        # Evidence WAS fully passing but is now stale: the anchor is
        # the last-verified-safe version -- manual path only.
        info["status"] = "last_verified_safe"
        info["reason"] = "evidence_stale_ttl_expired"
        return info
    info["status"] = "verified_safe"
    info["reason"] = "evidence_fresh_and_passing"
    return info


def assess_anchors(workdir, native_record_path, probe_db=None, now=None):
    """Classify every rollback anchor. Returns an assessment dict.

    last_verified_safe: the NEWEST anchor classified last_verified_safe
    (or None). best_verified_safe: the newest verified_safe anchor.
    recommended_action: "rollback" | "manual-recovery" |
    "rebuild-from-fresh-native-test".
    """
    now = int(now if now is not None else time.time())
    publish_dir = os.path.join(workdir, "publish")
    anchors = []
    for anchor_path, kind in _anchor_candidates(publish_dir):
        anchors.append(_classify_anchor(
            anchor_path, kind, native_record_path, probe_db, now))
    verified = [a for a in anchors if a["status"] == "verified_safe"]
    last_safe = [a for a in anchors if a["status"] == "last_verified_safe"]
    # Newest first within each class (list order is already newest-first
    # for history; .prev precedes history).
    best_verified = verified[0] if verified else None
    best_last_safe = last_safe[0] if last_safe else None
    if best_verified is not None:
        recommended = "rollback"
    elif best_last_safe is not None:
        recommended = "manual-recovery"
    else:
        recommended = "rebuild-from-fresh-native-test"
    return {
        "checked_at": now,
        "anchors": anchors,
        "verified_safe_count": len(verified),
        "last_verified_safe_count": len(last_safe),
        "best_verified_safe": best_verified,
        "last_verified_safe": best_last_safe,
        "recommended_action": recommended,
    }


def _served_status(workdir, native_record_path, probe_db=None, now=None):
    """Compute the served file's qualification from live evidence.

    Returns (status, sha_prefix, lines): status is one of
      qualified                chain verifies AND the gate currently
                               admits every served line (fresh, passing)
      stale-not-qualified      chain verifies AND the evidence says
                               the lines passed, but the evidence is
                               STALE (TTL expired) or its timestamps
                               are invalid -- the file is intact, the
                               proof is old. NEVER reported as qualified.
      broken-unqualified       chain fails, or the file's lines do not
                               match what the phone measured (evidence
                               says fail/slow, or no evidence at all)
      unknown-no-evidence      the native record itself is missing /
                               unreadable
      manual-restored-unverified (only reported by status(), never
                               invented here)
    The stale/broken distinction matters: a stale file may be restored
    by a fresh native re-test; a broken file must never be served.
    """
    now = int(now if now is not None else time.time())
    served = os.path.join(workdir, "served", PUBLISH_FILENAME)
    manifest = file_manifest(served)
    if manifest is None:
        return "unknown-no-evidence", "", 0
    try:
        lines = _read_lines(served)
    except OSError:
        return "broken-unqualified", manifest["sha_prefix"], manifest["lines"]
    served_dir = os.path.dirname(served)
    _meta, chain = read_chain_sidecar(served_dir, PUBLISH_FILENAME)
    if chain is None:
        # Served file with no verifiable chain: unproven provenance.
        return "broken-unqualified", manifest["sha_prefix"], manifest["lines"]
    ok, _err, _summary = verify_version_chain(
        chain, lines, native_record_path, probe_db=probe_db, now=now)
    if not ok:
        return "broken-unqualified", manifest["sha_prefix"], manifest["lines"]
    # Chain verifies: the file IS the version the phone measured.
    # Does the evidence still say these lines pass (ignoring TTL)?
    from .native_gate import evidence_admitted_fps
    record, rec_err = load_native_record(native_record_path)
    if rec_err is not None:
        return "unknown-no-evidence", manifest["sha_prefix"], manifest["lines"]
    fps, unparsable = fingerprints_of_lines(lines)
    if unparsable:
        return "broken-unqualified", manifest["sha_prefix"], manifest["lines"]
    evidence = evidence_admitted_fps(record, chain["source_sha"])
    if not fps.issubset(evidence):
        # Evidence says fail/slow (or nothing) for these lines.
        return "broken-unqualified", manifest["sha_prefix"], manifest["lines"]
    # Evidence says pass; is it still fresh?
    admitted, _cond, gdiag = load_native_allowlist(
        native_record_path, chain["source_sha"], probe_db=probe_db, now=now)
    if gdiag.get("error"):
        return "unknown-no-evidence", manifest["sha_prefix"], manifest["lines"]
    if fps.issubset(set(admitted)):
        return "qualified", manifest["sha_prefix"], manifest["lines"]
    # Evidence passes but the gate does not admit: WHY?
    rejected = gdiag.get("rejected_prefixes", {})
    stale_only = True
    for fp in fps:
        reason = rejected.get(fp[:12], "")
        if not (reason.startswith("native_age_s=")
                or reason == "native_ts_invalid"):
            stale_only = False
            break
    if stale_only:
        return "stale-not-qualified", manifest["sha_prefix"], manifest["lines"]
    return "broken-unqualified", manifest["sha_prefix"], manifest["lines"]


def status(workdir, native_record_path=None, probe_db=None, now=None):
    """Full recovery status: state file + live served qualification."""
    now = int(now if now is not None else time.time())
    state = read_state(workdir)
    out = dict(state)
    if native_record_path:
        served_status, prefix, lines = _served_status(
            workdir, native_record_path, probe_db=probe_db, now=now)
        # A manual restore is never re-labelled "qualified" or merely
        # "stale" by this helper: the file was restored by hand from
        # old evidence and is unverified until a fresh native re-test
        # passes and the stop is cleared. (A "broken-unqualified"
        # live verdict is left as-is: it is more alarming and correct.)
        if (state.get("state") == "manual-restored"
                and served_status in ("qualified", "stale-not-qualified")):
            served_status = "manual-restored-unverified"
        out["served_status_live"] = served_status
        out["served_sha_prefix_live"] = prefix
        out["served_lines_live"] = lines
    return out


def _enter_degraded_inner(workdir, reason, now, deadline_hours):
    """Lock-free inner state write. CALLER MUST HOLD THE SHARED LOCK."""
    state = read_state(workdir)
    served = file_manifest(os.path.join(workdir, "served", PUBLISH_FILENAME))
    state.update({
        "state": "degraded",
        "stopped": True,
        "since": now,
        "since_iso": _iso(now),
        "reason": reason,
        "served_sha_prefix": served["sha_prefix"] if served else "",
        "served_lines": served["lines"] if served else 0,
        # The served file is NOT claimed qualified: its evidence
        # is stale or its provenance is broken -- that is exactly
        # why we are degraded.
        "served_status": "stale-not-qualified",
        "deadline_iso": _iso(now + deadline_hours * 3600),
        "requires_fresh_native_retest": True,
    })
    _history_append(state, "enter-degraded", reason)
    _write_state(workdir, state)
    return state


def enter_degraded(workdir, reason, now=None, deadline_hours=None):
    """Enter degraded state: STOP publishing/syncing, flag served stale.

    Never touches publish/served files. Idempotent. Writes under the
    shared lock. Returns (rc, result).
    """
    now = int(now if now is not None else time.time())
    deadline_hours = (DEFAULT_DEADLINE_HOURS if deadline_hours is None
                      else deadline_hours)
    lock_path = os.path.join(workdir, "lock", "publish.lock")
    try:
        lock = PublishLock(lock_path, owner="recovery", timeout=30)
        lock.acquire()
    except Exception as e:
        return 1, {"ok": False, "error": "lock_timeout: %s" % type(e).__name__}
    try:
        state = _enter_degraded_inner(workdir, reason, now, deadline_hours)
        return 0, {"ok": True, "state": state}
    finally:
        lock.release()


def manual_restore(workdir, anchor_path, native_record_path, owner_ack,
                   probe_db=None, now=None):
    """Controlled manual restore of the last-verified-safe anchor.

    Requires owner_ack == OWNER_ACK_RESTORE and the anchor to be
    classified last_verified_safe (or verified_safe -- restoring a
    verified-safe anchor through this path is allowed but recorded as
    manual). Restores the anchor bytes to publish/ AND served/ under
    the shared lock, with in-lock SHA verification before and after
    the copy. The state becomes manual-restored, the STOP marker STAYS
    set, and a fresh native re-test is REQUIRED before returning to ok.
    The restored version is NEVER claimed currently qualified.
    Returns (rc, result).
    """
    now = int(now if now is not None else time.time())
    if owner_ack != OWNER_ACK_RESTORE:
        return 1, {"ok": False, "error": "owner_ack_required",
                   "hint": "pass owner_ack=%s" % OWNER_ACK_RESTORE}
    publish_dir = os.path.join(workdir, "publish")
    served_dir = os.path.join(workdir, "served")
    lock_path = os.path.join(workdir, "lock", "publish.lock")
    os.makedirs(served_dir, exist_ok=True)
    # Classify the anchor BEFORE taking the lock (read-only).
    anchor_kind = (".prev" if anchor_path.endswith(".prev")
                   else "history-snapshot")
    info = _classify_anchor(anchor_path, anchor_kind, native_record_path,
                            probe_db, now)
    if info["status"] not in ("last_verified_safe", "verified_safe"):
        return 1, {"ok": False, "error": "anchor_not_restorable",
                   "anchor": info}
    try:
        lock = PublishLock(lock_path, owner="recovery-restore", timeout=30)
        lock.acquire()
    except Exception as e:
        return 1, {"ok": False, "error": "lock_timeout: %s" % type(e).__name__}
    try:
        # Re-classify inside the lock: the anchor must not have changed
        # under us (its bytes are re-read and the chain re-verified by
        # _classify_anchor via verify_version_chain).
        info = _classify_anchor(anchor_path, anchor_kind, native_record_path,
                                probe_db, now)
        if info["status"] not in ("last_verified_safe", "verified_safe"):
            return 1, {"ok": False, "error": "anchor_not_restorable",
                       "anchor": info}
        anchor_lines = _read_lines(anchor_path)
        # Rebuild the chain for the restored bytes from the anchor's
        # own sidecar chain (bytes are identical, so the chain stays
        # valid); fall back to rebuilding from the native record.
        _meta, chain = read_chain_sidecar(
            os.path.dirname(anchor_path), os.path.basename(anchor_path))
        if chain is None:
            return 1, {"ok": False, "error": "anchor_no_version_chain",
                       "anchor": info}
        # Publish restore (snapshot + atomic write + verify, in-lock).
        written = _atomic_write_inner(
            publish_dir, PUBLISH_FILENAME, anchor_lines,
            source_version_sha=chain["source_sha"], version_chain=chain)
        restored_sha = written["manifest"]["sha256"]
        # Serve restore: in-lock SHA before AND after the copy.
        target_file = os.path.join(publish_dir, PUBLISH_FILENAME)
        served_file = os.path.join(served_dir, PUBLISH_FILENAME)
        source_sha_before = sha256_file(target_file)
        tmp = served_file + ".tmp"
        import shutil
        shutil.copyfile(target_file, tmp)
        try:
            os.chmod(tmp, 0o644)
        except OSError:
            pass
        os.rename(tmp, served_file)
        _fsync_dir(served_dir)
        served_after = file_manifest(served_file)
        source_sha_after = sha256_file(target_file)
        if (served_after is None
                or served_after["sha256"] != source_sha_before
                or source_sha_after != source_sha_before):
            return 1, {"ok": False, "error": "manual_restore_verify_failed",
                       "served_manifest_after": served_after,
                       "source_sha_before_prefix": source_sha_before[:12],
                       "source_sha_after_prefix": source_sha_after[:12]}
        state = read_state(workdir)
        state.update({
            "state": "manual-restored",
            "stopped": True,
            "since": now,
            "since_iso": _iso(now),
            "reason": "manual restore of %s (last verified %s)" % (
                info["kind"],
                _iso(info["last_verified_at"]) if info["last_verified_at"]
                else "unknown"),
            "served_sha_prefix": served_after["sha_prefix"],
            "served_lines": served_after["lines"],
            "served_status": "manual-restored-unverified",
            "restored_anchor": info,
            "restored_sha_prefix": restored_sha[:12],
            "requires_fresh_native_retest": True,
        })
        _history_append(state, "manual-restore",
                        "anchor=%s sha_prefix=%s last_verified_at=%s" % (
                            info["kind"], info["sha_prefix"],
                            info["last_verified_at"]))
        _write_state(workdir, state)
        # The served file carries the same version chain as the publish
        # file, so its provenance stays verifiable in the served dir.
        copy_sidecar(publish_dir, PUBLISH_FILENAME, served_dir)
        return 0, {"ok": True, "state": state,
                   "restored_manifest": written["manifest"],
                   "served_manifest_after": served_after,
                   "anchor": info}
    finally:
        lock.release()


def clear_stop(workdir, owner_ack, native_record_path, probe_db=None,
               now=None):
    """Clear the STOP marker and return to ok -- only with owner ack
    AND a fresh native gate pass for the SERVED version.

    The fresh gate pass is computed here from the native record (not
    asserted by the caller): the served file's chain source_sha must
    currently admit every served line (fresh, within TTL). When the
    served version cannot pass, the stop stays and the caller must
    first obtain a fresh native test (see docs/recovery-runbook.md).
    Returns (rc, result).
    """
    now = int(now if now is not None else time.time())
    if owner_ack != OWNER_ACK_CLEAR:
        return 1, {"ok": False, "error": "owner_ack_required",
                   "hint": "pass owner_ack=%s" % OWNER_ACK_CLEAR}
    served_status, prefix, lines = _served_status(
        workdir, native_record_path, probe_db=probe_db, now=now)
    if served_status != "qualified":
        return 1, {"ok": False, "error": "served_not_currently_qualified",
                   "served_status": served_status,
                   "served_sha_prefix": prefix, "served_lines": lines}
    lock_path = os.path.join(workdir, "lock", "publish.lock")
    try:
        lock = PublishLock(lock_path, owner="recovery-clear", timeout=30)
        lock.acquire()
    except Exception as e:
        return 1, {"ok": False, "error": "lock_timeout: %s" % type(e).__name__}
    try:
        # Re-check inside the lock: the served file must not have
        # changed under us.
        served_status2, _, _ = _served_status(
            workdir, native_record_path, probe_db=probe_db, now=now)
        if served_status2 != "qualified":
            return 1, {"ok": False,
                       "error": "served_not_currently_qualified",
                       "served_status": served_status2}
        state = read_state(workdir)
        state.update({
            "state": "ok",
            "stopped": False,
            "since": now,
            "since_iso": _iso(now),
            "reason": "fresh native evidence passed; stop cleared by owner",
            "served_status": "qualified",
            "served_sha_prefix": prefix,
            "served_lines": lines,
            "requires_fresh_native_retest": False,
        })
        _history_append(state, "clear-stop",
                        "served sha_prefix=%s lines=%s" % (prefix, lines))
        _write_state(workdir, state)
        return 0, {"ok": True, "state": state}
    finally:
        lock.release()


def main(argv=None):
    import argparse
    ap = argparse.ArgumentParser(description="D2 failure recovery (isolation)")
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("assess", help="classify rollback anchors")
    p.add_argument("--workdir", required=True)
    p.add_argument("--native-record", required=True)
    p.add_argument("--probe-db", default=None)
    p = sub.add_parser("status", help="recovery status + served qualification")
    p.add_argument("--workdir", required=True)
    p.add_argument("--native-record", default=None)
    p.add_argument("--probe-db", default=None)
    p = sub.add_parser("enter-degraded", help="STOP publishing/syncing")
    p.add_argument("--workdir", required=True)
    p.add_argument("--reason", required=True)
    p.add_argument("--deadline-hours", type=float, default=None)
    p = sub.add_parser("manual-restore",
                       help="restore last-verified-safe anchor (owner ack)")
    p.add_argument("--workdir", required=True)
    p.add_argument("--anchor", required=True,
                   help="path to the anchor file (.prev or history snapshot)")
    p.add_argument("--native-record", required=True)
    p.add_argument("--probe-db", default=None)
    p.add_argument("--owner-ack", required=True)
    p = sub.add_parser("clear-stop",
                       help="clear STOP after fresh native evidence (owner ack)")
    p.add_argument("--workdir", required=True)
    p.add_argument("--native-record", required=True)
    p.add_argument("--probe-db", default=None)
    p.add_argument("--owner-ack", required=True)
    args = ap.parse_args(argv)
    if args.cmd == "assess":
        out = assess_anchors(args.workdir, args.native_record,
                             probe_db=args.probe_db)
        print(json.dumps(out, ensure_ascii=False))
        return 0
    if args.cmd == "status":
        out = status(args.workdir, args.native_record, probe_db=args.probe_db)
        print(json.dumps(out, ensure_ascii=False))
        return 0
    if args.cmd == "enter-degraded":
        rc, out = enter_degraded(args.workdir, args.reason,
                                 deadline_hours=args.deadline_hours)
        print(json.dumps(out, ensure_ascii=False))
        return rc
    if args.cmd == "manual-restore":
        rc, out = manual_restore(args.workdir, args.anchor,
                                 args.native_record, args.owner_ack,
                                 probe_db=args.probe_db)
        print(json.dumps(out, ensure_ascii=False))
        return rc
    if args.cmd == "clear-stop":
        rc, out = clear_stop(args.workdir, args.owner_ack,
                             args.native_record, probe_db=args.probe_db)
        print(json.dumps(out, ensure_ascii=False))
        return rc
    return 2


if __name__ == "__main__":
    import sys
    sys.exit(main())
