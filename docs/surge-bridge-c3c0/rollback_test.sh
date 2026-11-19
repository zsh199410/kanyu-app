#!/bin/bash
# C3-C0 ROLLBACK_TEST (isolated simulation).
# Simulates a rollback of the bridge code (bridge.js / module / server.py)
# after a v2 deployment, and verifies that ONLY code is restored while
# state.json, last_id, pins, and timers are NEVER touched or backfilled.
# All paths are inside a temp dir; nothing under /opt/surge-bridge/ is used.
set -u
ROOT=$(mktemp -d /tmp/c3c0-rollback-XXXXXX)
mkdir -p "$ROOT/opt/surge-bridge" "$ROOT/opt/p2p3-shadow"
# --- "production" state BEFORE the rollback (as if v2 had been deployed) ---
cp ~/workspace/pr96-c3c0/bridge_fixed_v2.js "$ROOT/opt/surge-bridge/bridge.js"
printf 'control-api=1\nscript-path=https://example.invalid/s/placeholder\n' > "$ROOT/opt/surge-bridge/bridge.sgmodule"
printf '# server.py (v2-era placeholder)\nVERSION="c2b"\n' > "$ROOT/opt/surge-bridge/server.py"
# state.json: the live mailbox state (last_id, pins, timers). This is the
# file a rollback must NEVER backfill or rewrite.
cat > "$ROOT/opt/surge-bridge/state.json" << 'JSON'
{"cmd": {"id": 1795063030}, "result": {"id": 1795055213880}, "polls": 2439,
 "pins": ["node-a","node-b","node-c"], "timers": ["t1","t2","t3","t4","t5"]}
JSON
# --- "backup" of the pre-v2 code (what a rollback restores) ---
cp /tmp/bridge_orig_desens.txt "$ROOT/opt/p2p3-shadow/bridge.js.pre-v2"
printf 'control-api=1\nscript-path=https://example.invalid/s/placeholder\n' > "$ROOT/opt/p2p3-shadow/bridge.sgmodule.pre-v2"
printf '# server.py (pre-v2 placeholder)\nVERSION="c1"\n' > "$ROOT/opt/p2p3-shadow/server.py.pre-v2"
# --- record pre-rollback fingerprints ---
S_STATE_BEFORE=$(sha256sum "$ROOT/opt/surge-bridge/state.json" | cut -d' ' -f1)
LAST_BEFORE=$(python3 -c "import json;print(json.load(open('$ROOT/opt/surge-bridge/state.json'))['result']['id'])")
PINS_BEFORE=$(python3 -c "import json;print(json.load(open('$ROOT/opt/surge-bridge/state.json'))['pins'])")
TIMERS_BEFORE=$(python3 -c "import json;print(json.load(open('$ROOT/opt/surge-bridge/state.json'))['timers'])")
CODE_BEFORE=$(sha256sum "$ROOT/opt/surge-bridge/bridge.js" | cut -d' ' -f1)
# --- ROLLBACK: restore ONLY code files from backup; NEVER touch state.json ---
cp "$ROOT/opt/p2p3-shadow/bridge.js.pre-v2" "$ROOT/opt/surge-bridge/bridge.js"
cp "$ROOT/opt/p2p3-shadow/bridge.sgmodule.pre-v2" "$ROOT/opt/surge-bridge/bridge.sgmodule"
cp "$ROOT/opt/p2p3-shadow/server.py.pre-v2" "$ROOT/opt/surge-bridge/server.py"
# (No step writes state.json, last_id, pins, or timers.)
# --- verify ---
S_STATE_AFTER=$(sha256sum "$ROOT/opt/surge-bridge/state.json" | cut -d' ' -f1)
LAST_AFTER=$(python3 -c "import json;print(json.load(open('$ROOT/opt/surge-bridge/state.json'))['result']['id'])")
PINS_AFTER=$(python3 -c "import json;print(json.load(open('$ROOT/opt/surge-bridge/state.json'))['pins'])")
TIMERS_AFTER=$(python3 -c "import json;print(json.load(open('$ROOT/opt/surge-bridge/state.json'))['timers'])")
CODE_AFTER=$(sha256sum "$ROOT/opt/surge-bridge/bridge.js" | cut -d' ' -f1)
echo "state.json SHA unchanged: $([ "$S_STATE_BEFORE" = "$S_STATE_AFTER" ] && echo YES || echo NO)"
echo "last_id unchanged: $([ "$LAST_BEFORE" = "$LAST_AFTER" ] && echo YES || echo NO) ($LAST_AFTER)"
echo "pins unchanged: $([ "$PINS_BEFORE" = "$PINS_AFTER" ] && echo YES || echo NO)"
echo "timers unchanged: $([ "$TIMERS_BEFORE" = "$TIMERS_AFTER" ] && echo YES || echo NO)"
echo "code restored (bridge.js SHA changed): $([ "$CODE_BEFORE" != "$CODE_AFTER" ] && echo YES || echo NO)"
if [ "$S_STATE_BEFORE" = "$S_STATE_AFTER" ] && [ "$LAST_BEFORE" = "$LAST_AFTER" ] && [ "$PINS_BEFORE" = "$PINS_AFTER" ] && [ "$TIMERS_BEFORE" = "$TIMERS_AFTER" ] && [ "$CODE_BEFORE" != "$CODE_AFTER" ]; then
  echo "ROLLBACK_TEST: PASS"
  rm -rf "$ROOT"
  exit 0
else
  echo "ROLLBACK_TEST: FAIL"
  echo "root kept at: $ROOT"
  exit 1
fi
