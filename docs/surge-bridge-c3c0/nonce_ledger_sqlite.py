"""Issue #73 P0: isolated SQLite one-time nonce ledger (server reference).

Not an HTTP service, signed proof issuer, or Surge/iOS script.
An authenticated, authorized server handler must register a device-generated
challenge and consume it BEFORE issuing a signed proof. No token values here.
Local WAL + FULL synchronous + BEGIN IMMEDIATE serializes single-host writers.
DB snapshot rollback can resurrect consumed nonces; strict device-side replay
gate and rollback-resistant audit remain separate production requirements.
"""
from __future__ import annotations

import base64
import hashlib
import os
import secrets
import sqlite3
from contextlib import closing
from pathlib import Path

MAX_AGE_MS = 24 * 60 * 60 * 1000


class NonceLedgerError(RuntimeError):
    """Durable commit state UNKNOWN; never issue a proof after this error."""


class InvalidChallenge(ValueError):
    """Invalid input, rejected without database writes."""


def new_nonce() -> str:
    return base64.urlsafe_b64encode(secrets.token_bytes(32)).decode().rstrip("=")


def nonce_hash(nonce: str) -> bytes:
    if (not isinstance(nonce, str) or len(nonce) != 43 or
        any(c not in "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
            for c in nonce)):
        raise InvalidChallenge("invalid_nonce")
    try:
        raw = base64.urlsafe_b64decode(nonce + "=")
    except (ValueError, base64.binascii.Error) as exc:
        raise InvalidChallenge("invalid_nonce") from exc
    if len(raw) != 32 or base64.urlsafe_b64encode(raw).decode().rstrip("=") != nonce:
        raise InvalidChallenge("noncanonical_nonce")
    return hashlib.sha256(raw).digest()


def binding(kind: str, candidate_fp: str, token_id: str) -> tuple[str, str, str]:
    if kind not in ("dev", "localkey"):
        raise InvalidChallenge("invalid_kind")
    if (not isinstance(candidate_fp, str) or len(candidate_fp) != 64 or
        any(c not in "0123456789abcdef" for c in candidate_fp)):
        raise InvalidChallenge("invalid_fingerprint")
    if (not isinstance(token_id, str) or not 1 <= len(token_id) <= 128 or
        any(c not in "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-"
            for c in token_id)):
        raise InvalidChallenge("invalid_token_id")
    return kind, candidate_fp, token_id


def millis(n: int) -> int:
    if type(n) is not int or not 0 <= n <= (2**53 - 1):
        raise InvalidChallenge("invalid_millis")
    return n


class NonceLedger:
    def __init__(self, path: str | Path, *, max_records: int = 100_000):
        self.path = Path(path)
        if self.path == Path(":memory:") or not self.path.parent.is_dir():
            raise ValueError("persistent owner-only directory required")
        if self.path.is_symlink() or self.path.parent.stat().st_mode & 0o077:
            raise ValueError("unsafe database path or parent permissions")
        if type(max_records) is not int or max_records < 1:
            raise ValueError("invalid record capacity")
        self.path = self.path.absolute()
        self.max_records = max_records
        self._initialize()

    def _connect(self):
        con = sqlite3.connect(str(self.path), timeout=5, isolation_level=None)
        try:
            con.execute("PRAGMA journal_mode=WAL")
            con.execute("PRAGMA synchronous=FULL")
            con.execute("PRAGMA busy_timeout=5000")
            con.execute("PRAGMA trusted_schema=OFF")
            return con
        except Exception:
            con.close()
            raise

    def _initialize(self):
        try:
            with closing(self._connect()) as con:
                con.execute("""CREATE TABLE IF NOT EXISTS challenge(
                    nonce_sha256 BLOB PRIMARY KEY CHECK(length(nonce_sha256)=32),
                    kind TEXT NOT NULL CHECK(kind IN ('dev','localkey')),
                    candidate_fp TEXT NOT NULL, token_id TEXT NOT NULL,
                    issued_ms INTEGER NOT NULL, expires_ms INTEGER NOT NULL,
                    consumed_ms INTEGER,
                    status TEXT NOT NULL CHECK(status IN ('issued','consumed')),
                    CHECK((status='issued' AND consumed_ms IS NULL) OR
                          (status='consumed' AND consumed_ms IS NOT NULL))
                )""")
                ver = con.execute("PRAGMA user_version").fetchone()[0]
                if ver not in (0, 1):
                    raise NonceLedgerError("schema_version_unknown")
                if ver == 0:
                    con.execute("PRAGMA user_version=1")
                if con.execute("PRAGMA integrity_check").fetchone()[0] != "ok":
                    raise NonceLedgerError("integrity_unknown")
        except (sqlite3.Error, OSError) as exc:
            raise NonceLedgerError("initialization_unknown") from exc
        if not self.path.is_file() or self.path.is_symlink():
            raise NonceLedgerError("unsafe_database_file")
        os.chmod(self.path, 0o600)

    def register(self, nonce: str, *, kind: str, candidate_fingerprint: str,
                 token_id: str, issued_ms: int, expires_ms: int) -> bool:
        """First registration only. No retry after unknown SQLite commit."""
        digest = nonce_hash(nonce)
        kind, fp, token = binding(kind, candidate_fingerprint, token_id)
        issued_ms, expires_ms = millis(issued_ms), millis(expires_ms)
        if not issued_ms < expires_ms <= issued_ms + MAX_AGE_MS:
            raise InvalidChallenge("invalid_lifetime")
        try:
            with closing(self._connect()) as con:
                con.execute("BEGIN IMMEDIATE")
                if con.execute("SELECT COUNT(*) FROM challenge").fetchone()[0] >= self.max_records:
                    con.execute("ROLLBACK")
                    raise NonceLedgerError("ledger_full")
                inserted = con.execute("""INSERT OR IGNORE INTO challenge
                    (nonce_sha256,kind,candidate_fp,token_id,issued_ms,
                     expires_ms,consumed_ms,status)
                    VALUES (?,?,?,?,?,?,NULL,'issued')""",
                    (digest, kind, fp, token, issued_ms, expires_ms)).rowcount
                con.execute("COMMIT")
                return inserted == 1
        except NonceLedgerError:
            raise
        except (sqlite3.Error, OSError) as exc:
            raise NonceLedgerError("commit_state_unknown") from exc

    def consume(self, nonce: str, *, kind: str, candidate_fingerprint: str,
                token_id: str, now_ms: int) -> bool:
        """Exactly one committed consumption; only True permits proof issuance."""
        digest = nonce_hash(nonce)
        kind, fp, token = binding(kind, candidate_fingerprint, token_id)
        now_ms = millis(now_ms)
        try:
            with closing(self._connect()) as con:
                con.execute("BEGIN IMMEDIATE")
                changed = con.execute("""UPDATE challenge
                    SET status='consumed',consumed_ms=?
                    WHERE nonce_sha256=? AND kind=? AND candidate_fp=?
                    AND token_id=? AND status='issued'
                    AND issued_ms <= ? AND ? < expires_ms""",
                    (now_ms, digest, kind, fp, token, now_ms, now_ms)).rowcount
                con.execute("COMMIT")
                return changed == 1
        except (sqlite3.Error, OSError) as exc:
            raise NonceLedgerError("commit_state_unknown") from exc

    def counts(self) -> tuple[int, int]:
        """Nonsecret audit: no nonce/token values exposed."""
        try:
            with closing(self._connect()) as con:
                total, consumed = con.execute("""SELECT COUNT(*),
                    SUM(CASE WHEN status='consumed' THEN 1 ELSE 0 END)
                    FROM challenge""").fetchone()
                return int(total), int(consumed or 0)
        except (sqlite3.Error, OSError) as exc:
            raise NonceLedgerError("read_unknown") from exc
