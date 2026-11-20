"""Round 8 cross-review probes: independent confirmation of design claims.

P1 (documented limitation, PR #108): a revoke landing after the token
lookup but before nonce consume still yields a proof — the lookup->consume
TOCTOU gap PR #109 was built to close. The test asserts the gap is REAL.
P2 (documented limitation, PR #109): a revoke/activation landing after
consume_authorized COMMITs but before signing still completes signing —
the revocation-linearization limit. The test asserts it is REAL.
P3 (positive): the registry DB bytes contain no plaintext token values,
only SHA-256 fingerprints.
P4 (positive): an exposed_old token authenticates at the mock bridge
(200) during its window but can NEVER authorize a proof
(consume_authorized returns None).

All values synthetic; ephemeral keys; temp dirs only. Exit 0 with all
four passing. P1/P2 passing means the limitations are CONFIRMED REAL,
not that the code is broken — both are disclosed in the gate docs.
"""
from __future__ import annotations

import hashlib
import tempfile
import unittest
from pathlib import Path

from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

from nonce_ledger_sqlite import NonceLedger, new_nonce
from signed_proof_issuer import SignedProofIssuer, TrustedTokenRecord
from token_registry_sqlite import TokenRegistry, fingerprint
from atomic_signed_proof_issuer import AtomicSignedProofIssuer

NOW = 1800000000000
CAND = "TEST-R8-PROBE-CANDIDATE-0123456789ABCDEF"
FP = hashlib.sha256(CAND.encode()).hexdigest()
NEW_ID = "R8-PROBE-NEW-ID"
OLD_ID = "R8-PROBE-OLD-ID"
BACKUP_ID = "R8-PROBE-BACKUP-ID"
OLD_TOK = "TEST-R8-PROBE-EXPOSED-OLD-0123456789ABCDE"
NEW_TOK = "TEST-R8-PROBE-ROTATED-NEW-0123456789ABCDE"
BACKUP_TOK = "TEST-R8-PROBE-STANDBY-BACKUP-0123456789ABCDEF"


class CrossReviewProbeTests(unittest.TestCase):
    def test_p1_pr108_lookup_consume_toctou_gap_is_real(self):
        """A concurrent revoke after lookup does not stop PR #108 signing."""
        with tempfile.TemporaryDirectory() as d:
            ledger = NonceLedger(Path(d) / "p1.sqlite")
            nonce = new_nonce()
            ledger.register(nonce, kind="dev", candidate_fingerprint=FP,
                            token_id=NEW_ID, issued_ms=NOW,
                            expires_ms=NOW + 60000)
            state = {"revoked": False}
            rec = TrustedTokenRecord("dev", NEW_ID, FP, "active", False)

            def lookup_with_concurrent_revoke(token_id):
                state["revoked"] = True  # admin revoke lands mid-issue
                return rec if token_id == NEW_ID else None

            issuer = SignedProofIssuer(ledger, Ed25519PrivateKey.generate(),
                                       lookup_with_concurrent_revoke)
            proof = issuer.issue(nonce=nonce, requested_token_id=NEW_ID,
                                 expected_kind="dev", old_token_id=OLD_ID,
                                 now_ms=NOW)
            self.assertTrue(state["revoked"])
            self.assertEqual(proof["token_id"], NEW_ID)

    def test_p2_pr109_revocation_linearization_limit_is_real(self):
        """A revoke after atomic COMMIT but before signing still signs."""
        with tempfile.TemporaryDirectory() as d:
            db = Path(d) / "p2.sqlite"
            ledger = NonceLedger(db)
            reg = TokenRegistry(ledger)
            reg.add(OLD_TOK, token_id=OLD_ID, kind="dev",
                    role="exposed_old", issued_ms=NOW,
                    expires_ms=NOW + 3600000)
            reg.add(NEW_TOK, token_id=NEW_ID, kind="dev", role="new",
                    issued_ms=NOW, expires_ms=NOW + 86400000)
            reg.add(BACKUP_TOK, token_id=BACKUP_ID, kind="dev",
                    role="backup", issued_ms=NOW, expires_ms=NOW + 86400000)
            nonce = new_nonce()
            ledger.register(nonce, kind="dev",
                            candidate_fingerprint=fingerprint(NEW_TOK),
                            token_id=NEW_ID, issued_ms=NOW,
                            expires_ms=NOW + 60000)

            class RevokingSigner:
                def __init__(self, key, registry):
                    self.key, self.registry = key, registry

                def sign(self, data):
                    ok = self.registry.activate_backup(BACKUP_ID, now_ms=NOW)
                    assert ok, "backup activation must succeed in probe"
                    return self.key.sign(data)

            issuer = AtomicSignedProofIssuer(
                reg, RevokingSigner(Ed25519PrivateKey.generate(), reg),
                lambda s, tid, kind: s == "sess" and tid == NEW_ID
                and kind == "dev",
                now_ms=lambda: NOW)
            proof = issuer.issue(session="sess", nonce=nonce, token_id=NEW_ID,
                                 kind="dev",
                                 candidate_fingerprint=fingerprint(NEW_TOK),
                                 exposed_old_token_id=OLD_ID)
            self.assertEqual(proof["token_id"], NEW_ID)
            self.assertEqual(reg.authorize(NEW_TOK, kind="dev", now_ms=NOW),
                             {"status": 403, "reason": "token_revoked"})

    def test_p3_registry_db_holds_no_plaintext_token(self):
        with tempfile.TemporaryDirectory() as d:
            db = Path(d) / "p3.sqlite"
            ledger = NonceLedger(db)
            reg = TokenRegistry(ledger)
            reg.add(OLD_TOK, token_id=OLD_ID, kind="dev",
                    role="exposed_old", issued_ms=NOW,
                    expires_ms=NOW + 3600000)
            reg.add(NEW_TOK, token_id=NEW_ID, kind="dev", role="new",
                    issued_ms=NOW, expires_ms=NOW + 86400000)
            raw = db.read_bytes()
            self.assertNotIn(OLD_TOK.encode(), raw)
            self.assertNotIn(NEW_TOK.encode(), raw)
            self.assertIn(fingerprint(NEW_TOK).encode(), raw)

    def test_p4_exposed_old_authenticates_but_never_authorizes_proof(self):
        with tempfile.TemporaryDirectory() as d:
            db = Path(d) / "p4.sqlite"
            ledger = NonceLedger(db)
            reg = TokenRegistry(ledger)
            reg.add(OLD_TOK, token_id=OLD_ID, kind="dev",
                    role="exposed_old", issued_ms=NOW,
                    expires_ms=NOW + 3600000)
            reg.add(NEW_TOK, token_id=NEW_ID, kind="dev", role="new",
                    issued_ms=NOW, expires_ms=NOW + 86400000)
            self.assertEqual(
                reg.authorize(OLD_TOK, kind="dev", now_ms=NOW)["status"], 200)
            nonce = new_nonce()
            ledger.register(nonce, kind="dev",
                            candidate_fingerprint=fingerprint(OLD_TOK),
                            token_id=OLD_ID, issued_ms=NOW,
                            expires_ms=NOW + 60000)
            self.assertIsNone(reg.consume_authorized(
                nonce, kind="dev",
                candidate_fingerprint=fingerprint(OLD_TOK),
                token_id=OLD_ID, now_ms=NOW))


if __name__ == "__main__":
    unittest.main(verbosity=2)
