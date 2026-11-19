"""Read-only plan + isolated handover DB. No production write."""
from __future__ import annotations
import importlib.util
from pathlib import Path
import sqlite3
import tempfile
import unittest

F=Path(__file__).resolve().parent.parent/"single-writer"
sp=importlib.util.spec_from_file_location("surge_rotation_ledger",F/"rotation_ledger.py")
ledger=importlib.util.module_from_spec(sp)
sp.loader.exec_module(ledger)
NOW=1800000000
PINS=[("trojan",f"192.0.2.{i}",440+i) for i in range(1,22)]
EXTRAS=[("trojan",f"198.51.100.{i}",443) for i in range(1,25)]
BLOCKED=[("trojan",f"203.0.113.{i}",443) for i in range(1,5)]

def line(name,k):
    return f"{name} = trojan, {k[1]}, {k[2]}, password=test123"

def current():
    return ("\n".join(
        [line(f"美国{i}",k) for i,k in enumerate(PINS,start=1)] +
        [line(f"旧-{i}",k) for i,k in enumerate(EXTRAS,start=1)]
    )+"\n").encode()

def parse(s):
    parts=[t.strip() for t in s.split("=",1)[1].split(",")]
    return (parts[0],parts[1],int(parts[2]))

def snapshot():
    return {
        "db_pins":{
            **{k:f"美国{i}" for i,k in enumerate(PINS,start=1)},
            **{k:f"封禁{i}" for i,k in enumerate(BLOCKED,start=1)}
        },
        "blocked_keys":set(BLOCKED),
        "first_published":{
            k:NOW-2*86400 for k in EXTRAS
        }
    }

class RotationLedgerTests(unittest.TestCase):
    def plan(self,**kwargs):
        x=dict(current_pool=current(),db_snapshot=snapshot(),
               parse_fn=parse,now=NOW)
        x.update(kwargs)
        return ledger.handover_plan(**x)

    def test_actual_45_line_21_pin_24_rotation_bootstrap(self):
        p=self.plan()
        self.assertEqual(len(p["rows"]),24)
        self.assertEqual(p["meta"]["pin_count"],21)
        self.assertEqual(p["meta"]["legacy_history_count"],24)
        self.assertFalse(p["meta"]["deletion_allowed"])
        self.assertFalse(p["meta"]["winner_clean_eligible"])
        self.assertTrue(all(x["deletion_approved"]==0 for x in p["rows"]))
        # Even old rows that are >1 day old get a FULL new protection
        # epoch in the new ledger, not a simultaneous deletion wave.
        self.assertTrue(all(x["protection_since"]==NOW for x in p["rows"]))
        self.assertTrue(all(
            x["legacy_first_published"]==NOW-2*86400 for x in p["rows"]))
        summary=str(ledger.public_summary(p))
        self.assertNotIn("192.0.2",summary)
        self.assertNotIn("198.51.100",summary)

    def test_missing_legacy_history_is_grace_protected(self):
        snap=snapshot()
        del snap["first_published"][EXTRAS[0]]
        p=self.plan(db_snapshot=snap)
        self.assertEqual(p["meta"]["legacy_history_count"],23)
        self.assertEqual(sum(x["legacy_first_published"] is None for x in p["rows"]),1)
        self.assertTrue(all(x["deletion_approved"]==0 for x in p["rows"]))

    def test_blocklisted_db_pins_not_returned(self):
        p=self.plan()
        self.assertEqual(p["meta"]["pin_count"],21)
        self.assertEqual(len(p["rows"]),24)

    def test_blocklisted_current_member_refused(self):
        raw=current()+ (line("封禁",BLOCKED[0])+"\n").encode()
        with self.assertRaisesRegex(ledger.LedgerRefused,"duplicate_or_blocked_node"):
            self.plan(current_pool=raw)

    def test_missing_pin_refused(self):
        raw=current().replace((line("美国1",PINS[0])+"\n").encode(),b"")
        with self.assertRaisesRegex(ledger.LedgerRefused,"pinned_members_missing"):
            self.plan(current_pool=raw)

    def test_invalid_historical_future_timestamp_fails(self):
        snap=snapshot()
        snap["first_published"][EXTRAS[0]]=NOW+60
        with self.assertRaisesRegex(ledger.LedgerRefused,"invalid_legacy_first_published"):
            self.plan(db_snapshot=snap)

    def test_duplicate_key_refused(self):
        raw=current()+(line("别名",EXTRAS[0])+"\n").encode()
        with self.assertRaisesRegex(ledger.LedgerRefused,"duplicate_or_blocked_node"):
            self.plan(current_pool=raw)

    def test_bootstrap_requires_approval_and_does_not_create_file(self):
        with tempfile.TemporaryDirectory() as d:
            out=Path(d)/"writer.db"
            with self.assertRaisesRegex(ledger.LedgerRefused,"ledger_bootstrap_not_approved"):
                ledger.bootstrap_private_db(out,self.plan())
            self.assertFalse(out.exists())

    def test_bootstrap_only_new_writer_db_and_no_deletion(self):
        with tempfile.TemporaryDirectory() as d:
            out=Path(d)/"writer.db"
            p=self.plan()
            r=ledger.bootstrap_private_db(out,p,approved=True)
            self.assertEqual(r["decision"],"LEDGER_STAGED_AUTO_DELETE_OFF")
            c=sqlite3.connect(out)
            self.assertEqual(c.execute("SELECT COUNT(*) FROM rotation_ledger").fetchone()[0],24)
            self.assertEqual(c.execute("SELECT SUM(deletion_approved) FROM rotation_ledger").fetchone()[0],0)
            self.assertEqual(c.execute("SELECT COUNT(*) FROM rotation_ledger_meta").fetchone()[0],7)
            c.close()
            with self.assertRaisesRegex(ledger.LedgerRefused,"ledger_already_initialized"):
                ledger.bootstrap_private_db(out,p,approved=True)

    def test_legacy_db_path_forbidden(self):
        with tempfile.TemporaryDirectory() as d:
            with self.assertRaisesRegex(ledger.LedgerRefused,"legacy_db_path_forbidden"):
                ledger.bootstrap_private_db(Path(d)/"pool.db",self.plan(),approved=True)

if __name__=="__main__":
    unittest.main()
