"""Fail-closed safe-egress selector controller (A2).

Controls ONE Surge 5 select group ("测试安全出口") through the Surge
official HTTP API, and only that group. Stdlib only (urllib).

API used (Surge HTTP API):
  POST /v1/policy_groups/select
       body {"group_name": "测试安全出口", "policy": "<name>"}
  GET  /v1/policy_groups/select?group_name=<name>   -> read-back verification
  GET  /v1/policy_groups                            -> group/member listing
       (used by verify_config_loaded to confirm the device actually
       loaded the expected test profile before any selection is made)

Safety semantics (fail-closed):
  * A proxy is selected ONLY after: candidate health check passes,
    candidate-set SHA matches the expected version, the member name is
    verified against the device's own member list, and the POST is
    confirmed by a GET read-back returning the same policy.
  * No healthy proxy / stale evidence / STOP active / version mismatch:
    the controller ATTEMPTS an explicit select of REJECT and confirms it
    by GET read-back. REJECT_VERIFIED is the only safe terminal state.
  * If the POST times out, returns an indeterminate result, or the GET
    read-back fails, the controller does NOT claim REJECT. It records
    SELECTION_UNKNOWN (or CONTROLLER_UNAVAILABLE when the API itself is
    unreachable) and reports allow_production=False. "Unknown" is never
    reported as safe.
  * STOP: when the stop flag is set the controller refuses any proxy
    selection, attempts REJECT, and records STOPPED.

Three safety questions — honest answers (also in README.md):

  Q1. Does the selection survive a phone restart?
      A: Yes — Surge persists a select group's choice with the profile,
      so the previous selection is still active after a restart. The
      controller therefore NEVER trusts a persisted choice: on startup
      (startup_reverify) it loads the state file (which load_state()
      already marks unverified), re-reads the live selection with GET,
      and only re-marks it verified when the live value matches the
      expected policy AND the evidence is fresh. An old selection that
      fails re-verification is treated as unknown and the controller
      attempts an explicit REJECT.

  Q2. How does the controller stop an old selection from being used
      after the controller loses contact with the device?
      A: It cannot. The controller has no remote kill-switch over the
      device: once a proxy is selected, the device keeps using it until
      something on the device changes the selection. Loss of contact
      only lets the controller record CONTROLLER_UNAVAILABLE /
      SELECTION_UNKNOWN and refuse to authorise further production use
      from its side. It cannot force the device to REJECT. Any claim
      that "controller loss automatically reverts the device to REJECT"
      would be false.

  Q3. Can the device itself reliably fall back to REJECT when the
      controller fails?
      A: NOT PROVEN. There is no device-side mechanism demonstrated in
      this task (no on-device script, no Surge-side rule, no watchdog)
      that provably switches the group to REJECT without the
      controller. The select group's first member is REJECT, which is
      the *default* only when the group has never had a selection made
      (or the profile is freshly loaded without a stored choice) — it
      does NOT retroactively override a previously selected proxy.
      Therefore the "controller failure -> device auto-REJECT" capability
      is marked UNPROVEN. Fail-closed is NOT claimed as complete.
      The honest residual risk: a selected proxy can keep serving after
      controller failure until a human (or a future on-device mechanism)
      intervenes. The manual rollback entry point is rollback_to_reject().

Logging: structured JSON lines. Candidate / credential data is never
logged. Only policy names, SHAs, states and reasons are logged; any
dict passed to the logger is passed through _sanitize(), which redacts
keys matching password/token/secret/key/uri/url and values that look
like proxy URIs.

The API client is injectable: pass request_fn(method, url, body, timeout)
returning (status:int, body:bytes). Tests substitute a mock Surge server.
"""

from __future__ import annotations

import hashlib
import ipaddress
import json
import os
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request

# The state module lives in selector-state.py (hyphenated filename), so
# import it by file location instead of by module name.
import importlib.util  # noqa: E402

_SPEC = importlib.util.spec_from_file_location(
    "selector_state_mod",
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "selector-state.py"),
)
selector_state = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(selector_state)

GROUP_NAME = "测试安全出口"
REJECT = "REJECT"
TEST_NET = ipaddress.ip_network("192.0.2.0/24")
HEALTH_MAX_LATENCY_MS = 300
EVIDENCE_MAX_AGE_SECONDS = 24 * 3600  # candidate evidence must be < 24h old

# States that mean "do not authorise production through the test egress".
UNSAFE_STATES = frozenset(
    {
        "EVIDENCE_EXPIRED",
        "VERSION_MISMATCH",
        "SELECTION_UNKNOWN",
        "CONTROLLER_UNAVAILABLE",
        "STOPPED",
    }
)

_REDACT_KEYS = ("password", "passwd", "token", "secret", "api_key", "apikey",
                "auth", "credential", "uri", "url", "proxy_url", "private")


class ApiTimeout(Exception):
    """The API call timed out: outcome unknown, must not be treated as done."""


class ApiError(Exception):
    def __init__(self, status: int | None, message: str):
        super().__init__(message)
        self.status = status
        self.message = message


class SurgeApiClient:
    """Minimal Surge HTTP API client. request_fn is injectable for tests.

    request_fn(method, url, body_bytes_or_None, timeout_seconds)
        -> (status_code:int, response_body:bytes)
    It may raise TimeoutError / socket errors, which are converted to
    ApiTimeout / ApiError here.
    """

    def __init__(self, base_url: str, request_fn=None, timeout: float = 5.0):
        self.base_url = base_url.rstrip("/")
        self._request_fn = request_fn or self._urllib_request
        self.timeout = timeout

    # -- default transport (urllib) -------------------------------------
    @staticmethod
    def _urllib_request(method, url, body, timeout):
        req = urllib.request.Request(url, data=body, method=method)
        if body is not None:
            req.add_header("Content-Type", "application/json")
        try:
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                return resp.status, resp.read()
        except urllib.error.HTTPError as exc:
            return exc.code, exc.read()
        except (TimeoutError, urllib.error.URLError) as exc:
            # URLError wraps timeouts as well; distinguish by reason text.
            reason = getattr(exc, "reason", exc)
            if isinstance(reason, TimeoutError) or "timed out" in str(exc).lower():
                raise ApiTimeout(str(exc))
            raise ApiError(None, f"transport error: {exc}")

    # -- plumbing --------------------------------------------------------
    def _call(self, method: str, path: str, body: dict | None = None):
        url = self.base_url + path
        payload = json.dumps(body).encode("utf-8") if body is not None else None
        try:
            status, raw = self._request_fn(method, url, payload, self.timeout)
        except ApiTimeout:
            raise
        except TimeoutError as exc:
            raise ApiTimeout(str(exc))
        except ApiError:
            raise
        except Exception as exc:  # transport-level failure
            raise ApiError(None, f"transport error: {exc}")
        try:
            data = json.loads(raw.decode("utf-8")) if raw else {}
        except (ValueError, UnicodeDecodeError):
            data = {}
        if status is not None and status >= 400:
            raise ApiError(status, f"HTTP {status}: {data.get('error') or data}")
        return data

    def select_policy(self, group_name: str, policy: str) -> dict:
        return self._call(
            "POST", "/v1/policy_groups/select",
            {"group_name": group_name, "policy": policy},
        )

    def get_selected(self, group_name: str) -> str:
        path = "/v1/policy_groups/select?group_name=" + urllib.parse.quote(
            group_name
        )
        data = self._call("GET", path)
        policy = data.get("policy") or data.get("selected") or data.get("name")
        if not policy:
            raise ApiError(None, f"GET select returned no policy: {data!r}")
        return policy

    def get_groups(self) -> dict:
        return self._call("GET", "/v1/policy_groups")


def _sanitize(value):
    """Recursively redact credential / URI material from log payloads."""
    if isinstance(value, dict):
        out = {}
        for key, val in value.items():
            lk = str(key).lower()
            if any(tok in lk for tok in _REDACT_KEYS):
                out[key] = "<redacted>"
            else:
                out[key] = _sanitize(val)
        return out
    if isinstance(value, (list, tuple)):
        return [_sanitize(v) for v in value]
    if isinstance(value, str):
        low = value.lower()
        if "://" in value and any(
            s in low for s in ("trojan", "vless", "vmess", "ss://", "socks")
        ):
            return "<redacted-uri>"
        return value
    return value


def compute_candidate_sha(candidates) -> str:
    """SHA-256 over the canonical (sorted) list of candidate names.

    Only names enter the hash — never hosts, passwords or URIs.
    """
    names = sorted(c["name"] for c in candidates)
    canonical = json.dumps(names, ensure_ascii=False, sort_keys=True)
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


class SelectorController:
    """Fail-closed controller for one Surge select group."""

    def __init__(
        self,
        api_client: SurgeApiClient,
        state_path: str,
        group_name: str = GROUP_NAME,
        allowed_members=None,
        ttl_seconds: int = 3600,
        stop_path: str | None = None,
        stop_checker=None,
        health_checker=None,
        now_fn=None,
        log_fn=None,
    ):
        self.api = api_client
        self.state_path = state_path
        self.group_name = group_name
        self.allowed_members = list(allowed_members) if allowed_members else []
        self.ttl_seconds = ttl_seconds
        self.stop_path = stop_path
        self.stop_checker = stop_checker
        self.health_checker = health_checker or self._default_health_check
        self.now_fn = now_fn or time.time
        self._log_fn = log_fn or self._default_log
        self._lock = threading.Lock()

    # -- logging ----------------------------------------------------------
    def _default_log(self, event: str, **fields):
        record = {"ts": self.now_fn(), "event": event, **_sanitize(fields)}
        print(json.dumps(record, ensure_ascii=False), flush=True)

    def _log(self, event: str, **fields):
        self._log_fn(event, **fields)

    # -- STOP -------------------------------------------------------------
    def check_stop(self) -> bool:
        """STOP is a file flag and/or an injected checker. Any STOP means:
        refuse proxy selection, attempt REJECT, record STOPPED."""
        if self.stop_checker is not None:
            try:
                if self.stop_checker():
                    return True
            except Exception as exc:  # a broken checker fails closed
                self._log("stop_check_error", error=str(exc))
                return True
        if self.stop_path and os.path.exists(self.stop_path):
            return True
        return False

    # -- health / version checks ------------------------------------------
    @staticmethod
    def _default_health_check(candidate: dict, now: float) -> tuple[bool, str]:
        """Default health gate: TEST-NET host, latency < 300ms, evidence
        < 24h old. Real latency comes from the caller's evidence; the
        controller never invents a passing health result."""
        host = candidate.get("host", "")
        try:
            if ipaddress.ip_address(host) not in TEST_NET:
                return False, f"host {host} not in TEST-NET"
        except ValueError:
            return False, f"host {host} is not an IP"
        latency = candidate.get("latency_ms")
        if latency is None or float(latency) >= HEALTH_MAX_LATENCY_MS:
            return False, f"latency {latency} not < {HEALTH_MAX_LATENCY_MS}ms"
        tested_at = candidate.get("tested_at")
        if tested_at is None or (now - float(tested_at)) > EVIDENCE_MAX_AGE_SECONDS:
            return False, "evidence stale (>24h) or missing"
        return True, "healthy"

    def validate_candidates(self, candidates, expected_sha: str | None):
        """Return (healthy_list, problem) where problem is None on success.

        Refusals: duplicate names, unknown member names, unmapped
        identifiers, SHA mismatch, stale evidence. Any refusal means
        no proxy is selected from this set.
        """
        names = [c.get("name") for c in candidates]
        if len(names) != len(set(names)):
            return [], "duplicate candidate identifiers"
        if self.allowed_members:
            unknown = [n for n in names if n not in self.allowed_members]
            if unknown:
                return [], f"unmapped identifiers: {unknown}"
        if expected_sha is not None:
            actual = compute_candidate_sha(candidates)
            if actual != expected_sha:
                return [], (
                    f"candidate SHA mismatch: expected {expected_sha[:12]}…, "
                    f"got {actual[:12]}…"
                )
        now = self.now_fn()
        healthy, problems = [], []
        for cand in candidates:
            ok, reason = self.health_checker(cand, now)
            if ok:
                healthy.append(cand)
            else:
                problems.append(f"{cand.get('name')}: {reason}")
        if problems:
            self._log("candidates_unhealthy", problems=problems)
        return healthy, None

    # -- device config check ------------------------------------------------
    def verify_config_loaded(self, expected_members=None):
        """Confirm the device actually loaded the expected test profile
        (group present, member set matches). Returns (ok, reason)."""
        try:
            groups = self.api.get_groups()
        except ApiTimeout as exc:
            return False, f"config check timeout: {exc}"
        except ApiError as exc:
            return False, f"config check failed: {exc}"
        info = None
        if isinstance(groups, dict):
            pool = groups.get("groups") or groups
            if isinstance(pool, dict):
                info = pool.get(self.group_name)
        if info is None:
            return False, f"group {self.group_name!r} not loaded on device"
        members = info.get("members") or info.get("policies") or []
        expected = expected_members if expected_members is not None else self.allowed_members
        if expected and sorted(members) != sorted(expected + [REJECT]):
            return False, (
                f"device member set {sorted(members)} != expected "
                f"{sorted(expected + [REJECT])}"
            )
        return True, "config loaded"

    # -- selection primitives ----------------------------------------------
    def select_and_verify(self, policy: str):
        """POST select then GET read-back. Returns (verified, actual_or_None,
        error_or_None). A timeout / GET failure is NOT a verification."""
        try:
            self.api.select_policy(self.group_name, policy)
        except ApiTimeout as exc:
            return False, None, f"POST select timeout for {policy}: {exc}"
        except ApiError as exc:
            return False, None, f"POST select failed for {policy}: {exc}"
        try:
            actual = self.api.get_selected(self.group_name)
        except ApiTimeout as exc:
            return False, None, f"GET read-back timeout after selecting {policy}: {exc}"
        except ApiError as exc:
            return False, None, f"GET read-back failed after selecting {policy}: {exc}"
        if actual != policy:
            return False, actual, (
                f"read-back mismatch: requested {policy}, device reports {actual}"
            )
        return True, actual, None

    def _persist(self, state: str, selected, candidate_sha, reason, verified):
        record = selector_state.new_state(
            state,
            group_name=self.group_name,
            selected_policy=selected,
            candidate_sha=candidate_sha,
            evidence_ts=self.now_fn(),
            ttl_seconds=self.ttl_seconds,
            verified=verified,
            reason=reason,
            now=self.now_fn(),
        )
        selector_state.save_state(self.state_path, record)
        return record

    def attempt_fail_closed(self, cause_state: str, reason: str,
                            candidate_sha=None):
        """Attempt explicit REJECT + read-back. On success the record keeps
        the *cause* state (why we fell back) with selected=REJECT; on
        failure the state is SELECTION_UNKNOWN — never claim REJECT."""
        verified, actual, error = self.select_and_verify(REJECT)
        if verified:
            # Keep the *cause* state when the cause is meaningful
            # (STOPPED / VERSION_MISMATCH / EVIDENCE_EXPIRED) so the
            # record explains why we fell back; the REJECT selection
            # itself is read-back verified. A generic unknown cause
            # collapses to REJECT_VERIFIED.
            state = cause_state if cause_state in (
                "STOPPED", "VERSION_MISMATCH", "EVIDENCE_EXPIRED",
            ) else "REJECT_VERIFIED"
            self._log("fail_closed_reject_verified", cause=cause_state, reason=reason)
            return self._persist(state, REJECT, candidate_sha, reason, True)
        self._log("fail_closed_reject_unconfirmed", cause=cause_state, error=error)
        return self._persist(
            "SELECTION_UNKNOWN", actual, candidate_sha,
            f"{reason} | REJECT attempt unconfirmed: {error}", False,
        )

    # -- main cycle ---------------------------------------------------------
    def run_cycle(self, candidates, expected_sha: str | None = None):
        """One control cycle. Returns the persisted state record.

        ``candidates``: list of dicts {name, host, port, latency_ms,
        tested_at}. No passwords / URIs: they are never accepted here.
        """
        with self._lock:
            now = self.now_fn()
            sha = compute_candidate_sha(candidates) if candidates else None

            # 1. STOP — refuse everything, attempt REJECT.
            if self.check_stop():
                self._log("stop_active")
                return self.attempt_fail_closed(
                    "STOPPED", "STOP flag active", candidate_sha=sha)

            # 2. Device must have loaded the expected test profile.
            ok, reason = self.verify_config_loaded()
            if not ok:
                self._log("config_not_loaded", reason=reason)
                return self._persist(
                    "CONTROLLER_UNAVAILABLE", None, sha,
                    f"refused: device config not loaded: {reason}", False)

            # 3. Candidate validation: duplicates / mapping / SHA / health.
            if expected_sha is not None and sha != expected_sha:
                self._log("version_mismatch",
                          expected=expected_sha[:12], actual=(sha or "")[:12])
                return self.attempt_fail_closed(
                    "VERSION_MISMATCH",
                    "candidate-set SHA does not match expected version",
                    candidate_sha=sha)
            healthy, problem = self.validate_candidates(candidates, expected_sha)
            if problem:
                self._log("candidates_rejected", problem=problem)
                return self.attempt_fail_closed(
                    "SELECTION_UNKNOWN" if "duplicate" in problem or "unmapped" in problem
                    else "VERSION_MISMATCH",
                    f"candidate validation refused proxy selection: {problem}",
                    candidate_sha=sha)

            # 4. No healthy proxy -> REJECT (fail-closed, verified).
            if not healthy:
                self._log("no_healthy_proxy")
                return self._select_reject_verified(sha)

            # 5. Select the best healthy proxy (lowest latency), verify.
            best = min(healthy, key=lambda c: float(c["latency_ms"]))
            verified, actual, error = self.select_and_verify(best["name"])
            if verified:
                self._log("proxy_verified", policy=best["name"])
                return self._persist("PROXY_VERIFIED", best["name"], sha,
                                     "proxy selected and read-back verified", True)
            self._log("proxy_select_unconfirmed", policy=best["name"], error=error)
            return self._persist(
                "SELECTION_UNKNOWN", actual, sha,
                f"proxy selection unconfirmed: {error}", False)

    def _select_reject_verified(self, sha):
        """No-healthy-proxy path: attempt REJECT; success is REJECT_VERIFIED,
        failure is SELECTION_UNKNOWN (never claim REJECT)."""
        verified, actual, error = self.select_and_verify(REJECT)
        if verified:
            self._log("reject_verified", reason="no healthy proxy")
            return self._persist("REJECT_VERIFIED", REJECT, sha,
                                 "no healthy proxy; REJECT verified", True)
        self._log("reject_unconfirmed", error=error)
        return self._persist("SELECTION_UNKNOWN", actual, sha,
                             f"REJECT attempt unconfirmed: {error}", False)

    # -- lifecycle: startup / network change / recovery / rollback ---------
    def startup_reverify(self):
        """On (re)start: load persisted state (always unverified on load),
        re-read the live selection, and only trust it when it matches the
        recorded policy and the evidence is fresh. Otherwise attempt REJECT.
        See Q1 in the module docstring."""
        with self._lock:
            record = selector_state.load_state(self.state_path, now=self.now_fn())
            if record is None:
                self._log("startup_no_prior_state")
                return self.attempt_fail_closed(
                    "REJECT_VERIFIED", "no prior state; default to REJECT")
            prior = record.get("selected_policy")
            if selector_state.is_expired(record, now=self.now_fn()):
                self._log("startup_evidence_expired", prior_policy=prior)
                return self.attempt_fail_closed(
                    "EVIDENCE_EXPIRED", "persisted evidence expired on startup")
            try:
                live = self.api.get_selected(self.group_name)
            except ApiTimeout as exc:
                return self._persist("CONTROLLER_UNAVAILABLE", prior, None,
                                     f"startup read-back timeout: {exc}", False)
            except ApiError as exc:
                return self._persist("CONTROLLER_UNAVAILABLE", prior, None,
                                     f"startup read-back failed: {exc}", False)
            if live != prior:
                self._log("startup_selection_changed",
                          prior_policy=prior, live_policy=live)
                return self.attempt_fail_closed(
                    "SELECTION_UNKNOWN",
                    f"live selection {live} != persisted {prior}; not trusted")
            state = ("REJECT_VERIFIED" if live == REJECT else "PROXY_VERIFIED")
            self._log("startup_reverified", policy=live, state=state)
            return self._persist(state, live, record.get("candidate_sha"),
                                 "startup read-back matches persisted selection", True)

    def reverify_after_network_change(self):
        """Wi-Fi / cellular switch: re-read live selection and compare with
        the persisted record. Mismatch or read failure -> attempt REJECT;
        a failed REJECT attempt is SELECTION_UNKNOWN, never 'safe'."""
        with self._lock:
            record = selector_state.load_state(self.state_path, now=self.now_fn())
            prior = record.get("selected_policy") if record else None
            try:
                live = self.api.get_selected(self.group_name)
            except (ApiTimeout, ApiError) as exc:
                self._log("network_change_read_failed", error=str(exc))
                return self._persist("SELECTION_UNKNOWN", prior, None,
                                     f"re-verify after network change failed: {exc}",
                                     False)
            if prior is not None and live != prior:
                self._log("network_change_selection_changed",
                          prior_policy=prior, live_policy=live)
                return self.attempt_fail_closed(
                    "SELECTION_UNKNOWN",
                    f"selection changed across network switch: {prior} -> {live}")
            state = "REJECT_VERIFIED" if live == REJECT else "PROXY_VERIFIED"
            return self._persist(state, live,
                                 record.get("candidate_sha") if record else None,
                                 "re-verified after network change", True)

    def recover(self):
        """Recovery entry point after a controller crash/restart: same as
        startup re-verification, then report the verifiable state."""
        return self.startup_reverify()

    def rollback_to_reject(self, manual: bool = True):
        """Manual rollback entry point (human-triggered). Attempts an
        explicit REJECT + read-back. Returns the persisted record; if the
        read-back cannot confirm REJECT, the state is SELECTION_UNKNOWN.
        NOTE (Q2/Q3): this only works while the controller can still reach
        the device API. It is not an automatic device-side fallback."""
        with self._lock:
            self._log("manual_rollback", manual=manual)
            verified, actual, error = self.select_and_verify(REJECT)
            if verified:
                return self._persist("REJECT_VERIFIED", REJECT, None,
                                     "manual rollback to REJECT verified", True)
            return self._persist("SELECTION_UNKNOWN", actual, None,
                                 f"manual rollback unconfirmed: {error}", False)
