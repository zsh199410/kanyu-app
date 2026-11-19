"""Read-only normalized DB adapter test against disclosed schema."""
from __future__ import annotations

import importlib.util
from pathlib import Path
import sqlite3
import tempfile
import unittest

FILE = Path(__file__).resolve().parent.parent / "single-writer" / "pool_db_source.py"
sp = importlib.util.spec_from_file_location("pool_db_source", FILE)
source = importlib.util.module_from_spec(sp)
sp.loader.exec_module(source)

K = ("trojan", "192.0.2.11", 443)
BK = ("trojan", "192.0.2.12", 443)


def make_db(d):
    p = Path(d) / "pool.db"
    c = sqlite3.connect(p)
    c.executescript("""
    CREATE TABLE nodes (protocol TEXT,host TEXT,port INTEGER,source TEXT,
      name_hint TEXT,first_seen INTEGER,last_seen INTEGER,last_test_at INTEGER,
      last_result TEXT,last_reason TEXT,pass_count INTEGER,test_count INTEGER,
      country TEXT,status TEXT,PRIMARY KEY(protocol,host,port));
    CREATE TABLE node_tests (protocol TEXT,host TEXT,port INTEGER,
      tested_at INTEGER,result TEXT,reason TEXT,ms REAL);
    CREATE TABLE pinned(protocol TEXT,host TEXT,port INTEGER,name TEXT,
      created INTEGER,"by" TEXT,PRIMARY KEY(protocol,host,port));
    CREATE TABLE blocklist(protocol TEXT,host TEXT,port INTEGER,reason TEXT,
      created INTEGER,"by" TEXT,PRIMARY KEY(protocol,host,port));
    CREATE TABLE config(key TEXT PRIMARY KEY,value TEXT);
    CREATE TABLE published_first(protocol TEXT,host TEXT,port INTEGER,
      first_published INTEGER,PRIMARY KEY(protocol,host,port));
    CREATE TABLE winner_reports(ts INTEGER,name TEXT);
    """)
    c.execute("INSERT INTO nodes (protocol,host,port,first_seen,last_test_at,"
              "last_result,pass_count,test_count) VALUES(?,?,?,?,?,?,?,?)",
              (*K, 10, 100, "pass", 8, 10))
    c.executemany("INSERT INTO node_tests VALUES (?,?,?,?,?,?,?)", [
        (*K, 80, "pass", "", 225), (*K, 90, "pass", "", 175),
        (*K, 95, "fail", "timeout", None)])
    c.execute("INSERT INTO pinned (protocol,host,port,name) VALUES(?,?,?,?)",
              (*K, "美国1"))
    c.execute("INSERT INTO blocklist (protocol,host,port) VALUES(?,?,?)", BK)
    c.execute("INSERT INTO config VALUES ('publish_max_lines','150')")
    c.execute("INSERT INTO published_first VALUES (?,?,?,?)", (*K, 12))
    c.execute("INSERT INTO winner_reports VALUES (100,'美国1')")
    c.commit()
    c.close()
    return p


class PoolDBSourceTests(unittest.TestCase):
    def test_read_real_schema_normalized_rows(self):
        with tempfile.TemporaryDirectory() as d:
            p = make_db(d)
            x = source.read_db_snapshot(p)
            self.assertEqual(x["latest_pass_ms"][K], 175)
            self.assertEqual(len(x["node_rows"]), 1)
            self.assertEqual(x["node_rows"][0]["last_result"], "pass")
            self.assertEqual(x["db_pins"][K], "美国1")
            self.assertIn(BK, x["blocked_keys"])
            self.assertEqual(x["config_raw"]["publish_max_lines"], "150")
            self.assertEqual(x["first_published"][K], 12)
            self.assertEqual(x["winner_reports"], [(100, "美国1")])
            self.assertTrue(x["db_read_only"])
            self.assertFalse(x["production_modified"])

    def test_absolute_file_is_byte_identical_after_query(self):
        with tempfile.TemporaryDirectory() as d:
            p = make_db(d)
            original = p.read_bytes()
            source.read_db_snapshot(p)
            self.assertEqual(p.read_bytes(), original)
            c = sqlite3.connect(p)
            self.assertEqual(c.execute("SELECT COUNT(*) FROM nodes").fetchone()[0], 1)
            c.close()

    def test_unknown_schema_fails_closed(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "pool.db"
            sqlite3.connect(p).close()
            with self.assertRaisesRegex(source.SourceRefused, "missing_required_tables"):
                source.read_db_snapshot(p)

    def test_relative_or_missing_db_refused(self):
        for path in ("relative.db", "/tmp/this_is_not_a_surge_db_20261119.db"):
            with self.assertRaisesRegex(source.SourceRefused, "invalid_or_missing_db"):
                source.read_db_snapshot(path)

    def test_no_latest_pass_available_is_not_fabricated(self):
        with tempfile.TemporaryDirectory() as d:
            p = make_db(d)
            c = sqlite3.connect(p)
            c.execute("DELETE FROM node_tests WHERE result='pass'")
            c.commit()
            c.close()
            x = source.read_db_snapshot(p)
            self.assertNotIn(K, x["latest_pass_ms"])

    def test_invalid_last_pass_number_fails_closed(self):
        with tempfile.TemporaryDirectory() as d:
            p = make_db(d)
            c = sqlite3.connect(p)
            c.execute("UPDATE node_tests SET ms=NULL WHERE tested_at=90")
            c.commit()
            c.close()
            with self.assertRaisesRegex(source.SourceRefused, "invalid_latest_pass_latency"):
                source.read_db_snapshot(p)


if __name__ == "__main__":
    unittest.main()
