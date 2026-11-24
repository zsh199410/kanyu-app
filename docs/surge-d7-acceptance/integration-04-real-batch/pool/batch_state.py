#!/usr/bin/env python3
"""Per-source latest-successful-complete-crawl batches (integration-04,
Review 6034205305 points 2 and 3).

The gap this closes: LineageRecorder.observe saved one sighting per
parsed line and the crawl only wrote counts at the end. The registry was
saved but never used for member qualification, and there was no
per-source "latest successful complete crawl" member set or health
status. A variant that disappeared from a source's new crawl, a failed
or partially parsed crawl, a hook exception, a disabled/paused change,
or a missing key / missing adapter module could all keep qualifying on
a 24h-old sighting. The v4 docstring already said so: "active + 24h
freshness of a SOURCE is only a pre-screen of the source; it does not
prove that the latest successful scrape still contains this node."

Design (two halves, one explicit transaction):

  * COLLECT (in memory, during network I/O -- no DB access, no write
    lock held): BatchCollector.observe is the crawl_records
    on_observation callback (Test B position, same as the lineage
    hook). It records, per source, the member identities seen in THIS
    crawl (protocol/host/port + config fingerprint when the lineage
    recorder is available) plus per-source hook errors. It never
    touches the DB. After crawl_records returns, finish(counts) attaches
    the per-source fetch/parse outcomes from the crawl counts and
    decides each source's batch status:
      "complete"   -- fetch ok, no parse failures, no hook errors,
                      lineage available, at least one observed member.
      "failed"     -- the fetch itself failed (http/network/other).
      "partial"    -- fetch ok but some lines failed to parse or the
                      hook raised for this source.
      "empty"      -- fetch ok but zero lines observed (an empty
                      success proves nothing; it must not certify an
                      empty member set and must not silently keep the
                      old one either -- the latest batch is "empty",
                      so the consumer BLOCKs until a real complete
                      batch arrives).
      "incomplete" -- lineage unavailable for this crawl (no key /
                      no module / disabled by flag / schema not
                      migrated / bad registry): without the lineage
                      hook there is no per-line evidence, so the batch
                      cannot certify members even though the crawl
                      itself ran fine.
      "disabled"   -- the source was in disabled_sources at crawl time
                      (skipped before any fetch).
    A vanished variant is simply absent from the new member set: the
    consumer reads ONLY the latest complete batch, so a variant that
    disappeared stops qualifying the moment a newer complete batch
    exists. A source that disappears from sources.yaml entirely has no
    new batch; the consumer additionally requires the source to still
    be known and active (see qualified_batch_members), so it BLOCKs
    rather than serving the stale batch past its TTL.
  * COMMIT (one explicit transaction, after the crawl -- no network I/O
    while the lock is held): commit_batch writes, in a single
    BEGIN IMMEDIATE ... COMMIT, the batch rows (one per attempted
    source, with status + counts + error), the member rows (ONLY for
    "complete" batches -- an incomplete/failed/partial/empty/disabled
    batch writes NO members, so no consumable completion evidence can
    exist for it), and nothing else. A duplicate (source, started)
    commit is refused unless the stored batch is byte-identical (then
    it is a no-op). Any error inside the transaction rolls everything
    back: no batch row, no members, no completion marker.
    The caller (cmd_crawl) owns the transaction: it opens
    BEGIN IMMEDIATE, upserts nodes, updates sources, flushes lineage,
    commits the batch, writes the run row, and commits once. A batch
    schema problem is detected BEFORE the transaction (fail-closed for
    the batch only: the crawl still commits nodes/lineage, the batch
    is recorded as unavailable, consumers BLOCK). An error DURING the
    transaction rolls the whole crawl back.

  * CONSUME (read-only): qualified_batch_members returns a source's
    member set ONLY when the latest batch for that source is
    "complete" AND fresh (0 <= age <= TTL, default 24h) AND the source
    is currently active (not disabled, not paused, still known).
    Anything else returns (None, reason) -> BLOCKED. The registry and
    the disabled set are read at CONSUMPTION time, so a disabled/paused
    change takes effect immediately even if the latest batch is still
    fresh.

Tables (created by migrate_batch_state.py, never by cmd_crawl):
  crawl_batches (source, started, completed_at, status, members,
                 observed, unparsed, hook_errors, error, evidence,
                 registry_status; UNIQUE(source, started))
  crawl_batch_members (batch_id, protocol, host, port, fingerprint;
                       PRIMARY KEY(batch_id, protocol, host, port, fingerprint))
Member rows carry only non-secret identity (protocol/host/port +
HMAC fingerprint). No password, uuid, URI or key is ever stored here.
"""
import sqlite3

BATCH_TTL_S = 86400  # 24h: a complete batch older than this does not qualify
BATCH_PRUNE_DAYS = 30

BATCH_STATUSES = ("complete", "failed", "partial", "empty",
                  "incomplete", "disabled")

BATCH_SCHEMA = """
CREATE TABLE IF NOT EXISTS crawl_batches (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  source TEXT NOT NULL,
  started INTEGER NOT NULL,
  completed_at INTEGER NOT NULL,
  status TEXT NOT NULL,
  members INTEGER NOT NULL DEFAULT 0,
  observed INTEGER NOT NULL DEFAULT 0,
  unparsed INTEGER NOT NULL DEFAULT 0,
  hook_errors INTEGER NOT NULL DEFAULT 0,
  error TEXT NOT NULL DEFAULT '',
  evidence TEXT NOT NULL DEFAULT '',
  registry_status TEXT NOT NULL DEFAULT 'unknown',
  UNIQUE (source, started)
);
CREATE TABLE IF NOT EXISTS crawl_batch_members (
  batch_id INTEGER NOT NULL,
  protocol TEXT NOT NULL,
  host TEXT NOT NULL,
  port INTEGER NOT NULL,
  fingerprint TEXT,
  PRIMARY KEY (batch_id, protocol, host, port, fingerprint)
);
CREATE INDEX IF NOT EXISTS idx_crawl_batches_source_started
  ON crawl_batches (source, started);
CREATE INDEX IF NOT EXISTS idx_crawl_batch_members_key
  ON crawl_batch_members (protocol, host, port);
"""

EXPECTED_BATCH_TABLES = {
    "crawl_batches": ["id", "source", "started", "completed_at", "status",
                      "members", "observed", "unparsed", "hook_errors",
                      "error", "evidence", "registry_status"],
    "crawl_batch_members": ["batch_id", "protocol", "host", "port",
                            "fingerprint"],
}


class BatchUnavailable(Exception):
    """The batch layer cannot run for this crawl (schema/registry/key).
    Carries a short machine-readable reason; the crawl proceeds without
    batch evidence and consumers BLOCK."""

    def __init__(self, reason):
        super().__init__(reason)
        self.reason = reason


def batch_schema_ready(conn):
    """True iff the crawl_batches / crawl_batch_members tables exist with
    exactly the expected columns. (Migration is a separate approved step;
    cmd_crawl never creates tables on the fly.)"""
    try:
        for table, cols in EXPECTED_BATCH_TABLES.items():
            row = conn.execute(
                "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?",
                (table,)).fetchone()
            if row is None:
                return False
            have = [r[1] for r in conn.execute(
                "PRAGMA table_info(%s)" % table)]
            if have != cols:
                return False
        return True
    except Exception:
        return False


# ---------------------------------------------------------------------------
# Collector: in-memory only, no DB access during network I/O
# ---------------------------------------------------------------------------

class BatchCollector:
    """Per-crawl-batch collector. Constructed once per crawl run by
    cmd_crawl; `observe` is passed as crawl_records' on_observation
    callback (Test B position: per parsed line, before dedup).

    Owns no transaction and touches no DB: members and hook errors are
    collected in memory while the network fetch runs. `finish(counts)`
    attaches the per-source fetch/parse outcomes and decides each
    source's batch status; `commit_batch` (below) writes the result in
    one explicit transaction after the crawl.
    """

    def __init__(self, started, *, lineage=None, lineage_reason=""):
        self.started = started
        # lineage: a LineageRecorder in defer mode, or None when lineage
        # is unavailable for this crawl. Without it there is no per-line
        # evidence, so no batch from this crawl can be "complete".
        self.lineage = lineage
        self.lineage_reason = lineage_reason
        # source -> {"members": {(proto, host, port): fingerprint|None},
        #            "hook_errors": int, "observed": int,
        #            "skipped": {reason: count}}
        self.sources = {}
        self.finished = None  # {source: batch dict} after finish()

    def _src(self, name):
        return self.sources.setdefault(
            name, {"members": {}, "hook_errors": 0, "observed": 0,
                   "skipped": {}})

    def observe(self, rec):
        """Record one parsed line's batch membership. Never raises for a
        bad record: a hook failure is counted for this source (which
        makes its batch "partial") and the crawl continues -- lineage
        is additive diagnostics, its failure must not drag down the
        production crawl. Returns True if the line became a member."""
        st = self._src(rec["source"])
        st["observed"] += 1
        if self.lineage is None:
            # No per-line evidence this crawl: the member is recorded
            # by triple only (fingerprint None) and the batch will be
            # "incomplete" at finish() -- never consumable.
            key = (rec["protocol"], rec["host"], int(rec["port"]))
            st["members"].setdefault(key, None)
            return True
        try:
            r = self.lineage.collect(rec)
        except Exception:
            st["hook_errors"] += 1
            return False
        if not r.get("recorded"):
            st["skipped"][r.get("reason", "not_accepted")] = \
                st["skipped"].get(r.get("reason", "not_accepted"), 0) + 1
            return False
        # collect() staged the sighting; the fingerprint is the staged
        # identity. Recompute it cheaply from the staged pending entry
        # instead of re-hashing: the recorder exposes it via last_fp.
        fp = self.lineage.last_fingerprint
        key = (rec["protocol"], rec["host"], int(rec["port"]))
        st["members"].setdefault(key, fp)
        return True

    def finish(self, counts, *, disabled=(), registry_status=None):
        """Decide every attempted source's batch status from the crawl
        counts (per-source fetch/parse outcomes) plus the in-memory
        observations. `disabled` is the set of sources skipped before
        any fetch; `registry_status` maps source -> 'active'/'paused'/
        'disabled'/'unverified' at crawl time (audit only; the consumer
        re-checks current status). Returns {source: batch dict} and
        stores it on self.finished. Idempotent: a second call returns
        the same dict."""
        if self.finished is not None:
            return self.finished
        registry_status = registry_status or {}
        by_source = (counts or {}).get("by_source", {})
        out = {}
        names = set(by_source) | set(self.sources) | set(disabled)
        for name in sorted(names):
            sc = by_source.get(name, {})
            st = self.sources.get(name, {"members": {}, "hook_errors": 0,
                                         "observed": 0, "skipped": {}})
            # crawl_records per-source parse stats (v2 crawler): unparsed
            # lines and callback errors for THIS source. Older counters
            # without them default to 0 (a crawl that never ran the new
            # crawler cannot certify a batch either -- see below).
            unparsed = sc.get("unparsed", 0)
            obs_err = sc.get("observation_errors", 0)
            fetch_ok = sc.get("status") == "ok"
            if name in disabled:
                status, error = "disabled", "source_disabled_at_crawl"
            elif not fetch_ok:
                status, error = "failed", sc.get("error", "fetch_failed")
            elif self.lineage is None:
                status, error = "incomplete", (
                    "lineage_unavailable:%s" % (self.lineage_reason or "?"))
            elif unparsed or obs_err or st["hook_errors"]:
                status, error = "partial", (
                    "unparsed=%d observation_errors=%d hook_errors=%d"
                    % (unparsed, obs_err, st["hook_errors"]))
            elif st["observed"] == 0:
                status, error = "empty", "source_empty_success"
            else:
                status, error = "complete", ""
            out[name] = {
                "source": name, "started": self.started,
                "completed_at": self.started,
                "status": status, "error": error,
                "members": len(st["members"]) if status == "complete" else 0,
                "observed": st["observed"], "unparsed": unparsed,
                "hook_errors": st["hook_errors"],
                "evidence": "crawl:%d" % self.started,
                "registry_status": registry_status.get(name, "unknown"),
                "_member_rows": (sorted(
                    (p, h, po, fp) for (p, h, po), fp in st["members"].items())
                    if status == "complete" else []),
            }
        self.finished = out
        return out

    def summary(self):
        """Counts only -- no fingerprints, no credentials, no URIs.
        Safe to store in runs.counts and print to stdout."""
        if self.finished is None:
            return {"enabled": False, "reason": "not_finished"}
        by_status = {}
        for b in self.finished.values():
            by_status[b["status"]] = by_status.get(b["status"], 0) + 1
        return {"enabled": True, "evidence": "crawl:%d" % self.started,
                "batches": len(self.finished), "by_status": by_status,
                "complete_members": sum(
                    b["members"] for b in self.finished.values())}


# ---------------------------------------------------------------------------
# Commit: one explicit transaction, after the crawl
# ---------------------------------------------------------------------------

def commit_batch(conn, collector):
    """Write one crawl's batches + members in the caller's explicit
    transaction (BEGIN IMMEDIATE must already be held; this function
    never begins/commits). Only "complete" batches get member rows;
    every other status writes the batch row alone, so no consumable
    completion evidence can exist for it. A duplicate (source, started)
    commit is refused unless the stored batch is identical (then it is
    a no-op). Returns {source: batch_id}. Raises on any error: the
    caller rolls the whole crawl transaction back."""
    if collector.finished is None:
        raise BatchUnavailable("collector_not_finished")
    if not batch_schema_ready(conn):
        raise BatchUnavailable("schema_not_migrated")
    out = {}
    for name in sorted(collector.finished):
        b = collector.finished[name]
        row = conn.execute(
            "SELECT id, status, members, observed, unparsed, hook_errors,"
            " error, evidence, registry_status FROM crawl_batches"
            " WHERE source=? AND started=?",
            (name, b["started"])).fetchone()
        if row is not None:
            stored = {"status": row[1], "members": row[2],
                      "observed": row[3], "unparsed": row[4],
                      "hook_errors": row[5], "error": row[6],
                      "evidence": row[7], "registry_status": row[8]}
            current = {k: b[k] for k in stored}
            if stored == current:
                # The batch ROW matches, but the member rows are part of
                # the batch's bytes too: same counts with different
                # members is a conflict, not a no-op.
                stored_members = {
                    (p, h, po, fp) for (p, h, po, fp) in conn.execute(
                        "SELECT protocol, host, port, fingerprint"
                        " FROM crawl_batch_members WHERE batch_id=?",
                        (row[0],)).fetchall()}
                if stored_members == set(b["_member_rows"]):
                    out[name] = row[0]
                    continue
            raise BatchUnavailable(
                "duplicate_batch_conflict:%s" % name)
        cur = conn.execute(
            "INSERT INTO crawl_batches (source, started, completed_at,"
            " status, members, observed, unparsed, hook_errors, error,"
            " evidence, registry_status) VALUES (?,?,?,?,?,?,?,?,?,?,?)",
            (name, b["started"], b["completed_at"], b["status"],
             b["members"], b["observed"], b["unparsed"], b["hook_errors"],
             b["error"], b["evidence"], b["registry_status"]))
        batch_id = cur.lastrowid
        for (proto, host, port, fp) in b["_member_rows"]:
            conn.execute(
                "INSERT OR IGNORE INTO crawl_batch_members"
                " (batch_id, protocol, host, port, fingerprint)"
                " VALUES (?,?,?,?,?)",
                (batch_id, proto, host, port, fp))
        out[name] = batch_id
    return out


# ---------------------------------------------------------------------------
# Consume: read-only, fail-closed
# ---------------------------------------------------------------------------

def qualified_batch_members(conn, source, now, *, ttl_s=BATCH_TTL_S,
                            disabled=(), registry_status=None,
                            known_sources=None):
    """Return (members, reason) for one source's latest batch.

    members is a list of (protocol, host, port, fingerprint) ONLY when
    the latest batch for `source` is "complete" AND fresh
    (0 <= now - completed_at <= ttl_s) AND the source is currently
    active (not in `disabled`, registry status "active", still in
    `known_sources`). Anything else returns (None, reason) -> BLOCKED.
    `registry_status` maps source -> status; None means the registry
    could not be read -> BLOCKED ("registry_unavailable"). `known_sources`
    is the current source list; None -> BLOCKED ("source_unknown").
    The registry / disabled set are read at CONSUMPTION time, so a
    disabled/paused change takes effect immediately.
    """
    if not batch_schema_ready(conn):
        return None, "schema_missing"
    if registry_status is None:
        return None, "registry_unavailable"
    if known_sources is None:
        return None, "source_unknown"
    if source in (disabled or ()):
        return None, "source_disabled"
    if registry_status.get(source, "unverified") != "active":
        return None, "source_paused_or_unverified"
    if source not in known_sources:
        return None, "source_unknown"
    row = conn.execute(
        "SELECT id, status, completed_at FROM crawl_batches"
        " WHERE source=? ORDER BY started DESC, id DESC LIMIT 1",
        (source,)).fetchone()
    if row is None:
        return None, "no_complete_batch"
    batch_id, status, completed_at = row
    if status != "complete":
        return None, "batch_incomplete:%s" % status
    age = now - completed_at
    if age < 0 or age > ttl_s:
        return None, "batch_stale"
    members = conn.execute(
        "SELECT protocol, host, port, fingerprint FROM crawl_batch_members"
        " WHERE batch_id=? ORDER BY protocol, host, port",
        (batch_id,)).fetchall()
    if not members:
        return None, "batch_empty"
    return [(p, h, po, fp) for (p, h, po, fp) in members], "ok"


def prune_batches(conn, days=BATCH_PRUNE_DAYS):
    """Delete batch rows (and their members) older than `days`. Called
    by cmd_crawl after a successful commit, in its own short
    transaction -- same pattern as db.prune_old in cmd_test. Returns
    the number of batch rows deleted."""
    import time
    cutoff = int(time.time()) - days * 86400
    n = conn.execute(
        "DELETE FROM crawl_batches WHERE completed_at < ?",
        (cutoff,)).rowcount
    conn.execute(
        "DELETE FROM crawl_batch_members WHERE batch_id NOT IN"
        " (SELECT id FROM crawl_batches)")
    return n
