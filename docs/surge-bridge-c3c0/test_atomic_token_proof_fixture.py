"""Synthetic atomic-token-registry proof consumed by actual WebCrypto VM.

Real SQLite, ephemeral signing key, not production credentials or server.
"""
import hashlib
import json
import tempfile
from pathlib import Path
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from cryptography.hazmat.primitives import serialization
from nonce_ledger_sqlite import NonceLedger, new_nonce
from token_registry_sqlite import TokenRegistry, fingerprint
from atomic_signed_proof_issuer import AtomicSignedProofIssuer
from signed_proof_issuer import ProofIssuanceError

NOW = 1800000000000
CANDIDATE = "TEST-ATOMIC-NEW-CANDIDATE-0123456789ABCDE"
OLD = "TEST-ATOMIC-EXPOSED-OLD-0123456789ABCDE"
OLD_ID = "TEST-OLD-EXPOSED-ID"
NEW_ID = "TEST-ATOMIC-NEW-ID"
with tempfile.TemporaryDirectory() as d:
    ledger = NonceLedger(Path(d) / "nonce-and-tokens.sqlite")
    registry = TokenRegistry(ledger)
    assert registry.add(OLD, token_id=OLD_ID, kind="dev",
                        role="exposed_old", issued_ms=NOW,
                        expires_ms=NOW+3600000)
    assert registry.add(CANDIDATE, token_id=NEW_ID, kind="dev",
                        role="new", issued_ms=NOW, expires_ms=NOW+86400000)
    nonce = new_nonce()
    assert ledger.register(nonce,kind="dev",
                           candidate_fingerprint=fingerprint(CANDIDATE),
                           token_id=NEW_ID,issued_ms=NOW,expires_ms=NOW+60000)
    signer = Ed25519PrivateKey.generate()
    issuer = AtomicSignedProofIssuer(
        registry, signer,
        lambda session, token_id, kind:
            session == "synthetic-session" and token_id == NEW_ID and kind == "dev",
        now_ms=lambda:NOW
    )
    kwargs = dict(
        session="synthetic-session", nonce=nonce, token_id=NEW_ID,
        kind="dev",candidate_fingerprint=fingerprint(CANDIDATE),
        exposed_old_token_id=OLD_ID)
    proof = issuer.issue(**kwargs)
    try:
        issuer.issue(**kwargs)
        raise AssertionError("REPLAY_ALLOW")
    except ProofIssuanceError as exc:
        assert str(exc) == "challenge_or_token_not_usable"
    assert ledger.counts() == (1,1)
    pub = signer.public_key().public_bytes(
        serialization.Encoding.Raw,
        serialization.PublicFormat.Raw)
    print(json.dumps({"proof":proof,"candidate":CANDIDATE,
        "old_id":OLD_ID,"nonce":nonce,"public_hex":pub.hex(),"now":NOW},
        separators=(",",":"),ensure_ascii=True))
