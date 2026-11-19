"""Isolated end-to-end signer unit tests: synthetic records, ephemeral keys."""
from __future__ import annotations

import hashlib
import json
import tempfile
import threading
import unittest
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from cryptography.exceptions import InvalidSignature

from nonce_ledger_sqlite import NonceLedger, new_nonce
from signed_proof_issuer import (
    SignedProofIssuer, TrustedTokenRecord, ProofIssuanceError, PURPOSE,
)

NOW = 1800000000000
CANDIDATE = "TEST-NEW-DEV-CANDIDATE-0123456789ABCDEF"
FP = hashlib.sha256(CANDIDATE.encode()).hexdigest()
OLD_ID = "TEST-EXPOSED-OLD-ID"
NEW_ID = "TEST-NEW-TOKEN-ID"
REC = TrustedTokenRecord("dev", NEW_ID, FP, "active", False)


class SignerTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.ledger = NonceLedger(Path(self.tmp.name) / "proofs.sqlite")
        self.secret = Ed25519PrivateKey.generate()
        self.record = REC
        self.signer = SignedProofIssuer(
            self.ledger, self.secret, self.lookup,
        )
        self.nonce = new_nonce()
        self.ledger.register(
            self.nonce, kind="dev", candidate_fingerprint=FP,
            token_id=NEW_ID, issued_ms=NOW, expires_ms=NOW + 60000,
        )

    def tearDown(self):
        self.tmp.cleanup()

    def lookup(self, key):
        return self.record if key == NEW_ID else None

    def issue(self, **overrides):
        return self.signer.issue(**({
            "nonce": self.nonce, "requested_token_id": NEW_ID,
            "expected_kind": "dev", "old_token_id": OLD_ID, "now_ms": NOW,
        } | overrides))

    def test_01_signs_canonical_proof(self):
        proof = self.issue()
        self.assertEqual(proof["purpose"], PURPOSE)
        self.assertEqual(proof["nonce"], self.nonce)
        self.assertEqual(proof["fingerprint"], FP)
        import base64
        signed = {k: v for k, v in proof.items() if k != "signature"}
        raw = json.dumps(signed, separators=(",", ":"), ensure_ascii=True).encode()
        self.secret.public_key().verify(base64.b64decode(proof["signature"]), raw)
        self.assertEqual(self.ledger.counts(), (1, 1))

    def test_02_cannot_reissue_consumed_proof(self):
        self.issue()
        with self.assertRaisesRegex(ProofIssuanceError, "challenge_not_usable"):
            self.issue()

    def test_03_wrong_token_id_denied_before_consumption(self):
        with self.assertRaisesRegex(ProofIssuanceError, "token_not_issued"):
            self.issue(requested_token_id="FAKE-ID")
        self.assertEqual(self.ledger.counts(), (1, 0))

    def test_04_wrong_kind_denied_before_consumption(self):
        with self.assertRaisesRegex(ProofIssuanceError, "token_not_authorized"):
            self.issue(expected_kind="localkey")
        self.assertEqual(self.ledger.counts(), (1, 0))

    def test_05_old_token_id_denied(self):
        with self.assertRaisesRegex(ProofIssuanceError, "invalid_token_identity"):
            self.issue(requested_token_id=OLD_ID, old_token_id=OLD_ID)
        self.assertEqual(self.ledger.counts(), (1, 0))

    def test_06_server_record_marked_exposed_denied(self):
        self.record = TrustedTokenRecord("dev", NEW_ID, FP, "active", True)
        with self.assertRaisesRegex(ProofIssuanceError, "token_not_authorized"):
            self.issue()
        self.assertEqual(self.ledger.counts(), (1, 0))

    def test_07_revoked_record_denied(self):
        self.record = TrustedTokenRecord("dev", NEW_ID, FP, "revoked", False)
        with self.assertRaisesRegex(ProofIssuanceError, "token_not_authorized"):
            self.issue()
        self.assertEqual(self.ledger.counts(), (1, 0))

    def test_08_registry_failure_denied(self):
        def failed(_):
            raise IOError("synthetic database outage")
        issuer = SignedProofIssuer(self.ledger, self.secret, failed)
        with self.assertRaisesRegex(ProofIssuanceError, "registry_unknown"):
            issuer.issue(nonce=self.nonce, requested_token_id=NEW_ID,
                         expected_kind="dev", old_token_id=OLD_ID,
                         now_ms=NOW)
        self.assertEqual(self.ledger.counts(), (1, 0))

    def test_09_fake_candidate_binding_denied(self):
        self.record = TrustedTokenRecord(
            "dev", NEW_ID, hashlib.sha256(b"other").hexdigest(),
            "active", False,
        )
        with self.assertRaisesRegex(ProofIssuanceError, "challenge_not_usable"):
            self.issue()
        self.assertEqual(self.ledger.counts(), (1, 0))

    def test_10_expired_challenge_denied(self):
        with self.assertRaisesRegex(ProofIssuanceError, "challenge_not_usable"):
            self.issue(now_ms=NOW + 60000)
        self.assertEqual(self.ledger.counts(), (1, 0))

    def test_11_invalid_ttl_denied(self):
        for ttl in (0, -1, 60001, True):
            with self.subTest(ttl=ttl):
                with self.assertRaisesRegex(ProofIssuanceError, "invalid_ttl"):
                    self.issue(ttl_ms=ttl)
        self.assertEqual(self.ledger.counts(), (1, 0))

    def test_12_invalid_clock_denied(self):
        for now in (-1, 2**53, "now", True):
            with self.subTest(now=now):
                with self.assertRaisesRegex(ProofIssuanceError, "invalid_clock"):
                    self.issue(now_ms=now)
        self.assertEqual(self.ledger.counts(), (1, 0))

    def test_13_signer_crash_burns_nonce_without_proof(self):
        class BrokenSigner:
            def sign(self, _):
                raise RuntimeError("synthetic signer failure")
        issuer = SignedProofIssuer(self.ledger, BrokenSigner(), self.lookup)
        with self.assertRaisesRegex(ProofIssuanceError, "signing_failed_after_consume"):
            issuer.issue(nonce=self.nonce, requested_token_id=NEW_ID,
                         expected_kind="dev", old_token_id=OLD_ID,
                         now_ms=NOW)
        self.assertEqual(self.ledger.counts(), (1, 1))
        with self.assertRaisesRegex(ProofIssuanceError, "challenge_not_usable"):
            self.issue()

    def test_14_database_error_never_calls_signer(self):
        class CountingSigner:
            count = 0
            def sign(self, data):
                self.count += 1
                return b"x" * 64
        class BrokenLedger(NonceLedger):
            def consume(self, *args, **kwargs):
                raise IOError("synthetic ambiguous commit")
        faulty = BrokenLedger(Path(self.tmp.name) / "broken.sqlite")
        spy = CountingSigner()
        issuer = SignedProofIssuer(faulty, spy, self.lookup)
        with self.assertRaisesRegex(ProofIssuanceError, "nonce_commit_unknown"):
            issuer.issue(nonce=self.nonce, requested_token_id=NEW_ID,
                         expected_kind="dev", old_token_id=OLD_ID,
                         now_ms=NOW)
        self.assertEqual(spy.count, 0)

    def test_15_two_concurrent_issuers_only_one_signature(self):
        barrier = threading.Barrier(2)
        def attempt(_):
            ledger = NonceLedger(Path(self.tmp.name) / "proofs.sqlite")
            issuer = SignedProofIssuer(ledger, self.secret, self.lookup)
            barrier.wait(timeout=10)
            try:
                return issuer.issue(nonce=self.nonce,
                                   requested_token_id=NEW_ID,
                                   expected_kind="dev", old_token_id=OLD_ID,
                                   now_ms=NOW)["token_id"]
            except ProofIssuanceError as exc:
                return str(exc)
        with ThreadPoolExecutor(max_workers=2) as pool:
            results = sorted(pool.map(attempt, [1, 2]))
        self.assertEqual(results, ["challenge_not_usable", NEW_ID])
        self.assertEqual(self.ledger.counts(), (1, 1))

    def test_16_no_secret_or_private_key_in_proof(self):
        proof = self.issue()
        blob = json.dumps(proof)
        self.assertNotIn(CANDIDATE, blob)
        self.assertNotIn("PRIVATE KEY", blob)
        self.assertNotIn("BEGIN", blob)


if __name__ == "__main__":
    unittest.main(verbosity=2)
