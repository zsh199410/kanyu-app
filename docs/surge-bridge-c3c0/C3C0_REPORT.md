# C3-C0 Report — Private Fix Alignment with PR #96 Reference (HEAD 7aba9184)

Date: 2026-11-19. Project: PR #96 / Issue #73, C3-C0 (code review + isolated
testing only). All work was done in isolation on this machine
(`~/workspace/pr96-c3c0/`); no phone contact, no production mailbox, no
GitHub posts, no changes under `/opt/surge-bridge/`. C3-C1 live deployment
is NOT AUTHORIZED by this task.

## Round 2 addendum (2026-11-19 — GPT receipt 7010810585, PR #97 review)

GPT reviewed the PR #97 package and found two P0 blockers plus two S3
design blockers. Round 2 fixes all of them in isolation; see
`C3C0_ROUND2_REPORT.md` for the full Round 2 record.

1. **CODE P0 — `saveLedger()` ignored `$persistentStore.write === false`.**
   Absorbed GPT's PR #99 fix verbatim into the private v2 (now v2.1, 530
   lines): `saveLedger` throws `durable_checkpoint_failed` unless the
   write returns exactly `true`. Cross-reviewed complete: it is the only
   ledger-persisting call and every caller already catches its throw and
   fails closed. The legacy `last_id` write was also checked: it does NOT
   need the throw guard (the ledger is the authoritative dedup state;
   dedup takes `max(floor, acked, legacy)`), but a `false` return is now
   recorded as a `store_write` phase via the new `writeLegacyLastId()`
   helper. Full diff: `C3C0_V2_V21_DIFF.md`.
2. **EVIDENCE P0 — the PR #97 package could not re-run independently.**
   `test_fixed_v2.js` depended on `./simulator` and
   `../pr96-c3b/bridge_fixed.js`, neither of which was submitted. Fixed:
   the v1 control is now packaged at `v1/bridge_fixed.js`, the suite
   loads it from `./v1/`, `test_store_failure.js` (PR #99, fetched from
   its branch) is included, and `ci/issue73-c3c0-v2.yml` runs all four
   suites. Clean-copy verification (fresh `/tmp/c3c0-clean-copy/`, no
   `pr96-c3b` dependency): all four suites pass.
3. **S3 DESIGN P0 — auto-eviction and "persist fails = rolled back" were
   unsafe (review comment 7010797396).** `ID_ALLOCATOR_DESIGN.md` Rev 1:
   §2.3 auto-eviction replaced by durable tombstones for the 7-day retry
   horizon, explicit 409 `retry_identity_unknown` for unknown/expired
   retry identities, and fail-closed 503 `history_full` when history is
   full; §2.7 "persist fails = rolled back" replaced by
   `commit_state: unknown` + durable reconciliation. Four new adversarial
   tests (S3-T11–T14) pass; the s3 suite is now 14/14.
4. **Simulator fix required by the PR #99 absorption.** The mock
   `$persistentStore.write` now returns `true` on success (real Surge
   semantics) and gains a `ledgerWriteFalseAfter` fault-injection mode.
   Without the `return true`, every `saveLedger` call would throw in the
   simulator (the mock previously returned `undefined`).

Round 2 results: v2 suite 28/0/1 (unchanged), store-failure 5/5,
s1 11/0/0, s3 14/14. Clean-copy: all four suites pass from a fresh
directory. `PUBLIC_SANITIZED_DIFF_COMMIT` is now Draft PR #97
(branch `c3c0-sanitized-v2-review`, head `a4df7b4` at submission, plus
the S1 Rev 1 follow-up commit); the Round 2 files are to be committed
to PR #97 as a further follow-up — see `C3C0_ROUND2_REPORT.md` for the
commit list with SHAs.

## Headline: v2 aligns the private phone script with the PR #96 reference

The C3-B private fix (v1, 109 → 369 lines) used `toSec()` for dedup and
fenced the old command only after the ledger bootstrap. GPT's PR #96
reference (HEAD `7aba9184`, `bridge_delivery_state.js`, 226 lines) fixes two
further defects in that approach:

1. **`toSec()` collapses distinct millisecond IDs in the same second.**
   Flooring two ms IDs issued within the same second to the same second value
   silently dedupes a genuinely newer command (test V8: cmd M+1 is blocked
   on v1 and dispatched on v2). v2 replaces `toSec()` with
   `orderMillis()` / `newerRawId()` / `validId()` — millisecond-precision
   canonical ordering for ALL comparisons, with raw IDs preserved on the
   wire, in the ledger, and in ACK matching.
2. **The fence must precede the ledger bootstrap.** A bootstrap that observed
   an empty mailbox must not make the inherited old command executable on the
   next cron tick. v2 moves the `FENCED_LEGACY_COMMAND_ID` exact-id check to
   IMMEDIATELY after poll, before any ledger load/bootstrap/reconciliation/
   dispatch, and adds the pre-stored `result_ready` guard so a cached result
   for the old id is never re-sent even when the mailbox is empty.

The PR #96 reference test suite was re-run locally against the saved HEAD:
**23/23 PASS**. The v2 phone script was then tested with an extended suite:
**28 PASS, 0 FAIL, 1 named LIMITATION** (frozen timers, see below).

## Source identity (verified this session)

| File | SHA-256 | Lines |
|---|---|---|
| PR #96 reference `bridge_delivery_state.js` (HEAD 7aba9184) | `3720594c8a6a48729420ab0e064a1751305cfe67dd1b6b82002a3b36c8d5b52e` | 226 |
| PR #96 reference `test_bridge_delivery_state.js` | `bd7f24da27c324f0e51f45880707b86c1dd8de4216d783b7c9c6a528d00d6850` | 269 |
| C3-B v1 `bridge_fixed.js` | `a056af65611588e1ef1ea1d5f89b2c9e0487ddbab0b6445b1e338b4964b43603` | 369 |
| **v2 `bridge_fixed_v2.js` (v2.1, Round 2)** | **`1658cea7ce6566e3a6703f4e962ac9fb37fd0a2b78d96661575a86d23f4f9c9a`** | **530** |
| v2 test suite `test_fixed_v2.js` (v2.1: packaged v1 path + exit-code gate) | `348a6eee47bfd6305f86d66714df2664cefd6ea78ea3b15fdf6e5986df9324eb` | — |
| `test_store_failure.js` (PR #99, fetched from its branch) | `24a20ea1a18a5bac0e2ee35965d08b1f93a6002e18a4f619abb426e3237efa68` | — |
| v1 control `v1/bridge_fixed.js` (packaged, desensitised) | `36388819a8a9971a3031ed462a5f2793c09af4b8d19ae5908f50aa7ae22b9e8d` | 374 |
| simulator (C3-B + Round 2 `return true` / `ledgerWriteFalseAfter`) | `f0ac1dab9c7be8fafb1d2425068e9b9145275a92fbb64fb50f632011b269b0ad` | — |
| CI `ci/issue73-c3c0-v2.yml` (runs all four suites) | see `C3C0_ROUND2_REPORT.md` | — |
| S3 design `ID_ALLOCATOR_DESIGN.md` (Rev 1) | `c72ef737b90dfb10e1d880451aef74d1a94cad3e9e2a20f3064817be59b1c5d2` | — |
| v2.0 → v2.1 diff `C3C0_V2_V21_DIFF.md` | `f7265de9cdfb3b39a9de60ef15eacbbac3af3ea5d2e3e28cf2fa0fdcd54b4ac6` | — |
| Original `bridge.js` (PR #85, desensitised) | `466cb56b5877bf2d1956833851540d6491c53b2e29a3ea5c53762049fddceb24` | 109 |

## C3-C0 acceptance fields

| Field | Result | Evidence |
|---|---|---|
| PRIVATE_PATCH_SHA | PASS | v2.1 script SHA `1658cea7…f4f9c9a` (530 lines; v2.0 was `b3c0b340…86135`, 506 lines). Test suite SHA `348a6eee…9324eb`. The desensitised v2.1 script, its v2.0 → v2.1 diff (`C3C0_V2_V21_DIFF.md`), and the full unified diff are in `C3C0_MINIMAL_PATCH_V2.md` (109 → 530 lines). |
| PUBLIC_SANITIZED_DIFF_COMMIT | **DONE — Draft PR #97** | Submitted by the parent agent: Draft PR #97 (branch `c3c0-sanitized-v2-review`, head `a4df7b4` at submission, 13 files, +3507/−0; v2 file SHA on the branch verified to match local v2.0 `b3c0b340…`). The S1 Rev 1 follow-up commit was added (head `a8f12cf`, 5 commits, 15 files). **Round 2 files are NOT yet committed** — they are listed with SHAs in `C3C0_ROUND2_REPORT.md` for the parent to commit as the next follow-up to PR #97. |
| WIRE_RAW_ID_PRESERVED | PASS | V24: seconds cmd id and ms cmd id are unchanged in the posted result, in the ledger `last_acked_id`, and in the legacy `last_id` write. V18/V4 confirm the same for the strict-ACK path. |
| ORDERING_CANONICAL_MS | PASS | V1–V8. All comparisons go through `orderMillis()` (ms precision); a seconds id converts by x1000, a ms id stays; non-safe-integer or overflow returns null and fails closed. |
| SAME_SECOND_MS_CASE | PASS | V1: ms id LEGACY_MS+1 dispatches. V2: LEGACY_MS-1 is deduped. V5: M+1 and M+2 (same second) both dispatch; an exactly equal id is deduped. V8: v1 blocks M+1 (toSec collision), v2 dispatches it. |
| ID_ALLOCATOR_UNIQUENESS | **DESIGN Rev 1 (server-side, not implemented)** | The parent agent verified read-only that the server does NOT generate command IDs: `/issue` accepts a caller-supplied id, `_valid_id` only checks `int` in `(0, 2^53-1]`, and `issue_if_empty`'s `command_id_not_increasing` check is a RAW numeric comparison (unit-blind, the same bug class as the original dedup). Two callers issuing seconds-precision IDs in the same second would collide; the server cannot guarantee uniqueness. **Rev 1 (Round 2, GPT review 7010797396 — addressed):** `ID_ALLOCATOR_DESIGN.md` §2.3 auto-eviction replaced by durable tombstones for the 7-day retry horizon, explicit 409 `retry_identity_unknown` for unknown/expired retry identities, and fail-closed 503 `history_full` when history is full; §2.7 "persist fails = rolled back" replaced by `commit_state: unknown` + durable reconciliation. Isolated tests 14/14 (S3-T11–T14 adversarial). Production implementation still needs a separate review. The phone script must not depend on server-side uniqueness: it fails closed on an exactly equal id (dedup) and never assumes two distinct ids are ordered by their raw value. |
| LEGACY_FLOOR_MIXED_UNIT_FIXED | PASS | V6: old 13-digit ms last + future 10-digit sec cmd dispatches (R0 regression). V3: a second id for a second containing a newer ms checkpoint is deduped. V4: mixed s/ms bidirectional ordering carries the raw id each time. |
| FENCE_INDEPENDENT_OF_LEDGER | PASS | V9: 23 rounds old cmd with NO ledger → fenced, ledger stays null, 0/0/0. V10: empty-mailbox bootstrap, then 23 rounds old cmd → all fenced, ledger unchanged, 0/0/0. V11/V12: pre-stored old `result_ready` (polled old cmd, and empty mailbox) → never re-sent, 0 sends. V13: first-migration fence — a synthetic pending cmd on first run is fenced, floor recorded, not executed. |
| PR85_NO_POST_REPLAY | PASS | V17: a timed-out mutating POST via `$httpAPI` is NOT retried via direct HTTP (`outcome_unknown_no_retry` in the outputs, 0 direct local POSTs). |
| PR96_DURABLE_ACK | PASS | V14/V15/V16: 503, 409, and ACK-loss each asserted separately — dispatch 1, result POSTs 2, `last_id` advanced only after ACK, cached result re-sent, no re-execution. V18: new synthetic GET-only exactly-once + strict ACK (200 + `accepted:true` + `acked_id === raw id`). |
| TRACE_NO_SECRETS | PASS | V21: phase records carry only `{phase, id, cat, tb}`; no URL/token/body in the phase log. Secret scan of all 8 deliverable files: CLEAN (see below). |
| PUBLIC_JS_SECRET_EXPOSURE | **EXPOSED=YES — C3-C1 BLOCKED until fixed** | The parent agent verified privately (anonymous fetch, no auth) that the public script URL returns HTTP 200 with the live bridge.js byte-for-byte (SHA matches), and that file contains long-lived credentials in plaintext. The URL, token, and key values are NOT included in any file here. Consequence: **C3-C1 is BLOCKED until the distribution fix and a rotation/isolation pass are complete.** A 200 status, a 0600 file permission, or an obscure URL does not make a secret safe once it is served anonymously. Required before C3-C1: (1) stop serving the credential-bearing script from an anonymously reachable URL (move to an authenticated / short-lived distribution path or inject credentials out-of-band at deploy time); (2) rotate the exposed long-lived DEV token and the local HTTP API key, and isolate the old values (revoke/rotate, verify the old values return 403); (3) re-verify by anonymous fetch that the new distribution path does not return credentials. |
| SCRIPT_LOADING_EVIDENCE_PLAN | DESIGN ONLY (see below) | No phone execution in this task. The plan covers two consecutive cron rounds, the phase trace as evidence, switches, max wait timing, log sources, trigger/cache paths, rollback, and fail-closed behaviour. |
| ROLLBACK_TEST | PASS | Isolated simulation (see below): rollback restores ONLY code; `state.json` SHA, `last_id`, pins, and timers are all unchanged. |
| RUNTIME_HARD_TIMEOUT_UNPROVEN | **LIMITATION (named)** | V23: `$httpClient` callback never returns with timers THROTTLED → still hangs, `$done` 0. A `Promise.race` + `setTimeout` guard is NOT a hard deadline when background timers are frozen; no JS-level guard can release the await. Only the Surge host cron timeout (120s) bounds it. Real device script logs are the final link to verify this later. The fix complies with the 120s host timeout and the exactly-once `$done` contract on every path where the script completes. |
| LIVE_UNCHANGED | PASS | Nothing under `/opt/surge-bridge/` was touched, nothing was posted to GitHub, nothing was sent to the phone or the production mailbox. 21 pins, 5 old timers, old node pool, STOP, and PR #93 are unchanged; PR #96 stays Draft. |

## v2 test results (28 PASS, 0 FAIL, 1 LIMITATION)

Suite: `test_fixed_v2.js`, output `test_fixed_v2_out.json`. All commands are
synthetic (ids 2000000001, 1795064000, ms variants), except the fence tests
which MUST use the inherited old id 1795063030 and the real ms last_id
1795055213880 (both public, GitHub #73). The v1 suite was re-run as a
control and still passes (24/0/2).

| ID | Check | Result |
|---|---|---|
| V1 | Same-second +1ms id dispatches (LEGACY_MS+1) | PASS |
| V2 | Same-second -1ms id is deduped (LEGACY_MS-1) | PASS |
| V3 | Second id floor(LEGACY_MS/1000) deduped | PASS |
| V4 | Mixed s/ms bidirectional; last_acked_id carries the raw id each time | PASS |
| V5 | Equal-value collision: M+1, M+2 both dispatch; exactly equal id deduped | PASS |
| V6 | Old 13-digit ms last + future 10-digit sec cmd dispatches (R0 regression) | PASS |
| V7 | Non-safe-integer legacy id fails closed (no action, no poll) | PASS |
| V8 | v1 toSec() bug: M+1 blocked on v1, dispatched on v2 | PASS |
| V9 | Fence before bootstrap: 23 rounds old cmd, NO ledger → fenced, ledger null | PASS |
| V10 | Empty-mailbox first init, then 23 rounds old cmd → all fenced, ledger unchanged | PASS |
| V11 | Pre-stored old result_ready + old cmd polled → never re-sent | PASS |
| V12 | Pre-stored old result_ready + empty mailbox → never re-sent | PASS |
| V13 | First-migration fence: synthetic pending cmd on first run fenced, floor recorded | PASS |
| V14 | Result POST 503 → cached, run 2 re-sends cached (no re-execution) | PASS |
| V15 | Result POST 409 → cached, run 2 re-sends cached (no re-execution) | PASS |
| V16 | ACK loss → cached, run 2 re-sends cached, duplicate ACK | PASS |
| V17 | PR#85 outcome_unknown_no_retry preserved | PASS |
| V18 | New synthetic GET-only → exactly-once + strict ACK | PASS |
| V19a–e | Exception in any stage → visible phase + $done exactly once (store read, poll parse, action throw, checkpoint throw, result POST throw) | PASS (5) |
| V20 | Late callback after terminal → dropped, 0 extra write/send | PASS |
| V21 | Phase trace: all 9 required phases in order, clean keys, no secrets | PASS |
| V22 | $httpClient callback never returns, timers NORMAL → guard releases, $done 1 | PASS |
| V23 | $httpClient callback never returns, timers THROTTLED → still hangs | LIMITATION (`RUNTIME_HARD_TIMEOUT_UNPROVEN`) |
| V24 | Raw IDs preserved on the wire (sec and ms), in the ledger, and in legacy last_id | PASS |
| V25 | Mock state isolation (no leakage between runs) | PASS |

## ROLLBACK_TEST (isolated simulation, PASS)

Procedure (script `rollback_test.sh`, re-runnable in isolation; it uses only
a temp dir, never `/opt/surge-bridge/`):

1. Build a simulated production tree: `bridge.js` (v2), `bridge.sgmodule`,
   `server.py`, and `state.json` (last result id 1795055213880, pins,
   timers). Record the SHA of `state.json`, the `last_id`, the pins, and the
   timers. Keep a backup of the pre-v2 code files.
2. Rollback: copy ONLY the backed-up code files (`bridge.js`, module,
   `server.py`) back into place. No step writes `state.json`, `last_id`,
   pins, or timers. There is no "backfill old state" step.
3. Verify: `state.json` SHA unchanged, `last_id` unchanged
   (1795055213880), pins unchanged, timers unchanged; only the code SHA
   changed.

Observed result: `state.json` SHA unchanged: YES; `last_id` unchanged: YES;
pins unchanged: YES; timers unchanged: YES; code restored: YES.
**ROLLBACK_TEST: PASS.**

Production rollback (when C3-C1 is eventually approved) follows the same
rule: restore ONLY code from the pre-deployment backup; never write, restore,
or backfill `state.json` or `sgbridge_last_id`. If the ledger
(`sgbridge_ledger_v1`) was created by v2, leave it in place — it is
forward-compatible (version 1, raw ids) and a rollback of the code does not
require deleting it; deleting it would lose the `result_ready` cache and the
fence floor. The old command stays `OUTCOME_UNKNOWN` through any rollback.

## SCRIPT_LOADING_EVIDENCE_PLAN (design only — nothing executed on the phone)

First phone load of the v2 script, in observation/isolation mode. This plan
is a design for the parent agent and GPT to approve; no step here touches
the phone.

**Goal.** Prove, from the phone itself, that the new script (new SHA) loaded
and that two consecutive cron rounds show
`cron_enter → poll → old_cmd_fenced → done_once`, with zero actions, zero
`/result` POSTs, and zero `last_id` writes. VPS `/poll` 200 alone is
insufficient: it only proves a GET reached the server, not that the phone
processed the response or ran the new code.

**Preconditions.** (1) The desensitised v2 diff is reviewed and the Draft PR
is approved for a controlled load. (2) The public-script credential exposure
is fixed and the long-lived tokens are rotated/isolated (see
PUBLIC_JS_SECRET_EXPOSURE). (3) A backup of the current live `bridge.js`,
module, `server.py`, and the semantic content of `state.json` exists, and the
rollback procedure above is ready. (4) The old command 1795063030 is still
pending and `OUTCOME_UNKNOWN`; the 5 timers and 21 pins are unchanged.

**Trigger / cache update path.** The owner updates the phone's Surge module
(or the cron script reference) to the new script location/SHA through the
approved C3-C1 step. Surge downloads the new script on the next cron tick
(or immediately on a manual script reload). The old script stays cached until
the new one loads; the load is confirmed by the phase trace (below), not by
assuming the download happened.

**Observation (two consecutive cron rounds).** After the load, observe two
consecutive 10-minute cron rounds. Expected evidence per round, read from the
phone:
- Phase trace (persisted in `$persistentStore` under the phase key, read via
  a limited diagnostic that posts ONLY `{phase, id, cat, tb}` records to the
  `/diagnostic` endpoint — never a body, token, or URI):
  `cron_enter → poll_http_done → cmd_parsed → legacy_fenced →
  dedup_decision → done_or_catch`, with `$done` exactly once.
- Zero dispatches, zero `/result` POSTs, zero `last_id` writes.
- VPS corroboration: `/poll` 200 each round, zero `/result` POSTs, and
  `state.json` cmd/result unchanged. This corroborates but does not replace
  the phone phase trace.

**Log sources.** (1) The phone phase trace (primary — proves the new code
ran and fenced). (2) The VPS nginx log (`/poll` 200, no `/result`).
(3) The VPS `state.json` (cmd/result unchanged). (4) The phone Surge
logbook, if accessible, as a secondary check. No packet capture is required
and no repeated manual phone runs are requested.

**Switches.** (1) The module/script URL can be reverted to the previous SHA
at any time — this is the kill switch; the old script loads on the next cron
tick. (2) The cron itself can be disabled from the Surge app if the new
script misbehaves. (3) There is no remote kill switch inside the script;
stopping it is done by reverting the distribution URL.

**Max wait timing.** Two cron rounds = up to 20 minutes after the load,
plus up to 10 minutes for the first post-load tick. If no phase trace
matching the expected sequence is observed within 30 minutes of the load,
treat the load as unconfirmed, revert to the previous SHA, and fail closed
(no command execution, no `/result`, no `last_id` write).

**Rollback steps.** (1) Revert the module/script URL to the previous SHA.
(2) Confirm on the next cron tick that the old script is running again (the
phase trace returns to the old behaviour: poll + clean dedup exit). (3)
Verify `state.json`, `last_id`, pins, and timers are unchanged (same rule as
ROLLBACK_TEST: restore code only, never backfill state). (4) Keep the old
command `OUTCOME_UNKNOWN` and fenced.

**Fail-closed behaviour.** If the new script fails to load, throws, or
produces a phase trace that does not match the expected sequence, the phone
must not execute any command, must not POST any `/result`, and must not write
any `last_id`. The old command stays fenced and `OUTCOME_UNKNOWN`. Any
configuration change in this plan must not affect the Surge proxy policy or
the 5 existing timers.

**What this plan does NOT authorise.** It does not authorise executing the
old command, clearing the single-slot mailbox, issuing a new command via
`/issue` to overwrite the old slot, or opening GET-only execution for new
IDs. Those need a separate review of the old single-slot
preservation/isolation/reconciliation plan.

## What changed relative to v1 (summary)

- `toSec()` → `orderMillis()` / `newerRawId()` / `validId()` (ms-precision
  canonical ordering; raw ids preserved). V8 demonstrates the fix.
- Fence moved to immediately after poll, before any ledger load/bootstrap.
- Bootstrap floor via `newerRawId(observed, legacyId)`; a synthetic pending
  cmd on first run is fenced, never executed.
- Full `saneState()` ledger validation (corrupt ledger fails closed).
- Pre-stored old `result_ready` never re-sent, independent of the polled cmd.
- Result payload `{id, timestamp, outputs}` (matches the reference).
- `PENDING_ID_MISMATCH` and `OUTCOME_UNKNOWN` fail closed (no receipt
  lookup on the phone).
- Legacy `last_id` validated; a non-safe-integer fails closed.
- Full detail: `C3C0_MINIMAL_PATCH_V2.md`.

## Simulator notes

Two C3-B simulator behaviours were relied on and re-verified (no new
simulator bugs were found in this round): the mock `setTimeout` scales all
timers by 0.01 (so production 35s/15s/100s guards become 350ms/150ms/1000ms
in tests — the source timeouts are NOT scaled, avoiding the double-scaling
bug caught in C3-B), and `runSeries`/`runScript` with a shared store/mailbox
reuses live state across rounds (the v2 suite manages this explicitly via
`bootstrapShared` / `round` / `seededShared` helpers).

## Secret scan

All 8 deliverable files were scanned for the real DEV token, the real API
key, real URLs, and real node URIs (patterns built from the private copy,
values never printed): `bridge_fixed_v2.js`, `test_fixed_v2.js`,
`test_fixed_v2_out.json`, `simulator.js`, `C3C0_MINIMAL_PATCH_V2.md`,
`rollback_test.sh`, `v2_vs_orig.diff`, `v2_vs_orig_clean.diff` — **ALL CLEAN**.
Placeholders only (`<BRIDGE_BASE>`, `<DEV_TOKEN>`, `<API_KEY>`). The public
command ids 1795063030 / 1795055213880 appear (they are already public on
GitHub #73) and are not secrets.

## Deliverables (all under `~/workspace/pr96-c3c0/`)

- [bridge_fixed_v2.js](sandbox://workspace/pr96-c3c0/bridge_fixed_v2.js) — v2.1 fixed script (desensitised, 530 lines, SHA `1658cea7…f4f9c9a`)
- [test_fixed_v2.js](sandbox://workspace/pr96-c3c0/test_fixed_v2.js) — v2 regression suite (29 checks; packaged v1 path + exit-code gate)
- [test_fixed_v2_out.json](sandbox://workspace/pr96-c3c0/test_fixed_v2_out.json) — v2 results (28 PASS, 0 FAIL, 1 LIMITATION)
- [test_store_failure.js](sandbox://workspace/pr96-c3c0/test_store_failure.js) — PR #99 durable-store injections (5/5, fetched from its branch)
- [C3C0_MINIMAL_PATCH_V2.md](sandbox://workspace/pr96-c3c0/C3C0_MINIMAL_PATCH_V2.md) — desensitised unified diff v2 vs original (109 → 530 lines) + v1→v2 change list + v2.1 addendum
- [C3C0_V2_V21_DIFF.md](sandbox://workspace/pr96-c3c0/C3C0_V2_V21_DIFF.md) — desensitised v2.0 → v2.1 diff (PR #99 absorption + legacy-write check)
- [C3C0_ROUND2_REPORT.md](sandbox://workspace/pr96-c3c0/C3C0_ROUND2_REPORT.md) — Round 2 report (PR #99 absorption, package completion, S3 Rev 1, clean-copy verification)
- [C3C0_REPORT.md](sandbox://workspace/pr96-c3c0/C3C0_REPORT.md) — this report
- [simulator.js](sandbox://workspace/pr96-c3c0/simulator.js) — isolated Surge mock (C3-B + Round 2 `return true` / `ledgerWriteFalseAfter`)
- [v1/bridge_fixed.js](sandbox://workspace/pr96-c3c0/v1/bridge_fixed.js) — v1 control script (packaged, desensitised, 374 lines)
- [ci/issue73-c3c0-v2.yml](sandbox://workspace/pr96-c3c0/ci/issue73-c3c0-v2.yml) — CI workflow (syntax check + all four suites)
- [rollback_test.sh](sandbox://workspace/pr96-c3c0/rollback_test.sh) — isolated rollback simulation (PASS)
- [pr96-head-7aba9184/bridge_delivery_state.js](sandbox://workspace/pr96-c3c0/pr96-head-7aba9184/bridge_delivery_state.js) — PR #96 reference (HEAD 7aba9184, as received)
- [pr96-head-7aba9184/test_bridge_delivery_state.js](sandbox://workspace/pr96-c3c0/pr96-head-7aba9184/test_bridge_delivery_state.js) — PR #96 reference tests (23/23 PASS locally)

## Notes for the parent agent / GPT

- **Round 2 files to commit to PR #97 (the open item from this task).**
  The parent must commit the Round 2 files listed with SHAs in
  `C3C0_ROUND2_REPORT.md` as the next follow-up to Draft PR #97
  (branch `c3c0-sanitized-v2-review`). The package then re-runs
  independently (clean-copy verified) and the CI workflow
  `ci/issue73-c3c0-v2.yml` runs all four suites on the branch.
- **PUBLIC_JS_SECRET_EXPOSURE = YES blocks C3-C1.** Do not load the v2
  script from the current anonymously reachable distribution path, and do
  not treat a new script SHA as a fix for the exposure. Rotation/isolation
  of the exposed long-lived credentials must pass first.
- **ID_ALLOCATOR_UNIQUENESS is a server-side design (Rev 1).** The
  allocator is a draft with 14/14 isolated tests; production
  implementation needs a separate review. The phone script must not
  depend on server-side uniqueness.
- The frozen-timer case remains `RUNTIME_HARD_TIMEOUT_UNPROVEN` (V23). Only
  real device script logs can confirm whether it ever occurs on the phone.
- The old command 1795063030 stays `OUTCOME_UNKNOWN` and is permanently
  fenced in v2. C3-C1 remains NOT AUTHORIZED; PR #93 stays BLOCKED.

## Round 3 addendum (2026-11-19): PR #100 absorbed → v2.2

- v2.2 SHA `8691e962cba4ab40e961702b7d30090aaaedc29fdbe46b63a257878f9f90abfc`
  (571 lines). GPT Draft PR #100 (S1 secret-free credential adapter) applied
  verbatim via `git apply` (zero conflicts; base SHAs matched exactly).
  `DEV`/`APIKEY` are now read at runtime from `$persistentStore`
  (`sgbridge_cred_dev` / `sgbridge_cred_localkey`); missing DEV fails closed
  (zero network/action/result); 403 fails closed with no fallback to old
  credentials; missing local key blocks localhost HTTP/MCP.
- Five suites against v2.2: v2 regression 28/0/1, store-failure 5/5,
  S1 live adapter 10/10 (new), S1 11/11, S3 14/14. Clean-copy verification
  PASS (23 files, fresh directory). Bootstrap design + 7/7 isolated tests
  (`BOOTSTRAP_DESIGN.md`, `s1/bootstrap.js`, `s1/bootstrap_test.js`).
- Full record: `C3C0_ROUND3_REPORT.md`. Desensitised v2.1→v2.2 diff:
  `C3C0_V2_V22_DIFF.md`.
- Gates unchanged: `CREDENTIAL_DISTRIBUTION_GATE=BLOCKED`, `C3-C1=NO-GO`,
  `PR93_CUTOVER=BLOCKED`, old command 1795063030 `OUTCOME_UNKNOWN`.

---

## Addendum — Round 3 continued (2026-11-19, PR #101 absorbed)

- **PR #101 absorbed:** GPT's Shortcuts candidate bootstrap
  (`gpt6-issue73-s1-shortcuts-bootstrap-20261119`, head `2e6c44d`,
  4 commits, +236/−0, 3 files, Draft). Template
  `bootstrap_candidate_shortcuts.template.js` (SHA `6bfa8838…ca7591`),
  test `test_bootstrap_candidate_shortcuts.js` (SHA `5bde1810…8931b56`),
  workflow `ci/issue73-s1-shortcuts-bootstrap.yml` (SHA `950e9602…499331`)
  — all byte-identical to PR #101's files (verified by diff
  reconstruction + SHA comparison against GitHub raw files).
- **Cross-review:** all checks PASS (trigger rejection, validation,
  occupied-slot, fail-closed writes, no leak path, no touch of active
  token/ledger/last_id/old slot/timers/policies, CI). Minor notes:
  no dedicated test for `$intent === null`/`undefined` with trigger
  intent; production token format vs the 32–256 printable-ASCII window
  still to confirm; template does not reject `<...>` placeholders
  (bounded: bridge fails closed); `ACTIVE_KEY` declared but unused;
  no approved bootstrap path for the local key yet.
- **Bootstrap design corrected (Rev 2):** Rev 1's paste-into-source +
  delete-the-script approach is **DEPRECATED and wrong** — Surge caches
  script source and retains logs, the manual gives no wipe guarantee
  on deletion, and `$persistentStore` keys are cross-script
  accessible. `s1/bootstrap.js` kept as a record only (DEPRECATED
  header added); `s1/bootstrap_test.js` 7/7 is a logic record of the
  superseded approach, not an endorsement. Recommended path is now
  PR #101: Shortcuts intent parameter at run time, candidate staged
  under `sgbridge_cred_dev_candidate`, active token untouched,
  promotion a separate approved gate. 12 open device-side items
  (Shortcuts input history, iOS backup, script cache leakage,
  device-side log check, other scripts' permissions, candidate key
  visibility, token format window, local-key path, promotion gate,
  gate 2 server change, real-device staging run, real-device loading +
  two cron cycles) — none verified.
- **Tests:** seven suites, **88 PASS / 0 FAIL / 1 LIMITATION**
  (v2 28/0/1, store 5/5, S1 live 10/10, S1 11/11, S3 14/14,
  bootstrap-deprecated 7/7, bootstrap candidate 13/13); rollback
  PASS; clean-copy verification PASS
  (`/tmp/c3c0-clean-copy-r3b/`).
- **v2.2 unchanged:** 571 lines, SHA `8691e962…abfc`.
- **Note on GPT receipt 7012275778:** it cites PR #97 head `13abefec` /
  22 files — that is **stale**; PR #97 is at head `4ef98d4`
  (12 commits, 31 files) after the Round 3 commit, both CIs green on
  that head. The head is not regressed.
- Full record: `C3C0_ROUND3B_REPORT.md`. Design: `BOOTSTRAP_DESIGN.md`
  (Rev 2, SHA `3b188e24…e149b`).
- Gates unchanged: `CREDENTIAL_DISTRIBUTION_GATE=BLOCKED`, `C3-C1=NO-GO`,
  `PR93_CUTOVER=BLOCKED`, old command 1795063030 `OUTCOME_UNKNOWN`.

## Addendum — Round 3C (2026-11-19, GPT P0-B1/B2/B3, review 7012623369)

- **GPT's three P0 findings on the committed bootstrap artifacts:**
  (B1) the deprecated `s1/bootstrap.js` embeds literal credentials in
  script source; manual deletion is not evidence the source bytes are
  absent from caches/sync/backups/logs, so "token only goes into
  `$persistentStore`" / "never written to any file except
  `$persistentStore`" are **not established**; (B2) the deprecated
  script writes the two active keys separately (partial update
  possible) and ignores a `false` return on the done-marker write, so
  it can emit `bootstrap_ok` without a durable marker; (B3) it writes
  straight to the active keys, bypassing the candidate→proof→promotion
  gate. Also: the bootstrap 7/7 was isolated-only — neither PR #97
  workflow ran `s1/bootstrap_test.js`.
- **P0-B1 fix:** `BOOTSTRAP_DESIGN.md` Rev 2.1 addendum (§9.1) quotes
  and **withdraws both statements explicitly**. The defect is proven,
  not just asserted: regression file D1/D2 (below) run the deprecated
  script's real logic and show the defect.
- **P0-B2 fix:** new `test_bootstrap_candidate_regressions.js`
  (14/14). D1 proves the deprecated script leaves a partial
  active-key update (DEV changed, local key old, failure reported);
  D2 proves it emits `bootstrap_ok` with no durable done marker.
  R1–R6 prove the new candidate-staging approach has no such defect:
  (a) independence — zero writes to either active key in both
  directions; (b) local-key write-then-false → unknown, 1 write, no
  retry; (c) both status writes false → no candidate rewrite,
  candidates on disk, statuses absent (not misreported as staged);
  (d) preloaded active keys unchanged; (e) ambiguous commit then a
  different candidate → `candidate_slot_occupied`, original preserved;
  (f) no token in logs/source/status on all paths. No two-key atomic
  write BY DESIGN — staging never touches active keys. Never assume
  an exception proves storage did not commit (both write-false
  flavours tested).
- **P0-B3 fix:** Rev 2.1 addendum §9.3 states it explicitly —
  staging writes ONLY candidate keys; promotion is a separate approved
  gate; no phone provisioning, no public script change, no server
  token enablement, no credential revocation until explicit approval.
- **Local-key candidate template (new):**
  `bootstrap_candidate_localkey.template.js` stages the local key
  under `sgbridge_cred_localkey_candidate` via the same
  intent-parameter mechanism (status
  `sgbridge_cred_localkey_bootstrap_status`). Tests L1–L5 in the
  regression file cover valid staging, occupied/idempotent,
  status-marker failure, write-false without persisting, and the
  ambiguous-commit retry.
- **CI coverage (evidence gap):** the S1 adapter workflow
  (`.github/workflows/issue73-c3c0-s1-adapter.yml`) now runs ALL
  bootstrap suites (`s1/bootstrap_test.js`,
  `test_bootstrap_candidate_shortcuts.js`,
  `test_bootstrap_candidate_regressions.js`) with a nonzero-failure
  gate (verified by a forced-failure negative control, exit 1). The
  `docs/surge-bridge-c3c0/**` path filter already covers every file,
  so no filter change was needed. Note: the 7/7 bootstrap result is
  isolated-only until this updated workflow runs on the new PR #97
  head.
- **Tests:** nine suites, **102 PASS / 0 FAIL / 1 LIMITATION**
  (v2 28/0/1, store 5/5, S1 live 10/10, S1 11/11, S3 14/14,
  bootstrap-deprecated 7/7, bootstrap candidate 13/13, candidate
  regressions 14/14); rollback PASS; clean-copy verification PASS
  (`/tmp/c3c0-clean-copy-r3c/`).
- **v2.2 unchanged:** 571 lines, SHA `8691e962…abfc`.
- Full record: `C3C0_ROUND3C_REPORT.md`. Design: `BOOTSTRAP_DESIGN.md`
  (Rev 2 + Rev 2.1 addendum).
- Gates unchanged: `CREDENTIAL_DISTRIBUTION_GATE=BLOCKED`, `C3-C1=NO-GO`,
  `PR93_CUTOVER=BLOCKED`, old command 1795063030 `OUTCOME_UNKNOWN`.

## Round 4 (P0 fast-track) addendum — 2026-11-19 23:xx CST
- **Owner priority (GPT receipt 7013674858):** "抓紧上线、以最快可用版本为先"
  — first complete the C3-C1 Bridge stable launch P0 gates; P2/P3 node
  auto-isolation/deletion only as offline designs; do not delay P0 for
  new features; do not open AUTO_DELETE early.
- **PR #102 absorbed (hermetic rollback):** GPT's rewrite of
  `rollback_test.sh` (head `d0ce8f94`, base PR #97 head `225d8dc`, CI
  runs 44555342039 / 44555341540 / 44555341842 all success) is
  byte-identical to the diff reconstruction (SHA `5a92efec…102ae6`) and
  copied unmodified, plus its CI workflow
  (`issue73-c3c0-hermetic-rollback.yml`, SHA `5e6fe7dd…302b7`). The old
  version depended on private paths
  `~/workspace/pr96-c3c0/bridge_fixed_v2.js` and
  `/tmp/bridge_orig_desens.txt`; the new version sources v2.2 and v1
  ONLY from the checkout, uses `mktemp -d` + `trap EXIT` cleanup,
  `set -euo pipefail`. Local runs: positive PASS (exit 0); negative
  control `--inject-state-change` FAIL as expected (exit 1,
  `state.json altered`). New version contains no private paths.
- **Item 1 — credential provisioning on device:** standalone executable
  `provisioning_demo.js` runs the two PR #101 candidate templates for
  real (vm sandbox, synthetic tokens): Shortcuts intent parameter →
  candidate staging (DEV + local key, independent) → verification
  (candidates present, active keys unchanged, status markers) → the
  13 items still unverified on the real device (logs, Shortcuts
  history, cross-script access, iOS backup, script cache, device-side
  log check, other scripts' permissions, candidate key visibility,
  token format window, promotion gate, server dual-token revocation,
  real-device staging run, real-device loading + two cron cycles).
  Prints only status enums/booleans, never a token or digest.
  `test_provisioning_demo.js` spawns the demo and asserts on its real
  output: **5/5 PASS** (exit 0, both staged, active unchanged,
  unverified list present, no secret in any output).
- **Item 2 — staging-to-active promotion gate:**
  `PROMOTION_GATE_DESIGN.md` + `promotion_gate.js` +
  `test_promotion_gate.js` (**17/17 PASS**). Promotion only when all
  six conditions hold: (a) candidate exists and validates
  (readCredential rules + 32–256 printable-ASCII window); (b)
  `/credential-proof` present (fingerprint only, never the token;
  ok, fingerprint_matches, token_id ≠ old id, issued within 24h);
  (c) active still the old one (already-promoted is an idempotent
  no-op; absent active fails closed); (d) write new active, read-back
  verify, only then clear the candidate — any failure before
  verification leaves active unchanged and candidate intact;
  (e) old exposed token never re-enabled (rollback = new backup token
  or fail-closed); (f) old command 1795063030 never touched (gate has
  no code path to the mailbox). Two findings: a clear failure AFTER
  the verified active write does NOT roll back (safer than rolling
  back a verified promotion; retry converges to already-promoted);
  `$persistentStore` has NO documented delete, so the sample clears
  via `remove()` when available and otherwise writes the tombstone
  `"__PROMOTED__"` (can never validate as a candidate; occupies the
  slot until a separate approved device-side action clears it).
- **Item 3 — server dual-token and revocation:**
  `DUAL_TOKEN_DESIGN.md` + `dual_token_server.js` +
  `test_dual_token.js` (**12/12 PASS**). Table stores FINGERPRINTS
  (SHA-256 hex), never token values; append-only audit (revocation is
  a status change, never a delete); two active rows during a bounded
  window (48h upper bound per S1 Rev 1); bridge accepts either during
  the window; old token → 403 after revocation (bridge 403 gate fails
  closed, no fallback); 401 = missing/unknown token, 403 = revoked or
  expired; expiry fails closed (old token 403 `window_expired` even
  without explicit revocation); rollback = NEW backup token, never
  the old exposed one (refused by the sample); revocation/expiry/
  rollback never touch the old command id. One test bug caught and
  fixed during the run (the "fingerprints only" assertion wrongly
  included the non-secret row IDs); the sample code was not changed.
- **CI:** new workflow `issue73-c3c0-round4.yml` runs syntax checks +
  the three new test files with a nonzero-failure gate. The hermetic
  rollback has its own workflow from PR #102.
- **Tests:** twelve suites, **136 PASS / 0 FAIL / 1 LIMITATION**
  (v2 28/0/1, store 5/5, S1 live 10/10, S1 11/11, S3 14/14,
  bootstrap-deprecated 7/7, bootstrap candidate 13/13, candidate
  regressions 14/14, rollback positive PASS + negative control FAIL
  as expected, provisioning demo 5/5, promotion gate 17/17, dual
  token 12/12); clean-copy verification PASS
  (`/tmp/c3c0-clean-copy-r4/`, 42 files).
- **Blockers (4) and (5) NOT built:** real-device release proof and
  the release checklist / prod rollback need real-device gates and
  explicit owner permission. P2/P3 node auto-isolation/deletion NOT
  opened.
- **v2.2 unchanged:** 571 lines, SHA `8691e962…abfc`.
- Full record: `C3C0_ROUND4_REPORT.md`.
- Gates unchanged: `CREDENTIAL_DISTRIBUTION_GATE=BLOCKED`,
  `BOOTSTRAP_SECURITY_GATE=BLOCKED`, `C3-C1=NO-GO`,
  `PR93_CUTOVER=BLOCKED`, old command 1795063030 `OUTCOME_UNKNOWN`.
