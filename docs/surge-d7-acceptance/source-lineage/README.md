# #73 source attribution: stable identity + full source lineage

**Offline reference only; no production deployment, no authorization mechanism.**

Implements GPT decision 3 (Issue #73, comment 7115166096): source attribution
uses the node stable identity plus full source lineage. Do not use the last
scrape source or the first-seen source as the only trusted source.

## Problem
`nodes.source` stores a single source (the last scrape). When a node appears in
multiple upstreams, only the last-scraped source is kept and earlier sources
are lost. Example: one node changed its recorded source between two upstreams
and was wrongly excluded under a paused-source rule, even though it also came
from an unpaused source.

## Design (DESIGN.md)
- Stable identity = `(protocol, host, port)`, the `nodes` table primary key.
  Failure history (`node_tests`, `phone_failures`) is already keyed by this
  triple, so changing source never clears it.
- New table `node_sources`: one row per (identity, source) with first_seen,
  last_seen and sighting_count. `nodes.source` stays as a cached "last seen
  source" for backward compatibility, not the sole truth.
- Primary source = the lineage row with max(last_seen); ties by
  max(sighting_count), then source name ASC.
- Batch diversity counts each node once, under its primary source:
  distinct primary sources >= 3 and any one <= 1/3. A node seen in N sources
  is still one node; same-identity multi-scrape is not multiple independent
  sources.

## Files
- `source_lineage.py`: `record_sighting`, `lineage`, `primary_source`,
  `distinct_source_count`, `batch_diversity`, `ensure_schema`. Pure SQLite
  helpers; the caller owns the connection and transaction.
- `migrate_node_sources.py`: idempotent migration (create table + indexes +
  backfill from `nodes.source`). `--check` dry-run, `--rollback` drops the
  table. Fail-closed: any verification failure exits 1. Does not modify
  `nodes`, `node_tests` or `phone_failures`.
- `test_source_lineage.py`: 24 tests on a local copy of a production pool.db
  snapshot (7784 nodes, 247365 node_tests). **24/24 passed in VPS isolation.**
  Synthetic nodes use TEST-NET addresses (203.0.113.0/24). The snapshot itself
  is a local test fixture and is NOT committed here; to re-run, place a
  `pool-snapshot.db` copy next to the test file.

## Deployment (after review)
- GPT reviews this module and its tests first.
- Migration runs in a stopped-crawler window (~1 minute, adds a new table only).
- Then deploy the `record_sighting` call in the crawler.
- Rollback = `DROP TABLE node_sources`; `nodes`/`node_tests`/`phone_failures`
  were never modified.
- No rule is relaxed: diversity (>= 3 sources, any <= 1/3) and freshness
  (<= 300 ms) stay unchanged; this module only makes source attribution exact.
