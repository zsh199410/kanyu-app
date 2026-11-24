"""Source lineage module (GPT decision 3: stable identity + full source lineage).

Rules:
- Stable identity is (protocol, host, port) -- the nodes table primary key.
- node_sources records EVERY source a node was ever seen in. nodes.source
  stays as a cached "last seen source" for backward compatibility but is no
  longer the sole truth.
- Changing source never clears failure history: node_tests and phone_failures
  are keyed by (protocol, host, port), not by source.
- Same-identity multi-scrape is NOT multiple independent sources: a node
  seen in N sources is still ONE node. Batch diversity counts each node once,
  under its primary source.
- Primary source = the lineage row with max(last_seen); ties broken by
  max(sighting_count), then source name ASC (deterministic).

Pure SQLite helpers; no network, no publisher, no production writes here --
the caller owns the connection and the transaction.
"""
import sqlite3

UPSERT_SIGHTING = """
INSERT INTO node_sources
  (protocol, host, port, source, first_seen, last_seen, sighting_count)
VALUES (?, ?, ?, ?, ?, ?, 1)
ON CONFLICT(protocol, host, port, source) DO UPDATE SET
  last_seen = excluded.last_seen,
  sighting_count = node_sources.sighting_count + 1
"""

LINEAGE_QUERY = """
SELECT source, first_seen, last_seen, sighting_count FROM node_sources
WHERE protocol=? AND host=? AND port=? ORDER BY last_seen DESC, sighting_count DESC, source ASC
"""

PRIMARY_QUERY = """
SELECT source FROM node_sources
WHERE protocol=? AND host=? AND port=?
ORDER BY last_seen DESC, sighting_count DESC, source ASC LIMIT 1
"""

DISTINCT_SOURCES_QUERY = """
SELECT COUNT(DISTINCT source) FROM node_sources
WHERE protocol=? AND host=? AND port=?
"""


def record_sighting(conn, protocol, host, port, source, ts):
    """Record that identity (protocol,host,port) was seen in `source` at `ts`.
    Idempotent per (identity, source): repeat sightings bump sighting_count
    and refresh last_seen. Never touches nodes/node_tests/phone_failures."""
    if not isinstance(ts, int) or ts < 0:
        raise ValueError("bad timestamp")
    if not source or not isinstance(source, str):
        raise ValueError("bad source")
    conn.execute(UPSERT_SIGHTING, (protocol, host, port, source, ts, ts))


def lineage(conn, protocol, host, port):
    """All sources an identity was ever seen in, most recent first."""
    return [
        {"source": s, "first_seen": fs, "last_seen": ls, "sighting_count": c}
        for (s, fs, ls, c) in conn.execute(LINEAGE_QUERY, (protocol, host, port))
    ]


def primary_source(conn, protocol, host, port):
    """The single primary source of an identity (most recent sighting).
    Returns None when the identity has no lineage rows."""
    row = conn.execute(PRIMARY_QUERY, (protocol, host, port)).fetchone()
    return row[0] if row else None


def distinct_source_count(conn, protocol, host, port):
    """How many distinct sources an identity was ever seen in.
    Reporting only: this does NOT make the node count as N independent
    sources in any diversity rule."""
    return conn.execute(DISTINCT_SOURCES_QUERY, (protocol, host, port)).fetchone()[0]


def batch_diversity(conn, identities):
    """Diversity of a candidate batch, counted per node under its primary
    source. Each node contributes exactly 1, even if it was seen in many
    sources. Nodes with no lineage are counted under source None and do not
    add a distinct source.
    Returns {counts, distinct, total, max_share, passes} where passes means
    distinct >= 3 and max_share <= 1/3."""
    counts = {}
    total = 0
    for (protocol, host, port) in identities:
        ps = primary_source(conn, protocol, host, port)
        counts[ps] = counts.get(ps, 0) + 1
        total += 1
    named = {s: n for s, n in counts.items() if s is not None}
    distinct = len(named)
    max_share = (max(named.values()) / total) if total and named else 0.0
    return {
        "counts": counts,
        "distinct": distinct,
        "total": total,
        "max_share": max_share,
        "passes": distinct >= 3 and max_share <= 1.0 / 3.0,
    }


def ensure_schema(conn):
    """Create node_sources + indexes if missing. Same DDL as the migration."""
    conn.execute("""
CREATE TABLE IF NOT EXISTS node_sources (
  protocol TEXT NOT NULL,
  host TEXT NOT NULL,
  port INTEGER NOT NULL,
  source TEXT NOT NULL,
  first_seen INTEGER NOT NULL,
  last_seen INTEGER NOT NULL,
  sighting_count INTEGER NOT NULL DEFAULT 1,
  PRIMARY KEY (protocol, host, port, source),
  FOREIGN KEY (protocol, host, port) REFERENCES nodes(protocol, host, port)
)""")
    conn.execute("CREATE INDEX IF NOT EXISTS idx_node_sources_identity "
                 "ON node_sources(protocol, host, port, last_seen)")
    conn.execute("CREATE INDEX IF NOT EXISTS idx_node_sources_source "
                 "ON node_sources(source, last_seen)")
