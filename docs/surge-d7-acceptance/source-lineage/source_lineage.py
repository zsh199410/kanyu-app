"""Source lineage module v3 (GPT decision 3, revised per Review 6031702642).

Fixes all 5 gaps GPT found in the v2 design:
 (1) Identity key: NOT just (protocol, host, port). A config variant is
     (protocol, host, port, config_fingerprint) where the fingerprint is a
     SHA-256 of the canonical non-credential config (SNI / transport / path /
     TLS / ALPN / flow ...). Credentials are stripped BEFORE hashing and are
     never stored, never logged, never committed to the repo. The fingerprint
     can only be computed by the scraper at parse time from the parsed
     subscription config; the DB stores no SNI/transport/auth columns
     (verified against the live pool.db snapshot: nodes/node_tests/
     phone_failures have no such columns), so historical triplets CANNOT be
     retroactively fingerprinted. They are backfilled as the single
     'legacy' variant (fingerprint='legacy', verified=0, NO observation
     times) -- never fabricated into proof of any variant.
 (2) Primary source is DISPLAY ONLY. Qualification for diversity is a
     separate determination: a variant qualifies under a source GROUP only
     when a healthy independent source (status 'active', in a confirmed
     group) currently provides that exact variant with valid, fresh
     evidence. Mirrors share one group; paused/disabled/unregistered
     sources never qualify; a variant with no qualified group is rejected
     from diversity counting, not counted under None.
 (3) batch_diversity REJECTS duplicate variants and unknown/unverified/
     untrusted variants. Diversity is computed over ACCEPTED variants only,
     grouped by confirmed independent source group. Unknown sources never
     enter the denominator, so they cannot dilute a dominant source into
     passing. Backfilling sources never clears a node's failure history:
     this module never touches node_tests / phone_failures.
 (4) record_sighting is event-level idempotent with monotone time:
     - every sighting is an event (variant, source, ts, evidence,
       optional event_id); an exact replay (same variant/source/ts, or
       same event_id) is a no-op -- no count bump, no time change;
     - first_seen = min(...), last_seen = max(...): out-of-order or
       replayed evidence can never move last_seen backwards;
     - evidence (scrape run / batch id) is REQUIRED, non-empty;
     - historical nodes.source is backfilled as legacy/unverified ONLY,
       with NULL observation times -- a node's global first_seen /
       last_seen is never presented as a source's valid observation time.
 (5) Migration is transactional with a verified backup (see
     migrate_node_sources.py): verify BEFORE commit, --check uses a
     read-only connection, backups are never overwritten, --rollback
     restores from a verified backup and refuses when it would destroy
     verified lineage recorded after the backup (unless --allow-data-loss).

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
import json
import re
import sqlite3

LEGACY_FINGERPRINT = "legacy"
_HEX64 = re.compile(r"^[a-f0-9]{64}$")

# Credential / display fields stripped before fingerprinting. A raw URI or
# password must never reach this module: callers parse the subscription
# line first and pass only the parsed config dict.
CREDENTIAL_FIELDS = frozenset({
    "password", "passwd", "pass", "pswd", "uuid", "id", "user", "username",
    "token", "secret", "key", "ps", "name", "remark", "url", "raw", "uri",
    "raw_uri", "link",
})

# ---------------------------------------------------------------------------
# Fingerprint
# ---------------------------------------------------------------------------

def config_fingerprint(config):
    """SHA-256 hex of the canonical non-credential config.

    config is the PARSED subscription config (dict), e.g.
    {"protocol": "trojan", "host": "...", "port": 443, "sni": "...",
     "transport": "ws", "path": "/", "tls": True, "alpn": "h2"}.
    Credential fields (password/uuid/id/user/token/...) and display names
    are removed before hashing, so two configs differing ONLY in
    credentials share one fingerprint, and no credential can leak into the
    fingerprint or the DB. Raises ValueError on non-dict / empty config /
    config that is empty after stripping.
    """
    if not isinstance(config, dict):
        raise ValueError("config must be a dict")
    clean = {k: v for k, v in config.items()
             if k not in CREDENTIAL_FIELDS and v is not None}
    if not clean:
        raise ValueError("config empty after stripping credentials")
    canonical = json.dumps(clean, sort_keys=True, separators=(",", ":"),
                           ensure_ascii=True)
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


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
# Schema (v3)
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
    """Create v3 lineage tables + indexes if missing. No data changes."""
    for stmt in SCHEMA_STATEMENTS:
        conn.execute(stmt)


def table_columns(conn, table):
    return [r[1] for r in conn.execute(f"PRAGMA table_info({table})")]


def schema_matches_v3(conn):
    """True iff all four v3 tables exist with exactly the expected columns."""
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
    sighting_count grows only on genuinely new events.

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
    conn.execute(
        "INSERT INTO node_sources (protocol, host, port, fingerprint, source,"
        " first_seen, last_seen, sighting_count, verified, last_evidence)"
        " VALUES (?, ?, ?, ?, ?, ?, ?, 1, 1, ?)"
        " ON CONFLICT(protocol, host, port, fingerprint, source) DO UPDATE SET"
        " first_seen = MIN(COALESCE(node_sources.first_seen, excluded.first_seen), excluded.first_seen),"
        " last_seen = MAX(COALESCE(node_sources.last_seen, excluded.last_seen), excluded.last_seen),"
        " sighting_count = node_sources.sighting_count + 1,"
        " verified = 1, last_evidence = excluded.last_evidence",
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
    (d) fresh: last_seen within fresh_within_seconds of `now`.
    Returns the group name of the most recent such sighting, else None.
    A legacy variant (fingerprint 'legacy') never qualifies."""
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
        if now - last_seen > fresh_within_seconds:
            continue
        if not registry.is_qualified(source):
            continue
        return registry.group_of(source)
    return None


# ---------------------------------------------------------------------------
# Batch diversity (reject-first, computed over accepted variants only)
# ---------------------------------------------------------------------------

def batch_diversity(conn, registry, candidates, now,
                    fresh_within_seconds=86400):
    """Diversity of a candidate batch, counted per config variant under its
    QUALIFIED source group. candidates: iterable of
    (protocol, host, port, fingerprint).

    Reject-first: a candidate is REJECTED (excluded from every count) when
      - it is a duplicate variant already in this batch, or
      - it has no qualified source group (unknown / unverified / paused /
        disabled / legacy / stale evidence).
    Unknown sources never enter the denominator, so they cannot dilute a
    dominant source into passing.

    Each ACCEPTED variant contributes exactly 1, under its qualified group.
    passes = distinct qualified groups >= 3 AND max group share <= 1/3
    (over accepted total). Returns {"counts", "distinct", "total",
    "accepted", "rejected": [{"variant", "reason"}], "max_share", "passes"}.
    Never modifies node_tests / phone_failures (failure history is never
    cleared by source bookkeeping)."""
    _validate_ts(now)
    counts = {}
    rejected = []
    seen_variants = set()
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
    distinct = len(counts)
    max_share = (max(counts.values()) / accepted) if accepted else 0.0
    return {
        "counts": counts,
        "distinct": distinct,
        "total": accepted,
        "accepted": accepted,
        "rejected": rejected,
        "max_share": max_share,
        "passes": distinct >= 3 and max_share <= 1.0 / 3.0,
    }
