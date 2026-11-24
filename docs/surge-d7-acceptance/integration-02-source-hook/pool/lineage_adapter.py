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
      B10-EXTENSION (same defect class, flagged for GPT confirmation):
      a vmess uuid containing "," breaks the Surge line the same way
      (username= is a comma-split param), so it is rejected the same
      way (pre_filter reason "comma-uuid", build_surge_line raises).
      Live prevalence this round: re-measured in the probe (expect 0).
  O1  vmess `net` whitelist (scrape-layer admission): only explicitly
      supported transports are admitted to lineage -- {"tcp", "ws", ""}.
      An unknown net (grpc/raw/http/xhttp/h2/none, or a malformed value
      such as "tcp,udp") is NOT fingerprinted and NOT recorded; it is
      counted in the isolation audit (counts by net value) and its
      history (nodes / node_tests) is NEVER touched -- the hook only
      gates lineage, never the crawl, never history. The gate is scoped
      to vmess net ONLY (O1's scope): trojan t_type and ss method are
      NOT gated here -- pre_filter already rejects them from publish,
      and their lineage is real source evidence; gating them would hide
      300+ real records' attribution per round without a ruling behind
      it. If GPT wants the broader gate, it is a one-line extension of
      admission_gate(). Canonicalization itself keeps the RAW net value
      (R3): the gate is a policy layer in the recorder, not a silent
      fold.

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
"""
import json
import os

try:
    from . import source_lineage as sl
except ImportError:  # imported as a top-level module in tests
    import source_lineage as sl

KEY_ENV_VAR = "POOL_LINEAGE_HMAC_KEY"
REGISTRY_FILENAME = "source_groups.json"

# O1: explicitly supported vmess transports (scrape-layer admission).
SUPPORTED_VMESS_NET = frozenset({"tcp", "ws", ""})


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
        out.update({
            "password": rec.get("password", ""),
            "t_type": (rec.get("t_type") or "tcp").lower(),
            "sni": rec.get("sni"),
            "ws": ws,
            "ws_path": rec.get("ws_path") if ws else "/",
            "ws_host": rec.get("ws_host") if ws else None,
            "skip_verify": bool(rec.get("skip_verify")),
        })
    elif proto == "vmess":
        net = (rec.get("net") or "tcp").lower()
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
        out.update({
            "method": (rec.get("method") or "").lower(),
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

    O1 scope: vmess `net` only. An inadmissible record is NOT
    fingerprinted and NOT recorded; the caller counts it in the
    isolation audit keyed by (reason, detail) and leaves history
    untouched. Trojan t_type and ss method are deliberately NOT gated
    here (see the O1 paragraph in the module docstring).
    """
    proto = rec.get("protocol")
    if proto == "vmess":
        net = (rec.get("net") or "tcp").lower()
        if net not in SUPPORTED_VMESS_NET:
            return (False, "unsupported-net", net)
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

    Owns no transaction: record_sighting calls share the crawl
    connection/transaction (per-batch commit in cmd_crawl). Each
    sighting is wrapped in a SAVEPOINT so a lineage write failure
    rolls back only its own statements, never the crawl's upserts.
    """

    def __init__(self, conn, key, registry, evidence, started):
        if not key or (isinstance(key, (bytes, str)) and len(key) == 0):
            raise ValueError("HMAC key is required and must be non-empty")
        self.conn = conn
        self.key = key
        self.registry = registry
        self.evidence = evidence
        self.started = started
        self.recorded = 0
        self.skipped = {}   # reason -> {detail: count}
        self.variants = set()
        self.errors = 0

    def _skip(self, reason, detail):
        bucket = self.skipped.setdefault(reason, {})
        bucket[detail] = bucket.get(detail, 0) + 1

    def observe(self, rec):
        """Record one parsed line's lineage. Returns the v4
        record_sighting result, or {"recorded": False, "reason": ...}
        for gated-out records. Raises only on unexpected DB errors
        (counted by crawl_records as observation_errors; the SAVEPOINT
        keeps the crawl transaction intact)."""
        ok, reason, detail = admission_gate(rec)
        if not ok:
            self._skip(reason, detail)
            return {"recorded": False, "reason": reason}
        cfg = canonical_config(rec)
        fp = sl.config_fingerprint(cfg, self.key)
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
                "skipped": self.skipped, "errors": self.errors}


def build_lineage_recorder(conn, base, started, key=None):
    """Build the recorder for one crawl run, or raise LineageUnavailable.

    Order: key -> registry -> schema. Any failure disables LINEAGE ONLY
    (the caller logs + counts it and runs the crawl without a hook).
    key defaults to the POOL_LINEAGE_HMAC_KEY environment variable.
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
                           run_evidence(started), started)
