"""Issue #73: fail-closed HTTPS staging ingress adapter.

This is intentionally NOT production ready. It wraps the FULL
HTTPSProofService.handle() request (including nonce registration) in the
same single-process issuance gate used for admin revocation and recovery.

Starting a listener does not authorize requests. It starts frozen and
requires independent externally authenticated Ed25519 checkpoint+epoch.
Every potentially mutating proof request freezes admissions again until
a fresh *external* anchor has been committed and verified.

An immutable external epoch store or authenticated anchor writer is NOT
implemented here. Real credentials, real domains, multiworker deployments,
server/process crash and external anchor atomicity remain unproven.
"""
from __future__ import annotations

from typing import Callable

from credential_proof_https import HTTPSProofService, _encode
from recovery_signed_checkpoint import (
    RecoveryNotVerified, require_signed_recovery_checkpoint,
)
from staging_issuance_drain import IssuanceDrainGate, IssuanceGateClosed


class StagingRecoveryFencedHTTPSService(HTTPSProofService):
    """Opt-in single-process staging wrapper; never use the unwrapped service.

    The gate MUST be shared with all admin/token mutations on the same
    staging process. A second gunicorn/uvicorn worker is NOT covered.
    """

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.gate = IssuanceDrainGate(start_frozen=True)

    def open_after_trusted_recovery(self, signed_record: dict, *,
                                   trusted_external_epoch: int,
                                   independently_pinned_public_key: bytes) -> bool:
        """Operator-only; not exposed by the HTTP listener.

        The expected epoch and pinned key MUST be fetched independently
        of the restored DB/backup. Invalid signed state stays frozen.
        """
        try:
            return self.gate.reconcile_and_resume(
                lambda: require_signed_recovery_checkpoint(
                    self.ledger, signed_record,
                    independently_pinned_public_key=independently_pinned_public_key,
                    trusted_external_epoch=trusted_external_epoch,
                ) is True
            )
        except RecoveryNotVerified as exc:
            raise IssuanceGateClosed("trusted_recovery_failed_frozen") from exc

    def handle(self, *, body: bytes, authorization: str | None,
               content_type: str) -> tuple[int, bytes]:
        """Admission covers BOTH nonce register and atomic proof issuance.

        After any request that may write the ledger, require the external
        checkpoint to catch up BEFORE admitting a new request. This is a
        strict *serial gate* reference, not a production throughput solution.
        """
        try:
            with self.gate.admission():
                try:
                    code, payload = super().handle(
                        body=body, authorization=authorization,
                        content_type=content_type,
                    )
                    if code not in (400, 401, 405):
                        # 200 / 403 / 409 / 503: state may have changed,
                        # or its COMMIT is unknown. Never re-open casually.
                        self.gate.freeze_for_reconciliation()
                    return code, payload
                except Exception:
                    self.gate.freeze_for_reconciliation()
                    # Never reflect raw errors or bearer material.
                    return 503, _encode({"status": "proof_state_unknown_frozen"})
        except IssuanceGateClosed:
            return 503, _encode({"status": "issuance_frozen"})

    def guarded_admin_change(self, *,
                             authorized_change: Callable[[], bool],
                             authoritative_readback: Callable[[], bool],
                             new_external_anchor_verified: Callable[[], bool],
                             timeout_s: float = 5.0) -> bool:
        """Freeze/drain, admin mutate, then REQUIRE a fresh external anchor.

        The callback must verify the new DB state against an independently
        committed signed epoch before the gate automatically re-opens.
        """
        if not all(map(callable, (
            authorized_change, authoritative_readback,
            new_external_anchor_verified,
        ))):
            raise ValueError("trusted_admin_and_external_anchor_required")
        return self.gate.guarded_admin_change(
            authorized_change,
            lambda: authoritative_readback() is True
                    and new_external_anchor_verified() is True,
            timeout_s=timeout_s,
        )
