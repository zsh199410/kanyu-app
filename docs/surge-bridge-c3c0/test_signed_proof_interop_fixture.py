"""Isolated, ephemeral signed-proof fixture consumed by a Node WebCrypto test.

Never use real signing keys or credentials. All values here are synthetic.
Do NOT deploy as an endpoint.
"""
import hashlib
import json
import tempfile
from pathlib import Path

from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from cryptography.hazmat.primitives import serialization

from nonce_ledger_sqlite import NonceLedger, new_nonce
from signed_proof_issuer import SignedProofIssuer, TrustedTokenRecord

NOW = 1800000000000
CANDIDATE = "TEST-INTEROP-DEV-CANDIDATE-0123456789ABCDEF"
FP = hashlib.sha256(CANDIDATE.encode()).hexdigest()
ID = "TEST-INTEROP-NEW-TOKEN-ID"
OLD = "TEST-INTEROP-OLD-TOKEN-ID"

with tempfile.TemporaryDirectory() as temp:
    ledger = NonceLedger(Path(temp) / "proof.sqlite")
    nonce = new_nonce()
    assert ledger.register(nonce, kind="dev", candidate_fingerprint=FP,
                           token_id=ID, issued_ms=NOW, expires_ms=NOW+60000)
    private_key = Ed25519PrivateKey.generate()
    record = TrustedTokenRecord("dev", ID, FP, "active", False)
    issuer = SignedProofIssuer(ledger, private_key,
                               lambda token_id: record if token_id == ID else None)
    proof = issuer.issue(nonce=nonce, requested_token_id=ID,
                         expected_kind="dev", old_token_id=OLD, now_ms=NOW)
    assert ledger.counts() == (1, 1)
    raw_pub = private_key.public_key().public_bytes(
        encoding=serialization.Encoding.Raw,
        format=serialization.PublicFormat.Raw
    )
    # Test fixture sent over local process stdout only (all synthetic data).
    print(json.dumps({"proof": proof, "candidate": CANDIDATE,
                      "nonce": nonce, "oldId": OLD, "publicHex": raw_pub.hex(),
                      "now": NOW}, separators=(",", ":")))
