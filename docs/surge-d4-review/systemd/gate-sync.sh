#!/bin/bash
# D4 gated sync, every 15 minutes (:00/:15/:30/:45) (Issue #73, D3 gate).
#
#   1. Run the D3 sync gate on the gate state dir. It re-verifies the
#      version chain + dual gate INSIDE the shared lock and copies the
#      gated file to $STATE/served/pool-new.txt. On refusal the
#      previously served clean file stays in place (safe state).
#   2. Only on sync rc=0, copy the served file to the bridge modules
#      dir (the phone's subscription target) and to the legacy
#      old-pool-file path, tmp+rename, chmod 644, then verify SHA.
# The old blind pool-sync.sh (plain cp, no gate) must be DISABLED at
# switch time; this script is its gated replacement.
#
# Paths are overridable by environment for the isolated rehearsal.
# Exit: sync's rc (0 = synced, 1 = refused/failed).
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

# Main target: the phone's subscription file.
cp "$SERVED" "$BRIDGE_DIR/.sync-new.tmp" && chmod 644 "$BRIDGE_DIR/.sync-new.tmp" \
    && mv "$BRIDGE_DIR/.sync-new.tmp" "$BRIDGE_DIR/pool-new.txt" || {
    log "error=bridge_copy_failed"; exit 1; }
GOT_SHA="$(sha256sum "$BRIDGE_DIR/pool-new.txt" | awk '{print $1}')"
if [ "$GOT_SHA" != "$SERVED_SHA" ]; then
    log "error=bridge_sha_mismatch served=${SERVED_SHA:0:12} bridge=${GOT_SHA:0:12}"
    exit 1
fi

# Legacy old-pool-file path (only if the manifest exists and is non-empty).
OLD=""
if [ -f "$OLD_MANIFEST" ]; then OLD="$(cat "$OLD_MANIFEST" 2>/dev/null)"; fi
if [ -n "$OLD" ]; then
    cp "$SERVED" "$BRIDGE_DIR/.sync-old.tmp" && chmod 644 "$BRIDGE_DIR/.sync-old.tmp" \
        && mv "$BRIDGE_DIR/.sync-old.tmp" "$OLD" && \
        log "old_copy_ok old_lines=$(wc -l < "$OLD")" || \
        log "old_copy_failed old_path_unverified"
else
    log "old_copy_skipped no_old_pool_manifest"
fi

log "synced served_sha=${SERVED_SHA:0:12} served_lines=$SERVED_LINES bridge_sha=${GOT_SHA:0:12}"
exit 0
