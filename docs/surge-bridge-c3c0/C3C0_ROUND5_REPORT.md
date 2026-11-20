# C3-C0 Round 5 — PR #103 Signed-Proof Fix + Device Evidence Alignment

## 1. Summary

GPT comment 7024105041 (2026-11-20 06:34 CST, C3-C1
POST-DEVICE-ACCEPTANCE SECURITY GATE): the owner reported
"真机验收通过" in chat, recorded as `DEVICE_ACCEPTANCE=USER_REPORTED`,
but GitHub Issue #73 has no corresponding desensitized device
evidence record, so `DEVICE_EVIDENCE_CORRELATION=OPEN`. GPT's
line-by-line review of the Round 4 `promotion_gate.js` found that
the original `validProof()` trusted any passed
`{fingerprint_matches:true, ok:true}` without authenticating the
issuer's identity, signature, or candidate token fingerprint — and
that a missing candidate with an old `promotion_done` status value
allowing a success return was untrustworthy. GPT directly fixed it
in independent Draft PR #103 (stacked on PR #97 Round 4 HEAD
`13e55c0`, head `4ebac06a55f759fa4b7e747390cbe9df9943a427`, 8 commits,
+352/−43, 6 files, four GitHub Actions all completed/success).

This round absorbs PR #103 byte-identical, verifies the signed-proof
suites locally, adds a 5-case negative control, writes the explicit
Rev 3 withdrawal (verbatim quotes, WITHDRAWN markers), and adds the
desensitized device-evidence alignment checklist (all fields
UNVERIFIED — nothing invented). Fourteen suites pass (**156 PASS /
0 FAIL / 1 LIMITATION**), clean-copy verification passes, secret
scan is 0 hits. No live files touched, no credentials revoked or
rotated, no GitHub posts, no phone contact. Private v2.2 is
unchanged. P2/P3 were NOT opened.

- GPT comment: 7024105041 on Issue #73.
- GPT's PR #103: branch
  `gpt6-issue73-round4-signed-proof-guard-20261120`, head
  `4ebac06a55f759fa4b7e747390cbe9df9943a427`, base =
  `c3c0-sanitized-v2-review` (13e55c0), Draft. CI runs 44629712777
  (Signed-proof 17+15), 44629712924 (Round4 regression),
  44629712994 (C3-C0 full), 44629712849 (S1 true-script) all
  `completed/success`.
- GPT verdict: `SIGNED_PROOF_REFERENCE=CI_GREEN`,
  `DEVICE_ACCEPTANCE=USER_REPORTED`,
  `RELEASE_EVIDENCE_NOT_YET_COMPLETE`; `C3-C1=NO-GO`,
  `PR93=BLOCKED` until production credential and rollback gates
  are met.
- PR #97 (branch `c3c0-sanitized-v2-review`) is at head `13e55c0`
  (17 commits, 54 files, Draft). Round 4 receipt (Rev 4) is on #73
  as comment 7024382875 (posted 2026-11-20 06:48 CST).

## 2. PR #103 absorption (byte-identical verification)

The full diff was read at `/tmp/pr103/pr103.diff` (517 lines). All
six files were fetched from GitHub (raw, ref
`gpt6-issue73-round4-signed-proof-guard-20261120`) and compared
against a reconstruction obtained by applying the diff to the
Round 4 base files with `git apply` (the base files in the private
tree match the Round 4 committed SHAs, verified first):

| File | SHA-256 (full) | Byte-identical |
|---|---|---|
| `promotion_gate.js` | `b12545be12145ce2b27a9a2fa91e9905f00b5a1536945e1568de9a12667b9b90` | YES (`git apply` reconstruction == API fetch) |
| `signed_promotion_proof.js` | `69d3f2fe1bbab16121d6c1f3f7f116126508468e76ba637b9ef62309a26a2145` | YES (same) |
| `test_promotion_gate.js` | `ef5579e2c7c5b75f81e5132953d0c70be6cdb310c5bb1aa69697fec18d6e9364` | YES (same) |
| `test_signed_promotion_proof.js` | `7d0c9981e7d003c18981e8f6915db9a78f784f1db8391a9890c7423ad4b438f5` | YES (same) |
| `PROMOTION_GATE_DESIGN.md` | `8dfd60d43a304f76ed5e135c4b5641585f6d6b43bfb96a06c9c9b0b6c8600797` | YES (same, before Rev 3 addendum) |
| `.github/workflows/issue73-round4-signed-proof.yml` | `8e80f5bc9ce330144b88585539c2fdf07613c932bfdf5a50dff9c42ebbc6459c` | YES (same) |

Copied unmodified into the private tree as:

- `~/workspace/pr96-c3c0/promotion_gate.js` (REPLACES the Round 4 version)
- `~/workspace/pr96-c3c0/signed_promotion_proof.js` (NEW)
- `~/workspace/pr96-c3c0/test_promotion_gate.js` (REPLACES the Round 4 version)
- `~/workspace/pr96-c3c0/test_signed_promotion_proof.js` (NEW)
- `~/workspace/pr96-c3c0/PROMOTION_GATE_DESIGN.md` (REPLACES, then Rev 3 addendum appended — see §4)
- `~/workspace/pr96-c3c0/ci/issue73-round4-signed-proof.yml` (NEW)

**What changed (PR #103):** the old `validProof(proof, oldTokenId)`
that accepted a bare `{ok:true, fingerprint_matches:true}` is
replaced by `validSignedProof()` (`signed_promotion_proof.js`,
Node-only reference): Ed25519 signature over the canonical proof
(`purpose`, `kind`, `ok`, `fingerprint_matches`, `token_id`,
`fingerprint`, `nonce`, `issued_at`, `expires_at`; fixed domain
`purpose = "issue73/credential-promotion/v1"`); fingerprint must
equal SHA-256 of the ACTUAL candidate read from the local store
(timing-safe compare); token id must not be the old exposed id; a
locally generated, cryptographically unpredictable single-use
expected nonce (≥16 chars) must match the signed response; issuance
within 24h, 5-minute future skew, signed expiry in the future and
no later than 24h after issue; the pinned public key is an
independent trust input (never taken from the proof payload) and
must be Ed25519; the key set must be exactly the intended DEV or
local-key candidate/active/status triple. `promote()` now takes
`expectedNonce` and `pinnedPublicKeyPem` and returns
`promotion_invalid_keys` for any other key set. The no-candidate
success path based on the previous `promotion_done` status is
removed: an absent candidate now always returns
`promotion_no_candidate`.

**Old unsigned path GONE (verified by grep):** 0 occurrences of the
bare `proof.fingerprint_matches !== true` check in the new
`promotion_gate.js`; 0 occurrences of the old "leaves the active
token unchanged" guarantee in the gate code; the only
`fingerprint_matches` mention in `promotion_gate.js` is a comment
explaining that the pinned key/nonce must NOT come from the proof
payload. The two remaining `promotion_done` occurrences (lines
178–179) are the legitimate success return after a verified
promotion, not the old no-candidate shortcut. Signature
verification (`validSignedProof` / `crypto.verify`) is present in
`signed_promotion_proof.js` and required by `promotion_gate.js`.

**Known label discrepancy (GPT's file, not a test failure):** the
PR #103 workflow step is named "Independent 14 adversarial
signed-proof cases", but `test_signed_promotion_proof.js`
contains 15 `test()` calls and prints `SUMMARY 15 PASS, 0 FAIL`.
GPT's comment 7024105041 also says 15. The workflow label is off
by one; the test file itself is authoritative.

## 3. Local verification

| Suite | Result |
|---|---|
| Promotion gate, signed-proof `test_promotion_gate.js` | **17/17 PASS** (reference tests now use real Ed25519 signatures generated at test time) |
| Signed-proof adversarial `test_signed_promotion_proof.js` | **15/15 PASS** (self-asserted boolean without signature; wrong candidate; tampered fingerprint/status; wrong signing key; wrong/absent nonce; old token id; missing old-token identity; expired/too-old/future/non-integer; kind/purpose domain separation; malformed signature/missing pinned key; promotion fails without verifiable proof; valid signed proof succeeds; stale `promotion_done` marker cannot fabricate success; wrong candidate never changes active key) |
| Negative control `test_signed_proof_negative_control.js` (NEW, this round) | **5/5 PASS** — unsigned proof, wrong signature, replayed nonce, mismatched candidate fingerprint, expired proof ALL fail closed through `promote()`: `{ ok:false, status:"promotion_invalid_proof" }`, active token unchanged, candidate intact, no write to the active key |

Note on the replayed-nonce case: the reference only proves a proof
whose nonce does not match the CURRENT expected challenge is
rejected. Durable replay rejection (remembering used nonces) is NOT
implemented in the reference — the design addendum states a real
implementation must durably reject a reused challenge. That is an
open item, not a hidden pass.

## 4. Rev 3 withdrawal (verbatim, WITHDRAWN)

Appended to `PROMOTION_GATE_DESIGN.md` as the "Rev 3 addendum —
explicit withdrawals, verbatim (2026-11-20)", following the Round
3C Rev 2.1 pattern. The source of every quote is the Round 4
version of the design doc (SHA `33098ce2…bd73b`) and of
`promotion_gate.js` (SHA `c3fb617d…11dab0`). New design doc SHA:
`a586c99e05d7ea452897ea4ec51f80f46efcb8ec6120ce43f21bbdec70a82d6a`
(365 lines).

- **W1 — Unsigned `/credential-proof` contract (WITHDRAWN):** the
  Round 4 §3 response
  `{ ok: true, fingerprint_matches: true, token_id: "<server token id>",
    issued_at: <unix ms>, expires_at: <unix ms> }` and the acceptance
  rule "The gate accepts the proof ONLY if: `ok === true`,
  `fingerprint_matches === true`, …" — a self-asserted boolean does
  not establish proof.
- **W2 — "Active value definitely unchanged on failure"
  (WITHDRAWN):** the Round 4 §2(d) guarantee "Any failure at any
  step before the read-back verification leaves the active token
  unchanged and the candidate intact (fail-closed)." A write that
  returns `false` may already have committed; an unverified
  read-back leaves the active state UNKNOWN, not "unchanged".
- **W3 — Status-only idempotence shortcut (WITHDRAWN):** the Round 4
  §4 step 1 "if the status key reads `promotion_done` …:
  `promotion_already_active`, OK (no-op, idempotent)". A
  best-effort status marker cannot authenticate the active
  credential; an absent candidate now always returns
  `promotion_no_candidate`.

Findings carried forward: (a) `$persistentStore` has NO documented
delete (already known from Round 4, §5) — production clear
mechanism remains an OPEN ITEM; (b) the no-candidate success path
based on previous status is removed.

## 5. Device evidence alignment (OPEN)

`DEVICE_EVIDENCE_ALIGNMENT.md` (SHA `83971e77…20ee`, NEW): a
checklist/template for the desensitized device evidence record GPT
requires — test time, actual running source script SHA, Surge
TF/iOS version, two cron cycles and old-ID fence results,
logs/Shortcuts history privacy check, plus pins/timers intact and
acceptance scope — 15 rows, each as a boolean/matrix field, **all
UNVERIFIED**. Nothing is invented; every field stays UNVERIFIED
until the owner supplies the observation from the real device with
source + time. The record closes only when all 15 rows are VERIFIED
(or explicitly N/A with a recorded reason). Until then:
`DEVICE_EVIDENCE_CORRELATION=OPEN`,
`RELEASE_EVIDENCE_NOT_YET_COMPLETE`, `C3-C1=NO-GO`,
`PR93_CUTOVER=BLOCKED`.

## 6. CI for Round 5

New workflow `ci/issue73-c3c0-round5.yml` (SHA `c57ffce6…c8b4`):
syntax check for the negative-control test + a step running it with
a nonzero-failure gate. GPT's PR #103 workflow
(`issue73-round4-signed-proof.yml`) is absorbed unchanged and
covers the 17 reference + 15 adversarial tests. Both workflows are
`contents: read` and isolated (synthetic tokens only, no network,
no phone).

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
| Provisioning demo `test_provisioning_demo.js` | **5/5 PASS** |
| Promotion gate signed-proof `test_promotion_gate.js` | **17/17 PASS** (PR #103, real Ed25519 signatures at test time) |
| Signed-proof adversarial `test_signed_promotion_proof.js` | **15/15 PASS** (PR #103, new) |
| Negative control `test_signed_proof_negative_control.js` | **5/5 PASS** (new, this round) |
| Dual token `test_dual_token.js` | **12/12 PASS** |

Total across the fourteen suites: **156 PASS / 0 FAIL / 1 LIMITATION**
(28+5+10+11+14+7+13+14+5+17+15+5+12).

## 8. Clean-copy verification

**PASS.** The full private tree (51 files) was copied to a fresh
`/tmp/c3c0-clean-copy-r5/` and all fourteen suites were run from
there: v2 28/0/1, store 5/5, S1 live 10/10, S1 11/11, S3 14/14,
bootstrap 7/7, bootstrap candidate 13/13, candidate regressions
14/14, rollback positive PASS + negative control FAIL as expected,
provisioning demo 5/5, promotion gate 17/17, signed-proof
adversarial 15/15, negative control 5/5, dual token 12/12. v2.2
SHA in the copy: `8691e962…abfc` (unchanged).

## 9. Files to commit to PR #97 (branch `c3c0-sanitized-v2-review`)

| Target path | SHA-256 (full) | Status |
|---|---|---|
| `docs/surge-bridge-c3c0/promotion_gate.js` | `b12545be12145ce2b27a9a2fa91e9905f00b5a1536945e1568de9a12667b9b90` | UPDATED (PR #103, signed proof) |
| `docs/surge-bridge-c3c0/signed_promotion_proof.js` | `69d3f2fe1bbab16121d6c1f3f7f116126508468e76ba637b9ef62309a26a2145` | NEW (PR #103) |
| `docs/surge-bridge-c3c0/test_promotion_gate.js` | `ef5579e2c7c5b75f81e5132953d0c70be6cdb310c5bb1aa69697fec18d6e9364` | UPDATED (PR #103, Ed25519 at test time) |
| `docs/surge-bridge-c3c0/test_signed_promotion_proof.js` | `7d0c9981e7d003c18981e8f6915db9a78f784f1db8391a9890c7423ad4b438f5` | NEW (PR #103, 15 adversarial) |
| `docs/surge-bridge-c3c0/test_signed_promotion_proof_out.json` | `610c19fc1c1a544b3cf47a4df5e18362188856e49b0eeaf9f46c61907e5c8c40` | NEW (15/15 record) |
| `docs/surge-bridge-c3c0/test_promotion_gate_out.json` | `8b0d500c0b2008a7b084319b98ac2927d9f51b5f1acfd01b0e357def53c17009` | UPDATED (17/17 record, signed-proof run) |
| `docs/surge-bridge-c3c0/test_signed_proof_negative_control.js` | `d15988255109c1fec6c99844bd597542e2dc7ede4da1481221b6bf3670512f59` | NEW (5-case negative control) |
| `docs/surge-bridge-c3c0/test_signed_proof_negative_control_out.json` | `daf3c636b4872d3b98bfd55d5d610092c6e81cb86e332a8802122ba3a36515a4` | NEW (5/5 record) |
| `docs/surge-bridge-c3c0/PROMOTION_GATE_DESIGN.md` | `a586c99e05d7ea452897ea4ec51f80f46efcb8ec6120ce43f21bbdec70a82d6a` | UPDATED (PR #103 + Rev 3 addendum) |
| `docs/surge-bridge-c3c0/DEVICE_EVIDENCE_ALIGNMENT.md` | `83971e77a91720ee946b87ff334380d73ca8fd736b6359ab0f82bf8b863cb0b5` | NEW (checklist, all UNVERIFIED) |
| `.github/workflows/issue73-round4-signed-proof.yml` | `8e80f5bc9ce330144b88585539c2fdf07613c932bfdf5a50dff9c42ebbc6459c` | NEW (PR #103) |
| `.github/workflows/issue73-c3c0-round5.yml` | `c57ffce62ab398a7e70da2b3a89bf80bda1eebdfc322ae3dbc1a7d039123d089` | NEW (negative-control CI) |
| `docs/surge-bridge-c3c0/C3C0_REPORT.md` | `12985cb54f268afa249f546df75354cc5e5a9a8bf4b717f259dbc28806a4d3cb` | UPDATED (Round 5 addendum, 614 lines) |
| `docs/surge-bridge-c3c0/C3C0_ROUND5_REPORT.md` | self-referential (recompute at commit time) | NEW |

Unchanged in Round 5: `bridge_fixed_v2.js` (v2.2,
`8691e962…abfc`, 571 lines), `test_fixed_v2.js`,
`test_store_failure.js`, `test_s1_live_adapter.js`, `simulator.js`,
`s1/test_s1.js`, `s1/bootstrap.js` (DEPRECATED, `fd9076f6…f31a`),
`s1/bootstrap_test.js`, `bootstrap_candidate_shortcuts.template.js`
(`6bfa8838…ca7591`), `test_bootstrap_candidate_shortcuts.js`
(`5bde1810…8931b56`), `bootstrap_candidate_localkey.template.js`
(`187e65c2…938be41`), `test_bootstrap_candidate_regressions.js`
(`4f7337f0…21b5`), `s3/*`, `v1/*`, `rollback_test.sh`
(`5a92efec…102ae6`), `provisioning_demo.js` (`8922afba…db125e`),
`test_provisioning_demo.js` (`1be286c1…432a09d`),
`PROMOTION_GATE_DESIGN.md` prior version (`33098ce2…bd73b`,
superseded), `DUAL_TOKEN_DESIGN.md` (`b4f2875b…31e26`),
`dual_token_server.js` (`0943b04e…d4bc`), `test_dual_token.js`
(`0d110341…8d5f60`), `ci/issue73-c3c0-v2.yml`,
`ci/issue73-c3c0-s1-adapter.yml`,
`ci/issue73-s1-shortcuts-bootstrap.yml`,
`ci/issue73-c3c0-hermetic-rollback.yml`,
`ci/issue73-c3c0-round4.yml`, `BOOTSTRAP_DESIGN.md`,
`SECURITY_GATE_PLAN.md`, `SECURITY_GATE_PLAN_REV1.md`,
`ID_ALLOCATOR_DESIGN.md`, `C3C0_S1_S3_SUMMARY.md`,
`C3C0_ROUND2_REPORT.md`, `C3C0_ROUND3_REPORT.md`,
`C3C0_ROUND3B_REPORT.md`, `C3C0_ROUND3C_REPORT.md`,
`C3C0_ROUND4_REPORT.md`, `C3C0_MINIMAL_PATCH_V2.md`,
`C3C0_V2_V21_DIFF.md`, `C3C0_V2_V22_DIFF.md`.

## 10. Secret scan

All 13 existing new/changed Round 5 files scanned for the real DEV
token, real API key, real URLs, node URIs, and the VPS IP: **0
hits**. Only placeholders and synthetic `TEST-*` tokens. (The
Round 5 report itself is scanned at commit time by the parent.)

## 11. Gates (unchanged)

`CREDENTIAL_DISTRIBUTION_GATE=BLOCKED`; `BOOTSTRAP_SECURITY_GATE=BLOCKED`;
`C3-C1=NO-GO`; `PR93_CUTOVER=BLOCKED`; `AUTO_DELETE=OFF`;
`DEVICE_EVIDENCE_CORRELATION=OPEN`; `DEVICE_ACCEPTANCE=USER_REPORTED`;
`RELEASE_EVIDENCE_NOT_YET_COMPLETE`; old command 1795063030 stays
`OUTCOME_UNKNOWN`, permanently fenced. PR #98 (GPT oracle 28/28),
PR #99 (saveLedger fix), PR #100 (S1 credential adapter), PR #101
(Shortcuts candidate bootstrap), PR #102 (hermetic rollback)
untouched and not conflated with these counts. The signed-proof
reference is Node-only: Surge/iOS runtime support for Node `crypto`
is UNPROVEN, and there is no production pinned key, no real signed
`/credential-proof`, no durable nonce replay rejection, and no real
server token-table persistence yet. P2/P3 node auto-isolation/deletion
were NOT opened.

## 12. What the parent still needs to do

1. Commit the §9 files to PR #97 (branch
   `c3c0-sanitized-v2-review`) as the Round 5 follow-up.
2. Post the C3-C0 Round 5 receipt to Issue #73 (referencing PR #97's
   new head, PR #103 absorbed, the Rev 3 withdrawals, the device
   evidence record still OPEN, and the unchanged gates).
