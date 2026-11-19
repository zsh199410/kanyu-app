# C3-C0 Round 4 (P0 fast-track) — PR #102 Hermetic Rollback + First-Stage Launch Blockers 1–3

## 1. Summary

Owner priority (GPT receipt 7013674858): "抓紧上线、以最快可用版本为先"
— hurry up and go live, fastest usable version first. Narrow scope:
first complete the C3-C1 Bridge stable launch P0 gates; P2/P3 node
auto-isolation/deletion only as offline designs; do not delay P0 for
new features; do not open AUTO_DELETE early.

This round absorbs GPT's PR #102 (hermetic rollback test) and delivers
desensitized executable samples + isolated CI for the three first-stage
launch blockers: (1) credential provisioning on device, (2)
staging-to-active promotion gate, (3) server dual-token and revocation.
Blockers (4) (real-device release proof) and (5) (release checklist /
prod rollback) are NOT built in this round — they need real-device
gates and explicit owner permission.

Twelve suites pass (**136 PASS / 0 FAIL / 1 LIMITATION**, plus the
hermetic rollback positive PASS and its negative control FAIL as
expected), clean-copy verification passes, secret scan is 0 hits. No
live files touched, no credentials revoked or rotated, no GitHub
posts, no phone contact. Private v2.2 is unchanged. P2/P3 were NOT
opened.

- GPT receipt: 7013674858 on Issue #73.
- GPT's PR #102: branch `gpt6-issue73-c3c0-hermetic-rollback-20261119`,
  head `d0ce8f948fae8b01a7d1a6e9520d81d3aeeedb3e`, base =
  `c3c0-sanitized-v2-review`, 2 commits, +108/−52, 2 files, Draft.
  CI runs 44555342039 / 44555341540 / 44555341842 all
  `completed/success`.
- PR #97 (branch `c3c0-sanitized-v2-review`) is at head `225d8dc`
  (15 commits, 40 files); three CIs green on that head (v2 run
  44551075671, S1 run 44551075587 incl. bootstrap tests, Shortcuts
  bootstrap run 44551076143). Round 3 receipt (Rev 3) is on #73 as
  comment 7013375500.

## 2. PR #102 absorption (byte-identical verification)

The full diff was read at `/tmp/pr102.diff` (173 lines). The two files
were fetched from GitHub (raw, ref
`gpt6-issue73-c3c0-hermetic-rollback-20261119`) and compared against a
reconstruction from the diff:

| File | SHA-256 (full) | Byte-identical |
|---|---|---|
| `rollback_test.sh` | `5a92efec1b3727866c29372bdc6ef2c39e5ae258086c883bfe15e4ec04102ae6` | YES (diff reconstruction + trailing newline == API fetch) |
| `.github/workflows/issue73-c3c0-hermetic-rollback.yml` | `5e6fe7dde724af49929fb78ca2845318f9dc342a66fed538ba77004f6de302b7` | YES (same) |

Copied unmodified into the private tree as:

- `~/workspace/pr96-c3c0/rollback_test.sh` (REPLACES the old version)
- `~/workspace/pr96-c3c0/ci/issue73-c3c0-hermetic-rollback.yml` (NEW)

**What changed:** the old version depended on private paths
`~/workspace/pr96-c3c0/bridge_fixed_v2.js` and
`/tmp/bridge_orig_desens.txt` (not reproducible in CI). The new
version sources v2.2 and v1 ONLY from the checkout
(`$SRC_DIR/bridge_fixed_v2.js` and `$SRC_DIR/v1/bridge_fixed.js`),
uses `mktemp -d` + `trap EXIT` cleanup, `set -euo pipefail`.
Synthetic deployment + backup + snapshot; state files `state.json`
(cmd 1795063030, result 1795055213880, 2 synthetic pins, 5 timers),
`sgbridge_last_id`, `pins.json`, `timers.json`. Rollback restores
ONLY the three code files (bridge.js, bridge.sgmodule, server.py).
Negative control `--inject-state-change` appends a synthetic mutation
to state.json and the verification must FAIL. Verification: state
files byte-identical (`cmp`), code files restored from backup, code
files actually changed from v2 (not a no-op), legacy pending ID
1795063030 still present (no command clearing/replay).

**Local runs (this round):** positive `ROLLBACK_TEST: PASS (hermetic
code-only restore; state, last_id, pins, timers unchanged)`, exit 0;
negative control `ROLLBACK_TEST: FAIL (state.json altered)`, exit 1
as expected. New version contains NO private paths (verified by grep:
no `pr96-c3c0`, no `/tmp/bridge_orig`, no `workspace`).

## 3. Item 1 — credential provisioning on device

The PR #101 candidate templates (DEV + local-key) are already the
desensitized samples. This round adds a standalone executable DEMO
that walks the full provisioning flow end to end in a mock
environment:

- `provisioning_demo.js` (SHA `8922afba…db125e`): loads the two
  candidate templates for real (vm sandbox) and runs them with
  synthetic tokens — Shortcuts intent parameter → candidate staging
  (DEV + local key, independent) → verification (candidates present,
  active keys unchanged, status markers) → the list of what is STILL
  UNVERIFIED on the real device (13 items: script-run logs retention,
  Shortcuts input history, cross-script `$persistentStore` access,
  iOS/iCloud backup, script cache leakage, device-side log check,
  other scripts' permissions, candidate key visibility, production
  token format window, promotion gate approval, server dual-token
  revocation, real-device staging run, real-device loading + two cron
  cycles). Prints ONLY non-secret status enums and booleans — never a
  token, never a digest, never a key value. Exit 0 on success.
- `test_provisioning_demo.js` (SHA `1be286c1…432a09d`): spawns the
  demo as a child process and asserts on its REAL output — **5/5
  PASS**: demo exits 0 with no stderr; both candidates staged;
  verification confirms candidates present and active keys unchanged;
  the demo lists what is still unverified; no secret in any output
  (asserts none of the four synthetic token values appears, plus a
  blanket rejection of any `TEST-` string in stdout/stderr).

## 4. Item 2 — staging-to-active promotion gate

- `PROMOTION_GATE_DESIGN.md` (SHA `33098ce2…bd73b`): promotion moves
  a staged candidate to active ONLY when ALL six conditions hold:
  (a) candidate exists and passes `readCredential` validation AND
  the 32–256 printable-ASCII window; (b) a server-side
  `/credential-proof` response for the NEW token is present (endpoint
  contract described — fingerprint only, never the token value;
  `ok`, `fingerprint_matches`, non-empty `token_id` ≠ old token id,
  issued within 24h and not >5min in the future); (c) the active
  token is still the old one (already-promoted is an idempotent
  no-op; absent active fails closed); (d) the promotion write is
  atomic in the only sense available — write new active, read-back
  verify, only then clear the candidate; any failure before
  verification leaves the active token unchanged and the candidate
  intact; (e) the old exposed token is NEVER re-enabled (rollback =
  new backup token or fail-closed, per S1 Rev 1); (f) the old command
  1795063030 stays `OUTCOME_UNKNOWN`, never replayed/overwritten/
  cleared (the gate has no code path to the mailbox).
- `promotion_gate.js` (SHA `c3fb617d…11dab0`): the mock gate
  (`promote(store, { keys, proof, oldTokenId })` against a
  `$persistentStore`-like `{ read, write, remove? }` interface).
  Two findings recorded in the design: (i) a clear failure AFTER the
  verified active write does NOT roll back — rolling back a verified
  promotion is more dangerous than a stale candidate equal to the
  active value; it reports `promotion_candidate_clear_failed`
  (ok=false) and a retry converges to `promotion_already_active`;
  (ii) `$persistentStore` has NO documented delete, so the sample's
  clear uses `remove()` when available and otherwise overwrites with
  the tombstone `"__PROMOTED__"` (12 chars, can never validate as a
  candidate, occupies the slot until a separate approved device-side
  action clears it).
- `test_promotion_gate.js` (SHA `bd7c3336…c737b`): **17/17 PASS** —
  happy path; missing candidate; invalid candidate; invalid proof
  (ok=false, fingerprint mismatch, stale 25h, proof for the OLD token
  id); active write false not persisted; active write persisted then
  false (commit_unknown, NOT reported as success, candidate intact);
  read-back mismatch; promotion attempted twice (second is a no-op,
  already promoted, candidate gone); no active key; clear failure +
  retry convergence; tombstone fallback path; local-key pair happy
  path; old command id untouched in every path (mailbox snapshot);
  no secret in any returned result or recorded write.

## 5. Item 3 — server dual-token and revocation

- `DUAL_TOKEN_DESIGN.md` (SHA `b4f2875b…31e26`): the server token
  table holds TWO active rows during a bounded window (old exposed +
  new; 48h upper bound per S1 Rev 1, exact length an approval item);
  the table stores FINGERPRINTS (SHA-256 hex), never token values;
  the table is append-only for audit (revocation is a status change,
  never a delete); the bridge accepts either token during the window
  (dual-token support lives on the SERVER, the phone holds one active
  token); after revocation or window expiry the old token returns
  403 and the bridge's v2.2 403 gate fails closed without falling
  back; 401 = no such token / missing token, 403 = known token
  revoked or expired; revocation is a separate approved step after
  real-device proof; expiry fails closed (old token rejected after
  `windowEndsAt` even without explicit revocation); rollback =
  activate a NEW backup token, never the old exposed one; the old
  command is never touched.
- `dual_token_server.js` (SHA `0943b04e…d4bc`): the mock server
  (`DualTokenServer` with injectable clock, `addToken` /
  `authorize` / `revoke` / `rollbackToBackup`, mock mailbox with cmd
  1795063030). A first failing test caught a real test bug (the
  "fingerprints only" assertion wrongly included the non-secret row
  IDs in the forbidden list); the test was corrected to assert only
  token VALUES are absent and fingerprints are 64-hex. The sample
  code itself was not changed.
- `test_dual_token.js` (SHA `0d110341…8d5f60`): **12/12 PASS** — old
  token accepted before revocation; new token accepted; both accepted
  during the window; old token 403 after revocation, new still
  accepted; no token → 401 `token_missing`; unknown token → 401
  `unknown_token` (not 403); window expiry fails closed (403
  `window_expired` without explicit revocation, new still accepted);
  window boundary (accepted 1s inside, rejected 1s past); revocation
  is a status change, never a delete (row stays with `revoked_at` /
  `revoked_reason`; second revoke refused; unknown id refused);
  rollback activates a NEW backup token, rollback with the OLD token
  value refused; revocation/expiry/rollback never touch the old
  command id; no token value stored in the table (fingerprints only).

## 6. CI for Round 4

New workflow `ci/issue73-c3c0-round4.yml` (SHA `cf9ccb7e…fc8b4`):
syntax checks for all six Round 4 JS files + a step running the
three new test files (`test_provisioning_demo.js`,
`test_promotion_gate.js`, `test_dual_token.js`) with a nonzero-failure
gate (node exits 1 on an uncaught assertion failure). The hermetic
rollback has its own workflow from PR #102
(`issue73-c3c0-hermetic-rollback.yml`), which runs the positive run
and the negative control. Both workflows are `contents: read` and
isolated (synthetic tokens only, no network, no phone).

## 7. Test results (all against the current private tree)

| Suite | Result |
|---|---|
| v2 regression `test_fixed_v2.js` | **28 PASS / 0 FAIL / 1 LIMITATION** (V23, `RUNTIME_HARD_TIMEOUT_UNPROVEN`, frozen timer — unchanged) |
| Storage failure `test_store_failure.js` | **5/5 PASS** |
| S1 live adapter `test_s1_live_adapter.js` | **10/10 PASS** |
| S1 `s1/test_s1.js` | **11/11 PASS** |
| S3 `s3/test_s3.js` | **14/14 PASS** |
| Bootstrap `s1/bootstrap_test.js` | **7/7 PASS** (deprecated approach — logic record only) |
| Bootstrap candidate `test_bootstrap_candidate_shortcuts.js` | **13/13 PASS** (PR #101) |
| Candidate regressions `test_bootstrap_candidate_regressions.js` | **14/14 PASS** |
| Rollback hermetic `rollback_test.sh` (PR #102) | **PASS** (positive, exit 0) + negative control **FAIL as expected** (exit 1, `state.json altered`) |
| Provisioning demo `test_provisioning_demo.js` | **5/5 PASS** (new) |
| Promotion gate `test_promotion_gate.js` | **17/17 PASS** (new) |
| Dual token `test_dual_token.js` | **12/12 PASS** (new) |

Total across the twelve suites: **136 PASS / 0 FAIL / 1 LIMITATION**
(28+5+10+11+14+7+13+14+5+17+12).

## 8. Clean-copy verification

**PASS.** The full private tree (42 files) was copied to a fresh
`/tmp/c3c0-clean-copy-r4/` and all twelve suites were run from there:
v2 28/0/1, store 5/5, S1 live 10/10, S1 11/11, S3 14/14, bootstrap
7/7, bootstrap candidate 13/13, candidate regressions 14/14,
rollback positive PASS + negative control FAIL as expected,
provisioning demo 5/5, promotion gate 17/17, dual token 12/12.
v2.2 SHA in the copy: `8691e962…abfc` (unchanged).

## 9. Files to commit to PR #97 (branch `c3c0-sanitized-v2-review`)

| Target path | SHA-256 (full) | Status |
|---|---|---|
| `docs/surge-bridge-c3c0/rollback_test.sh` | `5a92efec1b3727866c29372bdc6ef2c39e5ae258086c883bfe15e4ec04102ae6` | UPDATED (PR #102, hermetic) |
| `.github/workflows/issue73-c3c0-hermetic-rollback.yml` | `5e6fe7dde724af49929fb78ca2845318f9dc342a66fed538ba77004f6de302b7` | NEW (PR #102) |
| `docs/surge-bridge-c3c0/provisioning_demo.js` | `8922afba409059ff83fccec78bf93a99558ab0d4351fb7584b42c4e0c6db125e` | NEW |
| `docs/surge-bridge-c3c0/test_provisioning_demo.js` | `1be286c1ff719aef62887e195dcf65100f26e5bda933a18f8d9089229432a09d` | NEW |
| `docs/surge-bridge-c3c0/test_provisioning_demo_out.json` | `1e340f2cb044c7d895c8359c4e5ffd698062e5c1d24c5d6c91311cbf18b28c50` | NEW (5/5 record) |
| `docs/surge-bridge-c3c0/PROMOTION_GATE_DESIGN.md` | `33098ce21634e4f272ba896fed5be8dc5aaa2e956cb1fc4dc753d1ec152bd73b` | NEW |
| `docs/surge-bridge-c3c0/promotion_gate.js` | `c3fb617dfeed0f6b5b48eb68af5206da298242aac941aa0700af70b75d11dab0` | NEW |
| `docs/surge-bridge-c3c0/test_promotion_gate.js` | `bd7c33369c0484312578044887b178389ed348b948a368ca24a41500939c737b` | NEW |
| `docs/surge-bridge-c3c0/test_promotion_gate_out.json` | `4509cb7ab93210c47f2fc6b533c5c76c808a47ce9385a2b2959c09892ed55449` | NEW (17/17 record) |
| `docs/surge-bridge-c3c0/DUAL_TOKEN_DESIGN.md` | `b4f2875b3a579b0043bfe72545ca6338ab75f65ecf5fefb706f2d5a5a2331e26` | NEW |
| `docs/surge-bridge-c3c0/dual_token_server.js` | `0943b04e17471a09a8d0a8553b1216ab172ec65cdfd86ab40e5ff1bb47d0d4bc` | NEW |
| `docs/surge-bridge-c3c0/test_dual_token.js` | `0d11034185bffc9826941c06bfc02f4988ddf2526277a5b6e410ac513b8d5f60` | NEW |
| `docs/surge-bridge-c3c0/test_dual_token_out.json` | `b36bb88f384cc458cc9364a4454a477f8acf6134cea0eb909ca3697950affb1b` | NEW (12/12 record) |
| `.github/workflows/issue73-c3c0-round4.yml` | `cf9ccb7e8b748a881a81182a411a9ab174731f6e1bb39635d88a23a2200fc8b4` | NEW |
| `docs/surge-bridge-c3c0/C3C0_REPORT.md` | (recompute at commit time) | UPDATED (Round 4 addendum) |
| `docs/surge-bridge-c3c0/C3C0_ROUND4_REPORT.md` | self-referential (recompute at commit time) | NEW |

Unchanged in Round 4: `bridge_fixed_v2.js` (v2.2,
`8691e962…abfc`, 571 lines), `test_fixed_v2.js`,
`test_store_failure.js`, `test_s1_live_adapter.js`, `simulator.js`,
`s1/test_s1.js`, `s1/bootstrap.js` (DEPRECATED, `fd9076f6…f31a`),
`s1/bootstrap_test.js`, `bootstrap_candidate_shortcuts.template.js`
(`6bfa8838…ca7591`), `test_bootstrap_candidate_shortcuts.js`
(`5bde1810…8931b56`), `bootstrap_candidate_localkey.template.js`
(`187e65c2…938be41`), `test_bootstrap_candidate_regressions.js`
(`4f7337f0…21b5`), `s3/*`, `v1/*`, `ci/issue73-c3c0-v2.yml`,
`ci/issue73-c3c0-s1-adapter.yml`,
`ci/issue73-s1-shortcuts-bootstrap.yml`, `BOOTSTRAP_DESIGN.md`,
`SECURITY_GATE_PLAN.md`, `SECURITY_GATE_PLAN_REV1.md`,
`ID_ALLOCATOR_DESIGN.md`, `C3C0_S1_S3_SUMMARY.md`,
`C3C0_ROUND2_REPORT.md`, `C3C0_ROUND3_REPORT.md`,
`C3C0_ROUND3B_REPORT.md`, `C3C0_ROUND3C_REPORT.md`,
`C3C0_MINIMAL_PATCH_V2.md`, `C3C0_V2_V21_DIFF.md`,
`C3C0_V2_V22_DIFF.md`.

## 10. Secret scan

All 14 new/changed Round 4 files scanned for the real DEV token,
real API key, real URLs, node URIs, script/module paths, and the VPS
IP: **0 hits**. Only placeholders and synthetic `TEST-*` tokens.
(Scan result recorded in the parent's verification step.)

## 11. Gates (unchanged)

`CREDENTIAL_DISTRIBUTION_GATE=BLOCKED`; `BOOTSTRAP_SECURITY_GATE=BLOCKED`;
`C3-C1=NO-GO`; `PR93_CUTOVER=BLOCKED`; `AUTO_DELETE=OFF`; old command
1795063030 stays `OUTCOME_UNKNOWN`, permanently fenced. PR #98 (GPT
oracle 28/28), PR #99 (saveLedger fix), PR #100 (S1 credential
adapter), PR #101 (Shortcuts candidate bootstrap), PR #102 (hermetic
rollback) untouched and not conflated with these counts. Blockers (4)
(real-device release proof) and (5) (release checklist / prod
rollback) were NOT built in this round — they need real-device gates
and explicit owner permission. P2/P3 node auto-isolation/deletion
were NOT opened.

## 12. What the parent still needs to do

1. Commit the §9 files to PR #97 (branch
   `c3c0-sanitized-v2-review`) as the Round 4 follow-up.
2. Post the C3-C0 Round 4 receipt to Issue #73 (referencing PR #97's
   new head, PR #102 absorbed, the three item designs + samples,
   and the unchanged gates).
