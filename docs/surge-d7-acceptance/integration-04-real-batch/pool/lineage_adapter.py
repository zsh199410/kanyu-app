#!/usr/bin/env python3
"""Integration-02 adapter: source-lineage hook for the real scraper.

Maps a parsed record (from EITHER entry point) to the config dict that
v4 config_fingerprint() hashes, and wires the per-line observation hook
(D1, Test B position) into the crawl path. v4 (pool/source_lineage.py)
is FROZEN: this file does not modify it; it is the caller-side
canonicalization + admission + recording the integration must apply
before calling config_fingerprint().

GPT rulings applied (Issue #73 comment 7120382777, 2026-11-24 10:40):
  D1  hook at per-parsed-line, BEFORE dedup (Test B). Test A (hook after
      dedup, in cmd_crawl) loses mirror evidence and auth variants and
      MUST NOT be used.
  D2  vmess `security` is KEPT in the canonical config (never normalized
      to "auto"). A non-auto node that goes through a Surge line yields a
      SECOND variant (the Surge entry fixes security="auto"); that is
      honest behaviour -- the two entries genuinely see different
      configs -- not a bug to paper over. Live prevalence this round:
      see the integration report (34/3645 in P1-1; re-measured here).
  D3  ss `plugin` is KEPT in the canonical config. Publish admits only
      plugins the client AND the tester both support with lossless
      round-trip; live pre_filter() already rejects ALL plugin ss from
      publish, so today no plugin ss can reach publish. The field stays
      in the fingerprint so a future supported-plugin decision cannot
      silently merge distinct configs.
  B10 passwords containing "," are REJECTED FROM PUBLISH (see rules.py:
      pre_filter reason "comma-password", build_surge_line raises).
      The comma is rejected with or without a following space. Lineage
      still records such nodes: the password is valid config and the
      node is real; only the Surge-line expression is broken. B10 gates
      PUBLISH, not lineage.
      B10-EXTENSION (GPT 7121245603, CONFIRMED -- retained): a vmess
      uuid containing "," breaks the Surge line the same way
      (username= is a comma-split param), so it is rejected the same
      way (pre_filter reason "comma-uuid", build_surge_line raises).
      v2 adds a UUID FORMAT check (rules.is_valid_uuid): a uuid must
      be a legal 8-4-4-4-12 hex UUID; a malformed uuid is refused
      from publish as "invalid-uuid". Nothing is ever truncated,
      replaced or rewritten, and no credential is ever recorded.
      Live prevalence this round: re-measured in the probe.
  O1 v2 (GPT 7121245603): the vmess-net-only whitelist is EXPANDED to
      a protocol / transport / encryption SUPPORT MATRIX (see
      SUPPORT_MATRIX below). A record is admitted to lineage ONLY if
      its combination is SUPPORTED, i.e. the parser extracts it AND
      the tester verifies it losslessly AND the Surge line expresses
      it losslessly. Trojan gRPC and ss non-AEAD are NOT judged dead
      by name: each is analysed leg by leg (see the matrix rows), and
      rejected only because a leg of the chain actually breaks
      (tester refuses; Surge drops the transport / plugin). A
      combination failing ANY leg is rejected from lineage admission;
      it is counted in the isolation audit (by reason/detail) with
      the ORIGINAL source counts, and its history (nodes /
      node_tests) is NEVER touched -- the hook only gates lineage,
      never the crawl, never history. The filtered denominator is
      never presented as the full population. Unknown combinations
      fail closed ("unknown-protocol" / the gate's default reject).
      The gate is a policy layer in the recorder, not a silent fold:
      canonicalization itself keeps the RAW values (R3).
      D2 note: vmess security values the tester passes through
      losslessly (auto / aes-128-gcm / chacha20-poly1305 / none) are
      admitted; the Surge line carries no security field, so a
      non-auto security yields a SECOND variant with security="auto"
      on the Surge entry -- that D2-accepted divergence is
      documented in the matrix, not hidden. Unknown security values
      are NOT covered by D2: the tester folds them to "auto", so the
      actual config is unverifiable as-is and the gate rejects them.

Canonicalization rules (R1-R8; proven by the 17 dual-entry cases):
  R1 strip metadata/display: drop `source`, `name_hint` (and any key in
     v4 DISPLAY_FIELDS). They are not node config.
  R2 trojan/vmess ws_path/ws_host count only when the transport uses
     them (trojan ws=true, vmess net=="ws"); otherwise force "/" / None.
     A path/host on a non-ws transport is inert and the Surge line
     cannot carry it.
  R3 keep raw t_type / net values (do NOT collapse grpc/raw to tcp).
     Surge lines can only express ws/tcp, but pre_filter() already
     rejects non-ws/tcp transports from publish; collapsing them would
     conflate genuinely different transports at crawl time.
  R4 vmess `security`: KEPT (D2). Divergence remains for scy != "auto"
     (Surge entry yields "auto") -- accepted, documented, not hidden.
  R5 ss `plugin`: KEPT (D3). Divergence remains (Surge entry yields
     None) -- but pre_filter() rejects plugin ss from publish, so no
     live case can reach publish today.
  R6 passwords with "," (B10): see above. Lineage records them;
     publish refuses them.
  R7 auth variants stay distinct: same triplet, different password ->
     different fingerprint (v4 core property, verified).
  R8 transport enums are case-normalized (t_type / net lowercased):
     "WS" and "ws" are the same transport; without this, entry A and
     entry B could disagree on case alone. (security is NOT lowercased:
     it is an upstream enum value kept verbatim, conservative.)

Key / registry / schema gating (B5, fail-closed for LINEAGE only):
  - The HMAC key comes from the environment (POOL_LINEAGE_HMAC_KEY),
    loaded by the scraper service from a 600 root-only env file via
    systemd EnvironmentFile (deployment, NOT part of this diff).
    No key -> lineage is DISABLED (loudly logged + counted), the crawl
    itself still runs. A missing key never produces lineage rows and
    never falls back to an unkeyed hash. The key gates LINEAGE, not
    the crawl: blocking the hourly crawl over a missing key file would
    be worse than a lineage gap, and the gap is visible in the run
    counts. If GPT wants the crawl itself blocked on a missing key,
    that is a one-line change in cmd_crawl.
  - The registry (source_groups.json, next to sources.yaml) supplies
    groups + paused status. Missing/malformed -> lineage disabled,
    crawl proceeds, counted + logged.
  - The lineage schema must already exist (migration run in a
    maintenance window, v4 migrate_node_sources.py). cmd_crawl does
    NOT auto-create the tables: if the schema is absent or mismatched,
    lineage is disabled, crawl proceeds, counted + logged.

Failure isolation: record_sighting() validates all inputs BEFORE any
write, so a mid-write failure is not a reachable path in the current
code. The recorder additionally wraps each sighting in a SAVEPOINT so
that, if a lineage write ever did fail, only its own statements roll
back -- never the crawl's upserts. Callback exceptions are counted by
crawl_records (observation_errors) and never abort the crawl.
Integration-04 (Review 6034205305 point 3): the SAVEPOINT path is kept
only for the #127 v2 test suite and direct diagnostic use. Production
cmd_crawl builds the recorder with defer=True and uses collect() +
flush() inside one explicit transaction (see LineageRecorder): no write
lock is held during network I/O, and a failed crawl produces no
consumable completion evidence.
"""
import json
import os

try:
    from . import source_lineage as sl
    from .crawler import AEAD_METHODS
    from .normalize import norm_method, norm_transport
except ImportError:  # imported as a top-level module in tests
    import source_lineage as sl
    from crawler import AEAD_METHODS
    from normalize import norm_method, norm_transport

KEY_ENV_VAR = "POOL_LINEAGE_HMAC_KEY"
REGISTRY_FILENAME = "source_groups.json"

# O1 v2: protocol / transport / encryption support matrix (GPT 7121245603).
# A combination is SUPPORTED only if the parser extracts it AND the
# tester verifies it losslessly AND the Surge line expresses it
# losslessly. The gate (admission_gate) implements this matrix; the
# SUPPORT_MATRIX table below is the human-readable record of the same
# decisions, and the v2 test suite asserts the two agree row by row.
# Only combinations the current implementation actually supports are
# listed as admitted -- nothing unverified is guessed in.
SUPPORTED_VMESS_NET = frozenset({"tcp", "ws", ""})
# The exact set tester.build_config() passes through without folding
# (any other security value is silently folded to "auto" = lossy, so
# the actual config is unverifiable as-is). The comparison is
# case-sensitive on purpose: it mirrors build_config() exactly.
SUPPORTED_VMESS_SECURITY = frozenset({"auto", "aes-128-gcm",
                                       "chacha20-poly1305", "none"})
SUPPORTED_TROJAN_TTYPE = frozenset({"tcp", "ws", ""})

# Support matrix rows. Columns: protocol / transport / encryption are
# the combination being judged; parser / tester / surge state what
# each leg does with it; admitted is the gate verdict; reason is the
# gate's rejection reason ("" when admitted). "surge~" marks the
# D2-accepted divergence (see the O1 v2 paragraph in the docstring).
SUPPORT_MATRIX = [
    # -- vmess: net x security x tls ------------------------------------
    {"protocol": "vmess", "transport": "tcp", "encryption": "auto, tls",
     "parser": "extracts", "tester": "verifies", "surge": "expresses",
     "admitted": True, "reason": ""},
    {"protocol": "vmess", "transport": "ws", "encryption": "auto, tls",
     "parser": "extracts", "tester": "verifies", "surge": "expresses",
     "admitted": True, "reason": ""},
    {"protocol": "vmess", "transport": "(empty net -> tcp)",
     "encryption": "auto, tls",
     "parser": "extracts", "tester": "verifies", "surge": "expresses",
     "admitted": True, "reason": ""},
    {"protocol": "vmess", "transport": "tcp / ws / empty",
     "encryption": "aes-128-gcm / chacha20-poly1305 / none, tls",
     "parser": "extracts", "tester": "verifies (passes through)",
     "surge": "D2 divergence: line carries no security; Surge entry "
              "yields auto as a SECOND variant (documented, not hidden)",
     "admitted": True, "reason": ""},
    {"protocol": "vmess",
     "transport": "grpc / raw / http / xhttp / h2 / none / 'tcp,udp' / malformed",
     "encryption": "any",
     "parser": "extracts", "tester": "rejects (unsupported-transport)",
     "surge": "drops the transport; round-trip returns tcp (lossy)",
     "admitted": False, "reason": "unsupported-transport"},
    {"protocol": "vmess", "transport": "tcp / ws / empty",
     "encryption": "no TLS",
     "parser": "extracts", "tester": "refuses (vmess-non-tls)",
     "surge": "expresses (omits tls=true) -- but not verifiable",
     "admitted": False, "reason": "vmess-non-tls"},
    {"protocol": "vmess", "transport": "tcp / ws / empty",
     "encryption": "security other than auto / aes-128-gcm / "
                   "chacha20-poly1305 / none, tls",
     "parser": "extracts", "tester": "folds to auto (lossy, unverifiable as-is)",
     "surge": "line carries no security",
     "admitted": False, "reason": "unsupported-security"},
    {"protocol": "vmess", "transport": "any", "encryption": "uuid missing",
     "parser": "extracts (empty)", "tester": "refuses (missing-uuid)",
     "surge": "username= empty",
     "admitted": False, "reason": "missing-uuid"},
    # -- trojan -----------------------------------------------------------
    {"protocol": "trojan", "transport": "tcp / ws / empty",
     "encryption": "password present",
     "parser": "extracts", "tester": "verifies", "surge": "expresses",
     "admitted": True, "reason": ""},
    {"protocol": "trojan", "transport": "grpc / other",
     "encryption": "password present",
     "parser": "extracts", "tester": "rejects (unsupported-transport)",
     "surge": "drops t_type silently; round-trip returns tcp (lossy) -- "
              "would publish as plain trojan",
     "admitted": False, "reason": "unsupported-transport"},
    {"protocol": "trojan", "transport": "any",
     "encryption": "password missing",
     "parser": "extracts (empty)", "tester": "refuses (missing-password)",
     "surge": "password= empty",
     "admitted": False, "reason": "missing-password"},
    # -- ss ---------------------------------------------------------------
    {"protocol": "ss", "transport": "AEAD method, no plugin",
     "encryption": "password present",
     "parser": "extracts", "tester": "verifies", "surge": "expresses",
     "admitted": True, "reason": ""},
    {"protocol": "ss", "transport": "non-AEAD method",
     "encryption": "password present",
     "parser": "extracts",
     "tester": "rejects (ss-method) -- NOT verifiable; judged by the "
               "chain, not by the name",
     "surge": "line CAN carry encrypt-method losslessly in text "
              "(round-trip matches) -- but pre_filter bars publish",
     "admitted": False, "reason": "ss-method"},
    {"protocol": "ss", "transport": "any method, plugin present",
     "encryption": "password present",
     "parser": "extracts", "tester": "rejects (ss-plugin)",
     "surge": "line carries no plugin (lossy); no supported plugin today",
     "admitted": False, "reason": "ss-plugin"},
    {"protocol": "ss", "transport": "any", "encryption": "password missing",
     "parser": "extracts (empty)", "tester": "refuses (missing-password)",
     "surge": "password= empty",
     "admitted": False, "reason": "missing-password"},
    # -- unknown ----------------------------------------------------------
    {"protocol": "(other)", "transport": "any", "encryption": "any",
     "parser": "n/a", "tester": "n/a", "surge": "n/a",
     "admitted": False, "reason": "unknown-protocol"},
]

# All rejection reasons the gate can return (the matrix above is the
# authority; the test asserts every row's reason is in this set and
# every set member appears in the matrix).
GATE_REASONS = frozenset({
    "vmess-non-tls", "unsupported-security",
    "missing-uuid", "unsupported-transport", "missing-password",
    "ss-method", "ss-plugin", "unknown-protocol",
})


class LineageUnavailable(Exception):
    """Lineage cannot run for this crawl (key/registry/schema). Carries
    a short machine-readable reason; the crawl proceeds without it."""

    def __init__(self, reason):
        super().__init__(reason)
        self.reason = reason


# ---------------------------------------------------------------------------
# Canonicalization (R1-R8)
# ---------------------------------------------------------------------------

def canonical_config(rec):
    """Map a parsed record (parse_record OR surge_line_to_record output)
    to the canonical fingerprint config. Returns None for None input.
    Never includes source / name_hint / display fields."""
    if rec is None:
        return None
    proto = rec["protocol"]
    out = {"protocol": proto, "host": rec["host"], "port": int(rec["port"])}
    if proto == "trojan":
        ws = bool(rec.get("ws"))
        t_type, _t_status = norm_transport(rec.get("t_type"))
        out.update({
            "password": rec.get("password", ""),
            "t_type": t_type,
            "sni": rec.get("sni"),
            "ws": ws,
            "ws_path": rec.get("ws_path") if ws else "/",
            "ws_host": rec.get("ws_host") if ws else None,
            "skip_verify": bool(rec.get("skip_verify")),
        })
    elif proto == "vmess":
        net, _n_status = norm_transport(rec.get("net"))
        use_ws = net == "ws"
        out.update({
            "uuid": rec.get("uuid", ""),
            "security": rec.get("security") or "auto",
            "net": net,
            "tls": bool(rec.get("tls")),
            "ws_path": rec.get("ws_path") if use_ws else "/",
            "ws_host": rec.get("ws_host") if use_ws else None,
            "sni": rec.get("sni"),
            "skip_verify": bool(rec.get("skip_verify")),
        })
    elif proto == "ss":
        method, _m_status = norm_method(rec.get("method"), AEAD_METHODS)
        out.update({
            "method": method if method is not None else "",
            "password": rec.get("password", ""),
            "plugin": rec.get("plugin"),
        })
    return out


def fingerprint_for_record(rec, key):
    """config_fingerprint(canonical_config(rec), key). Key required."""
    return sl.config_fingerprint(canonical_config(rec), key)


# ---------------------------------------------------------------------------
# Admission gate (O1)
# ---------------------------------------------------------------------------

def admission_gate(rec):
    """(admissible, reason, detail) for LINEAGE admission.

    O1 v2 (GPT 7121245603): implements SUPPORT_MATRIX above. Check
    order follows pre_filter() where the checks overlap, so the first
    failing leg is reported the same way by both gates. B10 (comma /
    malformed credentials) is deliberately NOT checked here: B10 gates
    PUBLISH only (rules.py); a comma-password / comma-uuid /
    invalid-uuid node still gets lineage. Unknown protocols fail
    closed ("unknown-protocol") -- the hook only fires for whitelisted
    protocols, so this is unreachable in the crawl path, but the gate
    itself must not default-admit anything it does not know.
    """
    proto = rec.get("protocol")
    if proto == "vmess":
        if not rec.get("tls"):
            return (False, "vmess-non-tls", "")
        # Unified contract (integration-04): transport is normalized
        # (strip + lowercase) exactly like pre_filter / the tester;
        # "unknown" and "invalid" are both refused as
        # unsupported-transport (the lowered token is echoed so the
        # audit can tell grpc from a malformed value; an invalid value
        # echoes "" because there is no token to echo).
        net, net_status = norm_transport(rec.get("net"))
        if net_status in ("unknown", "invalid"):
            return (False, "unsupported-transport", net or "")
        if net not in SUPPORTED_VMESS_NET:
            return (False, "unsupported-transport", net)
        if not rec.get("uuid"):
            return (False, "missing-uuid", "")
        sec = rec.get("security") or "auto"
        if sec not in SUPPORTED_VMESS_SECURITY:
            return (False, "unsupported-security", sec)
    elif proto == "trojan":
        t, t_status = norm_transport(rec.get("t_type"))
        if t_status in ("unknown", "invalid"):
            return (False, "unsupported-transport", t or "")
        if t not in SUPPORTED_TROJAN_TTYPE:
            return (False, "unsupported-transport", t)
        if not rec.get("password"):
            return (False, "missing-password", "")
    elif proto == "ss":
        method, m_status = norm_method(rec.get("method"), AEAD_METHODS)
        if m_status != "ok":
            return (False, "ss-method", method or "")
        if rec.get("plugin"):
            # Detail is a fixed marker, not the plugin string: plugin
            # parameters are caller-controlled text and must never be
            # echoed into audit counts.
            return (False, "ss-plugin", "present")
        if not rec.get("password"):
            return (False, "missing-password", "")
    else:
        return (False, "unknown-protocol", str(proto))
    return (True, "", "")


# ---------------------------------------------------------------------------
# Registry (caller-supplied config; never guessed from the DB)
# ---------------------------------------------------------------------------

def load_registry(path):
    """Load source_groups.json -> (SourceRegistry, meta).

    File shape: {"groups": {group: [source, ...]},
                 "paused": [source, ...], ...}.
    Every source named in groups gets status "paused" if listed in
    "paused", else "active". A source in no group is 'unverified' and
    never qualifies (v4 rule). Raises ValueError on malformed input.
    """
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    if not isinstance(data, dict):
        raise ValueError("registry must be a JSON object")
    groups = data.get("groups")
    if not isinstance(groups, dict) or not groups:
        raise ValueError("registry 'groups' must be a non-empty object")
    paused = data.get("paused", [])
    if not isinstance(paused, list) or not all(isinstance(s, str) for s in paused):
        raise ValueError("registry 'paused' must be a list of source names")
    known = {s for members in groups.values() for s in members}
    for s in paused:
        if s not in known:
            raise ValueError(f"paused source {s!r} is not in any group")
    status = {s: ("paused" if s in paused else "active") for s in known}
    registry = sl.SourceRegistry(groups=groups, status=status)
    return registry, {"groups": len(groups), "sources": len(known),
                      "paused": sorted(paused)}


def lineage_schema_ready(conn):
    """True iff the v4 lineage tables exist with the expected columns.
    (Migration is a separate approved step; cmd_crawl never creates
    tables on the fly.)"""
    try:
        return sl.schema_matches_v3(conn)
    except Exception:
        return False


# ---------------------------------------------------------------------------
# Recorder (the D1 hook target)
# ---------------------------------------------------------------------------

def run_evidence(started):
    """Evidence string binding every sighting to one crawl batch."""
    return f"crawl:{started}"


def event_id_for(started, protocol, host, port, fingerprint, source):
    """Deterministic event id: re-running the same crawl round is a
    no-op (event-level dedup in v4)."""
    return (f"crawl:{started}:{protocol}|{host}|{int(port)}|"
            f"{fingerprint}|{source}")


class LineageRecorder:
    """Per-crawl-batch lineage recorder. Constructed once per crawl run
    by cmd_crawl; `observe` is passed as crawl_records' on_observation
    callback (Test B position: per parsed line, before dedup).

    Two modes (integration-04, Review 6034205305 point 3):
      * defer=False (default, v1/v2 behaviour, kept for the #127 v2
        test suite and direct diagnostic use): observe() writes one
        sighting immediately via SAVEPOINT. NOTE: with no outer
        transaction (db.connect commits at connect time) the SAVEPOINT
        RELEASE can commit that sighting on its own, so a later crawl
        failure cannot un-write it. Production cmd_crawl MUST NOT use
        this mode.
      * defer=True (production path): observe() / collect() only stage
        the sighting in memory (gate + canonicalize + fingerprint, no
        DB access). flush(conn) writes all staged sightings inside the
        caller's explicit transaction (BEGIN IMMEDIATE ... COMMIT in
        cmd_crawl); any error raises and the caller rolls the whole
        crawl back, so a failed crawl produces no consumable evidence.
    `last_fingerprint` holds the fingerprint of the most recently
    staged/observed record (the BatchCollector reads it to build the
    batch member set without re-hashing).
    """

    def __init__(self, conn, key, registry, evidence, started, defer=False):
        if not key or (isinstance(key, (bytes, str)) and len(key) == 0):
            raise ValueError("HMAC key is required and must be non-empty")
        self.conn = conn
        self.key = key
        self.registry = registry
        self.evidence = evidence
        self.started = started
        self.defer = bool(defer)
        self.pending = []  # (protocol, host, port, fingerprint, source, event_id)
        self.last_fingerprint = None
        self.flushed = 0
        self.recorded = 0
        self.skipped = {}   # reason -> {detail: count}
        self.variants = set()
        self.errors = 0

    def _skip(self, reason, detail):
        bucket = self.skipped.setdefault(reason, {})
        bucket[detail] = bucket.get(detail, 0) + 1

    def collect(self, rec):
        """Stage one parsed line's lineage in memory (defer mode).
        Gate + canonicalize + fingerprint; NO DB access. Returns the
        same result shape as observe(): {"recorded": bool, ...}.
        Sets last_fingerprint on success (None on gate rejection)."""
        ok, reason, detail = admission_gate(rec)
        if not ok:
            self.last_fingerprint = None
            self._skip(reason, detail)
            return {"recorded": False, "reason": reason}
        cfg = canonical_config(rec)
        fp = sl.config_fingerprint(cfg, self.key)
        event_id = event_id_for(self.started, rec["protocol"], rec["host"],
                                rec["port"], fp, rec["source"])
        self.pending.append((rec["protocol"], rec["host"], int(rec["port"]),
                             fp, rec["source"], event_id))
        self.last_fingerprint = fp
        self.recorded += 1
        self.variants.add((rec["protocol"], rec["host"],
                           int(rec["port"]), fp))
        return {"recorded": True, "accepted": True, "reason": "staged"}

    def flush(self, conn):
        """Write all staged sightings inside the CALLER's explicit
        transaction. This method never begins or commits: the caller
        (cmd_crawl) holds BEGIN IMMEDIATE and commits once at the end,
        so a failure anywhere rolls the whole crawl back. Returns the
        number of accepted sightings. Raises on any DB error (the
        caller rolls back; self.errors counts it). Idempotent w.r.t.
        re-runs: record_sighting dedups on event_id, so a second flush
        of the same staged list is a no-op for already-written rows;
        flush() clears the pending list after a successful write."""
        n = 0
        for (proto, host, port, fp, source, event_id) in self.pending:
            try:
                r = sl.record_sighting(
                    conn, proto, host, port, fp, source, self.started,
                    evidence=self.evidence, event_id=event_id)
            except Exception:
                self.errors += 1
                raise
            if r.get("accepted"):
                n += 1
            else:
                self._skip(r.get("reason", "not_accepted"), "")
        self.flushed += n
        self.pending = []
        return n

    def observe(self, rec):
        """Record one parsed line's lineage. Returns the v4
        record_sighting result, or {"recorded": False, "reason": ...}
        for gated-out records. Raises only on unexpected DB errors
        (counted by crawl_records as observation_errors; the SAVEPOINT
        keeps the crawl transaction intact)."""
        if self.defer:
            return self.collect(rec)
        ok, reason, detail = admission_gate(rec)
        if not ok:
            self.last_fingerprint = None
            self._skip(reason, detail)
            return {"recorded": False, "reason": reason}
        cfg = canonical_config(rec)
        fp = sl.config_fingerprint(cfg, self.key)
        self.last_fingerprint = fp
        event_id = event_id_for(self.started, rec["protocol"], rec["host"],
                                rec["port"], fp, rec["source"])
        self.conn.execute("SAVEPOINT lineage_obs")
        try:
            r = sl.record_sighting(
                self.conn, rec["protocol"], rec["host"], int(rec["port"]),
                fp, rec["source"], self.started, evidence=self.evidence,
                event_id=event_id)
        except Exception:
            self.conn.execute("ROLLBACK TO SAVEPOINT lineage_obs")
            self.conn.execute("RELEASE SAVEPOINT lineage_obs")
            self.errors += 1
            raise
        self.conn.execute("RELEASE SAVEPOINT lineage_obs")
        if r.get("accepted"):
            self.recorded += 1
            self.variants.add((rec["protocol"], rec["host"],
                               int(rec["port"]), fp))
        else:
            self._skip(r.get("reason", "not_accepted"), "")
        return r

    def summary(self):
        """Counts only -- no fingerprints, no credentials, no URIs.
        Safe to store in runs.counts and print to stdout."""
        return {"enabled": True, "evidence": self.evidence,
                "recorded": self.recorded, "variants": len(self.variants),
                "skipped": self.skipped, "errors": self.errors,
                "deferred": self.defer, "flushed": self.flushed,
                "pending": len(self.pending)}


def build_lineage_recorder(conn, base, started, key=None, defer=False):
    """Build the recorder for one crawl run, or raise LineageUnavailable.

    Order: key -> registry -> schema. Any failure disables LINEAGE ONLY
    (the caller logs + counts it and runs the crawl without a hook).
    key defaults to the POOL_LINEAGE_HMAC_KEY environment variable.
    defer=True builds the production recorder: observe()/collect()
    stage sightings in memory and flush(conn) writes them inside the
    caller's explicit transaction (integration-04, Review 6034205305
    point 3). defer=False keeps the v1/v2 per-line SAVEPOINT behaviour
    for the #127 v2 test suite and direct diagnostic use.
    """
    if key is None:
        key = os.environ.get(KEY_ENV_VAR, "")
    if not key:
        raise LineageUnavailable("no_key")
    registry_path = os.path.join(base, REGISTRY_FILENAME)
    try:
        registry, _meta = load_registry(registry_path)
    except FileNotFoundError:
        raise LineageUnavailable("no_registry")
    except (ValueError, OSError) as e:
        raise LineageUnavailable(f"bad_registry:{e}")
    if not lineage_schema_ready(conn):
        raise LineageUnavailable("schema_not_migrated")
    return LineageRecorder(conn, key, registry,
                           run_evidence(started), started, defer=defer)
