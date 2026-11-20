"""Issue73 recovery signed-checkpoint isolated tests.

Uses temp SQLite snapshots and ephemeral Ed25519 keys. No real
external control plane, server credentials, or production source changes.
"""
from __future__ import annotations

import base64
import json
import sqlite3
import tempfile
import unittest
from pathlib import Path

from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from cryptography.hazmat.primitives import serialization

from nonce_ledger_sqlite import NonceLedger, new_nonce
from token_registry_sqlite import TokenRegistry, fingerprint
from recovery_signed_checkpoint import (
    PURPOSE, RecoveryNotVerified, _canonical, logical_state_sha256,
    require_signed_recovery_checkpoint,
)

NOW = 1800000000000
OLD = "TEST-ANCHOR-EXPOSED-OLD-0123456789ABCDEFGHIJKLMNOP"
NEW = "TEST-ANCHOR-ROTATED-NEW-0123456789ABCDEFGHIJKLMNOP"
BACKUP = "TEST-ANCHOR-STANDBY-BACKUP-0123456789ABCDEFGHIJKL"
OLD_ID, NEW_ID, BACKUP_ID = "ANCHOR-OLD", "ANCHOR-NEW", "ANCHOR-BACKUP"


class RecoveryCheckpointTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.db_path = Path(self.temp.name) / "credentials.sqlite"
        self.snapshot = Path(self.temp.name) / "old_snapshot.sqlite"
        self.ledger = NonceLedger(self.db_path)
        self.registry = TokenRegistry(self.ledger)
        for token, tid, role in (
            (OLD, OLD_ID, "exposed_old"),
            (NEW, NEW_ID, "new"),
            (BACKUP, BACKUP_ID, "backup"),
        ):
            self.assertTrue(self.registry.add(
                token, token_id=tid, role=role, kind="dev",
                issued_ms=NOW, expires_ms=NOW + 3600000,
            ))
        self.nonce = new_nonce()
        self.assertTrue(self.ledger.register(
            self.nonce, kind="dev", candidate_fingerprint=fingerprint(NEW),
            token_id=NEW_ID, issued_ms=NOW, expires_ms=NOW + 60000,
        ))
        self.signer = Ed25519PrivateKey.generate()
        self.pub = self.signer.public_key().public_bytes(
            encoding=serialization.Encoding.Raw,
            format=serialization.PublicFormat.Raw,
        )
        self.first = self.record(1)
        self.copy_snapshot(self.db_path, self.snapshot)

    @staticmethod
    def copy_snapshot(source, dest):
        with sqlite3.connect(source) as from_db, sqlite3.connect(dest) as to_db:
            from_db.backup(to_db)

    def record(self, epoch):
        digest = logical_state_sha256(self.ledger)
        message = _canonical(PURPOSE, epoch, digest)
        sig = self.signer.sign(message)
        return {
            "purpose": PURPOSE, "epoch": epoch, "state_sha256": digest,
            "signature": base64.b64encode(sig).decode("ascii"),
        }

    def check(self, record=None, *, floor=1, key=None):
        return require_signed_recovery_checkpoint(
            self.ledger, self.first if record is None else record,
            trusted_external_epoch=floor,
            independently_pinned_public_key=self.pub if key is None else key,
        )

    def advanced(self):
        self.assertEqual(
            self.registry.consume_authorized(
                self.nonce, kind="dev",
                candidate_fingerprint=fingerprint(NEW),
                token_id=NEW_ID, now_ms=NOW,
            )["token_id"], NEW_ID,
        )
        self.assertTrue(self.registry.activate_backup(
            BACKUP_ID, now_ms=NOW + 1))
        self.assertEqual(self.ledger.counts(), (1, 1))
        return self.record(2)

    def test_01_authentic_initial_state_accepted(self):
        self.assertTrue(self.check())

    def test_02_proof_is_pinned_to_raw_public_key(self):
        other = Ed25519PrivateKey.generate()
        key = other.public_key().public_bytes(
            encoding=serialization.Encoding.Raw,
            format=serialization.PublicFormat.Raw,
        )
        with self.assertRaisesRegex(RecoveryNotVerified, "checkpoint_signature_invalid"):
            self.check(key=key)

    def test_03_digest_tamper_rejected_by_signature(self):
        fake = dict(self.first, state_sha256="0" * 64)
        with self.assertRaisesRegex(RecoveryNotVerified, "checkpoint_signature_invalid"):
            self.check(fake)

    def test_04_signed_state_cannot_authorize_newer_epoch(self):
        with self.assertRaisesRegex(RecoveryNotVerified, "external_epoch_mismatch"):
            self.check(floor=2)

    def test_05_sqlite_mutation_without_updated_anchor_blocks(self):
        self.advanced()
        with self.assertRaisesRegex(RecoveryNotVerified, "sqlite_state_mismatch"):
            self.check()

    def test_06_new_signed_checkpoint_for_new_state_accepted(self):
        second = self.advanced()
        self.assertTrue(self.check(second, floor=2))

    def test_07_old_snapshot_restored_with_new_anchor_is_detected(self):
        second = self.advanced()
        self.copy_snapshot(self.snapshot, self.db_path)
        self.assertEqual(self.ledger.counts(), (1, 0))
        with self.assertRaisesRegex(RecoveryNotVerified, "sqlite_state_mismatch"):
            self.check(second, floor=2)

    def test_08_old_signed_checkpoint_replayed_against_new_external_epoch(self):
        self.advanced()
        self.copy_snapshot(self.snapshot, self.db_path)
        with self.assertRaisesRegex(RecoveryNotVerified, "external_epoch_mismatch"):
            self.check(self.first, floor=2)

    def test_09_signed_payload_rejects_extra_fields(self):
        with self.assertRaisesRegex(RecoveryNotVerified, "checkpoint_shape_invalid"):
            self.check(dict(self.first, token="not_an_allowed_field"))

    def test_10_false_or_missing_external_epoch_is_rejected(self):
        for floor in (None, 0, False, "1"):
            with self.subTest(floor=floor):
                with self.assertRaisesRegex(RecoveryNotVerified, "external_epoch_unavailable"):
                    self.check(floor=floor)

    def test_11_missing_or_malformed_trust_root_is_rejected(self):
        for key in (b"", b"A"*31, b"A"*33):
            with self.subTest(n=len(key)):
                with self.assertRaisesRegex(RecoveryNotVerified, "trusted_key_unavailable"):
                    self.check(key=key)

    def test_12_wrong_purpose_rejected(self):
        with self.assertRaisesRegex(RecoveryNotVerified, "checkpoint_purpose_mismatch"):
            self.check(dict(self.first, purpose="issue73/other"))

    def test_13_mutated_signature_rejected(self):
        with self.assertRaisesRegex(RecoveryNotVerified, "checkpoint_signature_invalid"):
            self.check(dict(self.first, signature=base64.b64encode(b"x"*64).decode()))

    def test_14_logical_state_digest_excludes_plaintext_credentials(self):
        output = logical_state_sha256(self.ledger)
        self.assertRegex(output, r"^[0-9a-f]{64}$")
        self.assertNotIn(OLD, output)
        self.assertNotIn(NEW, output)
        self.assertNotIn(self.nonce, output)

    def test_15_checkpoint_verifies_after_process_style_db_reopen(self):
        fresh = NonceLedger(self.db_path)
        self.assertTrue(require_signed_recovery_checkpoint(
            fresh, self.first,
            trusted_external_epoch=1,
            independently_pinned_public_key=self.pub,
        ))

    def test_16_missing_registry_table_fails_closed(self):
        with sqlite3.connect(self.db_path) as db:
            db.execute("DROP TABLE token_registry")
        with self.assertRaisesRegex(RecoveryNotVerified, "state_read_unknown"):
            self.check()

    def test_17_same_counts_but_different_nonce_consumption_is_detected(self):
        # A fresh independent nonce with different binding changes logical
        # state even if the total number of consumed tombstones remains one.
        self.advanced()
        latest = self.record(3)
        self.copy_snapshot(self.snapshot, self.db_path)
        self.assertTrue(self.registry.consume_authorized(
            self.nonce, kind="dev", candidate_fingerprint=fingerprint(NEW),
            token_id=NEW_ID, now_ms=NOW))
        self.assertEqual(self.ledger.counts(), (1, 1))
        with self.assertRaisesRegex(RecoveryNotVerified, "sqlite_state_mismatch"):
            self.check(latest, floor=3)


if __name__ == "__main__":
    unittest.main(verbosity=2)
