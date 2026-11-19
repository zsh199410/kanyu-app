# C3-C0 Round 3 Continued — PR #101 Shortcuts Candidate Bootstrap

## 1. Summary

GPT's PR #101 (Shortcuts candidate bootstrap) has been cross-reviewed
and absorbed into the private tree. The private Rev 1 bootstrap design
(paste the token into a one-time script's source, run once, delete the
script) is **corrected as wrong** and the approach is **deprecated**:
script deletion is not a security mechanism (Surge caches script source
and retains logs; the manual gives no wipe guarantee), and
`$persistentStore` keys are cross-script accessible. The recommended
path is now the PR #101 template: source never contains the token, the
candidate is staged under `sgbridge_cred_dev_candidate` via a Shortcuts
intent parameter supplied at run time, and promotion is a separate
approved gate.

All seven test suites pass (88 PASS / 0 FAIL / 1 LIMITATION), clean-copy
verification passes, secret scan is 0 hits. No live files touched, no
credentials revoked or rotated, no GitHub posts, no phone contact.

- PR #101: branch `gpt6-issue73-s1-shortcuts-bootstrap-20261119`,
  head `2e6c44df8ff633f008442a44585eaedfd38587c7`, base = PR #100 branch
  `gpt6-issue73-s1-secret-free-adapter-20261119`, 4 commits, +236/−0,
  3 files, Draft. CI runs 44545672281 / 44545672526 / 44545672479 all
  `completed/success`.
- PR #97 (branch `c3c0-sanitized-v2-review`) is at head `4ef98d4`
  (12 commits, 31 files) after the Round 3 commit; both CIs pass on
  that head (isolated run 44546294718 success, real-script-s1 run
  44546294626 success). **Note:** GPT's receipt 7012275778 still cites
  PR #97 head `13abefec` / 22 files — that is **stale** (GPT checked
  before the Round 3 commits landed). The Round 3 commit is already on
  the branch; the head is not regressed.
- Private v2.2 is **unchanged** by this round: 571 lines, SHA
  `8691e962cba4ab40e961702b7d30090aaaedc29fdbe46b63a257878f9f90abfc`.
  PR #101 does not modify the bridge script.

## 2. PR #101 absorption (byte-identical verification)

The full diff was read at `/tmp/pr101.diff` (256 lines). The three
files were fetched from GitHub (raw, ref
`gpt6-issue73-s1-shortcuts-bootstrap-20261119`) and compared against a
reconstruction from the diff:

| File | SHA-256 (full) | Byte-identical |
|---|---|---|
| `bootstrap_candidate_shortcuts.template.js` | `6bfa88385485210ae9c6016ef8ff87a01d539441471c3545711bd3df80ca7591` | YES (no trailing newline, matches diff) |
| `test_bootstrap_candidate_shortcuts.js` | `5bde1810dc6ea01e78bb2e50479e06f121a69290a3c77c73b0e8fd6ab8931b56` | YES (no trailing newline, matches diff) |
| `.github/workflows/issue73-s1-shortcuts-bootstrap.yml` | `950e9602181cf6af78b7c3b7608938fa96acfd7cca21d6673da867d8ff499331` | YES (with trailing newline) |

Copied unmodified into the private tree as:

- `~/workspace/pr96-c3c0/bootstrap_candidate_shortcuts.template.js`
- `~/workspace/pr96-c3c0/test_bootstrap_candidate_shortcuts.js`
- `~/workspace/pr96-c3c0/ci/issue73-s1-shortcuts-bootstrap.yml`

`git apply` was not needed (all three files are new); the verification
above is the byte-identity proof. No discrepancy between PR #101's
files and the absorbed copies.

## 3. Cross-review verdict (PR #101)

| Check | Verdict |
|---|---|
| Trigger rejection covers all non-intent paths | **PASS.** Editor / HTTP API / cron (null) / panel / unknown rejected before any write; `triggered` set only after the check, so rejected runs produce zero state changes. Minor coverage gap: no dedicated test for `$intent === null` / `undefined` with `$trigger === "intent"` (code handles it → `unsupported_trigger`, untested). |
| Candidate validation adequate (length + printable ASCII) | **PASS, with an open item.** 32–256 chars, printable ASCII only; rejects empty / short / CR-LF / non-string / non-ASCII. Open: the production token's actual length and character class must be confirmed against this window **before** use (length + class only, never the value). If the real token were < 32 chars it would be rejected. |
| Occupied-slot logic prevents silent overwrite, allows idempotent re-stage | **PASS.** Different existing candidate → `candidate_slot_occupied`, no write. Same candidate → `candidate_already_staged`, no re-write. Non-string or empty existing value → occupied (fail-closed). |
| Write-false / readback-mismatch fail-closed, no auto-retry | **PASS.** Write `!== true` → `candidate_commit_unknown`, no retry. Read-back mismatch → `candidate_readback_unverified`. Write-reaches-disk-then-false → still `unknown` (test confirms the value IS on disk but the status does not claim success). The ambiguity must be resolved by a separate read-back verification gate. |
| Any path that logs or leaks the parameter, a digest, or a local key | **None found in the template.** No network, no console, no notification, no digest. Status is a fixed enum. Mock limitation (not a code gap): the test mock records writes as `{key, valueKind}`, so it cannot detect whether the **real Surge runtime** logs `$persistentStore.write` values. That is a device-side open item. |
| Template does not touch active token, ledger, last_id, old slot, timers, policies | **PASS.** Only reads/writes `sgbridge_cred_dev_candidate` and writes the status key. Minor observation: `ACTIVE_KEY` is declared but never referenced (dead constant). Not a bug. |
| CI workflow | **PASS.** Syntax checks + the 13-case test, `contents: read`, 5-minute timeout. |

Additional notes (recorded in `BOOTSTRAP_DESIGN.md` Rev 2 §3):

- The template does **not** reject `<...>` placeholder values (unlike
  v2.2's `readCredential`). Blast radius is bounded: the bridge would
  refuse it (`credential_missing` → fail-closed) and the candidate slot
  would be occupied until cleared by a separate gate.
- The template cannot distinguish a **manual** Shortcuts intent
  invocation from an **automated** Shortcuts automation invoking the
  same intent. Manual invocation only; device-side governance item.
- A stale/wrong candidate has **no clear path in this script** (by
  design). Clearing it needs a separate approved device-side action.
- The **local key** (`sgbridge_cred_localkey`) has **no approved
  bootstrap path** in PR #101 (template stages only the DEV token).
  v2.2 can run without the local key for native `$httpAPI` calls; the
  key is only needed for the direct-HTTP fallback and MCP. Lower
  priority open item, not a blocker for the DEV-token path.

## 4. Bootstrap design correction (Rev 1 → Rev 2)

`BOOTSTRAP_DESIGN.md` rewritten as **Rev 2** (17,091 bytes, SHA
`3b188e24eb0aeec0…`, full SHA in §7).

**What was wrong:** Rev 1's mechanism pasted the token into the script
source and treated manual script deletion as the credential having been
cleared. That is wrong because (a) the token sits in script source,
which Surge caches and logs, and the manual gives no guarantee that
deleting a script wipes cached source or logs; (b) `$persistentStore`
keys are cross-script accessible, so writing the credential into the
store does not hide it from other scripts; (c) deleting a script does
not wipe `$persistentStore` or logs.

**What changed:**

- `s1/bootstrap.js` is **DEPRECATED** (header comment added, file
  kept as a record only; no behavior change — the added text is a
  comment). Do not use it to bootstrap a credential.
- `s1/bootstrap_test.js` (7/7) is the isolated verification of the
  **superseded approach's logic only**, kept as a record. It is not an
  endorsement.
- Recommended path is now PR #101: Shortcuts intent parameter at run
  time, candidate staged under `sgbridge_cred_dev_candidate`, active
  token untouched, promotion a separate approved gate.
- Rev 2 lists 12 open device-side items (§6 of the design): Shortcuts
  input history, iOS/iCloud backup, script cache leakage, device-side
  log check, other scripts' permissions, candidate key visibility,
  production token format vs the 32–256 window, local-key bootstrap
  path, promotion gate, gate 2 server-side token-table change,
  real-device candidate staging run, real-device loading + two cron
  cycles. None is verified in this round.
- `$persistentStore` is **not** a proven secure hardware keystore
  (stated explicitly in both revisions; Rev 2 adds that the PR #101
  approach removes the credential from the distributed script and
  from script source, and does not claim secure-enclave storage).
- The old exposed token must **not** be routinely revived (unchanged).

## 5. Test results (all against the current private tree)

| Suite | Result |
|---|---|
| v2 regression `test_fixed_v2.js` | **28 PASS / 0 FAIL / 1 LIMITATION** (V23, `RUNTIME_HARD_TIMEOUT_UNPROVEN`, frozen timer — unchanged) |
| Storage failure `test_store_failure.js` | **5/5 PASS** |
| S1 live adapter `test_s1_live_adapter.js` | **10/10 PASS** |
| S1 `s1/test_s1.js` | **11/11 PASS** |
| S3 `s3/test_s3.js` | **14/14 PASS** |
| Bootstrap `s1/bootstrap_test.js` | **7/7 PASS** (deprecated approach — logic record only, not an endorsement) |
| Bootstrap candidate `test_bootstrap_candidate_shortcuts.js` | **13/13 PASS** (new; PR #101) |
| Rollback `rollback_test.sh` | **PASS** |

Total across the seven suites: **88 PASS / 0 FAIL / 1 LIMITATION**
(28+5+10+11+14+7+13).

## 6. Clean-copy verification

**PASS.** The full submission set (14 files, §7) was copied to a fresh
`/tmp/c3c0-clean-copy-r3b/` and all seven suites were run from there:
v2 28/0/1, store 5/5, S1 live 10/10, S1 11/11, S3 14/14, bootstrap
7/7, bootstrap candidate 13/13.

## 7. Files to commit to PR #97 (branch `c3c0-sanitized-v2-review`)

| Target path | SHA-256 (short) | Status |
|---|---|---|
| `docs/surge-bridge-c3c0/bootstrap_candidate_shortcuts.template.js` | `6bfa8838…ca7591` | NEW (PR #101, unmodified) |
| `docs/surge-bridge-c3c0/test_bootstrap_candidate_shortcuts.js` | `5bde1810…8931b56` | NEW (PR #101, unmodified) |
| `docs/surge-bridge-c3c0/test_bootstrap_candidate_out.json` | `1fa4ce5a…f22c` | NEW (13/13 record) |
| `docs/surge-bridge-c3c0/BOOTSTRAP_DESIGN.md` | `3b188e24…` (full SHA below) | UPDATED (Rev 2 rewrite) |
| `docs/surge-bridge-c3c0/s1/bootstrap.js` | `fd9076f6…f31a` | UPDATED (DEPRECATED header only) |
| `docs/surge-bridge-c3c0/C3C0_REPORT.md` | (recompute at commit time) | UPDATED (Round 3 continued addendum) |
| `docs/surge-bridge-c3c0/C3C0_ROUND3B_REPORT.md` | self-referential (recompute at commit time) | NEW |
| `.github/workflows/issue73-s1-shortcuts-bootstrap.yml` | `950e9602…499331` | NEW (PR #101, unmodified) |

Full SHA of `BOOTSTRAP_DESIGN.md` (Rev 2):
`3b188e24eb0aeec0d738b939a75a240d0ef183dab7986634000ceab7c38e149b`.

Unchanged in Round 3 continued: `bridge_fixed_v2.js` (v2.2,
`8691e962…abfc`, 571 lines), `test_fixed_v2.js`, `test_store_failure.js`,
`test_s1_live_adapter.js`, `simulator.js`, `s1/test_s1.js`,
`s1/bootstrap_test.js`, `s1/bootstrap_out.json`, `s3/*`, `v1/*`,
`ci/issue73-c3c0-v2.yml`, `ci/issue73-c3c0-s1-adapter.yml`,
`SECURITY_GATE_PLAN.md`, `SECURITY_GATE_PLAN_REV1.md`,
`ID_ALLOCATOR_DESIGN.md`, `C3C0_S1_S3_SUMMARY.md`,
`C3C0_ROUND2_REPORT.md`, `C3C0_ROUND3_REPORT.md`,
`C3C0_MINIMAL_PATCH_V2.md`, `C3C0_V2_V21_DIFF.md`,
`C3C0_V2_V22_DIFF.md`, `rollback_test.sh`.

## 8. Secret scan

All 8 new/changed Round 3-continued files scanned for the real DEV
token, real API key, real URLs, node URIs, script/module paths, and
the VPS IP: **0 hits**. Only placeholders and synthetic `TEST-*`
tokens. (Scan result recorded in the parent's verification step.)

## 9. Gates (unchanged)

`CREDENTIAL_DISTRIBUTION_GATE=BLOCKED`; `C3-C1=NO-GO`;
`PR93_CUTOVER=BLOCKED`; `AUTO_DELETE=OFF`; old command 1795063030
stays `OUTCOME_UNKNOWN`, permanently fenced. PR #98 (GPT oracle 28/28)
and PR #99 (saveLedger fix) and PR #100 (S1 credential adapter)
untouched and not conflated with these counts. PR #101's own CI runs
(44545672281, 44545672526, 44545672479, success) are GPT's verification
of the same change set.

## 10. What the parent still needs to do

1. Commit the §7 files to PR #97 (branch
   `c3c0-sanitized-v2-review`) as the Round 3 continued follow-up.
2. Post the C3-C0 Round 3 continued receipt to Issue #73 (referencing
   PR #97's new head, PR #101 absorbed, the bootstrap design
   correction, and the unchanged gates).
