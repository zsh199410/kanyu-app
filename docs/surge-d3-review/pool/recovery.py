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

D3 (GPT D2 review 6884522235, P0 -- recovery-state fail-open):
  D2 admitted the hole and D3 closes it: read_state() used to return a
  DEFAULT OK state when recovery-state.json was missing, corrupt,
  unreadable, or held an illegal value. A deleted state file silently
  reset a recorded STOP. That is gone:
  * FAIL-CLOSED READS. read_state_strict() returns (state, error);
    every failure mode -- missing, corrupt JSON, unreadable
    (permission/IO), illegal/unknown state value, interrupted atomic
    write (torn .tmp / missing rename target / partial content),
    state/anchor checksum or field mismatch, missing anchor -- refuses
    with a machine-readable recovery_state_*/recovery_anchor_* code.
    read_state() now RAISES RecoveryStateError instead of defaulting
    to ok. gate_check() is the single gate publish/sync/rollback
    consult (inside the held lock): it allows ONLY a valid,
    integrity-checked state file whose anchor agrees and whose state
    is ok. is_stopped() is fail-closed too: unknown counts as stopped.
  * PERSISTENT ANCHOR. Every state write also writes
    recovery-anchor.json (600, atomic tmp+rename, same lock): the
    last-known state/stopped, a monotonic seq, sha256 of the canonical
    state JSON, and the served version binding (served SHA prefix +
    chain_id + timestamp). The anchor is the second record that makes
    a STOP survive the loss of the state file: deleting
    recovery-state.json while STOP is recorded is detected (anchor
    says stopped) and refuses with ..._stop_recorded. A single-file
    loss/corruption can never reset a STOP.
  * EXPLICIT INIT ONLY. A fresh deployment has NO state and NO anchor
    and the gate refuses it (recovery_state_uninitialized). ok is
    established ONLY by init_recovery_state() with the typed owner
    ack OWNER_ACK_INIT: it writes the state + anchor with a safety
    anchor binding the served version SHA + chain_id + timestamp and
    an audit (history) entry. init REFUSES when a STOP is recorded
    (anchor or state file says stopped) -- init cannot launder a STOP.
    Re-init after state-file loss re-verifies the served file against
    the anchor; on mismatch it refuses and the operator uses the
    fresh-evidence + clear-stop path.
  * THREAT MODEL (stated plainly). The two-file design defeats
    single-file loss, single-file corruption/tampering, interrupted
    writes, and stale-file rollback (seq + checksum catch a state
    file replaced by an older copy). It does NOT defeat a party with
    write access who deliberately deletes or consistently rewrites
    BOTH records and then runs init with the owner ack -- that is an
    explicit operator action with an audit entry, not an accident;
    file checks alone cannot stop a privileged writer (same boundary
    as the D2 version chain: it stops misconfiguration, not a
    malicious writer). The audit trail (history in the state file,
    init/rebuild events) is the detection for that case.

All output is desensitised: counts, SHA prefixes, timestamps, state
names. No passwords, URIs, tokens, or subscription URLs.
"""

import hashlib
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
ANCHOR_FILENAME = "recovery-anchor.json"
ANCHOR_FORMAT = "recovery-anchor-v1"
VALID_STATES = ("ok", "degraded", "manual-restored")
PUBLISH_FILENAME = "pool-new.txt"
OWNER_ACK_RESTORE = "OWNER-ACK-RESTORE-LAST-VERIFIED-SAFE"
OWNER_ACK_CLEAR = "OWNER-ACK-CLEAR-STOP"
OWNER_ACK_INIT = "OWNER-ACK-INIT-RECOVERY-STATE"
DEFAULT_DEADLINE_HOURS = 24


class RecoveryStateError(Exception):
    """Raised by read_state() when the recovery state cannot be
    established as a valid, integrity-checked state. .error is the
    machine-readable refusal code (recovery_state_* /
    recovery_anchor_*); the gate refuses on any of these. D3: this
    replaces the D2 behaviour of silently defaulting to ok."""

    def __init__(self, error, detail=""):
        super().__init__(error + (": " + detail if detail else ""))
        self.error = error
        self.detail = detail


def _canonical_json(obj):
    """Canonical JSON for integrity hashing: sorted keys, compact
    separators, so a state dict hashes identically after a
    JSON round-trip regardless of file formatting."""
    return json.dumps(obj, sort_keys=True, separators=(",", ":"),
                      ensure_ascii=False)


def _sha256_text(text):
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def _state_path(workdir):
    return os.path.join(workdir, STATE_FILENAME)


def _anchor_path(workdir):
    return os.path.join(workdir, ANCHOR_FILENAME)


def _fresh_state_skeleton(now):
    """A state dict for a deployment with no prior state. FAIL-CLOSED
    BY CONSTRUCTION: it claims degraded/stopped, never ok. It is only
    a starting point for a transition (which overwrites it with the
    transition's own state) or for init (which validates, then sets
    ok explicitly). It is NEVER returned to a gate check."""
    return {
        "state": "degraded",
        "stopped": True,
        "since": now,
        "since_iso": _iso(now),
        "reason": "",
        "served_status": "unknown-no-evidence",
        "served_sha_prefix": "",
        "served_chain_id": "",
        "served_lines": 0,
        "deadline_iso": "",
        "requires_fresh_native_retest": True,
        "history": [],
        "seq": 0,
    }


def _read_state_file(workdir):
    """Raw state-file load. Returns (state_or_None, error_or_None).
    error in {missing, unreadable, corrupt, illegal,
    write_interrupted}: missing = file absent (write_interrupted when
    a .tmp is left behind, i.e. the atomic rename never happened);
    unreadable = permission/IO error opening it (including the file
    being replaced by a directory); corrupt = JSON parse failure or
    partial content; illegal = valid JSON but unknown state value or
    wrong shape (stopped not a bool, seq not an int)."""
    path = _state_path(workdir)
    if not os.path.exists(path):
        if os.path.exists(path + ".tmp"):
            return None, "write_interrupted"
        return None, "missing"
    try:
        with open(path, encoding="utf-8") as f:
            state = json.load(f)
    except OSError:
        return None, "unreadable"
    except ValueError:
        return None, "corrupt"
    if (not isinstance(state, dict)
            or state.get("state") not in VALID_STATES
            or not isinstance(state.get("stopped"), bool)
            or not isinstance(state.get("seq"), int)):
        return None, "illegal"
    return state, None


def _read_anchor(workdir):
    """Raw anchor-file load. Returns (anchor_or_None, error_or_None).
    error in {missing, unreadable, corrupt, illegal}: corrupt = JSON
    parse failure; illegal = wrong format tag, unknown state value,
    or a missing/ill-typed binding field (stopped, seq,
    state_sha256)."""
    path = _anchor_path(workdir)
    if not os.path.exists(path):
        return None, "missing"
    try:
        with open(path, encoding="utf-8") as f:
            anchor = json.load(f)
    except OSError:
        return None, "unreadable"
    except ValueError:
        return None, "corrupt"
    if (not isinstance(anchor, dict)
            or anchor.get("format") != ANCHOR_FORMAT
            or anchor.get("state") not in VALID_STATES
            or not isinstance(anchor.get("stopped"), bool)
            or not isinstance(anchor.get("seq"), int)
            or not isinstance(anchor.get("state_sha256"), str)
            or not anchor.get("state_sha256")):
        return None, "illegal"
    return anchor, None


def _build_anchor(state, reason=""):
    """Anchor record for a state dict. The anchor is the second,
    independent record of the recovery state: it vouches for the
    state file (state_sha256 over the canonical state JSON + the
    monotonic seq) and binds the served version (served SHA prefix +
    chain_id) at the time the state was written."""
    return {
        "format": ANCHOR_FORMAT,
        "state": state["state"],
        "stopped": bool(state.get("stopped")),
        "seq": int(state.get("seq", 0)),
        "state_sha256": _sha256_text(_canonical_json(state)),
        "served_sha_prefix": state.get("served_sha_prefix", ""),
        "chain_id": state.get("served_chain_id", ""),
        "updated_at": state.get("updated_at", int(time.time())),
        "updated_at_iso": state.get("updated_at_iso", _iso()),
        "reason": reason or state.get("reason", ""),
    }


def _write_anchor(workdir, state, reason=""):
    """Atomically write the anchor for a state dict (tmp + rename +
    fsync, 600). CALLER MUST HOLD THE SHARED LOCK."""
    anchor = _build_anchor(state, reason)
    path = _anchor_path(workdir)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(anchor, f, ensure_ascii=False, indent=2)
    try:
        os.chmod(tmp, 0o600)
    except OSError:
        pass
    os.rename(tmp, path)
    _fsync_dir(workdir)
    return anchor


def read_state_strict(workdir):
    """Fail-closed state read. Returns (state_dict_or_None,
    error_code_or_None).

    (state, None) is returned ONLY when a valid state file exists,
    its anchor exists and agrees with it (same state/stopped/seq,
    and state_sha256 matches the canonical state JSON).

    Every other condition returns (None, error) -- the gate refuses
    on all of these, never defaults to ok:
      recovery_state_uninitialized   no state file AND no anchor:
                                     fresh deployment, explicit init
                                     required
      recovery_state_missing         state file gone (anchor says ok)
      recovery_state_write_interrupted
                                     state file gone, .tmp left behind:
                                     the atomic rename never happened
      recovery_state_unreadable      permission / IO error reading it
      recovery_state_corrupt         JSON parse failure / partial content
      recovery_state_illegal         unknown state value / bad shape
      recovery_state_checksum_mismatch
                                     state bytes do not match the anchor
      recovery_state_anchor_mismatch state/anchor fields disagree
                                     (state, stopped, or seq)
      recovery_anchor_missing        state says ok but the anchor is gone
      recovery_anchor_unreadable / _corrupt / _illegal
                                     the anchor itself is unusable
    Any code is suffixed `_stop_recorded` when the surviving anchor
    (or state) records a STOP, so the operator sees that a STOP was
    recorded and the state cannot be trusted -- not just that a file
    is missing. Deleting the state file while STOP is recorded yields
    recovery_state_missing_stop_recorded, never ok.
    """
    state, serr = _read_state_file(workdir)
    anchor, aerr = _read_anchor(workdir)
    stop_recorded = False
    if anchor is not None and anchor.get("stopped"):
        stop_recorded = True
    if state is not None and state.get("stopped"):
        stop_recorded = True

    def _err(code):
        if stop_recorded and not code.endswith("_stop_recorded"):
            code = code + "_stop_recorded"
        return "recovery_" + code

    if state is None:
        if anchor is None:
            if aerr == "missing":
                return None, "recovery_state_uninitialized"
            # State gone AND anchor unusable: name both failures.
            return None, _err("state_%s_anchor_%s" % (serr, aerr))
        return None, _err("state_" + serr)
    # State file loaded and shape-valid.
    if anchor is None:
        if aerr == "missing":
            return None, _err("anchor_missing")
        return None, _err("anchor_" + aerr)
    # Both present: cross-check.
    if (anchor.get("state") != state["state"]
            or anchor.get("stopped") != state["stopped"]
            or anchor.get("seq") != state.get("seq")):
        return None, _err("state_anchor_mismatch")
    if anchor.get("state_sha256") != _sha256_text(_canonical_json(state)):
        return None, _err("state_checksum_mismatch")
    return state, None


def read_state(workdir):
    """Current recovery state. STRICT (D3): raises RecoveryStateError
    when the state cannot be established as a valid,
    integrity-checked state. A missing/corrupt/unreadable/illegal
    state file, a missing or disagreeing anchor, or an uninitialized
    deployment NEVER defaults to ok (that was the D2 fail-open hole).
    Callers that must keep working when the state is unreadable
    (status diagnostics, state transitions) use read_state_strict()
    or _load_state_for_transition() instead."""
    state, err = read_state_strict(workdir)
    if err is not None:
        raise RecoveryStateError(err)
    return state


def gate_check(workdir):
    """The recovery gate. Returns (allowed, error, state).
    allowed is True ONLY when a valid, integrity-checked state file
    exists, its anchor agrees, and the state is ok (not stopped).
    Every other condition refuses: missing/corrupt/unreadable/illegal
    state or anchor, checksum/field mismatch, uninitialized
    deployment, or a recorded STOP. error is None when allowed, else
    the machine-readable refusal code (pool_stopped for a recorded
    STOP, recovery_state_*/recovery_anchor_* otherwise). publish,
    sync and rollback consult this INSIDE the held lock."""
    state, err = read_state_strict(workdir)
    if err is not None:
        return False, err, None
    if state.get("stopped") or state.get("state") != "ok":
        return False, "pool_stopped", state
    return True, None, state


def is_stopped(workdir):
    """True when publishing/syncing must refuse: a STOP is recorded OR
    the recovery state cannot be established as ok (fail-closed).
    Unknown counts as stopped. Kept for callers that only need a
    boolean; new code should use gate_check() to get the precise
    refusal reason."""
    allowed, _err, _state = gate_check(workdir)
    return not allowed


def _write_state(workdir, state, reason=""):
    """Write state + anchor atomically (both tmp + rename + fsync,
    600). CALLER MUST HOLD THE SHARED LOCK (state transitions are
    serialized with publish/sync). The seq is bumped on every write,
    so the anchor always vouches for the newest state: a state file
    replaced by an older copy is caught by the seq/checksum
    cross-check on read. Returns the state dict."""
    state["seq"] = int(state.get("seq") or 0) + 1
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
    _write_anchor(workdir, state, reason=reason)
    return state


def _served_binding(workdir):
    """(sha_prefix, lines, chain_id) of the currently served file,
    from its manifest + sidecar chain. chain_id is "" when the served
    file carries no verifiable v2 chain. Never raises."""
    served = os.path.join(workdir, "served", PUBLISH_FILENAME)
    manifest = file_manifest(served)
    if manifest is None:
        return "", 0, ""
    chain_id = ""
    try:
        _meta, chain = read_chain_sidecar(
            os.path.dirname(served), PUBLISH_FILENAME)
        if chain:
            chain_id = chain.get("chain_id", "") or ""
    except Exception:
        chain_id = ""
    return manifest["sha_prefix"], manifest["lines"], chain_id


def _load_state_for_transition(workdir, now):
    """Load the best available state for a TRANSITION (enter-degraded,
    manual-restore, clear-stop). Transitions must keep working when
    the state file is unreadable: they fall back to the anchor's
    last-known state, or to a fail-closed skeleton when neither file
    is usable. This is safe because every transition writes a
    fail-closed state (degraded/stopped, or ok only with fresh
    evidence + owner ack) and re-anchors it -- nothing here can
    resurrect an ok state from an unreadable one. Returns
    (state_dict, note) where note describes what was recovered
    ('' when the state file was intact). Never raises."""
    state, err = read_state_strict(workdir)
    if err is None:
        return state, ""
    anchor, _aerr = _read_anchor(workdir)
    if anchor is not None:
        skel = {
            "state": anchor["state"],
            "stopped": bool(anchor["stopped"]),
            "since": anchor.get("updated_at", now),
            "since_iso": anchor.get("updated_at_iso", _iso(now)),
            "reason": "recovered from anchor after state error %s" % err,
            "served_status": "unknown-no-evidence",
            "served_sha_prefix": anchor.get("served_sha_prefix", ""),
            "served_chain_id": anchor.get("chain_id", ""),
            "served_lines": 0,
            "deadline_iso": "",
            "requires_fresh_native_retest": bool(anchor["stopped"]),
            "history": [],
            "seq": int(anchor.get("seq", 0)),
        }
        return skel, ("state file %s; rebuilt from anchor seq=%s"
                      % (err, anchor.get("seq")))
    skel = _fresh_state_skeleton(now)
    skel["reason"] = "no usable state or anchor (%s); fresh skeleton" % err
    return skel, "no state or anchor (%s); fresh skeleton" % err


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
    """Full recovery status: state file + live served qualification.
    Never raises and never defaults to ok: when the state cannot be
    established, the report says state=unknown-unsafe, stopped=True
    and names the state_error code."""
    now = int(now if now is not None else time.time())
    state, err = read_state_strict(workdir)
    if err is not None:
        out = {
            "state": "unknown-unsafe",
            "stopped": True,
            "state_error": err,
            "since": None,
            "since_iso": "",
            "reason": "",
            "served_status": "unknown-no-evidence",
            "served_sha_prefix": "",
            "served_chain_id": "",
            "served_lines": 0,
            "deadline_iso": "",
            "requires_fresh_native_retest": True,
            "history": [],
            "seq": None,
        }
    else:
        out = dict(state)
    if native_record_path:
        served_status, prefix, lines = _served_status(
            workdir, native_record_path, probe_db=probe_db, now=now)
        # A manual restore is never re-labelled "qualified" or merely
        # "stale" by this helper: the file was restored by hand from
        # old evidence and is unverified until a fresh native re-test
        # passes and the stop is cleared. (A "broken-unqualified"
        # live verdict is left as-is: it is more alarming and correct.)
        if (err is None and state.get("state") == "manual-restored"
                and served_status in ("qualified", "stale-not-qualified")):
            served_status = "manual-restored-unverified"
        out["served_status_live"] = served_status
        out["served_sha_prefix_live"] = prefix
        out["served_lines_live"] = lines
    return out


def _enter_degraded_inner(workdir, reason, now, deadline_hours):
    """Lock-free inner state write. CALLER MUST HOLD THE SHARED LOCK.
    Works from the anchor when the state file is unreadable (a broken
    state file must never block entering the safe state)."""
    state, note = _load_state_for_transition(workdir, now)
    sha_prefix, lines, chain_id = _served_binding(workdir)
    state.update({
        "state": "degraded",
        "stopped": True,
        "since": now,
        "since_iso": _iso(now),
        "reason": reason,
        "served_sha_prefix": sha_prefix,
        "served_chain_id": chain_id,
        "served_lines": lines,
        # The served file is NOT claimed qualified: its evidence
        # is stale or its provenance is broken -- that is exactly
        # why we are degraded.
        "served_status": "stale-not-qualified",
        "deadline_iso": _iso(now + deadline_hours * 3600),
        "requires_fresh_native_retest": True,
    })
    if note:
        _history_append(state, "state-recovered-for-transition", note)
    _history_append(state, "enter-degraded", reason)
    _write_state(workdir, state, reason=reason)
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
        state, note = _load_state_for_transition(workdir, now)
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
            "served_chain_id": chain.get("chain_id", "") or "",
            "served_lines": served_after["lines"],
            "served_status": "manual-restored-unverified",
            "restored_anchor": info,
            "restored_sha_prefix": restored_sha[:12],
            "requires_fresh_native_retest": True,
        })
        if note:
            _history_append(state, "state-recovered-for-transition", note)
        _history_append(state, "manual-restore",
                        "anchor=%s sha_prefix=%s last_verified_at=%s" % (
                            info["kind"], info["sha_prefix"],
                            info["last_verified_at"]))
        _write_state(workdir, state, reason="manual restore")
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
        state, note = _load_state_for_transition(workdir, now)
        _sha_prefix, _lines, _chain_id = _served_binding(workdir)
        state.update({
            "state": "ok",
            "stopped": False,
            "since": now,
            "since_iso": _iso(now),
            "reason": "fresh native evidence passed; stop cleared by owner",
            "served_status": "qualified",
            "served_sha_prefix": prefix,
            "served_chain_id": _chain_id,
            "served_lines": lines,
            "requires_fresh_native_retest": False,
        })
        if note:
            _history_append(state, "state-recovered-for-transition", note)
        _history_append(state, "clear-stop",
                        "served sha_prefix=%s lines=%s" % (prefix, lines))
        _write_state(workdir, state, reason="clear stop")
        return 0, {"ok": True, "state": state}
    finally:
        lock.release()


def init_recovery_state(workdir, owner_ack, now=None):
    """Explicitly establish the recovery state (D3). This is the ONLY
    way an ok state comes into existence: a fresh deployment has no
    state file and no anchor, and the gate refuses it
    (recovery_state_uninitialized) until init runs. Requires the typed
    owner ack (a human operator action; timers never call init).

    The init writes the state + anchor with a safety anchor binding
    the CURRENT served version (served SHA prefix + chain_id +
    timestamp) and an audit (history) entry naming the mode.

    Modes (returned in result["mode"]):
      fresh                  no state file and no usable anchor: a
                             genuinely new deployment (or both records
                             deliberately removed by the operator --
                             see the runbook; that is an explicit
                             operator action with an audit entry, not
                             something a single lost file can cause)
      rebuild-from-anchor    state file lost/corrupt, anchor intact
                             and not stopped, served file matches the
                             anchor's binding
      rebuild-anchor         anchor lost/corrupt, state file intact
                             and not stopped, served file matches the
                             state's binding

    Init REFUSES (fail-closed) when:
      * the owner ack is wrong -> owner_ack_required
      * the anchor records a STOP -> init_refused_stop_recorded
        (init can never launder a STOP; use manual-restore /
        clear-stop). Deleting the state file does not help: the
        anchor survives and still says stopped.
      * the state file records a STOP (anchor lost) ->
        init_refused_stop_recorded
      * the state file exists but is unreadable/corrupt/illegal ->
        init_refused_unreadable_state (remove the unreadable file
        deliberately first, per the runbook; the anchor then governs)
      * the served file disagrees with the surviving binding ->
        init_anchor_served_mismatch / init_state_served_mismatch
        (the served version changed outside the state machine; use
        the fresh-evidence + clear-stop path instead)
    Returns (rc, result). rc 0 = initialized (state ok, gate open).
    """
    now = int(now if now is not None else time.time())
    if owner_ack != OWNER_ACK_INIT:
        return 1, {"ok": False, "error": "owner_ack_required",
                   "hint": "pass owner_ack=%s" % OWNER_ACK_INIT}
    lock_path = os.path.join(workdir, "lock", "publish.lock")
    try:
        lock = PublishLock(lock_path, owner="recovery-init", timeout=30)
        lock.acquire()
    except Exception as e:
        return 1, {"ok": False, "error": "lock_timeout: %s" % type(e).__name__}
    try:
        anchor, aerr = _read_anchor(workdir)
        state, serr = _read_state_file(workdir)
        # A recorded STOP can never be laundered by init -- whichever
        # record survives, it governs.
        if anchor is not None and anchor.get("stopped"):
            return 1, {"ok": False,
                       "error": "init_refused_stop_recorded",
                       "record": "anchor",
                       "anchor_state": anchor["state"],
                       "anchor_seq": anchor["seq"]}
        if state is not None and state.get("stopped"):
            return 1, {"ok": False,
                       "error": "init_refused_stop_recorded",
                       "record": "state",
                       "state": state["state"],
                       "state_seq": state["seq"]}
        if state is None and serr in ("unreadable", "corrupt", "illegal"):
            # Something was there but cannot be read: do not guess
            # whether it recorded a STOP. The operator removes the
            # unreadable file deliberately first (runbook).
            return 1, {"ok": False,
                       "error": "init_refused_unreadable_state",
                       "state_error": serr,
                       "hint": "inspect the state file; remove it "
                               "deliberately per the runbook, then "
                               "re-run init (the anchor then governs)"}
        # Served binding at init time: what IS served right now.
        sha_prefix, lines, chain_id = _served_binding(workdir)
        served_exists = os.path.exists(
            os.path.join(workdir, "served", PUBLISH_FILENAME))
        mode = None
        base_seq = 0
        history_note = ""
        if anchor is not None:
            # Rebuild the state file from the anchor.
            if anchor.get("served_sha_prefix"):
                if not served_exists:
                    return 1, {"ok": False,
                               "error": "init_anchor_served_mismatch",
                               "detail": "anchor records served "
                                         "sha_prefix=%s but no served "
                                         "file exists"
                                         % anchor["served_sha_prefix"]}
                if sha_prefix != anchor["served_sha_prefix"]:
                    return 1, {"ok": False,
                               "error": "init_anchor_served_mismatch",
                               "anchor_served_sha_prefix":
                                   anchor["served_sha_prefix"],
                               "served_sha_prefix": sha_prefix}
                if anchor.get("chain_id") and chain_id \
                        and chain_id != anchor["chain_id"]:
                    return 1, {"ok": False,
                               "error": "init_anchor_served_mismatch",
                               "anchor_chain_id_prefix":
                                   anchor["chain_id"][:12],
                               "served_chain_id_prefix": chain_id[:12]}
            mode = "rebuild-from-anchor"
            base_seq = int(anchor.get("seq", 0))
            history_note = ("rebuilt state file from anchor seq=%s "
                            "(state file was %s)"
                            % (anchor.get("seq"), serr))
        elif state is not None:
            # Rebuild the anchor from the state file.
            if state.get("served_sha_prefix"):
                if not served_exists:
                    return 1, {"ok": False,
                               "error": "init_state_served_mismatch",
                               "detail": "state records served "
                                         "sha_prefix=%s but no served "
                                         "file exists"
                                         % state["served_sha_prefix"]}
                if sha_prefix != state["served_sha_prefix"]:
                    return 1, {"ok": False,
                               "error": "init_state_served_mismatch",
                               "state_served_sha_prefix":
                                   state["served_sha_prefix"],
                               "served_sha_prefix": sha_prefix}
            mode = "rebuild-anchor"
            base_seq = int(state.get("seq", 0))
            history_note = ("rebuilt anchor from state file seq=%s "
                            "(anchor was %s)" % (state.get("seq"), aerr))
        else:
            # Neither record usable: genuinely fresh (or both records
            # deliberately removed -- an explicit operator action).
            mode = "fresh"
            base_seq = 0
            history_note = ("fresh init (state file %s, anchor %s)"
                            % (serr, aerr))
        new_state = _fresh_state_skeleton(now)
        new_state.update({
            "state": "ok",
            "stopped": False,
            "since": now,
            "since_iso": _iso(now),
            "reason": "initialized by owner (mode=%s)" % mode,
            "served_status": "unknown-no-evidence",
            "served_sha_prefix": sha_prefix,
            "served_chain_id": chain_id,
            "served_lines": lines,
            "deadline_iso": "",
            "requires_fresh_native_retest": False,
            "seq": base_seq,
        })
        # Preserve prior history when rebuilding from a readable state
        # file; otherwise start a fresh audit trail that names the
        # rebuild.
        if state is not None and isinstance(state.get("history"), list):
            new_state["history"] = list(state["history"])
        _history_append(
            new_state, "init",
            "%s; served sha_prefix=%s lines=%s chain_id_prefix=%s"
            % (history_note, sha_prefix, lines,
               chain_id[:12] if chain_id else ""))
        _write_state(workdir, new_state, reason="init (%s)" % mode)
        anchor_after, _aerr2 = _read_anchor(workdir)
        return 0, {"ok": True, "mode": mode, "state": new_state,
                   "anchor": anchor_after,
                   "served_sha_prefix": sha_prefix,
                   "served_lines": lines,
                   "chain_id_prefix": chain_id[:12] if chain_id else ""}
    finally:
        lock.release()


def main(argv=None):
    import argparse
    ap = argparse.ArgumentParser(description="D3 failure recovery (isolation)")
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
    p = sub.add_parser("init",
                       help="D3: explicitly establish the recovery state "
                            "(owner ack; the ONLY way ok comes into "
                            "existence)")
    p.add_argument("--workdir", required=True)
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
    if args.cmd == "init":
        rc, out = init_recovery_state(args.workdir, args.owner_ack)
        print(json.dumps(out, ensure_ascii=False))
        return rc
    return 2


if __name__ == "__main__":
    import sys
    sys.exit(main())
