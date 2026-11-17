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
# D6 (GPT D5 review 6887615694, item 3) -- EXIT CODES AND HEALTH:
# D5 exited with "$GATE_RC" always, so gate=0 + assembly!=0 exited 0
# and an assembly failure was invisible to the timer/monitoring.
# Exit codes now distinguish the two halves of the cycle:
#   0 = gate passed AND assembly succeeded (whole cycle healthy).
#   1 = gate refused (safe state; served unchanged) OR a pre-check
#       failed (missing files, unreadable state). The assembly
#       outcome for this cycle is in the cycle record + health file.
#   2 = gate passed (this round's verified publish SUCCEEDED) but
#       the NEXT version's assembly FAILED. The phone still serves
#       the verified version; the next :07 re-gates the SAME source
#       version (it does NOT mistake the assembly failure for a
#       publish failure -- see drills/d6_item3_publish_exit.py).
# Every cycle also writes $GATE/logs/health.json (atomic
# tmp+rename) with health in {healthy, published_assembly_failed,
# gate_refused, precheck_failed} plus gate_rc / assembly_rc / SHAs,
# so monitoring can tell "publish ok, assembly failed" from "gate
# refused" without parsing logs. A non-zero exit marks the oneshot
# unit failed (systemctl is-failed pool-gate-publish.service); exit 0
# MUST NOT be read as "the whole cycle succeeded" beyond what the
# health file says -- the health file is the authority.
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

# D6: write the latest-cycle health file atomically. Args:
#   $1 health, $2 gate_rc, $3 assembly_rc, $4 gated_source_sha (12),
#   $5 published_sha (12), $6 new_source_sha (12),
#   $7 assembly_failed (true/false), $8 src_changed (true/false).
# rc -1 means "did not run" (pre-check failure).
write_health() {
    local _ts _tmp _file
    _ts="$(date +%s)"
    _file="$GATE/logs/health.json"
    _tmp="$_file.tmp.$$"
    printf '%s' "{\"cycle_ts\": $_ts, \"health\": \"$1\", \"gate_rc\": $2, \"assembly_rc\": $3, \"gated_source_sha\": \"$4\", \"published_sha\": \"$5\", \"new_source_sha\": \"$6\", \"new_source_gated\": false, \"assembly_failed\": $7, \"src_changed\": $8}" > "$_tmp" \
        && mv "$_tmp" "$_file" || log "error=health_write_failed file=$_file"
}

# P0: verify no real, unlocked legacy writer can race this gate.
# Isolation harnesses intentionally set GATE/PROG to private paths.
if [ "$GATE" = "/opt/pool-gate" ] && [ "$PROG" = "/opt/free-node-program" ]; then
    if [ ! -r "$GATE/legacy-writer-guard.py" ]; then
        log "error=legacy_writer_guard_missing"; write_health "precheck_failed" -1 -1 "" "" "" false false; exit 1
    fi
    if ! "$PY" "$GATE/legacy-writer-guard.py" >/dev/null 2>&1; then
        log "error=legacy_writer_not_drained"; write_health "precheck_failed" -1 -1 "" "" "" false false; exit 1
    fi
fi

# --- Pre-checks (fail closed, log plainly, do not publish) ---
if [ ! -f "$SRC" ]; then log "error=source_missing src=$SRC"; write_health "precheck_failed" -1 -1 "" "" "" false false; exit 1; fi
if [ ! -s "$SRC" ]; then log "error=source_empty src=$SRC"; write_health "precheck_failed" -1 -1 "" "" "" false false; exit 1; fi
if [ ! -f "$RECORD" ]; then
    log "error=native_record_missing record=$RECORD hint=owner-native-test-then-transcribe"
    write_health "precheck_failed" -1 -1 "" "" "" false false
    exit 1
fi
if [ ! -d "$GATE/pool" ]; then log "error=gate_code_missing gate=$GATE"; write_health "precheck_failed" -1 -1 "" "" "" false false; exit 1; fi
if [ ! -f "$STATE/recovery-state.json" ] && [ ! -f "$STATE/recovery-anchor.json" ]; then
    log "error=recovery_state_uninitialized hint=run-manual-init-with-owner-ack"
    write_health "precheck_failed" -1 -1 "" "" "" false false
    exit 1
fi

SOURCE_SHA="$(sha256sum "$SRC" | awk '{print $1}')"
log "cycle_start source_sha=${SOURCE_SHA:0:12} source_lines=$(wc -l < "$SRC")"

# --- Step 1: gate the CURRENT source version ---
cd "$GATE" || { log "error=chdir_gate_failed"; write_health "precheck_failed" -1 -1 "${SOURCE_SHA:0:12}" "" "" false false; exit 1; }
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
# D6 note: the assembly ALWAYS runs, even when the gate refused --
# that is intentional (a refused gate must not stall the assembly of
# the next candidate). The exit code and health file, not the fact
# that assembly ran, carry the distinction.
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

# --- Step 4 (D6): health file + distinct exit code. ---
if [ "$GATE_RC" -ne 0 ]; then
    HEALTH="gate_refused"
    EXIT_RC=1
elif [ "$ASM_RC" -ne 0 ]; then
    HEALTH="published_assembly_failed"
    EXIT_RC=2
else
    HEALTH="healthy"
    EXIT_RC=0
fi
write_health "$HEALTH" "$GATE_RC" "$ASM_RC" "${SOURCE_SHA:0:12}" "${PUBLISHED_SHA:0:12}" "${NEW_SOURCE_SHA:0:12}" "$ASSEMBLY_FAILED" "$SRC_CHANGED"
log "cycle_end gate_rc=$GATE_RC assembly_rc=$ASM_RC health=$HEALTH exit=$EXIT_RC new_source_gated=false"
exit "$EXIT_RC"
