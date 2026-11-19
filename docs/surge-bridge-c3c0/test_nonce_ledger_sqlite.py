"""Real SQLite adversarial regression (no production DB, network, or token)."""
import hashlib
import os
import sqlite3
import subprocess
import sys
import tempfile
import threading
import unittest
from concurrent.futures import ThreadPoolExecutor
from contextlib import closing
from pathlib import Path

from nonce_ledger_sqlite import NonceLedger, NonceLedgerError, InvalidChallenge, new_nonce

ISSUED = 1800000000000
EXPIRES = ISSUED + 60000
FP = hashlib.sha256(b"synthetic-candidate").hexdigest()
OTHER = hashlib.sha256(b"wrong-candidate").hexdigest()
TOKEN_ID = "synthetic-id"


class NonceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.db = Path(self.temp.name) / "nonce.sqlite"
        self.ledger = NonceLedger(self.db)
        self.nonce = new_nonce()
        self.binding = dict(kind="dev", candidate_fingerprint=FP, token_id=TOKEN_ID)

    def tearDown(self):
        self.temp.cleanup()

    def reg(self, nonce=None, **overrides):
        return self.ledger.register(self.nonce if nonce is None else nonce,
            **(self.binding | overrides), issued_ms=ISSUED, expires_ms=EXPIRES)

    def use(self, nonce=None, now=ISSUED, **overrides):
        return self.ledger.consume(self.nonce if nonce is None else nonce,
            **(self.binding | overrides), now_ms=now)

    def test_first_issue_and_one_consumption(self):
        self.assertTrue(self.reg())
        self.assertTrue(self.use())
        self.assertEqual(self.ledger.counts(), (1, 1))

    def test_consumed_nonce_is_never_reusable(self):
        self.reg()
        self.assertTrue(self.use())
        self.assertFalse(self.use())
        self.assertFalse(self.reg())

    def test_duplicate_registration_before_consumption(self):
        self.assertTrue(self.reg())
        self.assertFalse(self.reg())
        self.assertEqual(self.ledger.counts(), (1, 0))

    def test_unissued_nonce_is_rejected(self):
        self.assertFalse(self.use())
        self.assertEqual(self.ledger.counts(), (0, 0))

    def test_wrong_fingerprint_preserves_nonce(self):
        self.reg()
        self.assertFalse(self.use(candidate_fingerprint=OTHER))
        self.assertTrue(self.use())

    def test_wrong_kind_and_id_preserve_nonce(self):
        self.reg()
        self.assertFalse(self.use(kind="localkey"))
        self.assertFalse(self.use(token_id="wrong-id"))
        self.assertTrue(self.use())

    def test_expiration_boundary_is_exclusive(self):
        self.reg()
        self.assertFalse(self.use(now=EXPIRES))
        self.assertTrue(self.use(now=EXPIRES - 1))

    def test_issued_in_future_cannot_be_consumed(self):
        self.reg()
        self.assertFalse(self.use(now=ISSUED - 1))
        self.assertTrue(self.use(now=ISSUED))

    def test_restart_preserves_consumed_tombstone(self):
        self.reg()
        self.use()
        again = NonceLedger(self.db)
        self.assertFalse(again.consume(self.nonce, **self.binding, now_ms=ISSUED))
        self.assertFalse(again.register(self.nonce, **self.binding,
                                        issued_ms=ISSUED, expires_ms=EXPIRES))

    def test_new_process_cannot_replay_nonce(self):
        self.reg()
        self.use()
        code = """import sys
from nonce_ledger_sqlite import NonceLedger
db, nonce, fp, token = sys.argv[1:]
assert NonceLedger(db).consume(nonce,kind="dev",candidate_fingerprint=fp,
    token_id=token,now_ms=1800000000000) is False
print("REPLAY_REJECTED")"""
        p = subprocess.run([sys.executable, "-c", code, str(self.db),
                           self.nonce, FP, TOKEN_ID], check=True,
                           capture_output=True, text=True,
                           cwd=Path(__file__).resolve().parent)
        self.assertEqual(p.stdout.strip(), "REPLAY_REJECTED")

    def test_two_simultaneous_consumers_only_one_wins(self):
        self.reg()
        barrier = threading.Barrier(2)
        def consume(_):
            actor = NonceLedger(self.db)
            barrier.wait(timeout=10)
            return actor.consume(self.nonce, **self.binding, now_ms=ISSUED)
        with ThreadPoolExecutor(max_workers=2) as pool:
            self.assertEqual(sorted(pool.map(consume, (0, 1))), [False, True])
        self.assertEqual(self.ledger.counts(), (1, 1))

    def test_two_simultaneous_registrations_only_one_wins(self):
        barrier = threading.Barrier(2)
        def issue(_):
            actor = NonceLedger(self.db)
            barrier.wait(timeout=10)
            return actor.register(self.nonce, **self.binding,
                                  issued_ms=ISSUED, expires_ms=EXPIRES)
        with ThreadPoolExecutor(max_workers=2) as pool:
            self.assertEqual(sorted(pool.map(issue, (0, 1))), [False, True])
        self.assertEqual(self.ledger.counts(), (1, 0))

    def test_simulated_database_write_failure_fails_closed(self):
        self.reg()
        with closing(sqlite3.connect(self.db)) as con:
            con.executescript("""CREATE TRIGGER fail_write BEFORE UPDATE ON challenge
                BEGIN SELECT RAISE(ABORT, 'synthetic-fault'); END;""")
        with self.assertRaisesRegex(NonceLedgerError, "commit_state_unknown"):
            self.use()
        self.assertEqual(self.ledger.counts(), (1, 0))
        with closing(sqlite3.connect(self.db)) as con:
            con.execute("DROP TRIGGER fail_write")
            con.commit()
        self.assertTrue(self.use())

    def test_corrupt_database_and_missing_directory_fail_closed(self):
        with self.assertRaises(ValueError):
            NonceLedger(Path(self.temp.name) / "missing" / "db")
        bad = Path(self.temp.name) / "bad.sqlite"
        bad.write_bytes(b"NOT SQLITE")
        with self.assertRaises(NonceLedgerError):
            NonceLedger(bad)

    def test_schema_version_drift_fails_closed(self):
        with closing(sqlite3.connect(self.db)) as con:
            con.execute("PRAGMA user_version=777")
        with self.assertRaises(NonceLedgerError):
            NonceLedger(self.db)

    def test_full_ledger_fails_closed_without_purging_tombstones(self):
        actor = NonceLedger(self.db, max_records=1)
        self.assertTrue(actor.register(self.nonce, **self.binding,
                                       issued_ms=ISSUED, expires_ms=EXPIRES))
        with self.assertRaisesRegex(NonceLedgerError, "ledger_full"):
            actor.register(new_nonce(), **self.binding,
                           issued_ms=ISSUED, expires_ms=EXPIRES)
        self.assertTrue(actor.consume(self.nonce, **self.binding, now_ms=ISSUED))

    def test_malformed_noncanonical_nonce_rejected(self):
        for nonce in ("", "x", "x" * 42, "!" * 43, "x" * 44, "A" * 42 + "B"):
            with self.subTest(length=len(nonce)):
                with self.assertRaises(InvalidChallenge):
                    self.reg(nonce)

    def test_malformed_binding_rejected(self):
        for bad in ({"kind":"invalid"}, {"candidate_fingerprint":"1234"},
                    {"token_id":"../../path"}):
            with self.subTest(bad=bad):
                with self.assertRaises(InvalidChallenge):
                    self.reg(**bad)

    def test_invalid_lifetime_rejected(self):
        for expiry in (ISSUED, ISSUED + 90000000):
            with self.assertRaises(InvalidChallenge):
                self.ledger.register(self.nonce, **self.binding,
                                     issued_ms=ISSUED, expires_ms=expiry)

    def test_world_readable_directory_and_symlink_rejected(self):
        unsafe = Path(self.temp.name) / "unsafe"
        unsafe.mkdir()
        os.chmod(unsafe, 0o755)
        with self.assertRaises(ValueError):
            NonceLedger(unsafe / "db.sqlite")
        link = Path(self.temp.name) / "link.sqlite"
        link.symlink_to(self.db)
        with self.assertRaises(ValueError):
            NonceLedger(link)

    def test_database_stores_only_digest_not_nonce_or_token_value(self):
        self.reg()
        with closing(sqlite3.connect(self.db)) as con:
            nonce_digest, fingerprint, token = con.execute(
                "SELECT nonce_sha256,candidate_fp,token_id FROM challenge").fetchone()
        self.assertEqual(len(nonce_digest), 32)
        self.assertEqual(fingerprint, FP)
        self.assertEqual(token, TOKEN_ID)
        self.assertNotIn(self.nonce, self.db.read_bytes().decode("latin1"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
