# C3-C0 Round 3C — GPT P0-B1/B2/B3 Bootstrap Fixes

## 1. Summary

GPT independently reviewed the committed bootstrap artifacts on PR #97
head `4ef98d4` (review comment 7012623369, receipt 7012637830) and raised
three P0 bootstrap findings. All three are addressed in this round in
isolation. The defects in the deprecated script are **proven by test,
not just asserted**: the new regression file runs the deprecated
script's real logic in a VM mock and shows the partial update and the
unbacked `bootstrap_ok`. The new candidate-staging approach is proven
to have no such defect, a local-key candidate template is added, and
the S1 adapter CI workflow now runs **all** bootstrap suites with a
nonzero-failure gate.

Nine suites pass (**102 PASS / 0 FAIL / 1 LIMITATION**), clean-copy
verification passes, secret scan is 0 hits. No live files touched, no
credentials revoked or rotated, no GitHub posts, no phone contact.
Private v2.2 is unchanged.

- GPT review: comment 7012623369 on PR #97 head `4ef98d4`;
  receipt 7012637830 on Issue #73.
- GPT disposition: `V2_2_ISOLATED_CI=GREEN`,
  `BOOTSTRAP_SECURITY_GATE=BLOCKED`, `C3-C1=NO-GO`, `PR93=BLOCKED`.
  (The gate stays BLOCKED: this round fixes the code/design, it does
  not claim device-side verification or production readiness.)

## 2. P0-B1 — source-embedded secrets (explicit withdrawal)

### Verification of Rev 2 (done first, before fixing)

- `s1/bootstrap.js` carries the `DEPRECATED` header: **YES**
  (header added in Round 3 continued, file kept as a record only).
- `BOOTSTRAP_DESIGN.md` Rev 2 explicitly withdraws the two Rev 1
  statements: **NO — missing.** Rev 2 §0 deprecated the mechanism
  and explained why, but it never quoted the two statements and
  marked them withdrawn. The claim text also still sits inside the
  deprecated `s1/bootstrap.js` body (SAFETY comment) as part of the
  superseded record.

### Fix

`BOOTSTRAP_DESIGN.md` Rev 2.1 addendum (§9.1, appended — Rev 2's body
is not rewritten) quotes and **withdraws both statements explicitly**:

1. *"The token is NEVER sent over the network, NEVER logged, and
   NEVER written to any file except $persistentStore."* — WITHDRAWN.
2. *"token only goes into $persistentStore."* — WITHDRAWN.

Both are not established, because the token was pasted into script
source and the manual gives no guarantee that deleting a script wipes
its cached source, logs, editor autosave, sync copies, backups,
screenshots, or Shortcuts inputs. The 7 tests in
`s1/bootstrap_test.js` only scan the *placeholder template*, not a
real token-populated source or device persistence — acknowledged in
the addendum.

### Defect demonstration (not a gate for the new approach)

`test_bootstrap_candidate_regressions.js` Section D runs the
deprecated script's real logic (same JSON.stringify injection as
`s1/bootstrap_test.js`) with a per-key mock. The tests are labelled
DOCUMENTED DEFECT DEMONSTRATION and PASS when the defect is observed:

- **D1:** DEV write `true` + local-key write `false` → the active DEV
  key IS changed (new token), the local key keeps its old value, the
  owner is told `bootstrap_failed`, no done flag. A partial
  active-key update despite a failure report.
- **D2:** both credential writes `true` + done-marker write `false` →
  `bootstrap_ok` is still emitted, but `sgbridge_bootstrap_done` is
  absent. Success reported without a durable completion marker.

## 3. P0-B2 — partial updates / completion marker failure

### The new approach has no two-key atomic write BY DESIGN

Staging never touches the active keys, so a partial update of ACTIVE
keys is impossible. The regressions prove it
(`test_bootstrap_candidate_regressions.js`, Section R, both templates,
synthetic tokens, VM mock):

| GPT requirement | Test | Result |
|---|---|---|
| (a) DEV write=true, KEY write=false (and vice versa) | R1 | PASS — zero writes to either active key in both directions; the successful staging records `candidate_staged`, the failed one `candidate_commit_unknown` |
| (b) KEY write committed then returns false | R2 | PASS — `candidate_commit_unknown`, exactly 1 write, value on disk, no auto-retry |
| (c) both credentials write=true but DONE marker=false | R3 | PASS — no candidate rewrite (1 write each), candidates on disk, both statuses read as absent (NOT `candidate_staged`), active keys unchanged |
| (d) existing active keys unchanged during candidate staging | R4 | PASS — preloaded OLD DEV + OLD local key values unchanged after both stagings succeed |
| (e) second invocation after ambiguous commit must fail closed, not overwrite a different candidate | R5 (DEV), L5 (local key) | PASS — `candidate_slot_occupied`, zero candidate writes on retry, original candidate preserved |
| (f) no token in logs/source/status | R6 | PASS — all trigger paths, both templates; writes recorded as valueKind only |

Never assume an exception proves storage did not commit: every
write-false case is tested in both flavours (not persisted, and
persisted-then-false). A write that returns `false` but committed is
recorded as `candidate_commit_unknown` and must be resolved by a
separate read-back verification gate, not by an automatic retry.

## 4. P0-B3 — premature active-key mutation (staging vs promotion)

`BOOTSTRAP_DESIGN.md` Rev 2.1 addendum (§9.3) states it explicitly,
supplementing Rev 2 §1.4/§4/§5:

- Staging writes **ONLY candidate keys**
  (`sgbridge_cred_dev_candidate`,
  `sgbridge_cred_localkey_candidate`) plus a non-secret status marker.
  It never writes an active key.
- Promotion (candidate → active) is a **separate approved gate** with
  its own design and approval. It must not happen by changing a
  profile or by changing the server token table ahead of approval.
- **No phone provisioning, no public script change, no server token
  enablement, and no credential revocation until explicit approval.**
  The old exposed token must not be routinely revived.

## 5. Local-key candidate template (new)

`bootstrap_candidate_localkey.template.js` (86 lines, SHA
`187e65c2…938be41`) stages the local key under
`sgbridge_cred_localkey_candidate` using the **same**
intent-parameter mechanism as the PR #101 DEV template: same trigger
rejection (editor / HTTP API / cron / panel / unknown), same 32–256
printable-ASCII validation, same occupied/idempotent logic, strict
write + read-back, status marker
`sgbridge_cred_localkey_bootstrap_status`. The two candidate stagings
are independent single-key operations; there is no two-key atomic
write, and that is BY DESIGN. The local key is only needed for the
direct-HTTP fallback and MCP; v2.2 can run without it for native
`$httpAPI` calls.

Dedicated tests in the regression file (Section L):

| Test | Result |
|---|---|
| L1 valid local-key candidate stages without modifying the active local key | PASS |
| L2 local-key candidate occupied / idempotent | PASS |
| L3 local-key status-marker write false: candidate on disk, status absent, no rewrite | PASS |
| L4 local-key write returns false WITHOUT persisting: unknown, exactly 1 write, nothing on disk, no retry | PASS |
| L5 local-key ambiguous commit then different candidate: occupied, original preserved | PASS |

## 6. CI coverage (evidence gap)

GPT's finding: the bootstrap 7/7 was Muse's isolated record only —
neither PR #97 workflow executed `s1/bootstrap_test.js`.

**Fix:** `.github/workflows/issue73-c3c0-s1-adapter.yml` (SHA
`20f8d820…d2feb`) now has a new step "Bootstrap tests — deprecated
record + candidate staging (synthetic only)" running, from
`docs/surge-bridge-c3c0`:

```
node s1/bootstrap_test.js
node test_bootstrap_candidate_shortcuts.js
node test_bootstrap_candidate_regressions.js
```

plus `node --check` syntax checks for all five bootstrap files. The
nonzero-failure gate: node exits 1 on an uncaught assertion failure,
and the regressions file sets `process.exitCode = 1` when its SUMMARY
reports FAIL > 0. **Verified by a forced-failure negative control:**
a copy of the regressions file with one assertion flipped exited 1.
The workflow's `docs/surge-bridge-c3c0/**` path filter already covers
every one of these files, so no filter change was needed.

**Note:** the 7/7 bootstrap result is isolated-only until this updated
workflow runs on the new PR #97 head; it must not be cited as
CI-backed before then.

## 7. Test results (all against the current private tree)

| Suite | Result |
|---|---|
| v2 regression `test_fixed_v2.js` | **28 PASS / 0 FAIL / 1 LIMITATION** (V23, `RUNTIME_HARD_TIMEOUT_UNPROVEN`, frozen timer — unchanged) |
| Storage failure `test_store_failure.js` | **5/5 PASS** |
| S1 live adapter `test_s1_live_adapter.js` | **10/10 PASS** |
| S1 `s1/test_s1.js` | **11/11 PASS** |
| S3 `s3/test_s3.js` | **14/14 PASS** |
| Bootstrap `s1/bootstrap_test.js` | **7/7 PASS** (deprecated approach — logic record only, not an endorsement) |
| Bootstrap candidate `test_bootstrap_candidate_shortcuts.js` | **13/13 PASS** (PR #101) |
| Candidate regressions `test_bootstrap_candidate_regressions.js` | **14/14 PASS** (new: D1–D2 defect demos, R0–R6, L1–L5) |
| Rollback `rollback_test.sh` | **PASS** |

Total across the nine suites: **102 PASS / 0 FAIL / 1 LIMITATION**
(28+5+10+11+14+7+13+14).

## 8. Clean-copy verification

**PASS.** The full submission set (20 files, §9) was copied to a fresh
`/tmp/c3c0-clean-copy-r3c/` and all nine suites were run from there:
v2 28/0/1, store 5/5, S1 live 10/10, S1 11/11, S3 14/14, bootstrap
7/7, bootstrap candidate 13/13, candidate regressions 14/14,
rollback PASS.

## 9. Files to commit to PR #97 (branch `c3c0-sanitized-v2-review`)

| Target path | SHA-256 (full) | Status |
|---|---|---|
| `docs/surge-bridge-c3c0/bootstrap_candidate_localkey.template.js` | `187e65c242d1c728e30c4a580d6d38d233c89ef57da555c97e1ad3a7f938be41` | NEW |
| `docs/surge-bridge-c3c0/test_bootstrap_candidate_regressions.js` | `4f7337f0ce797dd3bcdd05c210458b72f6aca60944b65c72d9205f48658121b5` | NEW |
| `docs/surge-bridge-c3c0/test_bootstrap_candidate_regressions_out.json` | `4b040b86642d2ab1726e79c435227052499ccb92e3117288d09191bb671ac907` | NEW (14/14 record) |
| `.github/workflows/issue73-c3c0-s1-adapter.yml` | `20f8d820ce14d6e71d69e75cc5cfbada031ef20fb96367f6d26253c1ab9d2feb` | UPDATED (bootstrap CI step) |
| `docs/surge-bridge-c3c0/BOOTSTRAP_DESIGN.md` | `0aa6086e735075b259044f0df6aca5d8323a46d025ddf462eea50d47ba731856` | UPDATED (Rev 2.1 addendum) |
| `docs/surge-bridge-c3c0/C3C0_REPORT.md` | `c3ea7ef18bb33e0d3e0852d9c36c618ec669eb8458643b388449eeb931b4e8a5` | UPDATED (Round 3C addendum) |
| `docs/surge-bridge-c3c0/C3C0_ROUND3C_REPORT.md` | self-referential (recompute at commit time) | NEW |

Unchanged in Round 3C: `bridge_fixed_v2.js` (v2.2,
`8691e962…abfc`, 571 lines), `test_fixed_v2.js`,
`test_store_failure.js`, `test_s1_live_adapter.js`, `simulator.js`,
`s1/test_s1.js`, `s1/bootstrap.js` (DEPRECATED, `fd9076f6…f31a`),
`s1/bootstrap_test.js`, `bootstrap_candidate_shortcuts.template.js`
(`6bfa8838…ca7591`), `test_bootstrap_candidate_shortcuts.js`
(`5bde1810…8931b56`), `s3/*`, `v1/*`,
`ci/issue73-c3c0-v2.yml`, `ci/issue73-s1-shortcuts-bootstrap.yml`,
`SECURITY_GATE_PLAN.md`, `SECURITY_GATE_PLAN_REV1.md`,
`ID_ALLOCATOR_DESIGN.md`, `C3C0_S1_S3_SUMMARY.md`,
`C3C0_ROUND2_REPORT.md`, `C3C0_ROUND3_REPORT.md`,
`C3C0_ROUND3B_REPORT.md`, `C3C0_MINIMAL_PATCH_V2.md`,
`C3C0_V2_V21_DIFF.md`, `C3C0_V2_V22_DIFF.md`, `rollback_test.sh`.

## 10. Secret scan

All 7 new/changed Round 3C files scanned for the real DEV token,
real API key, real URLs, node URIs, script/module paths, and the VPS
IP: **0 hits**. Only placeholders and synthetic `TEST-*` tokens.
(Scan result recorded in the parent's verification step.)

## 11. Gates (unchanged)

`CREDENTIAL_DISTRIBUTION_GATE=BLOCKED`; `C3-C1=NO-GO`;
`PR93_CUTOVER=BLOCKED`; `AUTO_DELETE=OFF`; old command 1795063030
stays `OUTCOME_UNKNOWN`, permanently fenced. PR #98 (GPT oracle 28/28),
PR #99 (saveLedger fix), PR #100 (S1 credential adapter), PR #101
(Shortcuts candidate bootstrap) untouched and not conflated with these
counts. The candidate templates stage only; they do not promote, do
not revoke, and do not authorize any phone action. Real-device gates
(Shortcuts input history, iOS backup, script cache leakage,
device-side log check, other scripts' permissions, candidate key
visibility, token format window, promotion gate, gate 2 server change,
real-device staging run, real-device loading + two cron cycles) remain
open.

## 12. What the parent still needs to do

1. Commit the §9 files to PR #97 (branch
   `c3c0-sanitized-v2-review`) as the Round 3C follow-up.
2. Post the C3-C0 Round 3C receipt to Issue #73 (referencing PR #97's
   new head, the three P0 findings and their fixes, the local-key
   candidate template, the CI coverage change, and the unchanged
   gates).
