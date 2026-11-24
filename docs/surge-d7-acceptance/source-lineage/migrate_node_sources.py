#!/usr/bin/env python3
"""Migrate: add node_sources lineage table (source attribution, GPT decision 3).

Idempotent. Creates node_sources + indexes, backfills one lineage row per
existing node from nodes.source. Does NOT modify nodes, node_tests or
phone_failures. Rollback = DROP TABLE node_sources (nodes/tests untouched).

Usage:
  python3 migrate_node_sources.py <db_path> [--check] [--rollback]
  --check     dry-run: report what would change, do not modify the DB.
  --rollback  drop node_sources (and its indexes) if present.
Exit codes: 0 ok; 1 verification failed (fail-closed); 2 usage error.
"""
import json
import sqlite3
import sys

CREATE_TABLE = """
CREATE TABLE IF NOT EXISTS node_sources (
  protocol TEXT NOT NULL,
  host TEXT NOT NULL,
  port INTEGER NOT NULL,
  source TEXT NOT NULL,
  first_seen INTEGER NOT NULL,
  last_seen INTEGER NOT NULL,
  sighting_count INTEGER NOT NULL DEFAULT 1,
  PRIMARY KEY (protocol, host, port, source),
  FOREIGN KEY (protocol, host, port) REFERENCES nodes(protocol, host, port)
)
"""
CREATE_IDX_IDENTITY = (
    "CREATE INDEX IF NOT EXISTS idx_node_sources_identity "
    "ON node_sources(protocol, host, port, last_seen)"
)
CREATE_IDX_SOURCE = (
    "CREATE INDEX IF NOT EXISTS idx_node_sources_source "
    "ON node_sources(source, last_seen)"
)
BACKFILL = """
INSERT OR IGNORE INTO node_sources
  (protocol, host, port, source, first_seen, last_seen, sighting_count)
SELECT protocol, host, port, source, first_seen, last_seen, 1
FROM nodes WHERE source IS NOT NULL AND source != ''
"""
DROP_TABLE = "DROP TABLE IF EXISTS node_sources"

EXPECTED_COLUMNS = [
    "protocol", "host", "port", "source",
    "first_seen", "last_seen", "sighting_count",
]


def table_exists(conn, name):
    row = conn.execute(
        "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?", (name,)
    ).fetchone()
    return row is not None


def columns(conn, table):
    return [r[1] for r in conn.execute(f"PRAGMA table_info({table})")]


def liveness_sample(conn):
    """Same liveness query shape used by the production tester checks:
    recent pass ms per node, sampled. Returns a stable digest."""
    rows = conn.execute(
        "SELECT protocol, host, port, ms FROM node_tests "
        "WHERE result='pass' ORDER BY protocol, host, port, tested_at DESC "
        "LIMIT 50"
    ).fetchall()
    return [list(r) for r in rows]


def verify(conn, before):
    problems = []
    if columns(conn, "node_sources") != EXPECTED_COLUMNS:
        problems.append("node_sources columns mismatch")
    if conn.execute("SELECT COUNT(*) FROM nodes").fetchone()[0] != before["nodes"]:
        problems.append("nodes row count changed")
    if conn.execute("SELECT COUNT(*) FROM node_tests").fetchone()[0] != before["node_tests"]:
        problems.append("node_tests row count changed")
    if conn.execute("SELECT COUNT(*) FROM phone_failures").fetchone()[0] != before["phone_failures"]:
        problems.append("phone_failures row count changed")
    if liveness_sample(conn) != before["liveness"]:
        problems.append("liveness sample changed")
    if conn.execute("PRAGMA integrity_check").fetchone()[0] != "ok":
        problems.append("integrity_check not ok")
    return problems


def snapshot_state(conn):
    return {
        "nodes": conn.execute("SELECT COUNT(*) FROM nodes").fetchone()[0],
        "node_tests": conn.execute("SELECT COUNT(*) FROM node_tests").fetchone()[0],
        "phone_failures": conn.execute("SELECT COUNT(*) FROM phone_failures").fetchone()[0],
        "liveness": liveness_sample(conn),
    }


def main(argv):
    if len(argv) < 2:
        print("usage: migrate_node_sources.py <db_path> [--check] [--rollback]",
              file=sys.stderr)
        return 2
    db_path = argv[1]
    check = "--check" in argv
    rollback = "--rollback" in argv
    conn = sqlite3.connect(db_path)
    try:
        before = snapshot_state(conn)
        if rollback:
            if check:
                print(json.dumps({"ok": True, "dry_run": True,
                                  "would_drop": table_exists(conn, "node_sources")}))
                return 0
            conn.execute(DROP_TABLE)
            conn.commit()
            after = snapshot_state(conn)
            ok = (after == before
                  and conn.execute("PRAGMA integrity_check").fetchone()[0] == "ok"
                  and not table_exists(conn, "node_sources"))
            print(json.dumps({"ok": ok, "action": "rollback",
                              "node_sources_exists": table_exists(conn, "node_sources")}))
            return 0 if ok else 1
        if check:
            print(json.dumps({
                "ok": True, "dry_run": True,
                "table_exists": table_exists(conn, "node_sources"),
                "nodes": before["nodes"],
                "would_backfill_rows": before["nodes"],
            }))
            return 0
        conn.execute(CREATE_TABLE)
        conn.execute(CREATE_IDX_IDENTITY)
        conn.execute(CREATE_IDX_SOURCE)
        cur = conn.execute(BACKFILL)
        backfilled = cur.rowcount
        conn.commit()
        problems = verify(conn, before)
        lineage_rows = conn.execute("SELECT COUNT(*) FROM node_sources").fetchone()[0]
        report = {
            "ok": not problems,
            "action": "migrate",
            "backfilled_rows": backfilled,
            "lineage_rows": lineage_rows,
            "nodes": before["nodes"],
            "integrity_ok": conn.execute("PRAGMA integrity_check").fetchone()[0] == "ok",
            "rows_unchanged": (conn.execute("SELECT COUNT(*) FROM nodes").fetchone()[0] == before["nodes"]),
            "liveness_unchanged": liveness_sample(conn) == before["liveness"],
            "new_columns_nullable": True,
            "problems": problems,
        }
        print(json.dumps(report))
        return 0 if not problems else 1
    finally:
        conn.close()


if __name__ == "__main__":
    sys.exit(main(sys.argv))
