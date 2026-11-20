"""Issue #73: fail-closed entire-HTTPS staging request admission.

Synthetic staging reference ONLY, not deployed to a production VPS.
No independent rollback-resistant epoch service is implemented here.

Every potentially mutating request is admitted as a WHOLE (including
nonce registration), and a SUCCESSFUL SIGNED PROOF is never exposed to
the HTTP caller until a trusted externally committed signed checkpoint
for the latest DB state has independently verified. Unknown anchor
status returns 503 with a burned nonce and a frozen gate.
"""
from __future__ import annotations

import hmac
import threading
from collections.abc import Callable

from credential_proof_https import HTTPSProofService, _encode
from recovery_signed_checkpoint import (
    RecoveryNotVerified, require_signed_recovery_checkpoint,
)
from staging_issuance_drain import IssuanceDrainGate, IssuanceGateClosed


class StagingRecoveryFencedHTTPSService(HTTPSProofService):
    """Single-process staging wrapper: never mix with unwrapped HTTPS routes.

    commit_and_fetch_anchor MUST be a trusted, independently authenticated
    external authority operation that commits a new monotonically increasing
    epoch for the current database digest, returning (signed_record, epoch).
    No such authority is provided by this library; CI uses a fake in-memory
    fixture, not a verified rollback-resistant production service.
    """

    def __init__(self, *args,
                 commit_and_fetch_anchor: Callable[[], tuple[dict, int]],
                 **kwargs):
        if not callable(commit_and_fetch_anchor):
            raise ValueError("independent_external_anchor_authority_required")
        super().__init__(*args, **kwargs)
        self.gate = IssuanceDrainGate(start_frozen=True)
        self._anchor_lock = threading.Lock()
        self._anchor_commit = commit_and_fetch_anchor
        self._pinned_key = None
        self._verified_epoch = None

    def _verify_anchor(self, record: dict, epoch: int,
                       *, require_advance: bool) -> bool:
        key = self._pinned_key
        if key is None:
            raise RecoveryNotVerified("trusted_key_unavailable")
        if require_advance and (
            self._verified_epoch is None or type(epoch) is not int or
            epoch <= self._verified_epoch
        ):
            raise RecoveryNotVerified("external_epoch_not_advanced")
        require_signed_recovery_checkpoint(
            self.ledger, record,
            independently_pinned_public_key=key,
            trusted_external_epoch=epoch,
        )
        self._verified_epoch = epoch
        return True

    def _externally_anchor_mutation(self) -> bool:
        """Commit and independently verify a higher signed epoch.

        Called with request admission or admin drain still held. If external
        write is lost/unknown or signature/DB mismatch, refuse the HTTP
        success and remain frozen. No same-nonce automatic retry.
        """
        with self._anchor_lock:
            record, epoch = self._anchor_commit()
            return self._verify_anchor(record, epoch, require_advance=True)

    def open_after_trusted_recovery(self, signed_record: dict, *,
                                   trusted_external_epoch: int,
                                   independently_pinned_public_key: bytes) -> bool:
        """Operator-only startup/recovery; not routed over public HTTPS."""
        if (type(independently_pinned_public_key) is not bytes or
            len(independently_pinned_public_key) != 32):
            raise IssuanceGateClosed("trusted_root_unavailable_frozen")
        if (self._pinned_key is not None and
            not hmac.compare_digest(
                self._pinned_key, independently_pinned_public_key
            )):
            raise IssuanceGateClosed("trusted_root_changed_frozen")
        try:
            def verified() -> bool:
                with self._anchor_lock:
                    require_signed_recovery_checkpoint(
                        self.ledger, signed_record,
                        independently_pinned_public_key=independently_pinned_public_key,
                        trusted_external_epoch=trusted_external_epoch,
                    )
                    if (self._verified_epoch is not None and
                        trusted_external_epoch < self._verified_epoch):
                        raise RecoveryNotVerified("epoch_regression")
                    self._pinned_key = independently_pinned_public_key
                    self._verified_epoch = trusted_external_epoch
                    return True
            return self.gate.reconcile_and_resume(verified)
        except RecoveryNotVerified as exc:
            raise IssuanceGateClosed("trusted_recovery_failed_frozen") from exc

    def handle(self, *, body: bytes, authorization: str | None,
               content_type: str) -> tuple[int, bytes]:
        """Protect nonce registration and proof issuance under ONE admission.

        After any status that may have touched the ledger, immediately
        freeze new admissions. HTTP 200 is CONDITIONAL on an externally
        committed and cryptographically verified new recovery anchor,
        else replace the proof with a generic 503 and never replay nonce.
        """
        try:
            with self.gate.admission():
                try:
                    code, payload = super().handle(
                        body=body, authorization=authorization,
                        content_type=content_type,
                    )
                    if code in (400, 401, 405):
                        return code, payload
                    self.gate.freeze_for_reconciliation()
                    if code == 200:
                        try:
                            if self._externally_anchor_mutation() is not True:
                                raise RecoveryNotVerified("anchor_unconfirmed")
                        except Exception:
                            return 503, _encode({
                                "status": "external_anchor_unknown_frozen"
                            })
                    # 403/409/503 may have written a challenge; do not
                    # automatically reopen without reconciliation.
                    return code, payload
                except Exception:
                    self.gate.freeze_for_reconciliation()
                    return 503, _encode({
                        "status": "proof_state_unknown_frozen"
                    })
        except IssuanceGateClosed:
            return 503, _encode({"status": "issuance_frozen"})

    def guarded_admin_change(self, *,
                             authorized_change: Callable[[], bool],
                             authoritative_readback: Callable[[], bool],
                             timeout_s: float = 5.0) -> bool:
        """Drain, apply mutation, verify state and NEW external signed epoch."""
        if not callable(authorized_change) or not callable(authoritative_readback):
            raise ValueError("trusted_admin_callbacks_required")
        def confirmed() -> bool:
            if authoritative_readback() is not True:
                return False
            # On any exception from external anchor, the outer gate
            # GUARANTEES frozen until manual reconciliation.
            return self._externally_anchor_mutation() is True
        return self.gate.guarded_admin_change(
            authorized_change, confirmed, timeout_s=timeout_s
        )
