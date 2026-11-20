# C3-C0 Round 10 Report — GPT PR #113 (F3 fix + signer drain) + PR #114 (signed recovery checkpoint)

Date: 2026-11-20. Round 9 baseline: PR #97 head `3708b42`, 29 commits, 136 files, twenty-eight suites **347/0/1**.
GPT comment: 7028731819 (P0 DIRECT IMPLEMENTATION, full text read by the parent).
v2.2 unchanged: 571 lines, SHA `8691e962cba4ab40e961702b7d30090aaaedc29fdbe46b63a257878f9f90abfc`.

## 1. PR heads (verified via authenticated connector)

| PR | Head | Branch | Base | Commits | Diff | State |
|---|---|---|---|---|---|---|
| #113 | `60a7d14ba18e72c4e0459368ee0aae81192812d0` | `gpt6-issue73-f3-drain-rollback-fences-20261120` | PR #112 head `849e5a8c` | 7 | +677/−2, 7 files | open, Draft |
| #114 | `df77b6987b4fe2bbfe6ea8c97f063cb35454e7e8` | `gpt6-issue73-signed-recovery-checkpoint-20261120` | PR #113 head `60a7d14` | 4 | +423/−0, 4 files | open, Draft |

Both heads match GPT's claimed SHAs exactly. Neither head moved during this round.

## 2. Fetched files (SHA-256, from the exact head-branch refs via the authenticated connector)

### PR #113 (7 files)

| File | Status | SHA-256 | Blob SHA (connector) |
|---|---|---|---|
| `docs/surge-bridge-c3c0/signed_proof_issuer.py` | MODIFIED (was PR #108) | `5087f2378e0b0fa98a23257a89b47cee302d44b5fdae92c13c23a61759bb17a8` | `1c7d18c5…` |
| `docs/surge-bridge-c3c0/atomic_signed_proof_issuer.py` | MODIFIED (was PR #109) | `9486291988e72519ba5be740e7ce52e2f27a5f4ee7dbcfd63bb6a174de6e8125` | `07155c9e…` |
| `docs/surge-bridge-c3c0/staging_issuance_drain.py` | NEW | `9c3ed1aece82ced36003148b4f3333652b5c78632fa76ece561f078f3e847418` | `ea8b5a1f…` |
| `docs/surge-bridge-c3c0/test_f3_proof_error_classification.py` | NEW | `69cd0490026f4dfbd87b6695d560ecc299ec35069d5fc66f145d5ce1159ab641` | `96e7ec71…` |
| `docs/surge-bridge-c3c0/test_staging_issuance_drain.py` | NEW | `85de71eb098546f39849a0325010ea38aac61f6292b4c4f1859a41ef3c9ee894` | `cf7739bd…` |
| `docs/surge-bridge-c3c0/F3_DRAIN_STAGING_GATE.md` | NEW | `1ba25c19a110820b431eb9205bf405d41dfb1fc0407d446fa6c3a16b7b47ccf7` | `9360be35…` |
| `.github/workflows/issue73-f3-drain-staging.yml` | NEW | `2c3eba888b9ae24a6e933d8ec3505b5e6f814c674eae5a0109e9bf8ba604471e` | `67228b46…` |

### PR #114 (4 files, all new)

| File | Status | SHA-256 | Blob SHA (connector) |
|---|---|---|---|
| `docs/surge-bridge-c3c0/recovery_signed_checkpoint.py` | NEW | `bf44d086cc31ca6d06d214979c3b6bef0a3de040cbbdb2f0b23c653c65cffb89` | `26ce0df3…` |
| `docs/surge-bridge-c3c0/test_recovery_signed_checkpoint.py` | NEW | `f0aa34fcb8e3a802d9a0a1937f783794572a91a040586e54afe6134fb62022e7` | `ed4c5c7f…` |
| `docs/surge-bridge-c3c0/EXTERNAL_RECOVERY_CHECKPOINT_GATE.md` | NEW | `e7f880d05d7ceedaafff8cb321de509208f4ceac3fec27a700c6e33d0b07ab2c` | `77addf1f…` |
| `.github/workflows/issue73-recovery-checkpoint.yml` | NEW | `11571d28369026374cd6d3da782588546831464634f6299d9c8ccd084ccd396d` | `7f1ef201…` |

### Round 10 cross-review probes (mine, not GPT's)

| File | SHA-256 |
|---|---|
| `test_r10_cross_review_probes.py` | `e70e0cb2c5cc4f215b6a8be213dad034d1d8d76268b30e946243b071f5895d49` |
| `test_r10_cross_review_probes_out.json` | `7ce142545b3abb32708dc2676864b0fa3c0da5edc9df82037e5ffa617fa3065d` |

## 3. Three-way diff review — the two MODIFIED files (required before overwrite)

PR #113 modifies `signed_proof_issuer.py` and `atomic_signed_proof_issuer.py`, which Round 9 already absorbed (PR #108 / PR #109 versions). PR #110/#111/#112 did **not** touch either file (verified via the public files API for all three PRs), so the Round 9 workspace copies are exactly the PR #112 head (PR #113 base) versions. The three-way review (Round 9 copy vs PR #113 version) shows the changes are **exactly** the F3 fix and nothing else:

- `signed_proof_issuer.py` (121 → 128 lines; PR diff +8/−1, matches): import adds `InvalidChallenge, nonce_hash`; before the trusted lookup, `nonce_hash(nonce)` is validated and `InvalidChallenge` maps to `ProofIssuanceError("invalid_challenge")`. No other change.
- `atomic_signed_proof_issuer.py` (88 → 93 lines; PR diff +6/−1, matches): import adds `InvalidChallenge, nonce_hash`; `nonce_hash(nonce)` is called at the start of the preflight try (before `binding()` and session lookup); a new `except InvalidChallenge` handler maps to `ProofIssuanceError("invalid_proof_input")`. No other change.
- Dependency verified: both files import `InvalidChallenge` and `nonce_hash` from `nonce_ledger_sqlite`, which the PR #106 workspace copy already exports. `nonce_hash` is real validation (43-char base64url, 32-byte decode, canonical re-encode equality; raises `InvalidChallenge("invalid_nonce")` / `("noncanonical_nonce")`). Probes confirmed `'BAD'`, `''`, `'zz'`, `None`, `123` all raise `InvalidChallenge`.
- **Decision: workspace copies UPDATED to the PR #113 versions** (SHAs `5087f237…`, `94862919…`). The Round 9 copies are preserved at `/tmp/signed_proof_issuer.r108.py` and `/tmp/atomic_signed_proof_issuer.r109.py`.

## 4. Test results (all run locally, isolated venv /tmp/r9-venv, cryptography==46.0.4)

| Suite | Command | Result |
|---|---|---|
| F3 classification (PR #113) | `/tmp/r9-venv/bin/python -W error::ResourceWarning -m unittest test_f3_proof_error_classification.py` | **12/12 PASS** (`Ran 12 tests … OK`) |
| Staging drain (PR #113) | `… -m unittest test_staging_issuance_drain.py` | **14/14 PASS** (`Ran 14 tests … OK`) |
| Recovery checkpoint (PR #114) | `… -m unittest test_recovery_signed_checkpoint.py` | **17/17 PASS** (`Ran 17 tests … OK`) |
| Cross-review probes R10 (mine) | `… -m unittest test_r10_cross_review_probes.py` | **4/4 PASS** |
| Issuer regression (PR #113 version) | `… -m unittest test_signed_proof_issuer.py` | 16/16 PASS |
| Registry regression | `… -m unittest test_atomic_token_registry.py` | 21/21 PASS |
| HTTPS regression | `… -m unittest test_credential_proof_https.py` | 22/22 PASS (11.4s) |
| Issuer interop (R8) | `PATH=/tmp/r9-venv/bin:$PATH node test_signed_proof_issuer_webview.js` | 7/7 PASS |
| Registry webview (R8) | `PATH=/tmp/r9-venv/bin:$PATH node test_atomic_token_registry_webview.js` | 7/7 PASS |
| Nonce ledger (R7) | `… -m unittest test_nonce_ledger_sqlite.py` | 21/21 PASS |
| WebView probe (R9) | `node test_surge_webview_crypto_probe.js` | 22/22 PASS |
| Snapshot demo (R7) | `python3 test_nonce_snapshot_restore_limitation.py` | 1/0/1 (separate) |

**Totals: thirty-two suites, 394 PASS / 0 FAIL / 1 LIMITATION** (v2 V23 frozen timer; the PureJS stateless-replay limitation is the same underlying theme as the verifier/replay-control limitations). Delta vs Round 9 (347): +47 (F3 12 + drain 14 + recovery 17 + R10 probes 4). Clean-copy verification PASS (fresh `/tmp/c3c0-clean-copy-r10/`, 161 files, all 32 suites + bundle `--check` + rollback hermetic + snapshot demo; see §7).

## 5. Head CI verification (check-runs API, NOT taken on trust)

| PR head | Checks | Result |
|---|---|---|
| #113 `60a7d14` | 5 | **5/5 success** — `isolated` run 44662401612 (the dedicated F3+drain workflow, identical to GPT's claimed #44662401612), `token-atomic` run 44662401573, `real-script-s1` run 44662401498, `isolated` run 44662401610, `proof-issuer` run 44662401500. (The two `isolated` jobs share a job name across workflows; the run IDs are exact. The dedicated run 44662401612 matches GPT's claim.) |
| #114 `df77b69` | 3 | **3/3 success** — `synthetic-recovery` run 44662956632 (the dedicated recovery workflow, identical to GPT's claimed #44662956632), `real-script-s1` run 44662956570, `isolated` run 44662956575. |

## 6. Diff-apply reconstruction (COMPLETE)

Public API diff endpoint (healthy this round: 58/60 remaining at first check). `git apply` of each PR's diff onto its base state reproduces byte-identical files:

- PR #113: **7/7 MATCH** — diff applied onto the PR #112 base state (the two issuer files at their PR #108/#109 versions, verified identical to the PR #112 head versions since #110/#111/#112 never touched them; the other 5 files are new). All 7 reconstructed SHAs match the fetched files.
- PR #114: **4/4 MATCH** — diff applied onto an empty tree (all 4 files are new). All 4 reconstructed SHAs match.

## 7. Clean-copy verification

Fresh `/tmp/c3c0-clean-copy-r10/` (161 files, full workspace copy minus `__pycache__`). All 32 suites re-run from the clean copy: **394 PASS / 0 FAIL / 1 LIMITATION** (v2 V23 frozen timer). Bundle `--check` PASS (`BUNDLE EXACT SOURCE MATCH 85914`). Rollback hermetic PASS (positive + negative control FAIL as expected). Snapshot demo 1/0/1 (separate). No failing suite. (Runner note: two suites print `SUMMARY N PASS M FAIL` without a comma and the v2 suite reports `V2: PASS=28 FAIL=0 LIMITATION=1`; the runner was corrected to parse both forms — the counts above use the suites' own test counts, consistent with Rounds 8–9.)

## 8. Cross-review (independent verification, not a re-run of GPT's suites)

### F3 fix — verified real (probe P3)
Same ledger, same malformed nonce `'BAD'`: the PR #108 issuer raises `nonce_commit_unknown` **after** 1 token lookup; the PR #113 issuer raises `invalid_challenge` with **0** lookups and 0 signer calls, ledger unchanged (1,0). The fix is real, not just a label change in the tests.

### Drain gate — verified by code + probes
- Freeze-before-drain: `_freeze_and_drain` sets `_frozen=True` and `_admin_active=True` **before** awaiting active issuers, so no new admission can start after the barrier. Confirmed by test_04 (new admission raises `issuance_frozen` while a prior issuance is held) and by code reading.
- Timeout / failed action / exception / failed read-back all leave the gate frozen (`_admin_active=False`, `_frozen` stays True); only `reconcile_and_resume` with a literal-`True` verification reopens it. Confirmed by tests 05–09, 12, 14 and by code reading.
- Cross-process detection verified by probe P1: a forked child calling `status()` is refused with `cross_process_unverified` (the gate records `_owner_pid` at construction and checks it on every entry point, including via `admission()`/`issue()`).
- Single-process limitation is honestly stated in the module docstring and gate doc: the original issuer/registry remain directly callable, so the gate only works if **every** handler routes through it; a crash/restart resets it; multiple workers/hosts have no shared barrier.

### Recovery checkpoint — verified by code + probes
- The verifier genuinely requires the independent monotonic epoch: `record["epoch"]` must equal `trusted_external_epoch` exactly (type `int`, 1..2^53−1); an old signed checkpoint against a newer external epoch is rejected at `external_epoch_mismatch` **before** the signature check. Confirmed by test_04/test_08 and by code reading.
- Signature covers the canonical `(purpose, epoch, state_sha256)`; digest tamper and signature mutation are rejected (`checkpoint_signature_invalid`); missing table fails closed (`state_read_unknown`); extra fields rejected (`checkpoint_shape_invalid`); malformed trust root rejected (`trusted_key_unavailable`); false/missing epoch rejected (`external_epoch_unavailable`).
- The digest covers the full logical state (all token_registry rows + all challenge rows) in a single SQLite read transaction (`BEGIN`/`COMMIT` on a fresh connection; `_connect()` uses `isolation_level=None`, so the explicit transaction is safe). Determinism across fresh connections confirmed by probe P4. Test_17 confirms the digest is sensitive to the full state, not just counts (same (1,1) counts, different token status → mismatch).
- **Confirmed limitation (P2, honestly documented — NOT a code defect):** the verifier trusts the epoch the **caller** supplies. Probe P2 shows that if the epoch is rolled back together with the DB, the old checkpoint verifies against the restored old DB (old state + old epoch 1 → accepted). The gate doc states this explicitly ("Signed checkpoint integrity alone does not stop replay of an old signed checkpoint if the independent epoch is also rolled back"). The external monotonic control plane is the actual security property, and it is **not provisioned** (`EXTERNAL_EPOCH_PROVISIONED=NO_EVIDENCE`). This is the same gap the VPS staging demonstration exposed (old DB resurrects a consumed nonce → 200).

### Findings: NONE (no F5+ code defects)
All claimed behaviors were independently verified. Two record notes (not GPT defects):
- **O2 (behavior note):** in the atomic issuer, `binding()` raising `InvalidChallenge` (invalid kind/fingerprint/token_id) is now caught by the new `except InvalidChallenge` handler and mapped to `invalid_proof_input`, where it previously fell through to the generic handler as `preflight_unknown`. GPT's tests 05/06/07 assert this as intended. Fail-closed, more precise. Not a defect.
- **P2 (confirmed limitation):** see above — the epoch-rollback limitation is real and honestly documented; the verifier is a detection endpoint, not a provisioned external anchor.

PR #113 modifies 2 PR #112 files (the two issuers — exactly the F3 fix, §3) and adds 5 new files; PR #114 modifies no PR #113 file (all 4 new). Neither PR touches any PR #97 file. GPT's files kept byte-identical (except the two issuer files, which were updated to the PR #113 versions per the three-way review in §3).

## 9. Workflows (all `permissions: contents: read`)

- `.github/workflows/issue73-f3-drain-staging.yml`: pins `cryptography==46.0.4`, Python 3.12, runs F3 (12) + drain (14) + issuer (16) + registry (21) regressions with `-W error::ResourceWarning`.
- `.github/workflows/issue73-recovery-checkpoint.yml`: pins `cryptography==46.0.4`, Python 3.12, runs the recovery suite (17) with `-W error::ResourceWarning`.

## 10. Secret scan

All 13 new/changed Round 10 files scanned CLEAN (0 real-token/key/URL/IP matches; my own re-scan confirmed across all 13 files, including the two updated issuers and the probe files). Only `TEST-*` synthetic tokens, public test vectors, and temporary test keys generated at runtime (never committed). The F3 gate doc contains the placeholder string `TEST-ACTUAL-IP` (a literal placeholder, not an address). No real credential or private key is committed.

## 11. Commit list for PR #97 (for the parent to submit via browser)

Batch 1 — `docs/surge-bridge-c3c0/` (13 files):
- `signed_proof_issuer.py` — UPDATED (PR #113 version, SHA `5087f237…`)
- `atomic_signed_proof_issuer.py` — UPDATED (PR #113 version, SHA `94862919…`)
- `staging_issuance_drain.py` — NEW (SHA `9c3ed1ae…`)
- `test_f3_proof_error_classification.py` — NEW (SHA `69cd0490…`)
- `test_staging_issuance_drain.py` — NEW (SHA `85de71eb…`)
- `F3_DRAIN_STAGING_GATE.md` — NEW (SHA `1ba25c19…`)
- `recovery_signed_checkpoint.py` — NEW (SHA `bf44d086…`)
- `test_recovery_signed_checkpoint.py` — NEW (SHA `f0aa34fc…`)
- `EXTERNAL_RECOVERY_CHECKPOINT_GATE.md` — NEW (SHA `e7f880d0…`)
- `test_r10_cross_review_probes.py` — NEW (SHA `e70e0cb2…`)
- `test_r10_cross_review_probes_out.json` — NEW (SHA `7ce14254…`)
- `C3C0_REPORT.md` — UPDATED (Round 10 addendum; SHA to be computed after append)
- `C3C0_ROUND10_REPORT.md` — NEW (this file)

Batch 2 — `.github/workflows/` (2 files):
- `issue73-f3-drain-staging.yml` — NEW (SHA `2c3eba88…`)
- `issue73-recovery-checkpoint.yml` — NEW (SHA `11571d28…`)

Total: 15 files (2 UPDATED + 13 NEW). Commit message (both batches): `C3-C0 Round 10: absorb PR #113 F3 fix + signer drain + PR #114 recovery checkpoint, no F5+`.

## 12. Gates (unchanged)

`BOOTSTRAP_SECURITY_GATE=BLOCKED`. `CREDENTIAL_DISTRIBUTION_GATE=BLOCKED`. `C3-C1=NO-GO`. `PR93_CUTOVER=BLOCKED`. `AUTO_DELETE=OFF`. `DEVICE_EVIDENCE_CORRELATION=OPEN`. `DEVICE_ACCEPTANCE=USER_REPORTED` (node-pool scope only). `PUREJS_DEVICE_PROBE=UNVERIFIED`. `REAL_PRIVATE_HTTPS=NOT_DEPLOYED`. `EXTERNAL_EPOCH_PROVISIONED=NO_EVIDENCE`. Old command 1795063030 `OUTCOME_UNKNOWN`, fenced.

## 13. What is NOT done (for the parent / GPT)

- The external monotonic epoch / control plane does **not** exist — PR #114 is a read/verify endpoint only. Staging cannot claim rollback protection until a separate failure domain, exclusive signing/epoch authority, and a deployment graph with recovery journal are proven.
- The drain gate is single-process and in-memory; the VPS staging HTTP handler must prove **every** route is wrapped by the same gate instance, plus a durable frozen state and crash recovery, before it can be called a revocation barrier.
- No device-side one-time consume, no production TLS/domain/pinned-key distribution, no production deployment. P2/P3 NOT opened.
