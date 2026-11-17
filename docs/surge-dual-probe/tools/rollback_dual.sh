#!/bin/bash
# Roll back the #73 dual-channel (B1) probe patch — reverse order (P0-4):
#   1. phone script  (restore the old script; phone picks it up next hour)
#   2. nginx         (remove the -wifi location; restore from backup)
#   3. service       (restore the original service binary; restart)
# The wifi tables are ALWAYS RETAINED for audit. Removing them is NOT a
# rollback step (GPT #6938432964 gate 5: routine rollback keeps the
# wifi tables; there is no cleanup flag).
#
# Usage:
#   sudo bash tools/rollback_dual.sh
# The backups taken by tools/deploy_dual.sh are used; if none exist the
# script refuses to run (pass explicit files via env overrides, see below).
set -euo pipefail

SERVICE_DST=/opt/probe-service/probe_service.py
SCRIPT_DST=/opt/surge-bridge/modules/probe-task.js
NGINX_CONF=/etc/nginx/conf.d/<nginx-vhost>.conf
SEG="$(cat /opt/probe-service/config/probe-path.txt)"
# Desensitized PR copy: SHA of the desensitized orig script in
# this PR. At deploy time substitute the production orig-script
# SHA (isolation tree docs/SHA_MANIFEST.md).
ORIG_SCRIPT_SHA=9a05ff0e82d387e37d6cabf6b97cf30cde41c880f62aaceff001e8751fd8c77a

sha_of() { sha256sum "$1" | awk '{print $1}'; }
latest_bak() { ls -t "$1".bak-* 2>/dev/null | head -1; }

SERVICE_BAK="${SERVICE_BAK:-$(latest_bak "$SERVICE_DST")}"
SCRIPT_BAK="${SCRIPT_BAK:-$(latest_bak "$SCRIPT_DST")}"
NGINX_BAK="${NGINX_BAK:-$(latest_bak "$NGINX_CONF")}"
[ -n "$SERVICE_BAK" ] && [ -f "$SERVICE_BAK" ] || { echo "no service backup found"; exit 1; }
[ -n "$SCRIPT_BAK" ] && [ -f "$SCRIPT_BAK" ] || { echo "no script backup found"; exit 1; }
[ -n "$NGINX_BAK" ] && [ -f "$NGINX_BAK" ] || { echo "no nginx backup found"; exit 1; }

echo "== rollback step 1: phone script =="
cp "$SCRIPT_BAK" "$SCRIPT_DST"
[ "$(sha_of "$SCRIPT_DST")" = "$ORIG_SCRIPT_SHA" ] || { echo "restored script sha mismatch"; exit 1; }
chmod 644 "$SCRIPT_DST"
echo "old script restored (sha $ORIG_SCRIPT_SHA); phone picks it up next hour."

echo "== rollback step 2: nginx =="
cp "$NGINX_BAK" "$NGINX_CONF"
nginx -t || { echo "nginx -t failed after restore"; exit 1; }
systemctl reload nginx
curl -sk -o /dev/null -w "wifi path after rollback: %{http_code}\n" \
  -H "Host: <probe-host>" -H "X-Probe-Action: tasks" -H "X-Probe-Network: wifi" \
  "https://127.0.0.1:8443/$SEG-wifi" | grep -q "404" \
  || { echo "wifi path still reachable after nginx rollback"; exit 1; }

echo "== rollback step 3: service =="
cp "$SERVICE_BAK" "$SERVICE_DST"
systemctl restart probe-service
sleep 2
systemctl is-active --quiet probe-service || { echo "probe-service failed to start"; exit 1; }
curl -s -o /dev/null -w "cellular tasks: %{http_code}\n" \
  -H "X-Probe-Action: tasks" "http://127.0.0.1:18081/$SEG" | grep -q "200" \
  || { echo "cellular tasks health check failed"; exit 1; }
echo "cellular service restored; old script shape still accepted."

echo "== wifi tables: RETAINED for audit (always) =="
python3 -c "
import sqlite3
c = sqlite3.connect('/opt/probe-service/data/probe.db')
print('probe_reports_wifi rows retained:',
      c.execute('SELECT COUNT(*) FROM probe_reports_wifi').fetchone()[0])
print('cellular probe_reports rows:',
      c.execute('SELECT COUNT(*) FROM probe_reports').fetchone()[0])
"

echo "rollback complete."
