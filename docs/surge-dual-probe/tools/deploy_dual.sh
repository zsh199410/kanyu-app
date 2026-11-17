#!/bin/bash
# Deploy the #73 dual-channel (B1) probe patch to production — STAGED.
# ISOLATED SCRIPT: do NOT run without GPT's explicit deploy approval
# (Issue #73). Real host/path values are NEVER in this file: they come
# from the private render config (600) on the server
# (/opt/probe-service/config/deploy-render.conf: PROBE_HOST + NGINX_CONF)
# and from /opt/probe-service/config/probe-path.txt (segment). The
# patch files come from the reviewed Draft PR (or the isolation tree).
#
# Stages (docs/STAGED_RUNBOOK.md). Each stage runs ALONE and STOPS:
# the operator verifies that stage's gate, then runs the next stage.
# There is no "run everything" mode (GPT #6940445042 P0-3).
#   1 baseline   (no changes): cellular tasks 200, wifi 404, record
#                  cellular tables SHA + stats snapshot.
#   2 service    backup service file + WAL-safe DB snapshot (SQLite
#                  backup API, tools/backup_db.py — never plain cp of
#                  the live WAL database), install new service,
#                  restart, cellular tasks 200.
#   3 nginx      add the -wifi location, nginx -t, reload, wifi 200.
#   4 compat     (no changes): old cellular still works, wifi tasks
#                  returns a batch, header mismatch 400. Production
#                  wifi REPORTS are NOT required here: the phone still
#                  runs the old script; they come in stage 5.
#   5 script     private render (tools/render_probe_script.py:
#                  placeholders fail-closed, CLIENT_VERSION recomputed
#                  from the rendered content), deploy the RENDERED
#                  script, verify by the RENDERED product SHA (never
#                  the desensitized GitHub SHA). Phone picks it up
#                  next hour.
# Rollback is tools/rollback_dual.sh (reverse order; wifi tables always
# retained).
#
# Usage:
#   sudo bash tools/deploy_dual.sh 1
#   sudo bash tools/deploy_dual.sh 2 <service_file> <service_sha>
#   sudo bash tools/deploy_dual.sh 3
#   sudo bash tools/deploy_dual.sh 4
#   sudo bash tools/deploy_dual.sh 5 <script_file> <script_sha>
#
# Env overrides (isolated testing only; production uses the defaults):
#   PROBE_BASE        default /opt/probe-service
#   PROBE_LOCAL_BASE  default http://127.0.0.1:18081 (direct service)
#   PROBE_PUBLIC_BASE default https://127.0.0.1:8443 (public nginx)
#   SERVICE_DST / SCRIPT_DST default production paths
set -euo pipefail

TOOLS_DIR="$(cd "$(dirname "$0")" && pwd)"
PROBE_BASE="${PROBE_BASE:-/opt/probe-service}"
LOCAL_BASE="${PROBE_LOCAL_BASE:-http://127.0.0.1:18081}"
PUBLIC_BASE="${PROBE_PUBLIC_BASE:-https://127.0.0.1:8443}"
SERVICE_DST="${SERVICE_DST:-/opt/probe-service/probe_service.py}"
SCRIPT_DST="${SCRIPT_DST:-/opt/surge-bridge/modules/probe-task.js}"
DB_PATH="$PROBE_BASE/data/probe.db"
SEG_FILE="$PROBE_BASE/config/probe-path.txt"
RENDER_CONF="${DEPLOY_RENDER_CONF:-$PROBE_BASE/config/deploy-render.conf}"
TS="$(date +%Y%m%d-%H%M%S)"

usage() {
  echo "usage: deploy_dual.sh <stage 1|2|3|4|5> [args]" >&2
  echo "  1                 baseline (no changes)" >&2
  echo "  2 <svc> <sha>     swap service" >&2
  echo "  3                 add nginx -wifi location" >&2
  echo "  4                 compat verification (no changes)" >&2
  echo "  5 <script> <sha>  render + swap phone script" >&2
  exit 2
}

sha_of() { sha256sum "$1" | awk '{print $1}'; }

read_seg() {
  [ -f "$SEG_FILE" ] || { echo "probe-path.txt not found: $SEG_FILE"; exit 1; }
  SEG="$(cat "$SEG_FILE")"
  [ -n "$SEG" ] || { echo "probe-path.txt empty"; exit 1; }
}

# Render-conf values (host + nginx conf). Stages 3 and 5 REQUIRE them;
# stages 1, 2 and 4 do not (stage 1/4 send no Host header when unknown).
read_render_conf() {
  PROBE_HOST=""; NGINX_CONF=""
  if [ -f "$RENDER_CONF" ]; then
    PROBE_HOST="$(grep -E '^PROBE_HOST=' "$RENDER_CONF" | cut -d= -f2- | tr -d '[:space:]')"
    NGINX_CONF="$(grep -E '^NGINX_CONF=' "$RENDER_CONF" | cut -d= -f2- | tr -d '[:space:]')"
  fi
}

require_render_conf() {
  read_render_conf
  [ -n "$PROBE_HOST" ] || { echo "PROBE_HOST missing from $RENDER_CONF"; exit 1; }
  [ -n "$NGINX_CONF" ] || { echo "NGINX_CONF missing from $RENDER_CONF"; exit 1; }
  [ -f "$NGINX_CONF" ] || { echo "NGINX_CONF does not exist: $NGINX_CONF"; exit 1; }
}

host_args() {
  # Optional Host header for the public wifi checks (only when the
  # private render conf supplied a host).
  if [ -n "${PROBE_HOST:-}" ]; then echo "-H" "Host: $PROBE_HOST"; fi
}

cell_tables_sha() {
  python3 - "$DB_PATH" <<'PY'
import sqlite3, json, hashlib, sys
c = sqlite3.connect(sys.argv[1])
out = {}
for t in ('probe_reports', 'probe_nodes'):
    out[t] = [list(r) for r in c.execute(f'SELECT * FROM {t} ORDER BY 1, 2')]
print('cell_tables_sha=' + hashlib.sha256(json.dumps(out, sort_keys=True).encode()).hexdigest())
PY
}

http_code() { # $1 = url, rest = extra curl args
  local url="$1"; shift
  curl -sk -o /dev/null -w "%{http_code}" "$@" "$url"
}

expect_code() { # $1 = wanted, $2 = label, $3 = url, rest = curl args
  local want="$1" label="$2" url="$3"; shift 3
  local got
  got="$(http_code "$url" "$@")"
  echo "$label: $got"
  [ "$got" = "$want" ] || { echo "GATE FAILED: $label expected $want, got $got"; exit 1; }
}

stage_1() {
  echo "== stage 1: baseline (no changes) =="
  read_seg
  read_render_conf
  expect_code 200 "cellular tasks" "$LOCAL_BASE/$SEG" -H "X-Probe-Action: tasks"
  # shellcheck disable=SC2046
  expect_code 404 "wifi tasks (public)" "$PUBLIC_BASE/$SEG-wifi" $(host_args) -H "X-Probe-Action: tasks" -H "X-Probe-Network: wifi"
  cell_tables_sha
  curl -s -H "X-Probe-Action: stats" "$LOCAL_BASE/$SEG" | head -c 600; echo
  echo "stage 1 complete: baseline recorded. Verify the runbook checks, then run stage 2."
}

stage_2() {
  local service_file="$1" service_sha="$2"
  echo "== stage 2: swap service =="
  read_seg
  [ "$(sha_of "$service_file")" = "$service_sha" ] || { echo "service sha mismatch"; exit 1; }
  systemctl is-active --quiet probe-service || { echo "probe-service not running"; exit 1; }
  cp "$SERVICE_DST" "$SERVICE_DST.bak-$TS"
  # WAL-safe DB snapshot (P0-4): the SQLite backup API, never plain cp
  # of the live WAL database.
  python3 "$TOOLS_DIR/backup_db.py" "$DB_PATH" "$DB_PATH.bak-$TS" || exit 1
  cp "$service_file" "$SERVICE_DST"
  [ "$(sha_of "$SERVICE_DST")" = "$service_sha" ] || { echo "service copy sha mismatch"; exit 1; }
  systemctl restart probe-service
  sleep 2
  systemctl is-active --quiet probe-service || { echo "probe-service failed to start"; exit 1; }
  expect_code 200 "cellular tasks" "$LOCAL_BASE/$SEG" -H "X-Probe-Action: tasks"
  echo "stage 2 complete: new service answers; old script shape still accepted."
  echo "Backups: $SERVICE_DST.bak-$TS, $DB_PATH.bak-$TS"
  echo "Verify the runbook checks, then run stage 3."
}

stage_3() {
  echo "== stage 3: add nginx -wifi location =="
  read_seg
  require_render_conf
  cp "$NGINX_CONF" "$NGINX_CONF.bak-$TS"
  if grep -q "location = /$SEG-wifi" "$NGINX_CONF"; then
    echo "-wifi location already present, skipping insert"
  else
    # Insert the wifi location directly after the existing cellular block.
    python3 - "$NGINX_CONF" "$SEG" <<'PYEOF'
import sys
conf, seg = sys.argv[1], sys.argv[2]
src = open(conf).read()
anchor = "location = /" + seg + " {"
assert anchor in src, "cellular location block not found in nginx conf"
block = (
    "    location = /" + seg + "-wifi {\n"
    "        proxy_pass http://127.0.0.1:18081;\n"
    "        proxy_http_version 1.1;\n"
    "        proxy_set_header Host $host;\n"
    "        client_max_body_size 64k;\n"
    "    }\n"
)
src = src.replace(anchor, block + "    " + anchor, 1)
open(conf, "w").write(src)
print("inserted -wifi location")
PYEOF
  fi
  nginx -t || { echo "nginx -t failed, restoring"; cp "$NGINX_CONF.bak-$TS" "$NGINX_CONF"; exit 1; }
  systemctl reload nginx
  # shellcheck disable=SC2046
  expect_code 200 "wifi tasks (public)" "$PUBLIC_BASE/$SEG-wifi" $(host_args) -H "X-Probe-Action: tasks" -H "X-Probe-Network: wifi"
  expect_code 200 "cellular tasks" "$LOCAL_BASE/$SEG" -H "X-Probe-Action: tasks"
  echo "stage 3 complete: wifi endpoint reachable; cellular unchanged."
  echo "Backup: $NGINX_CONF.bak-$TS"
  echo "Verify the runbook checks, then run stage 4."
}

stage_4() {
  echo "== stage 4: compat verification (no changes) =="
  read_seg
  read_render_conf
  # Old script (cellular) still works on the new service.
  expect_code 200 "cellular tasks" "$LOCAL_BASE/$SEG" -H "X-Probe-Action: tasks"
  # The wifi endpoint answers with a batch (isolated check: a tasks GET
  # through the test harness/proxy). Production wifi REPORTS are NOT
  # required here — the phone still runs the OLD script, which never
  # calls the wifi endpoint; those reports come in stage 5.
  # shellcheck disable=SC2046
  expect_code 200 "wifi tasks (public)" "$PUBLIC_BASE/$SEG-wifi" $(host_args) -H "X-Probe-Action: tasks" -H "X-Probe-Network: wifi"
  # Header/path mismatch is still fail-closed.
  # shellcheck disable=SC2046
  expect_code 400 "wifi tasks, wrong header" "$PUBLIC_BASE/$SEG-wifi" $(host_args) -H "X-Probe-Action: tasks" -H "X-Probe-Network: cellular"
  cell_tables_sha
  echo "stage 4 complete: old cellular compatible; wifi route live."
  echo "Verify the runbook checks (including the phone's next hourly cellular report), then run stage 5."
}

stage_5() {
  local script_file="$1" script_sha="$2"
  echo "== stage 5: render + swap phone script =="
  read_seg
  require_render_conf
  [ "$(sha_of "$script_file")" = "$script_sha" ] || { echo "script sha mismatch (desensitized input)"; exit 1; }
  # Private render (P0-2): placeholders fail-closed, CLIENT_VERSION
  # recomputed from the rendered content. The deployed product SHA is
  # the RENDERED sha, never the desensitized GitHub sha.
  rendered="$(mktemp)"
  trap 'rm -f "$rendered"' EXIT
  python3 "$TOOLS_DIR/render_probe_script.py" \
    "$script_file" "$RENDER_CONF" "$SEG_FILE" "$rendered" || exit 1
  rendered_sha="$(sha_of "$rendered")"
  cp "$SCRIPT_DST" "$SCRIPT_DST.bak-$TS"
  cp "$rendered" "$SCRIPT_DST"
  [ "$(sha_of "$SCRIPT_DST")" = "$rendered_sha" ] || { echo "deployed script sha mismatch (rendered)"; exit 1; }
  chmod 644 "$SCRIPT_DST"
  echo "deployed rendered script sha256=$rendered_sha"
  echo "stage 5 complete. Phone picks up the new script at its next hourly run."
  echo "Backup: $SCRIPT_DST.bak-$TS"
  echo "After the next hour, verify both channels report (runbook stage 5 checks)."
}

STAGE="${1:-}"
case "$STAGE" in
  1) stage_1 ;;
  2) [ $# -eq 3 ] || usage; stage_2 "$2" "$3" ;;
  3) stage_3 ;;
  4) stage_4 ;;
  5) [ $# -eq 3 ] || usage; stage_5 "$2" "$3" ;;
  *) usage ;;
esac
