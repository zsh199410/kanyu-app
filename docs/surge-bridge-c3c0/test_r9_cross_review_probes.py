#!/usr/bin/env python3
"""Round 9 cross-review probes (independent of GPT's own suites).

P1: WebView probe reports insecure_context when isSecureContext=false even
    when a mocked crypto.subtle would pass all checks; reports no_webcrypto
    when isSecureContext is true/undefined and subtle is absent.
P2: Atomic issuer (Round 8/9) signs a proof -> Pure-JS verifier (Round 9)
    accepts it; tampered copy rejected. Cross-language canonical-JSON check.
P3: Real LoopbackTLSServer end-to-end: valid HTTPS request -> proof that
    the Pure-JS verifier accepts; same-nonce replay -> 409, no proof.
P4: LoopbackTLSServer refuses non-loopback binding and TLS < 1.2.
P5: Wrong/missing pairing bearer -> 401 with ZERO ledger writes.
"""
import json
import os
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

# Node helper lives next to this probe file so CI can run P2/P3 too.
NODE_HELPER = os.path.join(HERE, "test_r9_js_verify_helper.js")
NOW = 1790000000000
OLD = "TEST-OLD-EXPOSED-CREDENTIAL-0123456789ABCDE"
NEW = "TEST-NEW-ROTATED-CREDENTIAL-0123456789ABCDE"
BACKUP = "TEST-STANDBY-BACKUP-CREDENTIAL-0123456789ABC"
OLD_ID = "TEST-OLD-ID"
NEW_ID = "TEST-NEW-ID"
BACKUP_ID = "TEST-BACKUP-ID"


def run_node(script, cwd=HERE):
    r = subprocess.run(["node", "-e", script], cwd=cwd, capture_output=True,
                       text=True, timeout=60)
    return r


class TestR9CrossReview(unittest.TestCase):
    def test_p1_insecure_context_precedence(self):
        script = r"""
const fs = require("fs");
const vm = require("vm");
const src = fs.readFileSync("surge_webview_crypto_probe.template.js", "utf8");
function runProbe(isSecure, subtle) {
  let written = null, done = 0;
  const subtleObj = subtle ? {
    digest: async (alg, data) => {
      const hex = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855";
      const out = new Uint8Array(32);
      for (let i = 0; i < 32; i++) out[i] = parseInt(hex.slice(2*i, 2*i+2), 16);
      return out.buffer;
    },
    importKey: async () => ({}),
    verify: async (alg, key, sig, msg) => sig[0] === 0,
  } : undefined;
  const ctx = vm.createContext({
    isSecureContext: isSecure,
    crypto: subtle ? { subtle: subtleObj, getRandomValues: (b) => b } : undefined,
    TextEncoder,
    atob: (s) => Buffer.from(s, "base64").toString("binary"),
    $trigger: "editor",
    $persistentStore: { write: (v, k) => { written = v; }, read: () => null },
    $done: () => { done++; },
  });
  vm.runInNewContext(src, ctx);
  return { written, done };
}
let a = runProbe(false, true);
assert.strictEqual(a.written, "insecure_context");
assert.strictEqual(a.done, 1);
let b = runProbe(true, false);
assert.strictEqual(b.written, "no_webcrypto");
let c = runProbe(undefined, false);
assert.strictEqual(c.written, "no_webcrypto");
console.log("P1 OK", JSON.stringify({a, b, c}));
"""
        r = run_node(script)
        self.assertEqual(r.returncode, 0, r.stderr[-2000:])
        self.assertIn("P1 OK", r.stdout)

    def test_p2_atomic_issuer_to_purejs_verifier(self):
        from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
        from nonce_ledger_sqlite import NonceLedger, new_nonce
        from token_registry_sqlite import TokenRegistry, fingerprint
        from atomic_signed_proof_issuer import AtomicSignedProofIssuer

        tmp = tempfile.mkdtemp(prefix="r9p2-")
        db = os.path.join(tmp, "t.db")
        ledger = NonceLedger(db)
        registry = TokenRegistry(ledger)
        self.assertTrue(registry.add(OLD, kind="dev", token_id=OLD_ID,
                                     role="exposed_old", issued_ms=NOW,
                                     expires_ms=NOW + 3600000))
        self.assertTrue(registry.add(NEW, kind="dev", token_id=NEW_ID,
                                     role="new", issued_ms=NOW,
                                     expires_ms=NOW + 86400000))
        key = Ed25519PrivateKey.generate()
        pub_hex = key.public_key().public_bytes_raw().hex()
        candidate = NEW
        fp = fingerprint(candidate)
        sentinel = object()
        issuer = AtomicSignedProofIssuer(
            registry, key,
            lambda session, _tid, _kind: session is sentinel,
            now_ms=lambda: NOW)
        nonce = new_nonce()
        self.assertTrue(ledger.register(
            nonce, kind="dev", candidate_fingerprint=fp, token_id=NEW_ID,
            issued_ms=NOW, expires_ms=NOW + 60000))
        proof = issuer.issue(session=sentinel, nonce=nonce, token_id=NEW_ID,
                             kind="dev", candidate_fingerprint=fp,
                             exposed_old_token_id=OLD_ID)
        opts = {"candidate": candidate, "kind": "dev", "oldTokenId": OLD_ID,
                "expectedNonce": nonce, "pinnedPublicKeyHex": pub_hex,
                "now": NOW}
        with open("/tmp/r9_xlang_proof.json", "w") as f:
            json.dump({"proof": proof, "opts": opts}, f)
        tampered = dict(proof)
        tampered["fingerprint"] = "0" * 64
        with open("/tmp/r9_xlang_tampered.json", "w") as f:
            json.dump({"proof": tampered, "opts": opts}, f)
        r = subprocess.run(["node", NODE_HELPER, "/tmp/r9_xlang_proof.json"],
                           cwd=HERE, capture_output=True, text=True, timeout=60)
        self.assertEqual(r.returncode, 0, r.stderr[-2000:])
        self.assertIn("VERIFY true", r.stdout)
        r2 = subprocess.run(["node", NODE_HELPER, "/tmp/r9_xlang_tampered.json"],
                            cwd=HERE, capture_output=True, text=True, timeout=60)
        self.assertEqual(r2.returncode, 0, r2.stderr[-2000:])
        self.assertIn("VERIFY false", r2.stdout)

    def test_p3_https_end_to_end_then_purejs_verify(self):
        import ipaddress
        import ssl
        from urllib.request import Request, urlopen
        from urllib.error import HTTPError
        from cryptography import x509
        from cryptography.hazmat.primitives import hashes, serialization
        from cryptography.hazmat.primitives.asymmetric import rsa, ed25519
        from cryptography.x509.oid import NameOID
        import datetime
        from nonce_ledger_sqlite import NonceLedger, new_nonce
        from token_registry_sqlite import TokenRegistry, fingerprint
        from credential_proof_https import HTTPSProofService, LoopbackTLSServer, serve_in_thread

        tmp = tempfile.mkdtemp(prefix="r9p3-")
        db = os.path.join(tmp, "t.db")
        ledger = NonceLedger(db)
        registry = TokenRegistry(ledger)
        self.assertTrue(registry.add(OLD, kind="dev", token_id=OLD_ID,
                                     role="exposed_old", issued_ms=NOW,
                                     expires_ms=NOW + 3600000))
        self.assertTrue(registry.add(NEW, kind="dev", token_id=NEW_ID,
                                     role="new", issued_ms=NOW,
                                     expires_ms=NOW + 86400000))
        sign_key = ed25519.Ed25519PrivateKey.generate()
        pub_hex = sign_key.public_key().public_bytes_raw().hex()
        candidate = NEW
        fp = fingerprint(candidate)
        pairing = "A" * 64
        service = HTTPSProofService(registry, ledger, sign_key,
                                    pairing_secret=pairing, old_token_id=OLD_ID,
                                    clock_ms=lambda: NOW)
        rsa_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "localhost")])
        cert = (x509.CertificateBuilder().subject_name(name).issuer_name(name)
                .public_key(rsa_key.public_key())
                .serial_number(x509.random_serial_number())
                .not_valid_before(datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=1))
                .not_valid_after(datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(days=1))
                .add_extension(x509.SubjectAlternativeName(
                    [x509.DNSName("localhost"),
                     x509.IPAddress(ipaddress.ip_address("127.0.0.1"))]), critical=False)
                .sign(rsa_key, hashes.SHA256()))
        cert_pem = cert.public_bytes(serialization.Encoding.PEM)
        key_pem = rsa_key.private_bytes(serialization.Encoding.PEM,
                                        serialization.PrivateFormat.PKCS8,
                                        serialization.NoEncryption())
        cert_path = os.path.join(tmp, "cert.pem")
        key_path = os.path.join(tmp, "key.pem")
        with open(cert_path, "wb") as f:
            f.write(cert_pem)
        with open(key_path, "wb") as f:
            f.write(key_pem)
        ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        ctx.minimum_version = ssl.TLSVersion.TLSv1_2
        ctx.load_cert_chain(cert_path, key_path)
        server = LoopbackTLSServer(service, ctx, ("127.0.0.1", 0))
        port = server.server_address[1]
        thread = serve_in_thread(server)
        try:
            client_ctx = ssl.create_default_context(cadata=cert_pem.decode())
            nonce = new_nonce()
            body = json.dumps({"nonce": nonce, "kind": "dev",
                               "token_id": NEW_ID,
                               "candidate_fingerprint": fp}).encode()
            req = Request(f"https://localhost:{port}/credential-proof",
                          data=body, method="POST",
                          headers={"Content-Type": "application/json",
                                   "Authorization": "Bearer " + pairing})
            with urlopen(req, context=client_ctx, timeout=10) as resp:
                self.assertEqual(resp.status, 200)
                proof = json.loads(resp.read())
            opts = {"candidate": candidate, "kind": "dev", "oldTokenId": OLD_ID,
                    "expectedNonce": nonce, "pinnedPublicKeyHex": pub_hex,
                    "now": NOW}
            with open("/tmp/r9_https_proof.json", "w") as f:
                json.dump({"proof": proof, "opts": opts}, f)
            r = subprocess.run(["node", NODE_HELPER, "/tmp/r9_https_proof.json"],
                               cwd=HERE, capture_output=True, text=True, timeout=60)
            self.assertEqual(r.returncode, 0, r.stderr[-2000:])
            self.assertIn("VERIFY true", r.stdout)
            req2 = Request(f"https://localhost:{port}/credential-proof",
                           data=body, method="POST",
                           headers={"Content-Type": "application/json",
                                    "Authorization": "Bearer " + pairing})
            try:
                with urlopen(req2, context=client_ctx, timeout=10) as resp2:
                    self.fail("replay should not return 200")
            except HTTPError as e:
                self.assertEqual(e.code, 409)
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=5)

    def test_p4_loopback_binding_and_tls_minimum(self):
        import ssl
        from nonce_ledger_sqlite import NonceLedger
        from token_registry_sqlite import TokenRegistry
        from credential_proof_https import HTTPSProofService, LoopbackTLSServer
        from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

        tmp = tempfile.mkdtemp(prefix="r9p4-")
        db = os.path.join(tmp, "t.db")
        ledger = NonceLedger(db)
        registry = TokenRegistry(ledger)
        key = Ed25519PrivateKey.generate()
        service = HTTPSProofService(registry, ledger, key,
                                    pairing_secret="B" * 64,
                                    old_token_id=OLD_ID)
        ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        ctx.minimum_version = ssl.TLSVersion.TLSv1_2
        with self.assertRaises(ValueError):
            LoopbackTLSServer(service, ctx, ("0.0.0.0", 0))
        with self.assertRaises(ValueError):
            LoopbackTLSServer(service, ctx, ("192.168.1.1", 0))
        weak = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        weak.minimum_version = ssl.TLSVersion.TLSv1_1
        with self.assertRaises(ValueError):
            LoopbackTLSServer(service, weak, ("127.0.0.1", 0))
        ok = LoopbackTLSServer(service, ctx, ("127.0.0.1", 0))
        ok.server_close()

    def test_p5_wrong_bearer_zero_writes(self):
        from nonce_ledger_sqlite import NonceLedger, new_nonce
        from token_registry_sqlite import TokenRegistry, fingerprint
        from credential_proof_https import HTTPSProofService
        from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

        tmp = tempfile.mkdtemp(prefix="r9p5-")
        db = os.path.join(tmp, "t.db")
        ledger = NonceLedger(db)
        registry = TokenRegistry(ledger)
        key = Ed25519PrivateKey.generate()
        service = HTTPSProofService(registry, ledger, key,
                                    pairing_secret="C" * 64,
                                    old_token_id=OLD_ID,
                                    clock_ms=lambda: NOW)
        nonce = new_nonce()
        fp = fingerprint(NEW)
        body = json.dumps({"nonce": nonce, "kind": "dev",
                           "token_id": NEW_ID,
                           "candidate_fingerprint": fp}).encode()
        code, _ = service.handle(body=body, authorization="Bearer " + "D" * 64,
                                 content_type="application/json")
        self.assertEqual(code, 401)
        code, _ = service.handle(body=body, authorization=None,
                                 content_type="application/json")
        self.assertEqual(code, 401)
        self.assertEqual(ledger.counts(), (0, 0))


if __name__ == "__main__":
    unittest.main(verbosity=2)
