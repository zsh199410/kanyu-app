#!/bin/bash
# D4 gated publish, hourly at :07 (Issue #73, D3 gate).
#
# GATE-FIRST ORDER (see switch-runbook.md section 2 -- this is the
# whole point of the wiring, do not "fix" it into publish-first):
#   1. Gate the CURRENT source file -- the version assembled in the
#      previous cycle, the one the owner could have natively tested
#      during the intervening hour.
#   2. THEN run the production assembly for the NEXT version, which
#      becomes the source for the next cycle's gate.
# A refused gate is the SAFE state (served file untouched, nothing
# ungated ever published). It is EXPECTED whenever the current version
# has no fresh native evidence; it is not an error to bypass.
#
# Paths are overridable by environment for the isolated rehearsal
# (drills/switch_rehearsal.py). Production defaults are the real ones.
# The timer NEVER calls recovery init (owner ack is a manual step).
#
# Exit: gate's rc (0 = gated publish ok, 1 = refused). Unexpected
# errors (missing files, assembly crash) also exit 1 and are logged.
set -u

PROG="${PROG:-/opt/free-node-program}"
GATE="${GATE:-/opt/pool-gate}"
STATE="$GATE/state"
RECORD="${RECORD:-$PROG/gate/native-results.json}"
PROBE_DB="${PROBE_DB:-/opt/probe-service/data/probe.db}"
LOG="$GATE/logs/gate-publish.log"
SRC="$PROG/publish/pool-new.txt"
PY="${GATE_PY:-python3}"
PROD_PY="${PROD_PY:-$PROG/venv/bin/python}"

mkdir -p "$GATE/logs"

log() { echo "$(date -Iseconds) gate-publish $*" >> "$LOG"; }

# --- Pre-checks (fail closed, log plainly, do not publish) ---
if [ ! -f "$SRC" ]; then log "error=source_missing src=$SRC"; exit 1; fi
if [ ! -s "$SRC" ]; then log "error=source_empty src=$SRC"; exit 1; fi
if [ ! -f "$RECORD" ]; then
    log "error=native_record_missing record=$RECORD hint=owner-native-test-then-transcribe"
    exit 1
fi
if [ ! -d "$GATE/pool" ]; then log "error=gate_code_missing gate=$GATE"; exit 1; fi
if [ ! -f "$STATE/recovery-state.json" ] && [ ! -f "$STATE/recovery-anchor.json" ]; then
    log "error=recovery_state_uninitialized hint=run-manual-init-with-owner-ack"
    exit 1
fi

SOURCE_SHA="$(sha256sum "$SRC" | awk '{print $1}')"
log "cycle_start source_sha=${SOURCE_SHA:0:12} source_lines=$(wc -l < "$SRC")"

# --- Step 1: gate the CURRENT source version ---
cd "$GATE" || { log "error=chdir_gate_failed"; exit 1; }
GATE_OUT="$("$PY" -m pool.publish --workdir "$STATE" \
    --candidates "$SRC" --source-file "$SRC" \
    --native-record "$RECORD" --source-version "$SOURCE_SHA" \
    --probe-db "$PROBE_DB" 2>&1)"
GATE_RC=$?
log "gate rc=$GATE_RC out=$GATE_OUT"
if [ "$GATE_RC" -ne 0 ]; then
    log "gate_refused_safe_state served_unchanged hint=no-fresh-native-evidence-for-this-version"
fi

# --- Step 2: assemble the NEXT version (source for the next cycle) ---
# The assembly writes the UNGATED candidate to $SRC. It never touches
# the gate's published/served files (they live under $STATE).
ASM_OUT="$(cd "$PROG" && "$PROD_PY" -m pool.cli publish 2>&1)"
ASM_RC=$?
log "assembly rc=$ASM_RC out=$(echo "$ASM_OUT" | tail -c 400 | tr '\n' ' ')"
if [ "$ASM_RC" -ne 0 ]; then
    log "assembly_failed next_cycle_will_regate_same_source_version"
fi

# --- Step 3 (D5, cross-cycle binding record): after the assembly step,
# whether it succeeded or failed, record what this cycle gated and what
# the assembly produced. The record states EXPLICITLY that a pass in
# this cycle does NOT cover the newly assembled version:
# new_source_gated=false, always. The next cycle's gate must verify
# the new source SHA against fresh native evidence for THAT version
# before anything of it is published or served.
NEW_SOURCE_SHA=""
NEW_SOURCE_LINES=0
SRC_CHANGED=false
if [ -f "$SRC" ]; then
    NEW_SOURCE_SHA="$(sha256sum "$SRC" | awk '{print $1}')"
    NEW_SOURCE_LINES="$(wc -l < "$SRC")"
    if [ "$NEW_SOURCE_SHA" != "$SOURCE_SHA" ]; then SRC_CHANGED=true; fi
fi
PUBLISHED_SHA=""
if [ "$GATE_RC" -eq 0 ] && [ -f "$STATE/publish/pool-new.txt" ]; then
    PUBLISHED_SHA="$(sha256sum "$STATE/publish/pool-new.txt" | awk '{print $1}')"
fi
ASSEMBLY_FAILED=false
if [ "$ASM_RC" -ne 0 ]; then ASSEMBLY_FAILED=true; fi
CYCLE_TS="$(date +%s)"
CYCLE_FILE="$GATE/logs/cycle-${CYCLE_TS}-$$.json"
printf '%s' "{\"cycle_ts\": $CYCLE_TS, \"gate_rc\": $GATE_RC, \"gated_source_sha\": \"${SOURCE_SHA:0:12}\", \"published_sha\": \"${PUBLISHED_SHA:0:12}\", \"new_source_sha\": \"${NEW_SOURCE_SHA:0:12}\", \"new_source_lines\": $NEW_SOURCE_LINES, \"new_source_gated\": false, \"assembly_rc\": $ASM_RC, \"assembly_failed\": $ASSEMBLY_FAILED, \"src_changed\": $SRC_CHANGED}" > "$CYCLE_FILE"
log "cycle_record file=$CYCLE_FILE gated_source_sha=${SOURCE_SHA:0:12} published_sha=${PUBLISHED_SHA:0:12} new_source_sha=${NEW_SOURCE_SHA:0:12} new_source_gated=false assembly_rc=$ASM_RC assembly_failed=$ASSEMBLY_FAILED src_changed=$SRC_CHANGED"

log "cycle_end gate_rc=$GATE_RC assembly_rc=$ASM_RC new_source_gated=false"
exit "$GATE_RC"
