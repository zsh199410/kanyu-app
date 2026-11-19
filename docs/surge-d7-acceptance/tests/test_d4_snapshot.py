"""D4 backup tool: never alters live sources and drills recovery only in temp."""
from __future__ import annotations
import importlib.util
from pathlib import Path
import json
import os
import sqlite3
import tempfile
import unittest

SRC=Path(__file__).resolve().parent.parent/"single-writer"/"d4_snapshot.py"
sp=importlib.util.spec_from_file_location("surge_d4_snapshot",SRC)
m=importlib.util.module_from_spec(sp)
sp.loader.exec_module(m)


def fixture(root):
    a=root/"served.txt"
    b=root/"staging.txt"
    data=("".join(
        f"美国{i} = trojan, 192.0.2.{i}, 443, password=FAKE_SECRET\n"
        for i in range(1,22))).encode()
    a.write_bytes(data)
    b.write_bytes(data)
    db=root/"pool.db"
    conn=sqlite3.connect(db)
    conn.execute("CREATE TABLE nodes(name TEXT, source TEXT)")
    conn.execute("INSERT INTO nodes VALUES (?,?)",
                 ("SECRET_NODE","trojan://FAKE_SECRET@198.51.100.42"))
    conn.commit()
    conn.close()
    backup=root/"backup-root"
    backup.mkdir(mode=0o700)
    return a,b,db,backup,data


def unit_reader():
    return {n:{"LoadState":"loaded","UnitFileState":"enabled",
               "ActiveState":"active"} for n in m.UNITS}


def cleanup(snapshot):
    # Test fixture cleanup; production captures are intentionally read-only.
    if snapshot.exists():
        snapshot.chmod(0o700)
        for p in snapshot.iterdir():
            p.chmod(0o600)


class D4SnapshotTests(unittest.TestCase):
    def test_check_does_not_modify_sources_or_emit_secret(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d);a,b,db,backup,raw=fixture(root)
            first=m.pool_state(a,b)
            self.assertEqual(first[0],raw)
            self.assertEqual(first[1]["line_count"],21)
            self.assertTrue(first[1]["served_staging_equal"])
            self.assertNotIn("FAKE_SECRET",str(first[1]))
            self.assertEqual((a.read_bytes(),b.read_bytes()),(raw,raw))
            self.assertEqual(list(backup.iterdir()),[])

    def test_distinct_sources_fail_closed(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d);a,b,db,backup,raw=fixture(root)
            b.write_bytes(raw+b"\n")
            with self.assertRaisesRegex(m.SnapshotRefused,"served_staging_not_identical"):
                m.pool_state(a,b)
            self.assertEqual(list(backup.iterdir()),[])

    def test_invalid_or_symlink_source_refused(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d);a,b,db,backup,raw=fixture(root)
            link=root/"link"
            link.symlink_to(a)
            with self.assertRaisesRegex(m.SnapshotRefused,"unsafe_source_path"):
                m.pool_state(link,b)

    def test_snapshot_is_private_and_recovery_is_isolated(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d);a,b,db,backup,raw=fixture(root)
            db_before=db.read_bytes()
            shot,facts=m.capture(served_path=a,staging_path=b,db_path=db,
                                  backup_root=backup,unit_reader=unit_reader)
            try:
                self.assertEqual(facts["sha256"],m._sha(raw))
                self.assertEqual(shot.stat().st_mode&0o777,0o500)
                self.assertEqual((shot/"served.bin").stat().st_mode&0o777,0o400)
                self.assertEqual((shot/"staging.bin").read_bytes(),raw)
                self.assertEqual(a.read_bytes(),raw)
                self.assertEqual(db.read_bytes(),db_before)
                manifest=json.loads((shot/"manifest.json").read_text())
                self.assertEqual(len(manifest["unit_states"]),7)
                self.assertFalse(manifest["production_mutated"])
                check=m.verify(shot)
                self.assertTrue(check["isolation_restore_drill"])
                self.assertTrue(check["db_backup_verified"])
                self.assertFalse(check["production_systemd_restored"])
            finally:
                cleanup(shot)

    def test_two_captures_do_not_overwrite(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d);a,b,db,backup,raw=fixture(root)
            x,_=m.capture(served_path=a,staging_path=b,db_path=db,
                           backup_root=backup,unit_reader=unit_reader)
            y,_=m.capture(served_path=a,staging_path=b,db_path=db,
                           backup_root=backup,unit_reader=unit_reader)
            try:
                self.assertNotEqual(x,y)
                self.assertTrue(x.exists() and y.exists())
            finally:
                cleanup(x);cleanup(y)

    def test_backup_root_requires_private_permissions(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d);a,b,db,backup,raw=fixture(root)
            backup.chmod(0o755)
            with self.assertRaisesRegex(m.SnapshotRefused,"backup_root_not_private"):
                m.capture(served_path=a,staging_path=b,db_path=db,
                          backup_root=backup,unit_reader=unit_reader)

    def test_restore_tamper_detected(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d);a,b,db,backup,raw=fixture(root)
            shot,_=m.capture(served_path=a,staging_path=b,db_path=db,
                             backup_root=backup,unit_reader=unit_reader)
            try:
                (shot/"served.bin").chmod(0o600)
                (shot/"served.bin").write_bytes(b"CORRUPTED")
                with self.assertRaisesRegex(m.SnapshotRefused,"pool_snapshot_sha_mismatch"):
                    m.verify(shot)
            finally:
                cleanup(shot)

    def test_duplicate_names_refused(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d);a,b,db,backup,raw=fixture(root)
            duplicated=raw+raw.splitlines(keepends=True)[0]
            a.write_bytes(duplicated);b.write_bytes(duplicated)
            with self.assertRaisesRegex(m.SnapshotRefused,"duplicate_proxy_names"):
                m.pool_state(a,b)

if __name__=="__main__":
    unittest.main()
