# C3-C0 Round 2 Report — PR #99 Absorption, Package Completion, S3 Rev 1

Date: 2026-11-19. Project: PR #96 / Issue #73, C3-C0 Round 2.
Trigger: GPT receipt 7010810585 (PR #97 review) + S3 addendum review
comment 7010797396.

Scope: DESIGN + isolated verification + private-script work only. No live
files touched (`/opt/surge-bridge/`), no credential revoked or rotated, no
GitHub posts, no phone contact, no production mailbox contact. C3-C1 live
deployment is NOT AUTHORIZED by this task. PR #93 stays BLOCKED. Old
command 1795063030 stays OUTCOME_UNKNOWN and fenced.

## Headline

All three GPT P0 blockers are fixed and verified in isolation:

1. **CODE P0** — v2 `saveLedger()` ignored `$persistentStore.write === false`.
   PR #99's fix absorbed verbatim into the private v2 (now v2.1).
2. **EVIDENCE P0** — the PR #97 package could not re-run independently
   (`test_fixed_v2.js` depended on `./simulator` and
   `../pr96-c3b/bridge_fixed.js`, neither submitted). The package is now
   complete: v1 control packaged, store-failure test included, CI added,
   clean-copy verified.
3. **S3 DESIGN P0** — auto-eviction of idempotency keys and "persist fails
   = rolled back" were unsafe. `ID_ALLOCATOR_DESIGN.md` Rev 1 replaces
   both with durable tombstones + explicit rejection + fail-closed 503,
   and `commit_state: unknown` + durable reconciliation. Four new
   adversarial tests pass.

Results: v2 suite **28 PASS / 0 FAIL / 1 LIMITATION** (unchanged),
store-failure **5/5**, s1 **11/0/0**, s3 **14/14**. Clean-copy: all four
suites pass from a fresh directory with no `pr96-c3b` dependency.

## 1. PR #99 absorption (v2.0 → v2.1)

### What GPT's PR #99 fixed

PR #99 (branch `gpt6-issue73-fix-durable-store-false-20261119`, head
`41cfb22a`, base `c3c0-sanitized-v2-review`, CI success) fixes a real bug
in the v2 script: `saveLedger()` called `$persistentStore.write(...)`
and ignored its return value. Surge's `$persistentStore.write` returns
`true` only on a successful write; returning `false` is NOT an exception.
Without the check, an action could run while `in_progress` was never
persisted, or a receipt could be POSTed while `result_ready` was never
persisted. PR #99 also adds `test_store_failure.js` (5 self-contained
cases that run the ACTUAL v2 script in a vm with mocked
`$persistentStore` / `$httpClient` / `$notification` / `$done`) and a CI
workflow `.github/workflows/issue73-c3c0-v2-storage.yml`.

### Cross-review of the fix

The fix is correct and complete for `saveLedger`:

- `saveLedger` is the ONLY ledger-persisting call in the script. Every
  caller already catches its throw and fails closed:
  claim → `ledger_write` phase, checkpoint → `checkpoint_failed`,
  bootstrap → `ledger_bootstrap_failed`, ack-clear → `ledger_write`.
  No caller assumes `saveLedger` succeeds.
- The fix changes no control flow other than turning a silently ignored
  `false` into the same `durable_checkpoint_failed` throw that a
  `saneState` failure already produces. All existing v2 tests still
  pass (28/0/1).
- `test_store_failure.js` was fetched from PR #99's branch via the
  GitHub API (SHA `24a20ea1…efa68`) and run UNMODIFIED against the fixed
  private v2: **5/5 PASS**.

### Control run (the test catches the bug)

The same `test_store_failure.js` was run against the UNFIXED v2.0
(reconstructed by reverting only the `saveLedger` fix in a temp copy):
it FAILS on the first case — `false return on in_progress blocks
dispatch` — with `dispatches=1` where 0 is required (the action was
dispatched even though the `in_progress` checkpoint write returned
`false`). Exit code 1. This proves the test is sensitive to the bug and
the fix is what makes it pass.

### Legacy last_id write path — checked

Two sites write the legacy `sgbridge_last_id` checkpoint:
`resendCached()` and the ACK path. Neither needs the `saveLedger` throw
guard, because:

- The ledger (floor / `last_acked_id`) is the authoritative dedup state,
  persisted via the now-guarded `saveLedger`; dedup takes
  `max(floor, acked, legacy)`, so a stale legacy value cannot cause a
  re-dispatch of an ACKed command.
- In `resendCached()` the legacy write is reached only AFTER `saveLedger`
  persisted the cleared pending + updated `last_acked_id`.
- In the ACK path the `saveLedger` that follows persists `last_acked_id`;
  if it throws, the result stays cached and is re-sent next run, never
  re-executed.

Both sites now call the new `writeLegacyLastId()` helper, which records a
`false` return as a `store_write` phase (same as a thrown write) without
changing control flow — so a failed legacy write is no longer silently
swallowed. This is a v2.1 addition beyond PR #99, documented in
`C3C0_V2_V21_DIFF.md`.

### Simulator fix required by the absorption

The mock `$persistentStore.write` in `simulator.js` previously returned
`undefined` (no return statement). With the PR #99 fix, `saveLedger`
throws unless the write returns exactly `true`, so the whole v2 suite
would have failed in the simulator. The mock now returns `true` on
success (matching real Surge semantics) and gains a
`ledgerWriteFalseAfter` fault-injection mode mirroring
`ledgerWriteFailAfter`. This is a mock-fidelity fix, not a script change.

### New v2 SHA

- v2.0 (PR #97 head `a4df7b4`): 506 lines,
  SHA-256 `b3c0b34045d8b4cecbc86b1ae39ff8e7a778091f8aa45733592e704697986135`
  (verified against the PR #97 branch copy before diffing).
- v2.1 (Round 2): 530 lines,
  SHA-256 `1658cea7ce6566e3a6703f4e962ac9fb37fd0a2b78d96661575a86d23f4f9c9a`.
- Full desensitised diff: `C3C0_V2_V21_DIFF.md`.

## 2. Package completion (EVIDENCE P0)

The PR #97 package now re-runs independently from a clean checkout:

| Item | Status |
|---|---|
| `simulator.js` | Included; verified desensitised (no real token/key/URL/IP). Mock `write` now returns `true` on success + `ledgerWriteFalseAfter` mode. |
| v1 control `v1/bridge_fixed.js` | Copied from `../pr96-c3b/bridge_fixed.js`, verified desensitised (placeholders only, no real-token hits), with a package header note. 374 lines. |
| `test_fixed_v2.js` require path | Changed from `../pr96-c3b/bridge_fixed.js` to `./v1/bridge_fixed.js`. Also added the missing exit-code gate: `FAIL > 0` now sets `process.exitCode = 1` (previously a failed check still exited 0, which would have passed CI silently). |
| `test_store_failure.js` | Included, fetched unmodified from PR #99's branch. |
| CI `ci/issue73-c3c0-v2.yml` | New. Modelled on GPT's PR #99 workflow, extended to the full set: syntax-checks all 7 `.js` files, then runs `test_fixed_v2.js`, `test_store_failure.js`, `s1/test_s1.js`, `s3/test_s3.js`. Every suite exits non-zero on any FAIL. To be committed to `.github/workflows/issue73-c3c0-v2.yml` on the branch. |

### Clean-copy verification

The entire submission set (21 files) was copied to a fresh
`/tmp/c3c0-clean-copy/` directory (no `pr96-c3b` directory present) and
all suites were run from there:

- Syntax check: all 7 `.js` files pass `node --check`.
- `test_fixed_v2.js`: 28 PASS / 0 FAIL / 1 LIMITATION, exit 0.
- `test_store_failure.js`: 5 PASS / 0 FAIL, exit 0.
- `s1/test_s1.js`: 11/11, exit 0.
- `s3/test_s3.js`: 14/14, exit 0.
- No `../pr96-c3b` require remains (the only occurrences are comments
  stating there is no such dependency).

**Clean-copy verification: PASS.** The package re-runs independently.

## 3. S3 design Rev 1 (review comment 7010797396)

### §2.3 — idempotency eviction replaced

- **Before:** keep at most the last 100 keys (or last 24h), evict the
  oldest first; a retry with an evicted key was treated as a new request.
  **Unsafe:** after a delayed client retry and an empty single-slot
  mailbox, the same non-idempotent POST/PUT/DELETE could be issued again
  with a new id and performed twice. A high-water id prevents numeric
  collision, not business-level replay.
- **After:** durable request-key tombstones
  `{ id, issued_at_ms, status, action_hash }` retained for the supported
  retry horizon `RETRY_HORIZON_MS = 7 days` (must be at least as long as
  the longest supported client retry window; the bridge's operational
  retry window is minutes to hours). The map is also bounded by count
  (`MAX_TOMBSTONES = 10000`). When full, allocation FAILS CLOSED with
  503 `history_full` — never silently evicts and reissues. A full history
  is an operator event (archive / extend), not a reason to replay.
- **Unknown / expired retry identities explicitly rejected:** a request
  marked `retry: true` whose key is NOT in the tombstone store returns
  409 `retry_identity_unknown` — no allocation, no execution. A first
  attempt with an unknown key is a new request and is allocated normally.

### §2.7 — persist failure is commit_state = unknown

- **Before:** "persist fails → allocation rolled back in memory, command
  not stored." **Wrong:** filesystem sync/rename may succeed *before*
  persist reports an exception (PR#96 `server_http_commit.py`
  documents this), so a 503 never proves the command is absent.
- **After:** a persist exception means `commit_state: "unknown"`. The
  allocator does NOT roll back in memory and does NOT assume the command
  is absent. The transaction is marked unknown and must be **reconciled**
  before any further allocation: re-read the durable state; if it
  contains the command (same idempotency key / same id), return that id;
  if it is readable and contains no such command, the original
  transaction is provably absent and a new allocation may proceed; if it
  is unreadable or corrupt, fail closed with 503 and stay unknown.
  **A retry with a DIFFERENT idempotency key must not create another
  action until this reconciliation proves the previous transaction's
  outcome with durable server-side proof.**

### New adversarial tests (S3-T11–T14, all PASS)

| ID | Check | Result |
|---|---|---|
| S3-T11 | Evicted/expired-key retry explicitly rejected (409), never re-executed — never-issued key and archived tombstone | PASS |
| S3-T12 | History full fails closed (503 `history_full`), never silently evicts and reissues | PASS |
| S3-T13 | Persist error leaves `commit_state: unknown`; retry with a DIFFERENT key creates no second action (reconciliation finds the durably stored command and returns its id) | PASS |
| S3-T14 | Persist error + unreadable durable state fails closed (503), stays unknown | PASS |

The s3 suite is now **14/14** (10 original + 4 new). `s3/README.md`
updated to match Rev 1.

## 4. Test results (all suites, this round)

| Suite | Result | Output |
|---|---|---|
| v2 regressions `test_fixed_v2.js` | 28 PASS / 0 FAIL / 1 LIMITATION | `test_fixed_v2_out.json` |
| Store failure `test_store_failure.js` | 5 PASS / 0 FAIL | stdout (no output file; PR #99's script prints SUMMARY) |
| S1 secret-free distribution `s1/test_s1.js` | 11 PASS / 0 FAIL / 0 LIMITATION | `s1/s1_out.json` |
| S3 ID allocator `s3/test_s3.js` | 14 PASS / 0 FAIL / 0 LIMITATION | `s3/s3_out.json` |
| Clean-copy (fresh dir, all four suites) | PASS (28/0/1 + 5/5 + 11/11 + 14/14) | `/tmp/c3c0-clean-copy/` (ephemeral) |
| Control: store-failure vs UNFIXED v2.0 | 1/5 FAIL (expected — proves the test catches the bug) | `/tmp/v2-unfixed-control/` (ephemeral) |

The 1 LIMITATION is the standing `RUNTIME_HARD_TIMEOUT_UNPROVEN`
(V23, frozen timers) — unchanged from v2.0, and only real device script
logs can resolve it.

## 5. PR #99 absorption note

- Applied: the `saveLedger` fix, verbatim logic (capture the return,
  throw `durable_checkpoint_failed` unless exactly `true`), with a
  comment citing PR #99.
- Cross-reviewed: correct and complete for `saveLedger` (only
  ledger-persisting call; all callers already fail closed on its throw).
- Checked: the legacy `last_id` write path (2 sites). No throw guard
  needed (ledger is authoritative; dedup takes the max); a `false`
  return is now recorded as a `store_write` phase via `writeLegacyLastId()`.
- NOT applied from PR #99: nothing else. PR #99's `test_store_failure.js`
  was fetched unmodified; its CI workflow was used as the model (not
  copied verbatim) for the full-suite workflow `ci/issue73-c3c0-v2.yml`.
- GPT's PR #98 (S3 oracle, 28/28) is INDEPENDENT and was not touched;
  its 28/28 is not conflated with Muse's S3 14/14.

## 6. Files to commit to PR #97 (with SHAs)

Branch: `c3c0-sanitized-v2-review` (Draft PR #97). Target paths are
under `docs/surge-bridge-c3c0/` unless noted. Files already on PR #97
are listed as UPDATED; new files as NEW.

| Target path | Local file | SHA-256 | Status |
|---|---|---|---|
| `docs/surge-bridge-c3c0/bridge_fixed_v2.js` | `bridge_fixed_v2.js` | `1658cea7ce6566e3a6703f4e962ac9fb37fd0a2b78d96661575a86d23f4f9c9a` | UPDATED (v2.0 → v2.1) |
| `docs/surge-bridge-c3c0/test_fixed_v2.js` | `test_fixed_v2.js` | `348a6eee47bfd6305f86d66714df2664cefd6ea78ea3b15fdf6e5986df9324eb` | UPDATED (packaged v1 path + exit-code gate) |
| `docs/surge-bridge-c3c0/test_fixed_v2_out.json` | `test_fixed_v2_out.json` | `25c15fd096c9f00a7b81b7c5b6b09d8addabfb9000879ec90c187fe098633434` | UPDATED (regenerated) |
| `docs/surge-bridge-c3c0/test_store_failure.js` | `test_store_failure.js` | `24a20ea1a18a5bac0e2ee35965d08b1f93a6002e18a4f619abb426e3237efa68` | NEW (PR #99, unmodified) |
| `docs/surge-bridge-c3c0/simulator.js` | `simulator.js` | `f0ac1dab9c7be8fafb1d2425068e9b9145275a92fbb64fb50f632011b269b0ad` | UPDATED (`return true` + `ledgerWriteFalseAfter`) |
| `docs/surge-bridge-c3c0/v1/bridge_fixed.js` | `v1/bridge_fixed.js` | `36388819a8a9971a3031ed462a5f2793c09af4b8d19ae5908f50aa7ae22b9e8d` | NEW (v1 control, packaged) |
| `docs/surge-bridge-c3c0/s1/test_s1.js` | `s1/test_s1.js` | `f98506b5c98447f07bb214171a051cc9f86a6445dbb591209a5effc72e7334d7` | UNCHANGED (already on PR #97, Rev 1) |
| `docs/surge-bridge-c3c0/s1/s1_out.json` | `s1/s1_out.json` | `afe89e5724feb4082e6ab51088b1331c795730bc601ebe0fa3a984df8d0ea767` | UNCHANGED |
| `docs/surge-bridge-c3c0/s1/README.md` | `s1/README.md` | `28680742da09d09f7ea8e7eea748216b74849cee1adc523f02338457250311ca` | UNCHANGED |
| `docs/surge-bridge-c3c0/s3/test_s3.js` | `s3/test_s3.js` | `f890812d4f896caedf63015242b66cb19bc1517f68df14edf3427c687ce7e501` | UPDATED (Rev 1, 14 tests) |
| `docs/surge-bridge-c3c0/s3/s3_out.json` | `s3/s3_out.json` | `6bbf67eff4d3b445dd9227d74b3a2390921a24dd663e2c9903f87dbd64f44183` | UPDATED (regenerated) |
| `docs/surge-bridge-c3c0/s3/README.md` | `s3/README.md` | `2e94d3404874b31ca573536a0557ee4167579269ccaaedbfbfdff77c818ad9fb` | UPDATED (Rev 1) |
| `docs/surge-bridge-c3c0/C3C0_MINIMAL_PATCH_V2.md` | `C3C0_MINIMAL_PATCH_V2.md` | `a327886af9711d1b1e6eac0ea9156e0b9bc4245802c346c3748b1d88ed966756` | UPDATED (v2.1 addendum) |
| `docs/surge-bridge-c3c0/C3C0_REPORT.md` | `C3C0_REPORT.md` | `5d9c69c61ea84d5d1e9b4661f270b4b99f33c9b7e9d67ae80302046832cc501d` | UPDATED (Round 2 addendum + fields) |
| `docs/surge-bridge-c3c0/C3C0_V2_V21_DIFF.md` | `C3C0_V2_V21_DIFF.md` | `f7265de9cdfb3b39a9de60ef15eacbbac3af3ea5d2e3e28cf2fa0fdcd54b4ac6` | NEW |
| `docs/surge-bridge-c3c0/ID_ALLOCATOR_DESIGN.md` | `ID_ALLOCATOR_DESIGN.md` | `c72ef737b90dfb10e1d880451aef74d1a94cad3e9e2a20f3064817be59b1c5d2` | UPDATED (Rev 1, §2.3/§2.7) |
| `docs/surge-bridge-c3c0/C3C0_ROUND2_REPORT.md` | `C3C0_ROUND2_REPORT.md` | (self-referential — recompute with `sha256sum` at commit time) | NEW |
| `.github/workflows/issue73-c3c0-v2.yml` | `ci/issue73-c3c0-v2.yml` | `d6ae5ffbc0e9734b59d5a759cea6948e4fe8c5da6330e2209b398f149236ce2a` | NEW |
| `docs/surge-bridge-c3c0/rollback_test.sh` | `rollback_test.sh` | `d72a6efc4da1fb16dc29c669765ed167951095de529a3d2faeb336f663153a65` | UNCHANGED |

Notes:
- `SECURITY_GATE_PLAN.md` and `SECURITY_GATE_PLAN_REV1.md` are
  UNCHANGED in Round 2 (S1 Rev 1 already addresses GPT's 5 S1 findings
  and is on PR #97). They are not re-listed here.
- `C3C0_S1_S3_SUMMARY.md` is UNCHANGED in Round 2.
- `v2_vs_orig.diff` / `v2_vs_orig_clean.diff` (v2.0 artifacts) are
  superseded by `C3C0_V2_V21_DIFF.md` for the v2.0 → v2.1 change; the
  full original → v2.1 diff is in `C3C0_MINIMAL_PATCH_V2.md`.

## 7. Secret scan

All new/changed files were scanned for the real DEV token, the real API
key, real URLs, real node URIs, and the real script/module paths
(patterns built programmatically from the private token file and the
server config; values never printed): `bridge_fixed_v2.js`,
`test_fixed_v2.js`, `test_store_failure.js`, `simulator.js`,
`v1/bridge_fixed.js`, `s1/test_s1.js`, `s3/test_s3.js`,
`C3C0_MINIMAL_PATCH_V2.md`, `C3C0_REPORT.md`, `C3C0_V2_V21_DIFF.md`,
`ID_ALLOCATOR_DESIGN.md`, `ci/issue73-c3c0-v2.yml` — **ALL CLEAN**
(0 matches). Placeholders only (`<BRIDGE_BASE>`, `<DEV_TOKEN>`,
`<API_KEY>`). The public command ids 1795063030 / 1795055213880 appear
(they are already public on GitHub #73) and are not secrets. The
`127.0.0.1:6171` loopback address appears (local Surge HTTP API, not a
secret) and is already in the reviewable v2 script.

## 8. Gates (unchanged)

- `CREDENTIAL_DISTRIBUTION_GATE=BLOCKED`; `C3-C1=NO-GO`;
  `PR93_CUTOVER=BLOCKED`; old command 1795063030 `OUTCOME_UNKNOWN`.
- `RUNTIME_HARD_TIMEOUT_UNPROVEN` remains the single named limitation
  (V23, frozen timers); only real device script logs can resolve it.
- Nothing live was touched. No GitHub post was made by this task; the
  parent commits the files above to PR #97.
