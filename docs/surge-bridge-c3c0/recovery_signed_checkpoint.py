"""Issue73 recovery checkpoint verifier — INDEPENDENTLY TRUSTED ANCHOR REQUIRED.

A signed digest of the whole logical token/nonce SQLite state can detect
old database snapshots only when the caller ALSO supplies a trusted,
rollback-resistant expected epoch from outside the database/backup domain.

This verifier does NOT issue/sign checkpoints, increment an epoch, manage
an external high-water service, update tokens, run an HTTP server, or change
production. It is a fail-closed staging recovery proof of concept.
"""
from __future__ import annotations

import base64
import hashlib
import hmac
import json
import re
import sqlite3
from contextlib import closing

from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey

from nonce_ledger_sqlite import NonceLedger

PURPOSE = "issue73/recovery-state/v1"
DIGEST_PATTERN = re.compile(r"^[0-9a-f]{64}$")
FIELDS = {"purpose", "epoch", "state_sha256", "signature"}


class RecoveryNotVerified(RuntimeError):
    """Fail-closed nonsecret reason. NEVER bypass by re-anchoring an old DB."""


def _canonical(purpose: str, epoch: int, digest: str) -> bytes:
    return json.dumps(
        {"purpose": purpose, "epoch": epoch, "state_sha256": digest},
        separators=(",", ":"), ensure_ascii=True,
    ).encode("ascii")


def logical_state_sha256(ledger: NonceLedger) -> str:
    """Hash a consistent SQLite read transaction; NEVER expose raw rows."""
    if not isinstance(ledger, NonceLedger):
        raise RecoveryNotVerified("invalid_ledger")
    try:
        with closing(ledger._connect()) as db:
            db.execute("BEGIN")
            schema = db.execute("PRAGMA user_version").fetchone()[0]
            if schema != 1:
                raise RecoveryNotVerified("unexpected_schema")
            tokens = db.execute("""SELECT token_id,fingerprint,kind,role,status,
                         issued_ms,expires_ms,revoked_ms FROM token_registry
                         ORDER BY token_id""").fetchall()
            challenges = db.execute("""SELECT lower(hex(nonce_sha256)),
                        kind,candidate_fp,token_id,issued_ms,expires_ms,
                        consumed_ms,status FROM challenge
                        ORDER BY nonce_sha256""").fetchall()
            db.execute("COMMIT")
        # Field names + types encoded canonically: no token plaintext stored.
        canonical = json.dumps(
            {"purpose": PURPOSE, "schema": 1,
             "tokens": tokens, "challenges": challenges},
            ensure_ascii=True, separators=(",", ":"),
        ).encode("ascii")
        return hashlib.sha256(canonical).hexdigest()
    except RecoveryNotVerified:
        raise
    except (sqlite3.Error, OSError, TypeError, ValueError) as exc:
        raise RecoveryNotVerified("state_read_unknown") from exc


def require_signed_recovery_checkpoint(
    ledger: NonceLedger, record: dict,
    *, independently_pinned_public_key: bytes,
    trusted_external_epoch: int,
) -> bool:
    """Verify signed state AND external monotonic epoch BEFORE accepting work.

    Both the pinned key and external epoch MUST come from an independently
    authenticated, non-rollbackable control plane. Fetching either one
    from the restored SQLite database or alongside its old snapshot
    destroys the rollback safety property.
    """
    if type(trusted_external_epoch) is not int or not (
        1 <= trusted_external_epoch <= 2**53 - 1
    ):
        raise RecoveryNotVerified("external_epoch_unavailable")
    if (not isinstance(independently_pinned_public_key, bytes) or
        len(independently_pinned_public_key) != 32):
        raise RecoveryNotVerified("trusted_key_unavailable")
    if not isinstance(record, dict) or set(record) != FIELDS:
        raise RecoveryNotVerified("checkpoint_shape_invalid")
    if record["purpose"] != PURPOSE:
        raise RecoveryNotVerified("checkpoint_purpose_mismatch")
    if (type(record["epoch"]) is not int or
        record["epoch"] != trusted_external_epoch):
        raise RecoveryNotVerified("external_epoch_mismatch")
    if (not isinstance(record["state_sha256"], str) or
        DIGEST_PATTERN.fullmatch(record["state_sha256"]) is None):
        raise RecoveryNotVerified("state_digest_invalid")
    encoded = record["signature"]
    if not isinstance(encoded, str) or len(encoded) != 88:
        raise RecoveryNotVerified("signature_invalid")
    try:
        signature = base64.b64decode(encoded, validate=True)
        if (len(signature) != 64 or
            base64.b64encode(signature).decode("ascii") != encoded):
            raise ValueError("noncanonical_signature")
        Ed25519PublicKey.from_public_bytes(
            independently_pinned_public_key
        ).verify(signature, _canonical(
            record["purpose"], record["epoch"], record["state_sha256"],
        ))
    except (ValueError, InvalidSignature) as exc:
        raise RecoveryNotVerified("checkpoint_signature_invalid") from exc
    current = logical_state_sha256(ledger)
    if not hmac.compare_digest(current, record["state_sha256"]):
        raise RecoveryNotVerified("sqlite_state_mismatch")
    return True
