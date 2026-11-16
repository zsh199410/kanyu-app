#!/bin/bash
# D4 gated sync, every 15 minutes (:00/:15/:30/:45) (Issue #73, D3 gate).
#
#   1. Run the D3 sync gate on the gate state dir. It re-verifies the
#      version chain + dual gate INSIDE the shared lock and copies the
#      gated file to $STATE/served/pool-new.txt. On refusal the
#      previously served clean file stays in place (safe state).
#   2. D6 (GPT D5 review 6887615694, item 2): the bridge step is done
#      by `python3 -m pool.bridge_sync` UNDER THE SAME shared lock:
#      it re-verifies the served bytes in-lock, snapshots them ONCE
#      into memory (immutable snapshot -- a writer rewriting served
#      mid-flight cannot change what lands on the bridge), writes
#      bridge + legacy from those bytes, re-reads and SHA-verifies
#      both, and rolls the bridge back to its pre-run bytes if the
#      legacy copy fails. The old shell cp/rename/verify block had a
#      check -> copy race and a legacy failure that only logged while
#      exiting rc=0; both are gone.
# The old blind pool-sync.sh (plain cp, no gate) must be DISABLED at
# switch time; this script is its gated replacement.
#
# D6 exposure guard: the served dir must never resolve inside the
# bridge dir (the only HTTP-served dir). If it does, the served file
# would BE the HTTP entry and a served tamper would be directly
# readable -- refuse before any copy (see switch-runbook.md, D6).
#
# Paths are overridable by environment for the isolated rehearsal.
# Exit: bridge_sync's rc (0 = synced, 1 = refused/failed).
set -u

PROG="${PROG:-/opt/free-node-program}"
GATE="${GATE:-/opt/pool-gate}"
STATE="$GATE/state"
RECORD="${RECORD:-$PROG/gate/native-results.json}"
PROBE_DB="${PROBE_DB:-/opt/probe-service/data/probe.db}"
LOG="$GATE/logs/gate-sync.log"
BRIDGE_DIR="${BRIDGE_DIR:-/opt/surge-bridge/modules}"
OLD_MANIFEST="$PROG/config/old-pool-file.txt"
PY="${GATE_PY:-python3}"

mkdir -p "$GATE/logs"

log() { echo "$(date -Iseconds) gate-sync $*" >> "$LOG"; }

if [ ! -f "$RECORD" ]; then
    log "error=native_record_missing record=$RECORD"
    exit 1
fi
if [ ! -d "$GATE/pool" ]; then log "error=gate_code_missing gate=$GATE"; exit 1; fi
if [ ! -f "$STATE/recovery-state.json" ] && [ ! -f "$STATE/recovery-anchor.json" ]; then
    log "error=recovery_state_uninitialized hint=run-manual-init-with-owner-ack"
    exit 1
fi

# D6: served must not resolve inside the bridge dir (the HTTP entry).
EXPOSURE="$("$PY" -c 'import os,sys; s=os.path.realpath(sys.argv[1]); b=os.path.realpath(sys.argv[2]); print("exposed" if s==b or s.startswith(b+os.sep) else "ok")' "$STATE/served" "$BRIDGE_DIR" 2>/dev/null || echo "check_failed")"
if [ "$EXPOSURE" != "ok" ]; then
    log "error=served_path_exposure_check result=$EXPOSURE served=$STATE/served bridge=$BRIDGE_DIR hint=served-must-not-be-inside-bridge-dir"
    exit 1
fi

cd "$GATE" || { log "error=chdir_gate_failed"; exit 1; }
SYNC_OUT="$("$PY" -m pool.sync --workdir "$STATE" \
    --native-record "$RECORD" --probe-db "$PROBE_DB" 2>&1)"
SYNC_RC=$?
log "sync rc=$SYNC_RC out=$SYNC_OUT"
if [ "$SYNC_RC" -ne 0 ]; then
    log "sync_refused_safe_state served_unchanged"
    exit 1
fi

SERVED="$STATE/served/pool-new.txt"
if [ ! -f "$SERVED" ]; then log "error=served_missing_after_sync"; exit 1; fi
SERVED_SHA="$(sha256sum "$SERVED" | awk '{print $1}')"
SERVED_LINES="$(wc -l < "$SERVED")"

# D5: pre-bridge served check -- before copying served to the bridge,
# the served_version_sha the sync step REPORTED must equal the SHA of
# the served file's ACTUAL bytes on disk. A mismatch means the served
# file changed after sync verified it (or sync reported a different
# version than it wrote): refuse, leave served and bridge untouched.
# (D6 keeps this as a tripwire; the race itself is closed inside
# pool.bridge_sync, which re-verifies the actual bytes under the lock
# and writes from an in-memory snapshot.)
EXPECTED_SHA="$(printf '%s' "$SYNC_OUT" | "$PY" -c 'import sys,json; print(json.load(sys.stdin).get("served_version_sha",""))' 2>/dev/null || echo "")"
if [ -z "$EXPECTED_SHA" ] || [ "$EXPECTED_SHA" != "$SERVED_SHA" ]; then
    log "error=served_sha_mismatch_before_bridge_copy expected=${EXPECTED_SHA:0:12} served=${SERVED_SHA:0:12} served_unchanged bridge_unchanged"
    exit 1
fi

# D6: bridge + legacy update, one lock + one immutable snapshot
# (pool/bridge_sync.py). Legacy $OLD failure now fails the run
# (rc=1, bridge rolled back) instead of only logging.
OLD=""
if [ -f "$OLD_MANIFEST" ]; then OLD="$(cat "$OLD_MANIFEST" 2>/dev/null)"; fi
if [ -n "$OLD" ]; then
    BRIDGE_OUT="$("$PY" -m pool.bridge_sync --workdir "$STATE" \
        --bridge-dir "$BRIDGE_DIR" --old-path "$OLD" \
        --native-record "$RECORD" --probe-db "$PROBE_DB" 2>&1)"
    BRIDGE_RC=$?
else
    BRIDGE_OUT="$("$PY" -m pool.bridge_sync --workdir "$STATE" \
        --bridge-dir "$BRIDGE_DIR" \
        --native-record "$RECORD" --probe-db "$PROBE_DB" 2>&1)"
    BRIDGE_RC=$?
    log "old_copy_skipped no_old_pool_manifest"
fi
log "bridge_sync rc=$BRIDGE_RC out=$BRIDGE_OUT"
if [ "$BRIDGE_RC" -ne 0 ]; then
    log "bridge_sync_failed bridge_rolled_back_or_unchanged"
    exit 1
fi

log "synced served_sha=${SERVED_SHA:0:12} served_lines=$SERVED_LINES bridge_sha=${SERVED_SHA:0:12}"
exit 0
