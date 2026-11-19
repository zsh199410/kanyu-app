# C3-C0 Report — Private Fix Alignment with PR #96 Reference (HEAD 7aba9184)

Date: 2026-11-19. Project: PR #96 / Issue #73, C3-C0 (code review + isolated
testing only). All work was done in isolation on this machine
(`~/workspace/pr96-c3c0/`); no phone contact, no production mailbox, no
GitHub posts, no changes under `/opt/surge-bridge/`. C3-C1 live deployment
is NOT AUTHORIZED by this task.

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
| **v2 `bridge_fixed_v2.js`** | **`b3c0b34045d8b4cecbc86b1ae39ff8e7a778091f8aa45733592e704697986135`** | **506** |
| v2 test suite `test_fixed_v2.js` | `c4fd41893b71faa72e4fa662dae02ea3e0f8970cc4a4b91ac2074c8563017eda` | — |
| simulator (copied from C3-B, unchanged) | `7d2b6d0dca0a4bb1a8c21eaf3a6b54fbf74e65e0bf7abe20249234d6287f2521` | — |
| Original `bridge.js` (PR #85, desensitised) | `466cb56b5877bf2d1956833851540d6491c53b2e29a3ea5c53762049fddceb24` | 109 |

## C3-C0 acceptance fields

| Field | Result | Evidence |
|---|---|---|
| PRIVATE_PATCH_SHA | PASS | v2 script SHA `b3c0b340…86135` (506 lines). Test suite SHA `c4fd4189…17eda`. The desensitised v2 script and its unified diff are in `C3C0_MINIMAL_PATCH_V2.md` (109 → 506 lines). |
| PUBLIC_SANITIZED_DIFF_COMMIT | **PENDING (not done by this task)** | The desensitised diff is ready for review (`C3C0_MINIMAL_PATCH_V2.md`), but this subagent does not post to GitHub. No public commit exists yet. The parent agent must submit it as a Draft PR (PR #96 or a new independent Draft PR) and record the commit SHA. Do NOT treat this field as satisfied until that commit exists. |
| WIRE_RAW_ID_PRESERVED | PASS | V24: seconds cmd id and ms cmd id are unchanged in the posted result, in the ledger `last_acked_id`, and in the legacy `last_id` write. V18/V4 confirm the same for the strict-ACK path. |
| ORDERING_CANONICAL_MS | PASS | V1–V8. All comparisons go through `orderMillis()` (ms precision); a seconds id converts by x1000, a ms id stays; non-safe-integer or overflow returns null and fails closed. |
| SAME_SECOND_MS_CASE | PASS | V1: ms id LEGACY_MS+1 dispatches. V2: LEGACY_MS-1 is deduped. V5: M+1 and M+2 (same second) both dispatch; an exactly equal id is deduped. V8: v1 blocks M+1 (toSec collision), v2 dispatches it. |
| ID_ALLOCATOR_UNIQUENESS | **GAP (server-side, not fixed by the phone script)** | The parent agent verified read-only that the server does NOT generate command IDs: `/issue` accepts a caller-supplied id, `_valid_id` only checks `int` in `(0, 2^53-1]`, and `issue_if_empty`'s `command_id_not_increasing` check is a RAW numeric comparison (unit-blind, the same bug class as the original dedup). Two callers issuing seconds-precision IDs in the same second would collide; the server cannot guarantee uniqueness. **Required:** a documented allocation rule (recommend ms-only IDs) and a server-side `orderMillis` fix in a later production step. The phone script must not depend on server-side uniqueness: it fails closed on an exactly equal id (dedup) and never assumes two distinct ids are ordered by their raw value. This gap does not block C3-C0 review, but it must be tracked as a production follow-up. |
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

- [bridge_fixed_v2.js](sandbox://workspace/pr96-c3c0/bridge_fixed_v2.js) — v2 fixed script (desensitised, 506 lines, SHA `b3c0b340…86135`)
- [test_fixed_v2.js](sandbox://workspace/pr96-c3c0/test_fixed_v2.js) — v2 regression suite (29 checks)
- [test_fixed_v2_out.json](sandbox://workspace/pr96-c3c0/test_fixed_v2_out.json) — v2 results (28 PASS, 0 FAIL, 1 LIMITATION)
- [C3C0_MINIMAL_PATCH_V2.md](sandbox://workspace/pr96-c3c0/C3C0_MINIMAL_PATCH_V2.md) — desensitised unified diff v2 vs original (109 → 506 lines) + v1→v2 change list
- [C3C0_REPORT.md](sandbox://workspace/pr96-c3c0/C3C0_REPORT.md) — this report
- [simulator.js](sandbox://workspace/pr96-c3c0/simulator.js) — isolated Surge mock (copied from C3-B, unchanged)
- [rollback_test.sh](sandbox://workspace/pr96-c3c0/rollback_test.sh) — isolated rollback simulation (PASS)
- [pr96-head-7aba9184/bridge_delivery_state.js](sandbox://workspace/pr96-c3c0/pr96-head-7aba9184/bridge_delivery_state.js) — PR #96 reference (HEAD 7aba9184, as received)
- [pr96-head-7aba9184/test_bridge_delivery_state.js](sandbox://workspace/pr96-c3c0/pr96-head-7aba9184/test_bridge_delivery_state.js) — PR #96 reference tests (23/23 PASS locally)

## Notes for the parent agent / GPT

- **PUBLIC_SANITIZED_DIFF_COMMIT is the one open item from this task.**
  The desensitised diff is review-ready, but no public commit exists because
  this subagent does not post to GitHub. The parent must submit
  `C3C0_MINIMAL_PATCH_V2.md` (and/or the desensitised `bridge_fixed_v2.js`
  with its test suite) as a Draft PR and record the commit SHA.
- **PUBLIC_JS_SECRET_EXPOSURE = YES blocks C3-C1.** Do not load the v2
  script from the current anonymously reachable distribution path, and do
  not treat a new script SHA as a fix for the exposure. Rotation/isolation
  of the exposed long-lived credentials must pass first.
- **ID_ALLOCATOR_UNIQUENESS is a server-side gap.** Recommend ms-only IDs
  and a server-side `orderMillis` fix in a later production step; the phone
  script must not depend on server-side uniqueness.
- The frozen-timer case remains `RUNTIME_HARD_TIMEOUT_UNPROVEN` (V23). Only
  real device script logs can confirm whether it ever occurs on the phone.
- The old command 1795063030 stays `OUTCOME_UNKNOWN` and is permanently
  fenced in v2. C3-C1 remains NOT AUTHORIZED; PR #93 stays BLOCKED.
