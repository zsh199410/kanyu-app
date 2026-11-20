"""Issue #73: isolated durable token registry sharing the nonce SQLite DB.

INTERNAL server component only, not an HTTP route or admin API.
The caller must be authenticated/authorized independently. No production
token/host/key appears in this source. A database snapshot restore can
resurrect consumed nonces and revoked tokens: never deploy without an
external rollback-resistant epoch/control plane.
"""
from __future__ import annotations

import hashlib
import re
import sqlite3
from contextlib import closing

from nonce_ledger_sqlite import (
    NonceLedger, NonceLedgerError, InvalidChallenge, binding, millis, nonce_hash
)

OLD_MAX_MS = 48 * 60 * 60 * 1000
ACTIVE_MAX_MS = 30 * 24 * 60 * 60 * 1000
TOKEN_PATTERN = re.compile(r"^[\x21-\x7e]{32,256}$", re.ASCII)
ID_PATTERN = re.compile(r"^[A-Za-z0-9_-]{1,128}$", re.ASCII)
ROLES = {"exposed_old", "new", "backup"}


class TokenRegistryError(RuntimeError):
    """Nonsensitive fail-closed status; unknown commit state possible."""


def fingerprint(value: str) -> str:
    if not isinstance(value, str) or TOKEN_PATTERN.fullmatch(value) is None:
        raise ValueError("invalid_token_format")
    return hashlib.sha256(value.encode("ascii")).hexdigest()


def valid_id(value: str) -> str:
    if not isinstance(value, str) or ID_PATTERN.fullmatch(value) is None:
        raise ValueError("invalid_token_id")
    return value


class TokenRegistry:
    """Single-file SQLite registry with serializable nonce authorization.

    All signing decisions use a single BEGIN IMMEDIATE transaction that
    verifies an active token and durably consumes its challenge together.
    In-flight signing after a committed authorization is NOT stopped by
    a later revocation: production must drain in-flight requests first.
    """

    def __init__(self, ledger: NonceLedger):
        if not isinstance(ledger, NonceLedger):
            raise ValueError("shared_nonce_ledger_required")
        self.ledger = ledger
        try:
            with closing(self.ledger._connect()) as db:
                db.execute("""CREATE TABLE IF NOT EXISTS token_registry(
                    token_id TEXT PRIMARY KEY,
                    fingerprint TEXT NOT NULL UNIQUE,
                    kind TEXT NOT NULL CHECK(kind IN ('dev','localkey')),
                    role TEXT NOT NULL CHECK(role IN
                        ('exposed_old','new','backup')),
                    status TEXT NOT NULL CHECK(status IN
                        ('active','standby','revoked')),
                    issued_ms INTEGER NOT NULL,
                    expires_ms INTEGER NOT NULL,
                    revoked_ms INTEGER,
                    CHECK((status='revoked' AND revoked_ms IS NOT NULL)
                        OR (status!='revoked' AND revoked_ms IS NULL))
                )""")
                db.execute("""CREATE UNIQUE INDEX IF NOT EXISTS
                    single_active_new_per_kind ON token_registry(kind)
                    WHERE role='new' AND status='active'""")
                db.execute("""CREATE UNIQUE INDEX IF NOT EXISTS
                    single_active_old_per_kind ON token_registry(kind)
                    WHERE role='exposed_old' AND status='active'""")
        except (sqlite3.Error, OSError) as exc:
            raise TokenRegistryError("registry_initialization_unknown") from exc

    def add(self, token: str, *, token_id: str, kind: str,
            role: str, issued_ms: int, expires_ms: int) -> bool:
        """Trusted ADMIN-only operation; never expose to device HTTP."""
        fp = fingerprint(token)
        token_id = valid_id(token_id)
        kind, _, _ = binding(kind, fp, token_id)
        if role not in ROLES:
            raise ValueError("invalid_token_role")
        issued_ms, expires_ms = millis(issued_ms), millis(expires_ms)
        cap = OLD_MAX_MS if role == "exposed_old" else ACTIVE_MAX_MS
        if not issued_ms < expires_ms <= issued_ms + cap:
            raise ValueError("invalid_token_expiry")
        status = "standby" if role == "backup" else "active"
        try:
            with closing(self.ledger._connect()) as db:
                db.execute("BEGIN IMMEDIATE")
                changed = db.execute("""INSERT OR IGNORE INTO token_registry
                    (token_id,fingerprint,kind,role,status,issued_ms,
                     expires_ms,revoked_ms)
                    VALUES (?,?,?,?,?,?,?,NULL)""",
                    (token_id, fp, kind, role, status, issued_ms, expires_ms)
                ).rowcount
                db.execute("COMMIT")
                return changed == 1
        except (sqlite3.Error, OSError) as exc:
            raise TokenRegistryError("token_registration_unknown") from exc

    def authorize(self, token: str, *, kind: str, now_ms: int) -> dict:
        """Read-only mock bridge auth. Never returns token values/hashes."""
        fp = fingerprint(token)
        if kind not in ("dev", "localkey"):
            raise ValueError("invalid_kind")
        now_ms = millis(now_ms)
        try:
            with closing(self.ledger._connect()) as db:
                row = db.execute("""SELECT status,expires_ms FROM token_registry
                    WHERE fingerprint=? AND kind=?""", (fp, kind)).fetchone()
        except (sqlite3.Error, OSError) as exc:
            raise TokenRegistryError("token_lookup_unknown") from exc
        if row is None:
            return {"status": 401, "reason": "unknown_token"}
        status, expires = row
        if status == "revoked":
            return {"status": 403, "reason": "token_revoked"}
        if status != "active":
            return {"status": 403, "reason": "token_standby"}
        if now_ms >= expires:
            return {"status": 403, "reason": "token_expired"}
        return {"status": 200, "reason": "ok"}

    def consume_authorized(self, nonce: str, *, kind: str,
                           candidate_fingerprint: str,
                           token_id: str, now_ms: int) -> dict | None:
        """Atomic server-only check of token activity AND one-time consume.

        A committed result authorizes exactly one signer invocation;
        caller must not invoke signer on None or on an exception.
        Do not call from an unauthenticated or unauthorized endpoint.
        """
        digest = nonce_hash(nonce)
        kind, fp, token_id = binding(kind, candidate_fingerprint, token_id)
        now_ms = millis(now_ms)
        try:
            with closing(self.ledger._connect()) as db:
                db.execute("BEGIN IMMEDIATE")
                row = db.execute("""SELECT role,status,issued_ms,expires_ms
                    FROM token_registry WHERE token_id=? AND kind=?
                    AND fingerprint=?""", (token_id, kind, fp)).fetchone()
                if (row is None or row[0] not in ("new", "backup") or
                    row[1] != "active" or not row[2] <= now_ms < row[3]):
                    db.execute("ROLLBACK")
                    return None
                changed = db.execute("""UPDATE challenge
                    SET status='consumed',consumed_ms=?
                    WHERE nonce_sha256=? AND kind=? AND candidate_fp=?
                    AND token_id=? AND status='issued'
                    AND issued_ms<=? AND ?<expires_ms""",
                    (now_ms, digest, kind, fp, token_id, now_ms, now_ms)
                ).rowcount
                if changed != 1:
                    db.execute("ROLLBACK")
                    return None
                db.execute("COMMIT")
                return {"kind": kind, "fingerprint": fp, "token_id": token_id}
        except (sqlite3.Error, OSError) as exc:
            # Could have committed even if COMMIT raised. Never sign.
            raise TokenRegistryError("atomic_consumption_unknown") from exc

    def revoke(self, token_id: str, *, now_ms: int) -> bool:
        """Admin-only irrevocable status change; rows are never deleted.

        Requires an already-active, unexpired NON-old replacement.
        """
        token_id, now_ms = valid_id(token_id), millis(now_ms)
        try:
            with closing(self.ledger._connect()) as db:
                db.execute("BEGIN IMMEDIATE")
                row = db.execute("""SELECT kind,status FROM token_registry
                    WHERE token_id=?""", (token_id,)).fetchone()
                if row is None or row[1] == "revoked":
                    db.execute("ROLLBACK")
                    return False
                replacement = db.execute("""SELECT COUNT(*) FROM token_registry
                    WHERE kind=? AND token_id!=? AND status='active'
                      AND role IN ('new','backup')
                      AND issued_ms<=? AND ?<expires_ms""",
                    (row[0], token_id, now_ms, now_ms)).fetchone()[0]
                if replacement < 1:
                    db.execute("ROLLBACK")
                    return False
                changed = db.execute("""UPDATE token_registry SET
                    status='revoked',revoked_ms=?
                    WHERE token_id=? AND status!='revoked'""",
                    (now_ms, token_id)).rowcount
                db.execute("COMMIT")
                return changed == 1
        except (sqlite3.Error, OSError) as exc:
            raise TokenRegistryError("revocation_unknown") from exc

    def activate_backup(self, backup_token_id: str, *, now_ms: int) -> bool:
        """Admin-only atomic emergency new→backup switch; never revives old."""
        backup_token_id, now_ms = valid_id(backup_token_id), millis(now_ms)
        try:
            with closing(self.ledger._connect()) as db:
                db.execute("BEGIN IMMEDIATE")
                backup = db.execute("""SELECT kind,issued_ms,expires_ms
                    FROM token_registry WHERE token_id=? AND role='backup'
                    AND status='standby'""", (backup_token_id,)).fetchone()
                if (backup is None or not backup[1] <= now_ms < backup[2]):
                    db.execute("ROLLBACK")
                    return False
                current = db.execute("""SELECT token_id FROM token_registry
                    WHERE kind=? AND role='new' AND status='active'""",
                    (backup[0],)).fetchone()
                if current is None:
                    db.execute("ROLLBACK")
                    return False
                db.execute("""UPDATE token_registry SET status='revoked',
                    revoked_ms=? WHERE token_id=?""", (now_ms, current[0]))
                db.execute("""UPDATE token_registry SET status='active'
                    WHERE token_id=?""", (backup_token_id,))
                db.execute("COMMIT")
                return True
        except (sqlite3.Error, OSError) as exc:
            raise TokenRegistryError("backup_activation_unknown") from exc

    def audit_counts(self) -> dict:
        """Nonsensitive inspection; no token value or fingerprint emitted."""
        try:
            with closing(self.ledger._connect()) as db:
                rows = db.execute("""SELECT role,status,COUNT(*)
                    FROM token_registry GROUP BY role,status""").fetchall()
                return {role + ":" + status: n for role, status, n in rows}
        except (sqlite3.Error, OSError) as exc:
            raise TokenRegistryError("audit_unknown") from exc
