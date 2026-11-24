# Integration-02: source hook / normalization / latest-batch binding

[Draft] #73 follow-up to PR #125 (v4 frozen, HEAD `b10670d7`) and PR #126
(integration-01, control contract). Implements GPT ruling 7120382777,
second-stage item 2: **source hook / normalization / latest-batch
binding**. Isolated diff package + isolation tests only. No production
deployment, no live-file change, no unit change, no key created.

**v2 update (GPT 7121245603, 2026-11-24 11:35:52):** B10-EXTENSION
confirmed and extended with a UUID format check; O1 extended from a
vmess-net whitelist to the full protocol / transport / encryption
support matrix (16 rows); the gate's vmess-net reason string aligned
to live `pre_filter` / tester vocabulary (`unsupported-transport`).
See "v2 changes" below. v1 Parts 1–9 re-run green; Parts 10–13 are
new.

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
  **B10-EXTENSION (CONFIRMED by GPT 7121245603, v2):** a comma in a
  vmess uuid corrupts `username=` the same way (comma-split Surge
  params) — `comma-uuid` retained. **New in v2:** the uuid must also
  be a legal UUID in the standard 8-4-4-4-12 hex shape
  (`is_valid_uuid`, shape-only; version/variant nibbles not policed);
  a malformed uuid is refused from publish as `invalid-uuid`, in both
  `pre_filter` and `build_surge_line`. Comma takes precedence over
  format (v1 behaviour); missing uuid is `missing-uuid`. Neither
  check truncates, replaces or rewrites the credential, and no
  credential is ever recorded. Live prevalence re-measured in v2
  (see below): uuids valid / invalid / missing / comma, line and
  triple level.
- **O1 — protocol / transport / encryption support matrix (v2).**
  The v1 vmess-net whitelist is extended to the full matrix
  (`SUPPORT_MATRIX`, 16 rows) in `lineage_adapter.admission_gate`:
  vmess (net tcp/ws/empty + TLS + security in the tester-verifiable
  set auto/aes-128-gcm/chacha20-poly1305/none + uuid present), trojan
  (t_type tcp/ws/empty + password present), ss (AEAD method + no
  plugin + password present); unknown protocols fail closed.
  Each combination is judged leg by leg (parser / tester / Surge):
  trojan grpc is refused because the Surge line silently drops
  `t_type` AND the tester refuses it; ss non-AEAD is refused because
  the tester will not verify it (the Surge line itself can carry the
  method losslessly — the break is at the tester, not the name);
  vmess non-TLS is refused the same way (Surge expresses it, the
  tester refuses it). **Scope decision reversed by GPT 7121245603:**
  trojan grpc and ss non-AEAD ARE now gated (they were explicitly
  not gated in v1). Rejected rows go to the isolation audit
  (`skipped.<reason>` with the offending value as detail, except
  ss-plugin whose detail is the fixed marker `present`) and get no
  lineage row; they are NOT deleted — raw source counts stay as the
  audit population. B10 never gates lineage: a comma-password /
  comma-uuid / invalid-uuid node still gets lineage.
  **Reason vocabulary aligned (v2):** the gate's vmess-net reason is
  now `unsupported-transport`, the string live `pre_filter` and the
  tester both already use for a bad vmess net (v1's `unsupported-net`
  is retired); the check order (tls before net before uuid) already
  mirrored `pre_filter` and is unchanged. Live impact re-measured
  in v2 (see below): gate-admitted vs rejected, line and triple
  level, plus the v1-to-v2 delta.
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

## Diff size (vs live, 2026-11-24 12:xx CST; plain `diff` added/removed lines)

| file | change |
| --- | --- |
| `pool/crawler.py` | +17 / −2 (optional `on_observation` param + hook call; unchanged from v1) |
| `pool/cli.py` | +46 / −3 (lineage wiring, `--no-lineage`, lineage summary in `counts`; byte-identical to v1) |
| `pool/rules.py` | +51 / −4 (B10 `comma-password`, B10-EXTENSION `comma-uuid` + v2 `invalid-uuid` format check; v2 adds 31 lines vs v1) |
| `pool/lineage_adapter.py` | new, 508 lines (canonical_config, admission_gate + 16-row SUPPORT_MATRIX, LineageRecorder, registry, build_lineage_recorder; v2 adds 183 lines vs v1's 350) |
| `pool/source_lineage.py`, `pool/migrate_node_sources.py` | v4 verbatim (SHA-verified: `f6038da1…` / `0dbef378…`; not present in live) |
| `pool/db.py`, `publish.py`, `tester.py`, `geo.py`, `__init__.py` | live verbatim (SHA-verified: `1cfcc76e…` / `c63ed14b…` / `e012ff36…` / `9558c319…`) |
| `source_groups.json` | new, 33 lines (R1 registry: 3 groups, 10 sources, paused = chenzhihan-base64 + matin-ss; byte-identical to v1) |
| `tests/` | 7 scripts (see below) |

Total package: 20 files (v1: 18 files; v2 adds `test-i02-v2.py` +
`live-prevalence-v2.py`).

## Isolation tests (all green, 2026-11-24 ~12:40 CST)

Run from `tests/` (PR layout) or from the workspace harness — the
scripts resolve both layouts. Synthetic TEST-NET identities and test
keys only; live DB never written; live pool never touched.

- `tests/test-i02-v2.py` — **133 checks, 0 failed** (regression +
  Parts 10–13; run this one script to re-verify everything):
  - REG: v1 Parts 1–7 / Part 8 / Part 9 re-run as subprocesses, all
    rc=0 (Part 8 against the FRESH v2 snapshot, 2026-11-24 12:36,
    7798 nodes — not the v1 snapshot).
  - P10 UUID format matrix: 5 valid shapes pass `pre_filter` +
    `build_surge_line`; 13 malformed shapes (empty, not-a-uuid,
    short/long last group, missing dash, non-hex, too short,
    extra group, underscores, leading/trailing space, no dashes,
    braces) all `invalid-uuid` in both gates; non-string input
    cannot raise; comma beats format; missing beats format;
    version/variant nibbles are NOT policed (shape-only).
  - P11 support matrix completeness: all 16 matrix rows asserted
    against `admission_gate` (37 cases: every admitted row, every
    rejected row, every security value, every net value, unknown
    protocols); row count is 16; every row reason is in
    `GATE_REASONS` and every `GATE_REASONS` member appears in the
    matrix; admitted rows carry no reason. Precedence (multi-defect
    records mirror `pre_filter` order): tls beats net, net beats
    uuid, malformed uuid is NOT a gate reason (B10 gates publish
    only) — a malformed-uuid + bad-security record reports
    `unsupported-security`, and a malformed uuid alone is admitted.
  - P12 round-trip negatives (where exactly the chain breaks):
    trojan grpc loses `t_type` in the Surge line (returns tcp);
    vmess grpc / httpupgrade lose `net` (returns tcp); vmess
    security non-`auto` diverges ONLY on `security` (D2-accepted)
    while the tester preserves it, and unknown/uppercase security
    folds to `auto` in the tester; ss non-AEAD round-trips
    losslessly in TEXT (the line carries `encrypt-method`) — the
    break is at the tester, which refuses to verify it; ss plugin
    is dropped by the line AND refused by the tester; vmess non-TLS
    round-trips cleanly (Surge expresses it) — the break is at the
    tester. Positive controls (trojan ws, vmess ws auto tls, ss
    aes-256-gcm) round-trip cleanly.
  - P13 `no_module` TRIGGERED in isolation (v1: wired but untested):
    a copy of `pool/` with `lineage_adapter.py` deleted, run as a
    real `pool.cli crawl` subprocess against a synthetic base with
    the HMAC key set: lineage disabled with reason `no_module`,
    crawl still succeeds (unique=7), 7 nodes, NO lineage tables,
    run logged; the key never appears in crawl output. **All five
    fail-closed forms are now covered: no_key, --no-lineage,
    no_registry, schema_not_migrated (v1), no_module (v2).**
- `tests/test-i02-source-hook.py` — **152 checks, 0 failed** (Parts 1–7,
  v1 was 116; v2 adds 36):
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
  - P4 O1 support matrix (v2, was net whitelist): trojan grpc and
    ss-rc4-md5 are now GATED by the matrix (`unsupported-transport`,
    `ss-method`); vmess non-TLS, unknown security, uppercase
    security, ss plugin, missing uuid/password, unknown protocol all
    gated; B10 credentials still get lineage (gate admits comma /
    malformed uuids and comma passwords — publish refuses them).
  - P5 B10 + UUID format (v2): comma passwords refused by
    `pre_filter` + `build_surge_line` for trojan and ss (with and
    without a space); comma uuid refused (extension); 3 valid UUID
    shapes pass, 8 malformed shapes refused as `invalid-uuid` in
    both gates; comma beats format, missing beats format; lineage
    still records a comma-password node (B10 gates publish, not
    lineage).
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
  the FRESH production snapshot, 2026-11-24 12:36, 7798 nodes,
  node_tests 248974 — same counts as v1's 11:15 snapshot):
  `--check` is read-only (digest unchanged, `would_backfill_rows` 7798);
  migrate backfills 7798; after three post-backup write kinds
  (node_tests row, sighting event, status-log entry) `--rollback
  --backup` returns mode `retained`, `whole_db_restore: refused`,
  file digest byte-identical; (a) no further lineage calls + 2 s
  window stable, (b) counts identical, (c) liveness query + lineage
  query + `integrity_check ok`; zero-write whole-DB restore works on
  a SECOND copy only (snapshot-only; **production use DISABLED by
  GPT**); `--allow-data-loss` rejected (exit 2); `--rollback` without
  `--backup` rejected (exit 2). Also re-run on the v1 snapshot in
  the earlier v2 pass — same result.
- `tests/test-i02-perf.py` — **PASSED** (Part 9): 2000 synthetic lines
  (4 sources x 500) through the real `crawl_records` + recorder path
  in 178.3 ms, **89.2 ms / 1000 observations**, 0 errors (v1: 79.8
  and 92.5 on two runs — same range). No tuned threshold; the only
  bound is a 60 s sanity cap.
- `tests/live-prevalence.py`, `tests/live-prevalence-lines.py` —
  read-only live probes (v1 numbers, see below); `tests/live-prevalence-v2.py` —
  the v2 probe (gate + pre_filter + UUID format on live data).

## Live prevalence re-measured in v2 (2026-11-24 ~12:53 CST)

`tests/live-prevalence-v2.py` (VPS, read-only; live crawler parses,
v2 gate / pre_filter / UUID check classify). Two populations, labelled
so the numbers are not mixed up. The v1 numbers below are kept for
reference; the v2 numbers are the current ones.

- **Line level:** 9321 lines; 82 unparsed/other (vless 2665 / ssr 22 /
  hy2 177 / hysteria2 10); parsed 6365 (trojan 1064 / vmess 3645 /
  ss 1656). **Gate v2: admitted 3833** (60.2%), rejected 2532:
  `vmess-non-tls` 2166, `ss-method` 285, `unsupported-transport` 81
  (53 vmess bad net + 28 trojan bad t_type, one reason string since
  the v2 alignment). **Pre-filter v2: admitted 3761**, rejected:
  `vmess-non-tls` 2163, `ss-method` 285, `invalid-uuid` 72,
  `unsupported-transport` 81, `private-host` 3. **v1→v2 delta:
  2271 lines newly excluded from lineage** (`vmess-non-tls` 1958,
  `ss-method` 285, `unsupported-transport` 28 trojan-only — vmess net
  was already excluded in v1). Rejected rows are audit-only, NOT
  deleted; raw source counts stay.
- **Deduped-triple level (union 4023):** gate admitted **2442**
  (60.7%), rejected 1581 (`vmess-non-tls` 1350, `ss-method` 187,
  `unsupported-transport` 44); pre-filter admitted 2394; v1→v2 delta
  **1446** (`vmess-non-tls` 1244, `ss-method` 187,
  `unsupported-transport` 15).
- **UUID format (v2, NEW):** line level valid **3555** / invalid
  **90** / missing 0 / comma 0 (of 3645 vmess lines); triple level
  valid 2302 / invalid 63. The 90 invalid vs pre-filter's 72 is
  exact, not a miscount: pre_filter checks TLS before UUID, so 18
  invalid-uuid lines are reported as `vmess-non-tls` first (verified
  by a targeted re-count: 72 invalid-uuid + 18 vmess-non-tls + 0
  other = 90). Comma uuids still 0; comma passwords still 0/6365.
- **vmess security:** non-`auto` **34/3645** line level (auto 3611 /
  chacha20-poly1305 4 / none 16 / aes-128-gcm 14), 24/2365 triple
  level (same as v1 — the population is unchanged).
- **vmess net:** ws 2317 / tcp 1067 / httpupgrade 51 / grpc 38 /
  raw 55 / http 85 / xhttp 23 / none 4 / h2 2 / `tcp,udp` 1 /
  fragment junk 2; bad net 261/3645 (7.2%, same as v1).
  vmess TLS 1479 / non-TLS 2166. **ss-method 285 = aes-128-cfb 30 +
  aes-256-cfb 172 + rc4-md5 81 + chacha20-poly1305 2** (the non-IETF
  variant is not in live `AEAD_METHODS` — sing-box only supports
  `chacha20-ietf-poly1305`; the arithmetic closes exactly).
  Trojan t_type tcp 811 / ws 225 / grpc 26 / httpupgrade 2.
  ss plugin **0/1656** (0/1114 triple level).
- **Source overlap (unchanged from v1):** chenzhihan-base64 x
  chenzhihan-v2ray **375/375 identical**; alirewa-sub1 46/46, sub2
  47/47, sub3 13/13 contained in alirewa-config; au1rxx x chenzhihan
  **174/269 = 65%**; matin's three subscriptions share **0** triples
  with each other. Union triples 4023.
- **Live DB (read-only, re-verified this round):** nodes 7798,
  node_tests 248974 at snapshot time (249777 at the later live-state
  check — normal hourly test growth, not this diff),
  `disabled_sources = []`, 10 sources all reachable.
  **Formal pool unchanged: 22 lines, SHA
  `9e44841b177bb40463afb15f27fe2c801c9657257f463289dcea5f8051a1ebd4`,
  HTTPS 200 (re-checked after all v2 tests).**

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

- **B10-EXTENSION — RESOLVED by GPT 7121245603 (v2).** `comma-uuid`
  retained; UUID format check (`invalid-uuid`, 8-4-4-4-12 hex shape)
  added in `pre_filter` + `build_surge_line`. No truncation, no
  rewrite, no credential recorded.
- **O1 scope — RESOLVED by GPT 7121245603 (v2).** Full 16-row support
  matrix; trojan grpc + ss non-AEAD now gated; unknown fail-closed.
  The gate's vmess-net reason was aligned to live vocabulary
  (`unsupported-transport`, was `unsupported-net` in v1) so gate /
  pre_filter / tester audit logs join on one string; check order
  (tls before net before uuid) already mirrored `pre_filter`.
- **Normalization divergences (observation, not a blocker).** The
  gate lowercases trojan `t_type` and ss `method` before checking
  while live `pre_filter` compares them case-sensitively, and the
  gate does not `.strip()` vmess `net` while `pre_filter` does — so
  a mixed-case / whitespace-padded value can be gate-admitted but
  publish-refused (lineage records a real config that can never
  publish; not wrong, but the two gates can disagree on the same
  line). Left as-is in v2; needs a GPT call only if the project
  wants the two gates byte-identical on normalization.
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
