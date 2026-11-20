"""Issue #73: isolated HTTPS credential-proof adapter for the C3-C1 gate.

This is a *loopback-only TLS integration harness*, not a deployed public
production endpoint, not a credential enrollment API and not a mobile
provisioning script. Its callable components are intended for later auditing
against the owner's PRIVATE server service. NEVER put a real pairing token,
signing private key or target hostname into this public repository.

Trust boundary:
* A dedicated, independent high-entropy pairing bearer secret (not the old
  EXPOSED DEV token and not the credential being promoted) authenticates the
  request over real TLS.
* The request provides no token value and cannot create/activate registry
  credentials. The server-owned registry atomically verifies role, status,
  expiry, kind, ID and fingerprint while consuming a one-time nonce.
* A new proof is signed only after successful SQLite COMMIT.
* No request body, authorization header or response contents are logged.
* This does not establish device-side nonce durability or proof privacy.
"""
from __future__ import annotations

import hmac
import json
import re
import ssl
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Callable

from nonce_ledger_sqlite import NonceLedger, NonceLedgerError, InvalidChallenge, nonce_hash, binding
from atomic_signed_proof_issuer import AtomicSignedProofIssuer
from signed_proof_issuer import ProofIssuanceError
from token_registry_sqlite import TokenRegistry

BODY_LIMIT = 2048
PAIRING_RE = re.compile(r"^[A-Za-z0-9_-]{43,128}$", re.ASCII)
REQUIRED_FIELDS = frozenset(("nonce", "kind", "token_id", "candidate_fingerprint"))
RESULT_HEADERS = {"Cache-Control": "no-store", "Pragma": "no-cache",
                  "X-Content-Type-Options": "nosniff"}


def _unique_pairs(pairs):
    obj = {}
    for k, v in pairs:
        if k in obj:
            raise ValueError("duplicate_json_key")
        obj[k] = v
    return obj


def _encode(result: dict) -> bytes:
    return json.dumps(result, separators=(",", ":"), ensure_ascii=True).encode("ascii")


class HTTPSProofService:
    """Internal, explicitly authenticated server-only endpoint.

    The independent bearer value MUST be provisioned outside GitHub, distinct
    from both old exposed DEV token and the new/backup tokens.
    """

    def __init__(self, registry: TokenRegistry, ledger: NonceLedger, signer,
                 *, pairing_secret: str, old_token_id: str,
                 clock_ms: Callable[[], int] | None = None):
        if not isinstance(registry, TokenRegistry) or not isinstance(ledger, NonceLedger):
            raise ValueError("durable_registry_and_ledger_required")
        if registry.ledger.path != ledger.path:
            raise ValueError("different_databases_for_registry_and_ledger")
        if not isinstance(pairing_secret, str) or PAIRING_RE.fullmatch(pairing_secret) is None:
            raise ValueError("independent_high_entropy_pairing_secret_required")
        if not isinstance(old_token_id, str) or not old_token_id:
            raise ValueError("trusted_old_token_identity_required")
        if not callable(getattr(signer, "sign", None)):
            raise ValueError("server_owned_signing_key_required")
        self.ledger = ledger
        self.registry = registry
        self._auth_bytes = pairing_secret.encode("ascii")
        self.old_token_id = old_token_id
        self._clock_ms = clock_ms or (lambda: time.time_ns() // 1_000_000)
        self.issuer = AtomicSignedProofIssuer(
            registry, signer, lambda session, _token_id, _kind: session is self,
            now_ms=self._clock_ms)

    def _register_nonce(self, nonce: str, *, kind: str,
                        candidate_fingerprint: str, token_id: str,
                        issued_ms: int, expires_ms: int) -> bool:
        """Override ONLY with a separately reviewed witness-fenced writer."""
        return self.ledger.register(
            nonce, kind=kind, candidate_fingerprint=candidate_fingerprint,
            token_id=token_id, issued_ms=issued_ms, expires_ms=expires_ms)

    def _issue_proof(self, *, session: object, nonce: str, token_id: str,
                     kind: str, candidate_fingerprint: str,
                     exposed_old_token_id: str) -> dict:
        """The default isolated historical path, NOT a production GO."""
        return self.issuer.issue(
            session=session, nonce=nonce, token_id=token_id,
            kind=kind, candidate_fingerprint=candidate_fingerprint,
            exposed_old_token_id=exposed_old_token_id)

    def _authenticated(self, authorization: str | None) -> bool:
        if not isinstance(authorization, str) or not authorization.startswith("Bearer "):
            return False
        value = authorization[len("Bearer "):]
        if PAIRING_RE.fullmatch(value) is None:
            return False
        return hmac.compare_digest(self._auth_bytes, value.encode("ascii"))

    def handle(self, *, body: bytes, authorization: str | None,
               content_type: str) -> tuple[int, bytes]:
        """Never accept a request over plaintext; TLS enforced by listener."""
        if not self._authenticated(authorization):
            return 401, _encode({"status": "unauthorized"})
        if content_type != "application/json" or not isinstance(body, bytes) or (
            not 1 <= len(body) <= BODY_LIMIT
        ):
            return 400, _encode({"status": "invalid_request"})
        try:
            data = json.loads(body.decode("utf-8"), object_pairs_hook=_unique_pairs)
            if not isinstance(data, dict) or frozenset(data) != REQUIRED_FIELDS:
                raise ValueError("unexpected_request_fields")
            nonce = data["nonce"]
            kind = data["kind"]
            token_id = data["token_id"]
            fp = data["candidate_fingerprint"]
            # Validate all fields before any database writes.
            nonce_hash(nonce)
            binding(kind, fp, token_id)
            now = self._clock_ms()
            if type(now) is not int or not 0 < now < 2**53 - 61_000:
                raise ValueError("invalid_server_clock")
        except (ValueError, TypeError, UnicodeError, InvalidChallenge):
            return 400, _encode({"status": "invalid_request"})
        except Exception:
            return 503, _encode({"status": "clock_unknown"})

        # Registration is an internal step of this authenticated request.
        # The nonce cannot be re-registered (even if previous signing failed).
        try:
            registered = self._register_nonce(
                nonce, kind=kind, candidate_fingerprint=fp,
                token_id=token_id, issued_ms=now, expires_ms=now + 60_000)
        except (NonceLedgerError, OSError, RuntimeError):
            # RuntimeError covers an independently unavailable witness;
            # abort before issuing a proof. Never retry an unknown commit.
            return 503, _encode({"status": "nonce_store_unknown"})
        if not registered:
            return 409, _encode({"status": "nonce_reused"})

        try:
            signed_proof = self._issue_proof(
                session=self, nonce=nonce, token_id=token_id, kind=kind,
                candidate_fingerprint=fp, exposed_old_token_id=self.old_token_id)
            return 200, _encode(signed_proof)
        except ProofIssuanceError:
            # The nonce is deliberately burned, or the commit is ambiguous.
            # Do NOT automatically retry this nonce or fall back to old token.
            return 403, _encode({"status": "proof_not_authorized"})
        except Exception:
            return 503, _encode({"status": "proof_unknown"})


class _Handler(BaseHTTPRequestHandler):
    server_version = "Issue73ProofGate"
    sys_version = ""
    protocol_version = "HTTP/1.1"

    def log_message(self, *args):
        # Authorization headers, nonce and token IDs MUST NOT enter logs.
        return

    def _respond(self, code: int, payload: bytes):
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        for name, value in RESULT_HEADERS.items():
            self.send_header(name, value)
        self.end_headers()
        self.wfile.write(payload)

    def do_GET(self):
        self._respond(405, _encode({"status": "method_not_allowed"}))

    def do_POST(self):
        if self.path != "/credential-proof":
            self._respond(404, _encode({"status": "not_found"}))
            return
        # Never accept streaming/ambiguous body framing in this reference.
        if (self.headers.get("Transfer-Encoding") is not None or
            len(self.headers.get_all("Content-Length", [])) != 1):
            self.close_connection = True
            self._respond(400, _encode({"status": "invalid_request"}))
            return
        try:
            length = int(self.headers.get("Content-Length", ""), 10)
        except ValueError:
            length = 0
        if not 1 <= length <= BODY_LIMIT:
            self.close_connection = True
            self._respond(413, _encode({"status": "invalid_request"}))
            return
        content_type = self.headers.get("Content-Type", "")
        auth = self.headers.get("Authorization")
        data = self.rfile.read(length)
        code, response = self.server.proof_service.handle(
            body=data, content_type=content_type, authorization=auth)
        self._respond(code, response)


class LoopbackTLSServer(ThreadingHTTPServer):
    """Real HTTPS socket; loopback binding ONLY, no public deployment here."""

    daemon_threads = True

    def __init__(self, service: HTTPSProofService, tls_context: ssl.SSLContext,
                 address: tuple[str, int] = ("127.0.0.1", 0)):
        host, port = address
        if host != "127.0.0.1":
            raise ValueError("public_network_binding_not_authorized")
        if not isinstance(tls_context, ssl.SSLContext):
            raise ValueError("TLS_context_required")
        if tls_context.minimum_version < ssl.TLSVersion.TLSv1_2:
            raise ValueError("TLS_1_2_minimum_required")
        super().__init__((host, port), _Handler)
        self.proof_service = service
        try:
            self.socket = tls_context.wrap_socket(self.socket, server_side=True)
        except Exception:
            self.server_close()
            raise


def serve_in_thread(server: LoopbackTLSServer):
    """Tests only. Caller MUST stop server and join thread."""
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    return thread
