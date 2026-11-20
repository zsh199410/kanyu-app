"""Issue73: two-process localhost HTTPS anchor authority and client, staging ONLY.

This is a protocol demonstration, not a deployed independent failure domain.
A production witness MUST run on an independently administered host with
separately protected storage, backups, credentials and certificate/key custody.
The business signer MUST NOT have the anchor private signing key.

The only network mutation is POST /advance, authenticated using a dedicated
bearer over verified TLS. The authority CASes a persistent monotonic epoch
and prior state digest, commits SQLite, then returns an independently signed
Ed25519 checkpoint. No remote bootstrap/reset/delete endpoint exists.

The client independently validates TLS and the pinned Ed25519 root, and
compares the returned signed checkpoint with the actual business DB before
letting PR115 return any signed proof. No retry on unknown remote commit.
"""
from __future__ import annotations

import base64
import hmac
import json
import re
import sqlite3
import ssl
import threading
from contextlib import closing
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Callable
from urllib.error import HTTPError, URLError
from urllib.parse import urlsplit
from urllib.request import HTTPSHandler, ProxyHandler, Request, build_opener

from recovery_signed_checkpoint import (
    PURPOSE, RecoveryNotVerified, _canonical, logical_state_sha256,
    require_signed_recovery_checkpoint,
)

SHA = re.compile(r"^[0-9a-f]{64}$")
BEARER = re.compile(r"^[A-Za-z0-9_-]{43,128}$", re.ASCII)
MAX_BODY = 640


class RemoteAnchorDenied(RuntimeError):
    """No secret data, no unsafe retry on unknown/failed commit."""


def _valid_sha(v):
    if type(v) is not str or SHA.fullmatch(v) is None:
        raise RemoteAnchorDenied("invalid_digest")
    return v


def _encode(v):
    return json.dumps(v, separators=(",", ":"), ensure_ascii=True).encode("ascii")


def _strict_pairs(pairs):
    out = {}
    for key, value in pairs:
        if key in out:
            raise ValueError("duplicate_json_key")
        out[key] = value
    return out


class AnchorAuthorityStore:
    """Local SQLite stand-in; move to a genuinely separate secure host."""

    def __init__(self, path: Path, ed25519_signer):
        path = Path(path)
        if (not path.parent.is_dir() or
            path.parent.stat().st_mode & 0o077 or path.is_symlink()):
            raise ValueError("owner_only_anchor_directory_required")
        if not callable(getattr(ed25519_signer, "sign", None)):
            raise ValueError("trusted_private_signer_required")
        self.path = path.absolute()
        self._signer = ed25519_signer
        try:
            with closing(self._connect()) as db:
                db.execute("""CREATE TABLE IF NOT EXISTS anchor_head(
                    id INTEGER PRIMARY KEY CHECK(id=1),
                    epoch INTEGER NOT NULL CHECK(epoch>=1),
                    state_sha256 TEXT NOT NULL CHECK(length(state_sha256)=64)
                )""")
        except sqlite3.Error as exc:
            raise RemoteAnchorDenied("anchor_storage_unknown") from exc
        self._lock = threading.Lock()

    def _connect(self):
        db = sqlite3.connect(self.path, timeout=3, isolation_level=None)
        try:
            db.execute("PRAGMA journal_mode=WAL")
            db.execute("PRAGMA synchronous=FULL")
            db.execute("PRAGMA busy_timeout=3000")
            return db
        except Exception:
            db.close()
            raise

    def _signed(self, epoch, digest):
        body = {"purpose": PURPOSE, "epoch": epoch,
                "state_sha256": digest}
        body["signature"] = base64.b64encode(
            self._signer.sign(_canonical(PURPOSE, epoch, digest))
        ).decode("ascii")
        return body

    def bootstrap(self, initial_digest, *, authorized_offline: bool):
        """Offline operator ONLY. Inaccessible through the TLS listener."""
        initial_digest = _valid_sha(initial_digest)
        if authorized_offline is not True:
            raise RemoteAnchorDenied("trusted_bootstrap_required")
        with self._lock, closing(self._connect()) as db:
            try:
                db.execute("BEGIN IMMEDIATE")
                if db.execute("SELECT 1 FROM anchor_head").fetchone():
                    db.execute("ROLLBACK")
                    return False
                db.execute("INSERT INTO anchor_head VALUES (1,1,?)",
                           (initial_digest,))
                db.execute("COMMIT")
                return True
            except sqlite3.Error as exc:
                raise RemoteAnchorDenied("bootstrap_commit_unknown") from exc

    def head(self):
        try:
            with closing(self._connect()) as db:
                row = db.execute(
                    "SELECT epoch,state_sha256 FROM anchor_head WHERE id=1"
                ).fetchone()
        except sqlite3.Error as exc:
            raise RemoteAnchorDenied("anchor_read_unknown") from exc
        if row is None:
            raise RemoteAnchorDenied("anchor_not_initialized")
        return self._signed(*row)

    def advance(self, *, expected_epoch, expected_digest, state_sha256):
        if type(expected_epoch) is not int or not (1 <= expected_epoch < 2**53 - 1):
            raise RemoteAnchorDenied("epoch_invalid")
        expected_digest = _valid_sha(expected_digest)
        state_sha256 = _valid_sha(state_sha256)
        if expected_digest == state_sha256:
            raise RemoteAnchorDenied("state_not_changed")
        # Serialize every committed update against the authoritative
        # persistent head; no client-provided epoch can skip or rewind.
        with self._lock, closing(self._connect()) as db:
            try:
                db.execute("BEGIN IMMEDIATE")
                row = db.execute(
                    "SELECT epoch,state_sha256 FROM anchor_head WHERE id=1"
                ).fetchone()
                if row != (expected_epoch, expected_digest):
                    db.execute("ROLLBACK")
                    raise RemoteAnchorDenied("stale_or_conflicting_anchor")
                epoch = expected_epoch + 1
                db.execute("UPDATE anchor_head SET epoch=?,state_sha256=? WHERE id=1",
                           (epoch, state_sha256))
                db.execute("COMMIT")
            except RemoteAnchorDenied:
                raise
            except sqlite3.Error as exc:
                raise RemoteAnchorDenied("anchor_commit_unknown") from exc
            return self._signed(epoch, state_sha256)


class _AnchorHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "Issue73AnchorStaging"
    sys_version = ""

    def log_message(self, *_args):
        # No authentication material, nonce or digest in access logs.
        pass

    def _reply(self, code, body):
        payload = _encode(body)
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        self.wfile.write(payload)

    def _authenticated(self):
        auth = self.headers.get("Authorization")
        if not isinstance(auth, str) or not auth.startswith("Bearer "):
            return False
        value = auth[7:]
        if BEARER.fullmatch(value) is None:
            return False
        return hmac.compare_digest(
            self.server.auth_secret, value.encode("ascii")
        )

    def do_GET(self):
        if self.path != "/head":
            self._reply(404, {"status": "not_found"})
            return
        if not self._authenticated():
            self._reply(401, {"status": "unauthorized"})
            return
        try:
            self._reply(200, self.server.anchor_store.head())
        except RemoteAnchorDenied:
            self._reply(503, {"status": "anchor_unavailable"})

    def do_POST(self):
        if self.path != "/advance":
            self._reply(404, {"status": "not_found"})
            return
        if not self._authenticated():
            self._reply(401, {"status": "unauthorized"})
            return
        if (self.headers.get("Transfer-Encoding") is not None or
            len(self.headers.get_all("Content-Length", [])) != 1 or
            self.headers.get("Content-Type") != "application/json"):
            self.close_connection = True
            self._reply(400, {"status": "invalid_request"})
            return
        try:
            n = int(self.headers.get("Content-Length", ""))
        except ValueError:
            n = 0
        if not (1 <= n <= MAX_BODY):
            self.close_connection = True
            self._reply(400, {"status": "invalid_request"})
            return
        try:
            data = json.loads(self.rfile.read(n).decode("ascii"),
                              object_pairs_hook=_strict_pairs)
            if type(data) is not dict or set(data) != {
                "expected_epoch", "expected_digest", "state_sha256"
            }:
                raise ValueError("invalid_fields")
        except (UnicodeError, ValueError, TypeError):
            self._reply(400, {"status": "invalid_request"})
            return
        try:
            record = self.server.anchor_store.advance(**data)
            self._reply(200, record)
        except RemoteAnchorDenied as exc:
            # Conflict distinguishes a definitive stale CAS from an
            # ambiguous storage failure. Neither is automatically retried.
            if str(exc) == "stale_or_conflicting_anchor":
                self._reply(409, {"status": "stale_anchor"})
            elif str(exc) in {"invalid_digest", "epoch_invalid", "state_not_changed"}:
                self._reply(400, {"status": "invalid_request"})
            else:
                self._reply(503, {"status": "anchor_unknown"})


class LoopbackAnchorTLSServer(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, store: AnchorAuthorityStore, *, bearer: str,
                 tls_context: ssl.SSLContext,
                 address=("127.0.0.1", 0)):
        host, port = address
        if host != "127.0.0.1":
            raise ValueError("staging_public_bind_prohibited")
        if type(bearer) is not str or BEARER.fullmatch(bearer) is None:
            raise ValueError("dedicated_pairing_secret_required")
        if not isinstance(tls_context, ssl.SSLContext) or (
            tls_context.minimum_version < ssl.TLSVersion.TLSv1_2
        ):
            raise ValueError("TLS_1_2_required")
        super().__init__(address, _AnchorHandler)
        self.anchor_store = store
        self.auth_secret = bearer.encode("ascii")
        try:
            self.socket = tls_context.wrap_socket(self.socket, server_side=True)
        except Exception:
            self.server_close()
            raise


class PinnedAnchorTLSClient:
    """Never trust a server-provided public key or epoch without signature."""

    def __init__(self, url: str, *, bearer: str,
                 ca_cert_file: str, pinned_ed25519_key: bytes):
        parsed = urlsplit(url)
        if (parsed.scheme != "https" or
            parsed.hostname not in {"localhost", "127.0.0.1"} or
            parsed.username is not None or parsed.password is not None or
            parsed.path not in {"", "/"} or parsed.query or parsed.fragment):
            raise ValueError("staging_loopback_https_only")
        if type(bearer) is not str or BEARER.fullmatch(bearer) is None:
            raise ValueError("independent_bearer_required")
        if type(pinned_ed25519_key) is not bytes or len(pinned_ed25519_key) != 32:
            raise ValueError("trusted_pinned_root_required")
        self.url = url.rstrip("/")
        self._auth = "Bearer " + bearer
        self.pinned_ed25519_key = pinned_ed25519_key
        self._ssl = ssl.create_default_context(cafile=ca_cert_file)
        self._opener = build_opener(ProxyHandler({}), HTTPSHandler(context=self._ssl))
        self._known_epoch = None
        self._known_sha = None

    def _request(self, suffix, data=None):
        request = Request(
            self.url + suffix, data=None if data is None else _encode(data),
            headers={
                "Authorization": self._auth,
                "Content-Type": "application/json",
            }, method="GET" if data is None else "POST",
        )
        try:
            with self._opener.open(request, timeout=3) as reply:
                if reply.status != 200:
                    raise RemoteAnchorDenied("remote_anchor_not_confirmed")
                body = reply.read(1025)
            if len(body) > 1024:
                raise RemoteAnchorDenied("remote_response_oversized")
            result = json.loads(body.decode("ascii"), object_pairs_hook=_strict_pairs)
            if type(result) is not dict:
                raise RemoteAnchorDenied("remote_response_shape_invalid")
            return result
        except (HTTPError, URLError, TimeoutError, ssl.SSLError,
                UnicodeError, ValueError, OSError) as exc:
            raise RemoteAnchorDenied("remote_anchor_unknown") from exc

    def _verify(self, record, ledger, *, require_advance):
        if type(record) is not dict or set(record) != {
            "purpose", "epoch", "state_sha256", "signature"
        }:
            raise RemoteAnchorDenied("remote_anchor_shape_invalid")
        epoch = record["epoch"]
        digest = record["state_sha256"]
        if type(epoch) is not int or type(digest) is not str:
            raise RemoteAnchorDenied("remote_anchor_data_invalid")
        if require_advance and (
            self._known_epoch is None or epoch <= self._known_epoch
        ):
            raise RemoteAnchorDenied("remote_epoch_not_advanced")
        try:
            require_signed_recovery_checkpoint(
                ledger, record,
                independently_pinned_public_key=self.pinned_ed25519_key,
                trusted_external_epoch=epoch,
            )
        except RecoveryNotVerified as exc:
            raise RemoteAnchorDenied("remote_signature_or_state_mismatch") from exc
        self._known_epoch = epoch
        self._known_sha = digest
        return record, epoch

    def fetch_head(self, ledger):
        """Authenticated signed remote head; perform before opening PR115."""
        record = self._request("/head")
        if self._known_epoch is not None and record.get("epoch", 0) < self._known_epoch:
            raise RemoteAnchorDenied("remote_epoch_rollback")
        return self._verify(record, ledger, require_advance=False)

    def commit_and_fetch_anchor(self, ledger):
        """Adapter for PR115 commit_and_fetch_anchor callback.

        If network times out after remote commit, fail closed; caller
        must explicitly reconcile via fresh signed /head, not auto retry.
        """
        if self._known_epoch is None or self._known_sha is None:
            raise RemoteAnchorDenied("remote_head_unverified")
        after = logical_state_sha256(ledger)
        if after == self._known_sha:
            raise RemoteAnchorDenied("missing_business_state_transition")
        data = {
            "expected_epoch": self._known_epoch,
            "expected_digest": self._known_sha,
            "state_sha256": after,
        }
        record = self._request("/advance", data)
        return self._verify(record, ledger, require_advance=True)
