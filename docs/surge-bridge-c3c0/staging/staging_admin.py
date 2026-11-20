#!/usr/bin/env python3
"""C3-C0 staging admin (runs on the VPS, same DB as the staging service).

Admin-only operations on the synthetic test registry: counts, audit,
activate-backup, revoke. Prints IDs/roles/statuses only — never token values.
"""
import json
import os
import sys
import time

BASE = "/opt/c3c0-staging"
sys.path.insert(0, BASE)
from nonce_ledger_sqlite import NonceLedger
from token_registry_sqlite import TokenRegistry


def load():
    with open(os.path.join(BASE, "config.json")) as f:
        cfg = json.load(f)
    ledger = NonceLedger(cfg["db_path"])
    return cfg, ledger, TokenRegistry(ledger)


def main():
    cfg, ledger, registry = load()
    now_ms = time.time_ns() // 1_000_000
    cmd = sys.argv[1] if len(sys.argv) > 1 else "help"
    if cmd == "counts":
        print("ledger counts (total, consumed):", ledger.counts())
        print("registry audit:", registry.audit_counts())
    elif cmd == "activate-backup":
        ok = registry.activate_backup(cfg["backup_token_id"], now_ms=now_ms)
        print("activate-backup %s -> %s" % (cfg["backup_token_id"], ok))
        print("registry audit:", registry.audit_counts())
    elif cmd == "revoke":
        token_id = sys.argv[2]
        ok = registry.revoke(token_id, now_ms=now_ms)
        print("revoke %s -> %s" % (token_id, ok))
        print("registry audit:", registry.audit_counts())
    elif cmd == "auth-check":
        # Mock bridge auth for a token id (uses the value from config only).
        token_id = sys.argv[2]
        res = registry.authorize(cfg["tokens"][token_id], kind="dev", now_ms=now_ms)
        print("authorize %s -> %s" % (token_id, res))
    else:
        print("usage: staging_admin.py counts | activate-backup | "
              "revoke TOKEN_ID | auth-check TOKEN_ID")


if __name__ == "__main__":
    main()
