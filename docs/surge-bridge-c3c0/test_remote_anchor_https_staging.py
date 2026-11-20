"""Issue73: actual dual HTTPS socket TLS, signed anchor CAS, and PR115.

Synthetic tokens/keys and 127.0.0.1 listeners only. Both listeners share
the CI host: does NOT prove a separate rollback-resistant failure domain.
"""
from __future__ import annotations

import json
import sqlite3
import ssl
import tempfile
import threading
import unittest
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import HTTPSHandler, ProxyHandler, Request, build_opener

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

from nonce_ledger_sqlite import NonceLedger, new_nonce
from token_registry_sqlite import TokenRegistry, fingerprint
from credential_proof_https import LoopbackTLSServer, serve_in_thread
from recovery_signed_checkpoint import logical_state_sha256
from staging_recovery_fenced_https import StagingRecoveryFencedHTTPSService
from remote_anchor_https_staging import (
    AnchorAuthorityStore, LoopbackAnchorTLSServer, PinnedAnchorTLSClient,
    RemoteAnchorDenied,
)
import test_credential_proof_https as tlsfixture

NOW = 1800000000000
OLD = "TEST-REMOTE-EXPOSED-OLD-TOKEN-0123456789ABCDE"
NEW = "TEST-REMOTE-ROTATED-NEW-TOKEN-0123456789ABCDE"
BACKUP = "TEST-REMOTE-BACKUP-TOKEN-0123456789ABCDEFGHI"
OLD_ID, NEW_ID, BACKUP_ID = "REMOTE-OLD", "REMOTE-NEW", "REMOTE-BACKUP"
PAIR = "TEST_REMOTE_PROOF_PAIRING_0123456789_ABCDEFGHIJKLMNOPQRSTUVWXYZ"
AUTH = "TEST_REMOTE_ANCHOR_BEARER_0123456789_ABCDEFGHIJKLMNOPQRSTUVWXYZ"
BAD = "TEST_REMOTE_ANCHOR_BEARER_0123456789_ZYXWVUTSRQPONMLKJIHGFEDCBA"


class RemoteTLSIntegration(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        tlsfixture.HTTPSProofTests.setUpClass()
        cls.server_tls = tlsfixture.HTTPSProofTests.server_ctx
        cls.client_tls = tlsfixture.HTTPSProofTests.client_ctx
        cls.cert_path = tlsfixture.HTTPSProofTests.cert_file

    @classmethod
    def tearDownClass(cls):
        tlsfixture.HTTPSProofTests.tearDownClass()

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        (root / "business").mkdir(mode=0o700)
        (root / "anchor-test").mkdir(mode=0o700)
        self.db = root / "business" / "tokens.sqlite"
        self.anchor_db = root / "anchor-test" / "epoch.sqlite"
        self.ledger = NonceLedger(self.db)
        self.registry = TokenRegistry(self.ledger)
        for val,tid,role in (
            (OLD,OLD_ID,"exposed_old"),
            (NEW,NEW_ID,"new"),
            (BACKUP,BACKUP_ID,"backup"),
        ):
            self.assertTrue(self.registry.add(
                val, token_id=tid, kind="dev", role=role,
                issued_ms=NOW, expires_ms=NOW+86400000))
        self.private_proof = Ed25519PrivateKey.generate()
        self.private_anchor = Ed25519PrivateKey.generate()
        self.anchor_pub = self.private_anchor.public_key().public_bytes(
            encoding=serialization.Encoding.Raw,
            format=serialization.PublicFormat.Raw)
        self.store = AnchorAuthorityStore(self.anchor_db, self.private_anchor)
        self.assertTrue(self.store.bootstrap(
            logical_state_sha256(self.ledger), authorized_offline=True))
        self.anchor_listener = LoopbackAnchorTLSServer(
            self.store, bearer=AUTH, tls_context=self.server_tls)
        self.anchor_thread = serve_in_thread(self.anchor_listener)
        self.addCleanup(self.close_anchor)
        self.anchor_url = "https://localhost:%d" % self.anchor_listener.server_port
        self.client = self.new_client()
        record, epoch = self.client.fetch_head(self.ledger)
        self.assertEqual(epoch, 1)
        self.assertEqual(record["state_sha256"], logical_state_sha256(self.ledger))
        self.proof_service = self.new_proof_service()
        self.proof_listener = LoopbackTLSServer(self.proof_service, self.server_tls)
        self.proof_thread = serve_in_thread(self.proof_listener)
        self.addCleanup(self.close_proof)
        self.proof_url = "https://localhost:%d/credential-proof" % self.proof_listener.server_port
        self.http = build_opener(ProxyHandler({}), HTTPSHandler(context=self.client_tls))

    def close_anchor(self):
        self.anchor_listener.shutdown()
        self.anchor_listener.server_close()
        self.anchor_thread.join(timeout=3)
        self.assertFalse(self.anchor_thread.is_alive())

    def close_proof(self):
        self.proof_listener.shutdown()
        self.proof_listener.server_close()
        self.proof_thread.join(timeout=3)
        self.assertFalse(self.proof_thread.is_alive())

    def new_client(self, *, root=None, bearer=AUTH, ca=None):
        return PinnedAnchorTLSClient(
            self.anchor_url, bearer=bearer,
            ca_cert_file=str(ca or self.cert_path),
            pinned_ed25519_key=self.anchor_pub if root is None else root)

    def new_proof_service(self):
        return StagingRecoveryFencedHTTPSService(
            self.registry, self.ledger, self.private_proof,
            pairing_secret=PAIR, old_token_id=OLD_ID,
            clock_ms=lambda: NOW,
            commit_and_fetch_anchor=lambda: self.client.commit_and_fetch_anchor(self.ledger),
        )

    def open_from_remote_head(self):
        record, epoch = self.client.fetch_head(self.ledger)
        return self.proof_service.open_after_trusted_recovery(
            record, trusted_external_epoch=epoch,
            independently_pinned_public_key=self.anchor_pub)

    def body(self, **updates):
        b = {
            "nonce": new_nonce(), "kind": "dev",
            "token_id": NEW_ID, "candidate_fingerprint": fingerprint(NEW),
        }
        b.update(updates)
        return b

    def proof_request(self, body=None, *, auth=PAIR):
        raw = json.dumps(self.body() if body is None else body,
                         separators=(",", ":")).encode("ascii")
        req = Request(
            self.proof_url, data=raw, method="POST",
            headers={"Authorization": "Bearer "+auth,
                     "Content-Type": "application/json"})
        try:
            with self.http.open(req, timeout=4) as r:
                return r.status, json.loads(r.read())
        except HTTPError as exc:
            return exc.code, json.loads(exc.read())

    def anchor_request(self, *, body=None, path="/advance", bearer=AUTH):
        url = self.anchor_url + path
        req = Request(
            url, method="GET" if body is None else "POST",
            data=None if body is None else json.dumps(body).encode(),
            headers={"Authorization": "Bearer "+bearer,
                     "Content-Type": "application/json"})
        try:
            with self.http.open(req, timeout=3) as r:
                return r.status, json.loads(r.read())
        except HTTPError as exc:
            return exc.code, json.loads(exc.read())

    @staticmethod
    def backup(source, dest):
        with sqlite3.connect(source) as src, sqlite3.connect(dest) as out:
            src.backup(out)

    def test_01_two_real_tls_listeners_and_signed_remote_head(self):
        self.assertNotEqual(self.anchor_listener.server_port,
                            self.proof_listener.server_port)
        self.assertEqual(self.anchor_request(path="/head")[0], 200)
        self.assertEqual(self.store.head()["epoch"], 1)
        self.assertTrue(self.proof_service.gate.status()["frozen"])

    def test_02_external_signed_commit_before_http_200(self):
        self.open_from_remote_head()
        code, proof = self.proof_request()
        self.assertEqual(code, 200)
        self.assertEqual(proof["token_id"], NEW_ID)
        self.assertEqual(self.client._known_epoch, 2)
        self.assertEqual(self.store.head()["epoch"], 2)
        self.assertTrue(self.proof_service.gate.status()["frozen"])
        self.assertEqual(self.proof_request()[0], 503)

    def test_03_next_verified_remote_head_reopens_frozen_service(self):
        self.open_from_remote_head()
        self.assertEqual(self.proof_request()[0], 200)
        self.assertTrue(self.open_from_remote_head())
        self.assertEqual(self.proof_request()[0], 200)
        self.assertEqual(self.store.head()["epoch"], 3)

    def test_04_server_rejects_stale_epoch_without_advancing(self):
        h=self.store.head()
        data={"expected_epoch": 1, "expected_digest": h["state_sha256"],
              "state_sha256": "0"*64}
        self.assertEqual(self.anchor_request(body=data)[0], 200)
        self.assertEqual(self.anchor_request(body=data)[0], 409)
        self.assertEqual(self.store.head()["epoch"], 2)

    def test_05_wrong_bearer_does_not_update_state(self):
        h=self.store.head()
        data={"expected_epoch": 1, "expected_digest": h["state_sha256"],
              "state_sha256": "0"*64}
        self.assertEqual(self.anchor_request(body=data,bearer=BAD)[0],401)
        self.assertEqual(self.anchor_request(path="/head",bearer=BAD)[0],401)
        self.assertEqual(self.store.head()["epoch"],1)

    def test_06_wrong_tls_ca_rejected(self):
        bad_context=ssl.create_default_context()
        op=build_opener(ProxyHandler({}), HTTPSHandler(context=bad_context))
        req=Request(self.anchor_url+"/head",
                    headers={"Authorization":"Bearer "+AUTH})
        with self.assertRaises(URLError):
            op.open(req,timeout=3)
        self.assertEqual(self.store.head()["epoch"],1)

    def test_07_wrong_pinned_ed25519_key_rejected(self):
        wrong=Ed25519PrivateKey.generate().public_key().public_bytes(
            encoding=serialization.Encoding.Raw,
            format=serialization.PublicFormat.Raw)
        client=self.new_client(root=wrong)
        with self.assertRaisesRegex(RemoteAnchorDenied,
                                    "remote_signature_or_state_mismatch"):
            client.fetch_head(self.ledger)
        self.assertEqual(self.store.head()["epoch"],1)

    def test_08_snapshot_rollback_denied_by_remote_head_after_restart(self):
        before=self.db.parent/"old.sqlite"
        self.backup(self.db,before)
        self.open_from_remote_head()
        self.assertEqual(self.proof_request()[0],200)
        self.backup(before,self.db)
        restart_client=self.new_client()
        with self.assertRaisesRegex(RemoteAnchorDenied,
                                    "remote_signature_or_state_mismatch"):
            restart_client.fetch_head(self.ledger)
        self.assertEqual(self.store.head()["epoch"],2)
        self.assertTrue(self.new_proof_service().gate.status()["frozen"])

    def test_09_external_network_down_never_returns_signed_proof(self):
        self.open_from_remote_head()
        self.anchor_listener.shutdown()
        self.anchor_listener.server_close()
        self.anchor_thread.join(timeout=3)
        # avoid cleanup double-close by recreating the listener on same
        # saved synthetic store with a new ephemeral test port.
        self.anchor_listener=LoopbackAnchorTLSServer(
            self.store,bearer=AUTH,tls_context=self.server_tls)
        self.anchor_thread=serve_in_thread(self.anchor_listener)
        # Simulate unavailable remote URL instead of contacting the new port.
        code,body=self.proof_request()
        self.assertEqual((code,body),
                         (503,{"status":"external_anchor_unknown_frozen"}))
        self.assertTrue(self.proof_service.gate.status()["frozen"])
        self.assertEqual(self.store.head()["epoch"],1)
        self.assertEqual(self.ledger.counts(),(1,1))

    def test_10_remote_commit_unknown_must_be_reconciled_not_retried(self):
        self.open_from_remote_head()
        orig=self.client._request
        def commit_then_timeout(suffix,data=None):
            if suffix=="/advance":
                r=orig(suffix,data)
                raise RemoteAnchorDenied("simulated_response_lost_after_commit")
            return orig(suffix,data)
        self.client._request=commit_then_timeout
        code,body=self.proof_request()
        self.assertEqual(code,503)
        self.assertEqual(body,{"status":"external_anchor_unknown_frozen"})
        self.assertEqual(self.store.head()["epoch"],2)
        self.assertEqual(self.ledger.counts(),(1,1))
        self.assertTrue(self.proof_service.gate.status()["frozen"])
        self.client._request=orig
        self.assertTrue(self.open_from_remote_head())
        self.assertEqual(self.proof_request()[0],200)

    def test_11_auth_failure_no_nonce_no_anchor_writes(self):
        self.open_from_remote_head()
        self.assertEqual(self.proof_request(auth=BAD)[0],401)
        self.assertEqual(self.store.head()["epoch"],1)
        self.assertEqual(self.ledger.counts(),(0,0))

    def test_12_no_remote_bootstrap_or_reset_http_route(self):
        self.assertEqual(self.anchor_request(path="/bootstrap",
                                             body={"state_sha256":"0"*64})[0],404)
        self.assertEqual(self.anchor_request(path="/reset",
                                             body={"epoch":1})[0],404)
        self.assertEqual(self.store.head()["epoch"],1)

    def test_13_duplicate_fields_rejected_without_state_write(self):
        raw=('{"expected_epoch":1,"expected_epoch":2,'
             '"expected_digest":"'+self.store.head()["state_sha256"]+'",'
             '"state_sha256":"'+("0"*64)+'"}').encode()
        req=Request(self.anchor_url+"/advance",data=raw,method="POST",
                    headers={"Authorization":"Bearer "+AUTH,
                             "Content-Type":"application/json"})
        with self.assertRaises(HTTPError) as e:
            self.http.open(req,timeout=3)
        self.assertEqual(e.exception.code,400)
        self.assertEqual(self.store.head()["epoch"],1)

    def test_14_repeated_offline_bootstrap_cannot_reset_epoch(self):
        h=self.store.head()
        self.store.advance(expected_epoch=1,
                           expected_digest=h["state_sha256"],
                           state_sha256="1"*64)
        self.assertFalse(self.store.bootstrap("0"*64,
                                              authorized_offline=True))
        self.assertEqual(self.store.head()["epoch"],2)

    def test_15_server_restart_persists_monotonic_epoch(self):
        h=self.store.head()
        self.store.advance(expected_epoch=1,expected_digest=h["state_sha256"],
                           state_sha256="2"*64)
        resumed=AnchorAuthorityStore(self.anchor_db,self.private_anchor)
        self.assertEqual(resumed.head()["epoch"],2)
        self.assertFalse(resumed.bootstrap("0"*64,authorized_offline=True))

    def test_16_old_remote_anchor_snapshot_can_be_replayed_if_same_domain(self):
        copy=self.anchor_db.parent/"anchor-before.sqlite"
        self.backup(self.anchor_db,copy)
        h=self.store.head()
        self.store.advance(expected_epoch=1,
                           expected_digest=h["state_sha256"],
                           state_sha256="3"*64)
        self.backup(copy,self.anchor_db)
        # Independent durable fault-domain is a REAL prerequisite.
        self.assertEqual(self.store.head()["epoch"],1)
        # This is an expected failure demonstration, NOT security PASS.


if __name__=="__main__":
    unittest.main(verbosity=2)
