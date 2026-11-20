#!/usr/bin/env python3
"""C3-C0 staging setup (RUN ONCE, on the VPS, synthetic credentials only).

Generates: pairing bearer, 3 synthetic test tokens, Ed25519 test keypair,
self-signed staging CA + server cert + a WRONG CA (negative test).
Registers OLD/NEW/BACKUP tokens in the staging SQLite DB.
Prints ONLY fingerprints (SHA-256 prefixes) and counts — never secret values.
"""
import hashlib
import json
import os
import secrets
import string
import subprocess
import sys
import time

BASE = "/opt/c3c0-staging"
TLS_DIR = os.path.join(BASE, "tls")
DATA_DIR = os.path.join(BASE, "data")
CONFIG = os.path.join(BASE, "config.json")
KEY_PEM = os.path.join(BASE, "ed25519_test_key.pem")

sys.path.insert(0, BASE)
from nonce_ledger_sqlite import NonceLedger
from token_registry_sqlite import TokenRegistry, fingerprint


def _fp(value: str) -> str:
    return hashlib.sha256(value.encode("ascii")).hexdigest()


def _rand_token(length: int = 48) -> str:
    alphabet = string.ascii_letters + string.digits + "!#$%&*+-=?@^_~"
    return "".join(secrets.choice(alphabet) for _ in range(length))


def _rand_pairing(length: int = 64) -> str:
    alphabet = string.ascii_letters + string.digits + "_-"
    return "".join(secrets.choice(alphabet) for _ in range(length))


def _run(cmd, **kw):
    r = subprocess.run(cmd, capture_output=True, text=True, **kw)
    if r.returncode != 0:
        print("SETUP FAIL:", " ".join(cmd), "\n", r.stdout, r.stderr, file=sys.stderr)
        sys.exit(1)
    return r


def main():
    os.makedirs(TLS_DIR, exist_ok=True)
    os.makedirs(DATA_DIR, exist_ok=True)
    now_ms = time.time_ns() // 1_000_000

    pairing = _rand_pairing()
    tok_old = _rand_token()
    tok_new = _rand_token()
    tok_backup = _rand_token()

    # Ed25519 test keypair (cryptography library).
    from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
    from cryptography.hazmat.primitives import serialization
    priv = Ed25519PrivateKey.generate()
    priv_pem = priv.private_bytes(
        serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8,
        serialization.NoEncryption())
    with open(KEY_PEM, "wb") as f:
        f.write(priv_pem)
    os.chmod(KEY_PEM, 0o600)
    pub_raw = priv.public_key().public_bytes(
        serialization.Encoding.Raw, serialization.PublicFormat.Raw)
    pub_fp = hashlib.sha256(pub_raw).hexdigest()

    # TLS: staging CA + server cert (SAN localhost + 127.0.0.1) + wrong CA.
    _run(["openssl", "req", "-x509", "-newkey", "rsa:2048",
          "-keyout", os.path.join(TLS_DIR, "staging-ca.key"),
          "-out", os.path.join(TLS_DIR, "staging-ca.crt"),
          "-days", "2", "-nodes", "-subj", "/CN=staging-test.invalid",
          "-addext", "basicConstraints=critical,CA:TRUE",
          "-addext", "keyUsage=critical,keyCertSign,cRLSign"])
    _run(["openssl", "req", "-newkey", "rsa:2048",
          "-keyout", os.path.join(TLS_DIR, "staging-server.key"),
          "-out", os.path.join(TLS_DIR, "staging-server.csr"),
          "-nodes", "-subj", "/CN=localhost"])
    with open(os.path.join(TLS_DIR, "server_ext.cnf"), "w") as f:
        f.write("subjectAltName=DNS:localhost,IP:127.0.0.1\n"
                "basicConstraints=CA:FALSE\n"
                "keyUsage=digitalSignature,keyEncipherment\n"
                "extendedKeyUsage=serverAuth\n")
    _run(["openssl", "x509", "-req",
          "-in", os.path.join(TLS_DIR, "staging-server.csr"),
          "-CA", os.path.join(TLS_DIR, "staging-ca.crt"),
          "-CAkey", os.path.join(TLS_DIR, "staging-ca.key"),
          "-CAcreateserial",
          "-out", os.path.join(TLS_DIR, "staging-server.crt"),
          "-days", "2",
          "-extfile", os.path.join(TLS_DIR, "server_ext.cnf")])
    _run(["openssl", "req", "-x509", "-newkey", "rsa:2048",
          "-keyout", os.path.join(TLS_DIR, "staging-ca-wrong.key"),
          "-out", os.path.join(TLS_DIR, "staging-ca-wrong.crt"),
          "-days", "2", "-nodes", "-subj", "/CN=staging-wrong.invalid",
          "-addext", "basicConstraints=critical,CA:TRUE",
          "-addext", "keyUsage=critical,keyCertSign,cRLSign"])
    for name in ("staging-ca.key", "staging-server.key", "staging-ca-wrong.key"):
        os.chmod(os.path.join(TLS_DIR, name), 0o600)

    def cert_fp(path):
        r = _run(["openssl", "x509", "-in", path, "-noout", "-fingerprint", "-sha256"])
        return r.stdout.strip().split("=", 1)[1].replace(":", "").lower()

    config = {
        "port": 18443,
        "host": "127.0.0.1",
        "db_path": os.path.join(DATA_DIR, "staging.sqlite"),
        "tls_cert": os.path.join(TLS_DIR, "staging-server.crt"),
        "tls_key": os.path.join(TLS_DIR, "staging-server.key"),
        "tls_ca": os.path.join(TLS_DIR, "staging-ca.crt"),
        "tls_ca_wrong": os.path.join(TLS_DIR, "staging-ca-wrong.crt"),
        "ed25519_key": KEY_PEM,
        "pairing_secret": pairing,
        "old_token_id": "STAGE-OLD-01",
        "new_token_id": "STAGE-NEW-01",
        "backup_token_id": "STAGE-BACKUP-01",
        "tokens": {"STAGE-OLD-01": tok_old,
                   "STAGE-NEW-01": tok_new,
                   "STAGE-BACKUP-01": tok_backup},
    }
    with open(CONFIG, "w") as f:
        json.dump(config, f, indent=2)
    os.chmod(CONFIG, 0o600)

    # Register the three synthetic tokens (setup-time admin only).
    ledger = NonceLedger(config["db_path"])
    registry = TokenRegistry(ledger)
    ok_old = registry.add(tok_old, kind="dev", token_id="STAGE-OLD-01",
                          role="exposed_old", issued_ms=now_ms,
                          expires_ms=now_ms + 24 * 3600 * 1000)
    ok_new = registry.add(tok_new, kind="dev", token_id="STAGE-NEW-01",
                          role="new", issued_ms=now_ms,
                          expires_ms=now_ms + 7 * 24 * 3600 * 1000)
    ok_bak = registry.add(tok_backup, kind="dev", token_id="STAGE-BACKUP-01",
                          role="backup", issued_ms=now_ms,
                          expires_ms=now_ms + 7 * 24 * 3600 * 1000)

    print("SETUP OK")
    print("pairing_secret sha256 prefix:", _fp(pairing)[:8], "len:", len(pairing))
    print("token STAGE-OLD-01 fingerprint prefix:", fingerprint(tok_old)[:8],
          "registered:", ok_old)
    print("token STAGE-NEW-01 fingerprint prefix:", fingerprint(tok_new)[:8],
          "registered:", ok_new)
    print("token STAGE-BACKUP-01 fingerprint prefix:", fingerprint(tok_backup)[:8],
          "registered:", ok_bak)
    print("ed25519 test pubkey sha256 prefix:", pub_fp[:8])
    print("staging CA cert sha256 fingerprint:", cert_fp(os.path.join(TLS_DIR, "staging-ca.crt"))[:16])
    print("server cert sha256 fingerprint:", cert_fp(os.path.join(TLS_DIR, "staging-server.crt"))[:16])
    print("wrong CA cert sha256 fingerprint:", cert_fp(os.path.join(TLS_DIR, "staging-ca-wrong.crt"))[:16])
    print("ledger counts (total, consumed):", ledger.counts())
    print("registry audit:", registry.audit_counts())


if __name__ == "__main__":
    main()
