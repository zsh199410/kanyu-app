"""Issue #73 F3 classification regressions: synthetic tokens; temp SQLite only.

Expected: definitely malformed proof inputs never reach authorization, DB or signer;
genuinely ambiguous persistence failures remain fail-closed unknown.
"""
from __future__ import annotations

import sqlite3
import tempfile
import unittest
from pathlib import Path

from nonce_ledger_sqlite import NonceLedger, new_nonce
from token_registry_sqlite import TokenRegistry, fingerprint
from signed_proof_issuer import (
    SignedProofIssuer, TrustedTokenRecord, ProofIssuanceError,
)
from atomic_signed_proof_issuer import AtomicSignedProofIssuer

NOW = 1800000000000
CAND = "TEST-F3-NEW-CREDENTIAL-0123456789ABCDEF001122334455"
OLD = "TEST-F3-EXPOSED-OLD-0123456789ABCDEF0011223344"
BACKUP = "TEST-F3-BACKUP-CREDENTIAL-0123456789ABCDEF001122"
OLD_ID, NEW_ID, BACKUP_ID = "F3-OLD", "F3-NEW", "F3-BACKUP"
FP = fingerprint(CAND)


class SpySigner:
    def __init__(self):
        self.calls = 0

    def sign(self, raw):
        self.calls += 1
        return b"x" * 64


class ClassificationTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.db = Path(self.tmp.name) / "f3.sqlite"
        self.ledger = NonceLedger(self.db)
        self.registry = TokenRegistry(self.ledger)
        self.registry.add(
            OLD, token_id=OLD_ID, kind="dev", role="exposed_old",
            issued_ms=NOW, expires_ms=NOW + 60000,
        )
        self.registry.add(
            CAND, token_id=NEW_ID, kind="dev", role="new",
            issued_ms=NOW, expires_ms=NOW + 3600000,
        )
        self.registry.add(
            BACKUP, token_id=BACKUP_ID, kind="dev", role="backup",
            issued_ms=NOW, expires_ms=NOW + 3600000,
        )
        self.nonce = new_nonce()
        self.ledger.register(
            self.nonce, kind="dev", candidate_fingerprint=FP,
            token_id=NEW_ID, issued_ms=NOW, expires_ms=NOW + 60000,
        )
        self.signer = SpySigner()
        self.lookups = 0
        self.authorizations = 0

    def lookup(self, token_id):
        self.lookups += 1
        return TrustedTokenRecord("dev", NEW_ID, FP, "active", False)

    def authorize(self, session, token_id, kind):
        self.authorizations += 1
        return session == "test-session" and token_id == NEW_ID and kind == "dev"

    def legacy(self, nonce=None, lookup=None):
        issuer = SignedProofIssuer(
            self.ledger, self.signer, lookup or self.lookup,
        )
        return issuer.issue(
            nonce=self.nonce if nonce is None else nonce,
            requested_token_id=NEW_ID, expected_kind="dev",
            old_token_id=OLD_ID, now_ms=NOW,
        )

    def atomic(self, **changes):
        issuer = AtomicSignedProofIssuer(
            self.registry, self.signer, self.authorize, now_ms=lambda: NOW,
        )
        data = dict(
            session="test-session", nonce=self.nonce, token_id=NEW_ID,
            kind="dev", candidate_fingerprint=FP,
            exposed_old_token_id=OLD_ID,
        )
        data.update(changes)
        return issuer.issue(**data)

    def unchanged(self):
        self.assertEqual(self.ledger.counts(), (1, 0))
        self.assertEqual(self.signer.calls, 0)

    def test_01_legacy_malformed_nonce_never_looks_up_token(self):
        with self.assertRaisesRegex(ProofIssuanceError, "^invalid_challenge$"):
            self.legacy(nonce="BAD")
        self.assertEqual(self.lookups, 0)
        self.unchanged()

    def test_02_legacy_invalid_base64_is_not_commit_unknown(self):
        with self.assertRaisesRegex(ProofIssuanceError, "^invalid_challenge$"):
            self.legacy(nonce="!" * 43)
        self.assertEqual(self.lookups, 0)
        self.unchanged()

    def test_03_legacy_well_formed_unknown_challenge_is_rejected(self):
        with self.assertRaisesRegex(ProofIssuanceError, "challenge_not_usable"):
            self.legacy(nonce=new_nonce())
        self.assertEqual(self.lookups, 1)
        self.unchanged()

    def test_04_atomic_invalid_nonce_never_authorizes(self):
        with self.assertRaisesRegex(ProofIssuanceError, "^invalid_proof_input$"):
            self.atomic(nonce="BAD")
        self.assertEqual(self.authorizations, 0)
        self.unchanged()

    def test_05_atomic_invalid_fingerprint_is_precise(self):
        with self.assertRaisesRegex(ProofIssuanceError, "^invalid_proof_input$"):
            self.atomic(candidate_fingerprint="invalid")
        self.assertEqual(self.authorizations, 0)
        self.unchanged()

    def test_06_atomic_invalid_kind_is_precise(self):
        with self.assertRaisesRegex(ProofIssuanceError, "^invalid_proof_input$"):
            self.atomic(kind="invalid")
        self.assertEqual(self.authorizations, 0)
        self.unchanged()

    def test_07_atomic_invalid_token_id_is_precise(self):
        with self.assertRaisesRegex(ProofIssuanceError, "^invalid_proof_input$"):
            self.atomic(token_id="BAD ID!")
        self.assertEqual(self.authorizations, 0)
        self.unchanged()

    def test_08_atomic_bad_session_denied_before_db(self):
        with self.assertRaisesRegex(ProofIssuanceError, "^session_forbidden$"):
            self.atomic(session="untrusted")
        self.assertEqual(self.authorizations, 1)
        self.unchanged()

    def test_09_atomic_auth_callback_exception_is_not_input_error(self):
        def fails(*args):
            raise RuntimeError("synthetic identity backend down")
        issuer = AtomicSignedProofIssuer(
            self.registry, self.signer, fails, now_ms=lambda: NOW,
        )
        with self.assertRaisesRegex(ProofIssuanceError, "^preflight_unknown$"):
            issuer.issue(
                session="test-session", nonce=self.nonce, token_id=NEW_ID,
                kind="dev", candidate_fingerprint=FP,
                exposed_old_token_id=OLD_ID,
            )
        self.unchanged()

    def test_10_atomic_true_sqlite_failure_still_commit_unknown(self):
        with sqlite3.connect(self.db) as db:
            db.execute("""CREATE TRIGGER f3_block BEFORE UPDATE ON challenge
                BEGIN SELECT RAISE(ABORT, 'synthetic_sqlite_write_error'); END;""")
        with self.assertRaisesRegex(ProofIssuanceError, "^atomic_commit_unknown$"):
            self.atomic()
        self.assertEqual(self.authorizations, 1)
        self.unchanged()

    def test_11_atomic_valid_issued_proof_signs_once(self):
        p = self.atomic()
        self.assertEqual(p["token_id"], NEW_ID)
        self.assertEqual(self.signer.calls, 1)
        self.assertEqual(self.ledger.counts(), (1, 1))
        with self.assertRaisesRegex(ProofIssuanceError, "challenge_or_token_not_usable"):
            self.atomic()
        self.assertEqual(self.signer.calls, 1)

    def test_12_atomic_revoked_token_cannot_sign(self):
        self.assertTrue(self.registry.activate_backup(BACKUP_ID, now_ms=NOW))
        with self.assertRaisesRegex(ProofIssuanceError, "challenge_or_token_not_usable"):
            self.atomic()
        self.unchanged()


if __name__ == "__main__":
    unittest.main(verbosity=2)
