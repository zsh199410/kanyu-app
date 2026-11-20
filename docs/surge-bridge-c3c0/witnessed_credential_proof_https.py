"""Issue73: WITNESSED loopback HTTPS adapter, synthetic staging only.

This subclasses PR110's audited HTTP parser and TLS-only server while
replacing BOTH direct nonce registration and the signer with a shared
witness-fenced service. The witness below is currently a same-host
test double: no independently trusted remote control plane is deployed.

DO NOT expose this staging adapter to public network or migrate live
tokens with it. All privileged admin actions must be invoked outside HTTP.
"""
from __future__ import annotations

from typing import Callable
from contextlib import closing

from credential_proof_https import HTTPSProofService, _encode
from recovery_signed_checkpoint import logical_state_sha256
from staging_issuance_drain import IssuanceDrainGate, IssuanceGateClosed
from witness_fenced_issuer_reference import (
    IndependentWitnessTestDouble, WitnessedAtomicService
)


class WitnessedHTTPSProofService(HTTPSProofService):
    def __init__(self, registry, ledger, signer, *, pairing_secret: str,
                 old_token_id: str, witness: IndependentWitnessTestDouble,
                 gate: IssuanceDrainGate,
                 clock_ms: Callable[[], int] | None = None):
        if not isinstance(witness, IndependentWitnessTestDouble):
            raise ValueError("independent_witness_required")
        if not isinstance(gate, IssuanceDrainGate):
            raise ValueError("single_process_drain_gate_required")
        super().__init__(
            registry, ledger, signer,
            pairing_secret=pairing_secret,
            old_token_id=old_token_id, clock_ms=clock_ms
        )
        self._request_gate = gate
        self.witnessed_service = WitnessedAtomicService(
            registry, signer,
            lambda session, token_id, kind: session is self,
            witness, self._clock_ms, gate,
        )
        # STARTUP FAIL CLOSED: never bind the TLS listener when a restored
        # old local DB disagrees with the authoritative witness head.
        witness.require_fresh(logical_state_sha256(ledger))
        # Make direct access to the historical unfenced signer impossible
        # through this service. Production must independently audit paths.
        self.issuer = None

    def handle(self, *, body: bytes, authorization: str | None,
               content_type: str) -> tuple[int, bytes]:
        """Freeze applies to ENTIRE request, including nonce registration.

        A single outer admission lease covers auth, registration, atomic
        consume, external witness acknowledgment and signer. Existing
        inner gate checks intentionally remain fail-closed if a revoke
        freeze lands between request stages. New frozen requests cannot
        register their nonce before the admin drain barrier.
        """
        try:
            with self._request_gate.admission():
                return super().handle(
                    body=body, authorization=authorization,
                    content_type=content_type)
        except IssuanceGateClosed:
            return 503, _encode({"status": "issuance_frozen"})

    def _register_nonce(self, nonce: str, *, kind: str,
                        candidate_fingerprint: str, token_id: str,
                        issued_ms: int, expires_ms: int) -> bool:
        return self.witnessed_service.register(
            nonce, kind=kind, candidate_fingerprint=candidate_fingerprint,
            token_id=token_id, issued_ms=issued_ms,
            expires_ms=expires_ms)

    def _issue_proof(self, *, session: object, nonce: str, token_id: str,
                     kind: str, candidate_fingerprint: str,
                     exposed_old_token_id: str) -> dict:
        return self.witnessed_service.issue(
            session=session, nonce=nonce, token_id=token_id,
            kind=kind, candidate_fingerprint=candidate_fingerprint,
            exposed_old_token_id=exposed_old_token_id)

    def admin_activate_backup(self, backup_id: str, revoked_new_id: str,
                              *, now_ms: int) -> bool:
        """Privileged trusted-process method, intentionally NOT HTTP."""
        def exact_readback():
            # Verify the two trusted exact token IDs, not aggregate counts.
            with closing(self.registry.ledger._connect()) as db:
                old = db.execute(
                    "SELECT role,status FROM token_registry WHERE token_id=?",
                    (revoked_new_id,)).fetchone()
                new = db.execute(
                    "SELECT role,status FROM token_registry WHERE token_id=?",
                    (backup_id,)).fetchone()
            return old == ("new", "revoked") and new == ("backup", "active")

        return self.witnessed_service.admin_transition(
            lambda: self.registry.activate_backup(
                backup_id, now_ms=now_ms),
            exact_readback,
            revoked_token_id=revoked_new_id
        )
