"""Production service preflight is read-only and refuses real publication."""
from __future__ import annotations

import importlib.util
from pathlib import Path
import sqlite3
import tempfile
import unittest

F = Path(__file__).resolve().parent.parent / "single-writer"
spec = importlib.util.spec_from_file_location("surge_production_cycle", F / "production_cycle.py")
prod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(prod)


def make_env(tmp):
    db = Path(tmp) / "pool.db"
    c = sqlite3.connect(db)
    c.executescript("""
    CREATE TABLE nodes(protocol TEXT,host TEXT,port INTEGER,
      pass_count INTEGER,test_count INTEGER,first_seen INTEGER,
      last_test_at INTEGER,last_result TEXT);
    CREATE TABLE node_tests(protocol TEXT,host TEXT,port INTEGER,
      tested_at INTEGER,result TEXT,ms REAL);
    CREATE TABLE pinned(protocol TEXT,host TEXT,port INTEGER,name TEXT);
    CREATE TABLE blocklist(protocol TEXT,host TEXT,port INTEGER);
    """)
    for i in range(1, 22):
        c.execute("INSERT INTO pinned VALUES(?,?,?,?)",
                  ("trojan", f"192.0.2.{i}", 443, f"美国{i}"))
    for i in range(22, 26):
        c.execute("INSERT INTO pinned VALUES(?,?,?,?)",
                  ("trojan", f"192.0.2.{i}", 443, f"香港{i}"))
        c.execute("INSERT INTO blocklist VALUES(?,?,?)",
                  ("trojan", f"192.0.2.{i}", 443))
    c.commit()
    c.close()
    content = "".join(
        f"美国{i} = trojan, 192.0.2.{i}, 443, password=test123\n"
        for i in range(1, 22)
    ).encode()
    served = Path(tmp) / "served.txt"
    staging = Path(tmp) / "staging.txt"
    served.write_bytes(content)
    staging.write_bytes(content)
    return db, served, staging


class ProductionCycleTests(unittest.TestCase):
    def test_preflight_accepts_21_canonical_not_25_db_pins(self):
        with tempfile.TemporaryDirectory() as d:
            db, served, staging = make_env(d)
            before = (db.read_bytes(), served.read_bytes(), staging.read_bytes())
            x = prod.inspect_live(db, served, staging)
            self.assertEqual(x["canonical_pin_count"], 21)
            self.assertEqual(x["candidate_count"], 21)
            self.assertTrue(x["served_staging_sha_equal"])
            self.assertEqual(x["decision"],
                             "CUTOVER_BLOCKED_GENERATOR_ADAPTER_NOT_READY")
            self.assertFalse(x["source_adapter_verified"])
            self.assertFalse(x["production_changed"])
            self.assertEqual(before,
                             (db.read_bytes(), served.read_bytes(), staging.read_bytes()))

    def test_preflight_rejects_divergent_staging(self):
        with tempfile.TemporaryDirectory() as d:
            db, served, staging = make_env(d)
            staging.write_bytes(staging.read_bytes() + b"\n")
            with self.assertRaisesRegex(ValueError, "served_staging_differ"):
                prod.inspect_live(db, served, staging)

    def test_preflight_rejects_missing_pin(self):
        with tempfile.TemporaryDirectory() as d:
            db, served, staging = make_env(d)
            bad = served.read_bytes().replace(b"\xe7\xbe\x8e\xe5\x9b\xbd1 =",
                                              b"\xe5\x88\xa0\xe9\x99\xa41 =")
            served.write_bytes(bad)
            staging.write_bytes(bad)
            with self.assertRaisesRegex(ValueError, "pinned_names_not_in_served"):
                prod.inspect_live(db, served, staging)

    def test_preflight_rejects_symlink_to_served(self):
        with tempfile.TemporaryDirectory() as d:
            db, served, staging = make_env(d)
            link = Path(d) / "link"
            link.symlink_to(served)
            with self.assertRaisesRegex(ValueError, "invalid_file_or_symlink"):
                prod.inspect_live(db, link, staging)

    def test_systemd_template_disables_unapproved_release(self):
        service = (F / "systemd" / "p2p3-single-publish.service").read_text()
        timer = (F / "systemd" / "p2p3-single-publish.timer").read_text()
        self.assertIn("ConditionPathExists=/etc/p2p3-single-writer/release-ready",
                      service)
        self.assertIn("single_writer.py check", service)
        self.assertIn("production_cycle.py", service)
        self.assertIn("OnCalendar=*-*-* *:55:00", timer)
        self.assertIn("Persistent=false", timer)
        self.assertIn("Restart=no", service)
        self.assertNotIn("pool.cli publish", service)
        self.assertNotIn("pool-sync.sh", service)


if __name__ == "__main__":
    unittest.main()
