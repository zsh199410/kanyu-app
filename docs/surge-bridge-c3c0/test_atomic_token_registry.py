"""Issue73 single-file token registry + nonce proof issuance adversarial tests.

Real SQLite transactions, ephemeral test keys, synthetic tokens only.
"""
import base64
import hashlib
import json
import sqlite3
import tempfile
import threading
import unittest
from concurrent.futures import ThreadPoolExecutor
from contextlib import closing
from pathlib import Path

from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

from nonce_ledger_sqlite import NonceLedger, new_nonce
from token_registry_sqlite import (
    TokenRegistry, TokenRegistryError, OLD_MAX_MS, fingerprint
)
from atomic_signed_proof_issuer import AtomicSignedProofIssuer
from signed_proof_issuer import ProofIssuanceError

NOW = 1800000000000
OLD = "TEST-SYNTHETIC-EXPOSED-OLD-0123456789ABCDE"
NEW = "TEST-SYNTHETIC-ROTATED-NEW-0123456789ABCDE"
BACKUP = "TEST-SYNTHETIC-STANDBY-BACKUP-0123456789ABCDEF"
OLD_ID = "OLD-001"
NEW_ID = "NEW-002"
BACKUP_ID = "BACKUP-003"
SESSION = "synthetic-owner-session"


class RegistryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.db = Path(self.temp.name) / "registry.sqlite"
        self.ledger = NonceLedger(self.db)
        self.registry = TokenRegistry(self.ledger)
        self.registry.add(OLD, token_id=OLD_ID, kind="dev",
                          role="exposed_old", issued_ms=NOW,
                          expires_ms=NOW+OLD_MAX_MS)
        self.registry.add(NEW, token_id=NEW_ID, kind="dev",
                          role="new", issued_ms=NOW, expires_ms=NOW+86400000)
        self.registry.add(BACKUP, token_id=BACKUP_ID, kind="dev",
                          role="backup", issued_ms=NOW,
                          expires_ms=NOW+86400000)
        self.signer = Ed25519PrivateKey.generate()
        self.nonce = new_nonce()
        self.ledger.register(self.nonce, kind="dev",
                             candidate_fingerprint=fingerprint(NEW),
                             token_id=NEW_ID, issued_ms=NOW,
                             expires_ms=NOW+60000)
        self.issuer = AtomicSignedProofIssuer(
            self.registry, self.signer,
            lambda session, tid, kind:
                session == SESSION and tid in (NEW_ID, BACKUP_ID) and kind == "dev",
            now_ms=lambda: NOW)

    def tearDown(self):
        self.temp.cleanup()

    def issue(self, **kw):
        return self.issuer.issue(**({
            "session": SESSION, "nonce": self.nonce, "token_id": NEW_ID,
            "kind": "dev", "candidate_fingerprint": fingerprint(NEW),
            "exposed_old_token_id": OLD_ID,
        } | kw))

    def test_01_initial_dual_token_and_standby_behavior(self):
        self.assertEqual(self.registry.authorize(OLD,kind="dev",now_ms=NOW)["status"],200)
        self.assertEqual(self.registry.authorize(NEW,kind="dev",now_ms=NOW)["status"],200)
        self.assertEqual(self.registry.authorize(BACKUP,kind="dev",now_ms=NOW),
                         {"status":403,"reason":"token_standby"})

    def test_02_expired_old_token_fails_closed_even_without_revoke(self):
        self.assertEqual(self.registry.authorize(OLD,kind="dev",
            now_ms=NOW+OLD_MAX_MS-1)["status"],200)
        self.assertEqual(self.registry.authorize(OLD,kind="dev",
            now_ms=NOW+OLD_MAX_MS),{"status":403,"reason":"token_expired"})

    def test_03_explicit_revoke_old_keeps_new_live(self):
        self.assertTrue(self.registry.revoke(OLD_ID,now_ms=NOW+100))
        self.assertFalse(self.registry.revoke(OLD_ID,now_ms=NOW+101))
        self.assertEqual(self.registry.authorize(OLD,kind="dev",now_ms=NOW+200),
                         {"status":403,"reason":"token_revoked"})
        self.assertEqual(self.registry.authorize(NEW,kind="dev",now_ms=NOW+200)["status"],200)

    def test_04_old_revoke_requires_unexpired_nonold_replacement(self):
        with tempfile.TemporaryDirectory() as t:
            led=NonceLedger(Path(t)/"isolated.sqlite")
            reg=TokenRegistry(led)
            reg.add(OLD,token_id=OLD_ID,kind="dev",role="exposed_old",
                    issued_ms=NOW,expires_ms=NOW+OLD_MAX_MS)
            self.assertFalse(reg.revoke(OLD_ID,now_ms=NOW))
            self.assertEqual(reg.authorize(OLD,kind="dev",now_ms=NOW)["status"],200)

    def test_05_new_revoke_without_active_backup_is_denied(self):
        self.assertFalse(self.registry.revoke(NEW_ID,now_ms=NOW))
        self.assertEqual(self.registry.authorize(NEW,kind="dev",now_ms=NOW)["status"],200)

    def test_06_atomic_backup_activation_revokes_new_and_never_revives_old(self):
        self.assertTrue(self.registry.activate_backup(BACKUP_ID,now_ms=NOW+1))
        self.assertFalse(self.registry.activate_backup(BACKUP_ID,now_ms=NOW+2))
        self.assertEqual(self.registry.authorize(NEW,kind="dev",now_ms=NOW+2),
                         {"status":403,"reason":"token_revoked"})
        self.assertEqual(self.registry.authorize(BACKUP,kind="dev",now_ms=NOW+2)["status"],200)
        self.assertTrue(self.registry.revoke(OLD_ID,now_ms=NOW+3))
        self.assertEqual(self.registry.authorize(OLD,kind="dev",now_ms=NOW+4)["status"],403)

    def test_07_new_token_duplicate_id_and_fingerprint_never_overwrite(self):
        self.assertFalse(self.registry.add(NEW,token_id="SOME-OTHER-ID",kind="dev",
                           role="new",issued_ms=NOW,expires_ms=NOW+60000))
        self.assertFalse(self.registry.add(BACKUP,token_id=NEW_ID,kind="dev",
                           role="backup",issued_ms=NOW,expires_ms=NOW+60000))
        self.assertEqual(self.registry.audit_counts(),
                         {"exposed_old:active":1,"new:active":1,"backup:standby":1})

    def test_08_registry_does_not_store_plaintext_token(self):
        with closing(sqlite3.connect(self.db)) as db:
            rows=db.execute("SELECT fingerprint FROM token_registry").fetchall()
        self.assertEqual(len(rows),3)
        for value in (OLD,NEW,BACKUP):
            self.assertNotIn(value,self.db.read_bytes().decode("latin1"))
        self.assertTrue(all(len(r[0])==64 for r in rows))

    def test_09_valid_proof_verifies_and_nonce_consumed_exactly_once(self):
        proof=self.issue()
        raw={k:v for k,v in proof.items() if k!="signature"}
        signature=base64.b64decode(proof["signature"])
        self.signer.public_key().verify(signature,
               json.dumps(raw,separators=(",",":"),ensure_ascii=True).encode())
        self.assertEqual(self.ledger.counts(),(1,1))
        with self.assertRaisesRegex(ProofIssuanceError,"challenge_or_token_not_usable"):
            self.issue()

    def test_10_untrusted_session_denied_before_consumption(self):
        with self.assertRaisesRegex(ProofIssuanceError,"session_forbidden"):
            self.issue(session="wrong")
        self.assertEqual(self.ledger.counts(),(1,0))
        self.assertEqual(self.issue()["kind"],"dev")

    def test_11_session_authorizer_failure_denied_before_consumption(self):
        def fail(*_):
            raise RuntimeError("synthetic session outage")
        issuer=AtomicSignedProofIssuer(self.registry,self.signer,fail,now_ms=lambda:NOW)
        with self.assertRaisesRegex(ProofIssuanceError,"preflight_unknown"):
            issuer.issue(session=SESSION,nonce=self.nonce,token_id=NEW_ID,
                         kind="dev",candidate_fingerprint=fingerprint(NEW),
                         exposed_old_token_id=OLD_ID)
        self.assertEqual(self.ledger.counts(),(1,0))

    def test_12_wrong_candidate_kind_and_absent_nonce_rejected(self):
        self.assertIsNone(self.registry.consume_authorized(self.nonce,kind="dev",
            candidate_fingerprint=fingerprint(OLD),token_id=NEW_ID,now_ms=NOW))
        self.assertIsNone(self.registry.consume_authorized(self.nonce,kind="localkey",
            candidate_fingerprint=fingerprint(NEW),token_id=NEW_ID,now_ms=NOW))
        self.assertIsNone(self.registry.consume_authorized(new_nonce(),kind="dev",
            candidate_fingerprint=fingerprint(NEW),token_id=NEW_ID,now_ms=NOW))
        self.assertEqual(self.ledger.counts(),(1,0))

    def test_13_revoke_before_issue_makes_proof_impossible(self):
        self.assertTrue(self.registry.activate_backup(BACKUP_ID,now_ms=NOW))
        with self.assertRaisesRegex(ProofIssuanceError,"challenge_or_token_not_usable"):
            self.issue()
        self.assertEqual(self.ledger.counts(),(1,0))

    def test_14_backup_proof_only_after_approved_activation(self):
        nonce=new_nonce()
        self.ledger.register(nonce,kind="dev",candidate_fingerprint=fingerprint(BACKUP),
                             token_id=BACKUP_ID,issued_ms=NOW,expires_ms=NOW+60000)
        with self.assertRaisesRegex(ProofIssuanceError,"challenge_or_token_not_usable"):
            self.issue(nonce=nonce,token_id=BACKUP_ID,
                       candidate_fingerprint=fingerprint(BACKUP))
        self.assertTrue(self.registry.activate_backup(BACKUP_ID,now_ms=NOW))
        proof=self.issue(nonce=nonce,token_id=BACKUP_ID,
                         candidate_fingerprint=fingerprint(BACKUP))
        self.assertEqual(proof["token_id"],BACKUP_ID)

    def test_15_two_concurrent_signers_only_one_receives_proof(self):
        barrier=threading.Barrier(2)
        def run(_):
            registry=TokenRegistry(NonceLedger(self.db))
            issuer=AtomicSignedProofIssuer(registry,self.signer,
                    lambda *_:True,now_ms=lambda:NOW)
            barrier.wait(timeout=10)
            try:
                return issuer.issue(session=SESSION,nonce=self.nonce,
                   token_id=NEW_ID,kind="dev",candidate_fingerprint=fingerprint(NEW),
                   exposed_old_token_id=OLD_ID)["token_id"]
            except ProofIssuanceError as exc:
                return str(exc)
        with ThreadPoolExecutor(max_workers=2) as pool:
            self.assertEqual(sorted(pool.map(run,[1,2])),
                 sorted([NEW_ID,"challenge_or_token_not_usable"]))
        self.assertEqual(self.ledger.counts(),(1,1))

    def test_16_storage_failure_never_invokes_signer(self):
        class SpySigner:
            calls=0
            def sign(self,_):
                self.calls+=1
                return b"x"*64
        spy=SpySigner()
        issuer=AtomicSignedProofIssuer(self.registry,spy,lambda *_:True,now_ms=lambda:NOW)
        with closing(sqlite3.connect(self.db)) as db:
            db.execute("""CREATE TRIGGER reject_nonce BEFORE UPDATE ON challenge
                 BEGIN SELECT RAISE(ABORT,'synthetic_abort'); END;""")
        with self.assertRaisesRegex(ProofIssuanceError,"atomic_commit_unknown"):
            issuer.issue(session=SESSION,nonce=self.nonce,token_id=NEW_ID,
                         kind="dev",candidate_fingerprint=fingerprint(NEW),
                         exposed_old_token_id=OLD_ID)
        self.assertEqual(spy.calls,0)
        self.assertEqual(self.ledger.counts(),(1,0))

    def test_17_signer_failure_burns_challenge(self):
        class FaultSigner:
            def sign(self,_):
                raise RuntimeError("synthetic signer crash")
        issuer=AtomicSignedProofIssuer(self.registry,FaultSigner(),
                                      lambda *_:True,now_ms=lambda:NOW)
        with self.assertRaisesRegex(ProofIssuanceError,
                                    "signature_failed_challenge_burned"):
            issuer.issue(session=SESSION,nonce=self.nonce,token_id=NEW_ID,
                         kind="dev",candidate_fingerprint=fingerprint(NEW),
                         exposed_old_token_id=OLD_ID)
        self.assertEqual(self.ledger.counts(),(1,1))
        with self.assertRaisesRegex(ProofIssuanceError,"challenge_or_token_not_usable"):
            self.issue()

    def test_18_unknown_expired_token_rejected(self):
        self.assertEqual(self.registry.authorize(
            "TEST-NONEXISTENT-TOKEN-0123456789ABCDE",kind="dev",now_ms=NOW),
            {"status":401,"reason":"unknown_token"})
        self.assertEqual(self.registry.authorize(NEW,kind="dev",
            now_ms=NOW+86400000),{"status":403,"reason":"token_expired"})

    def test_19_old_exposed_token_cannot_be_used_for_signed_proof(self):
        nonce=new_nonce()
        self.ledger.register(nonce,kind="dev",candidate_fingerprint=fingerprint(OLD),
                             token_id=OLD_ID,issued_ms=NOW,expires_ms=NOW+60000)
        self.assertIsNone(self.registry.consume_authorized(
            nonce,kind="dev",candidate_fingerprint=fingerprint(OLD),
            token_id=OLD_ID,now_ms=NOW))
        self.assertEqual(self.ledger.counts(),(2,0))

    def test_20_restart_retains_revocation(self):
        self.assertTrue(self.registry.revoke(OLD_ID,now_ms=NOW+1))
        fresh=TokenRegistry(NonceLedger(self.db))
        self.assertEqual(fresh.authorize(OLD,kind="dev",now_ms=NOW+2),
                         {"status":403,"reason":"token_revoked"})

    def test_21_invalid_admin_expiry_never_registers(self):
        with self.assertRaises(ValueError):
            self.registry.add("TEST-OTHER-TOKEN-0123456789ABCDEF",token_id="X-NEW",
                 kind="dev",role="new",issued_ms=NOW,
                 expires_ms=NOW+OLD_MAX_MS+ACTIVE_MAX_MS)
        with self.assertRaises(ValueError):
            self.registry.add("short",token_id="BAD",kind="dev",role="new",
                              issued_ms=NOW,expires_ms=NOW+1)
        self.assertEqual(sum(self.registry.audit_counts().values()),3)


if __name__=="__main__":
    unittest.main(verbosity=2)
