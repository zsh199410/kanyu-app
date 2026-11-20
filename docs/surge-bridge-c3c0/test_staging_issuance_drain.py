"""Issue73 isolated in-process drain regression suite; NO production calls."""
from __future__ import annotations

import tempfile
import threading
import time
import unittest
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from nonce_ledger_sqlite import NonceLedger, new_nonce
from token_registry_sqlite import TokenRegistry, fingerprint
from atomic_signed_proof_issuer import AtomicSignedProofIssuer, ProofIssuanceError
from staging_issuance_drain import (
    IssuanceDrainGate, IssuanceGateClosed, IssuanceDrainTimeout
)

NOW = 1800000000000
OLD = "TEST-DRAIN-EXPOSED-OLD-CREDENTIAL-0123456789ABCDEF"
NEW = "TEST-DRAIN-ROTATED-NEW-CREDENTIAL-0123456789ABCDEF"
BACKUP = "TEST-DRAIN-STANDBY-BACKUP-CREDENTIAL-0123456789ABCDEF"
OLD_ID, NEW_ID, BACKUP_ID = "DRAIN-OLD", "DRAIN-NEW", "DRAIN-BACKUP"


class Signer:
    def __init__(self, behavior="ok"):
        self.calls = 0
        self.behavior = behavior

    def sign(self, _):
        self.calls += 1
        if self.behavior == "throw":
            raise RuntimeError("synthetic_signing_failure")
        return b"x" * 64


class GateTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.ledger = NonceLedger(Path(self.temp.name) / "drain.sqlite")
        self.registry = TokenRegistry(self.ledger)
        for value, tid, role in ((OLD, OLD_ID, "exposed_old"),
                                 (NEW, NEW_ID, "new"),
                                 (BACKUP, BACKUP_ID, "backup")):
            self.registry.add(value, token_id=tid, kind="dev", role=role,
                              issued_ms=NOW, expires_ms=NOW + 3600000)
        self.nonce = new_nonce()
        self.ledger.register(self.nonce, kind="dev",
                             candidate_fingerprint=fingerprint(NEW),
                             token_id=NEW_ID, issued_ms=NOW,
                             expires_ms=NOW + 60000)
        self.gate = IssuanceDrainGate()
        self.signer = Signer()
        self.issuer = AtomicSignedProofIssuer(
            self.registry, self.signer,
            lambda session, token_id, kind: (
                session == "staging" and token_id == NEW_ID and kind == "dev"
            ), now_ms=lambda: NOW,
        )
        self.args = dict(session="staging", nonce=self.nonce,
                         token_id=NEW_ID, kind="dev",
                         candidate_fingerprint=fingerprint(NEW),
                         exposed_old_token_id=OLD_ID)

    def swap(self):
        return self.registry.activate_backup(BACKUP_ID, now_ms=NOW)

    def readback(self):
        return (self.registry.authorize(NEW, kind="dev", now_ms=NOW)["status"] == 403
                and self.registry.authorize(BACKUP, kind="dev", now_ms=NOW)["status"] == 200)

    def test_01_initial_admission_open(self):
        self.assertEqual(self.gate.status(), {
            "frozen": False, "admin_active": False, "active_issuances": 0
        })

    def test_02_real_atomic_issuer_runs_through_admission(self):
        p = self.gate.issue(self.issuer, **self.args)
        self.assertEqual(p["token_id"], NEW_ID)
        self.assertEqual(self.signer.calls, 1)
        self.assertEqual(self.ledger.counts(), (1, 1))
        self.assertEqual(self.gate.status()["active_issuances"], 0)

    def test_03_admin_cutover_revokes_new_while_preserving_old_policy(self):
        self.assertTrue(self.gate.guarded_admin_change(
            self.swap, self.readback, timeout_s=1))
        self.assertFalse(self.gate.status()["frozen"])
        self.assertEqual(self.registry.authorize(
            OLD, kind="dev", now_ms=NOW)["status"], 200)
        with self.assertRaisesRegex(ProofIssuanceError, "challenge_or_token_not_usable"):
            self.gate.issue(self.issuer, **self.args)
        self.assertEqual(self.signer.calls, 0)

    def test_04_admin_must_wait_for_inflight_and_fence_new_admissions(self):
        entered, release, changed = threading.Event(), threading.Event(), threading.Event()

        def prior_issue():
            with self.gate.admission():
                entered.set()
                self.assertTrue(release.wait(timeout=3))

        def admin():
            def action():
                changed.set()
                return self.swap()
            return self.gate.guarded_admin_change(action, self.readback,
                                                  timeout_s=2)
        try:
            with ThreadPoolExecutor(max_workers=2) as pool:
                issuer_future = pool.submit(prior_issue)
                self.assertTrue(entered.wait(timeout=1))
                admin_future = pool.submit(admin)
                for _ in range(100):
                    if self.gate.status()["frozen"]:
                        break
                    time.sleep(0.005)
                self.assertTrue(self.gate.status()["frozen"])
                self.assertFalse(changed.is_set())
                with self.assertRaisesRegex(IssuanceGateClosed, "issuance_frozen"):
                    with self.gate.admission():
                        pass
                release.set()
                issuer_future.result(timeout=3)
                self.assertTrue(admin_future.result(timeout=3))
                self.assertTrue(changed.is_set())
                self.assertTrue(self.readback())
        finally:
            release.set()

    def test_05_drain_timeout_stays_frozen_and_no_mutation(self):
        entered, release = threading.Event(), threading.Event()
        try:
            with ThreadPoolExecutor(max_workers=1) as pool:
                def held():
                    with self.gate.admission():
                        entered.set()
                        release.wait(timeout=3)
                future = pool.submit(held)
                self.assertTrue(entered.wait(timeout=1))
                called = []
                with self.assertRaisesRegex(IssuanceDrainTimeout, "drain_timeout_frozen"):
                    self.gate.guarded_admin_change(
                        lambda: called.append("called") or True,
                        lambda: True, timeout_s=0.01)
                self.assertEqual(called, [])
                self.assertTrue(self.gate.status()["frozen"])
                release.set()
                future.result(timeout=3)
                self.assertTrue(self.gate.status()["frozen"])
        finally:
            release.set()

    def test_06_failing_admin_write_does_not_unfreeze(self):
        with self.assertRaisesRegex(IssuanceGateClosed, "admin_change_not_confirmed"):
            self.gate.guarded_admin_change(lambda: False, lambda: True)
        self.assertTrue(self.gate.status()["frozen"])
        with self.assertRaises(IssuanceGateClosed):
            self.gate.issue(self.issuer, **self.args)
        self.assertEqual(self.signer.calls, 0)

    def test_07_admin_exception_does_not_unfreeze(self):
        def broken():
            raise OSError("synthetic unknown commit")
        with self.assertRaises(OSError):
            self.gate.guarded_admin_change(broken, lambda: True)
        self.assertTrue(self.gate.status()["frozen"])

    def test_08_readback_failed_leaves_gate_frozen(self):
        self.assertRaisesRegex(
            IssuanceGateClosed, "admin_readback_failed",
            self.gate.guarded_admin_change, self.swap, lambda: False)
        self.assertTrue(self.gate.status()["frozen"])
        self.assertTrue(self.readback())

    def test_09_reconcile_requires_verified_readback(self):
        with self.assertRaises(IssuanceGateClosed):
            self.gate.guarded_admin_change(lambda: False, lambda: True)
        with self.assertRaisesRegex(IssuanceGateClosed, "reconciliation_failed_frozen"):
            self.gate.reconcile_and_resume(lambda: False)
        self.assertTrue(self.gate.status()["frozen"])
        self.assertTrue(self.gate.reconcile_and_resume(lambda: True))
        self.assertFalse(self.gate.status()["frozen"])

    def test_10_reconcile_while_active_request_is_rejected(self):
        with self.gate.admission():
            with self.assertRaisesRegex(IssuanceGateClosed, "reconciliation_not_safe"):
                self.gate.reconcile_and_resume(lambda: True)

    def test_11_signer_failure_releases_admission_slot(self):
        bad = AtomicSignedProofIssuer(
            self.registry, Signer("throw"),
            lambda *_: True, now_ms=lambda: NOW,
        )
        with self.assertRaises(ProofIssuanceError):
            self.gate.issue(bad, **self.args)
        self.assertEqual(self.gate.status()["active_issuances"], 0)
        self.assertEqual(self.ledger.counts(), (1, 1))

    def test_12_repeated_admin_change_cannot_override_frozen_state(self):
        self.assertRaises(IssuanceGateClosed,
                          self.gate.guarded_admin_change,
                          lambda: False, lambda: True)
        with self.assertRaisesRegex(IssuanceGateClosed, "gate_already_frozen"):
            self.gate.guarded_admin_change(self.swap, self.readback)

    def test_13_invalid_timeout_never_freezes(self):
        with self.assertRaises(ValueError):
            self.gate.guarded_admin_change(self.swap, self.readback,
                                           timeout_s=-1)
        self.assertFalse(self.gate.status()["frozen"])

    def test_14_non_boolean_readback_rejected(self):
        with self.assertRaises(IssuanceGateClosed):
            self.gate.guarded_admin_change(lambda: True, lambda: 1)
        self.assertTrue(self.gate.status()["frozen"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
