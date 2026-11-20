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

## Round 5 addendum — PR #103 signed proof (2026-11-20)

- **Trigger:** GPT comment 7024105041 (C3-C1 POST-DEVICE-ACCEPTANCE
  SECURITY GATE). Owner reported "真机验收通过" in chat
  (`DEVICE_ACCEPTANCE=USER_REPORTED`), but #73 has no desensitized
  device evidence record, so `DEVICE_EVIDENCE_CORRELATION=OPEN`.
- **PR #103 absorbed byte-identical** (head
  `4ebac06a55f759fa4b7e747390cbe9df9943a427`, stacked on PR #97 head
  `13e55c0`, 8 commits, +352/−43, 6 files; `git apply`
  reconstruction == API fetch for all six files):
  `promotion_gate.js` (`b12545be…67b9b90`),
  `signed_promotion_proof.js` (`69d3f2fe…a2145`),
  `test_promotion_gate.js` (`ef5579e2…e9364`),
  `test_signed_promotion_proof.js` (`7d0c9981…438f5`),
  `PROMOTION_GATE_DESIGN.md` (`8dfd60d4…600797`, before Rev 3),
  workflow `issue73-round4-signed-proof.yml` (`8e80f5bc…6459c`).
- **The fix:** the old `validProof()` trusted any passed
  `{fingerprint_matches:true, ok:true}` without authenticating the
  issuer, signature, or candidate fingerprint. The signed reference
  requires a pinned Ed25519 public key, an Ed25519 signature over
  the canonical proof (fixed domain `purpose/kind`), SHA-256 of the
  ACTUAL candidate, token id ≠ old exposed id, a single-use
  expected nonce, 24h issuance / 5-min skew / signed expiry. The
  no-candidate success path based on the old `promotion_done`
  status is removed. Old unsigned path verified GONE by grep.
- **Rev 3 withdrawal (verbatim, WITHDRAWN):** W1 unsigned
  `/credential-proof` contract; W2 "active value definitely
  unchanged on failure"; W3 status-only idempotence shortcut. New
  design doc SHA `a586c99e…70a82d6a` (365 lines).
- **Device evidence:** `DEVICE_EVIDENCE_ALIGNMENT.md` (NEW) — 15-row
  checklist/template (test time, running script SHA, Surge/iOS
  versions, two cron cycles, old-ID fence, logs/Shortcuts privacy
  checks, pins/timers, scope). ALL rows UNVERIFIED; nothing
  invented. Record stays OPEN.
- **CI:** GPT's `issue73-round4-signed-proof.yml` absorbed unchanged
  (17 reference + 15 adversarial). New `issue73-c3c0-round5.yml`
  runs the 5-case negative control. Note: the PR #103 workflow
  step name says "14 adversarial cases" but the file contains 15
  tests (SUMMARY 15 PASS) — label off by one, test file
  authoritative.
- **Tests:** fourteen suites, **156 PASS / 0 FAIL / 1 LIMITATION**
  (v2 28/0/1, store 5/5, S1 live 10/10, S1 11/11, S3 14/14,
  bootstrap-deprecated 7/7, bootstrap candidate 13/13, candidate
  regressions 14/14, rollback positive PASS + negative control FAIL
  as expected, provisioning demo 5/5, promotion gate signed-proof
  17/17, signed-proof adversarial 15/15, negative control 5/5,
  dual token 12/12); clean-copy verification PASS
  (`/tmp/c3c0-clean-copy-r5/`, 51 files).
- **v2.2 unchanged:** 571 lines, SHA `8691e962…abfc`.
- Full record: `C3C0_ROUND5_REPORT.md`.
- Gates unchanged: `CREDENTIAL_DISTRIBUTION_GATE=BLOCKED`,
  `BOOTSTRAP_SECURITY_GATE=BLOCKED`, `C3-C1=NO-GO`,
  `PR93_CUTOVER=BLOCKED`, `DEVICE_EVIDENCE_CORRELATION=OPEN`,
  `DEVICE_ACCEPTANCE=USER_REPORTED`,
  `RELEASE_EVIDENCE_NOT_YET_COMPLETE`, old command 1795063030
  `OUTCOME_UNKNOWN`. The signed-proof reference is Node-only:
  Surge/iOS `crypto` support UNPROVEN, no production pinned key,
  no real signed `/credential-proof`, no durable nonce replay
  rejection, no real server token-table persistence yet. P2/P3 NOT
  opened.

## Round 6 addendum (2026-11-20) — PR #104/#105 WebView crypto cross-review

- **Trigger:** GPT comment 7024399594 (2026-11-20 06:49 CST).
  GPT directly submitted two isolated Draft PRs at the owner's
  request to "continue the task": PR #104 (WebView crypto
  capability probe, head `44ad192`, 6 commits, 4 files,
  +415/−0) and PR #105 (WebView signed-proof verifier
  library, head `09db336`, 4 commits, 4 files, +400/−0).
  Neither modified Muse's branch, main, the real device,
  the production VPS, tokens, mailbox state, or the node
  pool.
- **Absorption:** all 8 files byte-identical (git-apply
  reconstruction == GitHub API fetch). Probe template SHA
  `6b76f8ef…5eb4`, probe test SHA `fa275f32…4501`,
  verifier SHA `02b18dbd…3bfe`, verifier test SHA
  `21118d7d…8c8c`. Head CIs re-verified via check-runs API:
  PR #104 head 3/3 success, PR #105 head 3/3 success.
- **Cross-review:** RFC 8032 §7.1 vector #1 independently
  verified with Node `crypto` (valid verifies, tampered
  rejected, SHA-256(empty) and TextEncoder "abc" match);
  canonical JSON field order byte-identical to PR #103
  `payload()` (source inspection + the test's direct
  equality assertion); probe has 0 network / device-control
  / credential-key references, editor/intent-only trigger
  gate, `$done` exactly once; verifier has 0 `require(`,
  0 device-control APIs, all bindings present
  (candidate / expectedNonce / pinned key / old token id /
  purpose-kind / issuance-expiry / fingerprint /
  signature), 14 fail-closed returns. Test counts match:
  18 probe, 19 verifier.
- **Named finding F1 (minor, coverage gap, GPT's files
  unchanged):** the PR #104 probe does not check `atob`
  availability, but the PR #105 verifier requires `atob`
  and fails closed without it — so a `crypto_ready`
  result does not guarantee the verifier can run. Fix is
  for GPT to decide.
- **Tests:** probe 18/18, verifier 19/0/1 (named replay
  limitation), new replay negative control 4/0/1 (same
  proof passes twice with reused nonce — documented
  limitation, not a verifier failure; rejected with a
  different nonce or candidate). Seventeen suites total:
  **197 PASS / 0 FAIL / 1 LIMITATION**; clean-copy PASS
  (`/tmp/c3c0-clean-copy-r6/`, 63 files).
- **Device evidence scope note:** the owner's reported
  device acceptance covers the NODE POOL only (chat
  clarification "节点池"); it does NOT cover
  Ed25519/WebCrypto support, the two cron fence
  verifications, or the logs/Shortcuts privacy check. All
  15 rows remain UNVERIFIED.
  `DEVICE_EVIDENCE_CORRELATION=OPEN`.
- **v2.2 unchanged:** 571 lines, SHA `8691e962…abfc`.
- Full record: `C3C0_ROUND6_REPORT.md`.
- Gates unchanged: `CREDENTIAL_DISTRIBUTION_GATE=BLOCKED`,
  `BOOTSTRAP_SECURITY_GATE=BLOCKED`, `C3-C1=NO-GO`,
  `PR93_CUTOVER=BLOCKED`, `AUTO_DELETE=OFF`,
  `DEVICE_EVIDENCE_CORRELATION=OPEN`,
  `DEVICE_ACCEPTANCE=USER_REPORTED` (node-pool scope
  only), `RELEASE_EVIDENCE_NOT_YET_COMPLETE`, old command
  1795063030 `OUTCOME_UNKNOWN`. The WebView probe has NOT
  been run on the real device and is NOT approved for
  auto-execution; the PR #105 verifier is a library, NOT
  a standalone Surge script; the stateless replay
  limitation is open (durable one-time nonce consumption
  still required). P2/P3 NOT opened.

## Round 7 addendum (2026-11-20) — PR #106 durable nonce ledger + PR #107 F1 close

- **PR #106 absorbed (byte-identical):** SQLite one-time nonce ledger
  (`nonce_ledger_sqlite.py` SHA `96dd9cb6…5d37`, 174 lines), 21 adversarial
  tests (`test_nonce_ledger_sqlite.py` SHA `a612a32f…31a3c`, 21/21 PASS),
  gate doc (`DURABLE_NONCE_LEDGER_GATE.md` SHA `3fd7c1e9…98f1`), workflow
  (`issue73-durable-nonce.yml` SHA `c51abecf…885`). Head `af944050`, CI 3/3
  re-verified via check-runs API (runs 44635572814 / 44635572821 /
  44635572764, all success — matches GPT's claimed numbers).
- **Cross-review (ledger):** BEGIN IMMEDIATE + WAL + synchronous=FULL +
  busy_timeout + trusted_schema=OFF all present; only the SHA-256 digest
  is stored (independently verified: nonce string absent from DB bytes,
  32-byte digest equals sha256 of raw nonce bytes); INSERT OR IGNORE
  duplicate → False; single conditional UPDATE consume (changed==1);
  0 DELETE (tombstones never deleted); commit_state_unknown on
  sqlite3/OSError, no auto-retry; max_records bound stops issuance;
  path safety (:memory:/symlink/0o077 parent/0o600); user_version 0/1 +
  integrity_check; 21 test methods counted. No discrepancies.
  Observation O1 (not a finding): under lock contention past the 5 s
  busy_timeout, a loser raises commit_state_unknown instead of returning
  False — the documented fail-closed contract.
- **PR #107 absorbed (byte-identical):** F1 fix. The `atob` check runs
  BEFORE SHA-256/Ed25519/random checks and `crypto_ready` is assigned
  only at the end; missing atob → `base64_unavailable`, broken atob →
  `base64_failed`. Vector independently verified (`AQIDBA==` → bytes
  1,2,3,4). Probe suite 18 → 20 tests, **20/20 PASS**; out record
  regenerated (SHA `814a911e…cd2`). Workflow label 18 → 20 matches.
  Gate doc records the fix honestly (still isolated, not a device result).
  **F1 is CLOSED.** Head `1a0d7bd5`, CI 3/3 re-verified via check-runs API
  (runs 44636206928 / 44636207032 / 44636207013, all success).
- **New negative control:** `test_nonce_snapshot_restore_limitation.py`
  (SHA `3c842de1…f4a`) proves GPT's documented limitation #3 is real:
  restoring a pre-consume DB snapshot resurrects the consumed nonce
  (checkpoint TRUNCATE + sidecar handling, deterministic across 5 repeats).
  **1 PASS, 0 FAIL, 1 KNOWN LIMITATION**, exit 0. The ledger alone is not
  end-to-end replay protection; production still needs a rollback-resistant
  epoch / high-water mark / audit anchor.
- **Tests:** eighteen suites total: **220 PASS / 0 FAIL / 1 LIMITATION**
  (v2 V23 frozen timer); clean-copy PASS (`/tmp/c3c0-clean-copy-r7/`,
  88 files, all suites + limitation demo). Delta vs Round 6 (197): +23
  (probe +2, nonce ledger +21).
- **Device evidence scope:** unchanged, 15 rows UNVERIFIED;
  `DEVICE_EVIDENCE_ALIGNMENT.md` NOT touched.
  `DEVICE_EVIDENCE_CORRELATION=OPEN`.
- **v2.2 unchanged:** 571 lines, SHA `8691e962…abfc`.
- Full record: `C3C0_ROUND7_REPORT.md`.
- Gates unchanged: `CREDENTIAL_DISTRIBUTION_GATE=BLOCKED`,
  `BOOTSTRAP_SECURITY_GATE=BLOCKED`, `C3-C1=NO-GO`, `PR93_CUTOVER=BLOCKED`,
  `AUTO_DELETE=OFF`, `DEVICE_EVIDENCE_CORRELATION=OPEN`,
  `DEVICE_ACCEPTANCE=USER_REPORTED` (node-pool scope only),
  `RELEASE_EVIDENCE_NOT_YET_COMPLETE`, old command 1795063030
  `OUTCOME_UNKNOWN`. The WebView probe has NOT been run on the real device
  and is NOT approved for auto-execution; the PR #105 verifier is a library,
  NOT a standalone Surge script; the nonce ledger is a single-host server
  reference, NOT a deployed signing endpoint; P2/P3 NOT opened.

## Round 8 addendum (2026-11-20) — GPT PR #108 (durable signed-proof issuer) + PR #109 (atomic token registry)
- **PR #108:** Draft, head `3a824f94` (branch `gpt6-issue73-durable-signed-proof-issuer-20261120`, stacked on PR #107), 8 commits, 6 files, +522/−0, mergeable clean. `signed_proof_issuer.py` consumes the PR #106 nonce durably BEFORE Ed25519 signing; 16 issuer tests + 7 cross-language interop tests (Python signer → real PR #105 WebCrypto verifier). **16/16 + 7/7 PASS locally.**
- **PR #109:** Draft, head `0ee9fb00` (branch `gpt6-issue73-atomic-token-registry-20261120`, stacked on PR #108 head), 8 commits, 7 files, +847/−0, mergeable clean. `token_registry_sqlite.py` + `atomic_signed_proof_issuer.py`: `consume_authorized()` checks token status AND consumes the nonce in ONE `BEGIN IMMEDIATE` transaction, closing PR #108's lookup→consume TOCTOU gap. 21 registry tests + 7 WebView interop tests. **21/21 + 7/7 PASS locally.**
- **Findings (GPT to decide; files kept byte-identical):** F2 (minor) — PR #108's own gate doc does not disclose the lookup→consume TOCTOU window (only PR #109's doc names it); independently confirmed real by probe P1. F3 (trivial) — both issuers report pre-validation input errors (e.g. malformed nonce) as `nonce_commit_unknown` / `atomic_commit_unknown` although nothing was written (ledger counts (0,0)); fail-closed, only the label is imprecise.
- **New negative controls:** `test_r8_cross_review_probes.py` (SHA `80805edd…f3c2`), **4/4 PASS** — P1 TOCTOU gap real, P2 revocation-linearization limit real (proof issued for a token revoked after COMMIT but before signing; authorize afterwards 403), P3 no plaintext tokens in DB bytes, P4 exposed_old authenticates (200) but never authorizes a proof (None). P1/P2 passing confirms documented limitations are real, not code failures.
- **Tests:** twenty-three suites total: **275 PASS / 0 FAIL / 1 LIMITATION** (v2 V23 frozen timer); clean-copy PASS (`/tmp/c3c0-clean-copy-r8/`, 110 files, all suites + snapshot demo). Delta vs Round 7 (220): +55 (issuer 16 + interop 7 + registry 21 + webview 7 + probes 4).
- **Verification gaps (honest, NOT claimed):** diff-apply reconstruction NOT performed (`get_diff` approvals timed out; public API rate-limited, reset sliding); head CI run numbers NOT independently verified (GPT's claimed runs recorded as unverified in `C3C0_ROUND8_REPORT.md` §2); GPT #73 comments 7025257619/7025858660 verbatim NOT fetched (same approval timeout). All code claims were verified from head-branch files + local test runs; the pending items need one approved `get_diff` / `get_check_runs` / `issue_read` call each, or a public-API quota reset.
- **Device evidence scope:** unchanged, 15 rows UNVERIFIED; `DEVICE_EVIDENCE_ALIGNMENT.md` NOT touched. `DEVICE_EVIDENCE_CORRELATION=OPEN`.
- **v2.2 unchanged:** 571 lines, SHA `8691e962…abfc`.
- Full record: `C3C0_ROUND8_REPORT.md`.
- Gates unchanged: `CREDENTIAL_DISTRIBUTION_GATE=BLOCKED`, `BOOTSTRAP_SECURITY_GATE=BLOCKED`, `C3-C1=NO-GO`, `PR93_CUTOVER=BLOCKED`, `AUTO_DELETE=OFF`, `DEVICE_EVIDENCE_CORRELATION=OPEN`, `DEVICE_ACCEPTANCE=USER_REPORTED` (node-pool scope only), `RELEASE_EVIDENCE_NOT_YET_COMPLETE`, old command 1795063030 `OUTCOME_UNKNOWN`. The issuer/registry are single-host server references, NOT a deployed signing endpoint; PR #108's issuer alone must not be deployed as the authorization path; production must drain in-flight signers before a strict revocation barrier; P2/P3 NOT opened.
- **Round 8 verification gaps — CLOSED in Round 9 (2026-11-20 10:17 CST):** the diff-apply reconstruction was completed after the public-API quota reset (see Round 9 addendum). PR #108: 6/6 files in the diff byte-identical to the absorbed files; PR #109: 7/7. The two `*_out.json` files in each round are **local test-run records generated by running the suites** (they contain the actual test names and PASS lines), not files from GPT's PRs — they do not exist on the PR #108/#109 head branches (verified: get_file_contents returns "file does not exist"). Head CIs were also re-verified via check-runs API in Round 9 (PR #108 head 3/3: proof-issuer 44638700951, v2 44638700998, S1 44638700826; PR #109 head 3/3: token-atomic 44643114016, v2 44643114065, S1 44643113934 — identical to GPT's claimed runs). GPT #73 comments 7025257619/7025858660 were read in full by the parent (not by the Round 8 subagent).

## Round 9 addendum (2026-11-20) — GPT PR #110 (loopback HTTPS proof) + PR #111 (insecure_context) + PR #112 (pure-JS Ed25519 verifier); first real device-side crypto evidence
- **Owner device evidence (comment 7027571021, 2026-11-20 09:31 CST):** Surge iOS script editor, Generic + WebView, reports `isSecureContext=false, crypto=yes, subtle=no, digest=missing, trigger=editor`. The editor WebView has NO `crypto.subtle` because the context is not secure — NOT a hardware Ed25519 limitation; the earlier `no_webcrypto` is now explained. **Gate B = `BLOCKED: EDITOR_WEBVIEW_INSECURE_CONTEXT`, NOT `crypto_ready`.** `DEVICE_EVIDENCE_ALIGNMENT.md` updated (SHA `b94d865e…413f`): rows 16–20 VERIFIED-DEVICE (editor-trigger scope only), rows 21 (generic/intent context) and 22 (Pure-JS probe) UNVERIFIED. Overall correlation stays OPEN.
- **PR #110:** Draft, head `354d2f4` (branch `gpt6-issue73-https-proof-gate-20261120`, stacked on PR #109 head), 6 new files + 1 workflow. `credential_proof_https.py` is a real loopback-only TLS service (binds ONLY 127.0.0.1, TLS≥1.2 enforced, independent high-entropy pairing bearer, strict JSON/length/method gates, atomic token+nonce consume, Ed25519 proof only after SQLite COMMIT). 22 HTTPS tests + 8 module tests. **22/22 + 8/8 PASS locally; head CI 3/3 re-verified** (real-local-tls 44645123332, v2 44645123072, S1 44645123042 — identical to GPT's claims).
- **PR #111:** Draft, head `7a5bba3` (branch `gpt6-issue73-insecure-context-device-gate-20261120`, stacked on PR #110 head), 7 modified files + 1 workflow. Adds the fail-closed `insecure_context` status (reported when `isSecureContext === false`, even if a synthetic environment exposes `crypto.subtle`), records the owner's device evidence in the gate doc, expands the probe 20→22 and the panel 8→9. **22/22 + 9/9 PASS locally; head CI 4/4 re-verified** (special 44655595055, HTTPS/Panel 44655595126, v2 44655595134, S1 44655595084 — identical to GPT's claims).
- **PR #112:** Draft, head `849e5a8c` (branch `gpt6-issue73-purejs-ed25519-verify-gate-20261120`, stacked on PR #111 head; the patrol note "head 04096c1" does not match the current head — verified via list_pull_requests, head is 849e5a8c as GPT stated). 9 new files + vendor/ (4 files) + 1 workflow. Pure-JS Ed25519 verifier not depending on WebCrypto: vendored TweetNaCl.js 1.0.3 + js-sha256 1.0.0, blob SHAs independently verified (`7ea5fb58…c6a6d`, `edb15da8…302e` — computed git blob SHAs match the pinned values and the CI `git hash-object` check). Deterministic 85,914-byte one-shot probe bundle, `--check` reproduces it exactly. **23/23 + 11/11 PASS locally (1 KNOWN LIMITATION: stateless replay); head CI 3/3 re-verified** (special 44656968540, v2 44656968531, S1 44656968557 — identical to GPT's claims).
- **Findings: NONE (no code defects).** All claimed behaviors were independently verified. Two record notes (not GPT defects): (a) the Round 8 `*_out.json` files are local result records, not PR files (see the Round 8 gap closure above); (b) the patrol's PR #112 head note "04096c1" is stale — the verified head is 849e5a8c. PR #111 modifies 6 PR #110 files; PR #112 modifies no #110/#111 file (all new). No F4+ finding; GPT's files kept byte-identical.
- **New cross-review probes:** `test_r9_cross_review_probes.py` (SHA `a0bb1ffb…32d06`), **5/5 PASS** — P1 insecure_context precedence (mocked working subtle + isSecureContext=false → insecure_context, never crypto_ready; isSecureContext true/undefined + no subtle → no_webcrypto), P2 Python atomic issuer → Pure-JS verifier accepts, tampered fingerprint rejected (cross-language canonical-JSON chain), P3 real LoopbackTLSServer end-to-end (valid HTTPS request → proof the Pure-JS verifier accepts; same-nonce replay → 409), P4 non-loopback binding and TLS < 1.2 refused, P5 wrong/missing bearer → 401 with ZERO ledger writes. Helper `test_r9_js_verify_helper.js` (SHA `281d6e86…2406`) loads the actual vendored sources in the insecure VM.
- **Diff reconstruction: COMPLETE for all five PRs** (public-API quota reset 10:17 CST). PR #108 6/6, PR #109 7/7, PR #110 7/7 (4 files verified against the #110 branch versions), PR #111 8/8 (chained on the #110 reconstruction + #109 base files), PR #112 14/14. The Round 8 `DIFF_RECONSTRUCTION_PENDING` is closed.
- **Module pins verified:** webcrypto module pins commit `6babadf552…` (probe + status at that commit byte-identical to the #111 versions; commit is 1 commit behind the #111 head); purejs module pins commit `ac1f0a0ff7…` (bundle + status at that commit byte-identical to the #112 versions; commit is 4 commits behind the #112 head).
- **Tests:** twenty-eight suites total: **347 PASS / 0 FAIL / 1 LIMITATION** (v2 V23 frozen timer; the PureJS stateless-replay limitation is the same underlying theme as the verifier/replay-control limitations, recorded in its suite as 1 KNOWN LIMITATION). Delta vs Round 8 (275): +72 (probe 20→22, +2; HTTPS 22; module 9; purejs 23; bundle 11; cross-review probes 5). Clean-copy PASS (`/tmp/c3c0-clean-copy-r9/`, all suites + snapshot demo). Secret scan 0 hits across all 26 new/changed Round 9 files + 6 out.json records + helper + workflow.
- **Device evidence scope:** rows 16–20 VERIFIED-DEVICE (editor trigger only); rows 21–22 UNVERIFIED; original 15 rows UNVERIFIED. `DEVICE_EVIDENCE_CORRELATION=OPEN`. `PUREJS_DEVICE_PROBE=UNVERIFIED`. `REAL_PRIVATE_HTTPS=NOT_DEPLOYED`.
- **v2.2 unchanged:** 571 lines, SHA `8691e962…abfc`.
- Full record: `C3C0_ROUND9_REPORT.md`.
- Gates unchanged: `CREDENTIAL_DISTRIBUTION_GATE=BLOCKED`, `BOOTSTRAP_SECURITY_GATE=BLOCKED`, `C3-C1=NO-GO`, `PR93_CUTOVER=BLOCKED`, `AUTO_DELETE=OFF`, `DEVICE_EVIDENCE_CORRELATION=OPEN`, `DEVICE_ACCEPTANCE=USER_REPORTED` (node-pool scope only), `RELEASE_EVIDENCE_NOT_YET_COMPLETE`, old command 1795063030 `OUTCOME_UNKNOWN`. The HTTPS service is loopback-only (not a deployed production endpoint); the Pure-JS verifier is a reference library (not a standalone Surge script, not installed, not run on the device); P2/P3 NOT opened.

## Round 10 addendum (2026-11-20) — GPT PR #113 (F3 precise validation + staging signer drain) + PR #114 (signed recovery checkpoint)
- **PR #113:** Draft, head `60a7d14` (branch `gpt6-issue73-f3-drain-rollback-fences-20261120`, stacked on PR #112 head `849e5a8c`), 7 commits, 7 files, +677/−2. Modifies the two issuers (exactly the F3 fix — see three-way review below) and adds `staging_issuance_drain.py` (single-process admission/drain gate), F3 tests (12) + drain tests (14). **12/12 + 14/14 PASS locally; head CI 5/5 re-verified** (dedicated F3+drain run 44662401612, token-atomic 44662401573, S1 44662401498, isolated 44662401610, proof-issuer 44662401500 — identical to GPT's claimed dedicated run).
- **PR #114:** Draft, head `df77b69` (branch `gpt6-issue73-signed-recovery-checkpoint-20261120`, stacked on PR #113 head), 4 commits, 4 files, +423/−0, all new. `recovery_signed_checkpoint.py` verifies a deterministic SHA-256 digest of the full token state + nonce ledger in one SQLite read transaction, with an independently pinned Ed25519 public key **and** an independently trusted monotonic epoch (exact equality required). 17 recovery tests. **17/17 PASS locally; head CI 3/3 re-verified** (synthetic-recovery 44662956632, S1 44662956570, isolated 44662956575 — identical to GPT's claimed dedicated run).
- **Three-way diff review (PR #113 modifies Round 9 files):** PR #110/#111/#112 never touched the two issuers, so the Round 9 copies are exactly the PR #112 base versions. The PR #113 changes are exactly the F3 fix (import + pre-validation + error mapping; +8/−1 and +6/−1 match the PR diff). Workspace copies updated to the PR #113 versions (`signed_proof_issuer.py` SHA `5087f237…`, `atomic_signed_proof_issuer.py` SHA `94862919…`); Round 9 copies preserved at `/tmp/signed_proof_issuer.r108.py` / `/tmp/atomic_signed_proof_issuer.r109.py`. The F3 dependency (`InvalidChallenge`, `nonce_hash`) was already exported by the PR #106 nonce ledger; the validation is real (43-char base64url, 32-byte decode, canonical re-encode).
- **Findings: NONE (no F5+ code defects).** F3 verified real by probe P3 (same ledger, same malformed nonce: PR #108 issuer → `nonce_commit_unknown` after 1 lookup; PR #113 issuer → `invalid_challenge`, 0 lookups, 0 signer calls). Drain gate verified: freeze-before-drain, timeout/failed-action/exception/failed-read-back all stay frozen, cross-process refused (probe P1, fork child → `cross_process_unverified`). Recovery checkpoint verified: old checkpoint vs newer epoch rejected, digest tamper/signature mutation/missing table/extra fields/malformed trust root all fail closed, digest deterministic across fresh connections (probe P4). Two record notes (not GPT defects): (a) O2 — `binding()` InvalidChallenge in the atomic issuer now maps to `invalid_proof_input` (was `preflight_unknown`); GPT's tests assert this as intended, fail-closed, more precise; (b) P2 — the recovery verifier trusts the caller-supplied epoch, so an old checkpoint verifies against a restored old DB if the epoch is also rolled back; the gate doc states this explicitly, and the external monotonic control plane is NOT provisioned (the same gap the VPS staging demo exposed: old DB resurrects a consumed nonce → 200).
- **Diff reconstruction: COMPLETE.** PR #113: 7/7 files byte-identical (diff applied onto the PR #112 base state). PR #114: 4/4 files byte-identical (diff applied onto an empty tree).
- **Tests:** thirty-two suites total: **394 PASS / 0 FAIL / 1 LIMITATION** (v2 V23 frozen timer). Delta vs Round 9 (347): +47 (F3 12 + drain 14 + recovery 17 + R10 probes 4). Clean-copy PASS (`/tmp/c3c0-clean-copy-r10/`, 161 files, all 32 suites + bundle `--check` + rollback hermetic + snapshot demo). Secret scan 0 hits across all 13 new/changed Round 10 files.
- **Device evidence scope:** unchanged (rows 16–20 VERIFIED-DEVICE for the editor trigger only; rows 21–22 UNVERIFIED; original 15 rows UNVERIFIED). `DEVICE_EVIDENCE_CORRELATION=OPEN`. `PUREJS_DEVICE_PROBE=UNVERIFIED`. `REAL_PRIVATE_HTTPS=NOT_DEPLOYED`. `EXTERNAL_EPOCH_PROVISIONED=NO_EVIDENCE`.
- **v2.2 unchanged:** 571 lines, SHA `8691e962…abfc`.
- Full record: `C3C0_ROUND10_REPORT.md`.
- Gates unchanged: `CREDENTIAL_DISTRIBUTION_GATE=BLOCKED`, `BOOTSTRAP_SECURITY_GATE=BLOCKED`, `C3-C1=NO-GO`, `PR93_CUTOVER=BLOCKED`, `AUTO_DELETE=OFF`, `DEVICE_EVIDENCE_CORRELATION=OPEN`, `DEVICE_ACCEPTANCE=USER_REPORTED` (node-pool scope only), `RELEASE_EVIDENCE_NOT_YET_COMPLETE`, old command 1795063030 `OUTCOME_UNKNOWN`. The drain gate is single-process/in-memory (not a production revocation barrier); the recovery checkpoint is a read/verify endpoint only (no external epoch service exists); P2/P3 NOT opened.
