#!/bin/sh
# Surge Issue #73 — install new unit definitions DISABLED ONLY.
# NEVER stops old timers, masks old services, starts new writer, edits
# served/staging or changes phone routing. Default is --dry-run.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
MODE=${1:---dry-run}
UNIT_DIR=/etc/systemd/system
SERVICE=p2p3-single-publish.service
TIMER=p2p3-single-publish.timer
case "$MODE" in
  --dry-run)
    printf '%s\n' "PROPOSED_DISABLED_INSTALL_ONLY"
    printf '%s\n' "$HERE/$SERVICE -> $UNIT_DIR/$SERVICE"
    printf '%s\n' "$HERE/$TIMER -> $UNIT_DIR/$TIMER"
    printf '%s\n' "No timers stopped; no systemd modification performed."
    ;;
  --install-disabled)
    test "$(id -u)" -eq 0 || {
      printf '%s\n' "Root required" >&2
      exit 2
    }
    # Never overwrite site-specific units; require review on conflict.
    for name in "$SERVICE" "$TIMER"; do
      test -f "$HERE/$name" || exit 2
      test ! -e "$UNIT_DIR/$name" || {
        printf '%s\n' "Refusing existing unit overwrite: $name" >&2
        exit 2
      }
    done
    # Create the replacement definitions without activation.
    install -m 0644 "$HERE/$SERVICE" "$UNIT_DIR/$SERVICE"
    install -m 0644 "$HERE/$TIMER" "$UNIT_DIR/$TIMER"
    systemctl daemon-reload
    # This action NEVER calls systemctl enable/start. Confirm absent.
    if systemctl is-active --quiet "$TIMER" ||
       systemctl is-active --quiet "$SERVICE"; then
      printf '%s\n' "Unexpected new unit activation; manual review required" >&2
      exit 3
    fi
    printf '%s\n' "INSTALLED_DISABLED_ONLY"
    printf '%s\n' "Do not enable until source parity, rollback, guard and STOP are proven."
    ;;
  *)
    printf '%s\n' "Usage: $0 [--dry-run|--install-disabled]" >&2
    exit 2
    ;;
esac
