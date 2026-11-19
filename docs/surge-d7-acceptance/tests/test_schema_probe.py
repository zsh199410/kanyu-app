"""Read-only SQLite schema probe fixtures — secret values must not print."""
from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import sqlite3
import tempfile
import unittest

PATH = (Path(__file__).resolve().parent.parent /
        "single-writer" / "schema_probe.py")
spec = importlib.util.spec_from_file_location("surge_schema_probe", PATH)
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)


class SchemaProbeTests(unittest.TestCase):
    def create_db(self, folder):
        path = Path(folder) / "pool.db"
        conn = sqlite3.connect(path)
        conn.execute("CREATE TABLE nodes (name TEXT, proxy_uri TEXT, pinned INTEGER)")
        conn.execute("INSERT INTO nodes VALUES (?, ?, ?)",
                     ("SECRET-NODE", "trojan://very-secret@192.0.2.9", 1))
        conn.execute("CREATE TABLE node_tests (id INTEGER, latency_ms INTEGER)")
        conn.execute("INSERT INTO node_tests VALUES (?,?)", (1, 123))
        conn.execute("CREATE TABLE unrelated_secrets (password TEXT)")
        conn.execute("INSERT INTO unrelated_secrets VALUES (?)", ("DO_NOT_PRINT",))
        conn.commit()
        conn.close()
        return path

    def test_only_known_schema_no_live_node_rows(self):
        with tempfile.TemporaryDirectory() as d:
            db = self.create_db(d)
            result = probe.inspect_schema(db)
            output = json.dumps(result)
            self.assertEqual(result["data_rows_read"], 0)
            self.assertTrue(result["read_only"])
            self.assertEqual(result["table_count_total"], 3)
            self.assertEqual({t["table"] for t in result["known_tables"]},
                             {"nodes", "node_tests"})
            for secret in ("SECRET-NODE", "very-secret", "DO_NOT_PRINT",
                           "unrelated_secrets", str(db)):
                self.assertNotIn(secret, output)

    def test_db_is_not_modified(self):
        with tempfile.TemporaryDirectory() as d:
            db = self.create_db(d)
            before = db.read_bytes()
            probe.inspect_schema(db)
            self.assertEqual(db.read_bytes(), before)
            conn = sqlite3.connect(db)
            self.assertEqual(conn.execute(
                "SELECT COUNT(*) FROM nodes").fetchone()[0], 1)
            conn.close()

    def test_missing_or_relative_path_fails(self):
        for v in ("does-not-exist.db", Path("/tmp/no-such-private-surge.db")):
            with self.assertRaisesRegex(ValueError, "db_not_found_or_relative"):
                probe.inspect_schema(v)

    def test_non_schema_values_are_not_emitted(self):
        with tempfile.TemporaryDirectory() as d:
            db = self.create_db(d)
            output = probe.inspect_schema(db)
            self.assertFalse(output["production_modified"])
            self.assertIn("proxy_uri", {
                col["name"] for table in output["known_tables"]
                if table["table"] == "nodes" for col in table["columns"]
            })


if __name__ == "__main__":
    unittest.main()
