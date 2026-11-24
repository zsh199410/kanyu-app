# Integration-02: source hook / normalization / latest-batch binding

[Draft] #73 follow-up to PR #125 (v4 frozen, HEAD `b10670d7`) and PR #126
(integration-01, control contract). Implements GPT ruling 7120382777,
second-stage item 2: **source hook / normalization / latest-batch
binding**. Isolated diff package + isolation tests only. No production
deployment, no live-file change, no unit change, no key created.

## What this diff does (one paragraph per ruling item)

- **D1 — hook position (Test B, mandatory).** `crawler.crawl_records`
  gains an optional `on_observation` callback, invoked per successfully
  parsed line AFTER the protocol allow-list check and BEFORE dedup.
  The same triple seen in 3 sources is recorded 3 times (12 lines ->
  12 sightings, 9 variants); a hook placed after dedup (Test A) sees
  only 1 source per triple and loses mirror evidence and auth variants
  — Test A is reproduced in the test suite as a negative proof and is
  NOT used. `cli.cmd_crawl` wires the hook; lineage is additive only:
  any lineage failure disables LINEAGE loudly (logged + counted in
  `runs.counts["lineage"]`), never the crawl itself. `--no-lineage`
  is an explicit operator escape hatch.
- **D2 — vmess security kept.** `canonical_config` keeps the `security`
  field verbatim (`auto` / `chacha20-poly1305` / `none` / `aes-128-gcm`);
  it is never normalized to `auto`. Live prevalence re-measured this
  round: 34/3645 vmess lines are non-`auto` (line level), 24/2365
  (deduped triples). Not a zero sample.
- **D3 — ss plugin kept.** `canonical_config` keeps `plugin` +
  parameters; only plugins supported by both the real client and the
  tester AND losslessly round-trippable may publish. Live: 0/1656
  lines carry a plugin today, but the field is kept, not omitted.
- **B10 — comma passwords refused from publish.** `pre_filter` and
  `build_surge_line` reject any `","` in a trojan/ss password
  (with or without a following space; the old `", "` check is subsumed).
  The original config is left in restricted parse/history only; the
  password is never rewritten and no credential is ever output.
  Live: 0/6365 lines carry a comma password today.
  **B10-EXTENSION (needs GPT confirmation):** a comma in a vmess uuid
  corrupts `username=` the same way (comma-split Surge params).
  Implemented the same way (`comma-uuid`), flagged in code and in the
  report; live: 0 uuids contain a comma.
- **O1 — vmess net whitelist.** Only `ws` / `tcp` / `""` are admitted
  to lineage; anything else (`grpc`, `raw`, `http`, `xhttp`, `h2`,
  `none`, `tcp,udp`, fragment junk) goes to the isolation audit
  (`skipped.unsupported-net`) and gets no lineage row. Live impact:
  261/3645 vmess lines (7.2%) would be excluded from lineage.
  **Scope decision (needs GPT confirmation):** trojan `grpc` and ss
  non-AEAD methods are NOT gated by O1 — `pre_filter` already bars
  them from publish, and their source attribution is real evidence.
  Gating them in lineage would hide 300+ real records with no ruling
  behind it. Extending the gate is a one-line change if GPT wants it.
- **B5 — HMAC key (code + docs only).** Key via 600 root-only env file
  + systemd `EnvironmentFile` (P0-1 option A); `build_lineage_recorder`
  checks key -> registry -> schema in that order and raises
  `LineageUnavailable` on any failure. **No key is created and no unit
  is changed in this diff** — GPT 7120382777 states unit changes and
  key creation are not in this round's production permission. Missing
  key = lineage disabled, crawl still runs (fail-closed for lineage).
- **Latest-batch binding.** Every sighting carries
  `evidence = "crawl:{started}"` and
  `event_id = "crawl:{started}:{protocol}|{host}|{port}|{fingerprint}|{source}"`;
  `node_sources.last_evidence` always tracks the newest run.
  Groups per P1-1 (alirewa / chenzhihan / matin / au1rxx) with D5
  applied: au1rxx is folded into the chenzhihan group (65% overlap,
  independence unproven); alirewa sub-subscriptions fold into alirewa;
  chenzhihan's two subscriptions are one group; barry-far is NOT a
  group (aggregator, not an operator). B4 registry is R1 (live reality:
  `disabled_sources = []`, re-verified this round); the R2
  (pause-at-scrape-layer) shape is tested as a contrast.
- **v4 frozen.** `source_lineage.py` and `migrate_node_sources.py`
  are byte-identical to PR #125 v4 (SHA `f6038da1…` / `0dbef378…`).
  `db.py`, `publish.py`, `tester.py`, `geo.py`, `__init__.py` are
  byte-identical to live. No threshold was lowered anywhere; the
  honest control count (0 qualified controls in the formal pool) is
  untouched by this diff.

## Diff size (vs live, 2026-11-24 11:26 CST)

| file | change |
| --- | --- |
| `pool/crawler.py` | +17 / −2 (optional `on_observation` param + hook call) |
| `pool/cli.py` | +45 / −3 (lineage wiring, `--no-lineage`, lineage summary in `counts`) |
| `pool/rules.py` | +24 / −4 (B10 `comma-password`, B10-EXTENSION `comma-uuid`) |
| `pool/lineage_adapter.py` | new, 350 lines (canonical_config, admission_gate, LineageRecorder, registry, build_lineage_recorder) |
| `pool/source_lineage.py`, `pool/migrate_node_sources.py` | v4 verbatim (SHA-verified) |
| `pool/db.py`, `publish.py`, `tester.py`, `geo.py`, `__init__.py` | live verbatim (SHA-verified) |
| `source_groups.json` | new, 33 lines (R1 registry: 3 groups, 10 sources, paused = chenzhihan-base64 + matin-ss) |
| `tests/` | 5 scripts (see below) |

Total package: 17 files, ~4,900 lines (tests included).

## Isolation tests (all green, 2026-11-24 ~11:30 CST)

Run from `tests/` (PR layout) or from the workspace harness — the
scripts resolve both layouts. Synthetic TEST-NET identities and test
keys only; live DB never written; live pool never touched.

- `tests/test-i02-source-hook.py` — **116 checks, 0 failed** (Parts 1–7):
  - P1 dual-entry regression (17 cases): raw fingerprint match **0/17**
    (known: `name_hint`/`source` differ by entry); after normalization
    **11/17** consistent. **Correction:** P1-1's summary said 12/17,
    but its own table lists 11 "yes" + 5 divergences + 1 refusal = 17;
    this suite asserts per-case expectations and measures 11/17.
    Divergences are by design, not failures: T5/S4 now BUILD_REFUSED
    (B10), T6 pre-existing refusal, V3 diverges on `security` only
    (D2), V4/S2 refused by `pre_filter` (O1 / ss-plugin).
  - P2 hook placement with the REAL `crawl_records`: Test A sees 1
    source for triple 101 (mirror evidence lost); Test B records 12
    sightings / 9 variants, triple 101 gets 3 variants / 4 lineage
    rows; hook errors counted (`observation_errors`), crawl intact.
  - P3 registries + batch diversity: real registry loads (3 groups,
    10 sources, 2 paused); au1rxx folded; barry-far not a group;
    R1/R2 contrast; GPT example A,A,B,C,unknown,unknown fails;
    3+1-unknown fails, `rebuild_batch` passes and the original list
    is not publishable; future timestamps rejected.
  - P4 O1 net whitelist: `ws`/`tcp`/`""` admitted; `grpc`/`raw`/
    `http`/`xhttp`/`h2`/`none`/`tcp,udp`/fragment junk audited, not
    recorded; trojan-grpc + ss-rc4-md5 explicitly NOT gated by O1
    (scope decision, see above).
  - P5 B10: comma passwords refused by `pre_filter` + `build_surge_line`
    for trojan and ss (with and without a space); comma uuid refused
    (extension); clean passwords pass; lineage still records a
    comma-password node (B10 gates publish, not lineage).
  - P6 `cmd_crawl` end-to-end (real subprocess, synthetic base):
    unmigrated schema -> lineage disabled (`schema_not_migrated`),
    crawl still succeeds; migrate (backfilled 7) -> 12 recorded /
    9 variants, `evidence = crawl:{started}`; second run -> 24
    events, variants still 9, same `event_id` replay is a no-op;
    no-key / `--no-lineage` / missing-registry all disable lineage
    while the crawl succeeds.
  - P7 latest-batch binding: 2 distinct run evidences;
    `last_evidence` = latest run on every real row; qualified group
    traces to the latest run.
- `tests/test-i02-rollback.py` — **ALL PASSED** (Part 8, on copies of
  the fresh production snapshot, 2026-11-24 11:15, 7798 nodes):
  `--check` is read-only (digest unchanged, `would_backfill_rows` 7798);
  migrate backfills 7798; after three post-backup write kinds
  (node_tests row, sighting event, status-log entry) `--rollback
  --backup` returns mode `retained`, `whole_db_restore: refused`,
  file digest byte-identical; (a) no further lineage calls + 2 s
  window stable, (b) counts identical, (c) liveness query + lineage
  query + `integrity_check ok`; zero-write whole-DB restore works on
  a SECOND copy only (snapshot-only; **production use DISABLED by
  GPT**); `--allow-data-loss` rejected (exit 2); `--rollback` without
  `--backup` rejected (exit 2).
- `tests/test-i02-perf.py` — **PASSED** (Part 9): 2000 synthetic lines
  (4 sources x 500) through the real `crawl_records` + recorder path
  in ~160 ms, **~80–93 ms / 1000 observations** (two runs: 79.8 and
  92.5), 0 errors. No tuned threshold; the only bound is a 60 s
  sanity cap.
- `tests/live-prevalence.py`, `tests/live-prevalence-lines.py` —
  read-only live probes (see below).

## Live prevalence re-measured this round (2026-11-24 11:26 CST)

Two populations, labelled so the numbers are not mixed up:

- **Line level (P1-1 population, duplicates included):** 9321 lines;
  82 unparsed; other protocols vless 2665 / ssr 22 / hy2 177 /
  hysteria2 10; trojan 1064 / vmess 3645 / ss 1656; vmess security
  non-`auto` **34/3645**; vmess net ws 2317 / tcp 1067 / httpupgrade
  51 / grpc 38 / raw 55 / http 85 / xhttp 23 / none 4 / h2 2 /
  malformed 3; vmess TLS 1479 / non-TLS 2166; vmess non-ws with path
  106 / with host 265; trojan t_type tcp 811 / ws 225 / grpc 26 /
  httpupgrade 2; ss plugin **0/1656**; comma passwords **0/6365**;
  comma uuids **0**; union triples 4023.
- **Deduped-triple level:** vmess security non-`auto` 24/2365; ss
  plugin 0/1114; trojan t_type tcp 405 / ws 124 / grpc 14 /
  httpupgrade 1 (544 unique trojan triples).
- **Source overlap (line level, per-line source labels):**
  chenzhihan-base64 x chenzhihan-v2ray **375/375 identical**;
  alirewa-sub1 46/46, sub2 47/47, sub3 13/13 contained in
  alirewa-config; au1rxx x chenzhihan **174/269 = 65%**;
  matin's three subscriptions share **0** triples with each other.
  Cross-group overlap is otherwise broad (e.g. alirewa-config x
  matin-vmess 299), confirming the shared node universe — the reason
  D5 stays conservative.
- **Live DB (read-only):** nodes 7798, node_tests 248974,
  `disabled_sources = []` (re-verified), 10 sources all reachable.

## Deployment notes (not a deployment request)

1. Migration first (separately approved window, writers stopped,
   ~1 min, adds tables only): `migrate_node_sources.py <db>`.
2. Deploy `pool/` files, then add the HMAC key as a 600 root-only env
   file and add `EnvironmentFile=` to the pool-crawl unit. **Unit
   change and key creation are NOT in this round's production
   permission (GPT 7120382777 B5)** — they need separate approval.
3. The crawl service needs no restart for the hook itself; the
   lineage summary appears in `runs.counts["lineage"]`.
4. Rollback: `--rollback --backup <file>` is retained-mode by default
   (refuses whole-DB restore after any post-backup write). Whole-DB
   restore is snapshot-only and DISABLED for production.

## Unresolved blockers / needs GPT decision

- **B10-EXTENSION** (comma uuid -> `comma-uuid`): implemented, flagged
  in code; needs GPT confirmation.
- **O1 scope**: trojan grpc + ss non-AEAD not gated by O1 (documented
  above); extend-or-keep needs GPT confirmation (one-line change).
- **B1**: probe-side changes are NOT in this diff (the probe must send
  protocol/host/port for control members before receiver V3 can check
  them). B1 stays BLOCKED until the supported trusted process resolves it.
- **G6**: 21 pins' source groups are not established; the qualified
  control list starts empty and real READY stays BLOCKED — outside this
  diff's scope (integration-01's registry starts with Canada only).
- **N2 / N3** (blocklist backfill, SNI admission) belong to
  integration-03, not this diff.
- Test artifact (not a code issue): the P1 `pre_filter` checks use
  hostname hosts because `ipaddress` classifies the synthetic
  203.0.113.x TEST-NET addresses as private and `pre_filter` refuses
  them as `private-host` before reaching the transport/method checks.
  Documented in the test; production subscriptions carry public hosts.
