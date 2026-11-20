# C3-C0 Round 9 Report — GPT PR #110 (loopback HTTPS proof) + PR #111 (insecure_context) + PR #112 (pure-JS Ed25519 verifier); first real device-side crypto evidence

**Date:** 2026-11-20 (Round 9 absorption, ~10:08–10:30 CST)
**Scope:** Absorb and cross-review GPT's three new Draft PRs (#110/#111/#112), update the device-evidence matrix with the owner's 09:31 CST real-device WebCrypto evidence (comment 7027571021), and close the Round 8 diff-reconstruction gap. No production changes. No token operations. No phone contact.
**Result:** All three PRs absorbed byte-identical from their exact head-branch refs. All suites pass locally. All three head CIs re-verified via the check-runs API (run numbers match GPT's claims exactly). Diff-apply reconstruction COMPLETE for all five PRs (#108–#112). **No code defects found — no F4+ finding.** Two record notes (not GPT defects): the Round 8 `*_out.json` files are local test-run records, not PR files; the patrol's PR #112 head note "04096c1" is stale. Twenty-eight suites, **347 PASS / 0 FAIL / 1 LIMITATION** (v2 V23 frozen timer).

## 1. PR heads (verified via authenticated connector, list_pull_requests)

| PR | Head SHA | Branch | Base | State |
|---|---|---|---|---|
| #110 | `354d2f4f4c3f42ecba4ca91b87e14acfd1f0c976` | `gpt6-issue73-https-proof-gate-20261120` | PR #109 head `0ee9fb00` | Draft, open |
| #111 | `7a5bba350492bf394a627dcfc2be1e871d30f294` | `gpt6-issue73-insecure-context-device-gate-20261120` | PR #110 head `354d2f4` | Draft, open |
| #112 | `849e5a8c5de96d838fdd62222c88d9f2cd71b959` | `gpt6-issue73-purejs-ed25519-verify-gate-20261120` | PR #111 head `7a5bba3` | Draft, open |

All three heads match GPT's stated values exactly (comments 7026232837 and 7027938781). The background patrol note claiming PR #112's head was "04096c1" does **not** match the current head — `list_pull_requests` returns head `849e5a8c`, updated 2026-11-20T01:55:16Z, and that is the head GPT's comment states. `04096c1` was either a transient intermediate or a misread; it is not the current head. 52 open PRs total.

## 2. Per-PR file attribution (blob-SHA diff of branch directory listings)

- **PR #110** (6 new docs files + 1 workflow): `P0_THREE_GATES_CHECKLIST.md` (7257), `credential_proof_https.py` (9589), `issue73_webcrypto_readonly.sgmodule` (1225), `surge_webview_crypto_status.js` (1405), `test_credential_proof_https.py` (13107), `test_device_probe_module.js` (3359), `.github/workflows/issue73-https-proof-integration.yml` (1668).
- **PR #111** (7 modified docs files + 1 workflow): `P0_THREE_GATES_CHECKLIST.md` (7257→7757), `SURGE_WEBVIEW_CRYPTO_GATE.md` (5529→6919), `issue73_webcrypto_readonly.sgmodule` (same size, new blob), `surge_webview_crypto_probe.template.js` (4303→4661), `surge_webview_crypto_status.js` (1405→1509), `test_device_probe_module.js` (3359→3641), `test_surge_webview_crypto_probe.js` (8081→8718), `.github/workflows/issue73-surge-webcrypto-probe.yml` (869, same size, new blob).
- **PR #112** (9 new docs files + vendor/ + 1 workflow): `PUREJS_ED25519_FALLBACK_GATE.md` (5042), `build_purejs_probe.js` (972), `issue73_purejs_probe_body.js` (2145), `issue73_purejs_probe_bundled.js` (85914), `issue73_purejs_readonly.sgmodule` (986), `issue73_purejs_status.js` (1078), `surge_purejs_signed_proof.review.js` (5050), `test_purejs_device_bundle.js` (4693), `test_purejs_signed_proof.js` (7659), `vendor/` (JS-SHA256-LICENSE.txt 1076, TWEETNACL-LICENSE.txt 1210, js-sha256-1.0.0.js 16658, tweetnacl-fast-1.0.3.js 61966), `.github/workflows/issue73-purejs-ed25519.yml` (2057).
- **PR #111 modifies 6 PR #110 files; PR #112 modifies no #110/#111 file (all new).** No PR modifies any PR #97 file. No files removed.

## 3. Fetched files (SHA-256, from the exact PR #112 head branch = final state of all three)

| File | SHA-256 (first 16) | Bytes | Origin |
|---|---|---|---|
| P0_THREE_GATES_CHECKLIST.md | `6e8e57b516407238` | 7757 | #110, mod #111 |
| credential_proof_https.py | `c638bfdda81641c0` | 9589 | #110 |
| issue73_webcrypto_readonly.sgmodule | `ae66e2460643cfc0` | 1225 | #110, mod #111 |
| surge_webview_crypto_status.js | `b1705df2bb8c7fa8` | 1509 | #110, mod #111 |
| test_credential_proof_https.py | `20e2d2b7b9062683` | 13107 | #110 |
| test_device_probe_module.js | `3f4959d0f961b521` | 3641 | #110, mod #111 |
| SURGE_WEBVIEW_CRYPTO_GATE.md | `7ed211b0e0b88acf` | 6919 | mod #111 |
| surge_webview_crypto_probe.template.js | `18c8ff5dadb604bf` | 4661 | mod #111 |
| test_surge_webview_crypto_probe.js | `a33daece843a6dbd` | 8718 | mod #111 |
| PUREJS_ED25519_FALLBACK_GATE.md | `7e5a0b5f78b609b7` | 5042 | #112 |
| build_purejs_probe.js | `5980c9fb918ecfdd` | 972 | #112 |
| issue73_purejs_probe_body.js | `947157cbe240124a` | 2145 | #112 |
| issue73_purejs_probe_bundled.js | `633952f506e99ebd` | 85914 | #112 |
| issue73_purejs_readonly.sgmodule | `420b4cd33540c1a3` | 986 | #112 |
| issue73_purejs_status.js | `e6be6f2300bd90d8` | 1078 | #112 |
| surge_purejs_signed_proof.review.js | `422c18354cfce594` | 5050 | #112 |
| test_purejs_device_bundle.js | `4dc23cb20b87874f` | 4693 | #112 |
| test_purejs_signed_proof.js | `b25e566b2ac20474` | 7659 | #112 |
| vendor/JS-SHA256-LICENSE.txt | `2153bd2978793748` | 1076 | #112 |
| vendor/TWEETNACL-LICENSE.txt | `88d9b4eb60579c19` | 1210 | #112 |
| vendor/js-sha256-1.0.0.js | `d14e31deaf7b7c3a` | 16658 | #112 |
| vendor/tweetnacl-fast-1.0.3.js | `6bcd37a3b20dce91` | 61966 | #112 |
| ci/issue73-https-proof-integration.yml | `dfda102d60e2f179` | 1668 | #110 |
| ci/issue73-surge-webcrypto-probe.yml | `e4b3383da2a81b9e` | 869 | mod #111 |
| ci/issue73-purejs-ed25519.yml | `e5b8803379c9737f` | 2057 | #112 |

Full SHA-256 values are in the parent's handoff report. All 25 files were fetched via the authenticated connector (`get_file_contents`, ref `gpt6-issue73-purejs-ed25519-verify-gate-20261120`); byte counts match the branch directory listings exactly, and the returned Git blob SHAs match the listings.

## 4. Test results (all run locally, isolated venv /tmp/r9-venv, cryptography==46.0.4)

| Suite | Command | Result |
|---|---|---|
| HTTPS proof (PR #110) | `/tmp/r9-venv/bin/python -W error::ResourceWarning -m unittest test_credential_proof_https.py` | **22/22 PASS** (`Ran 22 tests … OK`, 11.4s) |
| Device probe module (PR #111) | `node test_device_probe_module.js` | **9/9 PASS** (`SUMMARY 9 PASS, 0 FAIL`) |
| WebView crypto probe (PR #111) | `node test_surge_webview_crypto_probe.js` | **22/22 PASS** (`SUMMARY 22 PASS, 0 FAIL`) |
| PureJS signed proof (PR #112) | `node test_purejs_signed_proof.js` | **23/23 PASS, 1 KNOWN LIMITATION: stateless replay** |
| PureJS device bundle (PR #112) | `node test_purejs_device_bundle.js` | **11/11 PASS** (`SUMMARY 11 PASS, 0 FAIL (synthetic only)`) |
| Bundle --check (PR #112) | `node build_purejs_probe.js --check` | **BUNDLE EXACT SOURCE MATCH 85914** |
| Cross-review probes R9 (mine) | `/tmp/r9-venv/bin/python -W error::ResourceWarning -m unittest test_r9_cross_review_probes.py` | **5/5 PASS** |
| Issuer (R8, regression) | `… -m unittest test_signed_proof_issuer.py` | 16/16 PASS |
| Registry (R8, regression) | `… -m unittest test_atomic_token_registry.py` | 21/21 PASS |
| Nonce ledger (R7, regression) | `… -m unittest test_nonce_ledger_sqlite.py` | 21/21 PASS |
| R8 probes (regression) | `… -m unittest test_r8_cross_review_probes.py` | 4/4 PASS |
| Issuer interop (R8) | `PATH=/tmp/r9-venv/bin:$PATH node test_signed_proof_issuer_webview.js` | 7/7 PASS |
| Registry webview (R8) | `PATH=/tmp/r9-venv/bin:$PATH node test_atomic_token_registry_webview.js` | 7/7 PASS |
| Snapshot demo (R7) | `python3 test_nonce_snapshot_restore_limitation.py` | 1/0/1 (separate) |

Note: the interop JS tests shell out to `python3`, so they only pass when a Python with `cryptography` is on PATH (the venv was used); the CI workflows install `cryptography==46.0.4`, so CI is unaffected. `/tmp/r8-venv` was deleted by a service restart mid-round; a fresh `/tmp/r9-venv` was created with the same pinned version and all suites were re-run in it (identical results).

**Totals: twenty-eight suites, 347 PASS / 0 FAIL / 1 LIMITATION** (v2 V23 frozen timer; the PureJS stateless-replay limitation is the same underlying theme as the verifier/replay-control limitations). Delta vs Round 8 (275): +72 (probe 20→22, +2; HTTPS 22; module 9; purejs 23; bundle 11; R9 probes 5). Clean-copy verification PASS (fresh `/tmp/c3c0-clean-copy-r9-full/`, 112 files, all 28 suites + snapshot demo + rollback re-run from the clean copy).

## 5. Head CI verification (check-runs API, NOT taken on trust)

| PR head | Checks | Result |
|---|---|---|
| #110 `354d2f4` | 3 | **3/3 success** — `real-local-tls` run 44645123332, `isolated` run 44645123072, `real-script-s1` run 44645123042 (identical to GPT's claimed runs) |
| #111 `7a5bba3` | 4 | **4/4 success** — `isolated` run 44655595134, `real-local-tls` run 44655595126, `real-script-s1` run 44655595084, `isolated` run 44655595055 (identical to GPT's claimed runs) |
| #112 `849e5a8c` | 3 | **3/3 success** — `real-script-s1` run 44656968557, `isolated` run 44656968540, `isolated` run 44656968531 (identical to GPT's claimed runs) |

The two plain `isolated` jobs on #111 and #112 share a job name, so individual run-to-workflow attribution for those is by elimination, not by a workflow-name field; the run IDs and conclusions are exact.

## 6. Diff-apply reconstruction (COMPLETE — closes the Round 8 PENDING item)

Public-API quota reset at 10:17 CST (remaining 59). All five diffs fetched via the diff endpoint and applied with `git apply`:

| PR | Method | Result |
|---|---|---|
| #108 | empty tree | **6/6 files in the diff byte-identical** to the absorbed files |
| #109 | empty tree | **7/7 files in the diff byte-identical** |
| #110 | empty tree | **7/7** (3 directly vs workspace; 4 verified against the #110 branch versions, which #111 later modified) |
| #111 | on top of the #110 reconstruction + the 4 pre-existing #109-base files | **8/8 byte-identical** |
| #112 | empty tree | **14/14 byte-identical** (incl. all 4 vendor files) |

**Round 8 `*_out.json` correction:** the two `*_out.json` files per PR (#108: `test_signed_proof_issuer_out.json`, `test_signed_proof_issuer_webview_out.json`; #109: `test_atomic_token_registry_out.json`, `test_atomic_token_registry_webview_out.json`) do **not** exist on the PR head branches (verified: `get_file_contents` returns "file does not exist" for both the head and base refs) and do **not** appear in the PR diffs (0 occurrences). They are **local test-run records generated by running the suites** (their contents are the actual test names and PASS lines from the local runs, e.g. `test_01_signs_canonical_proof … ok`), not files from GPT's PRs. They were correctly generated and committed in Round 8 as Muse's own result records; the Round 8 receipt's wording implied they were absorbed from the PRs, which is corrected here and in `C3C0_REPORT.md`. No action needed beyond this correction.

## 7. Cross-review (independent verification, not a re-run of GPT's suites)

**HTTPS service (`credential_proof_https.py`) — verified by code + probes P3/P4/P5:**
- `LoopbackTLSServer` refuses any host other than exactly `127.0.0.1` (`public_network_binding_not_authorized`) and any TLS minimum below 1.2 (`TLS_1_2_minimum_required`); verified by probe P4 (0.0.0.0, 192.168.1.1, TLS 1.1 all raise ValueError; 127.0.0.1 + TLS 1.2 accepted).
- Pairing bearer: `PAIRING_RE ^[A-Za-z0-9_-]{43,128}$`, compared with `hmac.compare_digest`; independent of the old exposed DEV token and of the credential being promoted. Wrong/missing bearer → 401 with **zero** ledger writes (probe P5, `ledger.counts() == (0, 0)`).
- Request gates: `Content-Type` must be exactly `application/json`; body 1–2048 bytes; duplicate JSON keys rejected (`_unique_pairs`); field set must be exactly `{nonce, kind, token_id, candidate_fingerprint}`; `nonce_hash` + `binding` validation runs **before any DB write**; clock sanity-checked; all failures fail closed (400/401/403/409/503, never 500).
- Nonce registration precedes issuance; a failed issuance deliberately burns the nonce (no retry, no fallback to the old token). Replay of the same nonce → 409 (probe P3, over real HTTPS). Concurrent replay → only one proof (GPT test_22, re-run locally as part of the 22).
- No logging of request body, authorization header, or response contents (`log_message` suppressed; no other logging calls). Registry and ledger must be the same DB (`registry.ledger.path != ledger.path` → error).
- Issuer session is bound to the service instance itself (`session is self`), so only this service can authorize issuance.

**Insecure-context modeling (PR #111) — verified by code + probe P1:**
- The probe checks `isSecureContext === false` FIRST (after the editor/intent trigger gate) and reports `insecure_context` even when a mocked `crypto.subtle` would pass every check (probe P1, case A). With `isSecureContext` true or undefined and no subtle, it reports `no_webcrypto` (probe P1, cases B/C). The distinction is exactly the owner's device evidence, and it does not conflate insecure context with hardware incompatibility.
- The two new suite cases ("insecure iPhone editor WebView context is distinct and fail closed", "insecure context without subtle still reports insecure_context") model the observed device inputs. The 11-enum allowlist in the panel test includes `insecure_context`, rendered as an alert without release approval.
- Existing statuses are preserved (`no_webcrypto` remains for other absence cases); the probe writes only the allowlisted non-secret enum and calls `$done()` exactly once; non-editor/intent triggers write nothing.

**Pure-JS verifier (PR #112) — verified by code + probes P2/P3 + blob checks:**
- Vendor blobs independently verified: computed git blob SHA of `vendor/tweetnacl-fast-1.0.3.js` = `7ea5fb5883289b49f8d543f2d48af7132c3c6a6d` (pinned), of `vendor/js-sha256-1.0.0.js` = `edb15da8e79be6cb3878dc2b81c67d2cdbbb302e` (pinned). The CI workflow enforces the same check with `git hash-object`. Licenses present (TweetNaCl public domain, js-sha256 MIT 2014–2026 Chen, Yi-Cyuan).
- Canonical JSON field order (purpose, kind, ok, fingerprint_matches, token_id, fingerprint, nonce, issued_at, expires_at) is byte-identical to the Python issuer (`json.dumps` with `separators=(",", ":")`) and to the PR #105 JS verifier. **Probe P2 proves the chain end-to-end**: a proof signed by the Round 8 Python atomic issuer is accepted by the Pure-JS verifier, and the tampered-fingerprint copy is rejected. **Probe P3 proves the full chain**: a proof obtained over real HTTPS from the loopback service is accepted by the Pure-JS verifier.
- The verifier enforces: pinned public key (32-byte hex), locally hashed candidate fingerprint, old/new token ID separation (`token_id != oldTokenId`), trusted nonce equality (≥16 chars), purpose/domain, kind (`dev`/`localkey`), `ok`/`fingerprint_matches` true, issued/expiry windows (24h max age, 5min future skew, expiry after now and within issued+24h), signature shape (88-char base64, 64 bytes), and Ed25519 verification via the vendored TweetNaCl. Missing TextEncoder/atob/nacl/sha256 → fail closed. No network, no persistent writes, no `$done`, no console output (statically asserted by the suite).
- The 23-test suite genuinely exercises: real Node Ed25519 signing → pure-JS verify, corrupted signature, wrong key, changed candidate/fingerprint, wrong/tampered nonce, old token ID reuse, null/fake signature, expired/future proof, wrong purpose/kind, invalid trusted inputs, missing primitives, and the **stateless replay limitation stated explicitly** (same valid proof verifies twice — a documented limitation, not a replay-resistance pass).
- Bundle: `build_purejs_probe.js --check` reproduces the 85,914-byte bundle exactly from the four pinned sources. The bundle test (11/11) runs the real bundle in an insecure VM: editor/intent verify, cron/panel triggers write nothing, missing TextEncoder/atob fail closed, panel never leaks an arbitrary fake secret, module contains only manual generic scripts with 40-hex pinned URLs.

**Module pins — verified:**
- WebCrypto module pins commit `6babadf552bdc170b06abd3b9cf6001169dfd469`: the probe template and status script at that commit are byte-identical to the #111 versions (SHA `18c8ff5d…`, 4661 bytes; SHA `b1705df2…`, 1509 bytes). The commit is a proper ancestor of the #111 head (compare: ahead_by 1, behind_by 0).
- PureJS module pins commit `ac1f0a0ff7eed96e0d2df154dba25194ec3eebaa`: the bundled file and status script at that commit are byte-identical to the #112 versions (SHA `633952f5…`, 85914 bytes; SHA `e6be6f23…`, 1078 bytes). The commit is a proper ancestor of the #112 head (ahead_by 4, behind_by 0).

**Findings: NONE (no F4+).** No code defect, no documentation gap, and no TOCTOU/revocation gap was found in PRs #110/#111/#112. The known limitations are all honestly stated in the gate docs (single-host reference, in-flight revocation race, snapshot restore resurrects revoked tokens and consumed nonces, no device-side protection, no real-device crypto_ready evidence, no rate limiting on the loopback harness, stateless replay in the Pure-JS verifier). GPT's files were kept byte-identical.

## 8. Device evidence matrix (updated)

`DEVICE_EVIDENCE_ALIGNMENT.md` updated (new SHA `b94d865e…` — the parent will confirm the exact value after the commit; the pre-update SHA was `e2c188e6…fff2`). Added Round 9 addendum with rows 16–22:
- Rows 16–20 **VERIFIED-DEVICE** (source: Issue #73 comment 7027571021, owner, 2026-11-20 09:31 CST, Surge iOS script editor, Generic + WebView): `isSecureContext=false`, `crypto=yes`, `subtle=no`, `digest=missing`, `crypto_ready` NOT met (status `insecure_context`). Scope is strictly the editor-trigger runtime shown in the screenshot.
- Row 21 (module actual manual generic/intent context) **UNVERIFIED** — not separately measured.
- Row 22 (Pure-JS probe on device) **UNVERIFIED** — `PUREJS_DEVICE_PROBE=UNVERIFIED`.
- **Gate B: `BLOCKED: EDITOR_WEBVIEW_INSECURE_CONTEXT`.** Overall record status remains **OPEN** (original 15 rows still UNVERIFIED; correlation OPEN until generic/intent context and the Pure-JS probe are measured). No device token, private URL, or sensitive log value was collected or published.

## 9. Workflows (all `permissions: contents: read`)

- `issue73-https-proof-integration.yml` (PR #110): pins `cryptography==46.0.4`; runs the 22-test HTTPS suite + the module tests.
- `issue73-surge-webcrypto-probe.yml` (PR #111, modified): runs the 22-test probe suite.
- `issue73-purejs-ed25519.yml` (PR #112): enforces the vendor blob SHAs with `git hash-object`; runs the 23-test suite, the bundle `--check`, and the 11-test bundle suite.
- `issue73-c3c0-round9.yml` (mine, NEW): runs the 5 Round 9 cross-review probes (P1–P5) with `cryptography==46.0.4`.

## 10. Secret scan

0 hits across all 26 new/changed Round 9 files, the 6 out.json result records, the cross-review helper, and the Round 9 workflow (scanned against the real token/key values in `~/workspace/surge-bridge/tokens.env` and against the private host/IP/URL patterns). Only placeholders, synthetic `TEST-*` tokens, public test vectors, and runtime-generated test keys (never committed). No real credential or private key is committed.

## 11. Commit list for PR #97 (for the parent to submit via browser)

Target: `docs/surge-bridge-c3c0/<file>` and `.github/workflows/<file>`, branch `c3c0-sanitized-v2-review`. All files below are in `~/workspace/pr96-c3c0/` (docs files at top level, workflows under `ci/`).

**Batch 1 — docs/surge-bridge-c3c0/ (NEW, 19 files):**
`P0_THREE_GATES_CHECKLIST.md` (6e8e57b5…), `credential_proof_https.py` (c638bfdd…), `issue73_webcrypto_readonly.sgmodule` (ae66e246…), `surge_webview_crypto_status.js` (b1705df2…), `test_credential_proof_https.py` (20e2d2b7…), `test_device_probe_module.js` (3f4959d0…), `PUREJS_ED25519_FALLBACK_GATE.md` (7e5a0b5f…), `build_purejs_probe.js` (5980c9fb…), `issue73_purejs_probe_body.js` (947157cb…), `issue73_purejs_probe_bundled.js` (633952f5…), `issue73_purejs_readonly.sgmodule` (420b4cd3…), `issue73_purejs_status.js` (e6be6f23…), `surge_purejs_signed_proof.review.js` (422c1835…), `test_purejs_device_bundle.js` (4dc23cb2…), `test_purejs_signed_proof.js` (b25e566b…), `test_r9_cross_review_probes.py` (d73b5b5c…), `test_r9_js_verify_helper.js` (281d6e86…), `test_credential_proof_https_out.json` (d75467b5…), `test_device_probe_module_out.json` (69ff1f8c…), `test_purejs_signed_proof_out.json` (6a143e3a…), `test_purejs_device_bundle_out.json` (24225409…), `test_r9_cross_review_probes_out.json` (a0bb1ffb…). Also `vendor/JS-SHA256-LICENSE.txt` (2153bd29…), `vendor/TWEETNACL-LICENSE.txt` (88d9b4eb…), `vendor/js-sha256-1.0.0.js` (d14e31de…), `vendor/tweetnacl-fast-1.0.3.js` (6bcd37a3…) — the vendor/ subdirectory needs a separate upload batch (4 files).

**Batch 1b — docs/surge-bridge-c3c0/ (UPDATED, 4 files):**
`SURGE_WEBVIEW_CRYPTO_GATE.md` (7ed211b0…), `surge_webview_crypto_probe.template.js` (18c8ff5d…), `test_surge_webview_crypto_probe.js` (a33daece…), `test_surge_webview_crypto_probe_out.json` (f02a3758… — regenerated local record for the 22/22 run), `C3C0_REPORT.md` (updated, Round 9 addendum), `DEVICE_EVIDENCE_ALIGNMENT.md` (updated, Round 9 addendum), `C3C0_ROUND9_REPORT.md` (NEW, this file).

**Batch 2 — .github/workflows/ (NEW 3, UPDATED 1):**
NEW `issue73-https-proof-integration.yml` (dfda102d…), NEW `issue73-purejs-ed25519.yml` (e5b88033…), NEW `issue73-c3c0-round9.yml` (mine); UPDATED `issue73-surge-webcrypto-probe.yml` (e4b3383d…).

**Note on `test_r9_cross_review_probes.py`:** the file was edited after the out.json was first generated (two unclosed-file `ResourceWarning`s fixed in the probe itself, plus the helper moved from `/tmp` into the repo). The final probe file (SHA `a0bb1ffb…`) was re-run clean (5/5, no warnings) and the out.json was regenerated from that clean run — the out.json SHA above is the regenerated one. The helper SHA `281d6e86…` is the final repo file.

**Not committed:** nothing from the production VPS, no real tokens/keys/URLs, no phone state. `bridge_fixed_v2.js` unchanged (SHA `8691e962…abfc`, 571 lines).

## 12. Gates (unchanged)

`BOOTSTRAP_SECURITY_GATE=BLOCKED`. `CREDENTIAL_DISTRIBUTION_GATE=BLOCKED`. `C3-C1=NO-GO`. `PR93_CUTOVER=BLOCKED`. `AUTO_DELETE=OFF`. `DEVICE_EVIDENCE_CORRELATION=OPEN` (rows 16–20 are now VERIFIED-DEVICE for the editor trigger only; rows 21–22 and the original 15 remain UNVERIFIED). `DEVICE_ACCEPTANCE=USER_REPORTED` (node-pool scope only). `PUREJS_DEVICE_PROBE=UNVERIFIED`. `REAL_PRIVATE_HTTPS=NOT_DEPLOYED`. `TOKEN_ROTATION_LIVE=NO-GO`. Old command 1795063030 `OUTCOME_UNKNOWN`, fenced.

## 13. What is NOT done (for the parent / GPT)

- The Pure-JS probe has NOT been run on the real device (needs a separate explicit device approval; the module is not installed).
- The HTTPS service is loopback-only; the real private-VPS staging integration (independent test port/process/data volume, TLS cert chain/reverse proxy, device pairing, rollback rehearsal) is the parent's next task per GPT 7027938781 — this agent did not touch the VPS.
- The snapshot-restore resurrection (consumed nonce / revoked token) still has no rollback-resistant epoch / high-water mark / audit anchor — a production prerequisite, honestly stated in the gate docs.
- No F4+ finding was produced this round, so there is nothing for GPT to fix in the code; the open items are the device measurements (generic/intent context, Pure-JS probe) and the private-VPS staging work.
