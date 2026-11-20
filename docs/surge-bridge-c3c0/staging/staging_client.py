#!/usr/bin/env python3
"""C3-C0 staging client (runs on the VPS, loopback only).

Reads /opt/c3c0-staging/config.json (0600) for the synthetic pairing secret
and token values (to compute fingerprints — token values never leave the VPS
and are never printed). Talks real HTTPS to 127.0.0.1:18443 with the staging
CA pinned. Verifies returned proofs against the synthetic Ed25519 test
public key. Prints only status codes, fingerprints (prefixes), and counts.
"""
import base64
import concurrent.futures
import json
import os
import ssl
import sys
import urllib.error
import urllib.request

BASE = "/opt/c3c0-staging"
sys.path.insert(0, BASE)
from nonce_ledger_sqlite import NonceLedger, new_nonce
from token_registry_sqlite import TokenRegistry, fingerprint


def load_cfg():
    with open(os.path.join(BASE, "config.json")) as f:
        return json.load(f)


def client_ctx(cfg, ca_path=None):
    return ssl.create_default_context(cafile=ca_path or cfg["tls_ca"])


def send(cfg, body, secret=None, ctx=None, path="/credential-proof"):
    url = "https://127.0.0.1:%d%s" % (cfg["port"], path)
    raw = json.dumps(body, separators=(",", ":")).encode()
    req = urllib.request.Request(url, data=raw, method="POST")
    req.add_header("Content-Type", "application/json")
    if secret is not None:
        req.add_header("Authorization", "Bearer " + secret)
    try:
        with urllib.request.urlopen(
                req, context=ctx or client_ctx(cfg), timeout=10) as resp:
            return resp.status, json.loads(resp.read())
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read())
    except Exception as e:  # TLS failure, connection failure, ...
        return None, {"error": type(e).__name__, "detail": str(e)[:200]}


def proof_body(cfg, token_id, nonce=None):
    return {
        "nonce": nonce or new_nonce(),
        "kind": "dev",
        "token_id": token_id,
        "candidate_fingerprint": fingerprint(cfg["tokens"][token_id]),
    }


def verify_proof(cfg, proof):
    from cryptography.hazmat.primitives import serialization
    with open(cfg["ed25519_key"], "rb") as f:
        priv = serialization.load_pem_private_key(f.read(), password=None)
    pub = priv.public_key()
    signed = {k: v for k, v in proof.items() if k != "signature"}
    raw = json.dumps(signed, separators=(",", ":"), ensure_ascii=True).encode()
    try:
        pub.verify(base64.b64decode(proof["signature"]), raw)
        return True
    except Exception:
        return False


def verify_proof_wrong_key(cfg, proof):
    from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
    other = Ed25519PrivateKey.generate().public_key()
    signed = {k: v for k, v in proof.items() if k != "signature"}
    raw = json.dumps(signed, separators=(",", ":"), ensure_ascii=True).encode()
    try:
        other.verify(base64.b64decode(proof["signature"]), raw)
        return True  # BAD: verified against a different key
    except Exception:
        return False  # GOOD: rejected


def counts(cfg):
    ledger = NonceLedger(cfg["db_path"])
    registry = TokenRegistry(ledger)
    return ledger.counts(), registry.audit_counts()


def main():
    cfg = load_cfg()
    cmd = sys.argv[1] if len(sys.argv) > 1 else "help"
    if cmd == "proof":
        token_id = sys.argv[2] if len(sys.argv) > 2 else cfg["new_token_id"]
        code, data = send(cfg, proof_body(cfg, token_id), secret=cfg["pairing_secret"])
        print("proof token=%s -> HTTP %s" % (token_id, code))
        if code == 200:
            print("  token_id:", data.get("token_id"),
                  "| nonce fp prefix:", data.get("nonce", "")[:8],
                  "| verify vs test pubkey:", verify_proof(cfg, data),
                  "| verify vs WRONG pubkey:", verify_proof_wrong_key(cfg, data))
            print("  proof keys:", sorted(data.keys()))
        else:
            print("  body:", data)
        print("  counts (total, consumed):", counts(cfg)[0], "| audit:", counts(cfg)[1])
    elif cmd == "proof-nonce":
        token_id, nonce = sys.argv[2], sys.argv[3]
        code, data = send(cfg, proof_body(cfg, token_id, nonce=nonce),
                          secret=cfg["pairing_secret"])
        print("proof-nonce token=%s nonce=%s.. -> HTTP %s body=%s" % (
            token_id, nonce[:8], code, data if code != 200 else "proof(200)"))
        if code == 200:
            print("  verify vs test pubkey:", verify_proof(cfg, data))
        print("  counts:", counts(cfg)[0])
    elif cmd == "no-auth":
        code, data = send(cfg, proof_body(cfg, cfg["new_token_id"]), secret=None)
        print("no-auth -> HTTP %s body=%s counts=%s" % (code, data, counts(cfg)[0]))
    elif cmd == "wrong-auth":
        bad = "X" * 64
        code, data = send(cfg, proof_body(cfg, cfg["new_token_id"]), secret=bad)
        print("wrong-auth -> HTTP %s body=%s counts=%s" % (code, data, counts(cfg)[0]))
    elif cmd == "wrong-ca":
        ctx = client_ctx(cfg, ca_path=cfg["tls_ca_wrong"])
        code, data = send(cfg, proof_body(cfg, cfg["new_token_id"]),
                          secret=cfg["pairing_secret"], ctx=ctx)
        print("wrong-ca -> HTTP %s body=%s" % (code, data))
    elif cmd == "no-ca-verify":
        ctx = ssl._create_unverified_context()
        code, data = send(cfg, proof_body(cfg, cfg["new_token_id"]),
                          secret=cfg["pairing_secret"], ctx=ctx)
        print("no-ca-verify (unverified ctx) -> HTTP %s" % code)
        if code == 200:
            print("  NOTE: unverified client succeeds (client-side bypass, expected);"
                  " server still requires the pinned pairing bearer")
    elif cmd == "concurrent":
        token_id = sys.argv[2] if len(sys.argv) > 2 else cfg["new_token_id"]
        nonce = new_nonce()
        body = proof_body(cfg, token_id, nonce=nonce)
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as ex:
            futs = [ex.submit(send, cfg, dict(body), secret=cfg["pairing_secret"])
                    for _ in range(2)]
            results = [f.result() for f in futs]
        codes = sorted(r[0] for r in results)
        print("concurrent same-nonce token=%s nonce=%s.. -> codes=%s" % (
            token_id, nonce[:8], codes))
        print("  exactly one 200 and one 409:", codes == [200, 409])
        print("  counts:", counts(cfg)[0])
    elif cmd == "counts":
        c, a = counts(cfg)
        print("ledger counts (total, consumed):", c)
        print("registry audit:", a)
    else:
        print("usage: staging_client.py "
              "proof [TOKEN_ID] | proof-nonce TOKEN_ID NONCE | no-auth | "
              "wrong-auth | wrong-ca | no-ca-verify | concurrent [TOKEN_ID] | counts")


if __name__ == "__main__":
    main()
