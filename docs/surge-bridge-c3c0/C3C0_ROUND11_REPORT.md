# C3-C0 Round 11 Report — GPT PR #115 / #116 / #117 Review

**Date:** 2026-11-20 (12:2x–13:0x CST)
**Scope:** READ-ONLY review + synthetic-data isolated testing ONLY. No merge to PR #97 or main. No production deployment. No real credentials, config, or Surge changes. No writes to any GitHub repo/branch/PR/issue.
**Review baseline (per owner ruling, comment 7030306970):** PR #115's default-freeze whole-HTTPS gate is the single review baseline. PR #116 and #117 are components to cross-review, NOT separate gates to stack.
**Gates (unchanged, regardless of test results):** `C3-C1=NO-GO`, `PR93_CUTOVER=BLOCKED`, `AUTO_DELETE=OFF`, `EXTERNAL_EPOCH=BLOCKED`, `PUREJS_DEVICE_PROBE=UNVERIFIED`, `DEVICE_DURABLE_NONCE=UNVERIFIED`, `REMOTE_TLS_ANCHOR_CI!=PRODUCTION`. Old command 1795063030 remains `OUTCOME_UNKNOWN`, never replayed/cleared. 21 pinned nodes, 5 timers unchanged.
**PR #97 context:** head moved 644b44c5 → 6f17f7e8 (docs-only +32 lines, `C3C0_BACKGROUND_CHECKS_RESOLVED.md`, blob a49379bc, owner-verified). Round 11 does NOT modify PR #97.

## 0. Local test-execution limitation (read first)

**Local execution of the PR test suites was NOT performed.** The `git clone` of the three PR branches returned a system execution-risk notice: the cloned content "failed an execution-risk check" and the notice prohibits running, testing, importing, loading, or sourcing it, with no self-granted exceptions even for familiar projects. I complied.

Consequences, stated plainly:
- **I did NOT run any of the three test suites locally.** No local pass/fail counts exist from this review.
- **Test evidence in this report comes from GitHub CI only:** each PR's cited workflow run was independently verified via the Actions API (status, conclusion, head SHA, job name) and the check-runs API on the PR head. The test-method counts were verified by counting `def test_` in each test file (plain text reading) and matching them to the claimed totals and to each workflow's invoked unittest files.
- **Defect probes were STATIC, not executable.** I read every key module line by line, traced every return/raise path, and reasoned about ordering, fail-open, and revival cases. I did NOT execute reproduction probes. Where a probe would have been run, the report names the exact scenario and the static reasoning that resolves it.
- **What this means:** CI green (GitHub-hosted, isolated runners) is the test evidence; it is not a substitute for a local independent re-run. If the owner wants a local re-run, it needs an explicit go-ahead through a route that clears the execution-risk check (the parent agent / owner decides; I do not self-authorize it).

## 1. Per-PR verification table

| PR | Head (verified) | State | Base (verified) | Commits | Files | CI run (verified) | Claimed | Verified |
|---|---|---|---|---|---|---|---|---|
| #115 | `db37bcbedca95f265dbb12922139b492cca1aa4c` | Draft, open, unmerged, mergeable=true | `df77b6987b4fe2bbfe6ea8c97f063cb35454e7e8` (PR #114 head) — first commit b3e8d7a parent MATCH | 10 | 5 (+645/−2) | 44667763636, "Issue73 actual TLS recovery-fenced HTTPS admission (isolated)" run #4, completed/success, head db37bcb, 1 job `real-tls-fence` success | 47/47 (16 new TLS + 14 drain + 17 recovery), 4/4 CI green | **Run success + head match confirmed. Check-runs on head: 4/4 success** (real-tls-fence, isolated ×2, real-script-s1). Method counts: 16+14+17=47 ✓ |
| #116 | `d3eed5b900322f279c80ff2537bc7284ad6c6a6c` | Draft, open, unmerged, mergeable=true | `df77b6987b4fe2bbfe6ea8c97f063cb35454e7e8` (PR #114 head) — first commit 9a5da3a parent MATCH | 18 | 7 (+1290/−3) | 44668342795, "Issue73 monotonic external witness signing fence (isolated)" run #14, completed/success, head d3eed5b, 1 job `isolated-witness` success | 106/106 (18 witness + 14 HTTPS + 21 atomic + 22 orig HTTPS + 14 drain + 17 recovery), 4/4 CI green | **Run success + head match confirmed. Check-runs on head: 4/4 success** (isolated-witness, real-local-tls, real-script-s1, isolated). Method counts: 18+14+21+22+14+17=106 ✓ |
| #117 | `326451aa487a4ffa10081b7472731fafcf68018c` | Draft, open, unmerged, mergeable=true | `db37bcbedca95f265dbb12922139b492cca1aa4c` (PR #115 head) — first commit 84f34ea parent MATCH; compare base..head ahead_by=5, behind_by=0, status=ahead | 5 | 4 (+836/−0) | 44670014342, "Issue73 remote TLS anchor authority and pinned client (isolated)" run #1, completed/success, head 326451a, 1 job `remote-anchor-ci` success | 71/71 (16 new TLS + 16 PR115 + 17 PR114 + 22 orig HTTPS), 3/3 CI green | **Run success + head match confirmed. Check-runs on head: 3/3 success** (real-script-s1, isolated, remote-anchor-ci). Method counts: 16+16+17+22=71 ✓ |

**CI-log caveat:** the per-test "47/47 PASS" / "106/106" / "71/71" strings come from GPT's claim. I verified the run conclusions (success), the head SHAs, the job names, the workflow files (which invoke exactly those unittest files), and the test-method counts in each file. I did **not** retrieve the CI log text (the logs download endpoint requires authentication), so the exact "N/N PASS" line was not re-read from a log. The run-success + method-count + workflow-structure evidence is consistent with the claims, but it is not a log-level re-verification.

## 2. File lists and diff reconstruction

### PR #115 (5 files)
- `docs/surge-bridge-c3c0/staging_recovery_fenced_https.py` (+159, new) — `StagingRecoveryFencedHTTPSService`.
- `docs/surge-bridge-c3c0/test_staging_recovery_fenced_https.py` (+324, new) — 16 tests.
- `docs/surge-bridge-c3c0/RECOVERY_FENCED_HTTPS_GATE.md` (+109, new).
- `docs/surge-bridge-c3c0/staging_issuance_drain.py` (+17/−2, modified) — `IssuanceDrainGate.__init__(start_frozen=False)` + new `freeze_for_reconciliation()`.
- `.github/workflows/issue73-gated-https-recovery.yml` (+36, new).
- **Diff reconstruction: CLEAN.** The drain diff is minimal and exact (two changes, no other edits). Static import check: all imports in the new module (`HTTPSProofService`, `_encode`, `RecoveryNotVerified`, `require_signed_recovery_checkpoint`, `IssuanceDrainGate`, `IssuanceGateClosed`) resolve to definitions present in the branch. No missing imports, no dangling references. Clean stack on PR #114 head.

### PR #116 (7 files)
- `docs/surge-bridge-c3c0/witness_fenced_issuer_reference.py` (+314, new) — `IndependentWitnessTestDouble`, `_WitnessedSigner`, `WitnessedAtomicService`.
- `docs/surge-bridge-c3c0/witnessed_credential_proof_https.py` (+104, new) — `WitnessedHTTPSProofService`.
- `docs/surge-bridge-c3c0/test_witness_fenced_issuer.py` (+335, new) — 18 tests.
- `docs/surge-bridge-c3c0/test_witnessed_https_adapter.py` (+337, new) — 14 tests.
- `docs/surge-bridge-c3c0/credential_proof_https.py` (+22/−3, modified) — adds `_register_nonce` / `_issue_proof` override hooks; `handle` calls them; registration catch adds `RuntimeError`.
- `docs/surge-bridge-c3c0/MONOTONIC_WITNESS_STAGING_GATE.md` (+134, new).
- `.github/workflows/issue73-monotonic-witness.yml` (+44, new).
- **Diff reconstruction: CLEAN.** The `credential_proof_https.py` change is a behavior-preserving refactor: the two new hooks delegate to the exact calls they replace (`self.ledger.register`, `self.issuer.issue`), so the default path is unchanged. Static import check: all imports resolve. No missing imports, no dangling references. Clean stack on PR #114 head, **independent of #115** (does not contain `staging_recovery_fenced_https.py`).

### PR #117 (4 files)
- `docs/surge-bridge-c3c0/remote_anchor_https_staging.py` (+375, new) — `AnchorAuthorityStore`, `LoopbackAnchorTLSServer`, `PinnedAnchorTLSClient`.
- `docs/surge-bridge-c3c0/test_remote_anchor_https_staging.py` (+333, new) — 16 tests.
- `docs/surge-bridge-c3c0/REMOTE_ANCHOR_TLS_STAGING_GATE.md` (+94, new).
- `.github/workflows/issue73-remote-anchor-tls.yml` (+34, new).
- **Diff reconstruction: CLEAN.** No existing file is modified (pure addition). Static import check: all imports resolve, including the test's import of `StagingRecoveryFencedHTTPSService` from PR #115 (present because #117 stacks on #115). Clean stack on PR #115 head (ahead_by=5, behind_by=0).

## 3. Key-module behavior verification (read, not executed)

### PR #115 — `StagingRecoveryFencedHTTPSService`
- Gate starts frozen (`IssuanceDrainGate(start_frozen=True)`). No implicit resume after restart (test_12).
- `handle` wraps the ENTIRE request (auth + nonce registration + issuing) in one `gate.admission()`. A frozen gate returns 503 `issuance_frozen` before any ledger write (test_01).
- 400/401/405 return early WITHOUT freezing — verified safe: in the parent `handle`, 401 (auth) and 400 (request validation) are all pre-mutation. 405 never comes from `handle` (it comes from the HTTP handler's `do_GET`); its presence in the tuple is defensive. Test_05 confirms a 401 writes nothing and does not freeze.
- After any potentially-mutating status (200/403/409/503), `freeze_for_reconciliation()` is called. A 200 proof is returned **only if** `_externally_anchor_mutation()` returns True (a fresh, strictly-increasing, Ed25519-pinned, state-matching signed checkpoint). Any anchor failure/exception → 503 `external_anchor_unknown_frozen` and the proof is discarded (tests 13, 14). No path returns a 200 without a confirmed anchor.
- `open_after_trusted_recovery` (operator-only, not HTTP): requires a 32-byte pinned key; refuses a changed root (`trusted_root_changed_frozen`, test_15); verifies the signed checkpoint against the actual ledger; refuses epoch regression (`<`); resumes only via `gate.reconcile_and_resume(verified)`.
- `guarded_admin_change`: drain → admin mutation → authoritative readback AND a fresh external anchor → only then reopen. Anchor failure during admin leaves the gate frozen and propagates the error (test_10).
- **Known limitation (not new, carried from PR #114):** the verifier trusts the caller-supplied epoch. After a restart (`_verified_epoch is None`), presenting an OLD epoch + OLD checkpoint + OLD (rolled-back) DB would verify and reopen — the epoch-regression check is skipped when no epoch is yet recorded. Test_07 only demonstrates that a checkpoint for the NEW state fails against a rolled-back DB; it does NOT test the full old-epoch+old-checkpoint+old-DB replay. The gate doc is honest about this ("does not implement a genuine independent rollback-resistant high-water service"). No new defect; see §5 O1.

### PR #116 — witness ordering and the same-machine limit
- **`Witness write before signing: CONFIRMED by code.** `_WitnessedSigner.sign` calls `self.witness.advance(before, after_sha, nonce, token_id)` — a durable SQLite `BEGIN IMMEDIATE … COMMIT` — **before** `self.signer.sign(canonical)`. If the witness advance raises, the real signer is never invoked (test_06 in the witness suite asserts `signer.calls == 0` on witness outage; test_07 asserts the witness tombstone is committed before a signer crash, and the state stays consistent).
- The atomic issuer (`AtomicSignedProofIssuer.issue`, PR #109) funnels every signer-path exception — including `WitnessRejected` from the wrapped signer — into `ProofIssuanceError("signature_failed_challenge_burned")`; the nonce stays consumed. The parent `handle` maps that to 403 `proof_not_authorized` (or 503 on a generic exception). No proof escapes on witness failure.
- `_checked_before()` (`require_fresh`) at every register/issue boundary: the business digest must exactly equal the witness head, else `database_rollback_or_unknown_mutation` before any signer/nonce write. A business-only rollback is detected (tests 04, 05 in the witness suite; tests 04, 05 in the HTTPS suite).
- `admin_transition` freezes/drains, applies the SQLite change, commits the witness state + revoked-token tombstone, and reads back exactly before unfreezing. A witness failure during admin leaves the gate frozen (test_12). A revoked token is fenced in the witness `blocked` table; a later `advance` for that token raises `token_fenced_by_witness` (test_18).
- **Same-machine test double: CONFIRMED as a real limitation, and the PR says so itself.** `IndependentWitnessTestDouble` is a local SQLite file. Test_16 (`test_16_restoring_both_db_and_witness_resurrects_nonce_known_limit`) deliberately restores BOTH the business DB and the witness DB from matching old snapshots and shows the same nonce being signed again (`signer.calls == 2`). The test comment and the gate doc both state this is an expected known limitation, not a replay-protection result: "Real independent failure domain MUST make this impossible." A same-machine witness detects a PARTIAL rollback (business only) but cannot survive a correlated full-snapshot rollback. It is a protocol reference, not an independent fault domain.
- **Known limitation (not new):** an already-delivered signed proof remains cryptographically valid after server-side revocation (test_15, documented in the test and gate doc). Revocation must be enforced by the verifier/client nonce gate, not by invalidating the signature. Same class as prior rounds.
- `WitnessedHTTPSProofService` sets `self.issuer = None` after construction, so the parent's unfenced issuer is unreachable through this service; the parent's `handle` only reaches the signer via the overridden `_issue_proof` (virtual dispatch). Verified by reading the parent `handle` — no other path touches `self.issuer`. The nested `gate.admission()` (outer in `handle`, inner in `register`/`issue`) is safe: `threading.Condition` defaults to RLock, and `admission()` only checks `_frozen`/`_admin_active`, so same-thread nesting increments/decrements `_active` without deadlock. If the gate freezes between outer and inner admission, the inner raise (`IssuanceGateClosed`, a `RuntimeError`) is caught by the parent as `nonce_store_unknown` → 503 (test_13 documents this mapping as generic).

### PR #117 — remote anchor CAS and TLS
- **CAS enforcement: CONFIRMED by code.** `AnchorAuthorityStore.advance` requires the caller's `(expected_epoch, expected_digest)` to exactly equal the stored head (under `_lock` + `BEGIN IMMEDIATE`); a mismatch rolls back and raises `stale_or_conflicting_anchor`, mapped by the HTTP handler to **409 `stale_anchor`** with no epoch increment (test_04: same advance twice → 200 then 409, epoch stays 2). A replayed old epoch, a concurrent conflicting advance, and a duplicate all hit the same 409.
- **No HTTP bootstrap/reset/rollback API: CONFIRMED.** Only `GET /head` and `POST /advance` exist; `/bootstrap` and `/reset` return 404 (test_12). Bootstrap is an offline-only method call requiring `authorized_offline=True`, and a repeated bootstrap returns False and does not rewind (tests 14, 15). The epoch persists across a server restart (test_15, SQLite durability).
- **TLS verification: NOT disabled.** The client uses `ssl.create_default_context(cafile=ca_cert_file)` (strict CA + hostname verification; `ProxyHandler({})` disables proxy env). Wrong CA → `URLError`, no writes (test_06). Wrong pinned Ed25519 key → `remote_signature_or_state_mismatch` (test_07). The server requires TLS ≥ 1.2 and loopback-only binding (`staging_public_bind_prohibited`). Wrong bearer → 401 with no state change (test_05). Duplicate JSON keys → 400 with no state write (test_13).
- **`commit_and_fetch_anchor(ledger)` is a genuine PR #115 plugin.** It requires a prior `fetch_head` (`remote_head_unverified` otherwise), requires an actual business state transition (`missing_business_state_transition` if the digest is unchanged), POSTs the CAS advance with the known epoch/digest, and re-verifies the returned record (pinned key + actual ledger digest + strictly-increasing epoch) before returning `(record, epoch)` to PR #115. A lost acknowledgement after a remote commit fails closed (test_10: store epoch advanced to 2, client got 503, gate frozen, explicit reconciliation via fresh `/head` required — no auto-retry). A remote-network-down proof request returns 503 `external_anchor_unknown_frozen` with the nonce burned (test_09).
- **Dual-listener CI on one host: CONFIRMED insufficient for fault-domain independence, and the PR says so itself.** Both listeners run on the same CI host. Test_16 (`test_16_old_remote_anchor_snapshot_can_be_replayed_if_same_domain`) restores the anchor DB from an old snapshot and shows the epoch rewinding to 1; the comment states "Independent durable fault-domain is a REAL prerequisite. This is an expected failure demonstration, NOT security PASS." The gate doc states the same in plain terms ("Do not call this a separate VPS or real external authority").
- **Honest limitation (not new, but worth naming):** the anchor authority is a "dumb" CAS store — it accepts any new state digest from an authenticated client and does not independently inspect the business DB's mutations. A compromised business server holding a valid bearer could advance the anchor with arbitrary digests. The client-side verification (pinned key + actual ledger digest) catches a mismatch, but only if the verifying client itself is not compromised. The gate doc states this explicitly. This is a limitation of the staging reference, not a new defect in the CAS logic.

## 4. Cross-review against the PR #115 baseline

**(a) PR #116 witness-before-signing — YES, enforced.** `_WitnessedSigner.sign` durably commits the witness tombstone (`advance` → `BEGIN IMMEDIATE … COMMIT`) before invoking the Ed25519 signer; a witness failure means zero signer calls (witness-suite test_06) and a 403/503 with the nonce burned. The "second SQLite test double" **is a real limitation**: same machine, same failure/restore domain as the business DB; test_16 proves a correlated rollback of both DBs resurrects a consumed nonce. The PR documents this as an expected negative result. The witness is a protocol reference (CAS + tombstones + ordering), not an independent high-water mark.

**(b) PR #117 CAS — YES, enforced (409 on stale/replay/concurrent).** The store CAS + HTTP 409 mapping are verified in code and covered by test_04. The dual-listener CI on one host **is insufficient to prove fault-domain independence** — test_16 proves an anchor-DB snapshot restore rewinds the epoch, and the gate doc says so. The dual-listener setup proves the PROTOCOL (authenticated TLS + CAS + pinned-key verification + PR #115 integration), not independence.

**(c) Second gate? — #116 as written IS a second, parallel gate; #117 is already a plugin to #115.**
- PR #115's gate: whole-request admission + start-frozen + freeze-after-mutation + external-anchor-before-200. It is the single baseline.
- PR #116's `WitnessedHTTPSProofService` is a **separate service** subclassing the PR #110 base (not the #115 fenced service), with its own gate instance, no freeze-after-200, and no PR #115-style external anchor. Deploying it alongside #115 would stack two different admission objects with different post-proof behavior. It must NOT be deployed as-is alongside #115.
- **Candidate plugins from #116 (not a second gate):** the witness CAS + consumed-nonce SHA-256 tombstone + revoked-token tombstone (`IndependentWitnessTestDouble.advance`), and the witness-before-sign ordering (`_WitnessedSigner`). These can be described as candidate additions INSIDE #115's gate (e.g., a witness advance as an extra pre-signing step, or as the durable record behind `_externally_anchor_mutation`), not as a separate service.
- **#117 is already a plugin to #115:** `PinnedAnchorTLSClient.commit_and_fetch_anchor(ledger)` is the exact callback signature #115's `commit_and_fetch_anchor` parameter requires, and #117's test suite drives #115's `StagingRecoveryFencedHTTPSService` through it. #117 fills #115's missing external authority; it does not add a second admission gate.
- **Net:** one canonical ingress gate (#115). #117 supplies its external authority. #116 supplies witness/tombstone/ordering ideas to be adapted into that gate. Do not deploy #116's service as a parallel endpoint.

**(d) TLS / CA / hostname / same-machine-as-external-mark — CONFIRMED clean.**
- No PR disables TLS verification, bypasses hostname/CA checks, or weakens TLS. #117's client uses a strict default context with the provided CA (hostname verification on); #116/#115 tests use the PR #110 loopback TLS server (TLS ≥ 1.2, loopback-only) with a pinned CA. Wrong-CA tests (test_06 in #117, test_10 in #116) assert rejection with zero writes.
- No PR allows same-machine state to pose as an independent external high-water mark. All three gate docs explicitly deny it, and #116 test_16 / #117 test_16 are negative demonstrations of exactly that failure. `EXTERNAL_EPOCH` remains `BLOCKED` / `NOT_VERIFIED`; a real independent host is still required.

## 5. New defects (F5+ style)

**None found.** The static probes below were run (by code reading and path tracing; no executable probes, per §0).

Probes run (static) and outcomes:
1. **PR #115: 200 without anchor?** Traced every `return` in `handle`. The only 200 return is after `_externally_anchor_mutation() is True`. Anchor exception → 503, proof discarded. **No fail-open.**
2. **PR #115: 400/401/405 without freeze — safe?** All three are pre-mutation in the parent `handle` (auth, then request validation, before registration). Test_05 confirms a 401 writes nothing. 409/403/503 all fall through to `freeze_for_reconciliation()`. **No bypass.**
3. **PR #115: anchor-commit exception escaping `handle`?** `_externally_anchor_mutation` is wrapped in `except Exception` → 503. `guarded_admin_change`'s `confirmed()` lets an anchor exception propagate, but the drain gate catches it, leaves the gate frozen, and re-raises (test_10). **Fail-closed.**
4. **PR #116: signature without witness write?** `_WitnessedSigner.sign` advances the witness before calling the real signer; the atomic issuer converts any witness/sign exception to `ProofIssuanceError` → 403/503, nonce burned. `self.issuer = None` removes the unfenced path. **No bypass.**
5. **PR #116: revoked token reuse?** Revocation inserts a tombstone in the witness `blocked` table; a later `advance` for that token raises `token_fenced_by_witness` (test_18). The business registry also refuses the revoked token (`challenge_or_token_not_usable`, test_11). **Fenced.**
6. **PR #116: consumed nonce replay after business-only rollback?** Detected by `require_fresh` digest mismatch (tests 04, 05). **Blocked.** After BOTH-DB rollback, replay succeeds — **known limitation, test_16, not new.**
7. **PR #117: stale/replayed/concurrent advance?** CAS requires exact `(expected_epoch, expected_digest)` match; mismatch → 409, no increment (test_04). **Enforced.**
8. **PR #117: anchor advance without authentication or with a tampered root?** Bearer required (401, test_05); pinned-key verification against the actual ledger digest (test_07); wrong CA rejected (test_06). **Enforced.**
9. **PR #117: proof on remote-commit-unknown?** The client raises on a lost acknowledgement; PR #115 returns 503 and freezes; reconciliation requires a fresh signed `/head`, no auto-retry (test_10). **Fail-closed.**
10. **PR #117: anchor reset/rewind via HTTP?** No such route (404, test_12); offline re-bootstrap returns False (tests 14, 15). **No reset path.** After anchor-DB snapshot restore, the epoch rewinds — **known limitation, test_16, not new.**

Observations (NOT defects — O-series, fail-closed or documentary):
- **O1 (PR #115, carried P2 from PR #114):** `open_after_trusted_recovery` allows re-presenting the SAME epoch at startup (`<`, not `<=`, and the check is skipped when `_verified_epoch is None` after restart). A full old-epoch + old-checkpoint + old-DB replay after restart would reopen the gate. Test_07 does not cover that combination. This is the already-known "external epoch control plane does not exist" limitation, not a new F5. It is the reason `EXTERNAL_EPOCH` stays `BLOCKED`.
- **O2 (PR #115):** if `open_after_trusted_recovery`'s `verified()` succeeds but `reconcile_and_resume` then raises (e.g., the gate was already open), `_pinned_key`/`_verified_epoch` are already recorded, so a later retry with a DIFFERENT key would raise `trusted_root_changed_frozen` even though the gate never opened on the first attempt. Fail-closed (the gate stays in its prior state), but a failed open can "poison" the pinned key for retries. Minor robustness note; no security impact.
- **O3 (PR #116):** when a request that passed the outer admission is stalled in `_register_nonce` and an admin freeze lands, the inner admission raise is mapped to the generic 503 `nonce_store_unknown` (test_13 documents this mapping). Fail-closed, but the status is misleading for diagnosis (it is a gate freeze, not a nonce-store failure).
- **O4 (PR #117):** the client's `_request` collapses an HTTP 409 (definitive CAS conflict) and a network/timeout failure into the same `remote_anchor_unknown` error. Both are fail-closed (PR #115 returns 503 either way), but the operator loses the distinction between "stale anchor, reconcile" and "network unknown, reconcile" for diagnosis.

## 6. What is and is not verified

**Verified:**
- All three PR heads, Draft/open/unmerged status, bases, commit counts, file lists (exact SHAs, run IDs, counts in §1–§2).
- All three cited CI runs: completed/success on the exact claimed head SHAs, with the claimed job names; check-runs on each head all success (4/4, 4/4, 3/3).
- Test-method counts match the claimed totals (47, 106, 71) and the workflows invoke exactly those unittest files.
- Diff reconstruction: clean stacks (115→#114, 116→#114 independent, 117→#115), no missing imports, no dangling references (static grep check).
- Key-module behavior by line-by-line reading: #115 whole-request admission + anchor-before-200; #116 witness-before-sign + CAS/tombstones; #117 CAS 409 + pinned TLS + `commit_and_fetch_anchor` plugin shape.
- Cross-review conclusions (§4): #116 is a second parallel gate as written (adapt its parts as plugins); #117 is already a #115 plugin; no TLS/CA/hostname bypass; same-machine state is not presented as independent.
- No new F5+ defects (static probes §5).

**NOT verified:**
- Local independent re-runs of any test suite (blocked by the execution-risk notice; see §0). CI is the only test execution evidence.
- CI log text for the exact "N/N PASS" lines (logs endpoint requires authentication; not retrieved).
- Any production behavior. All three PRs are staging-only references on synthetic data. No real VPS, no real tokens, no device, no Surge. The gates in the header remain NO-GO/BLOCKED regardless of these results.
- The real independent external epoch/anchor authority does not exist. `EXTERNAL_EPOCH=BLOCKED` until a genuinely separate failure/backup/administrator domain is provisioned and proven (including a full business-VPS rollback with the witness surviving independently).
