#!/bin/bash
# Deploy the #73 dual-channel (B1) probe patch to production — 3 steps.
# ISOLATED SCRIPT: do NOT run without GPT's explicit deploy approval
# (Issue #73). Production paths below are real; the patch files come
# from the reviewed Draft PR (or the isolation tree).
#
# This script implements stages 2, 3 and 5 of docs/STAGED_RUNBOOK.md
# (five-stage acceptance: 1 baseline -> 2 service -> 3 nginx ->
# 4 old+new script compat -> 5 script swap, plus reverse rollback).
# Stage 1 (baseline) and stage 4 (compat verification) are manual
# checks in the runbook, not script steps. Rollback is
# tools/rollback_dual.sh (reverse order; wifi tables always retained).
#
# Order matters (P0-4):
#   1. service  (new service is backward compatible with the old script)
#   2. nginx    (add the -wifi location; old script never calls it)
#   3. script   (phone picks it up at the next hourly run)
# Each step backs up, verifies SHA256, and health-checks before moving on.
# Rollback is tools/rollback_dual.sh (reverse order).
#
# Usage:
#   sudo bash tools/deploy_dual.sh <service_file> <script_file> \
#        <expected_service_sha256> <expected_script_sha256>
set -euo pipefail

SERVICE_FILE="${1:?usage: deploy_dual.sh <service_file> <script_file> <service_sha> <script_sha>}"
SCRIPT_FILE="${2:?usage: deploy_dual.sh <service_file> <script_file> <service_sha> <script_sha>}"
SERVICE_SHA="${3:?missing expected service sha256}"
SCRIPT_SHA="${4:?missing expected script sha256}"

SERVICE_DST=/opt/probe-service/probe_service.py
SCRIPT_DST=/opt/surge-bridge/modules/probe-task.js
NGINX_CONF=/etc/nginx/conf.d/<nginx-vhost>.conf
SEG="$(cat /opt/probe-service/config/probe-path.txt)"
TS="$(date +%Y%m%d-%H%M%S)"

sha_of() { sha256sum "$1" | awk '{print $1}'; }

echo "== step 0: sanity =="
[ "$(sha_of "$SERVICE_FILE")" = "$SERVICE_SHA" ] || { echo "service sha mismatch"; exit 1; }
[ "$(sha_of "$SCRIPT_FILE")" = "$SCRIPT_SHA" ] || { echo "script sha mismatch"; exit 1; }
[ -n "$SEG" ] || { echo "probe-path.txt empty"; exit 1; }
systemctl is-active --quiet probe-service || { echo "probe-service not running"; exit 1; }

echo "== step 1: service =="
cp "$SERVICE_DST" "$SERVICE_DST.bak-$TS"
cp /opt/probe-service/data/probe.db "/opt/probe-service/data/probe.db.bak-$TS"
cp "$SERVICE_FILE" "$SERVICE_DST"
[ "$(sha_of "$SERVICE_DST")" = "$SERVICE_SHA" ] || { echo "service copy sha mismatch"; exit 1; }
systemctl restart probe-service
sleep 2
systemctl is-active --quiet probe-service || { echo "probe-service failed to start"; exit 1; }
curl -s -o /dev/null -w "cellular tasks: %{http_code}\n" \
  -H "X-Probe-Action: tasks" "http://127.0.0.1:18081/$SEG" | grep -q "200" \
  || { echo "cellular tasks health check failed"; exit 1; }
# Old script must still work: the new service answers the old client
# shape (no network_type, no pool sha) on the cellular path.

echo "== step 2: nginx (-wifi location) =="
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
curl -sk -o /dev/null -w "wifi tasks (public): %{http_code}\n" \
  -H "Host: <probe-host>" -H "X-Probe-Action: tasks" -H "X-Probe-Network: wifi" \
  "https://127.0.0.1:8443/$SEG-wifi" | grep -q "200" \
  || { echo "wifi endpoint check failed"; exit 1; }

echo "== step 3: phone script =="
cp "$SCRIPT_DST" "$SCRIPT_DST.bak-$TS"
cp "$SCRIPT_FILE" "$SCRIPT_DST"
[ "$(sha_of "$SCRIPT_DST")" = "$SCRIPT_SHA" ] || { echo "script copy sha mismatch"; exit 1; }
chmod 644 "$SCRIPT_DST"
echo "deployed. Phone picks up the new script at its next hourly run."
echo "Backups: $SERVICE_DST.bak-$TS, probe.db.bak-$TS, $NGINX_CONF.bak-$TS, $SCRIPT_DST.bak-$TS"
echo "Post-deploy checks: cellular /stats unchanged vs pre-deploy; wifi"
echo "endpoint counting; next hour both channels report with correct labels."
