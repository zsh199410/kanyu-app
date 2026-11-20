"""Issue #73 witness protocol tests: real SQLite and real Ed25519, synthetic only.

Both DB files live in test-only /tmp for convenience. This DOES NOT
demonstrate an independent remote failure domain or production readiness.
"""
from __future__ import annotations

import base64
import json
import sqlite3
import tempfile
import threading
import time
import unittest
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

from nonce_ledger_sqlite import NonceLedger, new_nonce
from token_registry_sqlite import TokenRegistry, fingerprint
from recovery_signed_checkpoint import logical_state_sha256
from staging_issuance_drain import IssuanceDrainGate, IssuanceGateClosed
from witness_fenced_issuer_reference import (
    IndependentWitnessTestDouble, WitnessedAtomicService, WitnessRejected,
)
from signed_proof_issuer import ProofIssuanceError

NOW = 1800000000000
OLD = "TEST-WITNESS-EXPOSED-OLD-0123456789ABCDEFGHIJKLMN"
NEW = "TEST-WITNESS-ROTATED-NEW-0123456789ABCDEFGHIJKLMN"
BACKUP = "TEST-WITNESS-STANDBY-BACKUP-0123456789ABCDEFGHIJ"
OLD_ID, NEW_ID, BACKUP_ID = "WIT-OLD", "WIT-NEW", "WIT-BACKUP"


class CountingEdSigner:
    def __init__(self, fail=False):
        self.key = Ed25519PrivateKey.generate()
        self.calls = 0
        self.fail = fail

    def sign(self, raw):
        self.calls += 1
        if self.fail:
            raise RuntimeError("synthetic_private_signer_failure")
        return self.key.sign(raw)


class WitnessTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        root = Path(self.tmp.name)
        business = root / "business"
        external = root / "external-test-double"
        business.mkdir(mode=0o700)
        external.mkdir(mode=0o700)
        self.path = business / "tokens.sqlite"
        self.witness_path = external / "epoch.sqlite"
        self.ledger = NonceLedger(self.path)
        self.reg = TokenRegistry(self.ledger)
        for value, tid, role in (
            (OLD, OLD_ID, "exposed_old"),
            (NEW, NEW_ID, "new"),
            (BACKUP, BACKUP_ID, "backup"),
        ):
            self.assertTrue(self.reg.add(
                value, token_id=tid, kind="dev", role=role,
                issued_ms=NOW, expires_ms=NOW + 86400000,
            ))
        self.witness = IndependentWitnessTestDouble(self.witness_path)
        self.assertTrue(self.witness.bootstrap(
            logical_state_sha256(self.ledger),
            trusted_operator_approved=True))
        self.gate = IssuanceDrainGate()
        self.signer = CountingEdSigner()
        self.service = self.make_service()
        self.nonce = new_nonce()

    def make_service(self):
        return WitnessedAtomicService(
            self.reg, self.signer, self.authorize, self.witness,
            now_ms=lambda: NOW, gate=self.gate)

    def authorize(self, session, token_id, kind):
        return session == "synthetic-session" and token_id == NEW_ID and kind == "dev"

    def register(self, nonce=None):
        return self.service.register(
            self.nonce if nonce is None else nonce, kind="dev",
            candidate_fingerprint=fingerprint(NEW), token_id=NEW_ID,
            issued_ms=NOW, expires_ms=NOW + 60000)

    def issue(self, nonce=None):
        return self.service.issue(
            session="synthetic-session",
            nonce=self.nonce if nonce is None else nonce,
            token_id=NEW_ID, kind="dev",
            candidate_fingerprint=fingerprint(NEW),
            exposed_old_token_id=OLD_ID)

    @staticmethod
    def backup(source, dest):
        with sqlite3.connect(source) as a, sqlite3.connect(dest) as b:
            a.backup(b)

    def test_01_explicit_bootstrap_only(self):
        self.assertFalse(self.witness.bootstrap(
            logical_state_sha256(self.ledger), trusted_operator_approved=True))
        self.assertEqual(self.witness.head()["epoch"], 1)
        self.assertEqual(self.witness.counts(), (0, 0))

    def test_02_registration_then_verified_real_signature(self):
        self.assertTrue(self.register())
        self.assertEqual(self.witness.head()["epoch"], 2)
        proof = self.issue()
        canonical = json.dumps(
            {k: v for k, v in proof.items() if k != "signature"},
            separators=(",", ":"), ensure_ascii=True).encode()
        self.signer.key.public_key().verify(
            base64.b64decode(proof["signature"]), canonical)
        self.assertEqual(self.witness.counts(), (1, 0))
        self.assertEqual(self.witness.head()["epoch"], 3)
        self.assertTrue(self.witness.require_fresh(logical_state_sha256(self.ledger)))

    def test_03_repeated_nonce_rejected_even_with_witness_present(self):
        self.register()
        self.issue()
        with self.assertRaises(ProofIssuanceError):
            self.issue()
        self.assertEqual(self.signer.calls, 1)
        self.assertEqual(self.witness.counts(), (1, 0))

    def test_04_restored_business_db_blocks_same_nonce_before_sign(self):
        self.register()
        snapshot = self.path.parent / "preconsume.sqlite"
        self.backup(self.path, snapshot)
        self.issue()
        self.backup(snapshot, self.path)
        with self.assertRaisesRegex(WitnessRejected,
                                    "database_rollback_or_unknown_mutation"):
            self.issue()
        self.assertEqual(self.signer.calls, 1)

    def test_05_restored_business_db_blocks_fresh_nonce_before_register(self):
        self.register()
        snapshot = self.path.parent / "beforeconsume.sqlite"
        self.backup(self.path, snapshot)
        self.issue()
        self.backup(snapshot, self.path)
        with self.assertRaisesRegex(WitnessRejected,
                                    "database_rollback_or_unknown_mutation"):
            self.register(new_nonce())
        self.assertEqual(self.signer.calls, 1)

    def test_06_witness_outage_after_sqlite_commit_fails_closed(self):
        self.register()
        original = self.witness.advance
        self.witness.advance = lambda *a, **k: (
            (_ for _ in ()).throw(WitnessRejected("synthetic_remote_timeout")))
        try:
            with self.assertRaisesRegex(ProofIssuanceError,
                                        "signature_failed_challenge_burned"):
                self.issue()
        finally:
            self.witness.advance = original
        self.assertEqual(self.signer.calls, 0)
        self.assertEqual(self.ledger.counts(), (1, 1))
        with self.assertRaisesRegex(WitnessRejected,
                                    "database_rollback_or_unknown_mutation"):
            self.issue()

    def test_07_signer_crash_after_witness_commit_burns_challenge(self):
        self.register()
        self.signer.fail = True
        with self.assertRaisesRegex(ProofIssuanceError,
                                    "signature_failed_challenge_burned"):
            self.issue()
        self.assertEqual(self.witness.counts(), (1, 0))
        self.assertTrue(self.witness.require_fresh(logical_state_sha256(self.ledger)))
        with self.assertRaises(ProofIssuanceError):
            self.issue()
        self.assertEqual(self.signer.calls, 1)

    def test_08_bad_session_does_not_advance_witness(self):
        self.register()
        with self.assertRaisesRegex(ProofIssuanceError, "session_forbidden"):
            self.service.issue(
                session="untrusted", nonce=self.nonce,
                token_id=NEW_ID, kind="dev",
                candidate_fingerprint=fingerprint(NEW),
                exposed_old_token_id=OLD_ID)
        self.assertEqual(self.witness.head()["epoch"], 2)
        self.assertEqual(self.ledger.counts(), (1, 0))
        self.assertEqual(self.signer.calls, 0)

    def test_09_simultaneous_duplicate_requests_one_signature(self):
        self.register()
        barrier = threading.Barrier(2)
        def issue(_):
            barrier.wait(timeout=3)
            try:
                return self.issue()["token_id"]
            except ProofIssuanceError:
                return "rejected"
        with ThreadPoolExecutor(max_workers=2) as ex:
            results = list(ex.map(issue, [0, 1]))
        self.assertEqual(sorted(results), sorted([NEW_ID, "rejected"]))
        self.assertEqual(self.signer.calls, 1)
        self.assertEqual(self.witness.counts(), (1, 0))

    def test_10_registered_challenge_survives_service_restart(self):
        self.register()
        self.witness = IndependentWitnessTestDouble(self.witness_path)
        self.gate = IssuanceDrainGate()
        self.service = self.make_service()
        proof = self.issue()
        self.assertEqual(proof["token_id"], NEW_ID)
        self.assertEqual(self.witness.counts(), (1, 0))

    def test_11_admin_backup_activate_requires_witness_seal(self):
        self.register()
        self.assertTrue(self.service.admin_transition(
            lambda: self.reg.activate_backup(BACKUP_ID, now_ms=NOW),
            lambda: self.reg.authorize(NEW, kind="dev", now_ms=NOW)["status"] == 403,
            revoked_token_id=NEW_ID))
        self.assertEqual(self.witness.counts(), (0, 1))
        self.assertEqual(self.witness.head()["epoch"], 3)
        self.assertEqual(self.reg.authorize(BACKUP, kind="dev", now_ms=NOW)["status"], 200)
        with self.assertRaisesRegex(ProofIssuanceError, "challenge_or_token_not_usable"):
            self.issue()

    def test_12_admin_remote_witness_failure_keeps_gate_frozen(self):
        def fail(*args, **kwargs):
            raise WitnessRejected("synthetic_remote_commit_unknown")
        self.witness.advance = fail
        with self.assertRaisesRegex(WitnessRejected, "synthetic_remote_commit_unknown"):
            self.service.admin_transition(
                lambda: self.reg.activate_backup(BACKUP_ID, now_ms=NOW),
                lambda: True, revoked_token_id=NEW_ID)
        self.assertTrue(self.gate.status()["frozen"])
        with self.assertRaises(IssuanceGateClosed):
            self.register()

    def test_13_inflight_signer_drains_before_admin_transition(self):
        entered, release = threading.Event(), threading.Event()
        original_sign = self.signer.sign
        def slow_sign(raw):
            entered.set()
            if not release.wait(timeout=3):
                raise RuntimeError("test_sign_timeout")
            return original_sign(raw)
        self.register()
        self.signer.sign = slow_sign
        def admin():
            return self.service.admin_transition(
                lambda: self.reg.activate_backup(BACKUP_ID, now_ms=NOW),
                lambda: self.reg.authorize(NEW, kind="dev", now_ms=NOW)["status"] == 403,
                revoked_token_id=NEW_ID)
        try:
            with ThreadPoolExecutor(max_workers=2) as ex:
                one = ex.submit(self.issue)
                self.assertTrue(entered.wait(timeout=2))
                two = ex.submit(admin)
                for _ in range(100):
                    if self.gate.status()["frozen"]:
                        break
                    time.sleep(.005)
                self.assertTrue(self.gate.status()["frozen"])
                with self.assertRaises(IssuanceGateClosed):
                    self.register(new_nonce())
                release.set()
                self.assertEqual(one.result(timeout=3)["token_id"], NEW_ID)
                self.assertTrue(two.result(timeout=3))
                self.assertEqual(self.signer.calls, 1)
        finally:
            release.set()

    def test_14_rejected_untrusted_bootstrap(self):
        other_dir = Path(self.tmp.name) / "another"
        other_dir.mkdir(mode=0o700)
        fresh = IndependentWitnessTestDouble(other_dir / "unbootstrapped.sqlite")
        with self.assertRaisesRegex(WitnessRejected, "trusted_bootstrap_missing"):
            fresh.bootstrap(logical_state_sha256(self.ledger))
        with self.assertRaisesRegex(WitnessRejected, "witness_not_bootstrapped"):
            fresh.require_fresh(logical_state_sha256(self.ledger))

    def test_15_old_signed_proof_still_valid_after_state_revoke(self):
        self.register()
        proof = self.issue()
        self.assertTrue(self.service.admin_transition(
            lambda: self.reg.activate_backup(BACKUP_ID, now_ms=NOW),
            lambda: True, revoked_token_id=NEW_ID))
        canonical = json.dumps({k: v for k, v in proof.items()
                                if k != "signature"}, separators=(",", ":")).encode()
        # Known limitation: standalone signature remains cryptographically
        # valid; client nonce/revocation gate is still mandatory.
        self.signer.key.public_key().verify(
            base64.b64decode(proof["signature"]), canonical)

    def test_16_restoring_both_db_and_witness_resurrects_nonce_known_limit(self):
        self.register()
        db_copy = self.path.parent / "oldtokens.sqlite"
        witness_copy = self.witness_path.parent / "oldwitness.sqlite"
        self.backup(self.path, db_copy)
        self.backup(self.witness_path, witness_copy)
        self.issue()
        self.backup(db_copy, self.path)
        self.backup(witness_copy, self.witness_path)
        # Real independent failure domain MUST make this impossible.
        # Tests deliberately show common-domain rollback defeats fence.
        replay = self.issue()
        self.assertEqual(replay["token_id"], NEW_ID)
        self.assertEqual(self.signer.calls, 2)

    def test_17_repeated_bootstrap_does_not_rewind_after_issue(self):
        self.register()
        self.issue()
        self.assertFalse(self.witness.bootstrap(
            logical_state_sha256(self.ledger), trusted_operator_approved=True))
        self.assertEqual(self.witness.head()["epoch"], 3)

    def test_18_witness_blocks_previously_revoked_token_tombstone(self):
        self.register()
        self.assertTrue(self.service.admin_transition(
            lambda: self.reg.activate_backup(BACKUP_ID, now_ms=NOW),
            lambda: True, revoked_token_id=NEW_ID))
        with self.assertRaisesRegex(WitnessRejected, "token_fenced_by_witness"):
            current = logical_state_sha256(self.ledger)
            self.witness.advance(current, "f"*64, nonce=new_nonce(),
                                 token_id=NEW_ID)


if __name__ == "__main__":
    unittest.main(verbosity=2)
