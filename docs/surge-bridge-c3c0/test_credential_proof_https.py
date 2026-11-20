"""Actual localhost TLS/SQLite/Ed25519 boundary regression tests.

Only ephemeral test certificate and signing keys, no production tokens or URL.
All requests use stdlib urllib over REAL HTTPS and verify the test TLS chain.
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
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa, ed25519
from cryptography.x509.oid import NameOID

from nonce_ledger_sqlite import NonceLedger, new_nonce
from token_registry_sqlite import TokenRegistry, fingerprint
from credential_proof_https import HTTPSProofService, LoopbackTLSServer, serve_in_thread

NOW = 1800000000000
OLD = "TEST-OLD-EXPOSED-CREDENTIAL-0123456789ABCDE"
NEW = "TEST-NEW-ROTATED-CREDENTIAL-0123456789ABCDE"
BACKUP = "TEST-STANDBY-BACKUP-CREDENTIAL-0123456789ABC"
OLD_ID = "TEST-OLD-ID"
NEW_ID = "TEST-NEW-ID"
BACKUP_ID = "TEST-BACKUP-ID"
PAIR = "SYNTHETIC_PAIRING_ONLY_FOR_TESTS_0123456789ABCDEFG"
BAD_PAIR = "WRONG_PAIRING_SECRET_FOR_TESTS_0123456789ABCDEFG"


class HTTPSProofTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tls_temp = tempfile.TemporaryDirectory()
        root = Path(cls.tls_temp.name)
        tls_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        subject = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "localhost")])
        cert = (
            x509.CertificateBuilder()
            .subject_name(subject).issuer_name(subject)
            .public_key(tls_key.public_key())
            .serial_number(x509.random_serial_number())
            .not_valid_before(datetime.datetime.now(datetime.timezone.utc) -
                              datetime.timedelta(days=1))
            .not_valid_after(datetime.datetime.now(datetime.timezone.utc) +
                             datetime.timedelta(days=1))
            .add_extension(x509.SubjectAlternativeName([
                x509.DNSName("localhost"),
                x509.IPAddress(ipaddress.ip_address("127.0.0.1"))
            ]), critical=False)
            .sign(private_key=tls_key, algorithm=hashes.SHA256())
        )
        cls.cert_file = root / "ephemeral-tls.crt"
        cls.key_file = root / "ephemeral-tls.key"
        cls.cert_file.write_bytes(cert.public_bytes(serialization.Encoding.PEM))
        cls.key_file.write_bytes(tls_key.private_bytes(
            serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8,
            serialization.NoEncryption()))
        cls.server_ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        cls.server_ctx.minimum_version = ssl.TLSVersion.TLSv1_2
        cls.server_ctx.load_cert_chain(str(cls.cert_file), str(cls.key_file))
        cls.client_ctx = ssl.create_default_context(cafile=str(cls.cert_file))

    @classmethod
    def tearDownClass(cls):
        cls.tls_temp.cleanup()

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.ledger = NonceLedger(Path(self.temp.name) / "proof.sqlite")
        self.registry = TokenRegistry(self.ledger)
        self.assertTrue(self.registry.add(
            OLD, kind="dev", token_id=OLD_ID, role="exposed_old",
            issued_ms=NOW, expires_ms=NOW+3600000))
        self.assertTrue(self.registry.add(
            NEW, kind="dev", token_id=NEW_ID, role="new",
            issued_ms=NOW, expires_ms=NOW+86400000))
        self.assertTrue(self.registry.add(
            BACKUP, kind="dev", token_id=BACKUP_ID, role="backup",
            issued_ms=NOW, expires_ms=NOW+86400000))
        self.signer = ed25519.Ed25519PrivateKey.generate()
        self.service = HTTPSProofService(
            self.registry, self.ledger, self.signer, pairing_secret=PAIR,
            old_token_id=OLD_ID, clock_ms=lambda: NOW)
        self.server = LoopbackTLSServer(self.service, self.server_ctx)
        self.thread = serve_in_thread(self.server)
        self.url = "https://localhost:%d/credential-proof" % self.server.server_port

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=3)
        self.assertFalse(self.thread.is_alive())
        self.temp.cleanup()

    def body(self, **overrides):
        return {
            "nonce": new_nonce(), "kind": "dev", "token_id": NEW_ID,
            "candidate_fingerprint": fingerprint(NEW),
        } | overrides

    def send(self, body=None, *, secret=PAIR, content_type="application/json",
             path=None, method="POST", raw=None, headers=None):
        if raw is None:
            raw = json.dumps(
                body if body is not None else self.body(),
                separators=(",", ":")).encode()
        h = {"Content-Type":content_type, "Authorization":"Bearer "+secret}
        h.update(headers or {})
        req = Request(path or self.url, data=raw if method == "POST" else None,
                      headers=h, method=method)
        try:
            with urlopen(req, context=self.client_ctx, timeout=3) as response:
                return response.status, json.loads(response.read()), dict(response.headers)
        except HTTPError as exc:
            return exc.code, json.loads(exc.read()), dict(exc.headers)

    def test_01_true_https_success_and_ed25519_verified(self):
        code, data, headers = self.send()
        self.assertEqual(code, 200)
        self.assertEqual(data["token_id"], NEW_ID)
        self.assertEqual(headers["Cache-Control"], "no-store")
        signed = {k: v for k, v in data.items() if k != "signature"}
        raw = json.dumps(signed, separators=(",", ":"), ensure_ascii=True).encode()
        self.signer.public_key().verify(base64.b64decode(data["signature"]), raw)
        self.assertEqual(self.ledger.counts(), (1, 1))

    def test_02_same_nonce_rejected_with_409(self):
        body = self.body()
        self.assertEqual(self.send(body)[0], 200)
        code, data, _ = self.send(body)
        self.assertEqual((code, data), (409, {"status":"nonce_reused"}))
        self.assertEqual(self.ledger.counts(), (1, 1))

    def test_03_missing_pairing_token_never_writes_ledger(self):
        code, data, _ = self.send(headers={"Authorization":""})
        self.assertEqual(code, 401)
        self.assertEqual(data, {"status":"unauthorized"})
        self.assertEqual(self.ledger.counts(), (0, 0))

    def test_04_wrong_pairing_token_never_writes_ledger(self):
        self.assertEqual(self.send(secret=BAD_PAIR)[0], 401)
        self.assertEqual(self.ledger.counts(), (0, 0))

    def test_05_old_exposed_token_cannot_authorize_proof(self):
        code, _, _ = self.send(self.body(
            token_id=OLD_ID, candidate_fingerprint=fingerprint(OLD)))
        self.assertEqual(code, 403)
        self.assertEqual(self.ledger.counts(), (1, 0))

    def test_06_standby_backup_cannot_sign(self):
        code, _, _ = self.send(self.body(
            token_id=BACKUP_ID, candidate_fingerprint=fingerprint(BACKUP)))
        self.assertEqual(code, 403)
        self.assertEqual(self.ledger.counts(), (1, 0))

    def test_07_invalid_fingerprint_and_kind_rejected(self):
        self.assertEqual(self.send(self.body(candidate_fingerprint="0"*64))[0],403)
        self.assertEqual(self.send(self.body(kind="localkey"))[0],403)
        self.assertEqual(self.ledger.counts(), (2, 0))

    def test_08_revoke_new_then_endpoint_stops_signing(self):
        self.assertTrue(self.registry.activate_backup(BACKUP_ID, now_ms=NOW))
        self.assertEqual(self.send()[0], 403)
        self.assertEqual(self.ledger.counts(), (1, 0))
        self.assertEqual(self.send(self.body(token_id=BACKUP_ID,
            candidate_fingerprint=fingerprint(BACKUP)))[0], 200)

    def test_09_wrong_method_and_path_rejected(self):
        self.assertEqual(self.send(method="GET")[0], 405)
        self.assertEqual(self.send(path=self.url+"/wrong")[0], 404)
        self.assertEqual(self.ledger.counts(), (0, 0))

    def test_10_duplicate_json_fields_rejected(self):
        raw=b'{"nonce":"A","nonce":"B","kind":"dev","token_id":"X","candidate_fingerprint":"0"}'
        self.assertEqual(self.send(raw=raw)[0], 400)
        self.assertEqual(self.ledger.counts(), (0, 0))

    def test_11_extra_request_fields_rejected(self):
        self.assertEqual(self.send(self.body(credential="NOT_ALLOWED"))[0], 400)
        self.assertEqual(self.ledger.counts(), (0, 0))

    def test_12_wrong_media_type_and_oversize_rejected(self):
        self.assertEqual(self.send(content_type="text/plain")[0], 400)
        self.assertEqual(self.send(raw=b"x"*3000)[0], 413)
        self.assertEqual(self.ledger.counts(), (0, 0))

    def test_13_bad_nonce_encoding_rejected(self):
        self.assertEqual(self.send(self.body(nonce="abc"))[0], 400)
        self.assertEqual(self.ledger.counts(), (0, 0))

    def test_14_secret_not_reflected_in_json_or_headers(self):
        _, body, headers = self.send()
        all_output=json.dumps(body)+json.dumps(headers)
        self.assertNotIn(PAIR, all_output)
        self.assertNotIn(NEW, all_output)
        self.assertNotIn(OLD, all_output)

    def test_15_tls_client_rejects_server_without_trusted_cert(self):
        untrusted=ssl.create_default_context()
        req=Request(self.url,data=json.dumps(self.body()).encode(),
                    headers={"Authorization":"Bearer "+PAIR,
                             "Content-Type":"application/json"},
                    method="POST")
        with self.assertRaises(URLError):
            urlopen(req,context=untrusted,timeout=3)
        self.assertEqual(self.ledger.counts(),(0,0))

    def test_16_server_refuses_non_loopback_binding(self):
        with self.assertRaisesRegex(ValueError,"public_network_binding_not_authorized"):
            LoopbackTLSServer(self.service,self.server_ctx,("0.0.0.0",0))

    def test_17_service_rejects_missing_tls_prerequisites(self):
        with self.assertRaisesRegex(ValueError,"independent_high_entropy"):
            HTTPSProofService(self.registry,self.ledger,self.signer,
                pairing_secret="short",old_token_id=OLD_ID)
        with self.assertRaisesRegex(ValueError,"TLS_context_required"):
            LoopbackTLSServer(self.service,None)

    def test_18_database_failure_does_not_sign(self):
        class SpySigner:
            count=0
            def sign(self,_):
                self.count+=1
                return b"x"*64
        spy=SpySigner()
        self.server.proof_service.issuer.signer = spy
        # Inject a write blocker on the same database used by real handler.
        with sqlite3.connect(self.ledger.path) as db:
            db.execute("""CREATE TRIGGER deny_consume BEFORE UPDATE ON challenge
                          BEGIN SELECT RAISE(ABORT,'synthetic_failure'); END;""")
        code, response, _ = self.send()
        self.assertEqual(code,403)
        self.assertEqual(response,{"status":"proof_not_authorized"})
        self.assertEqual(self.ledger.counts(),(1,0))
        self.assertEqual(spy.count,0)

    def test_19_real_https_uses_loopback_tls_socket(self):
        self.assertEqual(self.server.server_address[0], "127.0.0.1")
        self.assertIsInstance(self.server.socket, ssl.SSLSocket)


if __name__ == "__main__":
    unittest.main(verbosity=2)
