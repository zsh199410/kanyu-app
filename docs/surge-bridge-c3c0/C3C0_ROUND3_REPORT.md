# C3-C0 Round 3 Report — PR #100 S1 Credential Adapter Merged, Bootstrap Designed

## 1. Headline

GPT's Draft PR #100 (S1 secret-free credential adapter) is merged into the
private v2.1, producing **v2.2** (SHA `8691e962cba4ab40e961702b7d30090aaaedc29fdbe46b63a257878f9f90abfc`,
571 lines). All five test suites pass. A secure credential bootstrap design
(`BOOTSTRAP_DESIGN.md`) + isolated tests (7/7) is delivered for GPT gate 1.
No live changes, no credential revoked or rotated, no GitHub posts, no phone
contact.

## 2. PR #100 absorption — v2.1 → v2.2

### 2.1 Method

PR #100's full diff (`/tmp/pr100.diff`, 298 lines) was applied verbatim with
`git apply` to a copy of the private v2.1 tree. Pre-apply SHAs matched the
PR #97 Round-2 head exactly (v2.1 `1658cea7`, s1/test_s1.js `f98506b5`,
simulator `f0ac1dab`, test_store_failure `24a20ea1`). `git apply --check`
passed with **zero conflicts** — there is **no discrepancy** between
PR #100's base and the private v2.1. The resulting v2.1→v2.2 diff is
byte-identical to PR #100's v2 hunk (see `C3C0_V2_V22_DIFF.md`).

### 2.2 What was applied

- `readCredential(key)`: reads `$persistentStore`, returns null on throw /
  non-string / empty / >512 chars / CR-LF / `<placeholder>`. `DEV` and
  `APIKEY` are now `let ... = null` read at runtime; no hardcoded values.
- Entry gate: after `cron_enter`, read DEV; if absent → phase
  `credential_missing`, `$done` exactly once, return (zero network, zero
  action, zero result, zero ledger/last_id writes). Read APIKEY (may be
  absent); phase `credential_present`.
- 403 gate: after poll, if status is 403 (and not a timeout) → phase
  `auth_forbidden`, `$done` exactly once, return. Mailbox and ledger
  untouched; no fallback to old credentials; a cached `result_ready` is
  NOT re-sent on 403.
- `api()` direct-HTTP fallback: if no APIKEY → `local_key_missing`,
  blocked, no localhost request.
- MCP action: if no APIKEY → `local_key_missing` output, `continue`, no
  localhost request.
- `s1/test_s1.js` S1-T1 updated: the integrated script intentionally has
  NO token/key placeholders; it must reference the runtime
  persistent-store key names and must not contain `const DEV = "..."` /
  `const APIKEY = "..."`.
- `simulator.js`: injects synthetic credentials by default
  (`TEST-DEV-MOCK-ONLY`, `TEST-LOCAL-MOCK-ONLY`) unless
  `cfg.injectCredentials === false`; separates `credentialReadThrows`
  from `storeReadThrows`.
- `test_store_failure.js`: mock store now injects the synthetic
  credentials (so the v2.2 entry gate passes).
- New `test_s1_live_adapter.js` (10 actual-script S1 tests) and new CI
  workflow `issue73-c3c0-s1-adapter.yml`.

### 2.3 Cross-review verdict

Each change was reviewed for correctness against the v2.1 state machine:

| Check | Verdict |
|---|---|
| Credential gating preserves the state machine, strict ACK, old-cmd fence, durable store | PASS. The entry gate returns before any ledger load/bootstrap; the 403 gate returns before cmd parsing and before the fence; `saveLedger` (PR #99) is unchanged; `sendResult` / strict ACK unchanged. |
| `readCredential` validation holes | None found. Throw → null; non-string → null; empty → null; >512 → null; CR-LF → null (prevents header injection via `X-Dev-Token` / `X-Key`); `<...>` placeholder → null. Note (non-blocking): a value with leading/trailing whitespace is not trimmed, but it fails server-side with 403 and the 403 gate fails closed, so it is an operational annoyance, not a hole. |
| 403 path leaves mailbox and ledger untouched | PASS. The 403 return is before cmd parsing, before ledger load, and before the cached-result resend path, so no dispatch, no `/result`, no ledger mutation. |
| MCP / localhost gating covers every localhost call path | PASS. The only localhost calls are the `api()` direct-HTTP fallback (gated) and the MCP branch (gated). `sendResult` and poll go to the mailbox server (DEV-gated at entry). `$httpAPI` is native and needs no key. `$notification` makes no HTTP call. |
| Fence preserved | PASS. With a valid token the fence is unchanged. With no token, no command is fetched at all. With a 403, the old command is still not executed (phase is `auth_forbidden` instead of `legacy_fenced`, same effect). |
| `test_store_failure.js` still exercises the PR #99 fix | PASS. 5/5 on v2.2 (see §3). |

## 3. Test results (all against v2.2)

| Suite | Result |
|---|---|
| v2 regression `test_fixed_v2.js` | **28 PASS / 0 FAIL / 1 LIMITATION** (V23, `RUNTIME_HARD_TIMEOUT_UNPROVEN`, frozen timer — named limitation unchanged) |
| Storage failure `test_store_failure.js` | **5/5 PASS** |
| S1 live adapter `test_s1_live_adapter.js` | **10/10 PASS** (new; runs the actual v2.2 script) |
| S1 `s1/test_s1.js` | **11/11 PASS** |
| S3 `s3/test_s3.js` | **14/14 PASS** |
| Bootstrap `s1/bootstrap_test.js` | **7/7 PASS** (new; see §4) |
| Clean-copy verification | **PASS** — 23 files to a fresh `/tmp/c3c0-clean-copy-r3/` (no `pr96-c3b`), all five suites pass from there |
| Rollback simulation `rollback_test.sh` | PASS (re-run, unchanged) |

Total across the five main suites: **68 PASS / 0 FAIL / 1 LIMITATION**
(28 + 5 + 10 + 11 + 14).

## 4. Secure credential bootstrap design (GPT gate 1)

`BOOTSTRAP_DESIGN.md` + `s1/bootstrap.js` + `s1/bootstrap_test.js` (7/7).

- **Mechanism:** a one-time Surge script the owner creates **locally in the
  Surge app**, pastes the new DEV token + local key into two constants,
  runs once, verifies the output is exactly `bootstrap_ok`, then **deletes
  the script** (required checklist step; a Surge script cannot delete
  itself, so manual deletion is explicit). The script validates the pasted
  values, writes them to `$persistentStore`, verifies by read-back
  equality, sets `sgbridge_bootstrap_done`, and logs only a status word —
  the token is never sent over the network, never logged, never written
  to any file except `$persistentStore`.
- **Token delivery:** generated server-side into a root-only file; the
  owner reads it via SSH; never via public URL, chat, or email.
- **Verification:** `credential_present` phase on the next cron run, plus
  server-side `/poll` 200 (not 403) as the functional proof the right
  token is stored. The SHA-256 fingerprint is a server-side audit record;
  the on-device script uses read-back equality (Surge has no crypto API).
- **`$persistentStore` caveat (explicit):** it is a simple persistent
  key-value API, **not** a proven secure hardware keystore. This design
  removes the credential from the publicly distributed script; it does
  **not** claim secure-enclave storage. Backup / cross-app exposure is
  recorded as **unverified**, not assumed safe.
- **Gate 2 (dual-credential window / revocation):** referenced from the
  S1 Rev 1 plan (new backup token or fail-closed; never re-enable the
  leaked token). The server-side token-table change needs separate design
  + review and is NOT part of this bootstrap design.
- **Bootstrap tests (7/7):** B1 success + fingerprint match; B2 second
  run is a no-op (done flag); B3 failed write detected; B4 read-back
  mismatch detected; B5 invalid input rejected (empty / placeholder /
  CR-LF / >512); B6 source contains placeholder only; B7 bootstrapped
  values pass the v2.2 `readCredential` rules.
- **Finding during testing:** injecting a value containing a raw CR/LF
  into the script source would break the script (syntax error) before
  `valid()` runs. The test now injects via `JSON.stringify` so the value
  is a valid literal and `valid()` rejects it at runtime. Owner
  instruction: paste cleanly, no trailing newline; a parse failure is
  fail-closed (nothing written).

## 5. Gates (unchanged)

- `CREDENTIAL_DISTRIBUTION_GATE=BLOCKED` (bootstrap is a design + isolated
  test; the real-device bootstrap run and the server-side token-table
  change are still open).
- `C3-C1=NO-GO`. `PR93_CUTOVER=BLOCKED`. `AUTO_DELETE=OFF`.
- Old command 1795063030 stays `OUTCOME_UNKNOWN`, permanently fenced.
- `RUNTIME_HARD_TIMEOUT_UNPROVEN` (V23) still the one named limitation.
- PR #98 (GPT oracle 28/28) and PR #99 (saveLedger fix) are untouched and
  not conflated with these counts. PR #100's CI runs (44541066377,
  44541066419, success) are GPT's own verification of the same change set.

## 6. Files to commit to PR #97 (with SHAs)

Branch: `c3c0-sanitized-v2-review` (Draft PR #97). Target paths are under
`docs/surge-bridge-c3c0/` unless noted. Files already on PR #97 are listed
as UPDATED; new files as NEW.

| Target path | Local file | SHA-256 | Status |
|---|---|---|---|
| `docs/surge-bridge-c3c0/bridge_fixed_v2.js` | `bridge_fixed_v2.js` | `8691e962cba4ab40e961702b7d30090aaaedc29fdbe46b63a257878f9f90abfc` | UPDATED (v2.1 → v2.2) |
| `docs/surge-bridge-c3c0/test_fixed_v2.js` | `test_fixed_v2.js` | `348a6eee47bfd6305f86d66714df2664cefd6ea78ea3b15fdf6e5986df9324eb` | UNCHANGED |
| `docs/surge-bridge-c3c0/test_fixed_v2_out.json` | `test_fixed_v2_out.json` | `1f690ae371999cd7e3a0987514a82cd101a1e2b4396044d0fa0e172c7344a0a3` | UPDATED (regenerated, 28/0/1) |
| `docs/surge-bridge-c3c0/test_store_failure.js` | `test_store_failure.js` | `334322d61d95c2b9eca9b13353d298b2200b6ec0309a84d64a3e3d3dec982686` | UPDATED (PR #100 credential injection) |
| `docs/surge-bridge-c3c0/test_s1_live_adapter.js` | `test_s1_live_adapter.js` | `a300a7daddf1063d9b3f9d1465b4401271c51b13cc8d2af782bf5b0f9bbfb49e` | NEW (PR #100, unmodified) |
| `docs/surge-bridge-c3c0/test_s1_live_adapter_out.json` | `test_s1_live_adapter_out.json` | `caeb0e7df83b11207044cc96f8d5f1b5a66f57f628e9f828effb9eabdde456af` | NEW (10/10 record) |
| `docs/surge-bridge-c3c0/simulator.js` | `simulator.js` | `a752dc437d0133eb5de6fa78ccfe40c57b084b2d99ed1bc7a5498fa1c253aef4` | UPDATED (PR #100 credential injection) |
| `docs/surge-bridge-c3c0/s1/test_s1.js` | `s1/test_s1.js` | `6dbfcd4ce266a3190b59f657c4c38906766055caa20228205f26c610a5a0de1c` | UPDATED (PR #100 S1-T1) |
| `docs/surge-bridge-c3c0/s1/s1_out.json` | `s1/s1_out.json` | `82f05568753a7ffe7bc524ac80936109e99efe54f0f2c8f4e8b4d3424ded5c57` | UPDATED (regenerated, 11/11) |
| `docs/surge-bridge-c3c0/s1/bootstrap.js` | `s1/bootstrap.js` | `7ad808ce404b4f307c2fcfd14c99babbfd259eb2e09ffded815f07e93b491d2b` | NEW |
| `docs/surge-bridge-c3c0/s1/bootstrap_test.js` | `s1/bootstrap_test.js` | `149c713fe2ac081bbc9419374a46ecb0b26867c27c89e19a069dcbed38d94113` | NEW |
| `docs/surge-bridge-c3c0/s1/bootstrap_out.json` | `s1/bootstrap_out.json` | `8a4d00a9dc8d00127bc6a526a185acd9c741bed45b056e5740451e53e95ebe71` | NEW (7/7 record) |
| `docs/surge-bridge-c3c0/BOOTSTRAP_DESIGN.md` | `BOOTSTRAP_DESIGN.md` | `b7530d63c0f0102eb8196ea52f195e4ec427c0c41986900743c2ff14586884cf` | NEW |
| `docs/surge-bridge-c3c0/C3C0_V2_V22_DIFF.md` | `C3C0_V2_V22_DIFF.md` | `3938f22fabedc417` (short; full in file) | NEW |
| `docs/surge-bridge-c3c0/C3C0_REPORT.md` | `C3C0_REPORT.md` | `ae944256a74407ceaed798200e58e221d41f889619b147826630056bafc8dfc1` | UPDATED (Round 3 addendum) |
| `docs/surge-bridge-c3c0/C3C0_ROUND3_REPORT.md` | `C3C0_ROUND3_REPORT.md` | (self-referential — recompute with `sha256sum` at commit time) | NEW |
| `.github/workflows/issue73-c3c0-s1-adapter.yml` | `ci/issue73-c3c0-s1-adapter.yml` | `48a37c6eb8cc26c2e6a3b0ab3305df0327bf5d6bdf2daae947cd944d0f97acdf` | NEW (PR #100, unmodified) |

Notes:
- `C3C0_MINIMAL_PATCH_V2.md` is unchanged in Round 3 (the
  v2.1→v2.2 change is in `C3C0_V2_V22_DIFF.md`).
- `s3/*`, `v1/bridge_fixed.js`, `ci/issue73-c3c0-v2.yml`,
  `SECURITY_GATE_PLAN.md`, `SECURITY_GATE_PLAN_REV1.md`,
  `ID_ALLOCATOR_DESIGN.md`, `C3C0_S1_S3_SUMMARY.md`,
  `C3C0_ROUND2_REPORT.md`, `rollback_test.sh` are UNCHANGED in Round 3.

## 7. Secret scan

All 16 new/changed Round 3 files scanned for the real DEV token, real
API key, real URLs, node URIs, script/module paths, and the VPS IP:
**0 hits**. Only placeholders and synthetic `TEST-*` tokens. (Scan
re-run by the parent agent; see its report.)
