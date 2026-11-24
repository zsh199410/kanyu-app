#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""P0 #73: one-observation-at-a-time import of proven iPhone failures.

DRY RUN by default. This module does not publish, quarantine, delete, or
modify the subscriber pool. It is deliberately separate from the original
VPS importer until its current schema and receipts have been audited.

Trusted-failure gate (integration-01, Issue #73 G10): only failures with
control_verified=1, probe_mode='external_policy_id' and bearer='cellular'
are imported; the rest are diagnostic history and are never imported.

Integration-01 v2 (Review 6033276893, fix 5): the v2 receiver records
trial_generation and dual_target_ok per observation. This importer reads
them when present (PRAGMA detection; a pre-v2 staging DB yields null/0)
and writes them into the phone_failures detail JSON as audit metadata.
The G10 gate is unchanged; no generation gate is added here, because
formal-pool evidence has no trial generation to compare against, and
pre-v2 trusted rows (11-06/11-20/21) carry no generation.

Integration-04 (Review 6034204978, point 3): the importer now actually
CLASSIFIES on trial_generation (phone_evidence.classify_row, shared with
the legacy importer). An integer generation means the row is trial
evidence and is NEVER imported here (skipped as trial_generation_bound)
-- a trial row must never become formal prune evidence, even if it
carries cv=1 / external_policy_id / cellular. A null generation means
formal historical evidence and continues through the G10 gate; imported
rows carry an explicit "evidence_class": "formal_historical" in the
detail JSON so the prune consumer can tell the classes apart without
re-reading the staging DB.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import sqlite3
import sys
import time
from urllib.parse import quote

from phone_evidence import classify_row
from receiver import parse_pool

MAX_ROWS = 100000
MAX_AGE_SECONDS = 3 * 86400
APPROVAL = "YES_EXPLICITLY"
COLUMNS = ("nonce", "protocol", "host", "port", "status", "probe_mode",
           "trusted", "received_at", "bearer", "pool_sha", "control_verified")


class ImportRefused(ValueError):
    pass


def ro_connection(path):
    p = Path(path)
    if not p.is_absolute() or not p.is_file() or p.is_symlink():
        raise ImportRefused("missing_or_unsafe_sqlite")
    conn = sqlite3.connect("file:" + quote(str(p.resolve()), safe="/") + "?mode=ro",
                           uri=True, timeout=8)
    conn.execute("PRAGMA query_only=ON")
    return conn


def check_schema(conn, table, fields):
    row = conn.execute("PRAGMA table_info(" + table + ")").fetchall()
    if not set(fields) <= {r[1] for r in row}:
        raise ImportRefused("schema_mismatch:" + table)


def read_verified_candidates(staging_path, pool_raw, pins, blocked, *, now):
    pool_by_name = parse_pool(pool_raw)
    current = set(pool_by_name.values())
    if len(current) != len(pool_by_name) or len(pins) != 21 or not pins <= current:
        raise ImportRefused("pin_or_pool_mismatch")
    if blocked & current:
        raise ImportRefused("blocklisted_node_in_pool")
    current_sha = hashlib.sha256(pool_raw).hexdigest()
    c = ro_connection(staging_path)
    try:
        check_schema(c, "phone_observations", COLUMNS)
        count = c.execute("SELECT count(*) FROM phone_observations").fetchone()[0]
        if count > MAX_ROWS:
            raise ImportRefused("too_many_observations")
        # v2 audit columns (integration-01 v2): read when present; a
        # pre-v2 staging DB yields null generation / dual_target_ok=0.
        staging_cols = {r[1] for r in c.execute("PRAGMA table_info(phone_observations)")}
        extra = [n for n in ("trial_generation", "dual_target_ok") if n in staging_cols]
        q = ("SELECT " + ",".join(COLUMNS + tuple(extra)) + " FROM phone_observations "
             "WHERE status='failure' ORDER BY id ASC")
        rows = c.execute(q).fetchall()
    finally:
        c.close()
    candidates = []
    skipped = {"pinned": 0, "stale": 0, "untrusted": 0,
               "outside_pool": 0, "old": 0, "blocked": 0,
               "trial_generation_bound": 0}
    seen = set()
    for row in rows:
        nonce, proto, host, port, status, mode, trusted, ts, bearer, sha, cv = row[:11]
        gen = row[11 + extra.index("trial_generation")] if "trial_generation" in extra else None
        dual = row[11 + extra.index("dual_target_ok")] if "dual_target_ok" in extra else 0
        key = (proto, host, port)
        item_key = (nonce, *key)
        if item_key in seen:
            raise ImportRefused("duplicate_staging_observation")
        seen.add(item_key)
        if not isinstance(nonce, str) or len(nonce) != 32 or not all(x in "0123456789abcdef" for x in nonce):
            raise ImportRefused("invalid_nonce")
        if type(ts) is not int or ts > now + 300:
            raise ImportRefused("invalid_observation_time")
        if ts < now - MAX_AGE_SECONDS:
            skipped["old"] += 1
            continue
        if mode not in ("external_policy_id", "temporary_policy_descriptor"):
            raise ImportRefused("unknown_probe_method")
        # Integration-04 (Review 6034204978, point 3): classify on
        # trial_generation FIRST, before the G10 gate. An integer
        # generation is trial evidence and is NEVER imported by this
        # formal importer (skipped as trial_generation_bound), even with
        # cv=1 / external_policy_id / cellular. A null generation is
        # formal historical evidence and continues.
        if classify_row(gen) == "trial_bound":
            skipped["trial_generation_bound"] += 1
            continue
        # G10 trusted-failure gate (integration-01): a failure is consumable
        # evidence only when status='failure' AND control_verified=1 AND
        # probe_mode='external_policy_id' AND bearer='cellular'. Anything
        # else is diagnostic history and is never imported.
        if (status != "failure" or trusted != 1 or cv != 1
                or mode != "external_policy_id" or bearer != "cellular"):
            skipped["untrusted"] += 1
            continue
        if sha != current_sha:
            skipped["stale"] += 1
            continue
        if key in pins:
            skipped["pinned"] += 1
            continue
        if key in blocked:
            skipped["blocked"] += 1
            continue
        if key not in current:
            skipped["outside_pool"] += 1
            continue
        candidates.append((nonce, *key, ts, bearer, mode, gen, dual))
    return candidates, skipped


def import_once(staging_path, production_db, pool_file, *, now=None,
                apply=False, approved=False):
    now = int(time.time()) if now is None else now
    if apply and not approved:
        raise ImportRefused("explicit_apply_approval_missing")
    pool_p = Path(pool_file)
    if not pool_p.is_absolute() or pool_p.is_symlink() or not pool_p.is_file():
        raise ImportRefused("unsafe_pool_file")
    pool_raw = pool_p.read_bytes()
    prod = ro_connection(production_db)
    try:
        check_schema(prod, "pinned", ("protocol", "host", "port"))
        check_schema(prod, "blocklist", ("protocol", "host", "port"))
        check_schema(prod, "phone_failures",
                     ("protocol", "host", "port", "reported_at", "source", "detail"))
        pins_all = {tuple(r) for r in prod.execute("SELECT protocol,host,port FROM pinned")}
        blocked = {tuple(r) for r in prod.execute("SELECT protocol,host,port FROM blocklist")}
        pins = pins_all - blocked
    finally:
        prod.close()
    candidates, skipped = read_verified_candidates(
        staging_path, pool_raw, pins, blocked, now=now)
    out = {"eligible_staging_rows": len(candidates),
           "skipped": skipped, "new": 0, "reconciled_old": 0,
           "already_processed": 0, "applied": bool(apply)}
    # Re-read-only for dry-run: no schema changes, transactions or production writes.
    if not apply:
        return out
    c = sqlite3.connect(production_db, timeout=10)
    try:
        c.execute("BEGIN IMMEDIATE")
        # Fail closed if the independently-served pool or DB pin protections
        # changed between the dry-run snapshot and this write transaction.
        if hashlib.sha256(Path(pool_file).read_bytes()).digest() != hashlib.sha256(pool_raw).digest():
            raise ImportRefused("pool_changed_during_import")
        live_pins = {tuple(r) for r in c.execute("SELECT protocol,host,port FROM pinned")}
        live_blocked = {tuple(r) for r in c.execute("SELECT protocol,host,port FROM blocklist")}
        if live_pins != pins_all or live_blocked != blocked:
            raise ImportRefused("pin_or_blocklist_changed_during_import")
        check_schema(c, "phone_failures",
                     ("protocol", "host", "port", "reported_at", "source", "detail"))
        c.execute("""CREATE TABLE IF NOT EXISTS phone_import_item_v2 (
             nonce TEXT NOT NULL, protocol TEXT NOT NULL, host TEXT NOT NULL,
             port INTEGER NOT NULL, imported_at INTEGER NOT NULL,
             PRIMARY KEY(nonce,protocol,host,port))""")
        for nonce, proto, host, port, ts, bearer, mode, gen, dual in candidates:
            item = (nonce, proto, host, port)
            if c.execute("""SELECT 1 FROM phone_import_item_v2 WHERE
                         nonce=? AND protocol=? AND host=? AND port=?""", item).fetchone():
                out["already_processed"] += 1
                continue
            # Reconcile rows already inserted by legacy nonce-level importer.
            # A 5-minute window tolerates old arrival-vs-insert timestamp drift,
            # but does NOT treat a separate hourly probe as a duplicate.
            exists = c.execute("""SELECT 1 FROM phone_failures WHERE
                protocol=? AND host=? AND port=? AND source='surge-url-test'
                AND reported_at BETWEEN ? AND ? LIMIT 1""",
                (proto, host, port, ts-300, ts+300)).fetchone()
            if exists:
                out["reconciled_old"] += 1
            else:
                # v2 audit metadata (fix 5): generation and dual-target
                # evidence ride in the detail JSON; they are audit-only and
                # never change the G10 admission decision.
                # Integration-04: the evidence class is explicit so the
                # prune consumer can tell formal historical rows from
                # trial rows without re-reading the staging DB.
                detail = json.dumps({"method": mode, "bearer": bearer,
                                     "control_verified": 1,
                                     "trial_generation": gen,
                                     "dual_target_ok": dual,
                                     "evidence_class": "formal_historical"},
                                    sort_keys=True, separators=(",", ":"))
                c.execute("""INSERT INTO phone_failures
                      (protocol,host,port,reported_at,source,detail)
                      VALUES (?,?,?,?,?,?)""",
                      (proto, host, port, ts, "surge-url-test", detail))
                out["new"] += 1
            # Keyed by observation, NOT batch nonce alone.
            c.execute("""INSERT INTO phone_import_item_v2
                 (nonce,protocol,host,port,imported_at) VALUES (?,?,?,?,?)""",
                 (nonce, proto, host, port, now))
        c.commit()
        return out
    except Exception:
        c.rollback()
        raise
    finally:
        c.close()


def main(argv=None):
    p = argparse.ArgumentParser(description="Issue73 stage phone failures by observation")
    p.add_argument("--staging", required=True)
    p.add_argument("--production-db", required=True)
    p.add_argument("--pool", required=True)
    p.add_argument("--apply", action="store_true")
    args = p.parse_args(argv)
    try:
        result = import_once(args.staging, args.production_db, args.pool,
                             apply=args.apply,
                             approved=os.getenv("PHONE_IMPORT_V2_APPROVED") == APPROVAL)
    except (ImportRefused, OSError, sqlite3.Error, ValueError):
        # No raw SQLite error strings: they could contain file paths / identifiers.
        print(json.dumps({"ok": False, "decision": "HOLD_IMPORT_REFUSED"}))
        return 78
    print(json.dumps({"ok": True, **result}, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
