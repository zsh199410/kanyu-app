import contextlib
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import sqlite3
import tempfile
import unittest
from unittest import mock

import import_per_observation_v2 as importer
import receiver

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location(
    "prod_cycle_under_test", HERE.parent / "single-writer" / "production_cycle.py")
cycle = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(cycle)


class TestPerObservationImport(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        self.stage = root / "staging.sqlite"
        self.prod = root / "production.sqlite"
        self.pool = root / "pool.txt"
        pins = [
            (f"PIN{i}", "ss", f"192.0.2.{i}", 10000+i)
            for i in range(1, 22)
        ]
        other = [
            (f"NODE{i}", "trojan", f"198.51.100.{i}", 11000+i)
            for i in range(1, 26)
        ]
        lines = [
            f"{name} = {proto}, {host}, {port}, password=dummy"
            for name,proto,host,port in pins + other
        ]
        self.pool.write_text("\n".join(lines)+"\n", encoding="utf-8")
        self.sha = hashlib.sha256(self.pool.read_bytes()).hexdigest()
        self.now = 1763719200
        receiver.initialize_db(self.stage)
        with sqlite3.connect(self.prod) as c:
            c.executescript("""
                CREATE TABLE pinned (protocol TEXT,host TEXT,port INTEGER,name TEXT);
                CREATE TABLE blocklist (protocol TEXT,host TEXT,port INTEGER);
                CREATE TABLE phone_failures (protocol TEXT,host TEXT,port INTEGER,
                      reported_at INTEGER,source TEXT,detail TEXT);
            """)
            c.executemany("INSERT INTO pinned VALUES (?,?,?,?)",
                          [(proto,host,port,name) for name,proto,host,port in pins])
        self.first = other[0][1:]
        self.second = other[1][1:]
        self.pin = pins[0][1:]

    def tearDown(self):
        self.tmp.cleanup()

    def put(self, name, key, nonce="a"*32, ts=None, *,
            status="failure", trusted=1, mode="external_policy_id", sha=None):
        ts = self.now if ts is None else ts
        with sqlite3.connect(self.stage) as c:
            c.execute("INSERT OR IGNORE INTO batches VALUES (?,?,?)", (nonce,ts,sha or self.sha))
            c.execute("""INSERT INTO phone_observations
               (nonce,protocol,host,port,status,probe_mode,trusted,
                received_at,bearer,pool_sha,reason)
               VALUES (?,?,?,?,?,?,?,?,?,?,?)""",
               (nonce,*key,status,mode,trusted,ts,"cellular",sha or self.sha,
                "dual_transport_failure"))

    def execute(self, apply=True, approved=True):
        return importer.import_once(
            str(self.stage), str(self.prod), str(self.pool),
            now=self.now+10, apply=apply, approved=approved)

    def failures(self):
        with sqlite3.connect(self.prod) as c:
            return c.execute("SELECT protocol,host,port FROM phone_failures").fetchall()

    def test_two_failures_same_nonce_both_imported(self):
        self.put("n1",self.first)
        self.put("n2",self.second)
        res=self.execute()
        self.assertEqual(res["new"],2)
        self.assertCountEqual(self.failures(),[self.first,self.second])
        with sqlite3.connect(self.prod) as c:
            self.assertEqual(c.execute("SELECT count(*) FROM phone_import_item_v2").fetchone()[0],2)

    def test_old_importer_first_row_reconciled_later_row_not_lost(self):
        self.put("n1",self.first)
        self.put("n2",self.second)
        with sqlite3.connect(self.prod) as c:
            c.execute("""INSERT INTO phone_failures VALUES (?,?,?,?,?,?)""",
                      (*self.first,self.now,"surge-url-test","old-import"))
        res=self.execute()
        self.assertEqual(res["reconciled_old"],1)
        self.assertEqual(res["new"],1)
        self.assertEqual(len(self.failures()),2)

    def test_per_item_idempotent_after_restart(self):
        self.put("n1",self.first)
        self.put("n2",self.second)
        self.assertEqual(self.execute()["new"],2)
        self.assertEqual(self.execute()["new"],0)
        self.assertEqual(self.execute()["already_processed"],2)
        self.assertEqual(len(self.failures()),2)

    def test_pin_and_unknown_and_untrusted_never_imported(self):
        self.put("pin",self.pin)
        self.put("unknown",self.first,status="unknown")
        self.put("untrusted",self.second,trusted=0)
        result=self.execute()
        self.assertEqual(result["skipped"]["pinned"],1)
        self.assertEqual(result["skipped"]["untrusted"],1)
        self.assertEqual(self.failures(),[])

    def test_old_pool_generation_skipped(self):
        self.put("n1",self.first,sha="0"*64)
        result=self.execute()
        self.assertEqual(result["skipped"]["stale"],1)
        self.assertEqual(self.failures(),[])

    def test_default_dry_run_no_mutation(self):
        self.put("n1",self.first)
        self.assertEqual(self.execute(apply=False)["eligible_staging_rows"],1)
        with sqlite3.connect(self.prod) as c:
            self.assertEqual(c.execute("SELECT count(*) FROM phone_failures").fetchone()[0],0)
            self.assertIsNone(c.execute(
                "SELECT name FROM sqlite_master WHERE name='phone_import_item_v2'").fetchone())

    def test_apply_requires_explicit_authorization(self):
        self.put("n1",self.first)
        with self.assertRaisesRegex(importer.ImportRefused,"approval"):
            self.execute(approved=False)
        self.assertEqual(self.failures(),[])


class TestUnknownReasons(unittest.TestCase):
    def setUp(self):
        self.now = 1763719200
        self.pool = (
            "".join(f"PIN{i} = ss, 192.0.2.{i}, {10000+i}, password=x\n"
                    for i in range(1,22)) +
            "NODE1 = trojan, 198.51.100.1, 11001, password=x\n"
        ).encode()
        self.sha = hashlib.sha256(self.pool).hexdigest()

    def packet(self, mode="external_policy_id", bearer="cellular", a="timeout", b="transport_error"):
        return dict(schema=1,group="免费节点池",timestamp=self.now,
                    nonce="b"*32,pool_sha=self.sha,bearer=bearer,
                    surge_version="6.0.0",observations=[{
                        "name":"NODE1","probe_mode":mode,"results":[
                            {"id":"a","state":a,"hint":"none"},
                            {"id":"b","state":b,"hint":"none"}]}])

    def test_dual_transport_failure_keeps_prior_admission(self):
        r=receiver.validate(self.packet(),self.pool,self.now)[0]
        self.assertEqual(r[3],"failure")
        self.assertEqual(r[6],"dual_transport_failure")

    def test_unknown_bearer_reason(self):
        r=receiver.validate(self.packet(bearer="unknown"),self.pool,self.now)[0]
        self.assertEqual(r[3],"unknown")
        self.assertEqual(r[6],"unknown_network_bearer")

    def test_untrusted_descriptor_reason(self):
        r=receiver.validate(self.packet(mode="temporary_policy_descriptor"),self.pool,self.now)[0]
        self.assertEqual((r[3],r[6]),("unknown","untrusted_policy_descriptor"))

    def test_http_status_reason(self):
        p=self.packet(b="unknown")
        p["observations"][0]["results"][1]["hint"]="http_status"
        r=receiver.validate(p,self.pool,self.now)[0]
        self.assertEqual((r[3],r[6]),("unknown","http_status_inconclusive"))

    def test_legacy_db_migrates_additively(self):
        with tempfile.TemporaryDirectory() as t:
            path=Path(t)/"old.sqlite"
            with sqlite3.connect(path) as c:
                c.executescript("""
                  CREATE TABLE batches(nonce TEXT PRIMARY KEY,received_at INTEGER,payload_sha TEXT);
                  CREATE TABLE phone_observations (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,nonce TEXT,protocol TEXT,
                    host TEXT,port INTEGER,status TEXT,probe_mode TEXT,trusted INTEGER,
                    received_at INTEGER,bearer TEXT,pool_sha TEXT);
                """)
            receiver.initialize_db(path)
            with sqlite3.connect(path) as c:
                fields={r[1] for r in c.execute("PRAGMA table_info(phone_observations)")}
                self.assertIn("reason",fields)


class TestSafePreflightDiagnostics(unittest.TestCase):
    def _run_failure(self, exception):
        buf=io.StringIO()
        with mock.patch.object(cycle, "run_cycle", side_effect=exception), contextlib.redirect_stdout(buf):
            code=cycle.main(["--publish"])
        return code,json.loads(buf.getvalue())

    def test_exact_internal_gate_code_observable(self):
        code,body=self._run_failure(cycle.CycleRefused("served_staging_differ"))
        self.assertEqual(code,78)
        self.assertEqual(body["gate_code"],"served_staging_differ")
        self.assertFalse(body["production_changed"])

    def test_sensitive_message_never_printed(self):
        code,body=self._run_failure(ValueError("secret_key=superprivate /opt/path"))
        self.assertEqual(code,78)
        self.assertEqual(body["gate_code"],"unclassified_preflight_exception")
        self.assertNotIn("superprivate",json.dumps(body))

    def test_readonly_db_gate_visible(self):
        code,body=self._run_failure(cycle._db.SourceRefused("missing_required_tables"))
        self.assertEqual(code,78)
        self.assertEqual(body["gate_code"],"missing_required_tables")


if __name__=="__main__":
    unittest.main()
