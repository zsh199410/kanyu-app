# C3-C0 Round 7 Report — absorb GPT PR #106 (durable SQLite nonce ledger) + PR #107 (F1 atob fix)

Date: 2026-11-20. Reply to GPT comments 7024865519 (PR #106) and 7024937444
(PR #106 + PR #107, F1 close) on Issue #73 (zsh199410/kanyu-app).
Work done in isolation under `~/workspace/pr96-c3c0/` — no live files touched,
no credentials revoked or rotated, no GitHub posts, no phone contact, no
auto-execution of the probe, no registration of PR #105's verifier as a
standalone Surge script, no phone key test, no formal token promotion,
P2/P3 not opened. Private v2.2 unchanged (571 lines, SHA `8691e962…abfc`).

## 1. Sources

- GPT comment 7024865519 (2026-11-19T23:13:24Z, zsh199410, 1995 bytes):
  C3-C1 P0 durable nonce gate; PR #106.
- GPT comment 7024937444 (2026-11-19T23:17:16Z, zsh199410, 2078 bytes):
  PR #106 recap + PR #107 F1 close.
- PR #106: Draft, head `af944050e199fa0ff9315f2b3b42259989ffb568`,
  branch `gpt6-issue73-durable-nonce-ledger-20261120`,
  base `gpt6-issue73-surge-webcrypto-proof-verifier-20261120` (`09db3368`),
  4 commits, +512/−0, 4 NEW files. Mergeable clean.
- PR #107: Draft, head `1a0d7bd53756693016cd0422b828ba3e7264c28f`,
  branch `gpt6-issue73-webcrypto-atob-f1-20261120`,
  base `gpt6-issue73-durable-nonce-ledger-20261120` (`af944050`),
  4 commits, +38/−4, 4 MODIFIED files. Mergeable clean.
- PR #97 baseline (before Round 7): head `8463e67a9ab665ff47f48cbf3453e51b0d2a95e8`
  (21 commits, 77 files, +12804/−0, Draft).

## 2. Head CI re-verified (check-runs API, not taken on trust)

- PR #106 head `af944050` — 3/3 completed/success:
  `sqlite-nonce` run 44635572814, `isolated` run 44635572821,
  `real-script-s1` run 44635572764. Matches GPT's claimed run numbers exactly.
- PR #107 head `1a0d7bd5` — 3/3 completed/success:
  `isolated` run 44636206928, `real-script-s1` run 44636207013,
  `isolated` run 44636207032. Matches GPT's claimed run numbers exactly.

## 3. Byte-identical absorption

Both diffs read in full (536 + 121 lines). All eight files fetched from the
GitHub API (raw head-branch URLs) and compared against a reconstruction
obtained by applying each diff with `git apply`:

- PR #106: diff applied to an empty tree — all four files byte-identical.
- PR #107: the four base files on the PR #106 branch were first confirmed
  byte-identical to the CURRENT PR #97 versions in the private tree
  (surge_webview_crypto_probe.template.js, test_surge_webview_crypto_probe.js,
  SURGE_WEBVIEW_CRYPTO_GATE.md, ci/issue73-surge-webcrypto-probe.yml),
  then the diff applied cleanly onto copies of those files — all four
  resulting files byte-identical to the PR #107 head fetches.

| File | SHA-256 | Status |
|---|---|---|
| `nonce_ledger_sqlite.py` | `96dd9cb645d19c77e415b1ca76c3cad754c6457ea4ed164f2bb1251cf7b75d37` | NEW (PR #106) |
| `test_nonce_ledger_sqlite.py` | `a612a32f15008c75737d4d10a04414fd90f8d9caa4ce8c727bca7701fd331a3c` | NEW (PR #106) |
| `DURABLE_NONCE_LEDGER_GATE.md` | `3fd7c1e9cb0c6c5dadbb6f2a4be54eb5a496b09756a40ea2419ebb5d186798f1` | NEW (PR #106) |
| `ci/issue73-durable-nonce.yml` | `c51abecfdbcb84c2a89bf2b6873da0012c634d1c34948065302d68a83e50e885` | NEW (PR #106) |
| `surge_webview_crypto_probe.template.js` | `2eb650c62ba16c0243c6df70a5547908009eac7565098d01cf947f645c996753` | REPLACE (PR #107) |
| `test_surge_webview_crypto_probe.js` | `698926eca73600592d52e9112cd3215f4e33727826554ecadfcd0e24c04ca452` | REPLACE (PR #107) |
| `SURGE_WEBVIEW_CRYPTO_GATE.md` | `e3b67183d88d64821ed26ea1a132b5b00ea4b3aa32f9c343ab57e265cd89e165` | REPLACE (PR #107) |
| `ci/issue73-surge-webcrypto-probe.yml` | `04a5599d53390dbd9f3768a98b67e82165647623032d97766b0ee9a96bfd52c9` | REPLACE (PR #107) |
| `test_surge_webview_crypto_probe_out.json` | `814a911e57894c549a2be4b9869867ef9551d595f19829b542c2bc3139093cd2` | REPLACE (regenerated, 20/20) |

## 4. Cross-review — nonce ledger (PR #106)

Every claim verified by reading the code and by independent checks:

- `BEGIN IMMEDIATE` in both `register` and `consume` (3 occurrences incl.
  module docstring); `PRAGMA journal_mode=WAL`, `synchronous=FULL`,
  `busy_timeout=5000`, `trusted_schema=OFF` — all present in `_connect`.
- Only the SHA-256 digest is stored: `register` inserts `nonce_hash(nonce)`
  (32-byte digest); independently verified — registered a nonce, read the
  DB file bytes (nonce string absent), read the row (digest is 32 bytes and
  equals `sha256(raw nonce bytes)`); kind/fingerprint/token/status correct;
  consume True once, False second time; counts (1, 1).
- `register` is `INSERT OR IGNORE`, duplicate → `rowcount == 0` → False.
- `consume` is a single conditional `UPDATE` (`status='issued'` + binding
  + `issued_ms <= now < expires_ms`), returns `changed == 1`.
- Tombstones never deleted: 0 occurrences of `DELETE` in the module.
- `commit_state_unknown` raised on `sqlite3.Error`/`OSError` in register,
  consume, `_initialize`, and `counts` (as `read_unknown`); no auto-retry
  anywhere (no retry loop in the file).
- `max_records` bound stops issuance: `SELECT COUNT(*)` inside the
  `BEGIN IMMEDIATE` transaction, `>= max_records` → `ROLLBACK` +
  `NonceLedgerError("ledger_full")`; consumed tombstones count toward the
  bound (never purged).
- Path safety: `:memory:` rejected, missing parent rejected, symlink
  (file or parent) rejected, parent mode `& 0o077` rejected,
  `os.chmod(path, 0o600)` after init.
- Schema version check: `PRAGMA user_version` must be 0 or 1 (else
  `schema_version_unknown`), 0 → set to 1; `PRAGMA integrity_check` must
  return `"ok"`.
- Test count: 21 `def test_` methods in `test_nonce_ledger_sqlite.py`,
  matching the claim. Workflow runs them with `-W error::ResourceWarning`
  (GPT's "ResourceWarning eliminated" claim verified: local run with that
  flag passes).
- Gate doc (`DURABLE_NONCE_LEDGER_GATE.md`, 111 lines) is honest:
  single-host reference, not a deployed endpoint; limitation #3 states
  snapshot rollback can resurrect consumed nonces; device side remains
  unimplemented; no claim of end-to-end replay protection.

**Observation O1 (not a discrepancy, no file change):** under lock
contention, if a second caller's `BEGIN IMMEDIATE` blocks past the 5 s
`busy_timeout`, it raises `NonceLedgerError("commit_state_unknown")`
rather than returning False. That is the documented fail-closed contract
("stop and reconcile, do not retry automatically"), and the concurrency
tests ([False, True]) pass because the winning transaction holds the lock
for under a millisecond. Not a finding; recorded so the behavior is not
mistaken for a plain False under pathological contention.

No discrepancies found in PR #106. No named findings.

## 5. Cross-review — probe F1 fix (PR #107)

- The `atob` check sits after the TextEncoder check and BEFORE the SHA-256
  digest, Ed25519 import/verify, and random checks, and `crypto_ready` is
  assigned only at the very end of the probe. Missing `atob` returns early
  with `base64_unavailable`; a broken decoder returns early with
  `base64_failed`. The probe can no longer report `crypto_ready` when
  `atob` is missing or broken. **F1 is CLOSED.**
- Vector verified independently: `Buffer.from('AQIDBA==','base64')` decodes
  to bytes `1,2,3,4`, matching `String.fromCharCode(1, 2, 3, 4)`.
- Test file: 20 `await test(` calls (18 → 20); the two new tests are
  "missing atob fails before crypto_ready" (`suppliedDecoder: null` →
  `base64_unavailable`) and "incorrect atob decoding fails before
  crypto_ready" (`suppliedDecoder: () => "incorrect"` → `base64_failed`).
  Both new statuses are in the test's `allowedStatuses` whitelist.
- Workflow step label updated 18 → 20, matching the actual test count
  (no off-by-one label error).
- Gate doc adds check 5 + a "Round 6 F1 resolved" section and states
  honestly: "It remains an isolated test, not a real Surge device result
  or production credential-promotion authorization."

No discrepancies found in PR #107. No new named findings (F1 closed).

## 6. Local verification

- Nonce ledger `test_nonce_ledger_sqlite.py`: **21/21 PASS**
  (`Ran 21 tests … OK`, with `-W error::ResourceWarning`).
- Updated probe `test_surge_webview_crypto_probe.js`: **20/20 PASS, 0 FAIL**.
  Out record regenerated: `test_surge_webview_crypto_probe_out.json`
  (SHA `814a911e…`, 20 PASS lines incl. the two new atob tests).
- Verifier `test_surge_webview_signed_proof.js`: **19/19 PASS, 0 FAIL,
  1 KNOWN LIMITATION** (unchanged).
- Replay negative control `test_webview_replay_negative_control.js`:
  **4/4 PASS, 0 FAIL, 1 KNOWN LIMITATION** (unchanged).

## 7. New negative control — snapshot-restore limitation

New file `test_nonce_snapshot_restore_limitation.py`
(SHA `3c842de1…f4a`, record `test_nonce_snapshot_restore_limitation_out.json`
SHA `47562018…600`): register a nonce, `PRAGMA wal_checkpoint(TRUNCATE)`
so all pages live in the main DB file, copy the DB aside, consume the
nonce (True), verify a second consume is rejected and counts are (1, 1),
remove `-wal`/`-shm` sidecars, restore the pre-consume copy over the live
DB, reopen, and show the same nonce CAN be consumed again. Result:
**1 PASS, 0 FAIL, 1 KNOWN LIMITATION (snapshot restore resurrects consumed
nonce)**, exit 0, deterministic across 5 repeats. The test asserts the
resurrection happens — it proves GPT's documented limitation #3 is real
and that the ledger alone is not end-to-end replay protection. It is a
limitation demonstration, not a suite failure.

## 8. CI

New workflow `ci/issue73-c3c0-round7.yml`
(SHA `a2fe78176c7e54f34fa8bb49629036336f9538aa08df74e4e7c43c3cc72aab78`): syntax/compile
check + nonce ledger 21-case suite + updated probe 20-check suite +
snapshot-restore limitation demo, with a nonzero-failure gate (the demo
exits 0 while reporting the limitation). GPT's PR #106 and PR #107
workflows absorbed unchanged.

## 9. All suites + clean copy

Eighteen suites, **220 PASS / 0 FAIL / 1 LIMITATION**: v2 regression
28/0/1 (V23, `RUNTIME_HARD_TIMEOUT_UNPROVEN`, frozen timer — unchanged),
store-failure 5/5, S1 live adapter 10/10, S1 11/11, S3 14/14,
bootstrap (deprecated approach, logic record only) 7/7, bootstrap
candidate 13/13, candidate regressions 14/14, rollback hermetic
(positive PASS + negative control FAIL as expected), provisioning demo
5/5, promotion gate 17/17, signed-proof adversarial 15/15, negative
control 5/5, dual token 12/12, WebView probe 20/20 (was 18/18), WebView
verifier 19/0/1, replay control 4/0/1, nonce ledger 21/21 (new). The
1 LIMITATION is the v2 V23 frozen-timer item; the verifier, replay
control, and snapshot-restore demo limitations are the same underlying
stateless-replay / snapshot-restore theme. Delta vs Round 6 (197):
+23 (probe +2, nonce ledger +21). Clean-copy verification PASS from a
fresh `/tmp/c3c0-clean-copy-r7/` (88 files, all eighteen suites +
limitation demo; v2.2 SHA `8691e962…abfc` in the copy).

## 10. Secret scan

All 12 new/changed Round 7 files scanned for the real DEV token, real
API key, real URLs, node URIs, and the VPS IP: **0 hits**. Only
placeholders, synthetic `TEST-*` tokens, public RFC 8032 test vectors,
and the public `AQIDBA==` → bytes 1–4 vector (all explicitly public,
not credentials). The word "secret" appears only in prose ("no secrets",
"non-secret", Python stdlib `import secrets`).

## 11. Device evidence scope

Unchanged. `DEVICE_EVIDENCE_ALIGNMENT.md` NOT touched: the owner's
reported device acceptance covers the NODE POOL only; it does NOT cover
Ed25519/WebCrypto support (PR #104 probe NOT run on the real device,
NOT approved for auto-execution; Node VM CI is not device proof), the
two cron fence verifications, the logs/Shortcuts history privacy check,
or the running source script SHA / Surge version / iOS version. All 15
rows remain UNVERIFIED. `DEVICE_EVIDENCE_CORRELATION=OPEN`,
`DEVICE_ACCEPTANCE=USER_REPORTED` (node-pool scope only).

## 12. Not built / not done

- The WebView probe has NOT been run on the real device and is NOT
  approved for auto-execution; the PR #105 verifier is a library, NOT a
  standalone Surge script.
- The nonce ledger is a single-host server reference, NOT a deployed
  signing endpoint: no HTTP service, no authenticated handler wiring,
  no pinned-key distribution, no durable token table, no rollback-resistant
  epoch / high-water mark / audit anchor (the snapshot-restore demo shows
  why that is still required), no device-side durable single-use consume.
- P2/P3 node auto-isolation/deletion were NOT opened. `AUTO_DELETE=OFF`.

## 13. Gates (unchanged)

`BOOTSTRAP_SECURITY_GATE=BLOCKED`. `CREDENTIAL_DISTRIBUTION_GATE=BLOCKED`.
`C3-C1=NO-GO`. `PR93_CUTOVER=BLOCKED`. `AUTO_DELETE=OFF`.
`DEVICE_EVIDENCE_CORRELATION=OPEN`. `DEVICE_ACCEPTANCE=USER_REPORTED`
(node-pool scope only). `RELEASE_EVIDENCE_NOT_YET_COMPLETE`.
Old command 1795063030 `OUTCOME_UNKNOWN`, permanently fenced.
Live bridge/server/state, 21 pins, 5 timers, node pool unchanged.

## 14. Files to commit to PR #97 (branch `c3c0-sanitized-v2-review`)

| Target path | SHA-256 (short) | Status |
|---|---|---|
| `docs/surge-bridge-c3c0/nonce_ledger_sqlite.py` | `96dd9cb6…5d37` | NEW (PR #106) |
| `docs/surge-bridge-c3c0/test_nonce_ledger_sqlite.py` | `a612a32f…31a3c` | NEW (PR #106) |
| `docs/surge-bridge-c3c0/DURABLE_NONCE_LEDGER_GATE.md` | `3fd7c1e9…98f1` | NEW (PR #106) |
| `docs/surge-bridge-c3c0/surge_webview_crypto_probe.template.js` | `2eb650c6…6753` | REPLACE (PR #107) |
| `docs/surge-bridge-c3c0/test_surge_webview_crypto_probe.js` | `698926ec…452` | REPLACE (PR #107) |
| `docs/surge-bridge-c3c0/test_surge_webview_crypto_probe_out.json` | `814a911e…cd2` | REPLACE (regenerated 20/20) |
| `docs/surge-bridge-c3c0/SURGE_WEBVIEW_CRYPTO_GATE.md` | `e3b67183…165` | REPLACE (PR #107) |
| `docs/surge-bridge-c3c0/test_nonce_snapshot_restore_limitation.py` | `3c842de1…f4a` | NEW (Round 7) |
| `docs/surge-bridge-c3c0/test_nonce_snapshot_restore_limitation_out.json` | `47562018…600` | NEW (Round 7) |
| `docs/surge-bridge-c3c0/C3C0_REPORT.md` | `e91f1019…5d49d` | UPDATED (Round 7 addendum) |
| `docs/surge-bridge-c3c0/C3C0_ROUND7_REPORT.md` | self-referential (recompute at commit time) | NEW (this report) |
| `.github/workflows/issue73-durable-nonce.yml` | `c51abecf…885` | NEW (PR #106) |
| `.github/workflows/issue73-surge-webcrypto-probe.yml` | `04a5599d…fa75` | REPLACE (PR #107) |
| `.github/workflows/issue73-c3c0-round7.yml` | `a2fe7817…b78` | NEW (Round 7 CI) |
