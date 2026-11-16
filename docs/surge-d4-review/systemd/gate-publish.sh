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

log "cycle_end gate_rc=$GATE_RC assembly_rc=$ASM_RC"
exit "$GATE_RC"
