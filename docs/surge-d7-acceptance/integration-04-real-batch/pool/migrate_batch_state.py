#!/usr/bin/env python3
"""Migrate: add crawl-batch tables (integration-04, Review 6034205305
points 2 and 3).

Creates crawl_batches + crawl_batch_members (see batch_state.py).
Follows the migrate_node_sources.py v4 contract:

 - The migration runs in a maintenance window, NOT from cmd_crawl:
   cmd_crawl never creates tables on the fly. If the schema is absent,
   the batch layer is unavailable (BatchUnavailable) and consumers
   BLOCK; the crawl itself still runs.
 - Verify happens INSIDE the transaction, BEFORE commit; a verification
   failure rolls the whole migration back (no partial tables).
 - --check uses a READ-ONLY connection (SQLite URI mode=ro) and writes
   nothing; it returns 1 whenever problems are non-empty.
 - Backups are taken first (SQLite backup API), stored under a unique
   timestamped name that is never overwritten, and VERIFIED before any
   write. No whole-DB restore path, no --allow-data-loss switch:
   passing it (or any unknown --argument) is a usage error (exit 2).
 - Historical data is never touched: nodes / node_tests /
   phone_failures / node_sources are only read for the pre-flight
   digest, never modified. No backfill: a batch only exists for a crawl
   that actually ran with this code; old sightings never become batch
   members retroactively.

Usage:
  python3 migrate_batch_state.py <db_path> [--backup-dir DIR]
  python3 migrate_batch_state.py <db_path> --check
  python3 migrate_batch_state.py <db_path> --dry-run
Exit codes: 0 ok; 1 verification failed / refused (fail-closed); 2 usage error.
"""
import argparse
import hashlib
import os
import sqlite3
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import batch_state as bs


def table_columns(conn, table):
    return [r[1] for r in conn.execute("PRAGMA table_info(%s)" % table)]


def table_digest(conn, table):
    h = hashlib.sha256()
    for row in conn.execute("SELECT * FROM %s ORDER BY rowid" % table):
        h.update(repr(row).encode("utf-8"))
    return h.hexdigest()


def sqlite_backup(src_path, dst_path):
    """Copy a live SQLite DB with the backup API (WAL-safe). The
    destination must not exist; the result is verified with
    integrity_check before the caller proceeds."""
    if os.path.exists(dst_path):
        raise ValueError("backup destination already exists: %s" % dst_path)
    src = sqlite3.connect("file:%s?mode=ro" % src_path, uri=True)
    try:
        dst = sqlite3.connect(dst_path)
        try:
            src.backup(dst)
        finally:
            dst.close()
    finally:
        src.close()
    chk = sqlite3.connect("file:%s?mode=ro" % dst_path, uri=True)
    try:
        row = chk.execute("PRAGMA integrity_check").fetchone()
        if row is None or row[0] != "ok":
            raise ValueError("backup integrity_check failed: %r" % (row,))
        for table in ("nodes", "node_tests", "phone_failures"):
            n_src = sqlite3.connect(
                "file:%s?mode=ro" % src_path, uri=True).execute(
                "SELECT COUNT(*) FROM %s" % table).fetchone()[0]
            n_dst = chk.execute(
                "SELECT COUNT(*) FROM %s" % table).fetchone()[0]
            if n_src != n_dst:
                raise ValueError(
                    "backup row count mismatch on %s: %d != %d"
                    % (table, n_src, n_dst))
    finally:
        chk.close()
    os.chmod(dst_path, 0o600)


def do_check(db_path):
    """Read-only verification. Returns (ok, problems list)."""
    problems = []
    if not os.path.isfile(db_path):
        return False, ["db file missing: %s" % db_path]
    conn = sqlite3.connect("file:%s?mode=ro" % db_path, uri=True)
    try:
        conn.execute("PRAGMA query_only=ON")
        row = conn.execute("PRAGMA integrity_check").fetchone()
        if row is None or row[0] != "ok":
            problems.append("integrity_check failed: %r" % (row,))
        if bs.batch_schema_ready(conn):
            return (not problems), problems
        for table, cols in bs.EXPECTED_BATCH_TABLES.items():
            have = conn.execute(
                "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?",
                (table,)).fetchone()
            if have is None:
                problems.append("missing table: %s" % table)
            elif table_columns(conn, table) != cols:
                problems.append("schema mismatch: %s" % table)
        return (not problems), problems
    finally:
        conn.close()


def main(argv=None):
    p = argparse.ArgumentParser(description="Add crawl-batch tables.")
    p.add_argument("db_path")
    p.add_argument("--backup-dir", default=None)
    p.add_argument("--check", action="store_true")
    p.add_argument("--dry-run", action="store_true")
    args = p.parse_args(argv)
    if args.check and args.dry_run:
        p.error("--check and --dry-run are mutually exclusive")
    if args.check:
        ok, problems = do_check(args.db_path)
        print("check: %s" % ("ok" if ok else "FAILED"))
        for prob in problems:
            print("  problem: %s" % prob)
        return 0 if ok else 1
    if args.dry_run:
        print("--dry-run: the migration would execute:")
        print(bs.BATCH_SCHEMA.strip())
        print("--dry-run: no writes performed.")
        return 0
    if not os.path.isfile(args.db_path):
        print("FAIL-CLOSED: db file missing: %s" % args.db_path,
              file=sys.stderr)
        return 1
    backup_dir = args.backup_dir or os.path.join(
        os.path.dirname(os.path.abspath(args.db_path)), "backups")
    os.makedirs(backup_dir, exist_ok=True)
    stamp = time.strftime("%Y%m%dT%H%M%SZ", time.gmtime())
    backup_path = os.path.join(
        backup_dir, "batch-state-%s.sqlite3" % stamp)
    # The stamp has 1-second resolution: two migrations in the same
    # second (a re-run, or two DBs in one directory) would collide.
    # Never overwrite an existing backup; append a counter suffix
    # instead (-1, -2, ...). Refusing a legitimate re-run is not the
    # intent of the already-exists guard.
    suffix = 0
    while os.path.exists(backup_path):
        suffix += 1
        backup_path = os.path.join(
            backup_dir, "batch-state-%s-%d.sqlite3" % (stamp, suffix))
    # Pre-flight digest of the tables this migration must not touch.
    pre = {}
    ro = sqlite3.connect("file:%s?mode=ro" % args.db_path, uri=True)
    try:
        for table in ("nodes", "node_tests", "phone_failures"):
            pre[table] = table_digest(ro, table)
    finally:
        ro.close()
    try:
        sqlite_backup(args.db_path, backup_path)
    except (ValueError, sqlite3.Error, OSError) as e:
        print("FAIL-CLOSED: backup failed: %s" % e, file=sys.stderr)
        return 1
    print("backup written and verified: %s" % backup_path)
    conn = sqlite3.connect(args.db_path, timeout=30)
    try:
        conn.execute("BEGIN IMMEDIATE")
        conn.executescript(bs.BATCH_SCHEMA)
        # Verify INSIDE the transaction, BEFORE commit.
        if not bs.batch_schema_ready(conn):
            raise ValueError("post-migration schema check failed")
        for table, digest in pre.items():
            if table_digest(conn, table) != digest:
                raise ValueError(
                    "pre-existing table %s changed during migration" % table)
        conn.commit()
    except (ValueError, sqlite3.Error) as e:
        conn.rollback()
        print("FAIL-CLOSED: migration rolled back: %s" % e, file=sys.stderr)
        return 1
    finally:
        conn.close()
    ok, problems = do_check(args.db_path)
    print("migration: %s" % ("ok" if ok else "FAILED"))
    for prob in problems:
        print("  problem: %s" % prob)
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
