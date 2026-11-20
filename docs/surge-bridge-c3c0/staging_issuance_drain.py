"""Issue #73: SINGLE-PROCESS staging issuer admission/drain reference.

Does not replace durable SQL nonce consumption, multi-process coordination,
shared-service admission control, or externally anchored DB rollback defense.
Every issuance call AND admin revoke/activate path in the same process must
use THIS SAME object. The original issuer and registry remain callable
directly, so this is NOT a production security boundary until integrated
and proven at the real authenticated HTTPS routing layer.
"""
from __future__ import annotations

import os
import threading
import time
from contextlib import contextmanager
from typing import Callable


class IssuanceGateClosed(RuntimeError):
    """Nonsecret status. Do not resume automatically on unknown state."""


class IssuanceDrainTimeout(IssuanceGateClosed):
    """Gate remains frozen; operator reconciliation is required."""


class IssuanceDrainGate:
    def __init__(self):
        self._cv = threading.Condition()
        self._frozen = False
        self._admin_active = False
        self._active = 0
        self._owner_pid = os.getpid()

    def _same_process(self):
        if os.getpid() != self._owner_pid:
            raise IssuanceGateClosed("cross_process_unverified")

    def status(self) -> dict:
        self._same_process()
        with self._cv:
            return {
                "frozen": self._frozen,
                "admin_active": self._admin_active,
                "active_issuances": self._active,
            }

    @contextmanager
    def admission(self):
        self._same_process()
        with self._cv:
            if self._frozen or self._admin_active:
                raise IssuanceGateClosed("issuance_frozen")
            self._active += 1
        try:
            yield
        finally:
            with self._cv:
                self._active -= 1
                self._cv.notify_all()

    def issue(self, issuer, **kwargs):
        """Use instead of issuer.issue directly in *every* staging handler."""
        with self.admission():
            return issuer.issue(**kwargs)

    def _freeze_and_drain(self, timeout_s: float) -> None:
        self._same_process()
        if not isinstance(timeout_s, (float, int)) or isinstance(timeout_s, bool) or not 0 <= timeout_s <= 600:
            raise ValueError("invalid_drain_timeout")
        deadline = time.monotonic() + timeout_s
        with self._cv:
            if self._frozen or self._admin_active:
                raise IssuanceGateClosed("gate_already_frozen")
            # The barrier is active BEFORE we await active signers.
            self._frozen = True
            self._admin_active = True
            while self._active:
                left = deadline - time.monotonic()
                if left <= 0:
                    self._admin_active = False
                    self._cv.notify_all()
                    # Deliberately leave frozen. Never call a mutation.
                    raise IssuanceDrainTimeout("drain_timeout_frozen")
                self._cv.wait(timeout=left)

    def guarded_admin_change(self, action: Callable[[], bool],
                             confirm: Callable[[], bool],
                             *, timeout_s: float = 5.0) -> bool:
        """Quiesce issuers, make verified change, resume ONLY on fresh proof.

        The callback should execute exactly one authorized atomic SQLite
        admin mutation; confirm must read the authoritative post-change
        state and return the literal True. A failure freezes all issuance
        until separate operator reconciliation. Does not assert that an
        already-issued proof cannot arrive after revocation over a network.
        """
        if not callable(action) or not callable(confirm):
            raise ValueError("trusted_admin_callbacks_required")
        self._freeze_and_drain(timeout_s)
        try:
            if action() is not True:
                raise IssuanceGateClosed("admin_change_not_confirmed_frozen")
            if confirm() is not True:
                raise IssuanceGateClosed("admin_readback_failed_frozen")
        except Exception:
            with self._cv:
                self._admin_active = False
                # _frozen remains True, always.
                self._cv.notify_all()
            raise
        with self._cv:
            self._admin_active = False
            self._frozen = False
            self._cv.notify_all()
        return True

    def reconcile_and_resume(self, verify: Callable[[], bool]) -> bool:
        """Explicit trusted operator-only recovery after failed drain/change.

        This method must NOT be reachable from an unauthenticated route.
        A real deployment must independently validate complete ledger,
        token, epoch and active signer state (including other processes).
        """
        self._same_process()
        if not callable(verify):
            raise ValueError("trusted_reconciliation_required")
        with self._cv:
            if not self._frozen or self._admin_active or self._active:
                raise IssuanceGateClosed("reconciliation_not_safe")
            if verify() is not True:
                raise IssuanceGateClosed("reconciliation_failed_frozen")
            self._frozen = False
            return True
