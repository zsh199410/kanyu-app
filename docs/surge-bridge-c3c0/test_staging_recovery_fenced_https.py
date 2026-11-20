"""Issue73 real localhost TLS gate integration; synthetic-only.

This test verifies that admission covers the ENTIRE HTTPS request,
including nonce registration, and that startup/restarts remain frozen
without independently supplied signed anchor+epoch.
An in-memory test signer/epoch represents an EXTERNAL service contract,
not proof that a real rollback-resistant control plane exists.
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
from urllib.error import HTTPError
from urllib.request import Request, urlopen

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

import test_credential_proof_https as fixtures
from credential_proof_https import LoopbackTLSServer, serve_in_thread
from nonce_ledger_sqlite import NonceLedger, new_nonce
from recovery_signed_checkpoint import (
    PURPOSE, _canonical, logical_state_sha256,
    require_signed_recovery_checkpoint,
)
from staging_issuance_drain import IssuanceGateClosed
from staging_recovery_fenced_https import StagingRecoveryFencedHTTPSService
from token_registry_sqlite import TokenRegistry, fingerprint

NOW = 1800000000000
PAIR = "TESTSTAGINGINDEPENDENTPAIRINGKEY_0123456789_ABCDEF_9876543210"
OLD = "TEST-HTTPS-FENCED-OLD-0123456789-ABCDEFGHIJKLMNOP"
NEW = "TEST-HTTPS-FENCED-NEW-0123456789-ABCDEFGHIJKLMNOP"
BACKUP = "TEST-HTTPS-FENCED-BACKUP-0123456789-ABCDEFGHIJKL"
OLD_ID, NEW_ID, BACKUP_ID = "FENCED-OLD", "FENCED-NEW", "FENCED-BACKUP"


class BlockingSigner:
    def __init__(self):
        self.key = Ed25519PrivateKey.generate()
        self.entered = threading.Event()
        self.release = threading.Event()
        self.block = False
    def sign(self, message):
        if self.block:
            self.entered.set()
            if not self.release.wait(timeout=5):
                raise RuntimeError("synthetic_time_limit")
        return self.key.sign(message)


class RealTLSFenceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        fixtures.HTTPSProofTests.setUpClass()
        cls.server_ctx = fixtures.HTTPSProofTests.server_ctx
        cls.client_ctx = fixtures.HTTPSProofTests.client_ctx

    @classmethod
    def tearDownClass(cls):
        fixtures.HTTPSProofTests.tearDownClass()

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name) / "fenced.sqlite"
        self.ledger = NonceLedger(self.path)
        self.registry = TokenRegistry(self.ledger)
        for token,tid,role in (
            (OLD,OLD_ID,"exposed_old"),(NEW,NEW_ID,"new"),
            (BACKUP,BACKUP_ID,"backup")
        ):
            self.assertTrue(self.registry.add(
                token, token_id=tid, kind="dev",role=role,
                issued_ms=NOW, expires_ms=NOW+3600000
            ))
        self.signer=BlockingSigner()
        self.anchor_signer=Ed25519PrivateKey.generate()
        self.anchor_pub=self.anchor_signer.public_key().public_bytes(
            encoding=serialization.Encoding.Raw,
            format=serialization.PublicFormat.Raw
        )
        # In-memory external anchor fixture, NOT a production
        # rollback-resistant epoch authority or remote signer.
        self.external_epoch = 1
        self.external_record = self.checkpoint(1)
        self.service=StagingRecoveryFencedHTTPSService(
            self.registry,self.ledger,self.signer,pairing_secret=PAIR,
            old_token_id=OLD_ID,clock_ms=lambda:NOW,
            commit_and_fetch_anchor=self.external_commit,
        )
        self.server=LoopbackTLSServer(self.service,self.server_ctx)
        self.thread=serve_in_thread(self.server)
        self.url="https://localhost:%d/credential-proof"%self.server.server_port
        self.addCleanup(self.cleanup_server)

    def cleanup_server(self):
        self.signer.release.set()
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=3)
        self.assertFalse(self.thread.is_alive())

    def body(self, **updates):
        data={"nonce":new_nonce(),"kind":"dev","token_id":NEW_ID,
              "candidate_fingerprint":fingerprint(NEW)}
        data.update(updates)
        return data

    def request(self, body=None, *, secret=PAIR):
        raw=json.dumps(body if body is not None else self.body(),
                       separators=(",",":")).encode("utf8")
        req=Request(self.url,data=raw,method="POST",
                    headers={"Content-Type":"application/json",
                             "Authorization":"Bearer "+secret})
        try:
            with urlopen(req,context=self.client_ctx,timeout=7) as rsp:
                return rsp.status,json.loads(rsp.read())
        except HTTPError as exc:
            return exc.code,json.loads(exc.read())

    def checkpoint(self, epoch):
        digest=logical_state_sha256(self.ledger)
        signature=self.anchor_signer.sign(_canonical(PURPOSE,epoch,digest))
        return {"purpose":PURPOSE,"epoch":epoch,"state_sha256":digest,
                "signature":base64.b64encode(signature).decode("ascii")}

    def external_commit(self):
        self.external_epoch += 1
        self.external_record = self.checkpoint(self.external_epoch)
        return self.external_record, self.external_epoch

    def open(self, epoch=1, record=None, *, key=None):
        return self.service.open_after_trusted_recovery(
            self.checkpoint(epoch) if record is None else record,
            trusted_external_epoch=epoch,
            independently_pinned_public_key=self.anchor_pub if key is None else key)

    def test_01_listener_starts_frozen_no_auth_or_ledger_mutation(self):
        self.assertEqual(self.request()[0],503)
        self.assertEqual(self.ledger.counts(),(0,0))
        self.assertTrue(self.service.gate.status()["frozen"])

    def test_02_wrong_pinned_key_keeps_https_closed(self):
        wrong=Ed25519PrivateKey.generate().public_key().public_bytes(
            encoding=serialization.Encoding.Raw,format=serialization.PublicFormat.Raw)
        with self.assertRaisesRegex(IssuanceGateClosed,"trusted_recovery_failed_frozen"):
            self.open(key=wrong)
        self.assertEqual(self.request()[0],503)
        self.assertEqual(self.ledger.counts(),(0,0))

    def test_03_verified_anchor_allows_one_real_tls_proof_then_freezes(self):
        self.assertTrue(self.open())
        first=self.request()
        self.assertEqual(first[0],200)
        self.assertEqual(first[1]["token_id"],NEW_ID)
        self.assertEqual(self.ledger.counts(),(1,1))
        self.assertTrue(self.service.gate.status()["frozen"])
        self.assertEqual(self.request()[0],503)
        self.assertEqual(self.ledger.counts(),(1,1))

    def test_04_after_fresh_external_anchor_next_tls_proof_possible(self):
        self.open()
        self.assertEqual(self.request()[0],200)
        self.assertTrue(self.open(epoch=2))
        self.assertEqual(self.request()[0],200)
        self.assertEqual(self.ledger.counts(),(2,2))
        self.assertTrue(self.service.gate.status()["frozen"])

    def test_05_unauthorized_request_never_writes_and_does_not_freeze(self):
        self.open()
        self.assertEqual(self.request(secret="TEST-WRONG-INDEPENDENT-PAIRING-0123456789ABCDEF")[0],401)
        self.assertEqual(self.ledger.counts(),(0,0))
        self.assertFalse(self.service.gate.status()["frozen"])

    def test_06_old_token_denial_burns_nonce_and_freezes(self):
        self.open()
        code,_=self.request(self.body(
            token_id=OLD_ID,candidate_fingerprint=fingerprint(OLD)))
        self.assertEqual(code,403)
        self.assertEqual(self.ledger.counts(),(1,0))
        self.assertTrue(self.service.gate.status()["frozen"])

    def test_07_rollback_db_snapshot_detected_before_reopening_https(self):
        self.open()
        snapshot=Path(self.temp.name)/"pre-consume.sqlite"
        with sqlite3.connect(self.path) as origin, sqlite3.connect(snapshot) as dest:
            origin.backup(dest)
        self.assertEqual(self.request()[0],200)
        newest=self.checkpoint(2)
        with sqlite3.connect(snapshot) as origin, sqlite3.connect(self.path) as dest:
            origin.backup(dest)
        self.assertEqual(self.ledger.counts(),(0,0))
        with self.assertRaisesRegex(IssuanceGateClosed,"trusted_recovery_failed_frozen"):
            self.open(2,newest)
        self.assertEqual(self.request()[0],503)
        self.assertEqual(self.ledger.counts(),(0,0))

    def test_08_old_signed_checkpoint_cannot_match_new_epoch(self):
        old=self.checkpoint(1)
        with self.assertRaisesRegex(IssuanceGateClosed,"trusted_recovery_failed_frozen"):
            self.open(2,old)
        self.assertEqual(self.request()[0],503)

    def test_09_real_tls_inflight_signer_drains_before_revoke(self):
        self.open()
        self.signer.block=True
        def admin_change():
            def check():
                return (self.registry.authorize(NEW,kind="dev",now_ms=NOW)["status"]==403
                        and self.registry.authorize(BACKUP,kind="dev",now_ms=NOW)["status"]==200)
            return self.service.guarded_admin_change(
                authorized_change=lambda:self.registry.activate_backup(
                    BACKUP_ID,now_ms=NOW),
                authoritative_readback=check,
                timeout_s=4)
        with ThreadPoolExecutor(max_workers=2) as pool:
            first=pool.submit(self.request,self.body())
            self.assertTrue(self.signer.entered.wait(timeout=3))
            admin=pool.submit(admin_change)
            try:
                for _ in range(200):
                    if self.service.gate.status()["frozen"]:
                        break
                    time.sleep(.005)
                self.assertTrue(self.service.gate.status()["frozen"])
                self.assertFalse(admin.done())
                self.assertEqual(self.request()[0],503)
                self.assertEqual(self.ledger.counts(),(1,1))
            finally:
                self.signer.release.set()
            self.assertEqual(first.result(timeout=5)[0],200)
            self.assertTrue(admin.result(timeout=5))
        self.assertEqual(self.registry.authorize(NEW,kind="dev",now_ms=NOW)["status"],403)
        self.assertEqual(self.registry.authorize(BACKUP,kind="dev",now_ms=NOW)["status"],200)

    def test_10_failed_external_anchor_during_admin_keeps_frozen(self):
        self.open()
        self.service._anchor_commit = lambda: (_ for _ in ()).throw(
            OSError("synthetic external authority unavailable"))
        with self.assertRaises(OSError):
            self.service.guarded_admin_change(
                authorized_change=lambda:self.registry.activate_backup(
                    BACKUP_ID,now_ms=NOW),
                authoritative_readback=lambda:True)
        self.assertTrue(self.service.gate.status()["frozen"])
        self.assertEqual(self.request()[0],503)

    def test_11_actual_signer_failure_burns_nonce_and_fences_future_https(self):
        self.open()
        class ThrowingSigner:
            def sign(self, _):
                raise RuntimeError("synthetic_signer_failure")
        self.service.issuer.signer = ThrowingSigner()
        # The nonce is already committed as consumed when signer fails.
        self.assertEqual(self.request()[0],403)
        self.assertEqual(self.request()[0],503)
        self.assertEqual(self.ledger.counts(),(1,1))

    def test_12_new_listener_again_starts_frozen_after_old_service(self):
        # New object, same registry+ledger: cannot inherit previous
        # in-memory gate's OPEN state after kill/restart.
        self.open()
        second=StagingRecoveryFencedHTTPSService(
            self.registry,self.ledger,self.signer,pairing_secret=PAIR,
            old_token_id=OLD_ID,clock_ms=lambda:NOW,
            commit_and_fetch_anchor=self.external_commit)
        self.assertTrue(second.gate.status()["frozen"])
        self.assertEqual(second.handle(
            body=json.dumps(self.body()).encode(),authorization="Bearer "+PAIR,
            content_type="application/json")[0],503)
        self.assertEqual(self.ledger.counts(),(0,0))

    def test_13_external_commit_unavailable_withholds_http_200_proof(self):
        self.open()
        self.service._anchor_commit = lambda: (_ for _ in ()).throw(
            OSError("synthetic external authority down"))
        code, response = self.request()
        self.assertEqual(code,503)
        self.assertEqual(response,{"status":"external_anchor_unknown_frozen"})
        self.assertEqual(self.ledger.counts(),(1,1))
        self.assertTrue(self.service.gate.status()["frozen"])
        self.assertEqual(self.request()[0],503)

    def test_14_nonincreasing_epoch_withholds_signed_proof(self):
        self.open()
        self.service._anchor_commit = lambda: (self.checkpoint(1),1)
        self.assertEqual(self.request()[0],503)
        self.assertEqual(self.ledger.counts(),(1,1))
        self.assertTrue(self.service.gate.status()["frozen"])

    def test_15_alternate_public_root_cannot_reopen_existing_gate(self):
        self.open()
        self.assertEqual(self.request()[0],200)
        alternative=Ed25519PrivateKey.generate().public_key().public_bytes(
            encoding=serialization.Encoding.Raw,
            format=serialization.PublicFormat.Raw,
        )
        with self.assertRaisesRegex(IssuanceGateClosed,
                                    "trusted_root_changed_frozen"):
            self.open(2,key=alternative)
        self.assertEqual(self.request()[0],503)

    def test_16_valid_anchor_after_external_commit_is_required_for_resume(self):
        self.open()
        self.assertEqual(self.request()[0],200)
        bad=dict(self.external_record, state_sha256="0"*64)
        with self.assertRaisesRegex(IssuanceGateClosed,
                                    "trusted_recovery_failed_frozen"):
            self.open(epoch=2,record=bad)
        self.assertTrue(self.service.gate.status()["frozen"])
        self.assertTrue(self.open(2,record=self.external_record))
        self.assertFalse(self.service.gate.status()["frozen"])


if __name__=="__main__":
    unittest.main(verbosity=2)
