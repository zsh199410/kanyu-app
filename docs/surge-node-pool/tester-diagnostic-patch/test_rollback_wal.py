"""PR #124 WAL-safe rollback regression (standalone; no production DB access).

Run: python3 test_rollback_wal.py
Proves:
- Uncheckpointed WAL cannot replay a later schema/new row after restore.
- An active writer forces fail-closed without changing the target DB.
- A corrupt snapshot is rejected without changing the target DB.
- The original snapshot's entire schema and content match after restore.
"""
import json
import os
import sqlite3
import subprocess
import sys
import tempfile
from pathlib import Path

from migrate_diag_columns import rollback, _data_signature


def inspect(db_path):
    con = sqlite3.connect(str(db_path))
    try:
        return {
            "columns": len(con.execute("PRAGMA table_info(node_tests)").fetchall()),
            "rows": con.execute("SELECT * FROM node_tests ORDER BY rowid").fetchall(),
            "integrity": con.execute("PRAGMA integrity_check").fetchone()[0],
            "digest": _data_signature(con),
        }
    finally:
        con.close()


def run():
    with tempfile.TemporaryDirectory(prefix="surge-rollback-wal-") as td:
        db = Path(td) / "pool.db"
        snapshot = Path(td) / "before.db"
        live = sqlite3.connect(str(db))
        assert live.execute("PRAGMA journal_mode=WAL").fetchone()[0] == "wal"
        live.execute(
            "CREATE TABLE node_tests (protocol TEXT, host TEXT, port INTEGER, "
            "tested_at INTEGER, result TEXT, reason TEXT, ms REAL)")
        live.execute(
            "INSERT INTO node_tests VALUES (?,?,?,?,?,?,?)",
            ("vmess", "stable.example", 443, 1, "pass", "", 99.0))
        live.commit()
        snap_con = sqlite3.connect(str(snapshot))
        live.backup(snap_con)
        snap_con.close()
        before = inspect(snapshot)

        # New schema and new row are committed into WAL, with live connection
        # deliberately still open so no final-connection close checkpoints it.
        live.execute("ALTER TABLE node_tests ADD COLUMN curl_exit INTEGER")
        live.execute(
            "INSERT INTO node_tests VALUES (?,?,?,?,?,?,?,?)",
            ("vmess", "later.example", 443, 2, "fail", "curl-failed", 0.0, 97))
        live.commit()
        assert os.path.getsize(str(db) + "-wal") > 0
        assert inspect(db)["columns"] == 8
        assert len(inspect(db)["rows"]) == 2

        restored = rollback(str(db), str(snapshot))
        assert restored["ok"] is True, restored
        assert restored["content_match"] is True, restored
        assert inspect(db) == before, "stale WAL shadowed restored snapshot"

        # Even after the pre-existing idle connection closes, no old WAL is replayed.
        live.close()
        assert inspect(db) == before, "closing a prior connection changed restored DB"

        holder = sqlite3.connect(str(db))
        try:
            holder.execute("BEGIN IMMEDIATE")
            holder.execute("UPDATE node_tests SET ms=121.0")
            rejected = rollback(str(db), str(snapshot))
            assert rejected["ok"] is False, rejected
            assert "locked" in rejected["error"].lower(), rejected
            holder.rollback()
        finally:
            holder.close()
        assert inspect(db) == before, "failed busy rollback altered DB"

        corrupt = Path(td) / "invalid-snapshot.db"
        corrupt.write_bytes(b"not-a-sqlite-database")
        rejected = rollback(str(db), str(corrupt))
        assert rejected["ok"] is False, rejected
        assert inspect(db) == before, "corrupt snapshot altered DB"
        rejected = rollback(str(db), str(db))
        assert rejected["ok"] is False, rejected
        assert inspect(db) == before, "same-file rollback altered DB"

        # CLI contract: JSON ok=false MUST have nonzero exit status so deploy
        # automation cannot mistake failed recovery for a successful rollback.
        cli = os.path.join(os.path.dirname(__file__), "migrate_diag_columns.py")
        fail = subprocess.run(
            [sys.executable, cli, str(db), "--rollback", str(corrupt)],
            capture_output=True, text=True)
        fail_data = json.loads(fail.stdout)
        assert fail.returncode != 0, fail
        assert fail_data["ok"] is False, fail_data
        success = subprocess.run(
            [sys.executable, cli, str(db), "--rollback", str(snapshot)],
            capture_output=True, text=True)
        success_data = json.loads(success.stdout)
        assert success.returncode == 0, success
        assert success_data["ok"] is True, success_data
        assert inspect(db) == before

        print({
            "wal_replay_prevented": True,
            "full_content_matches_snapshot": True,
            "busy_writer_rejected": True,
            "corrupt_snapshot_rejected": True,
            "same_file_rejected": True,
            "rollback_cli_fail_exits_nonzero": True,
            "rollback_cli_success_exits_zero": True,
        })


if __name__ == "__main__":
    run()
