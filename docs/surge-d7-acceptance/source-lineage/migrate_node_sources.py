#!/usr/bin/env python3
"""Migrate: add source-lineage tables (GPT decision 3, Reviews 6031702642
and 6032131494). v4 closes the three rollback/contract gaps GPT found in
v3 (Review 6032131494, COMMENTED, 2026-11-24 09:13).

 - Rollback must not lose data. v3 compared only verified_lineage_keys,
   so new events on EXISTING keys, status-log changes and later
   node_tests/phone_failures writes never triggered protection, yet the
   whole DB was overwritten from the backup; and --allow-data-loss let
   the operator destroy data anyway. v4:
   * Normal rollback only DISABLES the new module / scraper calls and
     KEEPS the extra tables and history (backward compatible, no
     whole-DB overwrite). The CLI verifies the backup and the live
     state, refuses the whole-DB restore when any post-backup write is
     detected, modifies nothing, and reports exactly what changed so
     the operator can disable the module calls.
   * Whole-DB restore applies ONLY to a migration window with ZERO
     post-backup writes, proven by FULL content digests of
     nodes/node_tests/phone_failures (live vs backup) plus a lineage
     state check (backfill-only: no verified rows, no events, no status
     logs). Any unexpected change is refused. Writers must be stopped:
     the rollback probes for an active write lock first.
   * There is NO --allow-data-loss switch anymore. Passing it (or any
     unknown --argument) is a usage error (exit 2). Data loss cannot be
     opted into from this CLI.
 - do_check returned 0 even with problems: v4 returns 1 whenever
   problems are non-empty (and includes integrity_check in the report).
 - The already-migrated branch returned ok=true/0 even when
   integrity_ok was false: v4 returns ok/integrity as actually
   measured, with a non-zero exit on failure. Both are fail-closed.
 - Verify still happens INSIDE the transaction, BEFORE commit; a
   verification failure rolls the whole migration back (no partial
   tables). --check still uses a READ-ONLY connection (SQLite URI
   mode=ro) and writes nothing. Backups are still taken first (SQLite
   backup API), stored under a unique timestamped name that is never
   overwritten, and VERIFIED before any write. Fail-closed on schema
   mismatch. Historical triplets are NEVER fingerprinted: the backfill
   creates one 'legacy' variant + one legacy source row per node
   (verified=0, NO observation times).

Usage:
  python3 migrate_node_sources.py <db_path> [--backup-dir DIR]
  python3 migrate_node_sources.py <db_path> --check
  python3 migrate_node_sources.py <db_path> --rollback --backup FILE
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

# Pre-existing tables whose full content is digested for rollback safety.
PRE_EXISTING_TABLES = ("nodes", "node_tests", "phone_failures")

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


def table_count(conn, table):
    return conn.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]


def table_digest(conn, table):
    """SHA-256 over the FULL ordered content of a table (all columns).
    Same code, same process, same digest for identical content; any
    inserted / updated / deleted row changes it. Used to prove that no
    writer touched a pre-existing table since the backup."""
    cols = columns(conn, table)
    h = hashlib.sha256()
    h.update(f"{table}({','.join(cols)})".encode("utf-8"))
    cur = conn.execute(
        f"SELECT * FROM {table} ORDER BY {', '.join(cols)}")
    for row in cur:
        h.update(repr(row).encode("utf-8"))
    return h.hexdigest()


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
    # A v3/v4 table with wrong columns is also a hard stop.
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


def lineage_summary(conn):
    """Lineage state: whether the tables exist, what they hold, and
    whether they contain ONLY the migration backfill (legacy rows, no
    verified rows, no events, no status logs). Any verified row, event
    or status entry proves post-backup lineage activity."""
    if not table_exists(conn, "node_sources"):
        return {"has_tables": False, "verified_rows": 0, "legacy_rows": 0,
                "events": 0, "status_logs": 0, "variants": 0,
                "verified_variants": 0, "backfill_only": True}
    verified = conn.execute(
        "SELECT COUNT(*) FROM node_sources WHERE verified=1").fetchone()[0]
    legacy = conn.execute(
        "SELECT COUNT(*) FROM node_sources WHERE fingerprint=?", (LEGACY,)).fetchone()[0]
    variants = conn.execute("SELECT COUNT(*) FROM node_variants").fetchone()[0]
    verified_variants = conn.execute(
        "SELECT COUNT(*) FROM node_variants WHERE verified=1").fetchone()[0]
    events = (conn.execute("SELECT COUNT(*) FROM sighting_events").fetchone()[0]
              if table_exists(conn, "sighting_events") else 0)
    logs = (conn.execute("SELECT COUNT(*) FROM source_status_log").fetchone()[0]
            if table_exists(conn, "source_status_log") else 0)
    return {"has_tables": True, "verified_rows": verified,
            "legacy_rows": legacy, "events": events, "status_logs": logs,
            "variants": variants, "verified_variants": verified_variants,
            "backfill_only": (verified == 0 and verified_variants == 0
                              and events == 0 and logs == 0)}


def post_backup_changes(live_conn, backup_conn):
    """Every detected post-backup change, as human-readable strings.
    Empty means: pre-existing tables are byte-identical to the backup
    AND lineage holds only the migration backfill -- the migration
    window, with zero writes since the backup. Anything listed here
    makes a whole-DB restore unsafe."""
    changes = []
    for table in PRE_EXISTING_TABLES:
        if not table_exists(backup_conn, table):
            changes.append(f"backup is missing table {table}")
            continue
        if not table_exists(live_conn, table):
            changes.append(f"live DB is missing table {table}")
            continue
        if table_digest(live_conn, table) != table_digest(backup_conn, table):
            changes.append(
                f"table {table} differs from backup "
                f"({table_count(live_conn, table)} live rows vs "
                f"{table_count(backup_conn, table)} backup rows)")
    summ = lineage_summary(live_conn)
    if summ["has_tables"]:
        if summ["verified_rows"]:
            changes.append(
                f"{summ['verified_rows']} verified lineage rows recorded after the backup")
        if summ["verified_variants"]:
            changes.append(
                f"{summ['verified_variants']} verified variants recorded after the backup")
        if summ["events"]:
            changes.append(
                f"{summ['events']} sighting events recorded after the backup")
        if summ["status_logs"]:
            changes.append(
                f"{summ['status_logs']} source status log entries recorded after the backup")
    return changes


def check_no_active_writer(db_path):
    """Probe for an active writer: try to take a RESERVED lock. Returns
    False when the DB is locked (a writer is mid-transaction) or the
    file cannot be opened. Readers do not block this probe."""
    try:
        probe = sqlite3.connect(db_path, timeout=2)
        try:
            probe.execute("BEGIN IMMEDIATE")
            probe.execute("ROLLBACK")
            return True
        except sqlite3.OperationalError:
            return False
        finally:
            probe.close()
    except sqlite3.Error:
        return False


def do_migrate(conn, db_path, backup_dir):
    problems = check_existing_schema(conn)
    if problems:
        return 1, {"ok": False, "action": "migrate", "problems": problems}
    if sl.schema_matches_v3(conn):
        # Already migrated: verify only, no writes. The result follows
        # the ACTUAL conclusion: a failed integrity check is a failure.
        before = snapshot_state(conn)
        lineage_rows = conn.execute("SELECT COUNT(*) FROM node_sources").fetchone()[0]
        ok = bool(before["integrity_ok"])
        return (0 if ok else 1), {
            "ok": ok, "action": "migrate", "already_migrated": True,
            "backfilled_rows": 0, "lineage_rows": lineage_rows,
            "nodes": before["nodes"],
            "integrity_ok": before["integrity_ok"],
            "problems": [] if ok else ["integrity_check not ok on already-migrated DB"]}
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
    """Read-only dry-run: open mode=ro, report what would change, write
    nothing. The exit code follows the ACTUAL conclusion: any problem
    (including a failed integrity check) is a failure (exit 1)."""
    if not os.path.exists(db_path):
        return 2, {"ok": False, "dry_run": True, "problems": ["db file not found"]}
    conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
    try:
        problems = check_existing_schema(conn)
        already = sl.schema_matches_v3(conn)
        nodes = (conn.execute("SELECT COUNT(*) FROM nodes").fetchone()[0]
                 if table_exists(conn, "nodes") else None)
        try:
            integrity_ok = conn.execute("PRAGMA integrity_check").fetchone()[0] == "ok"
        except sqlite3.Error:
            integrity_ok = False
        if not integrity_ok:
            problems.append("integrity_check not ok")
        ok = len(problems) == 0
        return (0 if ok else 1), {"ok": ok, "dry_run": True,
                   "table_exists": already,
                   "nodes": nodes,
                   "integrity_ok": integrity_ok,
                   "would_backfill_rows": 0 if already else nodes,
                   "would_create_tables": [] if already else sorted(sl.EXPECTED_TABLES),
                   "problems": problems}
    finally:
        conn.close()


def do_rollback(db_path, backup_path):
    """Safe rollback. There is NO --allow-data-loss switch: data loss
    cannot be opted into from this CLI.

    Two outcomes, both lossless:
    - mode "restored": full digests prove ZERO post-backup writes
      anywhere (pre-existing tables byte-identical to the backup AND
      lineage holds only the migration backfill). The whole DB is
      restored from the backup and verified. This is the migration-
      window case; writers must be stopped first (probed below).
    - mode "retained": ANY post-backup write is detected (new test
      records, new sighting events on existing keys, status changes,
      ...). Whole-DB restore is REFUSED and NOTHING is modified: the
      lineage tables and all history are kept (backward compatible)
      and the operator must disable the new module / scraper calls to
      complete the rollback. The report lists every detected change.
    - mode "nothing_to_rollback": no lineage tables exist and the live
      DB already matches the backup.
    """
    if not backup_path:
        return 2, {"ok": False, "action": "rollback",
                   "problems": ["--rollback requires --backup <file>; refusing unprotected DROP TABLE"]}
    if not os.path.exists(backup_path):
        return 2, {"ok": False, "action": "rollback",
                   "problems": [f"backup file not found: {backup_path}"]}
    # Verify the backup first (read-only): integrity + pre-migration identity.
    bro = sqlite3.connect(f"file:{backup_path}?mode=ro", uri=True)
    try:
        backup_state = snapshot_state(bro)
        backup_has_lineage = table_exists(bro, "node_sources")
    finally:
        bro.close()
    if not backup_state["integrity_ok"]:
        return 1, {"ok": False, "action": "rollback",
                   "problems": ["backup integrity_check not ok"]}
    if backup_has_lineage:
        return 1, {"ok": False, "action": "rollback",
                   "problems": ["backup already contains lineage tables; "
                                "it is not a pre-migration backup"]}
    # Writers must be stopped: probe for an active write lock.
    if not check_no_active_writer(db_path):
        return 1, {"ok": False, "action": "rollback",
                   "problems": ["database is locked; stop all writers (scraper/tester) first"]}
    conn = sqlite3.connect(db_path)
    try:
        bro = sqlite3.connect(f"file:{backup_path}?mode=ro", uri=True)
        try:
            changes = post_backup_changes(conn, bro)
        finally:
            bro.close()
        if changes:
            summ = lineage_summary(conn)
            return 0, {"ok": True, "action": "rollback", "mode": "retained",
                       "backup_path": backup_path,
                       "whole_db_restore": "refused",
                       "post_backup_changes": changes,
                       "lineage_retained": summ["has_tables"],
                       "problems": [],
                       "note": "whole-DB restore refused: post-backup writes detected; "
                               "lineage tables and history kept -- disable the new module / "
                               "scraper calls to complete the rollback"}
        summ = lineage_summary(conn)
        if not summ["has_tables"]:
            return 0, {"ok": True, "action": "rollback",
                       "mode": "nothing_to_rollback",
                       "backup_path": backup_path,
                       "whole_db_restore": "not_needed",
                       "problems": [],
                       "note": "no lineage tables present; live DB already matches the backup"}
        # Zero post-backup writes: restore the whole DB from the backup.
        src = sqlite3.connect(backup_path)
        try:
            src.backup(conn)
        finally:
            src.close()
        after = snapshot_state(conn)
        ok = (after == backup_state)
        return (0 if ok else 1), {
            "ok": ok, "action": "rollback", "mode": "restored",
            "backup_path": backup_path,
            "whole_db_restore": "done" if ok else "failed",
            "restored_nodes": after["nodes"],
            "integrity_ok": after["integrity_ok"],
            "node_sources_exists": table_exists(conn, "node_sources"),
            "problems": [] if ok else ["restored state differs from backup"]}
    finally:
        conn.close()


def main(argv):
    if len(argv) < 2 or argv[1].startswith("--"):
        print("usage: migrate_node_sources.py <db_path> [--backup-dir DIR]"
              " [--check] [--rollback --backup FILE]",
              file=sys.stderr)
        return 2
    db_path = argv[1]
    check = "--check" in argv
    rollback = "--rollback" in argv
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
        elif argv[i] in ("--check", "--rollback"):
            i += 1
        else:
            # Unknown argument (including the removed --allow-data-loss):
            # fail loudly instead of silently ignoring it.
            print(f"usage: unknown argument {argv[i]!r}", file=sys.stderr)
            return 2
    if check and rollback:
        print("usage: --check and --rollback are mutually exclusive", file=sys.stderr)
        return 2
    if check:
        rc, rep = do_check(db_path)
        print(json.dumps(rep))
        return rc
    if rollback:
        rc, rep = do_rollback(db_path, backup_path)
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
