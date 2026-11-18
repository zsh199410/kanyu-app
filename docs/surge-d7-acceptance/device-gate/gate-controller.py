"""Device-side independent security gate — controller (P0-E).

Issues, renews and revokes short-lived leases that the ON-DEVICE rule
script (device-gate/gate-script.js) checks on every new request. The
controller is deliberately NOT the enforcement point: enforcement lives
in the device's rule evaluation, so a dead controller cannot keep
authorising traffic — the lease simply expires (TTL 600 s) and the rule
script falls through to FINAL,REJECT.

Issuance channel (official Surge HTTP API, manual.nssurge.com):
  POST /v1/scripting/evaluate  {"script_text": ..., "mock_type": "cron"}
  "Evaluate a script with a mock environment. `script_text` is required;
  `mock_type` is a script type string such as `http-request` or `cron`
  (default: cron). The `$trigger` global is set to `http-api` during
  evaluation." (tools/http-api.html)
The issue script runs ON the device, binds the lease to the device's
current network fingerprint and current boot id (both only visible
inside a script), and writes the lease JSON into $persistentStore. The
controller then attempts a read-back with a second evaluate call that
reads the stored lease. Whether an http-api-evaluated script's
$persistentStore.write persists on a REAL device, and whether the
evaluate response echoes the script's $done() value, is UNPROVEN —
the manual calls the evaluate environment a "mock environment". The
controller therefore NEVER reports LEASE_ACTIVE without a read-back
echo that matches every issued field; a bare HTTP 200 is recorded as
LEASE_ISSUED_UNVERIFIED, never as active.

Gate presence is verified before any issuance:
  GET  /v1/features/scripting   scripting must be enabled
  GET  /v1/scripting            gate-rule, the three gate-events-*
                                scripts and gate-sweep must be listed
  GET  /v1/policy_groups        the gated group must be loaded with
                                exactly REJECT + the test proxies
Missing scripts -> GATE_SCRIPT_MISSING; scripting off ->
SCRIPTING_DISABLED; either refuses issuance outright.

Proxy selection still goes through the task-A path (POST
/v1/policy_groups/select + GET read-back) so the group's CURRENT
selection equals the leased proxy — the rule script denies on any
selection mismatch. Selection alone authorises nothing: without a
valid lease the rule script denies and traffic hits FINAL,REJECT.

States (verified=True only when a live read-back just confirmed it):
  LEASE_ACTIVE             lease read-back matches, selection matches
  LEASE_ISSUED             evaluate accepted (transient; immediately
                           followed by a read-back attempt)
  LEASE_ISSUED_UNVERIFIED  evaluate returned 200 but no confirming echo
  LEASE_EXPIRED            read-back lease exists but now > expires_at
  LEASE_REVOKED            revoke confirmed by REJECT read-back
  NO_LEASE                 read-back shows no stored lease
  GATE_SCRIPT_MISSING      a gate script is not on the device
  SCRIPTING_DISABLED       scripting is disabled on the device
  GATE_UNKNOWN             indeterminate (mismatch / partial failure)
  CONTROLLER_UNAVAILABLE   device API unreachable / timed out
  STOPPED                  STOP flag active; everything refused

State is persisted atomically (tmp + fsync + rename); a loaded record
is NEVER trusted as verified — load marks it unverified and every
lifecycle entry re-reads the device.

Stdlib only (urllib). The HTTP client is injectable
(request_fn) so tests can substitute the mock Surge server
(tests/mock_gate_api.py), which executes the real gate JS in Node.
No real node URI / password / token / real egress IP appears here:
test proxies are TEST-NET 192.0.2.0/24 + test123 by construction, and
candidate data accepted here is names + TEST-NET hosts + latencies only.
"""

from __future__ import annotations

import hashlib
import ipaddress
import json
import os
import threading
import time
import urllib.error
import urllib.parse
import urllib.request

GROUP_NAME = "测试安全出口"
REJECT = "REJECT"
LEASE_KEY = "device-gate-lease-v1"
BOOT_KEY = "device-gate-boot-v1"
LASTSEEN_KEY = "device-gate-lastseen-v1"
TEST_NET = ipaddress.ip_network("192.0.2.0/24")
HEALTH_MAX_LATENCY_MS = 300
EVIDENCE_MAX_AGE_SECONDS = 24 * 3600
LEASE_TTL_SECONDS = 600  # 10 min; controller renews every ~300 s
REQUIRED_SCRIPTS = (
    "gate-rule",
    "gate-events-boot",
    "gate-events-net",
    "gate-events-profile",
    "gate-sweep",
)
STATE_VERSION = 1

GATE_STATES = (
    "NO_LEASE",
    "LEASE_ISSUED",
    "LEASE_ISSUED_UNVERIFIED",
    "LEASE_ACTIVE",
    "LEASE_EXPIRED",
    "LEASE_REVOKED",
    "GATE_SCRIPT_MISSING",
    "SCRIPTING_DISABLED",
    "GATE_UNKNOWN",
    "CONTROLLER_UNAVAILABLE",
    "STOPPED",
)

_REDACT_KEYS = ("password", "passwd", "token", "secret", "api_key", "apikey",
                "key", "uri", "url", "authorization", "x-key")


# ----------------------------------------------------------------------
# Errors / HTTP client (same injectable shape as task A's controller)
# ----------------------------------------------------------------------

class ApiTimeout(Exception):
    pass


class ApiError(Exception):
    def __init__(self, status, message):
        super().__init__(f"HTTP {status}: {message}" if status else message)
        self.status = status
        self.message = message


class SurgeApiClient:
    """Minimal Surge HTTP API client. request_fn is injectable for tests:
    request_fn(method, url, body_bytes_or_None, timeout_seconds)
    -> (status:int, body:bytes)."""

    def __init__(self, base_url: str, request_fn=None, timeout: float = 5.0):
        self.base_url = base_url.rstrip("/")
        self.timeout = timeout
        self._request_fn = request_fn or self._urllib_request

    def _urllib_request(self, method, url, body, timeout):
        req = urllib.request.Request(url, data=body, method=method)
        req.add_header("Content-Type", "application/json")
        try:
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                return resp.status, resp.read()
        except urllib.error.HTTPError as exc:
            return exc.code, exc.read()
        except (urllib.error.URLError, TimeoutError, OSError) as exc:
            raise ApiTimeout(str(exc))

    def _call(self, method, path, body_obj=None):
        url = self.base_url + path
        payload = None
        if body_obj is not None:
            payload = json.dumps(body_obj).encode("utf-8")
        try:
            status, raw = self._request_fn(method, url, payload, self.timeout)
        except ApiTimeout:
            raise
        except ApiError:
            raise
        except Exception as exc:  # transport failure is a timeout-class error
            raise ApiTimeout(str(exc))
        try:
            data = json.loads(raw.decode("utf-8")) if raw else {}
        except ValueError:
            raise ApiError(status, f"non-JSON response: {raw[:200]!r}")
        if status != 200:
            raise ApiError(status, f"HTTP {status}: {data.get('error') or data}")
        if not isinstance(data, dict):
            raise ApiError(status, f"unexpected response shape: {data!r}")
        return data

    def get_features_scripting(self) -> dict:
        return self._call("GET", "/v1/features/scripting")

    def list_scripts(self) -> dict:
        return self._call("GET", "/v1/scripting")

    def get_groups(self) -> dict:
        return self._call("GET", "/v1/policy_groups")

    def get_selected(self, group_name: str) -> str:
        data = self._call(
            "GET", "/v1/policy_groups/select?group_name="
            + urllib.parse.quote(group_name))
        policy = data.get("policy")
        if not policy:
            raise ApiError(None, f"GET select returned no policy: {data!r}")
        return policy

    def select_policy(self, group_name: str, policy: str) -> dict:
        return self._call("POST", "/v1/policy_groups/select",
                          {"group_name": group_name, "policy": policy})

    def evaluate_script(self, script_text: str, mock_type: str = "cron") -> dict:
        return self._call("POST", "/v1/scripting/evaluate",
                          {"script_text": script_text, "mock_type": mock_type})


# ----------------------------------------------------------------------
# Candidate helpers (same canonical SHA as task A: names only, never
# hosts / passwords / URIs enter the hash)
# ----------------------------------------------------------------------

def compute_candidate_sha(candidates) -> str:
    names = sorted(c["name"] for c in candidates)
    canonical = json.dumps(names, ensure_ascii=False, sort_keys=True)
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


# ----------------------------------------------------------------------
# Lease scripts executed ON the device via POST /v1/scripting/evaluate.
# The issue script is self-contained: it carries the same network
# fingerprint field list as gate-script.js (a copy — tests assert the
# two agree for identical $network input).
# ----------------------------------------------------------------------

_FINGERPRINT_JS = """
function __mul32(a,b){var ah=(a>>>16)&0xffff,al=a&0xffff;var bh=(b>>>16)&0xffff,bl=b&0xffff;var low=al*bl;var mid=((ah*bl+al*bh)&0xffff)<<16;return (low+mid)>>>0;}
function __fnv1aHex(s){var h=0x811c9dc5;for(var i=0;i<s.length;i++){h^=s.charCodeAt(i);h=__mul32(h,0x01000193);}var x=h.toString(16);while(x.length<8){x="0"+x;}return "fnv1a-"+x;}
function __netFp(n){var p=[];try{if(!n){return "no-network";}var w=n.wifi||{};var v4=n.v4||{};var v6=n.v6||{};var c=n["cellular-data"]||n.cellularData||{};p.push("ssid="+(w.ssid||""));p.push("bssid="+(w.bssid||""));p.push("v4addr="+(v4.primaryAddress||""));p.push("v4if="+(v4.primaryInterface||""));p.push("v4router="+(v4.primaryRouter||""));p.push("v6addr="+(v6.primaryAddress||""));p.push("v6if="+(v6.primaryInterface||""));p.push("dns="+((n.dns||[]).join(",")));p.push("carrier="+(c.carrier||""));p.push("radio="+(c.radio||""));}catch(e){return "fp-error";}return __fnv1aHex(p.join("|"));}
"""


def build_issue_script(lease_fields: dict) -> str:
    """JS that binds net_fp + boot_id on-device and stores the lease.

    The boot id is normally minted by gate-events.js on engine-started.
    If it is absent (the event did not fire on this device/build), the
    issue script mints one and stores it under BOOT_KEY so the lease
    can be issued at all. A later engine-started still mints a fresh
    boot id and deletes the lease, so the reboot-revocation property
    is preserved; the fallback only covers the first issuance when no
    boot id exists yet.
    """
    blob = json.dumps(lease_fields, ensure_ascii=False, sort_keys=True)
    return (
        "(function(){try{var lease=" + blob + ";" +
        _FINGERPRINT_JS +
        "function __mintBoot(now){var r='';var c='0123456789abcdef';"
        "for(var i=0;i<16;i++){r+=c.charAt(Math.floor(Math.random()*16));}"
        "return 'boot-'+String(now)+'-'+r;}" +
        "lease.net_fp=__netFp($network);" +
        "try{lease.boot_id=$persistentStore.read(" +
        json.dumps(BOOT_KEY) + ");}catch(e){lease.boot_id=null;}" +
        "if(!lease.boot_id){lease.boot_id=__mintBoot(Math.floor(Date.now()/1000));"
        "try{$persistentStore.write(lease.boot_id," +
        json.dumps(BOOT_KEY) + ");}catch(e){}}" +
        "$persistentStore.write(JSON.stringify(lease)," +
        json.dumps(LEASE_KEY) + ");" +
        "$done({lease:lease});}catch(e){try{$done({error:String(e)});}catch(e2){}}})();"
    )


def build_read_script() -> str:
    return (
        "(function(){var raw=null;try{raw=$persistentStore.read(" +
        json.dumps(LEASE_KEY) + ");}catch(e){raw=null;}" +
        "$done({lease_raw:raw});})();"
    )


def build_revoke_script() -> str:
    return (
        "(function(){try{$persistentStore.write(null," +
        json.dumps(LEASE_KEY) + ");}catch(e){}" +
        "try{$persistentStore.write(null," +
        json.dumps(LASTSEEN_KEY) + ");}catch(e){}" +
        "var ok=false;try{ok=$surge.setSelectGroupPolicy(" +
        json.dumps(GROUP_NAME) + "," + json.dumps(REJECT) +
        ");}catch(e){ok=false;}" +
        "$done({reject_ok:ok});})();"
    )


def extract_echo(body: dict):
    """Find a script $done() echo in an evaluate response, if any.

    The real response shape is undocumented; search leniently for a
    dict carrying lease_raw / lease / reject_ok / error, at top level
    or nested one level under result/data/output. Returns the dict or
    None when the response carries no echo at all."""
    if not isinstance(body, dict):
        return None
    for key in ("lease_raw", "lease", "reject_ok", "error"):
        if key in body:
            return body
    for key in ("result", "data", "output"):
        nested = body.get(key)
        if isinstance(nested, dict):
            for k in ("lease_raw", "lease", "reject_ok", "error"):
                if k in nested:
                    return nested
            return nested
    return None


# ----------------------------------------------------------------------
# State persistence (atomic; load never trusts the record as verified)
# ----------------------------------------------------------------------

def new_state(state: str, *, selected_policy=None, candidate_sha=None,
              lease=None, verified: bool = False, reason: str = "",
              now: float | None = None) -> dict:
    if state not in GATE_STATES:
        raise ValueError(f"unknown gate state: {state!r}")
    ts = time.time() if now is None else now
    return {
        "version": STATE_VERSION,
        "state": state,
        "group_name": GROUP_NAME,
        "selected_policy": selected_policy,
        "candidate_sha": candidate_sha,
        "lease": lease,
        "verified": bool(verified),
        "needs_revalidation": not bool(verified),
        "reason": reason,
        "updated_at": ts,
    }


def save_state(path: str, record: dict) -> None:
    tmp = f"{path}.tmp.{os.getpid()}"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(record, fh, ensure_ascii=False, sort_keys=True, indent=2)
        fh.flush()
        os.fsync(fh.fileno())
    os.replace(tmp, path)


def load_state(path: str, now: float | None = None):
    """Load a record, always marked unverified. None when absent/corrupt."""
    try:
        with open(path, encoding="utf-8") as fh:
            record = json.load(fh)
    except (OSError, ValueError):
        return None
    if not isinstance(record, dict) or record.get("version") != STATE_VERSION:
        return None
    record["verified"] = False
    record["needs_revalidation"] = True
    return record


# ----------------------------------------------------------------------
# Controller
# ----------------------------------------------------------------------

class GateController:
    """Issues / renews / revokes device-gate leases via the Surge HTTP API.

    Enforcement is on-device (gate-script.js); this class only manages
    lease lifecycle and records what the device confirmed. It never
    reports a lease active without a read-back echo.
    """

    def __init__(self, api_client: SurgeApiClient, state_path: str,
                 group_name: str = GROUP_NAME, allowed_members=None,
                 ttl_seconds: int = LEASE_TTL_SECONDS,
                 stop_path: str | None = None,
                 now_fn=None, log_fn=None):
        self.api = api_client
        self.state_path = state_path
        self.group_name = group_name
        self.allowed_members = list(allowed_members) if allowed_members else []
        self.ttl_seconds = ttl_seconds
        self.stop_path = stop_path
        self.now_fn = now_fn or time.time
        self._log_fn = log_fn or (lambda record: None)
        # RLock (not Lock): issue_lease() calls revoke_lease() while
        # already holding the lock (STOP / no-healthy-proxy paths).
        # A plain Lock deadlocks there; RLock serialises threads while
        # allowing same-thread re-entry.
        self._lock = threading.RLock()

    # -- logging (desensitised: never log passwords / tokens / URIs) ----
    def _log(self, event: str, **fields):
        clean = {}
        for k, v in fields.items():
            lk = k.lower()
            if any(bad in lk for bad in _REDACT_KEYS):
                clean[k] = "<redacted>"
            elif isinstance(v, str) and "://" in v:
                clean[k] = "<redacted-uri>"
            else:
                clean[k] = v
        self._log_fn({"event": event, "ts": self.now_fn(), **clean})

    # -- STOP ------------------------------------------------------------
    def check_stop(self) -> bool:
        if not self.stop_path:
            return False
        return os.path.exists(self.stop_path)

    # -- device checks ----------------------------------------------------
    def check_gate_scripts(self):
        """(ok, reason): scripting enabled AND all gate scripts listed."""
        try:
            features = self.api.get_features_scripting()
        except ApiTimeout as exc:
            return False, f"features check timeout: {exc}"
        except ApiError as exc:
            return False, f"features check failed: {exc}"
        enabled = _find_bool(features, ("scripting", "enabled"))
        if enabled is False:
            return False, "scripting disabled on device"
        if enabled is None:
            return False, (
                "cannot confirm scripting enabled from "
                f"GET /v1/features/scripting response: {features!r}"
            )
        try:
            listing = self.api.list_scripts()
        except ApiTimeout as exc:
            return False, f"script list timeout: {exc}"
        except ApiError as exc:
            return False, f"script list failed: {exc}"
        names = _script_names(listing)
        missing = [s for s in REQUIRED_SCRIPTS if s not in names]
        if missing:
            return False, f"gate scripts missing on device: {missing}"
        return True, "gate scripts present"

    def verify_config_loaded(self, expected_members=None):
        try:
            groups = self.api.get_groups()
        except ApiTimeout as exc:
            return False, f"config check timeout: {exc}"
        except ApiError as exc:
            return False, f"config check failed: {exc}"
        members = self._group_member_names(groups, self.group_name)
        if members is None:
            return False, f"group {self.group_name!r} not loaded on device"
        expected = expected_members if expected_members is not None else self.allowed_members
        if expected and sorted(members) != sorted(expected + [REJECT]):
            return False, (
                f"device member set {sorted(members)} != expected "
                f"{sorted(expected + [REJECT])}"
            )
        return True, "config loaded"

    @staticmethod
    def _group_member_names(groups, group_name):
        """Member names for a group, accepting both response shapes.

        Mock shape:  {"groups": {name: {"members": [...]}}}
        Real device: {name: [{"name": ...}, ...]} (group is a top-level
        key, value is the member list). Returns None when absent.
        """
        if not isinstance(groups, dict):
            return None
        # Real-device shape first: group name is a top-level key.
        direct = groups.get(group_name)
        if isinstance(direct, list):
            names = []
            for item in direct:
                if isinstance(item, dict) and isinstance(item.get("name"), str):
                    names.append(item["name"])
                elif isinstance(item, str):
                    names.append(item)
            return names
        if isinstance(direct, dict):
            m = direct.get("members") or direct.get("policies") or []
            if isinstance(m, list):
                return [x.get("name") if isinstance(x, dict) else x for x in m]
        # Mock shape: nested under "groups".
        pool = groups.get("groups")
        if isinstance(pool, dict):
            info = pool.get(group_name)
            if isinstance(info, dict):
                m = info.get("members") or info.get("policies") or []
                if isinstance(m, list):
                    return [x.get("name") if isinstance(x, dict) else x for x in m]
            if isinstance(info, list):
                return [x.get("name") if isinstance(x, dict) else x for x in info]
        return None

    # -- candidate validation (same rules as task A) ----------------------
    def health_checker(self, candidate, now):
        host = candidate.get("host")
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

    def validate_candidates(self, candidates, expected_sha):
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

    # -- persistence -------------------------------------------------------
    def _persist(self, state, selected, candidate_sha, lease, reason, verified):
        record = new_state(
            state, selected_policy=selected, candidate_sha=candidate_sha,
            lease=lease, verified=verified, reason=reason, now=self.now_fn(),
        )
        save_state(self.state_path, record)
        return record

    # -- selection primitive (POST + GET read-back, task-A semantics) ------
    def select_and_verify(self, policy: str):
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

    # -- lease read-back ----------------------------------------------------
    def read_lease_back(self):
        """Evaluate the read script on-device.

        Returns (lease_dict_or_None, echoed: bool, error_or_None).
        echoed=False means the evaluate call succeeded but carried no
        confirmation — the lease state from the controller side is then
        unknown, never active."""
        try:
            body = self.api.evaluate_script(build_read_script())
        except ApiTimeout as exc:
            return None, False, f"lease read-back timeout: {exc}"
        except ApiError as exc:
            return None, False, f"lease read-back failed: {exc}"
        echo = extract_echo(body)
        if echo is None:
            return None, False, "evaluate returned no echo (shape unknown)"
        if echo.get("error"):
            return None, True, f"read script error: {echo.get('error')}"
        raw = echo.get("lease_raw")
        if raw is None:
            return None, True, None  # no lease stored
        try:
            lease = json.loads(raw)
        except ValueError:
            return None, True, "stored lease is not valid JSON"
        if not isinstance(lease, dict):
            return None, True, "stored lease is not an object"
        return lease, True, None

    def _lease_matches(self, lease, proxy, expected_sha, now):
        """Field-by-field check of a read-back lease against issuance."""
        if lease.get("v") != 1:
            return False, "lease version != 1"
        if lease.get("proxy") != proxy:
            return False, "lease proxy != issued proxy"
        if lease.get("candidate_sha") != expected_sha:
            return False, "lease candidate SHA != expected"
        if lease.get("stopped") is True:
            return False, "lease stopped"
        if lease.get("ttl_seconds") != self.ttl_seconds:
            return False, "lease TTL != controller TTL"
        if lease.get("expires_at", 0) - lease.get("issued_at", 0) != self.ttl_seconds:
            return False, "lease times inconsistent with TTL"
        if not lease.get("net_fp"):
            return False, "lease has no network fingerprint"
        if not lease.get("boot_id"):
            return False, "lease has no boot id"
        if now < lease.get("issued_at", 0) - 60:
            return False, "lease issued in the future (clock anomaly)"
        if now > lease.get("expires_at", 0):
            return False, "lease expired"
        return True, "lease matches issuance"

    # -- main lifecycle ------------------------------------------------------
    def issue_lease(self, candidates, expected_sha: str | None = None):
        """Issue (or renew) a lease for the best healthy candidate.

        Order: STOP -> gate scripts present -> config loaded -> candidate
        validation -> select proxy (read-back) -> evaluate issue script
        -> evaluate read-back. Only a full read-back match yields
        LEASE_ACTIVE."""
        with self._lock:
            now = self.now_fn()
            sha = compute_candidate_sha(candidates) if candidates else None

            if self.check_stop():
                self._log("stop_active")
                self.revoke_lease("STOP flag active")
                return self._persist("STOPPED", REJECT, sha, None,
                                     "STOP flag active", False)

            ok, reason = self.check_gate_scripts()
            if not ok:
                self._log("gate_scripts_check_failed", reason=reason)
                state = ("SCRIPTING_DISABLED" if "disabled" in reason
                         else "GATE_SCRIPT_MISSING")
                return self._persist(state, None, sha, None,
                                     f"refused: {reason}", False)

            ok, reason = self.verify_config_loaded()
            if not ok:
                self._log("config_not_loaded", reason=reason)
                return self._persist("CONTROLLER_UNAVAILABLE", None, sha,
                                     None, f"refused: {reason}", False)

            if expected_sha is not None and sha != expected_sha:
                self._log("version_mismatch",
                          expected=expected_sha[:12], actual=(sha or "")[:12])
                return self._persist("GATE_UNKNOWN", None, sha, None,
                                     "candidate-set SHA does not match expected version",
                                     False)
            healthy, problem = self.validate_candidates(candidates, expected_sha)
            if problem:
                self._log("candidates_rejected", problem=problem)
                return self._persist("GATE_UNKNOWN", None, sha, None,
                                     f"candidate validation refused issuance: {problem}",
                                     False)
            if not healthy:
                self._log("no_healthy_proxy")
                revoked = self.revoke_lease("no healthy proxy")
                if revoked.get("state") == "LEASE_REVOKED" and revoked.get("verified"):
                    return self._persist("LEASE_REVOKED", REJECT, sha, None,
                                         "no healthy proxy; lease deletion and REJECT verified",
                                         True)
                return self._persist("GATE_UNKNOWN", REJECT, sha, None,
                                     "no healthy proxy; lease revocation unconfirmed",
                                     False)

            best = min(healthy, key=lambda c: float(c["latency_ms"]))
            verified, actual, error = self.select_and_verify(best["name"])
            if not verified:
                self._log("proxy_select_unconfirmed",
                          policy=best["name"], error=error)
                return self._persist("GATE_UNKNOWN", actual, sha, None,
                                     f"proxy selection unconfirmed: {error}", False)

            lease_fields = {
                "v": 1,
                "proxy": best["name"],
                "candidate_sha": sha,
                "issued_at": int(now),
                "expires_at": int(now) + self.ttl_seconds,
                "ttl_seconds": self.ttl_seconds,
                "stopped": False,
            }
            try:
                body = self.api.evaluate_script(build_issue_script(lease_fields))
            except ApiTimeout as exc:
                return self._persist("CONTROLLER_UNAVAILABLE", best["name"], sha,
                                     None, f"issue evaluate timeout: {exc}", False)
            except ApiError as exc:
                return self._persist("CONTROLLER_UNAVAILABLE", best["name"], sha,
                                     None, f"issue evaluate failed: {exc}", False)
            echo = extract_echo(body)
            if echo is not None and echo.get("error"):
                return self._persist("GATE_UNKNOWN", best["name"], sha, None,
                                     f"issue script error on device: {echo.get('error')}",
                                     False)

            lease, echoed, error = self.read_lease_back()
            if not echoed:
                self._log("lease_readback_no_echo", error=error)
                return self._persist("LEASE_ISSUED_UNVERIFIED", best["name"], sha,
                                     None,
                                     f"lease issued but not confirmed on device: {error}",
                                     False)
            if error:
                return self._persist("GATE_UNKNOWN", best["name"], sha, lease,
                                     f"lease read-back problem: {error}", False)
            if lease is None:
                return self._persist("GATE_UNKNOWN", best["name"], sha, None,
                                     "issue evaluate accepted but no lease stored",
                                     False)
            ok, reason = self._lease_matches(lease, best["name"], sha, self.now_fn())
            if not ok:
                return self._persist("GATE_UNKNOWN", best["name"], sha, lease,
                                     f"read-back lease mismatch: {reason}", False)
            try:
                live = self.api.get_selected(self.group_name)
            except (ApiTimeout, ApiError) as exc:
                return self._persist("GATE_UNKNOWN", best["name"], sha, lease,
                                     f"selection re-read failed after issue: {exc}",
                                     False)
            if live != best["name"]:
                return self._persist("GATE_UNKNOWN", live, sha, lease,
                                     "selection changed after issue; lease not trusted",
                                     False)
            self._log("lease_active", policy=best["name"])
            return self._persist("LEASE_ACTIVE", best["name"], sha, lease,
                                 "lease issued and read-back verified", True)

    def renew_lease(self, candidates, expected_sha: str | None = None):
        """Renewal is a fresh issuance (same checks, new timestamps)."""
        return self.issue_lease(candidates, expected_sha)

    def revoke_lease(self, reason: str):
        """Delete the on-device lease and force the group to REJECT.

        Revocation is confirmed only by TWO independent read-backs:
        (a) the group selection reads back REJECT, AND (b) the lease
        read-back shows no lease stored on the device. A REJECT
        selection alone is not enough: the group can sit on REJECT for
        other reasons while the lease is still in $persistentStore, and
        a stored lease is a live credential (re-selecting its proxy
        would admit traffic again). Anything short of both is
        GATE_UNKNOWN — never claim a revoke that was not confirmed."""
        with self._lock:
            self._log("revoke_lease", reason=reason)
            try:
                self.api.evaluate_script(build_revoke_script())
            except (ApiTimeout, ApiError) as exc:
                self._log("revoke_evaluate_failed", error=str(exc))
            verified, actual, error = self.select_and_verify(REJECT)
            if not verified:
                return self._persist("GATE_UNKNOWN", actual, None, None,
                                     f"revoke unconfirmed ({reason}): {error}", False)
            lease, echoed, read_error = self.read_lease_back()
            if not echoed:
                return self._persist("GATE_UNKNOWN", REJECT, None, None,
                                     f"revoke unconfirmed ({reason}): lease read-back "
                                     f"unconfirmed: {read_error}", False)
            if read_error:
                return self._persist("GATE_UNKNOWN", REJECT, None, lease,
                                     f"revoke unconfirmed ({reason}): lease read-back "
                                     f"error: {read_error}", False)
            if lease is not None:
                return self._persist("GATE_UNKNOWN", REJECT, None, lease,
                                     f"revoke unconfirmed ({reason}): lease still "
                                     f"stored on device after revoke", False)
            return self._persist("LEASE_REVOKED", REJECT, None, None,
                                 f"revoked ({reason}); REJECT read-back verified "
                                 f"and no lease stored on device", True)

    def check_lease_status(self):
        """Re-read the on-device lease and classify it. Never trusts the
        persisted record: always evaluates on the device."""
        with self._lock:
            now = self.now_fn()
            lease, echoed, error = self.read_lease_back()
            if not echoed:
                return self._persist(
                    "GATE_UNKNOWN", None, None, None,
                    f"cannot verify lease from controller: {error}", False)
            if error:
                return self._persist("GATE_UNKNOWN", None, None, lease,
                                     f"lease read-back problem: {error}", False)
            if lease is None:
                return self._persist("NO_LEASE", None, None, None,
                                     "no lease stored on device", False)
            if now > lease.get("expires_at", 0):
                return self._persist("LEASE_EXPIRED", None, None, lease,
                                     "stored lease expired", False)
            try:
                live = self.api.get_selected(self.group_name)
            except (ApiTimeout, ApiError) as exc:
                return self._persist("GATE_UNKNOWN", None, None, lease,
                                     f"selection re-read failed: {exc}", False)
            ok, reason = self._lease_matches(
                lease, lease.get("proxy"), lease.get("candidate_sha"), now)
            if not ok:
                return self._persist("GATE_UNKNOWN", live, None, lease,
                                     f"stored lease invalid: {reason}", False)
            if live != lease.get("proxy"):
                return self._persist("GATE_UNKNOWN", live, None, lease,
                                     "selection != leased proxy", False)
            return self._persist("LEASE_ACTIVE", live,
                                 lease.get("candidate_sha"), lease,
                                 "lease re-verified on device", True)

    def startup_reverify(self):
        """On controller (re)start: load the record (always unverified)
        and re-read the device. A prior LEASE_ACTIVE is worth nothing
        until the device confirms it again."""
        with self._lock:
            record = load_state(self.state_path, now=self.now_fn())
            if record is None:
                self._log("startup_no_prior_state")
                return self._persist("NO_LEASE", None, None, None,
                                     "no prior gate state", False)
        return self.check_lease_status()


def _find_bool(node, keys):
    """Recursively find the first boolean under one of `keys`."""
    if isinstance(node, dict):
        for k, v in node.items():
            if k in keys and isinstance(v, bool):
                return v
        for v in node.values():
            found = _find_bool(v, keys)
            if found is not None:
                return found
    elif isinstance(node, list):
        for item in node:
            found = _find_bool(item, keys)
            if found is not None:
                return found
    return None


def _script_names(listing) -> set:
    """Normalise GET /v1/scripting into a set of script names."""
    names: set = set()

    def walk(node):
        if isinstance(node, dict):
            for k in ("name", "script_name"):
                if isinstance(node.get(k), str):
                    names.add(node[k])
            for v in node.values():
                walk(v)
        elif isinstance(node, list):
            for item in node:
                walk(item)

    walk(listing)
    return names
