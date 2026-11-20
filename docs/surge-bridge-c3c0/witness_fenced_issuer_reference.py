"""Issue73: fail-closed, monotonic witness *protocol reference*.

The witness SQLite here is ONLY a test stand-in for a separately hosted,
authenticated, rollback-resistant control plane. Never place its backing
database on the same VPS, shared volume, backup or credential domain as
the real token/nonce SQLite database.

Security ordering for a signed proof:
1. Admission/drain gate (separate PR113, ALL HTTP routes must use it).
2. Reconcile exact logical state digest with the outside witness.
3. Register nonce in business DB, advance independent witness digest.
4. Atomic token+nonce consume in business DB.
5. Advance independent witness with consumed-nonce tombstone BEFORE
   invoking the Ed25519 private signer.
6. If any write or acknowledgment is missing/unknown, DO NOT sign.
A restored old business DB does not match the independent witness digest.

This module does NOT deploy an external server, authenticated protocol,
independent failure domain, signing-key vault, or real-device gate.
"""
from __future__ import annotations

import os
import re
import sqlite3
import threading
from contextlib import closing
from pathlib import Path
from typing import Callable

from atomic_signed_proof_issuer import AtomicSignedProofIssuer
from nonce_ledger_sqlite import NonceLedger, nonce_hash
from recovery_signed_checkpoint import logical_state_sha256
from staging_issuance_drain import IssuanceDrainGate
from token_registry_sqlite import TokenRegistry, valid_id

HEX64 = re.compile(r"^[0-9a-f]{64}$")


class WitnessRejected(RuntimeError):
    """Nonsecret, fail-closed; do not retry an uncertain commit."""


def _sha(s: str) -> str:
    if not isinstance(s, str) or HEX64.fullmatch(s) is None:
        raise WitnessRejected("invalid_state_digest")
    return s


class IndependentWitnessTestDouble:
    """SQLite stand-in for an external append-only service, NOT production."""

    def __init__(self, path: str | Path):
        self.path = Path(path)
        if (self.path == Path(":memory:") or
            not self.path.parent.is_dir() or
            self.path.parent.stat().st_mode & 0o077 or
            self.path.is_symlink()):
            raise ValueError("witness_requires_owner_only_persistent_directory")
        self.path = self.path.absolute()
        try:
            with closing(self._connect()) as db:
                db.execute("""CREATE TABLE IF NOT EXISTS witness_head(
                    singleton INTEGER PRIMARY KEY CHECK(singleton=1),
                    epoch INTEGER NOT NULL CHECK(epoch>0),
                    state_sha256 TEXT NOT NULL,
                    frozen INTEGER NOT NULL CHECK(frozen IN (0,1))
                )""")
                db.execute("""CREATE TABLE IF NOT EXISTS consumed(
                    nonce_digest BLOB PRIMARY KEY CHECK(length(nonce_digest)=32),
                    token_id TEXT NOT NULL,
                    epoch INTEGER NOT NULL
                )""")
                db.execute("""CREATE TABLE IF NOT EXISTS blocked(
                    token_id TEXT PRIMARY KEY,
                    epoch INTEGER NOT NULL
                )""")
                if db.execute("PRAGMA integrity_check").fetchone()[0] != "ok":
                    raise WitnessRejected("witness_integrity_unknown")
        except (sqlite3.Error, OSError) as exc:
            raise WitnessRejected("witness_initialization_unknown") from exc
        os.chmod(self.path, 0o600)

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

    def bootstrap(self, signed_initial_state_sha: str, *,
                  trusted_operator_approved: bool = False) -> bool:
        """Explicit staging setup. Never bootstrap from a restored DB."""
        initial = _sha(signed_initial_state_sha)
        if trusted_operator_approved is not True:
            raise WitnessRejected("trusted_bootstrap_missing")
        try:
            with closing(self._connect()) as db:
                db.execute("BEGIN IMMEDIATE")
                exists = db.execute(
                    "SELECT epoch FROM witness_head WHERE singleton=1"
                ).fetchone()
                if exists:
                    db.execute("ROLLBACK")
                    return False
                db.execute(
                    "INSERT INTO witness_head VALUES (1,1,?,0)", (initial,)
                )
                db.execute("COMMIT")
                return True
        except (sqlite3.Error, OSError) as exc:
            raise WitnessRejected("bootstrap_commit_unknown") from exc

    def head(self) -> dict:
        try:
            with closing(self._connect()) as db:
                row = db.execute("""SELECT epoch,state_sha256,frozen
                    FROM witness_head WHERE singleton=1""").fetchone()
        except (sqlite3.Error, OSError) as exc:
            raise WitnessRejected("witness_read_unknown") from exc
        if row is None:
            raise WitnessRejected("witness_not_bootstrapped")
        return {"epoch": row[0], "state_sha256": row[1],
                "frozen": row[2] == 1}

    def require_fresh(self, state_sha: str) -> bool:
        state_sha = _sha(state_sha)
        h = self.head()
        if h["frozen"]:
            raise WitnessRejected("witness_frozen")
        if h["state_sha256"] != state_sha:
            raise WitnessRejected("database_rollback_or_unknown_mutation")
        return True

    def advance(self, before: str, after: str, *,
                nonce: str | None = None, token_id: str | None = None,
                revoke_token_id: str | None = None) -> int:
        """Compare-and-swap state digest, append tombstone, monotonic epoch.

        A caller MUST NOT create a signature before the durable COMMIT of
        this operation. A committed but unacknowledged transition is an
        unknown outcome; reject and reconcile rather than retry.
        """
        before, after = _sha(before), _sha(after)
        if before == after:
            raise WitnessRejected("state_transition_not_observed")
        if (nonce is None) != (token_id is None):
            raise WitnessRejected("incomplete_nonce_binding")
        digest = nonce_hash(nonce) if nonce is not None else None
        token_id = valid_id(token_id) if token_id is not None else None
        revoked = (valid_id(revoke_token_id) if revoke_token_id is not None
                   else None)
        try:
            with closing(self._connect()) as db:
                db.execute("BEGIN IMMEDIATE")
                row = db.execute("""SELECT epoch,state_sha256,frozen
                    FROM witness_head WHERE singleton=1""").fetchone()
                if row is None or row[2] != 0 or row[1] != before:
                    db.execute("ROLLBACK")
                    raise WitnessRejected("witness_state_conflict")
                if token_id and db.execute(
                    "SELECT 1 FROM blocked WHERE token_id=?",
                    (token_id,)
                ).fetchone():
                    db.execute("ROLLBACK")
                    raise WitnessRejected("token_fenced_by_witness")
                epoch = row[0] + 1
                if epoch > 2**53 - 1:
                    db.execute("ROLLBACK")
                    raise WitnessRejected("epoch_exhausted")
                if digest is not None:
                    if db.execute(
                        "SELECT 1 FROM consumed WHERE nonce_digest=?",
                        (digest,)
                    ).fetchone():
                        db.execute("ROLLBACK")
                        raise WitnessRejected("nonce_fenced_by_witness")
                    db.execute(
                        "INSERT INTO consumed VALUES (?,?,?)",
                        (digest, token_id, epoch)
                    )
                if revoked is not None:
                    db.execute(
                        "INSERT OR IGNORE INTO blocked VALUES (?,?)",
                        (revoked, epoch)
                    )
                db.execute("""UPDATE witness_head
                    SET epoch=?,state_sha256=?
                    WHERE singleton=1""", (epoch, after))
                db.execute("COMMIT")
                return epoch
        except WitnessRejected:
            raise
        except (sqlite3.Error, OSError) as exc:
            raise WitnessRejected("witness_commit_unknown") from exc

    def counts(self):
        try:
            with closing(self._connect()) as db:
                return tuple(db.execute(
                    "SELECT (SELECT COUNT(*) FROM consumed),"
                    "(SELECT COUNT(*) FROM blocked)"
                ).fetchone())
        except (sqlite3.Error, OSError) as exc:
            raise WitnessRejected("witness_counts_unknown") from exc


class _WitnessedSigner:
    def __init__(self, witness, signer, ledger, before_sha, expected_token_id):
        self.witness, self.signer = witness, signer
        self.ledger, self.before_sha = ledger, before_sha
        self.expected_token_id = expected_token_id

    def sign(self, canonical: bytes) -> bytes:
        import json
        try:
            p = json.loads(canonical)
            if (p.get("purpose") != "issue73/credential-promotion/v1"
                    or p.get("token_id") != self.expected_token_id
                    or not isinstance(p.get("nonce"), str)):
                raise WitnessRejected("canonical_proof_mismatch")
        except (ValueError, UnicodeError, AttributeError, TypeError) as exc:
            raise WitnessRejected("canonical_proof_invalid") from exc
        after_sha = logical_state_sha256(self.ledger)
        # This irreversible external append happens BEFORE any private-key
        # signature, and a lost acknowledgment can only cause a rejection.
        self.witness.advance(
            self.before_sha, after_sha,
            nonce=p["nonce"], token_id=self.expected_token_id)
        return self.signer.sign(canonical)


class WitnessedAtomicService:
    """Serial, single-process staging wrapper; no HTTP endpoints or auth."""

    def __init__(self, registry: TokenRegistry, signer,
                 authorize_session: Callable, witness: IndependentWitnessTestDouble,
                 now_ms: Callable, gate: IssuanceDrainGate):
        if not isinstance(registry, TokenRegistry):
            raise ValueError("authoritative_registry_required")
        if not isinstance(witness, IndependentWitnessTestDouble):
            raise ValueError("trusted_external_witness_required")
        if not isinstance(gate, IssuanceDrainGate):
            raise ValueError("shared_admission_drain_gate_required")
        if registry.ledger.path == witness.path:
            raise ValueError("witness_must_not_share_business_sqlite")
        if not callable(authorize_session) or not callable(now_ms):
            raise ValueError("session_and_trusted_clock_required")
        if not callable(getattr(signer, "sign", None)):
            raise ValueError("real_ed25519_signer_required")
        self.registry, self.witness = registry, witness
        self.signer, self.authorize_session = signer, authorize_session
        self.now_ms, self.gate = now_ms, gate
        self.lock = threading.RLock()

    def _checked_before(self):
        before = logical_state_sha256(self.registry.ledger)
        self.witness.require_fresh(before)
        return before

    def register(self, nonce, *, kind, candidate_fingerprint,
                 token_id, issued_ms, expires_ms) -> bool:
        with self.gate.admission(), self.lock:
            before = self._checked_before()
            ok = self.registry.ledger.register(
                nonce, kind=kind, candidate_fingerprint=candidate_fingerprint,
                token_id=token_id, issued_ms=issued_ms,
                expires_ms=expires_ms)
            if not ok:
                return False
            after = logical_state_sha256(self.registry.ledger)
            self.witness.advance(before, after)
            return True

    def issue(self, *, session, nonce, token_id, kind,
              candidate_fingerprint, exposed_old_token_id,
              ttl_ms=60_000):
        with self.gate.admission(), self.lock:
            before = self._checked_before()
            wrapped_signer = _WitnessedSigner(
                self.witness, self.signer,
                self.registry.ledger, before, token_id)
            issuer = AtomicSignedProofIssuer(
                self.registry, wrapped_signer, self.authorize_session,
                now_ms=self.now_ms)
            return issuer.issue(
                session=session, nonce=nonce, token_id=token_id,
                kind=kind, candidate_fingerprint=candidate_fingerprint,
                exposed_old_token_id=exposed_old_token_id,
                ttl_ms=ttl_ms)

    def admin_transition(self, operation: Callable[[], bool],
                         readback: Callable[[], bool], *,
                         revoked_token_id: str | None = None) -> bool:
        """Admin-only: admission freeze, drain, durable state, readback."""
        if not callable(operation) or not callable(readback):
            raise ValueError("trusted_admin_callbacks_required")

        def change():
            with self.lock:
                before = self._checked_before()
                if operation() is not True:
                    raise WitnessRejected("admin_change_failed_frozen")
                after = logical_state_sha256(self.registry.ledger)
                self.witness.advance(
                    before, after, revoke_token_id=revoked_token_id)
                return True

        return self.gate.guarded_admin_change(change, readback)
