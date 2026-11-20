#!/usr/bin/env bash
# Issue #73: hermetic C3-C0 ROLLBACK_TEST, no live host, credentials or network.
# All data and deploy/backup paths live under a newly created temporary root.
# The reviewed v2.2 and pre-v2 control are sourced ONLY from this checkout.
# This is a simulation, not approval or a test of actual phone rollback.
set -euo pipefail

die() { printf 'ROLLBACK_TEST: FAIL (%s)\n' "$1" >&2; exit 1; }
[ "$#" -le 1 ] || die "unexpected arguments"
if [ "$#" -eq 1 ] && [ "$1" != "--inject-state-change" ]; then
  die "unknown argument"
fi

SRC_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
[ -f "$SRC_DIR/bridge_fixed_v2.js" ] || die "v2.2 source missing from checkout"
[ -f "$SRC_DIR/v1/bridge_fixed.js" ] || die "v1 source missing from checkout"

ROOT="$(mktemp -d)" || die "cannot make isolated root"
trap 'rm -rf "$ROOT"' EXIT
LIVE="$ROOT/synthetic-deployment"
BACKUP="$ROOT/synthetic-backup"
SNAPSHOT="$ROOT/snapshot"
mkdir -p "$LIVE" "$BACKUP" "$SNAPSHOT"

# Synthetic files; never open or modify /opt/surge-bridge or device state.
cp "$SRC_DIR/bridge_fixed_v2.js" "$LIVE/bridge.js"
cp "$SRC_DIR/v1/bridge_fixed.js" "$BACKUP/bridge.js.pre-v2"
printf 'control-api=1\nscript-path=https://example.invalid/synthetic-v2\n' > "$LIVE/bridge.sgmodule"
printf 'control-api=1\nscript-path=https://example.invalid/synthetic-v1\n' > "$BACKUP/bridge.sgmodule.pre-v2"
printf '# isolated synthetic v2 server\nVERSION="v2"\n' > "$LIVE/server.py"
printf '# isolated synthetic v1 server\nVERSION="v1"\n' > "$BACKUP/server.py.pre-v2"

# Explicit state, legacy checkpoint, pin group and timer list.
cat > "$LIVE/state.json" << 'JSON'
{"cmd":{"id":1795063030},"result":{"id":1795055213880},"polls":2439,
 "pins":["synthetic-pin-a","synthetic-pin-b"],"timers":["t1","t2","t3","t4","t5"]}
JSON
printf '%s\n' 1795055213880 > "$LIVE/sgbridge_last_id"
printf '%s\n' '["synthetic-pin-a","synthetic-pin-b"]' > "$LIVE/pins.json"
printf '%s\n' '["t1","t2","t3","t4","t5"]' > "$LIVE/timers.json"

# Snapshot every file that the code-only rollback MUST NOT change.
for f in state.json sgbridge_last_id pins.json timers.json; do
  cp "$LIVE/$f" "$SNAPSHOT/$f"
done
cp "$LIVE/bridge.js" "$SNAPSHOT/bridge.js.v2"
cp "$LIVE/bridge.sgmodule" "$SNAPSHOT/bridge.sgmodule.v2"
cp "$LIVE/server.py" "$SNAPSHOT/server.py.v2"

# Controlled rollback: ONLY the three code files are restored.
cp "$BACKUP/bridge.js.pre-v2" "$LIVE/bridge.js"
cp "$BACKUP/bridge.sgmodule.pre-v2" "$LIVE/bridge.sgmodule"
cp "$BACKUP/server.py.pre-v2" "$LIVE/server.py"

# Negative-control fault injection is restricted to this synthetic root.
if [ "$#" -eq 1 ] && [ "$1" = "--inject-state-change" ]; then
  printf 'synthetic mutation\n' >> "$LIVE/state.json"
fi

for f in state.json sgbridge_last_id pins.json timers.json; do
  cmp -s "$SNAPSHOT/$f" "$LIVE/$f" || die "$f altered"
done
for pair in 'bridge.js:bridge.js.pre-v2' 'bridge.sgmodule:bridge.sgmodule.pre-v2' 'server.py:server.py.pre-v2'; do
  dest="${pair%%:*}"
  backup="${pair#*:}"
  cmp -s "$BACKUP/$backup" "$LIVE/$dest" || die "$dest not restored"
done
# The rollback must actually replace each distinct v2 file, not no-op.
for f in bridge.js bridge.sgmodule server.py; do
  cmp -s "$SNAPSHOT/$f.v2" "$LIVE/$f" && die "$f unchanged after rollback"
done

# Exact legacy pending ID is still present (no command clearing/replay).
python3 - "$LIVE/state.json" << 'PY'
import json, sys
with open(sys.argv[1], encoding="utf8") as fp:
    state = json.load(fp)
assert state["cmd"]["id"] == 1795063030
assert state["result"]["id"] == 1795055213880
assert len(state["timers"]) == 5
assert len(state["pins"]) == 2
PY
printf 'ROLLBACK_TEST: PASS (hermetic code-only restore; state, last_id, pins, timers unchanged)\n'
