#!/usr/bin/env python3
"""Migrate: add v3 source-lineage tables (GPT decision 3, Review 6031702642).

Fixes all 5 migration gaps GPT found in v2:
 - verify happens INSIDE the transaction, BEFORE commit; a verification
   failure rolls the whole migration back (no partial tables).
 - --check uses a READ-ONLY connection (SQLite URI mode=ro) and writes
   nothing; it never creates the tables it inspects.
 - A backup is taken first (SQLite backup API), stored under a unique
   timestamped name that is never overwritten, and VERIFIED (integrity +
   row counts) before any write.
 - --rollback restores the DB from a verified --backup; it REFUSES when no
   --backup is given, and refuses when the live DB holds verified lineage
   recorded after the backup (unless --allow-data-loss). It never does an
   unprotected DROP TABLE: deleting the only copy of real history is not
   a "lossless rollback". NOTE: rollback restores the WHOLE DB to the
   backup point, so any tester/scraper writes made after the backup are
   lost too -- run migration in a stop-scraper/stop-tester window.
 - Fail-closed on schema mismatch: if node_sources already exists with
   the v2 layout (7 columns, no fingerprint) or any expected table has
   unexpected columns, exit 1 without touching anything. Historical
   triplets are NEVER fingerprinted: the backfill creates one 'legacy'
   variant + one legacy source row per node (verified=0, NO observation
   times), so no history is fabricated into proof of any variant.

Usage:
  python3 migrate_node_sources.py <db_path> [--backup-dir DIR]
  python3 migrate_node_sources.py <db_path> --check
  python3 migrate_node_sources.py <db_path> --rollback --backup FILE [--allow-data-loss]
Exit codes: 0 ok; 1 verification failed / refused (fail-closed); 2 usage error.
"""
import hashlib
import json
import os
import random
import shutil
import sqlite3
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import source_lineage as sl

LEGACY = sl.LEGACY_FINGERPRINT

# Columns the migration reads from existing tables. If any are missing the
# schema is not what this migration expects -> fail-closed.
REQUIRED_COLUMNS = {
    "nodes": ["protocol", "host", "port", "source", "first_seen", "last_seen"],
    "node_tests": ["protocol", "host", "port"],
    "phone_failures": ["protocol", "host", "port"],
}

BACKFILL_VARIANT = """
INSERT OR IGNORE INTO node_variants
  (protocol, host, port, fingerprint, first_seen, last_seen, verified)
SELECT protocol, host, port, ?, NULL, NULL, 0 FROM nodes
"""
BACKFILL_SOURCE = """
INSERT OR IGNORE INTO node_sources
  (protocol, host, port, fingerprint, source, first_seen, last_seen,
   sighting_count, verified, last_evidence)
SELECT protocol, host, port, ?, source, NULL, NULL, 0, 0, NULL
FROM nodes WHERE source IS NOT NULL AND source != ''
"""


def table_exists(conn, name):
    return conn.execute(
        "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?",
        (name,)).fetchone() is not None


def columns(conn, table):
    return [r[1] for r in conn.execute(f"PRAGMA table_info({table})")]


def liveness_sample(conn):
    """Same liveness query shape used by the production tester checks."""
    rows = conn.execute(
        "SELECT protocol, host, port, ms FROM node_tests "
        "WHERE result='pass' ORDER BY protocol, host, port, tested_at DESC "
        "LIMIT 50").fetchall()
    return [list(r) for r in rows]


def snapshot_state(conn):
    return {
        "nodes": conn.execute("SELECT COUNT(*) FROM nodes").fetchone()[0],
        "node_tests": conn.execute("SELECT COUNT(*) FROM node_tests").fetchone()[0],
        "phone_failures": conn.execute("SELECT COUNT(*) FROM phone_failures").fetchone()[0],
        "liveness": liveness_sample(conn),
        "integrity_ok": conn.execute("PRAGMA integrity_check").fetchone()[0] == "ok",
    }


def check_existing_schema(conn):
    """Fail-closed pre-checks on the live DB. Returns a list of problems."""
    problems = []
    for table, cols in REQUIRED_COLUMNS.items():
        if not table_exists(conn, table):
            problems.append(f"missing table {table}")
            continue
        have = columns(conn, table)
        for c in cols:
            if c not in have:
                problems.append(f"table {table} missing column {c}")
    if sl.has_v2_table(conn):
        problems.append(
            "node_sources already exists with the v2 layout (no fingerprint);"
            " manual review required, refusing to migrate over it")
    # A v3 table with wrong columns is also a hard stop.
    for table, cols in sl.EXPECTED_TABLES.items():
        if table_exists(conn, table) and columns(conn, table) != cols:
            problems.append(f"table {table} exists with unexpected columns")
    return problems


def verify_inside_txn(conn, before, nodes_count, sourced_nodes):
    """All checks run INSIDE the migration transaction, before commit."""
    problems = []
    if not sl.schema_matches_v3(conn):
        problems.append("v3 lineage tables/columns mismatch")
    after = snapshot_state(conn)
    for key in ("nodes", "node_tests", "phone_failures"):
        if after[key] != before[key]:
            problems.append(f"{key} row count changed")
    if after["liveness"] != before["liveness"]:
        problems.append("liveness sample changed")
    if not after["integrity_ok"]:
        problems.append("integrity_check not ok")
    variants = conn.execute("SELECT COUNT(*) FROM node_variants").fetchone()[0]
    if variants != nodes_count:
        problems.append(f"legacy variants {variants} != nodes {nodes_count}")
    legacy_sources = conn.execute(
        "SELECT COUNT(*) FROM node_sources WHERE fingerprint=?", (LEGACY,)).fetchone()[0]
    if legacy_sources != sourced_nodes:
        problems.append(
            f"legacy source rows {legacy_sources} != sourced nodes {sourced_nodes}")
    verified = conn.execute(
        "SELECT COUNT(*) FROM node_sources WHERE verified=1").fetchone()[0]
    if verified != 0:
        problems.append(f"backfill created {verified} verified rows (must be 0)")
    timed = conn.execute(
        "SELECT COUNT(*) FROM node_sources WHERE fingerprint=? "
        "AND (first_seen IS NOT NULL OR last_seen IS NOT NULL)",
        (LEGACY,)).fetchone()[0]
    if timed != 0:
        problems.append(f"backfill gave {timed} legacy rows observation times")
    return problems


def make_backup(conn, db_path, backup_dir):
    """WAL-safe backup via the SQLite backup API, unique name, verified.
    Returns (backup_path, report_dict). Never overwrites an existing file."""
    os.makedirs(backup_dir, exist_ok=True)
    for _ in range(10):
        stamp = time.strftime("%Y%m%dT%H%M%SZ", time.gmtime())
        suffix = f"{random.randint(0, 999999):06d}"
        name = f"pool-lineage-backup-{stamp}-{suffix}.db"
        path = os.path.join(backup_dir, name)
        if not os.path.exists(path):
            break
    else:
        raise RuntimeError("could not allocate a unique backup name")
    with sqlite3.connect(path) as dest:
        conn.backup(dest)
    # Verify the backup: open read-only, integrity + row counts.
    ro = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
    try:
        live = snapshot_state(conn)
        back = snapshot_state(ro)
        ok = (back == live)
        problems = [] if ok else ["backup state differs from live DB"]
    finally:
        ro.close()
    return path, {"ok": ok, "problems": problems,
                  "nodes": live["nodes"],
                  "integrity_ok": live["integrity_ok"]}


def verified_lineage_keys(conn):
    """Key set of verified (non-legacy) lineage rows -- used to detect
    data that a rollback would destroy."""
    if not table_exists(conn, "node_sources"):
        return set()
    return set(conn.execute(
        "SELECT protocol, host, port, fingerprint, source FROM node_sources"
        " WHERE verified=1").fetchall())


def do_migrate(conn, db_path, backup_dir):
    problems = check_existing_schema(conn)
    if problems:
        return 1, {"ok": False, "action": "migrate", "problems": problems}
    if sl.schema_matches_v3(conn):
        # Already migrated: idempotent no-op (verify only, no writes).
        before = snapshot_state(conn)
        lineage_rows = conn.execute("SELECT COUNT(*) FROM node_sources").fetchone()[0]
        return 0, {"ok": True, "action": "migrate", "already_migrated": True,
                   "backfilled_rows": 0, "lineage_rows": lineage_rows,
                   "nodes": before["nodes"],
                   "integrity_ok": before["integrity_ok"]}
    before = snapshot_state(conn)
    backup_path, backup_rep = make_backup(conn, db_path, backup_dir)
    if not backup_rep["ok"]:
        return 1, {"ok": False, "action": "migrate", "backup_path": backup_path,
                   "problems": ["backup verification failed: " + "; ".join(backup_rep["problems"])]}
    nodes_count = before["nodes"]
    sourced_nodes = conn.execute(
        "SELECT COUNT(*) FROM nodes WHERE source IS NOT NULL AND source != ''"
    ).fetchone()[0]
    try:
        conn.execute("BEGIN IMMEDIATE")
        try:
            sl.ensure_schema(conn)
            cur = conn.execute(BACKFILL_VARIANT, (LEGACY,))
            variants_added = cur.rowcount
            cur = conn.execute(BACKFILL_SOURCE, (LEGACY,))
            sources_added = cur.rowcount
            problems = verify_inside_txn(conn, before, nodes_count, sourced_nodes)
            if problems:
                conn.execute("ROLLBACK")
                return 1, {"ok": False, "action": "migrate",
                           "backup_path": backup_path,
                           "problems": problems,
                           "rolled_back": True}
            conn.execute("COMMIT")
        except Exception:
            try:
                conn.execute("ROLLBACK")
            except sqlite3.Error:
                pass
            raise
    except Exception as e:  # noqa: BLE001 - report, do not crash with a traceback
        return 1, {"ok": False, "action": "migrate",
                   "backup_path": backup_path,
                   "problems": [f"migration error: {e}", "transaction rolled back"]}
    after = snapshot_state(conn)
    lineage_rows = conn.execute("SELECT COUNT(*) FROM node_sources").fetchone()[0]
    return 0, {"ok": True, "action": "migrate",
               "backup_path": backup_path,
               "backfilled_rows": sources_added,
               "variants_added": variants_added,
               "lineage_rows": lineage_rows,
               "nodes": nodes_count,
               "integrity_ok": after["integrity_ok"],
               "rows_unchanged": all(after[k] == before[k]
                                     for k in ("nodes", "node_tests", "phone_failures")),
               "liveness_unchanged": after["liveness"] == before["liveness"],
               "problems": []}


def do_check(db_path):
    """Read-only dry-run: open mode=ro, report what would change, write nothing."""
    if not os.path.exists(db_path):
        return 2, {"ok": False, "dry_run": True, "problems": ["db file not found"]}
    conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
    try:
        problems = check_existing_schema(conn)
        already = sl.schema_matches_v3(conn)
        nodes = conn.execute("SELECT COUNT(*) FROM nodes").fetchone()[0]
        return 0, {"ok": len(problems) == 0, "dry_run": True,
                   "table_exists": already,
                   "nodes": nodes,
                   "would_backfill_rows": 0 if already else nodes,
                   "would_create_tables": [] if already else sorted(sl.EXPECTED_TABLES),
                   "problems": problems}
    finally:
        conn.close()


def do_rollback(db_path, backup_path, allow_data_loss):
    if not backup_path:
        return 2, {"ok": False, "action": "rollback",
                   "problems": ["--rollback requires --backup <file>; refusing unprotected DROP TABLE"]}
    if not os.path.exists(backup_path):
        return 2, {"ok": False, "action": "rollback",
                   "problems": [f"backup file not found: {backup_path}"]}
    # Verify the backup first (read-only).
    bro = sqlite3.connect(f"file:{backup_path}?mode=ro", uri=True)
    try:
        backup_state = snapshot_state(bro)
        backup_keys = verified_lineage_keys(bro)
    finally:
        bro.close()
    if not backup_state["integrity_ok"]:
        return 1, {"ok": False, "action": "rollback",
                   "problems": ["backup integrity_check not ok"]}
    conn = sqlite3.connect(db_path)
    try:
        live_keys = verified_lineage_keys(conn)
        lost = live_keys - backup_keys
        if lost and not allow_data_loss:
            return 1, {"ok": False, "action": "rollback",
                       "backup_path": backup_path,
                       "problems": [
                           f"rollback would destroy {len(lost)} verified lineage rows "
                           "recorded after the backup; pass --allow-data-loss to proceed"],
                       "would_lose_verified_rows": len(lost)}
        # Restore the whole DB from the backup (backup API, source -> live).
        src = sqlite3.connect(backup_path)
        try:
            src.backup(conn)
        finally:
            src.close()
        after = snapshot_state(conn)
        ok = (after == backup_state)
        return (0 if ok else 1), {
            "ok": ok, "action": "rollback", "backup_path": backup_path,
            "restored_nodes": after["nodes"],
            "integrity_ok": after["integrity_ok"],
            "node_sources_exists": table_exists(conn, "node_sources"),
            "problems": [] if ok else ["restored state differs from backup"]}
    finally:
        conn.close()


def main(argv):
    if len(argv) < 2 or argv[1].startswith("--"):
        print("usage: migrate_node_sources.py <db_path> [--backup-dir DIR]"
              " [--check] [--rollback --backup FILE [--allow-data-loss]]",
              file=sys.stderr)
        return 2
    db_path = argv[1]
    check = "--check" in argv
    rollback = "--rollback" in argv
    allow_data_loss = "--allow-data-loss" in argv
    backup_dir = None
    backup_path = None
    i = 2
    while i < len(argv):
        if argv[i] == "--backup-dir" and i + 1 < len(argv):
            backup_dir = argv[i + 1]
            i += 2
        elif argv[i] == "--backup" and i + 1 < len(argv):
            backup_path = argv[i + 1]
            i += 2
        else:
            i += 1
    if check and rollback:
        print("usage: --check and --rollback are mutually exclusive", file=sys.stderr)
        return 2
    if check:
        rc, rep = do_check(db_path)
        print(json.dumps(rep))
        return rc
    if rollback:
        rc, rep = do_rollback(db_path, backup_path, allow_data_loss)
        print(json.dumps(rep))
        return rc
    if backup_dir is None:
        backup_dir = os.path.join(os.path.dirname(os.path.abspath(db_path)),
                                  "lineage-backups")
    conn = sqlite3.connect(db_path)
    try:
        rc, rep = do_migrate(conn, db_path, backup_dir)
    finally:
        conn.close()
    print(json.dumps(rep))
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv))
