"""Round 10 cross-review probes (independent of GPT's suites).

P1: drain gate cross-process detection (fork; child status() must refuse).
P2: recovery checkpoint trusts the CALLER-supplied epoch — an old checkpoint
    verified against the restored old DB with the OLD epoch PASSES, proving
    the verifier alone cannot stop a rollback when the epoch is also rolled
    back (the documented limitation is real; the external control plane is
    the actual security property).
P3: F3 fix is real — same ledger, same malformed nonce: PR #108 issuer
    mislabels as nonce_commit_unknown, PR #113 issuer returns
    invalid_challenge with zero lookup.
P4: recovery digest is deterministic across fresh connections.
"""
from __future__ import annotations

import base64
import os
import sqlite3
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, "/home/hatch/workspace/pr96-c3c0")

from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from cryptography.hazmat.primitives import serialization

from nonce_ledger_sqlite import NonceLedger, new_nonce
from token_registry_sqlite import TokenRegistry, fingerprint
from signed_proof_issuer import SignedProofIssuer, TrustedTokenRecord, ProofIssuanceError
from staging_issuance_drain import IssuanceDrainGate, IssuanceGateClosed
from recovery_signed_checkpoint import (
    PURPOSE, _canonical, logical_state_sha256,
    require_signed_recovery_checkpoint,
)

NOW = 1800000000000
NEW = "TEST-R10-PROBE-NEW-0123456789ABCDEFGHIJKLMNOP"
NEW_ID = "R10-NEW"


class ProbeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.db_path = Path(self.temp.name) / "probe.sqlite"
        self.ledger = NonceLedger(self.db_path)
        self.registry = TokenRegistry(self.ledger)
        self.registry.add(NEW, token_id=NEW_ID, kind="dev", role="new",
                          issued_ms=NOW, expires_ms=NOW + 3600000)

    def test_p1_drain_gate_refuses_cross_process(self):
        gate = IssuanceDrainGate()
        self.assertEqual(gate.status()["frozen"], False)
        pid = os.fork()
        if pid == 0:  # child
            try:
                gate.status()
                os._exit(10)  # BUG: child was allowed
            except IssuanceGateClosed as exc:
                os._exit(0 if "cross_process_unverified" in str(exc) else 11)
            except Exception:
                os._exit(12)
        _, status = os.waitpid(pid, 0)
        self.assertEqual(os.waitstatus_to_exitcode(status), 0,
                         "child process must be refused by _same_process")

    def test_p2_old_epoch_from_old_checkpoint_passes_restored_db(self):
        """Demonstrates the documented limitation: the verifier trusts the
        epoch the CALLER supplies. If the epoch is rolled back together with
        the DB, the old checkpoint verifies against the old DB. The external
        monotonic control plane (not yet provisioned) is the real property."""
        nonce = new_nonce()
        self.ledger.register(nonce, kind="dev",
                             candidate_fingerprint=fingerprint(NEW),
                             token_id=NEW_ID, issued_ms=NOW,
                             expires_ms=NOW + 60000)
        signer = Ed25519PrivateKey.generate()
        pub = signer.public_key().public_bytes(
            encoding=serialization.Encoding.Raw,
            format=serialization.PublicFormat.Raw)
        digest = logical_state_sha256(self.ledger)
        record = {"purpose": PURPOSE, "epoch": 1, "state_sha256": digest,
                  "signature": base64.b64encode(
                      signer.sign(_canonical(PURPOSE, 1, digest))).decode()}
        # Advance state, snapshot the OLD file, then restore it.
        snap = Path(self.temp.name) / "snap.sqlite"
        with sqlite3.connect(self.db_path) as a, sqlite3.connect(snap) as b:
            a.backup(b)
        self.ledger.consume(nonce, kind="dev",
                            candidate_fingerprint=fingerprint(NEW),
                            token_id=NEW_ID, now_ms=NOW)
        self.assertEqual(self.ledger.counts(), (1, 1))
        with sqlite3.connect(snap) as a, sqlite3.connect(self.db_path) as b:
            a.backup(b)
        self.assertEqual(self.ledger.counts(), (1, 0))  # resurrected
        # Caller supplies the OLD epoch (as if it were also rolled back):
        # the verifier accepts the old checkpoint against the old DB.
        self.assertTrue(require_signed_recovery_checkpoint(
            self.ledger, record, trusted_external_epoch=1,
            independently_pinned_public_key=pub))
        # Caller supplies the NEW epoch: the same old checkpoint is rejected.
        with self.assertRaisesRegex(Exception, "external_epoch_mismatch"):
            require_signed_recovery_checkpoint(
                self.ledger, record, trusted_external_epoch=2,
                independently_pinned_public_key=pub)

    def test_p3_f3_fix_is_real_old_vs_new_issuer(self):
        nonce = new_nonce()
        self.ledger.register(nonce, kind="dev",
                             candidate_fingerprint=fingerprint(NEW),
                             token_id=NEW_ID, issued_ms=NOW,
                             expires_ms=NOW + 60000)
        lookups = {"n": 0}

        def lookup(token_id):
            lookups["n"] += 1
            return TrustedTokenRecord("dev", NEW_ID, fingerprint(NEW),
                                      "active", False)

        class SpySigner:
            def __init__(self):
                self.calls = 0

            def sign(self, raw):
                self.calls += 1
                return b"x" * 64

        signer = SpySigner()
        # NEW (PR #113) issuer: malformed nonce -> invalid_challenge, 0 lookups.
        new_issuer = SignedProofIssuer(self.ledger, signer, lookup)
        with self.assertRaisesRegex(ProofIssuanceError, "^invalid_challenge$"):
            new_issuer.issue(nonce="BAD", requested_token_id=NEW_ID,
                             expected_kind="dev", old_token_id="R10-OLD",
                             now_ms=NOW)
        self.assertEqual(lookups["n"], 0)
        self.assertEqual(signer.calls, 0)
        self.assertEqual(self.ledger.counts(), (1, 0))
        # OLD (PR #108) issuer: same malformed nonce -> nonce_commit_unknown.
        # Load the PR #108 version from the /tmp backup. Its TrustedTokenRecord
        # is a distinct class object, so the lookup must build THAT class.
        import importlib.util
        spec = importlib.util.spec_from_file_location(
            "signed_proof_issuer_r108", "/tmp/signed_proof_issuer.r108.py")
        mod = importlib.util.module_from_spec(spec)
        sys.modules["signed_proof_issuer_r108"] = mod
        spec.loader.exec_module(mod)

        def old_lookup(token_id):
            lookups["n"] += 1
            return mod.TrustedTokenRecord("dev", NEW_ID, fingerprint(NEW),
                                          "active", False)

        old_issuer = mod.SignedProofIssuer(self.ledger, signer, old_lookup)
        # The old module's ProofIssuanceError is a distinct class object.
        try:
            old_issuer.issue(nonce="BAD", requested_token_id=NEW_ID,
                             expected_kind="dev", old_token_id="R10-OLD",
                             now_ms=NOW)
            self.fail("old issuer must reject malformed nonce")
        except mod.ProofIssuanceError as exc:
            self.assertEqual(str(exc), "nonce_commit_unknown")
        # Old issuer DID reach the lookup (1 call) before failing at consume.
        self.assertEqual(lookups["n"], 1)

    def test_p4_recovery_digest_deterministic_across_connections(self):
        nonce = new_nonce()
        self.ledger.register(nonce, kind="dev",
                             candidate_fingerprint=fingerprint(NEW),
                             token_id=NEW_ID, issued_ms=NOW,
                             expires_ms=NOW + 60000)
        d1 = logical_state_sha256(self.ledger)
        fresh = NonceLedger(self.db_path)
        d2 = logical_state_sha256(fresh)
        self.assertEqual(d1, d2)
        self.assertRegex(d1, r"^[0-9a-f]{64}$")


if __name__ == "__main__":
    unittest.main(verbosity=2)
