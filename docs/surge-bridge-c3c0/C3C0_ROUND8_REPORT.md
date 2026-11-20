# C3-C0 Round 8 Report — absorb GPT PR #108 (durable signed-proof issuer) + PR #109 (atomic token registry)

Date: 2026-11-20. Reply to GPT comments 7025257619 (PR #108) and
7025858660 (PR #109) on Issue #73 (zsh199410/kanyu-app).
Work done in isolation under `~/workspace/pr96-c3c0/` — no live files
touched, no credentials revoked or rotated, no GitHub posts, no phone
contact, no auto-execution of the probe, no registration of PR #105's
verifier as a standalone Surge script, no phone key test, no formal
token promotion, P2/P3 not opened. Private v2.2 unchanged (571 lines,
SHA `8691e962…abfc`).

## 0. Verification gaps — read this first

Three approval-gated fetches could NOT be completed in this round, and
are recorded honestly as PENDING rather than claimed:

- **Diffs:** `pull_request_read get_diff` for PR #108 and PR #109
  (two parallel calls) and a later single `get_check_runs` call all
  timed out waiting for approval (`userConfirmationStatus: timed_out`,
  `approval_expired`). Per instructions they were NOT retried through
  the approval path. The public unauthenticated API is rate-limited
  (60/h on the shared egress IP, remaining 0 at every check; reset
  kept sliding 00:45 → 01:18 → 01:26 → 01:41 → 02:12 UTC), so the
  diffs could not be curled either. **The diff-apply reconstruction
  check is therefore NOT done.** What WAS verified instead: every
  file was fetched directly from the exact PR head branch refs via
  the authenticated connector (`get_file_contents`, approval-free),
  and the head SHAs were verified twice (PR metadata + `list_commits`).
  Both PRs contain ONLY new files (no modifications to existing
  files), and PR #109's base SHA is exactly PR #108's head SHA, so
  the reconstruction is structurally trivial — but it remains
  unperformed until the parent approves one `get_diff` call per PR
  or the public API quota resets.
- **Head CI:** GPT's claimed run numbers are recorded below as
  UNVERIFIED CLAIMS, not facts. `get_check_runs` approval timed out;
  public check-runs API is rate-limited (same sliding window).
- **GPT comments verbatim:** comments 7025257619 / 7025858660 were
  not fetched (`issue_read get_comments` needs the same approval).
  The PR bodies (fetched via approved `pull_request_read get`) carry
  the same substance and are quoted in §1.

Nothing in this report depends on the three pending items being true:
all code claims were verified by reading the fetched head-branch files
and by running the tests locally.

## 1. Sources (verified via approved connector calls)

- PR #108: Draft, open, head `3a824f94425616a4079835be4430ed57de41118c`,
  branch `gpt6-issue73-durable-signed-proof-issuer-20261120`,
  base `gpt6-issue73-webcrypto-atob-f1-20261120` (PR #107 head
  `1a0d7bd5`), 8 commits, 6 files, +522/−0, mergeable clean.
  Head commit (via `list_commits`): `3a824f94…`, "docs(issue73):
  document signed proof issuer, trust boundary and remaining release
  gates", 2026-11-19T23:33:25Z.
  PR body: "C3-C1 P0: integration of durable nonce consumption and
  candidate-bound Ed25519 proof … `signed_proof_issuer.py`: after
  privileged server-side token-record authorization, consumes a
  256-bit nonce durably via PR #106 SQLite ledger BEFORE signing.
  Duplicate, expired, wrong kind/fingerprint, revoked/exposed token
  and storage errors fail closed. Private key is injected by a
  server-owned signer; no actual key or token appears in GitHub …
  16 actual SQLite+Ed25519 signing tests … cross-language Python
  signer → real PR #105 WebCrypto verifier … Pinned isolated CI
  dependency `cryptography==46.0.4` … Not an operational signing
  endpoint."
- PR #109: Draft, open, head `0ee9fb004deda9ada161a2cc09220c070bf0a36f`,
  branch `gpt6-issue73-atomic-token-registry-20261120`,
  base `gpt6-issue73-durable-signed-proof-issuer-20261120` (PR #108
  head `3a824f94`), 8 commits, 7 files, +847/−0, mergeable clean.
  Head commit (via `list_commits`): `0ee9fb00…`, "docs(issue73):
  atomic status/nonce trust boundary, tested scopes and revocation
  limitation", 2026-11-20T00:05:54Z.
  PR body: "Issue #73 P0 — Same-transaction token status + one-time
  nonce gate (synthetic only) … `token_registry_sqlite.py`: single-file
  SQLite persistent token table storing only SHA-256 fingerprints …
  Core P0 safety improvement: `consume_authorized()` checks
  active/unexpired server token record AND consumes the matching
  one-use challenge within one `BEGIN IMMEDIATE` transaction on the
  same database … closes the previous PR#108's detached lookup→consume
  TOCTOU gap … 21 real SQLite adversarial tests and Python-issued
  proof → actual PR#105 WebCrypto verification … Must NOT overclaim:
  single-host demonstration … In-flight signer that consumed a nonce
  before revocation can sign after revocation; require
  drain/quiescence before strict revocation. Old DB snapshot
  restoration can resurrect revoked token and consumed challenge."
- PR #97 baseline (before Round 8): head
  `ecd49d3bded19b5547e7393c31c0d6fb5e1e07b5` (23 commits, 85 files,
  +13799/−0, Draft).

## 2. Head CI — UNVERIFIED (GPT's numbers, not independently checked)

GPT claims (from the task handoff; the #73 comments were not fetched):

- PR #108 head `3a824f94` — issuer 16+7 run 44638700951, v2 regression
  run 44638700998, S1 run 44638700826, all completed/success.
- PR #109 head `0ee9fb00` — Token+Nonce atomic run 44643114016
  (21 tests OK, WebCrypto SUMMARY 7 PASS, 0 FAIL), v2 regression run
  44643114065, S1 run 44643113934, all completed/success.

These run numbers are UNVERIFIED. The `get_check_runs` approval timed
out and the public check-runs API is rate-limited (see §0). The parent
should re-verify them before citing them in the receipt. Local runs
of the same suites all pass (see §6).

## 3. File sets (verified via `get_files`, approved calls)

- PR #108 (6 files, all `added`, +522/−0): `.github/workflows/
  issue73-signed-proof-issuer.yml` (36 lines),
  `docs/surge-bridge-c3c0/SIGNED_PROOF_ISSUER_GATE.md` (77),
  `docs/surge-bridge-c3c0/signed_proof_issuer.py` (121),
  `docs/surge-bridge-c3c0/test_signed_proof_interop_fixture.py` (42),
  `docs/surge-bridge-c3c0/test_signed_proof_issuer.py` (194),
  `docs/surge-bridge-c3c0/test_signed_proof_issuer_webview.js` (52).
- PR #109 (7 files, all `added`, +847/−0): `.github/workflows/
  issue73-atomic-token-registry.yml` (38),
  `docs/surge-bridge-c3c0/ATOMIC_TOKEN_REGISTRY_GATE.md` (110),
  `docs/surge-bridge-c3c0/atomic_signed_proof_issuer.py` (88),
  `docs/surge-bridge-c3c0/test_atomic_token_proof_fixture.py` (56),
  `docs/surge-bridge-c3c0/test_atomic_token_registry.py` (266),
  `docs/surge-bridge-c3c0/test_atomic_token_registry_webview.js` (54),
  `docs/surge-bridge-c3c0/token_registry_sqlite.py` (235).
- PR #109 modifies NO PR #108 file (all 7 are new additions on top of
  PR #108's head). Confirmed by the file list: zero `modified` entries
  in either PR. All 13 files are NEW to PR #97 (no name clashes).

## 4. Absorption (head-branch fetch; diff reconstruction PENDING)

All 13 files fetched from their exact head branch refs via the
authenticated connector and copied into the private tree. SHA-256:

| File | SHA-256 | Status |
|---|---|---|
| `signed_proof_issuer.py` | `a3d5bc5e0b727df0b5090183e1a22aed829564ed224074a3f451802e43b7f128` | NEW (PR #108) |
| `test_signed_proof_issuer.py` | `bcb185abeeb639a21d556d4eba03bcb9aefdd825893aff41aba229471fbc909f` | NEW (PR #108) |
| `test_signed_proof_issuer_out.json` | `7f60a6a82192d134e0a504aae4a04760fa7b980a75f7103fe9eb176596e6c298` | NEW (regenerated, 16/16) |
| `test_signed_proof_interop_fixture.py` | `2ad87ce9bd530c7ab077063899a3511fe1394d157c85d6c2973e8ee5a6625a87` | NEW (PR #108) |
| `test_signed_proof_issuer_webview.js` | `fb1a491f19d8595c7dd74074b77becf234063cfceee660be6ec58e3666b18e77` | NEW (PR #108) |
| `test_signed_proof_issuer_webview_out.json` | `477355ab1f3048657d6fa5dd8c2862973b8ebc104199261b4c88f0d8a62bc512` | NEW (regenerated, 7/7) |
| `SIGNED_PROOF_ISSUER_GATE.md` | `aa3140ba92b08a02c6eba013cebe1f223e6e7b84b524c389bce72e6729299786` | NEW (PR #108) |
| `ci/issue73-signed-proof-issuer.yml` | `b4f067982bfab2790d596642f5e8a827b2b6bbcf1b13a12f50b062ba4ab2b0d4` | NEW (PR #108) |
| `token_registry_sqlite.py` | `75c6a06345b19eac02293e69a6124259346446782be001c0f3b20a28c3c35934` | NEW (PR #109) |
| `atomic_signed_proof_issuer.py` | `a1e04f1554d02d5c9945119cebd5714f73dfcb8236b2303118d147587785fb66` | NEW (PR #109) |
| `test_atomic_token_registry.py` | `246b90a2abd69259e775317f69834a35d5e5d9e98b1a5dc0f1c5ca1b246ec2a0` | NEW (PR #109) |
| `test_atomic_token_registry_out.json` | `73e8bc03ee0b288ecbcd44e0e30a32b70f19edb9b213cba3df682a61a5501ed9` | NEW (regenerated, 21/21) |
| `test_atomic_token_proof_fixture.py` | `1d1e25090c03cda3c21cf556d041c7a2d1ee09fbc373348e93fed81107797beb` | NEW (PR #109) |
| `test_atomic_token_registry_webview.js` | `7869752b189d5549d31184e9dd728be138f1027f330d825ffb33d7ab26d7168c` | NEW (PR #109) |
| `test_atomic_token_registry_webview_out.json` | `81307497387fec048bc8bc9a8cfd93be5bf9463d89c4ffc623ea21353320a89e` | NEW (regenerated, 7/7) |
| `ATOMIC_TOKEN_REGISTRY_GATE.md` | `f5296cd7d32908ba50c62661ba7a36103f0c0a79f38f6fd1f196ef98ad18b229` | NEW (PR #109) |
| `ci/issue73-atomic-token-registry.yml` | `c8b4a42df70d6ad7811083afe1d52536e5defa8c0b4bb098db302556aee13d14` | NEW (PR #109) |

Diff-apply reconstruction: NOT performed (see §0). The fetched files
are the authoritative head-branch contents; the cross-check against
the diff text is pending parent approval or public-API reset.

## 5. Cross-review — issuer (PR #108)

Every claim verified by reading the code:

- `issue()` calls `trusted_token_lookup()` first, validates the record
  via `binding()` (kind/fingerprint/token_id formats), requires
  `token_id == requested_token_id`, `kind == expected_kind`,
  `status == "active"`, `is_exposed_old == False` — all BEFORE
  `ledger.consume()`. `consume()` is called with the TRUSTED record's
  values, not caller-supplied ones, so a caller cannot smuggle a
  different binding. On `was_consumed == False` → `challenge_not_usable`;
  on consume exception → `nonce_commit_unknown` (no sign, no retry).
  Signing happens only after a successful consume; signer failure →
  `signing_failed_after_consume`, nonce stays consumed (verified by
  test_13 + probe P1/P2 pattern). No HTTP/mailbox/node access anywhere
  (0 occurrences of `http`, `mailbox`, `node`, `last_id` in the module
  outside the docstring's "not an endpoint" statement).
- Signing key comes from caller-injected `signer.sign` (constructor
  requires a callable `sign`); no key/token in the repo. Proof dict
  field order is exactly PR #103 `payload()` order (verified against
  local `signed_promotion_proof.js` lines 14–27): purpose, kind, ok,
  fingerprint_matches, token_id, fingerprint, nonce, issued_at,
  expires_at — then `signature` (base64). TTL capped at 60 s
  (`DEFAULT_TTL_MS`), clock validated `0 <= now <= 2**53-1`.
- Test count: 16 `def test_` methods, matching the claim. Each
  denial-before-consume test asserts `ledger.counts() == (1, 0)`;
  signer-crash test asserts `(1, 1)` and re-issue refused.
- Interop JS test reads the REAL `surge_webview_signed_proof.js`
  (PR #105 verifier) from the same directory via `vm.runInNewContext`
  — not a reimplementation. 7 `await test(` calls, matching the claim,
  including an explicit canonical field-order assertion.
- Gate doc (`SIGNED_PROOF_ISSUER_GATE.md`) is honest: isolated server
  reference only; 5 release blockers (no production endpoint, no
  rollback resistance, client replay still possible, no iPhone proof,
  no real promotion/revocation). It states the nonce is stored only as
  a hash in SQLite and the signed response necessarily includes the
  nonce (verifier checks the signature over it).

**Finding F2 (minor, documentation gap — GPT to decide):** PR #108's
own gate doc does NOT disclose the lookup→consume TOCTOU window: a
token revoked after the lookup but before `consume()` still gets a
proof, because the issuer trusts the already-fetched record and never
re-checks. The gap is only named in PR #109's gate doc (as the
motivation for `consume_authorized`). A reader of PR #108 alone could
conclude the issuer is safe against concurrent revocation. Confirmed
real by independent probe P1 (see §7): lookup callback flips a
"revoked" flag as a side effect, `issue()` still returns a proof.
Severity minor: the design is superseded by PR #109; GPT to decide
whether to amend PR #108's doc. GPT's files kept byte-identical.

## 6. Cross-review — atomic registry (PR #109)

Every claim verified by reading the code and by independent probes:

- `consume_authorized()`: ONE `BEGIN IMMEDIATE` transaction — SELECT
  the token row (token_id + kind + fingerprint), require role in
  (`new`, `backup`), status `active`, `issued <= now < expires`;
  then UPDATE the challenge row (nonce hash + kind + candidate_fp +
  token_id + `status='issued'` + challenge time window) in the SAME
  transaction; `changed != 1` → ROLLBACK + None; else COMMIT + record.
  There is no separate lookup→consume gap inside this function
  (verified by code inspection + test_13/15/16 + probe P2).
- Token table stores only SHA-256 fingerprints: `fingerprint()` is
  `sha256(token)` hex; `add()` inserts only the fingerprint.
  Independently verified (probe P3, separate from test_08): raw DB
  bytes contain neither plaintext token, fingerprint present.
- Revocation is permanent: rows are never deleted (0 `DELETE` in the
  module); `revoke()` sets `status='revoked'` + `revoked_ms` under a
  CHECK constraint (`revoked ⟺ revoked_ms NOT NULL`); `activate_backup`
  only touches rows with `role='backup' AND status='standby'`; no code
  path sets a revoked row back to active. Restart retains revocation
  (test_20). `revoke()` requires an already-active, unexpired NON-old
  replacement (test_04/05) — you cannot revoke the new token while
  only the exposed old one remains.
- Backup activation atomically revokes current new AND activates the
  standby backup in one transaction (test_06/13/14); old exposed token
  is never touched by it and never reactivated as fallback.
- Old exposed token: `authorize()` (mock bridge auth) returns 200
  during its ≤48 h window (test_01/02) — that is the "new and
  exposed-old allowed during bounded window" claim, and it refers to
  bridge authentication, NOT proof issuance. `consume_authorized`
  rejects role `exposed_old` outright, and the atomic issuer
  additionally rejects `token_id == exposed_old_token_id`. Test_19
  and probe P4 confirm: old authenticates (200) but
  `consume_authorized` returns None. The distinction is documented
  in the gate doc's state table (exposed_old Proof = NEVER) and
  tested; no discrepancy, recorded here so it is not misread.
- `AtomicSignedProofIssuer.issue()`: session callback must return
  exactly `True` (`is not True` check); session failure → no consume
  (test_10/11 assert counts (1,0)); unknown commit → no sign/retry;
  signer failure → `signature_failed_challenge_burned`, nonce stays
  consumed (test_17). Proof field order matches PR #103 (same dict
  literal order as the PR #108 issuer; verified §5).
- Test counts: 21 `def test_` methods in `test_atomic_token_registry.py`
  and 7 `await test(` calls in `test_atomic_token_registry_webview.js`,
  matching the claims. The JS test loads the REAL PR #105 verifier
  source via `vm` (same pattern as PR #108) and asserts wrong
  nonce/candidate/old-ID/key/expiry rejections.
- Workflows: both pin `cryptography==46.0.4`, `permissions: contents:
  read`, run py_compile + unittest + Node WebCrypto test. Both YAML
  files parse cleanly. The JS tests invoke `python3 <fixture>.py`;
  in CI the dependency is pip-installed into system Python before the
  test steps (install step precedes them in both workflows).
- Gate doc (`ATOMIC_TOKEN_REGISTRY_GATE.md`) is honest and complete:
  single-host demonstration, not a deployed HTTPS `/credential-proof`
  service; old-token window is a maximum, not a recommendation;
  **revocation linearization limitation** stated explicitly (a nonce
  consumed before revocation may complete signing after revocation;
  drain/quiescence required); snapshot restore resurrects revoked
  tokens AND consumed nonces; no device-side protection; no real-device
  crypto_ready evidence; old command stays `OUTCOME_UNKNOWN` fenced.
  All five limitations the task asked to verify are present.

**Finding F3 (trivial, error-label precision — GPT to decide):** both
issuers map pre-validation input errors to "unknown commit" errors,
overstating unknown commit state. A malformed nonce (`'BAD'`) raises
`InvalidChallenge` inside `nonce_hash()` BEFORE any DB write, but
PR #108's issuer reports `nonce_commit_unknown` and PR #109's atomic
issuer reports `atomic_commit_unknown`. Verified at runtime: both cases
return those errors with ledger counts (0, 0) — nothing was written,
so the commit state is known-empty, not unknown. Behavior is
fail-closed (no proof, no state change); only the error label is
imprecise. GPT to decide whether to distinguish input validation from
genuinely ambiguous commits. GPT's files kept byte-identical.

No other discrepancies found. No files modified to fix F2/F3.

## 7. New negative controls — Round 8 cross-review probes

New file `test_r8_cross_review_probes.py`
(SHA `80805eddc50eaeb1f81be6d10a153e8287d7895b0a996f2254297d188698f3c2`,
record `test_r8_cross_review_probes_out.json`
SHA `eb0659f44ec83a7f6fd8aa0c69532ff46d1fe31c2c69915e4699b2515a159bae`):
**4/4 PASS, 0 FAIL.** P1/P2 passing means the documented limitations
are CONFIRMED REAL, not that the code is broken:

- P1 — PR #108 TOCTOU gap is real (supports F2): lookup callback
  flips a "revoked" flag as a side effect; `issue()` still returns a
  proof for the revoked token.
- P2 — PR #109 revocation-linearization limit is real (as documented
  in its gate doc): backup activation inside `sign()` revokes the new
  token after the atomic COMMIT but before signing; the proof is still
  issued, and `authorize()` afterwards returns 403 `token_revoked`.
- P3 — registry DB bytes contain no plaintext token values;
  fingerprints present.
- P4 — exposed_old authorizes at the mock bridge (200) but
  `consume_authorized` returns None for it.

## 8. Local verification (all suites)

| Suite | Result |
|---|---|
| v2 regression `test_fixed_v2.js` | 28 PASS / 0 FAIL / 1 LIMITATION (V23, frozen timer — unchanged) |
| Storage failure `test_store_failure.js` | 5/5 PASS |
| S1 live adapter `test_s1_live_adapter.js` | 10/10 PASS |
| S1 `s1/test_s1.js` | 11/11 PASS |
| S3 `s3/test_s3.js` | 14/14 PASS |
| Bootstrap `s1/bootstrap_test.js` | 7/7 PASS (deprecated approach — logic record only) |
| Bootstrap candidate `test_bootstrap_candidate_shortcuts.js` | 13/13 PASS |
| Candidate regressions `test_bootstrap_candidate_regressions.js` | 14/14 PASS |
| Rollback hermetic `rollback_test.sh` | PASS (positive) + negative control FAIL as expected |
| Provisioning demo `test_provisioning_demo.js` | 5/5 PASS |
| Promotion gate `test_promotion_gate.js` | 17/17 PASS |
| Signed-proof adversarial `test_signed_promotion_proof.js` | 15/15 PASS |
| Negative control `test_signed_proof_negative_control.js` | 5/5 PASS |
| Dual token `test_dual_token.js` | 12/12 PASS |
| WebView probe `test_surge_webview_crypto_probe.js` | 20/20 PASS |
| WebView verifier `test_surge_webview_signed_proof.js` | 19/19 PASS, 0 FAIL, 1 KNOWN LIMITATION |
| Replay negative control `test_webview_replay_negative_control.js` | 4/4 PASS, 0 FAIL, 1 KNOWN LIMITATION |
| Nonce ledger `test_nonce_ledger_sqlite.py` | 21/21 PASS |
| **Issuer `test_signed_proof_issuer.py` (PR #108, new)** | **16/16 PASS** |
| **Issuer interop `test_signed_proof_issuer_webview.js` (PR #108, new)** | **7/7 PASS** |
| **Registry `test_atomic_token_registry.py` (PR #109, new)** | **21/21 PASS** |
| **Registry webview `test_atomic_token_registry_webview.js` (PR #109, new)** | **7/7 PASS** |
| **Cross-review probes `test_r8_cross_review_probes.py` (new, this round)** | **4/4 PASS** |

Total across the twenty-three suites: **275 PASS / 0 FAIL /
1 LIMITATION** (220 + 16 + 7 + 21 + 7 + 4). The 1 LIMITATION is the
v2 V23 frozen-timer item. The verifier, replay-control, and
snapshot-restore limitations are the same underlying stateless-replay /
snapshot-restore theme. Snapshot-restore demo
`test_nonce_snapshot_restore_limitation.py`: 1 PASS, 0 FAIL,
1 KNOWN LIMITATION (separate, unchanged).

Python suites run with `cryptography==46.0.4` installed in an isolated
venv (`/tmp/r8-venv`, system python untouched — the system interpreter
still has no `cryptography` module; the sandbox `pip install` without
`--break-system-packages` was refused per PEP 668, so a venv was used
instead). JS interop tests run with the venv first on PATH so their
embedded `python3 <fixture>.py` finds the dependency.

## 9. CI

New workflow `ci/issue73-c3c0-round8.yml`
(SHA `9d5f803552fff1596b6302c93f69c876217bcc2bb1156f02270913dfec745c9b`):
syntax/compile check + the 4 cross-review probes with a
nonzero-failure gate. GPT's PR #108 workflow
(`issue73-signed-proof-issuer.yml`) and PR #109 workflow
(`issue73-atomic-token-registry.yml`) are absorbed unchanged and cover
all four new GPT test files (issuer 16 + interop 7, registry 21 +
webview 7). All workflows are `contents: read` and isolated.

## 10. Secret scan

All 20 new/changed Round 8 files scanned for the real DEV token, real
API key, real URLs, node URIs, and the VPS IP: **0 hits**. Only
placeholders, synthetic `TEST-*` tokens, and ephemeral test keys
generated at runtime (never written to any file). No `BEGIN PRIVATE
KEY` material in any file. (Both reports scanned after writing: 0 hits
across all 22 files.)

## 11. Clean-copy verification

**PASS.** The full private tree (110 files) was copied to a fresh
`/tmp/c3c0-clean-copy-r8/` and all twenty-three suites plus the
snapshot-restore demo were run from there with identical results
(v2 28/0/1, store 5/5, S1 live 10/10, S1 11/11, S3 14/14, bootstrap
7/7, bootstrap candidate 13/13, candidate regressions 14/14, rollback
PASS, provisioning 5/5, promotion gate 17/17, signed-proof adversarial
15/15, negative control 5/5, dual token 12/12, probe 20/20, verifier
19/0/1, replay control 4/0/1, nonce ledger 21/21, issuer 16/16,
issuer interop 7/7, registry 21/21, registry webview 7/7, probes 4/4,
snapshot demo 1/0/1). v2.2 SHA `8691e962…abfc` in the copy.

## 12. Device evidence scope

Unchanged. `DEVICE_EVIDENCE_ALIGNMENT.md` NOT touched: the owner's
reported device acceptance covers the NODE POOL only; it does NOT
cover Ed25519/WebCrypto support (PR #104 probe NOT run on the real
device, NOT approved for auto-execution; Node VM CI is not device
proof), the two cron fence verifications, the logs/Shortcuts history
privacy check, or the running source script SHA / Surge version / iOS
version. All 15 rows remain UNVERIFIED.
`DEVICE_EVIDENCE_CORRELATION=OPEN`,
`DEVICE_ACCEPTANCE=USER_REPORTED` (node-pool scope only).

## 13. Not built / not done

- The WebView probe has NOT been run on the real device and is NOT
  approved for auto-execution; the PR #105 verifier is a library, NOT
  a standalone Surge script.
- The issuer and registry are single-host server references, NOT a
  deployed signing endpoint: no HTTP service, no authenticated handler
  wiring, no pinned-key distribution, no rollback-resistant epoch,
  no device-side durable single-use consume.
- The PR #108 TOCTOU gap is closed only by adopting PR #109's
  `consume_authorized` — PR #108's issuer alone must not be deployed
  as the authorization path.
- The revocation-linearization limit (P2) means production must
  drain/quiesce in-flight signers before declaring a strict
  no-more-signatures revocation barrier, or build a transactionally
  held signing lease.
- P2/P3 node auto-isolation/deletion were NOT opened.
  `AUTO_DELETE=OFF`.

## 14. Gates (unchanged)

`BOOTSTRAP_SECURITY_GATE=BLOCKED`. `CREDENTIAL_DISTRIBUTION_GATE=BLOCKED`.
`C3-C1=NO-GO`. `PR93_CUTOVER=BLOCKED`. `AUTO_DELETE=OFF`.
`DEVICE_EVIDENCE_CORRELATION=OPEN`. `DEVICE_ACCEPTANCE=USER_REPORTED`
(node-pool scope only). `RELEASE_EVIDENCE_NOT_YET_COMPLETE`.
Old command 1795063030 `OUTCOME_UNKNOWN`, permanently fenced.
Live bridge/server/state, 21 pins, 5 timers, node pool unchanged.

## 15. Files to commit to PR #97 (branch `c3c0-sanitized-v2-review`)

All NEW (no REPLACEs — neither PR modifies an existing file):

| Target path | SHA-256 (short) | Status |
|---|---|---|
| `docs/surge-bridge-c3c0/signed_proof_issuer.py` | `a3d5bc5e…f128` | NEW (PR #108) |
| `docs/surge-bridge-c3c0/test_signed_proof_issuer.py` | `bcb185ab…909f` | NEW (PR #108) |
| `docs/surge-bridge-c3c0/test_signed_proof_issuer_out.json` | `7f60a6a8…c298` | NEW (PR #108, regenerated 16/16) |
| `docs/surge-bridge-c3c0/test_signed_proof_interop_fixture.py` | `2ad87ce9…5a87` | NEW (PR #108) |
| `docs/surge-bridge-c3c0/test_signed_proof_issuer_webview.js` | `fb1a491f…8e77` | NEW (PR #108) |
| `docs/surge-bridge-c3c0/test_signed_proof_issuer_webview_out.json` | `477355ab…c512` | NEW (PR #108, regenerated 7/7) |
| `docs/surge-bridge-c3c0/SIGNED_PROOF_ISSUER_GATE.md` | `aa3140ba…9786` | NEW (PR #108) |
| `docs/surge-bridge-c3c0/token_registry_sqlite.py` | `75c6a063…5934` | NEW (PR #109) |
| `docs/surge-bridge-c3c0/atomic_signed_proof_issuer.py` | `a1e04f15…fb66` | NEW (PR #109) |
| `docs/surge-bridge-c3c0/test_atomic_token_registry.py` | `246b90a2…a3c` | NEW (PR #109) |
| `docs/surge-bridge-c3c0/test_atomic_token_registry_out.json` | `73e8bc03…1ed9` | NEW (PR #109, regenerated 21/21) |
| `docs/surge-bridge-c3c0/test_atomic_token_proof_fixture.py` | `1d1e2509…7beb` | NEW (PR #109) |
| `docs/surge-bridge-c3c0/test_atomic_token_registry_webview.js` | `7869752b…fa75` | NEW (PR #109) |
| `docs/surge-bridge-c3c0/test_atomic_token_registry_webview_out.json` | `81307497…a89e` | NEW (PR #109, regenerated 7/7) |
| `docs/surge-bridge-c3c0/ATOMIC_TOKEN_REGISTRY_GATE.md` | `f5296cd7…b229` | NEW (PR #109) |
| `docs/surge-bridge-c3c0/test_r8_cross_review_probes.py` | `80805edd…f3c2` | NEW (Round 8) |
| `docs/surge-bridge-c3c0/test_r8_cross_review_probes_out.json` | `eb0659f4…9bae` | NEW (Round 8, 4/4) |
| `docs/surge-bridge-c3c0/C3C0_REPORT.md` | UPDATED (Round 8 addendum — recompute at commit time) | UPDATED |
| `docs/surge-bridge-c3c0/C3C0_ROUND8_REPORT.md` | self-referential (recompute at commit time) | NEW (this report) |
| `.github/workflows/issue73-signed-proof-issuer.yml` | `b4f06798…0d4` | NEW (PR #108) |
| `.github/workflows/issue73-atomic-token-registry.yml` | `c8b4a42d…fa75` | NEW (PR #109) |
| `.github/workflows/issue73-c3c0-round8.yml` | `9d5f8035…c9b` | NEW (Round 8 CI) |

## 16. Still pending for the parent (approval-gated, NOT done here)

1. `get_diff` for PR #108 and PR #109 (byte-identical reconstruction
   check) — approval timed out; do NOT claim byte-identical
   reconstruction until performed.
2. `get_check_runs` for PR #108 head `3a824f94` and PR #109 head
   `0ee9fb00` — GPT's claimed run numbers (§2) are unverified.
3. `issue_read get_comments` for #73 comments 7025257619 / 7025858660
   (GPT's handoff texts verbatim).
4. PR #110 (loopback HTTPS credential proof, head `354d2f4`) exists
   and is NOT in this round's scope; the parent decides whether it
   becomes Round 9.
