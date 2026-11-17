#!/usr/bin/env python3
"""WAL-safe backup tests (GPT #6940445042 P0-4).

The probe service runs with PRAGMA journal_mode=WAL. A plain `cp` of
the live probe.db file can miss commits still sitting in probe.db-wal
that have not been checkpointed. tools/backup_db.py must therefore
produce a consistent snapshot via the SQLite backup API, including
un-checkpointed WAL content, and verify it with integrity_check.

The test proves BOTH halves: the backup API snapshot contains rows
that were never checkpointed, AND a naive file copy of probe.db alone
(without its -wal) misses those same rows.
"""
import os
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
BACKUP_TOOL = os.path.join(ROOT, "tools", "backup_db.py")


class TestWalBackup(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="dual-backup-")
        self.src_path = os.path.join(self.tmp, "probe.db")

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def _make_wal_db_with_uncheckpointed_rows(self, n=25):
        """Create a WAL-mode DB, write n rows, commit, and keep the
        source connection OPEN so the -wal is never checkpointed.
        Returns the open connection. Callers must close it."""
        conn = sqlite3.connect(self.src_path, timeout=30)
        conn.execute("PRAGMA journal_mode=WAL")
        conn.execute("CREATE TABLE t(id INTEGER PRIMARY KEY, v TEXT)")
        for i in range(n):
            conn.execute("INSERT INTO t(v) VALUES(?)", (f"row-{i}",))
        conn.commit()
        wal_path = self.src_path + "-wal"
        self.assertTrue(os.path.isfile(wal_path),
                        "no -wal file: test setup did not use WAL")
        self.assertGreater(os.path.getsize(wal_path), 0,
                           "-wal is empty: rows were already checkpointed")
        return conn

    def test_backup_captures_uncheckpointed_wal_rows(self):
        n = 25
        src = self._make_wal_db_with_uncheckpointed_rows(n)
        try:
            dst_path = os.path.join(self.tmp, "probe.db.bak")
            r = subprocess.run(
                [sys.executable, BACKUP_TOOL, self.src_path, dst_path],
                capture_output=True, text=True, timeout=30)
            self.assertEqual(r.returncode, 0, r.stderr)
            self.assertIn("integrity_check=ok", r.stdout)
            dst = sqlite3.connect(dst_path, timeout=30)
            try:
                got = dst.execute("SELECT COUNT(*) FROM t").fetchone()[0]
                row = dst.execute("PRAGMA integrity_check").fetchone()
            finally:
                dst.close()
            self.assertEqual(got, n,
                             "backup snapshot missed un-checkpointed rows")
            self.assertEqual(row[0], "ok")
            # Contrast: a naive `cp` of probe.db alone (no -wal) MISSES
            # the un-checkpointed rows. This is the P0-4 bug.
            naive_path = os.path.join(self.tmp, "probe.db.naive")
            shutil.copyfile(self.src_path, naive_path)
            naive = sqlite3.connect(naive_path, timeout=30)
            try:
                try:
                    naive_n = naive.execute(
                        "SELECT COUNT(*) FROM t").fetchone()[0]
                except sqlite3.OperationalError:
                    # The CREATE TABLE itself never checkpointed either:
                    # the naive copy does not even have the table.
                    naive_n = 0
            finally:
                naive.close()
            self.assertLess(naive_n, n,
                            "naive cp saw all rows: the WAL fault was not "
                            "reproduced, test is vacuous")
        finally:
            src.close()

    def test_backup_missing_source_fails(self):
        dst_path = os.path.join(self.tmp, "probe.db.bak")
        r = subprocess.run(
            [sys.executable, BACKUP_TOOL,
             os.path.join(self.tmp, "no-such.db"), dst_path],
            capture_output=True, text=True, timeout=30)
        self.assertNotEqual(r.returncode, 0)
        self.assertFalse(os.path.exists(dst_path))

    def test_backup_of_clean_db(self):
        # A DB with no -wal present backs up exactly too.
        conn = sqlite3.connect(self.src_path, timeout=30)
        conn.execute("PRAGMA journal_mode=WAL")
        conn.execute("CREATE TABLE t(id INTEGER PRIMARY KEY, v TEXT)")
        conn.execute("INSERT INTO t(v) VALUES('x')")
        conn.commit()
        conn.execute("PRAGMA wal_checkpoint(TRUNCATE)")
        conn.close()
        dst_path = os.path.join(self.tmp, "probe.db.bak")
        r = subprocess.run(
            [sys.executable, BACKUP_TOOL, self.src_path, dst_path],
            capture_output=True, text=True, timeout=30)
        self.assertEqual(r.returncode, 0, r.stderr)
        dst = sqlite3.connect(dst_path, timeout=30)
        try:
            self.assertEqual(
                dst.execute("SELECT COUNT(*) FROM t").fetchone()[0], 1)
            self.assertEqual(
                dst.execute("PRAGMA integrity_check").fetchone()[0], "ok")
        finally:
            dst.close()


if __name__ == "__main__":
    unittest.main(verbosity=2)
