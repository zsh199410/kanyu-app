# C3-C0 Round 6 — PR #104/#105 WebView Crypto Cross-Review

## 1. Summary

GPT comment 7024399594 (2026-11-20 06:49 CST, GPT-6 DIRECT P0
IMPLEMENTATION | WebView crypto + signed proof): at the owner's
request to "continue the task", GPT wrote and submitted two
isolated Draft PRs, without modifying Muse's branch, main, the
real device, the production VPS, tokens, mailbox state, or the
node pool.

- PR #104 (branch
  `gpt6-issue73-surge-webcrypto-probe-20261120`, head
  `44ad19244628bc5e5c8fefeeef342019934cb1c3`, 6 commits, 4 files,
  +415/−0, title "test(issue73): iOS Surge WebView
  Ed25519/SHA-256 capability gate (no secrets)"): a Surge
  WebView crypto capability probe (RFC 8032 vectors, SHA-256,
  TextEncoder, secure random), 18 VM tests, three CIs
  completed/success on head (专项 44631205990, C3-C0
  44631205964, S1 44631205869).
- PR #105 (branch
  `gpt6-issue73-surge-webcrypto-proof-verifier-20261120`, head
  `09db336899b2e253c76303859ead1d8d5b57e27b`, 4 commits, 4
  files, +400/−0, title "security(issue73): browser WebCrypto
  Ed25519 candidate proof verifier (offline)"): a WebCrypto
  Ed25519 candidate-proof verifier library (NOT a standalone
  Surge script), 19 PASS / 0 FAIL / 1 named limitation,
  three CIs completed/success on head (专项 44631915125,
  C3-C0 44631915120, S1 44631915000).

Technical basis (GPT): Surge official docs confirm
`engine=webview` supports WebAPIs including `crypto` and must
be explicitly configured, BUT do NOT guarantee Ed25519 is
actually available on the phone's iOS/WebKit
(manual.nssurge.com/scripting/overview.html,
manual.nssurge.com/scripting/api.html). The CIs above are only
Node VM simulations, not device proof.

This round absorbs PR #104 and PR #105 byte-identical, runs
both test suites locally, cross-reviews the source line by
line, adds a 4-case replay negative control, and records the
device-evidence scope clarification (the owner's reported
device acceptance covers the NODE POOL only — it does NOT
cover Ed25519/WebCrypto support). Seventeen suites pass
(**197 PASS / 0 FAIL / 1 LIMITATION**, plus 2 named
replay limitations inside their suites), clean-copy
verification passes, secret scan is 0 hits. No live files
touched, no credentials revoked or rotated, no GitHub posts,
no phone contact, no auto-execution of the probe, no
registration of PR #105 as a standalone Surge script, no
phone key test, no formal token promotion. Private v2.2 is
unchanged. P2/P3 were NOT opened.

- GPT comment: 7024399594 on Issue #73.
- PR #97 (branch `c3c0-sanitized-v2-review`) is at head
  `c6ff549` (19 commits, 63 files, Draft, 7/7 checks green
  on head). Round 5 receipt (Rev 5) is on #73 as comment
  7024659514 (posted 2026-11-20 07:02 CST).
- PR #93 timer publisher isolated build is done separately
  (55/55 PASS, `~/workspace/pr93-publisher/`, no production
  changes); PR #93 head unchanged (`28c5f4b`),
  `mergeable: false` (dirty vs base) — a separate merge
  blocker.

## 2. PR #104 + PR #105 absorption (byte-identical verification)

Both diffs were read in full (439 + 424 lines). All eight
files were fetched from GitHub (raw, refs
`gpt6-issue73-surge-webcrypto-probe-20261120` and
`gpt6-issue73-surge-webcrypto-proof-verifier-20261120`) and
compared against a reconstruction obtained by applying each
diff to an empty tree with `git apply` — **byte-identical,
all eight**:

| File | SHA-256 (full) | Byte-identical |
|---|---|---|
| `surge_webview_crypto_probe.template.js` | `6b76f8efa1667f671aca443d41dac7b02b472ece12483c5d58496d1dbe8e5eb4` | YES (`git apply` reconstruction == API fetch) |
| `test_surge_webview_crypto_probe.js` | `fa275f32cb89d35de01f7de8879a5f4e5341c5e438118d67aeae0610f2de4501` | YES (same) |
| `SURGE_WEBVIEW_CRYPTO_GATE.md` | `b34a32ddd42cf0c58f875dcdda678713c3ba6846fe4fd2fd6baa1a0961fa0de4` | YES (same) |
| `ci/issue73-surge-webcrypto-probe.yml` | `97354e7836f7aa9b09e14843894fb32d946d0af4e57ee7077eac1959171a2e14` | YES (same) |
| `surge_webview_signed_proof.js` | `02b18dbdb7f2062e96ac0f2e47c14dfc6d729f987d78a7e49193b8c5c97b3bfe` | YES (same) |
| `test_surge_webview_signed_proof.js` | `21118d7db74d1deb109f0066ff1118eb0f9582149aa6bf24a0cd14c7e5774c8c` | YES (same) |
| `SURGE_WEBVIEW_SIGNED_PROOF.md` | `0a0bfbd9ecd5f32c4fa4de16362295a3577176627ee100da586ca891e823c8a3` | YES (same) |
| `ci/issue73-webview-signed-proof.yml` | `bf8e0a06fcfe3cf69068670ff55a4b75809e3ce1073e3d4ef0a13d611743fa75` | YES (same) |

Copied unmodified into the private tree as:

- `~/workspace/pr96-c3c0/surge_webview_crypto_probe.template.js` (NEW)
- `~/workspace/pr96-c3c0/test_surge_webview_crypto_probe.js` (NEW)
- `~/workspace/pr96-c3c0/SURGE_WEBVIEW_CRYPTO_GATE.md` (NEW)
- `~/workspace/pr96-c3c0/ci/issue73-surge-webcrypto-probe.yml` (NEW)
- `~/workspace/pr96-c3c0/surge_webview_signed_proof.js` (NEW)
- `~/workspace/pr96-c3c0/test_surge_webview_signed_proof.js` (NEW)
- `~/workspace/pr96-c3c0/SURGE_WEBVIEW_SIGNED_PROOF.md` (NEW)
- `~/workspace/pr96-c3c0/ci/issue73-webview-signed-proof.yml` (NEW)

Head CI re-verified via the check-runs API (not taken on
trust): PR #104 head `44ad192` — 3/3 completed/success
(isolated, isolated, real-script-s1); PR #105 head
`09db336` — 3/3 completed/success (isolated, isolated,
real-script-s1). Both PRs are Draft, `mergeable: true`,
`mergeable_state: clean`.

## 3. Cross-review findings

### 3.1 PR #104 probe template — verified claim by claim

- **No real token input:** the only data is RFC 8032 §7.1
  test vector #1 — public key
  `d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a`
  and signature
  `e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b`
  (empty message). Independently verified with Node `crypto`:
  the valid signature verifies `true`, the first-byte-flipped
  signature is rejected, SHA-256(empty) =
  `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`,
  TextEncoder("abc") = `616263`. These are the public
  standard vectors, not credentials.
- **No HTTP:** 0 occurrences of `require(`/`fetch(`/`XMLHttpRequest(`,
  0 of `$httpClient`/`$httpAPI`/`$surge`/`$notification`/
  `console.log`, 0 URLs (grep-verified).
- **No policy/ledger ops:** 0 occurrences of
  `sgbridge_cred`/`last_id`/`ledger`/`pins`/`timers`. The
  only `$persistentStore` call is
  `write(status, STATUS_KEY)` with the fixed key
  `sgbridge_webcrypto_probe_status` and an 8-value enum
  (`crypto_ready`, `no_webcrypto`, `no_text_encoder`,
  `sha256_failed`, `ed25519_unavailable`, `signature_failed`,
  `random_unavailable`, `probe_error`).
- **Trigger gating:** lines 38–39 — only `$trigger ===
  "editor"` or `"intent"` set `permitted = true`; any other
  trigger returns early with zero state writes (the `finally`
  block writes only when `permitted`).
- **`$done` exactly once:** 1 occurrence, in the `finally`
  block; a write that returns `false` or throws is swallowed
  and `$done` is still called (both cases covered by tests).
- **Test count:** 18 `test()` calls, matching the workflow
  step name "Execute 18 adversarial checks" (no off-by-one
  label error, unlike PR #103's "14" label for 15 tests).
- **First-CI-red history (GPT's account, consistent with the
  current files):** the first CI run failed because a test
  regex wrongly rejected the legal `sha256_failed` label
  (not a script algorithm failure); fixed with a strict enum
  whitelist (the 8-value `allowedStatuses` Set in the test)
  and re-ran green. Head CI is 3/3 success.

### 3.2 PR #105 verifier — verified claim by claim

- **No Node `require`:** 0 occurrences of `require(`. The
  only module reference is a `module.exports` export shim
  (lines 119–120) that falls back to the global
  `root.sgbridgeVerifySignedPromotionProof` in a WebView
  (line 122). WebCrypto-only: `crypto.subtle.digest` /
  `importKey` / `verify`, `TextEncoder`, `atob`.
- **Canonical JSON byte-identical to PR #103:** the
  `canonicalJson()` field order (purpose, kind, ok,
  fingerprint_matches, token_id, fingerprint, nonce,
  issued_at, expires_at) matches PR #103's `payload()` in
  `signed_promotion_proof.js` field for field (verified by
  source inspection AND by the test "canonical bytes
  exactly match PR103 Node reference", which asserts
  `canonicalJson(p) === payload(p)`).
- **All required bindings present** (grep counts in
  parentheses): candidate (8), expectedNonce (4),
  pinnedPublicKeyHex (5), oldTokenId (4), purpose (2),
  kind (4), issued_at (6), expires_at (5), fingerprint
  (6), signature (6), `crypto.subtle.verify` (2),
  `crypto.subtle.digest` (2), `atob` (2). The checks:
  candidate is a printable-ASCII string of length 32–256
  and not a `<...>` placeholder; kind is exactly `dev` or
  `localkey`; purpose is
  `issue73/credential-promotion/v1` and kind matches;
  `ok` and `fingerprint_matches` are `true`; token id is a
  non-empty string and differs from the trusted old
  exposed id; expectedNonce is a string of length ≥16 and
  equals the signed nonce; issuance is no more than 24h
  old and no more than 5 minutes in the future; expiry is
  strictly after now and no later than 24h after issuance;
  fingerprint is 64 lowercase hex; pinned key is 64 hex
  (32 bytes); signature matches the 64-byte base64 shape
  (`^[A-Za-z0-9+/]{86}==$` — correct for 64 bytes: 84 +
  2 + `==`); `atob` decodes to exactly 64 bytes; the
  candidate SHA-256 is computed locally by Web Crypto and
  compared to the signed fingerprint; the Ed25519 signature
  verifies against the independently pinned public key.
  Missing any item returns `false` — 14 fail-closed
  `return false` statements plus the outer `catch → false`.
- **No credential writes / HTTP / logs:** 0 occurrences of
  `$persistentStore`/`$httpClient`/`$httpAPI`/`console.log`
  in the library. The test asserts counts
  `{network:0, write:0, logs:0}`.
- **Library, not a standalone script:** the file has no
  `$done`, no `$trigger`, no top-level execution — just an
  IIFE that exports the function. The header and doc state
  it must be bundled into a separately approved generic
  script and MUST NOT be registered on its own. The test
  depends on `./signed_promotion_proof` (PR #103's file,
  present in the private tree and on the PR #105 branch
  chain), which is the correct cross-file dependency.
- **Test count:** 19 `test()` calls, matching GPT's
  19 PASS / 0 FAIL / 1 named limitation.

### 3.3 Named finding — F1 (minor, coverage gap, GPT's files unchanged)

**F1 — The PR #104 probe does not check `atob`
availability, but the PR #105 verifier requires it.**
`surge_webview_signed_proof.js` fails closed when
`typeof atob !== "function"` (and the PR #105 test has an
"atob absent fails closed" case). The PR #104 probe checks
`crypto.subtle`, `TextEncoder`, SHA-256, Ed25519 import /
verify, and `getRandomValues` — but not `atob`. A
`crypto_ready` result from the probe therefore does not
guarantee the verifier can run on the same runtime. This is
a coverage gap between the probe and the verifier's
requirements, not a defect in either file's logic, and it
fails closed on the verifier side. GPT's files are kept
byte-identical; the fix (add an `atob` availability check
to the probe, or record the gap in the probe doc) is for
GPT to decide. No other discrepancies found.

## 4. Local verification

| Suite | Result |
|---|---|
| WebView probe `test_surge_webview_crypto_probe.js` | **18/18 PASS** (PR #104) |
| WebView verifier `test_surge_webview_signed_proof.js` | **19/19 PASS, 0 FAIL, 1 KNOWN LIMITATION** (PR #105) — same valid signature reused with the same expectedNonce passes again (stateless verifier by design) |
| Replay negative control `test_webview_replay_negative_control.js` (NEW, this round) | **4/4 PASS, 0 FAIL, 1 KNOWN LIMITATION** — same valid proof passes twice with reused trusted nonce (documented limitation, NOT a verifier failure); same proof rejected with a different expectedNonce (nonce binding works); same proof rejected for a different candidate; no side effects (network 0, writes 0, logs 0) |

The replay control confirms the design notes: production
needs a durable one-time nonce consumption gate. The
reference only proves a proof whose nonce does not match
the CURRENT expected challenge is rejected; durable replay
rejection (remembering used nonces) is NOT implemented in
either reference. That is an open item, not a hidden pass.

## 5. Device evidence scope note (Round 6 addendum)

Appended to `DEVICE_EVIDENCE_ALIGNMENT.md` as the "Scope
clarification addendum (Round 6, 2026-11-20)". New file SHA:
`e2c188e61d0c97c15ce43642d3688009b378a9be849464c404cfe6cd51d8fff2`.
The owner's reported device acceptance covers the **NODE
POOL only** (chat clarification "节点池", 2026-11-20 06:30
CST). It does NOT cover Ed25519/WebCrypto support (the
PR #104 probe has NOT been run on the real device and is
NOT approved for auto-execution; Node VM CI is not device
proof), the two cron cycles actually verifying the old-ID
fence (rows 5–8), the logs/Shortcuts history privacy check
(rows 11–14), or the running source script SHA / Surge
version / iOS version (rows 2–4). Row 15 records scope =
node pool only. **All 15 rows remain UNVERIFIED; nothing
invented.**

## 6. CI for Round 6

New workflow `ci/issue73-c3c0-round6.yml` (SHA
`31982cf8…54ff8`): syntax check for the replay negative
control + a step running it with a nonzero-failure gate.
GPT's PR #104 workflow (`issue73-surge-webcrypto-probe.yml`)
and PR #105 workflow (`issue73-webview-signed-proof.yml`)
are absorbed unchanged and cover the 18 probe tests and
the 19 verifier tests. All workflows are `contents: read`
and isolated (synthetic tokens only, no network, no phone).

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
| Negative control `test_signed_proof_negative_control.js` | **5/5 PASS** |
| Dual token `test_dual_token.js` | **12/12 PASS** |
| WebView probe `test_surge_webview_crypto_probe.js` | **18/18 PASS** (PR #104, new) |
| WebView verifier `test_surge_webview_signed_proof.js` | **19/19 PASS, 0 FAIL, 1 KNOWN LIMITATION** (PR #105, new) |
| Replay negative control `test_webview_replay_negative_control.js` | **4/4 PASS, 0 FAIL, 1 KNOWN LIMITATION** (new, this round) |

Total across the seventeen suites: **197 PASS / 0 FAIL /
1 LIMITATION** (28+5+10+11+14+7+13+14+5+17+15+5+12+18+19+4).
The 1 LIMITATION is the v2 V23 frozen-timer item. The two
named replay limitations (one inside the verifier suite,
one inside the replay control) are the same underlying
stateless-replay issue, documented in both places.

## 8. Clean-copy verification

**PASS.** The full private tree (63 files) was copied to a
fresh `/tmp/c3c0-clean-copy-r6/` and all seventeen suites
were run from there with identical results: v2 28/0/1,
store 5/5, S1 live 10/10, S1 11/11, S3 14/14, bootstrap
7/7, bootstrap candidate 13/13, candidate regressions
14/14, rollback positive PASS + negative control FAIL as
expected, provisioning demo 5/5, promotion gate 17/17,
signed-proof adversarial 15/15, negative control 5/5,
dual token 12/12, WebView probe 18/18, WebView verifier
19/0/1, replay control 4/0/1. v2.2 SHA in the copy:
`8691e962…abfc` (unchanged).

## 9. Files to commit to PR #97 (branch `c3c0-sanitized-v2-review`)

| Target path | SHA-256 (full) | Status |
|---|---|---|
| `docs/surge-bridge-c3c0/surge_webview_crypto_probe.template.js` | `6b76f8efa1667f671aca443d41dac7b02b472ece12483c5d58496d1dbe8e5eb4` | NEW (PR #104) |
| `docs/surge-bridge-c3c0/test_surge_webview_crypto_probe.js` | `fa275f32cb89d35de01f7de8879a5f4e5341c5e438118d67aeae0610f2de4501` | NEW (PR #104) |
| `docs/surge-bridge-c3c0/test_surge_webview_crypto_probe_out.json` | `87d4fd3046119bebe76b4e1f1747a782558ca9b966ccce78948dfbfd26c539f1` | NEW (18/18 record) |
| `docs/surge-bridge-c3c0/SURGE_WEBVIEW_CRYPTO_GATE.md` | `b34a32ddd42cf0c58f875dcdda678713c3ba6846fe4fd2fd6baa1a0961fa0de4` | NEW (PR #104) |
| `docs/surge-bridge-c3c0/surge_webview_signed_proof.js` | `02b18dbdb7f2062e96ac0f2e47c14dfc6d729f987d78a7e49193b8c5c97b3bfe` | NEW (PR #105) |
| `docs/surge-bridge-c3c0/test_surge_webview_signed_proof.js` | `21118d7db74d1deb109f0066ff1118eb0f9582149aa6bf24a0cd14c7e5774c8c` | NEW (PR #105) |
| `docs/surge-bridge-c3c0/test_surge_webview_signed_proof_out.json` | `79939601d1ea43cc6cb477fa49274135b1f0abef229ea5eb6d79c16c6cdd8ab9` | NEW (19/0/1 record) |
| `docs/surge-bridge-c3c0/SURGE_WEBVIEW_SIGNED_PROOF.md` | `0a0bfbd9ecd5f32c4fa4de16362295a3577176627ee100da586ca891e823c8a3` | NEW (PR #105) |
| `docs/surge-bridge-c3c0/test_webview_replay_negative_control.js` | `745c04cd633c86dc6ab3e356c60534d38a460ee1cf2f77fba8676f785ff6b506` | NEW (4-case replay control) |
| `docs/surge-bridge-c3c0/test_webview_replay_negative_control_out.json` | `29fab4e5f42ceaac2b318e7a43e39a940883450e2af41497d417962fd078ac7e` | NEW (4/0/1 record) |
| `docs/surge-bridge-c3c0/DEVICE_EVIDENCE_ALIGNMENT.md` | `e2c188e61d0c97c15ce43642d3688009b378a9be849464c404cfe6cd51d8fff2` | UPDATED (Round 6 scope addendum) |
| `.github/workflows/issue73-surge-webcrypto-probe.yml` | `97354e7836f7aa9b09e14843894fb32d946d0af4e57ee7077eac1959171a2e14` | NEW (PR #104) |
| `.github/workflows/issue73-webview-signed-proof.yml` | `bf8e0a06fcfe3cf69068670ff55a4b75809e3ce1073e3d4ef0a13d611743fa75` | NEW (PR #105) |
| `.github/workflows/issue73-c3c0-round6.yml` | `31982cf8f4676b14875fcf787fbf1de76900fb59249b34b4cbe1df626e754ff8` | NEW (replay-control CI) |
| `docs/surge-bridge-c3c0/C3C0_REPORT.md` | (recompute at commit time — Round 6 addendum below) | UPDATED |
| `docs/surge-bridge-c3c0/C3C0_ROUND6_REPORT.md` | self-referential (recompute at commit time) | NEW |

Unchanged in Round 6: `bridge_fixed_v2.js` (v2.2,
`8691e962…abfc`, 571 lines), `promotion_gate.js`
(`b12545be…67b9b90`), `signed_promotion_proof.js`
(`69d3f2fe…a2145`), `test_promotion_gate.js`
(`ef5579e2…e9364`), `test_signed_promotion_proof.js`
(`7d0c9981…b438f5`), `test_signed_proof_negative_control.js`
(`d1598825…0512f59`), `PROMOTION_GATE_DESIGN.md`
(`a586c99e…0a82d6a`), and all other Round 1–5 files.

## 10. Secret scan

All 15 existing new/changed Round 6 files scanned for the
real DEV token, real API key, real URLs, node URIs, and the
VPS IP: **0 hits**. Only placeholders and synthetic
`TEST-*` tokens, plus the public RFC 8032 test vectors and
the public SHA-256(empty) digest (both explicitly public,
not credentials). (The Round 6 report itself is scanned at
commit time by the parent.)

## 11. Gates (unchanged)

`CREDENTIAL_DISTRIBUTION_GATE=BLOCKED`;
`BOOTSTRAP_SECURITY_GATE=BLOCKED`; `C3-C1=NO-GO`;
`PR93_CUTOVER=BLOCKED`; `AUTO_DELETE=OFF`;
`DEVICE_EVIDENCE_CORRELATION=OPEN`;
`DEVICE_ACCEPTANCE=USER_REPORTED` (node-pool scope only);
`RELEASE_EVIDENCE_NOT_YET_COMPLETE`; old command 1795063030
stays `OUTCOME_UNKNOWN`, permanently fenced. PR #98 (GPT
oracle 28/28), PR #99 (saveLedger fix), PR #100 (S1
credential adapter), PR #101 (Shortcuts candidate
bootstrap), PR #102 (hermetic rollback), PR #103
(signed-proof fix) untouched and not conflated with these
counts. The WebView probe has NOT been run on the real
device and is NOT approved for auto-execution; the PR #105
verifier is a library, NOT a standalone Surge script; the
stateless replay limitation is open (durable one-time nonce
consumption still required). P2/P3 node auto-isolation /
deletion were NOT opened.

## 12. What the parent still needs to do

1. Commit the §9 files to PR #97 (branch
   `c3c0-sanitized-v2-review`) as the Round 6 follow-up.
2. Post the C3-C0 Round 6 receipt to Issue #73 (referencing
   PR #97's new head, PR #104/#105 absorbed, finding F1,
   the device-evidence scope note, and the unchanged
   gates).
