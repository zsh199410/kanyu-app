"""Issue73 isolated proof issuer with atomic token+challenge authorization.

This is NOT an HTTP endpoint. The caller must supply an independently
trusted device/session permission checker and a server-owned clock.
Only the registry's one-transaction authorization + consumption result
permits signing. A committed nonce stays consumed on signer failure.
"""
import base64
import json
import time
from collections.abc import Callable

from nonce_ledger_sqlite import InvalidChallenge, binding, nonce_hash
from signed_proof_issuer import PURPOSE, ProofIssuanceError
from token_registry_sqlite import TokenRegistry

MAX_PROOF_TTL_MS = 60_000


class AtomicSignedProofIssuer:
    def __init__(self, registry: TokenRegistry, signer,
                 authorize_session: Callable[[object, str, str], bool],
                 now_ms: Callable[[], int] | None = None):
        if not isinstance(registry, TokenRegistry):
            raise ValueError("durable_registry_required")
        if not callable(getattr(signer, "sign", None)):
            raise ValueError("server_owned_signer_required")
        if not callable(authorize_session):
            raise ValueError("session_authorizer_required")
        self.registry = registry
        self.signer = signer
        self.authorize_session = authorize_session
        self.now_ms = now_ms or (lambda: time.time_ns() // 1_000_000)

    def issue(self, *, session: object, nonce: str, token_id: str,
              kind: str, candidate_fingerprint: str,
              exposed_old_token_id: str, ttl_ms: int = MAX_PROOF_TTL_MS):
        if (not isinstance(exposed_old_token_id, str) or
            not exposed_old_token_id or token_id == exposed_old_token_id):
            raise ProofIssuanceError("old_token_rejected")
        if type(ttl_ms) is not int or not 1 <= ttl_ms <= MAX_PROOF_TTL_MS:
            raise ProofIssuanceError("ttl_rejected")
        try:
            # F3: reject malformed input before session lookup or any DB
            # transaction; never mislabel this as an uncertain COMMIT.
            nonce_hash(nonce)
            kind, candidate_fingerprint, token_id = binding(
                kind, candidate_fingerprint, token_id)
            now_ms = self.now_ms()
            if type(now_ms) is not int or not 0 < now_ms < 2**53 - ttl_ms:
                raise ValueError("untrusted_clock")
            # Must authorize the DEVICE/SESSION, not only the token ID.
            # A real server's auth/session code must supply this callback.
            if self.authorize_session(session, token_id, kind) is not True:
                raise ProofIssuanceError("session_forbidden")
        except ProofIssuanceError:
            raise
        except InvalidChallenge as exc:
            raise ProofIssuanceError("invalid_proof_input") from exc
        except Exception as exc:
            raise ProofIssuanceError("preflight_unknown") from exc
        try:
            # Token active/revoked/expired, kind, fp and nonce unconsumed are
            # checked under ONE BEGIN IMMEDIATE in the same SQLite database.
            record = self.registry.consume_authorized(
                nonce, kind=kind, candidate_fingerprint=candidate_fingerprint,
                token_id=token_id, now_ms=now_ms)
        except Exception as exc:
            # The commit may have happened; do not sign/retry same nonce.
            raise ProofIssuanceError("atomic_commit_unknown") from exc
        if record is None:
            raise ProofIssuanceError("challenge_or_token_not_usable")
        proof = {
            "purpose": PURPOSE,
            "kind": record["kind"],
            "ok": True,
            "fingerprint_matches": True,
            "token_id": record["token_id"],
            "fingerprint": record["fingerprint"],
            "nonce": nonce,
            "issued_at": now_ms,
            "expires_at": now_ms + ttl_ms,
        }
        canonical = json.dumps(
            proof, separators=(",", ":"), ensure_ascii=True).encode("utf8")
        try:
            signature = self.signer.sign(canonical)
            if not isinstance(signature, bytes) or len(signature) != 64:
                raise ValueError("unexpected_signature_shape")
        except Exception as exc:
            raise ProofIssuanceError("signature_failed_challenge_burned") from exc
        proof["signature"] = base64.b64encode(signature).decode("ascii")
        return proof
