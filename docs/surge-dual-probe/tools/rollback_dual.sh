#!/bin/bash
# Issue #73 B1 - FAIL-CLOSED release-bound rollback.
# Manifest from deploy_dual.sh stage 2 pins originals + hashes for ONE release.
# No GitHub-redacted placeholder or latest-bak guessing. Wi-Fi tables retained.
set -euo pipefail

PROBE_BASE="${PROBE_BASE:-/opt/probe-service}"
SERVICE_DST="${SERVICE_DST:-/opt/probe-service/probe_service.py}"
SCRIPT_DST="${SCRIPT_DST:-/opt/surge-bridge/modules/probe-task.js}"
LOCAL_BASE="${PROBE_LOCAL_BASE:-http://127.0.0.1:18081}"
PUBLIC_BASE="${PROBE_PUBLIC_BASE:-https://127.0.0.1:8443}"
RENDER_CONF="${DEPLOY_RENDER_CONF:-$PROBE_BASE/config/deploy-render.conf}"
RELEASE_MANIFEST="$PROBE_BASE/config/dual-release.manifest"
SEG_FILE="$PROBE_BASE/config/probe-path.txt"
DB_PATH="$PROBE_BASE/data/probe.db"

sha_of() { sha256sum "$1" | awk '{print $1}'; }
fail() { echo "rollback gate failed: $1" >&2; exit 1; }

[ -f "$RELEASE_MANIFEST" ] || fail "single-release manifest missing"
[ -f "$RENDER_CONF" ] || fail "private render config missing"
[ -f "$SEG_FILE" ] || fail "private segment missing"
[ "$(stat -c %a "$RELEASE_MANIFEST")" = 600 ] || fail "manifest permissions must be 600"

PROBE_HOST=""
NGINX_CONF=""
while IFS='=' read -r key value; do
  case "$key" in
    PROBE_HOST) PROBE_HOST="$value";;
    NGINX_CONF) NGINX_CONF="$value";;
  esac
done < "$RENDER_CONF"
[ -n "$PROBE_HOST" ] && [ -n "$NGINX_CONF" ] || fail "missing private host/nginx config"
[[ "$PROBE_HOST" =~ ^[A-Za-z0-9.-]+$ ]] || fail "invalid host"
[ -f "$NGINX_CONF" ] || fail "configured nginx file missing"
SEG="$(cat "$SEG_FILE")"
[[ "$SEG" =~ ^[A-Za-z0-9_-]{8,64}$ ]] || fail "invalid private segment"

RELEASE_ID="" MAN_SERVICE_DST="" MAN_SCRIPT_DST="" MAN_NGINX_CONF=""
SERVICE_BAK="" SERVICE_SHA="" SCRIPT_BAK="" SCRIPT_SHA=""
NGINX_BAK="" NGINX_SHA="" DB_BAK="" DB_SHA=""
while IFS='=' read -r key value; do
  case "$key" in
    RELEASE_ID) RELEASE_ID="$value";;
    SERVICE_DST) MAN_SERVICE_DST="$value";;
    SERVICE_BAK) SERVICE_BAK="$value";;
    SERVICE_SHA) SERVICE_SHA="$value";;
    SCRIPT_DST) MAN_SCRIPT_DST="$value";;
    SCRIPT_BAK) SCRIPT_BAK="$value";;
    SCRIPT_SHA) SCRIPT_SHA="$value";;
    NGINX_CONF) MAN_NGINX_CONF="$value";;
    NGINX_BAK) NGINX_BAK="$value";;
    NGINX_SHA) NGINX_SHA="$value";;
    DB_BAK) DB_BAK="$value";;
    DB_SHA) DB_SHA="$value";;
    *) fail "unexpected manifest field";;
  esac
done < "$RELEASE_MANIFEST"

[[ "$RELEASE_ID" =~ ^[0-9]{8}-[0-9]{6}$ ]] || fail "invalid release ID"
[ "$SERVICE_DST" = "$MAN_SERVICE_DST" ] || fail "service target mismatch"
[ "$SCRIPT_DST" = "$MAN_SCRIPT_DST" ] || fail "script target mismatch"
[ "$NGINX_CONF" = "$MAN_NGINX_CONF" ] || fail "nginx target mismatch"

# Verify ALL originals before restoring the first file.
for kind in SERVICE SCRIPT NGINX DB; do
  bak_var="${kind}_BAK"; sha_var="${kind}_SHA"
  bak="${!bak_var}"; wanted="${!sha_var}"
  [ -n "$bak" ] && [ -f "$bak" ] || fail "missing $kind release backup"
  [[ "$wanted" =~ ^[0-9a-f]{64}$ ]] || fail "invalid $kind SHA"
  [ "$(sha_of "$bak")" = "$wanted" ] || fail "$kind backup SHA mismatch"
done
python3 - "$DB_BAK" <<'PY' || fail "DB backup integrity check failed"
import sqlite3, sys
c = sqlite3.connect("file:" + sys.argv[1] + "?mode=ro", uri=True)
try:
    assert c.execute("PRAGMA integrity_check").fetchone()[0] == "ok"
finally:
    c.close()
PY

echo "== rollback step 1: original script =="
cp "$SCRIPT_BAK" "$SCRIPT_DST"
[ "$(sha_of "$SCRIPT_DST")" = "$SCRIPT_SHA" ] || fail "script restore SHA mismatch"
chmod 644 "$SCRIPT_DST"

echo "== rollback step 2: original nginx =="
cp "$NGINX_BAK" "$NGINX_CONF"
nginx -t || fail "nginx syntax error after restore"
systemctl reload nginx || fail "nginx reload failed"
wifi_status="$(curl -sk -o /dev/null -w '%{http_code}' \
  -H "Host: $PROBE_HOST" -H "X-Probe-Action: tasks" -H "X-Probe-Network: wifi" \
  "$PUBLIC_BASE/$SEG-wifi")"
[ "$wifi_status" = 404 ] || fail "wifi route remains active after rollback"

echo "== rollback step 3: original probe service =="
cp "$SERVICE_BAK" "$SERVICE_DST"
[ "$(sha_of "$SERVICE_DST")" = "$SERVICE_SHA" ] || fail "service restore SHA mismatch"
systemctl restart probe-service || fail "service restart failed"
systemctl is-active --quiet probe-service || fail "service inactive"
cell_status="$(curl -s -o /dev/null -w '%{http_code}' \
  -H "X-Probe-Action: tasks" "$LOCAL_BASE/$SEG")"
[ "$cell_status" = 200 ] || fail "legacy cellular tasks not healthy"

echo "== preserve wifi tables (no DROP TABLE) =="
python3 - "$DB_PATH" <<'PY' || fail "audit read failed"
import sqlite3, sys
c = sqlite3.connect("file:" + sys.argv[1] + "?mode=ro", uri=True)
try:
    for table in ("probe_reports_wifi", "probe_nodes_wifi", "probe_reports"):
        present = c.execute(
            "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?", (table,)
        ).fetchone()
        count = c.execute('SELECT COUNT(*) FROM "' + table + '"').fetchone()[0] if present else 0
        print(table + "_rows=" + str(count))
finally:
    c.close()
PY
mv "$RELEASE_MANIFEST" "$RELEASE_MANIFEST.rolledback-$RELEASE_ID"
echo "rollback complete: verified original versions, release manifest archived."
