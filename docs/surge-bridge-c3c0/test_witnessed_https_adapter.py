"""Real loopback TLS + temporary independent witness test double.

These tests use ephemeral certificates and synthetic tokens, NOT a
remote authenticated monotonic epoch service and NOT an iPhone.
"""
from __future__ import annotations

import base64
import datetime
import ipaddress
import json
import sqlite3
import ssl
import tempfile
import unittest
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa, ed25519
from cryptography.x509.oid import NameOID

from credential_proof_https import LoopbackTLSServer, serve_in_thread
from nonce_ledger_sqlite import NonceLedger, new_nonce
from token_registry_sqlite import TokenRegistry, fingerprint
from recovery_signed_checkpoint import logical_state_sha256
from staging_issuance_drain import IssuanceDrainGate, IssuanceGateClosed
from witnessed_credential_proof_https import WitnessedHTTPSProofService
from witness_fenced_issuer_reference import IndependentWitnessTestDouble, WitnessRejected

NOW = 1800000000000
OLD = "TEST-WITNESS-HTTPS-OLD-TOKEN-0123456789ABCDEFGHIJKL"
NEW = "TEST-WITNESS-HTTPS-NEW-TOKEN-0123456789ABCDEFGHIJKL"
BACKUP = "TEST-WITNESS-HTTPS-BACKUP-TOKEN-0123456789ABCDEFG"
OLD_ID, NEW_ID, BACKUP_ID = "HTTPS-WIT-OLD", "HTTPS-WIT-NEW", "HTTPS-WIT-BACKUP"
PAIR = "TEST_WITNESS_PAIRING_BEARER_" + "A" * 60
BAD = "TEST_WITNESS_PAIRING_BEARER_" + "B" * 60


class CountSigner:
    def __init__(self):
        self.key = ed25519.Ed25519PrivateKey.generate()
        self.calls = 0

    def sign(self, payload):
        self.calls += 1
        return self.key.sign(payload)


class WitnessHTTPS(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tls_temp = tempfile.TemporaryDirectory()
        cls.root = Path(cls.tls_temp.name)
        key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        subject = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "localhost")])
        cert = (x509.CertificateBuilder()
            .subject_name(subject).issuer_name(subject)
            .public_key(key.public_key()).serial_number(x509.random_serial_number())
            .not_valid_before(datetime.datetime.now(datetime.timezone.utc) -
                              datetime.timedelta(days=1))
            .not_valid_after(datetime.datetime.now(datetime.timezone.utc) +
                             datetime.timedelta(days=1))
            .add_extension(x509.SubjectAlternativeName([
                x509.DNSName("localhost"),
                x509.IPAddress(ipaddress.ip_address("127.0.0.1"))
            ]), critical=False)
            .sign(private_key=key, algorithm=hashes.SHA256()))
        cls.cert_path = cls.root / "synthetic.crt"
        cls.key_path = cls.root / "synthetic.key"
        cls.cert_path.write_bytes(cert.public_bytes(serialization.Encoding.PEM))
        cls.key_path.write_bytes(key.private_bytes(
            serialization.Encoding.PEM,
            serialization.PrivateFormat.PKCS8,
            serialization.NoEncryption()))
        cls.tls = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        cls.tls.minimum_version = ssl.TLSVersion.TLSv1_2
        cls.tls.load_cert_chain(str(cls.cert_path), str(cls.key_path))
        cls.client_tls = ssl.create_default_context(cafile=str(cls.cert_path))

    @classmethod
    def tearDownClass(cls):
        cls.tls_temp.cleanup()

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        (root / "business").mkdir(mode=0o700)
        (root / "witness").mkdir(mode=0o700)
        self.db = root / "business" / "tokens.sqlite"
        self.witness_file = root / "witness" / "epoch.sqlite"
        self.ledger = NonceLedger(self.db)
        self.registry = TokenRegistry(self.ledger)
        for value, tid, role in (
            (OLD, OLD_ID, "exposed_old"),
            (NEW, NEW_ID, "new"),
            (BACKUP, BACKUP_ID, "backup"),
        ):
            self.assertTrue(self.registry.add(
                value, kind="dev", role=role, token_id=tid,
                issued_ms=NOW, expires_ms=NOW + 3600000))
        self.witness = IndependentWitnessTestDouble(self.witness_file)
        self.assertTrue(self.witness.bootstrap(
            logical_state_sha256(self.ledger),
            trusted_operator_approved=True))
        self.gate = IssuanceDrainGate()
        self.signer = CountSigner()
        self.service = self.new_service()
        self.server = LoopbackTLSServer(self.service, self.tls)
        self.thread = serve_in_thread(self.server)
        self.url = "https://localhost:%d/credential-proof" % self.server.server_port

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=3)
        self.assertFalse(self.thread.is_alive())
        self.tmp.cleanup()

    def new_service(self):
        return WitnessedHTTPSProofService(
            self.registry, self.ledger, self.signer,
            pairing_secret=PAIR, old_token_id=OLD_ID,
            witness=self.witness, gate=self.gate,
            clock_ms=lambda: NOW)

    @staticmethod
    def backup(a, b):
        with sqlite3.connect(a) as old, sqlite3.connect(b) as new:
            old.backup(new)

    def body(self, nonce=None, **changes):
        return dict(
            nonce=nonce or new_nonce(), kind="dev", token_id=NEW_ID,
            candidate_fingerprint=fingerprint(NEW)
        ) | changes

    def send(self, body=None, *, pairing=PAIR, raw=None, cert_ctx=None):
        if raw is None:
            raw = json.dumps(body or self.body(), separators=(",", ":")).encode()
        request = Request(
            self.url, data=raw,
            headers={"Authorization": "Bearer " + pairing,
                     "Content-Type": "application/json"},
            method="POST")
        try:
            with urlopen(request, context=cert_ctx or self.client_tls,
                         timeout=3) as result:
                return result.status, json.loads(result.read())
        except HTTPError as exc:
            return exc.code, json.loads(exc.read())

    def test_01_true_https_uses_witness_before_signature(self):
        code, proof = self.send()
        self.assertEqual(code, 200)
        canonical = json.dumps(
            {k: v for k, v in proof.items() if k != "signature"},
            separators=(",", ":"), ensure_ascii=True).encode()
        self.signer.key.public_key().verify(
            base64.b64decode(proof["signature"]), canonical)
        self.assertEqual(self.witness.counts(), (1, 0))
        self.assertEqual(self.witness.head()["epoch"], 3)
        self.assertEqual(self.signer.calls, 1)
        self.assertIsNone(self.service.issuer)

    def test_02_missing_or_wrong_pairing_does_not_write(self):
        self.assertEqual(self.send(pairing="")[0], 401)
        self.assertEqual(self.send(pairing=BAD)[0], 401)
        self.assertEqual(self.ledger.counts(), (0, 0))
        self.assertEqual(self.witness.head()["epoch"], 1)
        self.assertEqual(self.signer.calls, 0)

    def test_03_duplicate_nonce_over_https_returns_200_then_409(self):
        proof = self.body()
        self.assertEqual(self.send(proof)[0], 200)
        self.assertEqual(self.send(proof)[0], 409)
        self.assertEqual(self.signer.calls, 1)
        self.assertEqual(self.witness.counts(), (1, 0))

    def test_04_old_db_backup_rollback_blocks_http_signer(self):
        copy = self.db.parent / "precommit.sqlite"
        self.backup(self.db, copy)
        data = self.body()
        self.assertEqual(self.send(data)[0], 200)
        self.backup(copy, self.db)
        status, detail = self.send(data)
        self.assertEqual(status, 503)
        self.assertEqual(detail, {"status": "nonce_store_unknown"})
        self.assertEqual(self.signer.calls, 1)

    def test_05_old_db_backup_blocks_server_reinitialization(self):
        copy = self.db.parent / "precommit.sqlite"
        self.backup(self.db, copy)
        self.assertEqual(self.send()[0], 200)
        self.backup(copy, self.db)
        with self.assertRaisesRegex(WitnessRejected,
                                    "database_rollback_or_unknown_mutation"):
            self.new_service()

    def test_06_witness_registration_timeout_never_signs(self):
        original = self.witness.advance
        self.witness.advance = lambda *args, **kwargs: (
            (_ for _ in ()).throw(WitnessRejected("remote_witness_unavailable")))
        try:
            status, detail = self.send()
        finally:
            self.witness.advance = original
        self.assertEqual((status, detail), (503, {"status": "nonce_store_unknown"}))
        self.assertEqual(self.signer.calls, 0)
        self.assertEqual(self.ledger.counts(), (1, 0))
        self.assertEqual(self.send()[0], 503)

    def test_07_witness_postconsume_failure_refuses_signature(self):
        original = self.witness.advance
        count = [0]
        def fail_on_second(*args, **kwargs):
            count[0] += 1
            if count[0] == 2:
                raise WitnessRejected("remote_witness_commit_unknown")
            return original(*args, **kwargs)
        self.witness.advance = fail_on_second
        try:
            code, data = self.send()
        finally:
            self.witness.advance = original
        self.assertEqual((code, data), (403, {"status": "proof_not_authorized"}))
        self.assertEqual(self.signer.calls, 0)
        self.assertEqual(self.ledger.counts(), (1, 1))
        self.assertEqual(self.send()[0], 503)

    def test_08_privileged_backup_activation_fences_new_token(self):
        self.assertEqual(self.send()[0], 200)
        self.assertTrue(self.service.admin_activate_backup(
            BACKUP_ID, NEW_ID, now_ms=NOW))
        self.assertEqual(self.witness.counts(), (1, 1))
        self.assertEqual(self.send()[0], 403)
        code, proof = self.send(
            self.body(token_id=BACKUP_ID,
                      candidate_fingerprint=fingerprint(BACKUP)))
        self.assertEqual(code, 200)
        self.assertEqual(proof["token_id"], BACKUP_ID)
        self.assertEqual(self.witness.counts(), (2, 1))

    def test_09_nonloopback_public_bind_prohibited(self):
        with self.assertRaisesRegex(ValueError, "public_network_binding_not_authorized"):
            LoopbackTLSServer(self.service, self.tls, ("0.0.0.0", 0))

    def test_10_wrong_tls_ca_rejected_without_writing(self):
        wrong = ssl.create_default_context()
        with self.assertRaises(URLError):
            self.send(cert_ctx=wrong)
        self.assertEqual(self.witness.counts(), (0, 0))
        self.assertEqual(self.ledger.counts(), (0, 0))

    def test_11_unbootstrapped_witness_prevents_listener_setup(self):
        other_file = self.witness_file.parent / "notbootstrapped.sqlite"
        other = IndependentWitnessTestDouble(other_file)
        with self.assertRaisesRegex(WitnessRejected, "witness_not_bootstrapped"):
            WitnessedHTTPSProofService(
                self.registry, self.ledger, self.signer,
                pairing_secret=PAIR, old_token_id=OLD_ID,
                witness=other, gate=IssuanceDrainGate(),
                clock_ms=lambda: NOW)

    def test_12_failed_admin_readback_prevents_reopening_gate(self):
        self.assertEqual(self.send()[0], 200)
        with self.assertRaisesRegex(IssuanceGateClosed,
                                    "admin_readback_failed_frozen"):
            self.service.witnessed_service.admin_transition(
                lambda: self.registry.activate_backup(
                    BACKUP_ID, now_ms=NOW),
                lambda: False, revoked_token_id=NEW_ID)
        self.assertTrue(self.gate.status()["frozen"])
        self.assertEqual(self.send()[0], 503)


    def test_13_admin_freeze_covers_nonce_registration_before_signing(self):
        """A request stalled before nonce registration cannot bypass drain."""
        entered = threading.Event()
        release = threading.Event()
        original = self.service._register_nonce

        def delayed_registration(*args, **kwargs):
            entered.set()
            if not release.wait(timeout=3):
                raise RuntimeError("synthetic_registration_delay_timeout")
            return original(*args, **kwargs)

        self.service._register_nonce = delayed_registration
        try:
            with ThreadPoolExecutor(max_workers=2) as ex:
                first = ex.submit(self.send, self.body())
                self.assertTrue(entered.wait(timeout=2))
                admin = ex.submit(
                    self.service.admin_activate_backup,
                    BACKUP_ID, NEW_ID, now_ms=NOW)
                for _ in range(150):
                    if self.gate.status()["frozen"]:
                        break
                    time.sleep(.005)
                self.assertTrue(self.gate.status()["frozen"])
                code, data = self.send(self.body())
                self.assertEqual((code, data),
                                 (503, {"status": "issuance_frozen"}))
                self.assertEqual(self.ledger.counts(), (0, 0))
                release.set()
                # This request had already passed outer admission before
                # admin freeze; its inner registration is rejected by the
                # existing generic nonce-store failure mapping.
                self.assertEqual(first.result(timeout=3),
                                 (503, {"status": "nonce_store_unknown"}))
                self.assertTrue(admin.result(timeout=3))
                self.assertEqual(self.ledger.counts(), (0, 0))
                self.assertEqual(self.signer.calls, 0)
        finally:
            release.set()
            self.service._register_nonce = original

    def test_14_http_frozen_gate_rejects_even_before_bad_credentials(self):
        with self.assertRaisesRegex(WitnessRejected, "admin_change_failed_frozen"):
            # The deliberately failed admin operation freezes the gate.
            self.service.witnessed_service.admin_transition(
                lambda: False, lambda: True)
        self.assertTrue(self.gate.status()["frozen"])
        self.assertEqual(
            self.send(pairing=""),
            (503, {"status": "issuance_frozen"}))
        self.assertEqual(self.ledger.counts(), (0, 0))


if __name__ == "__main__":
    unittest.main(verbosity=2)
