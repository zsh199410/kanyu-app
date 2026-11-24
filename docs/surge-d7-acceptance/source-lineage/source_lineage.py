"""Source lineage module v4 (GPT decision 3, revised per Reviews
6031702642 and 6032131494).

v4 closes the three contract gaps GPT found in v3 (Review 6032131494,
COMMENTED, 2026-11-24 09:13). It does NOT redesign the parts that
already passed; module 1 (trial-small-pool) is frozen and untouched.

 (1) Config fingerprint: v3 stripped password/uuid etc. BEFORE hashing
     and its tests asserted that configs differing ONLY in credentials
     share one fingerprint. That violates "auth variants must be
     distinguished": a dead node could borrow another node's valid
     records. v4 fingerprints the NORMALIZED COMPLETE valid config with
     a local stable key: HMAC-SHA256(key, canonical_json(config)).
     - The key is REQUIRED (bytes or str, non-empty). There is NO
       unkeyed fallback: calling without a key raises ValueError.
       A simple unkeyed hash is never used.
     - The key lives in the scraper's secure config / environment and is
       passed in by the caller. It is NEVER stored in the DB, NEVER
       committed to the repo, NEVER logged. Tests use a synthetic test
       key that must never be used as a production key.
     - Credentials are inputs to the HMAC only: they stay inside the
       parse process. Only the 64-hex fingerprint is persisted or
       published, and an HMAC output does not reveal its inputs.
     - Display-only fields (name / remark / url / raw / ...) are
       stripped before hashing; a display-only difference does not
       change the fingerprint.
     - Unknown parse fields are INCLUDED in the hash (conservative: any
       difference -> a different fingerprint). The real scraper's exact
       parser field set and value-type normalization are UNVERIFIED
       (the live scraper config was not readable in this round); the
       caller must normalize types before calling (port int, tls bool,
       ...) and the integration must verify the field set. Do not guess.
     - Old fingerprints do NOT auto-upgrade. v3 fingerprints (unkeyed
       SHA-256 of the credential-stripped config) are different values
       from v4 HMAC fingerprints for the same config. v3 never ran in
       production, so no live data carries v3 fingerprints; a DB that
       does is simply holding different fingerprint values, and this
       module never rewrites them. Existing failure history stays keyed
       by the old triplet conservatively: changing fingerprints never
       clears node_tests / phone_failures.
 (2) Qualification / batch evidence boundaries (Review 6032131494):
     - qualified_source_group: age must satisfy 0 <= age <= TTL. A
       sighting whose last_seen is in the FUTURE (age < 0) is rejected
       as evidence, exactly like a stale one (age > TTL). It is skipped
       and an older valid sighting from another qualified source may
       still qualify the variant.
     - record_sighting: last_evidence is bound to the NEWEST
       observation. An out-of-order older sighting still counts as a
       new event (sighting_count grows, first/last_seen stay monotone)
       but must NOT overwrite last_evidence with older evidence.
     - batch_diversity: passes now REQUIRES zero rejected entries.
       A batch with 3 qualified groups plus 1 unknown/duplicate does
       NOT pass. The result carries accepted_variants (the accepted
       exact identities) and publishable. To publish, the caller MUST
       build a NEW batch from accepted_variants (see rebuild_batch),
       re-run batch_diversity on it, and require passes. Publishing
       the ORIGINAL list is forbidden: it still contains the rejected
       entries. active + 24h freshness of a SOURCE is only a pre-screen
       of the source; it does not prove that the latest successful
       scrape still contains this node, nor that VPS/phone passed it.
       Integration must bind to the latest valid scrape batch and the
       real health status (see DESIGN.md).
 (3) Rollback must not lose data: see migrate_node_sources.py v4.
     Normal rollback only disables the new module / scraper calls and
     keeps the extra tables and history (backward compatible, no
     whole-DB overwrite). Whole-DB restore applies ONLY to a migration
     window with zero post-backup writes, verified by full digests;
     any unexpected change is refused, and there is no --allow-data-loss
     switch anymore.

Source status / grouping are CALLER-SUPPLIED (SourceRegistry), built from
the scraper's own config. The live DB has no enabled/paused column
(sources table: name, url, last_success, last_count, ok_count, fail_count;
url is NULL in the snapshot) and no grouping info, so this module cannot
read them from the DB and does not guess them. Sources not in the registry
are 'unverified' and never qualify. set_source_status / current_source_
status / registry_from_log provide an append-only audit trail for status
changes; the registry itself remains the caller's config.

Pure SQLite helpers; no network, no publisher, no production writes here --
the caller owns the connection and the transaction.
"""
import hashlib
import hmac
import json
import re
import sqlite3

LEGACY_FINGERPRINT = "legacy"
_HEX64 = re.compile(r"^[a-f0-9]{64}$")

# Display-only fields stripped before fingerprinting. Credential fields
# are deliberately NOT in this set: they are HMAC inputs, so auth
# variants get different fingerprints. A raw URI or password must never
# reach this module as a bare string: callers parse the subscription
# line first and pass only the parsed config dict.
DISPLAY_FIELDS = frozenset({
    "ps", "name", "remark", "url", "raw", "uri", "raw_uri", "link",
})


# ---------------------------------------------------------------------------
# Fingerprint (v4: HMAC-SHA256 with a local stable key)
# ---------------------------------------------------------------------------

def _normalize_key(key):
    """Return the HMAC key as bytes, or raise. No unkeyed fallback."""
    if isinstance(key, str):
        key = key.encode("utf-8")
    if not isinstance(key, bytes) or len(key) == 0:
        raise ValueError("HMAC key is required and must be non-empty bytes/str")
    return key


def config_fingerprint(config, key):
    """HMAC-SHA256 hex of the canonical complete valid config.

    config is the PARSED subscription config (dict), e.g.
    {"protocol": "trojan", "host": "...", "port": 443, "sni": "...",
     "transport": "ws", "path": "/", "tls": True, "alpn": "h2",
     "password": "...", "uuid": "..."}.
    key is the caller's local stable HMAC key (bytes or str, non-empty),
    passed in from the scraper's secure config / environment. It is never
    stored, logged or committed by this module.

    Only display fields are stripped before hashing. Credential fields
    stay in the canonical input, so two configs differing ONLY in
    credentials get DIFFERENT fingerprints (auth variants are distinct),
    while the HMAC output itself reveals nothing about them.
    Unknown fields are included (conservative). Values must be
    JSON-serializable; the caller must normalize types first (port int,
    tls bool, ...). Raises ValueError on non-dict / empty config /
    config empty after stripping / missing or empty key.
    """
    if not isinstance(config, dict):
        raise ValueError("config must be a dict")
    key = _normalize_key(key)
    clean = {k: v for k, v in config.items()
             if k not in DISPLAY_FIELDS and v is not None}
    if not clean:
        raise ValueError("config empty after stripping display fields")
    try:
        canonical = json.dumps(clean, sort_keys=True, separators=(",", ":"),
                               ensure_ascii=True)
    except (TypeError, ValueError) as e:
        raise ValueError(f"config values must be JSON-serializable: {e}")
    return hmac.new(key, canonical.encode("utf-8"),
                    hashlib.sha256).hexdigest()


def is_verified_fingerprint(fp):
    """True iff fp is a real 64-hex config fingerprint (not 'legacy')."""
    return isinstance(fp, str) and bool(_HEX64.match(fp))


def _validate_variant(protocol, host, port, fingerprint):
    if not protocol or not isinstance(protocol, str):
        raise ValueError("bad protocol")
    if not host or not isinstance(host, str):
        raise ValueError("bad host")
    if not isinstance(port, int) or port <= 0 or port > 65535:
        raise ValueError("bad port")
    if not is_verified_fingerprint(fingerprint):
        raise ValueError("fingerprint must be a 64-hex config fingerprint")


def _validate_ts(ts):
    if not isinstance(ts, int) or isinstance(ts, bool) or ts < 0:
        raise ValueError("bad timestamp")


# ---------------------------------------------------------------------------
# Schema (v4: unchanged from v3 -- fingerprints are opaque 64-hex values)
# ---------------------------------------------------------------------------

SCHEMA_STATEMENTS = [
    """
CREATE TABLE IF NOT EXISTS node_variants (
  protocol TEXT NOT NULL,
  host TEXT NOT NULL,
  port INTEGER NOT NULL,
  fingerprint TEXT NOT NULL,
  first_seen INTEGER,
  last_seen INTEGER,
  verified INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (protocol, host, port, fingerprint),
  FOREIGN KEY (protocol, host, port) REFERENCES nodes(protocol, host, port)
)""",
    """
CREATE TABLE IF NOT EXISTS node_sources (
  protocol TEXT NOT NULL,
  host TEXT NOT NULL,
  port INTEGER NOT NULL,
  fingerprint TEXT NOT NULL,
  source TEXT NOT NULL,
  first_seen INTEGER,
  last_seen INTEGER,
  sighting_count INTEGER NOT NULL DEFAULT 0,
  verified INTEGER NOT NULL DEFAULT 0,
  last_evidence TEXT,
  PRIMARY KEY (protocol, host, port, fingerprint, source),
  FOREIGN KEY (protocol, host, port, fingerprint)
    REFERENCES node_variants(protocol, host, port, fingerprint)
)""",
    """
CREATE TABLE IF NOT EXISTS sighting_events (
  event_id TEXT PRIMARY KEY,
  protocol TEXT NOT NULL,
  host TEXT NOT NULL,
  port INTEGER NOT NULL,
  fingerprint TEXT NOT NULL,
  source TEXT NOT NULL,
  ts INTEGER NOT NULL,
  evidence TEXT,
  recorded_at INTEGER NOT NULL
)""",
    """
CREATE TABLE IF NOT EXISTS source_status_log (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  source TEXT NOT NULL,
  status TEXT NOT NULL,
  changed_at INTEGER NOT NULL,
  reason TEXT
)""",
    "CREATE INDEX IF NOT EXISTS idx_node_sources_variant "
    "ON node_sources(protocol, host, port, fingerprint, last_seen)",
    "CREATE INDEX IF NOT EXISTS idx_node_sources_source "
    "ON node_sources(source, last_seen)",
    "CREATE INDEX IF NOT EXISTS idx_node_variants_triplet "
    "ON node_variants(protocol, host, port)",
    "CREATE INDEX IF NOT EXISTS idx_sighting_events_variant "
    "ON sighting_events(protocol, host, port, fingerprint, source, ts)",
]

EXPECTED_TABLES = {
    "node_variants": ["protocol", "host", "port", "fingerprint",
                      "first_seen", "last_seen", "verified"],
    "node_sources": ["protocol", "host", "port", "fingerprint", "source",
                     "first_seen", "last_seen", "sighting_count",
                     "verified", "last_evidence"],
    "sighting_events": ["event_id", "protocol", "host", "port",
                        "fingerprint", "source", "ts", "evidence",
                        "recorded_at"],
    "source_status_log": ["id", "source", "status", "changed_at", "reason"],
}

# v2 table layout (7 columns, no fingerprint): incompatible, fail-closed.
V2_COLUMNS = ["protocol", "host", "port", "source",
              "first_seen", "last_seen", "sighting_count"]


def ensure_schema(conn):
    """Create v4 lineage tables + indexes if missing. No data changes."""
    for stmt in SCHEMA_STATEMENTS:
        conn.execute(stmt)


def table_columns(conn, table):
    return [r[1] for r in conn.execute(f"PRAGMA table_info({table})")]


def schema_matches_v3(conn):
    """True iff all four lineage tables exist with exactly the expected
    columns. (v4 keeps the v3 table layout; only the fingerprint
    computation and the evidence/rollback contracts changed.)"""
    for table, cols in EXPECTED_TABLES.items():
        row = conn.execute(
            "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?",
            (table,)).fetchone()
        if row is None:
            return False
        if table_columns(conn, table) != cols:
            return False
    return True


def has_v2_table(conn):
    """True iff a v2-layout node_sources (no fingerprint) already exists."""
    row = conn.execute(
        "SELECT 1 FROM sqlite_master WHERE type='table' AND name='node_sources'"
    ).fetchone()
    if row is None:
        return False
    return table_columns(conn, "node_sources") == V2_COLUMNS


# ---------------------------------------------------------------------------
# Source registry (caller-supplied config; never guessed from the DB)
# ---------------------------------------------------------------------------

SOURCE_STATUSES = ("active", "paused", "disabled")


class SourceRegistry:
    """Confirmed independent-source groups + statuses, supplied by the
    caller (built from the scraper's own config).

    groups: {group_name: [source, ...]} -- sources in one group are the
        same independent source (e.g. mirrors). A source in two groups is
        a configuration error.
    status: {source: 'active' | 'paused' | 'disabled'} -- a source not
        listed here is 'unverified' and never qualifies.
    A source qualifies only when it is 'active' AND in a confirmed group.
    """

    def __init__(self, groups=None, status=None):
        self.groups = {}
        self._source_group = {}
        for group, sources in dict(groups or {}).items():
            if not group or not isinstance(group, str):
                raise ValueError("bad group name")
            self.groups[group] = list(sources)
            for s in sources:
                if s in self._source_group:
                    raise ValueError(f"source {s!r} in two groups")
                self._source_group[s] = group
        self.status = dict(status or {})
        for s, st in self.status.items():
            if st not in SOURCE_STATUSES:
                raise ValueError(f"bad status {st!r} for {s!r}")

    def group_of(self, source):
        """Confirmed group of a source, or None if unregistered."""
        return self._source_group.get(source)

    def status_of(self, source):
        """'active' | 'paused' | 'disabled' | 'unverified'."""
        return self.status.get(source, "unverified")

    def is_qualified(self, source):
        """True iff the source is active AND in a confirmed group."""
        return self.status_of(source) == "active" and self.group_of(source) is not None


# --- append-only audit trail for source status changes ---------------------

def set_source_status(conn, source, status, ts, reason=""):
    """Append a status change to source_status_log. Does not commit."""
    if not source or not isinstance(source, str):
        raise ValueError("bad source")
    if status not in SOURCE_STATUSES:
        raise ValueError("bad status")
    _validate_ts(ts)
    conn.execute(
        "INSERT INTO source_status_log (source, status, changed_at, reason)"
        " VALUES (?, ?, ?, ?)", (source, status, ts, reason))


def current_source_status(conn, source):
    """Latest logged status for a source, or 'unverified' if never logged."""
    row = conn.execute(
        "SELECT status FROM source_status_log WHERE source=? "
        "ORDER BY id DESC LIMIT 1", (source,)).fetchone()
    return row[0] if row else "unverified"


def registry_from_log(conn, groups):
    """Build a SourceRegistry from the latest logged status per source plus
    caller-supplied groups. Sources never logged are 'unverified'."""
    status = {}
    for (source,) in conn.execute("SELECT DISTINCT source FROM source_status_log"):
        status[source] = current_source_status(conn, source)
    return SourceRegistry(groups=groups, status=status)


# ---------------------------------------------------------------------------
# Sightings (event-level idempotent, monotone time, real evidence required)
# ---------------------------------------------------------------------------

def record_sighting(conn, protocol, host, port, fingerprint, source, ts,
                    evidence, event_id=None, recorded_at=None):
    """Record one sighting event for a config variant.

    fingerprint must be a real 64-hex config fingerprint (never 'legacy':
    legacy rows come only from the migration backfill, never from live
    sightings). evidence (scrape run / batch id) is REQUIRED and non-empty.
    event_id, when given, is the caller's unique event id; a repeated
    event_id is a no-op. Without event_id, dedup uses (variant, source,
    ts): an exact replay is a no-op.

    Time is monotone: first_seen = min(...), last_seen = max(...), so
    out-of-order or replayed evidence can never move last_seen backwards.
    last_evidence is bound to the NEWEST observation: an out-of-order
    older sighting still counts as a new event (sighting_count grows)
    but must NOT overwrite last_evidence with older evidence.

    Returns {"accepted": bool, "reason": str}. Never commits; the caller
    owns the transaction. Never touches nodes / node_tests / phone_failures.
    """
    _validate_variant(protocol, host, port, fingerprint)
    _validate_ts(ts)
    if not source or not isinstance(source, str):
        raise ValueError("bad source")
    if not evidence or not isinstance(evidence, str):
        raise ValueError("evidence (scrape run id) is required")
    if event_id is not None and (not isinstance(event_id, str) or not event_id):
        raise ValueError("bad event_id")
    if recorded_at is None:
        recorded_at = ts
    _validate_ts(recorded_at)

    # Event-level dedup.
    if event_id is not None:
        dup = conn.execute(
            "SELECT 1 FROM sighting_events WHERE event_id=?",
            (event_id,)).fetchone()
        if dup is not None:
            return {"accepted": False, "reason": "duplicate_event"}
    dup = conn.execute(
        "SELECT 1 FROM sighting_events "
        "WHERE protocol=? AND host=? AND port=? AND fingerprint=? "
        "AND source=? AND ts=?",
        (protocol, host, port, fingerprint, source, ts)).fetchone()
    if dup is not None:
        return {"accepted": False, "reason": "replay_same_variant_source_ts"}

    conn.execute(
        "INSERT INTO sighting_events (event_id, protocol, host, port,"
        " fingerprint, source, ts, evidence, recorded_at)"
        " VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
        (event_id if event_id is not None else
         f"{protocol}|{host}|{port}|{fingerprint}|{source}|{ts}",
         protocol, host, port, fingerprint, source, ts, evidence,
         recorded_at))

    conn.execute(
        "INSERT INTO node_variants (protocol, host, port, fingerprint,"
        " first_seen, last_seen, verified) VALUES (?, ?, ?, ?, ?, ?, 1)"
        " ON CONFLICT(protocol, host, port, fingerprint) DO UPDATE SET"
        " first_seen = MIN(COALESCE(node_variants.first_seen, excluded.first_seen), excluded.first_seen),"
        " last_seen = MAX(COALESCE(node_variants.last_seen, excluded.last_seen), excluded.last_seen),"
        " verified = 1",
        (protocol, host, port, fingerprint, ts, ts))
    # last_evidence follows the NEWEST observation only: an out-of-order
    # older sighting (excluded.last_seen < stored last_seen) keeps the
    # evidence that belongs to the newer time.
    conn.execute(
        "INSERT INTO node_sources (protocol, host, port, fingerprint, source,"
        " first_seen, last_seen, sighting_count, verified, last_evidence)"
        " VALUES (?, ?, ?, ?, ?, ?, ?, 1, 1, ?)"
        " ON CONFLICT(protocol, host, port, fingerprint, source) DO UPDATE SET"
        " first_seen = MIN(COALESCE(node_sources.first_seen, excluded.first_seen), excluded.first_seen),"
        " last_seen = MAX(COALESCE(node_sources.last_seen, excluded.last_seen), excluded.last_seen),"
        " sighting_count = node_sources.sighting_count + 1,"
        " verified = 1,"
        " last_evidence = CASE WHEN excluded.last_seen >= node_sources.last_seen"
        " THEN excluded.last_evidence ELSE node_sources.last_evidence END",
        (protocol, host, port, fingerprint, source, ts, ts, evidence))
    return {"accepted": True, "reason": "recorded"}


def lineage(conn, protocol, host, port, fingerprint=None):
    """All (variant, source) rows for a triplet, or one variant when
    fingerprint is given. Most recent first. Each row carries verified /
    legacy markers; legacy rows have NULL observation times."""
    if fingerprint is None:
        rows = conn.execute(
            "SELECT fingerprint, source, first_seen, last_seen,"
            " sighting_count, verified, last_evidence FROM node_sources"
            " WHERE protocol=? AND host=? AND port=?"
            " ORDER BY COALESCE(last_seen, -1) DESC, fingerprint, source",
            (protocol, host, port)).fetchall()
    else:
        rows = conn.execute(
            "SELECT fingerprint, source, first_seen, last_seen,"
            " sighting_count, verified, last_evidence FROM node_sources"
            " WHERE protocol=? AND host=? AND port=? AND fingerprint=?"
            " ORDER BY COALESCE(last_seen, -1) DESC, source",
            (protocol, host, port, fingerprint)).fetchall()
    return [
        {"fingerprint": fp, "source": s, "first_seen": fs, "last_seen": ls,
         "sighting_count": c, "verified": bool(v), "legacy": fp == LEGACY_FINGERPRINT,
         "last_evidence": ev}
        for (fp, s, fs, ls, c, v, ev) in rows
    ]


def variants(conn, protocol, host, port):
    """Config variants known for a triplet (fingerprint + verified flag)."""
    return [
        {"fingerprint": fp, "first_seen": fs, "last_seen": ls,
         "verified": bool(v), "legacy": fp == LEGACY_FINGERPRINT}
        for (fp, fs, ls, v) in conn.execute(
            "SELECT fingerprint, first_seen, last_seen, verified"
            " FROM node_variants WHERE protocol=? AND host=? AND port=?"
            " ORDER BY fingerprint", (protocol, host, port)).fetchall()
    ]


# ---------------------------------------------------------------------------
# Display primary source vs. qualified source group
# ---------------------------------------------------------------------------

def primary_source(conn, protocol, host, port, fingerprint=None):
    """DISPLAY ONLY: the source of the most recent sighting of a variant
    (any status, including legacy). Returns
    {"source", "verified", "legacy", "last_seen"} or None.
    MUST NOT be used for diversity / publish decisions: a paused, dead or
    legacy source can be the most recent sighting."""
    if fingerprint is None:
        row = conn.execute(
            "SELECT source, verified, last_seen FROM node_sources"
            " WHERE protocol=? AND host=? AND port=?"
            " ORDER BY COALESCE(last_seen, -1) DESC, fingerprint, source LIMIT 1",
            (protocol, host, port)).fetchone()
    else:
        row = conn.execute(
            "SELECT source, verified, last_seen FROM node_sources"
            " WHERE protocol=? AND host=? AND port=? AND fingerprint=?"
            " ORDER BY COALESCE(last_seen, -1) DESC, source LIMIT 1",
            (protocol, host, port, fingerprint)).fetchone()
    if row is None:
        return None
    source, verified, last_seen = row
    return {"source": source, "verified": bool(verified),
            "legacy": last_seen is None and not verified,
            "last_seen": last_seen}


def qualified_source_group(conn, registry, protocol, host, port, fingerprint,
                           now, fresh_within_seconds=86400):
    """The qualified independent source GROUP for one config variant, or
    None. Qualification requires a sighting of THIS exact variant from a
    source that is (a) verified (real fingerprint, real evidence), (b)
    status 'active' in the registry, (c) in a confirmed group, and
    (d) fresh: the sighting's age satisfies 0 <= age <=
    fresh_within_seconds relative to `now`. A sighting dated in the
    FUTURE (age < 0) is rejected as evidence, exactly like a stale one;
    an older valid sighting from another qualified source may still
    qualify the variant. Returns the group name of the most recent such
    sighting, else None. A legacy variant (fingerprint 'legacy') never
    qualifies.

    NOTE: source 'active' + freshness is only a PRE-SCREEN of the
    source. It does not prove that the latest successful scrape still
    contains this node, nor that VPS/phone passed it. Integration must
    bind qualification to the latest valid scrape batch and the real
    health status (see DESIGN.md)."""
    if fingerprint == LEGACY_FINGERPRINT or not is_verified_fingerprint(fingerprint):
        return None
    _validate_ts(now)
    if not isinstance(fresh_within_seconds, int) or fresh_within_seconds < 0:
        raise ValueError("bad fresh_within_seconds")
    rows = conn.execute(
        "SELECT source, last_seen FROM node_sources"
        " WHERE protocol=? AND host=? AND port=? AND fingerprint=?"
        " AND verified=1 AND last_seen IS NOT NULL"
        " ORDER BY last_seen DESC, source ASC",
        (protocol, host, port, fingerprint)).fetchall()
    for source, last_seen in rows:
        age = now - last_seen
        if age < 0 or age > fresh_within_seconds:
            continue
        if not registry.is_qualified(source):
            continue
        return registry.group_of(source)
    return None


# ---------------------------------------------------------------------------
# Batch diversity (reject-first, computed over accepted variants only)
# ---------------------------------------------------------------------------

def rebuild_batch(diversity_result):
    """Build a NEW batch from a diversity result: the accepted exact
    identities only, in first-seen order. Publishing MUST use a rebuilt
    batch (re-run through batch_diversity, requiring passes); the
    ORIGINAL candidate list -- which still contains the rejected entries
    -- must never be published."""
    return [tuple(v) for v in diversity_result.get("accepted_variants", [])]


def batch_diversity(conn, registry, candidates, now,
                    fresh_within_seconds=86400):
    """Diversity of a candidate batch, counted per config variant under its
    QUALIFIED source group. candidates: iterable of
    (protocol, host, port, fingerprint).

    Reject-first: a candidate is REJECTED (excluded from every count) when
      - it is a duplicate variant already in this batch, or
      - it has no qualified source group (unknown / unverified / paused /
        disabled / legacy / stale evidence / future-dated evidence).
    Unknown sources never enter the denominator, so they cannot dilute a
    dominant source into passing.

    Each ACCEPTED variant contributes exactly 1, under its qualified group.
    passes = NO rejected entries AND distinct qualified groups >= 3 AND
    max group share <= 1/3 (over accepted total). A batch with any
    rejected entry does NOT pass, even if the accepted remainder would
    pass on its own: the caller must rebuild a new batch from
    accepted_variants and re-run this function on it.
    publishable is True exactly when passes is True (this exact batch may
    be published). Returns {"counts", "distinct", "total", "accepted",
    "accepted_variants", "rejected": [{"variant", "reason"}], "max_share",
    "passes", "publishable"}.
    Never modifies node_tests / phone_failures (failure history is never
    cleared by source bookkeeping)."""
    _validate_ts(now)
    counts = {}
    rejected = []
    seen_variants = set()
    accepted_variants = []
    accepted = 0
    for cand in candidates:
        if len(cand) != 4:
            raise ValueError("candidate must be (protocol, host, port, fingerprint)")
        protocol, host, port, fingerprint = cand
        key = (protocol, host, port, fingerprint)
        if key in seen_variants:
            rejected.append({"variant": key, "reason": "duplicate_variant"})
            continue
        seen_variants.add(key)
        group = qualified_source_group(
            conn, registry, protocol, host, port, fingerprint, now,
            fresh_within_seconds)
        if group is None:
            rejected.append({"variant": key, "reason": "no_qualified_source_group"})
            continue
        counts[group] = counts.get(group, 0) + 1
        accepted += 1
        accepted_variants.append(key)
    distinct = len(counts)
    max_share = (max(counts.values()) / accepted) if accepted else 0.0
    passes = (len(rejected) == 0 and distinct >= 3
              and max_share <= 1.0 / 3.0)
    return {
        "counts": counts,
        "distinct": distinct,
        "total": accepted,
        "accepted": accepted,
        "accepted_variants": accepted_variants,
        "rejected": rejected,
        "max_share": max_share,
        "passes": passes,
        "publishable": passes,
    }
