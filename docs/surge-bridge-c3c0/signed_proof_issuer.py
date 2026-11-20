"""Issue #73 C3-C1: signed proof issuance after durable nonce consumption.

ISOLATED server-side reference, NOT a deployed HTTP endpoint.
Private signing key, authenticated caller, authoritative token registry,
single-host durable SQLite storage and rollback-resistant state are
required from a separately reviewed production integration.
No real credentials or private keys are included in this repository.
"""
from __future__ import annotations

import base64
import json
from dataclasses import dataclass
from typing import Callable

from nonce_ledger_sqlite import NonceLedger, binding

PURPOSE = "issue73/credential-promotion/v1"
DEFAULT_TTL_MS = 60_000
MAX_AGE_MS = 24 * 60 * 60 * 1000


class ProofIssuanceError(RuntimeError):
    """Nonsecret error status; never include token/nonce/key in messages."""


@dataclass(frozen=True)
class TrustedTokenRecord:
    """Must originate from an authenticated SERVER-OWNED token registry.

    This object alone is not an authorization mechanism. Never construct it
    directly from a request body, untrusted device input or proof response.
    """

    kind: str
    token_id: str
    fingerprint: str
    status: str
    is_exposed_old: bool


class SignedProofIssuer:
    def __init__(self, ledger: NonceLedger, signer,
                 trusted_token_lookup: Callable[[str], TrustedTokenRecord | None]):
        if not isinstance(ledger, NonceLedger):
            raise ValueError("durable_ledger_required")
        if not callable(getattr(signer, "sign", None)):
            raise ValueError("private_signer_required")
        if not callable(trusted_token_lookup):
            raise ValueError("authoritative_token_lookup_required")
        self.ledger = ledger
        self.signer = signer
        self.trusted_token_lookup = trusted_token_lookup

    def issue(self, *, nonce: str, requested_token_id: str,
              expected_kind: str, old_token_id: str, now_ms: int,
              ttl_ms: int = DEFAULT_TTL_MS) -> dict:
        """Consume a challenge BEFORE signing: one durable consume, one proof.

        After an ambiguous commit or signing failure the challenge may be
        permanently burned. Never retry that nonce as if it were unused.
        """
        if (not isinstance(old_token_id, str) or not old_token_id or
            not isinstance(requested_token_id, str) or
            requested_token_id == old_token_id):
            raise ProofIssuanceError("invalid_token_identity")
        if type(now_ms) is not int or not 0 <= now_ms <= 2**53 - 1:
            raise ProofIssuanceError("invalid_clock")
        if type(ttl_ms) is not int or not 1 <= ttl_ms <= DEFAULT_TTL_MS or (
            now_ms + ttl_ms > 2**53 - 1
        ):
            raise ProofIssuanceError("invalid_ttl")
        try:
            trusted = self.trusted_token_lookup(requested_token_id)
        except Exception as exc:
            raise ProofIssuanceError("registry_unknown") from exc
        if not isinstance(trusted, TrustedTokenRecord):
            raise ProofIssuanceError("token_not_issued")
        try:
            kind, fp, token_id = binding(
                trusted.kind, trusted.fingerprint, trusted.token_id
            )
        except Exception as exc:
            raise ProofIssuanceError("invalid_registry_record") from exc
        if (token_id != requested_token_id or kind != expected_kind or
            trusted.status != "active" or trusted.is_exposed_old):
            raise ProofIssuanceError("token_not_authorized")
        try:
            was_consumed = self.ledger.consume(
                nonce, kind=kind, candidate_fingerprint=fp,
                token_id=token_id, now_ms=now_ms
            )
        except Exception as exc:
            # This must not authorize a retry. The DB may have committed.
            raise ProofIssuanceError("nonce_commit_unknown") from exc
        if not was_consumed:
            raise ProofIssuanceError("challenge_not_usable")

        proof = {
            "purpose": PURPOSE,
            "kind": kind,
            "ok": True,
            "fingerprint_matches": True,
            "token_id": token_id,
            "fingerprint": fp,
            "nonce": nonce,
            "issued_at": now_ms,
            "expires_at": now_ms + ttl_ms,
        }
        canonical = json.dumps(
            proof, separators=(",", ":"), ensure_ascii=True
        ).encode("utf-8")
        try:
            signature = self.signer.sign(canonical)
            if not isinstance(signature, bytes) or len(signature) != 64:
                raise ValueError("invalid_signature_output")
        except Exception as exc:
            # Nonce is already durably consumed; do NOT issue or retry.
            raise ProofIssuanceError("signing_failed_after_consume") from exc
        proof["signature"] = base64.b64encode(signature).decode("ascii")
        return proof
