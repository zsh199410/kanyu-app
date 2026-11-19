# C3-C0 S1+S3 Summary — Receipt-ready fields

Date: 2026-11-19. Project: PR #96 / Issue #73, C3-C0-S1 + C3-C0-S3.
Scope: DESIGN + isolated verification only. No live file touched, no live
credential revoked or rotated, no GitHub post, no phone contact.
All work under `~/workspace/pr96-c3c0/`.

## Receipt fields

| Field | Result |
|---|---|
| SECURITY_GATE_PLAN | **DELIVERED** — `SECURITY_GATE_PLAN.md` (348 lines). Credential inventory + risk grading, secret-free distribution design, rotation / parallel-cutover / rollback plan, abnormal-access audit, gate statement. |
| V2_SANITIZED_COMMIT | **PENDING (sibling's deliverable, not this task)** — the v2 desensitised diff is ready (`C3C0_MINIMAL_PATCH_V2.md`, 109 → 506 lines, v2 script SHA `b3c0b340…86135`). No public commit exists yet; the parent agent must submit it as a Draft PR and record the commit SHA. |
| V2_TEST_RESULTS | **28 PASS, 0 FAIL, 1 LIMITATION** (sibling's `test_fixed_v2_out.json`, suite `fixed-v2-regressions`). The 1 limitation is the frozen-timer case (`RUNTIME_HARD_TIMEOUT_UNPROVEN`). PR #96 reference suite re-run locally: 23/23 PASS. |
| ID_ALLOCATOR_DESIGN | **DELIVERED (DRAFT)** — `ID_ALLOCATOR_DESIGN.md` (264 lines). Server-side allocator: `candidate = max(now_ms, last_allocated + 1)`, persisted atomically, idempotency-key map, canonical `orderMillis` increasing check. Production implementation needs a separate review. |
| PUBLIC_SECRET_SCAN_STATUS | **Anonymous fetch: YES. Exposure: YES.** (See §1 below. No values in this file.) All S1/S3 deliverables scanned: CLEAN (see §4). |
| LIVE_UNCHANGED | **PASS** — nothing under `/opt/surge-bridge/` was modified (read-only SSH reads only); no GitHub post; no phone/production contact; no live credential revoked or rotated. 21 pins, 5 timers, node pool, STOP, PR #93 BLOCKED, old command OUTCOME_UNKNOWN — all unchanged. |

## 1. PUBLIC_SECRET_SCAN_STATUS (booleans only, no values)

- Anonymous fetch of the public script URL (no auth headers): **YES**
  (HTTP 200, content byte-for-byte identical to the live bridge.js,
  SHA matches). Verified privately by the parent agent; the URL, the
  token, and the key are NOT reproduced here.
- Long-lived credential exposed in the publicly served script: **YES**.
  The live bridge.js contains the long-lived DEV token and the local
  Surge HTTP API key in plaintext. The ADMIN token is NOT in the script.
- Historical access (observed window only): 14 requests to the public
  script + module paths, 3 distinct IPs (the phone's two carrier IPs and
  the VPS itself, the latter being the parent agent's own tests). No
  unknown third-party IP in this window — but the window is short and the
  URL has been live longer, so this does NOT prove no leak. Grade:
  **possibly leaked**. Treat both credentials as compromised until
  rotation completes.
- Consequence: **CREDENTIAL_DISTRIBUTION_GATE = BLOCKED**.
  C3-C1 = NO-GO until the gate conditions in `SECURITY_GATE_PLAN.md` §5
  hold (isolated verification done here; rotation plan approved; new
  distribution confirmed on the phone; audit running with a clean
  baseline).

## 2. Risk grades (from SECURITY_GATE_PLAN.md §1)

| Credential | Grade |
|---|---|
| DEV token (device token, long-lived) | **EXPOSED** — anonymous fetch 200, SHA match, plaintext in the public script. Scope: /poll, /result, /diagnostic, /receipt. Cannot issue commands. |
| ADMIN token (admin token, long-lived) | **CONTAINED** — server config only (root-only), not in any distributed file. Must never be added to a distributed script. |
| Local Surge HTTP API key | **EXPOSED in the public script — lower remote value** (localhost-only API). Must still leave the distributed script. |
| Script / module download-path hashes | **NOT SECRET (obscurity only)** — the module is served unauthenticated and contains the script URL. Randomizing the URL is NOT a fix. |
| Diagnostic token (C2-B, scoped) | **REVOKED** — revocation verified by 403 on reuse. Not a current risk. |

## 3. S1 isolated verification (s1/, 8/8 PASS)

Suite `s1-secret-free-distribution`: **8 PASS, 0 FAIL, 0 LIMITATION.**
Static scan (no credential in the distributed script), fail-closed with
no credential, normal operation from `$persistentStore`, rotation cutover
(parallel window → revoke → 403), old token rejected after revocation,
rollback restores old-token acceptance, anomalous-access audit (unknown
IP flagged, no full token in the log), local key absent → fallback
skipped. Full results: `s1/s1_out.json`.

## 4. S3 isolated verification (s3/, 10/10 PASS)

Suite `s3-id-allocator`: **10 PASS, 0 FAIL, 0 LIMITATION.** Strictly
increasing across 1000 allocations; no duplicates with 50 allocations in
the same millisecond; no repeats across a simulated restart; idempotency
key returns the same id; seconds id normalized to ms for ordering (raw
comparison shown wrong in both directions); new id greater than any last
result id (s and ms); refuses when a pending command exists (409); clock
backwards preserves monotonicity; overflow / invalid clock fails closed;
corrupt allocator state fails closed. Full results: `s3/s3_out.json`.
Two real bugs were caught and fixed during this round (idempotency check
must precede the pending check; the mock store must catch JSON parse
errors) — see `s3/README.md`.

## 5. Server-side gap (ID allocation)

Verified read-only against the live server code (`mailbox_ack.py`,
`server_http_commit.py`): the server does NOT generate command IDs;
`/issue` accepts a caller-supplied id; `_valid_id` only checks
`int` in `(0, 2^53-1]`; `issue_if_empty`'s `command_id_not_increasing`
check is a RAW numeric comparison (unit-blind, same bug class as the
phone dedup). Two callers issuing seconds-precision IDs in the same
second would collide. The draft allocator design
(`ID_ALLOCATOR_DESIGN.md`) fixes this server-side; production
implementation needs a separate review and must not be done as an
experiment on live state.

## 6. Deliverable file SHAs (SHA-256, for traceability)

| File | SHA-256 |
|---|---|
| SECURITY_GATE_PLAN.md | `6a2e44d8944c020f6bb3b4d5e3fd5164c5e5e73efaf62b9fdefffb86eddec43e` |
| ID_ALLOCATOR_DESIGN.md | `3ea582823cf983bbf3af26221e47a624d9f6f3be1fa59251846493e27bec1338` |
| s1/test_s1.js | `4f3382afadfa874b5280c027209633b7912dec31668477aa1741e1b14ab8c4b2` |
| s1/s1_out.json | `4615029b0634a7e232067281b7d3cbe2e6d20e63d903994876e7b5864f1ef5dc` |
| s1/README.md | `f8ced101358828323ae080847d20425f4e42b52591567b67ed32e7225741d544` |
| s3/test_s3.js | `c7272513dc06a3c1827b07cc7b57bb11d9ca033460768ab569f9f17c0de61b4b` |
| s3/s3_out.json | `339250203a96877958aa6ccc595620a99de19f519eaa6a92714f3eb678de5b8f` |
| s3/README.md | `2a719c404eb0bcb0251703316f88d430e2c4be881e3845c1830fb506712349d7` |

Related (sibling's C3-C0 v2 deliverables, same directory, not this task):

| File | SHA-256 |
|---|---|
| bridge_fixed_v2.js (506 lines) | `b3c0b34045d8b4cecbc86b1ae39ff8e7a778091f8aa45733592e704697986135` |
| test_fixed_v2.js | `c4fd41893b71faa72e4fa662dae02ea3e0f8970cc4a4b91ac2074c8563017eda` |
| C3C0_REPORT.md | (see that file for its own SHA table) |
| C3C0_MINIMAL_PATCH_V2.md | (see that file for its own SHA table) |

## 7. Secret scan (all S1/S3 deliverables)

Scan method: patterns built programmatically from the private bridge.js
copy (the DEV token value and the API key value), from the live script
path (read from the server config, never printed), and from generic
patterns (the bridge subdomain and domain strings, node URI schemes, and
the VPS IP). The scan reports match COUNTS only; no secret value is
reproduced here or in any scanned file. Result: **all 9 files scanned
(the 8 S1/S3 deliverables plus this summary) CLEAN (0 matches)**.
Note: the loopback address of the phone's local Surge API is
intentionally not a fail pattern — it is not a secret and it already
appears in the reviewable v2 script. Placeholders only
(`<DEV_TOKEN>`, `<API_KEY>`, `<BRIDGE_BASE>`, `TEST-DEV-*`,
documentation-range IPs `192.0.2.x` / `198.51.100.x` / `203.0.113.x`).

## 8. What is NOT done (gaps / next steps)

- **PUBLIC_SANITIZED_DIFF_COMMIT**: no public commit exists yet. The
  parent agent must submit the desensitised v2 diff as a Draft PR and
  record the commit SHA.
- **Server token-table change** (accept a SET of DEV tokens during the
  parallel window) and **server allocator implementation**: designs are
  in `SECURITY_GATE_PLAN.md` §3 and `ID_ALLOCATOR_DESIGN.md` §4; both
  need separate review + isolated tests before any production change.
- **One-time bootstrap UX** (§2.3 of the security plan): the exact Surge
  screen/flow for provisioning the new token must be confirmed with the
  owner before C3-C1.
- **ADMIN token rotation**: out of scope for this gate (contained); a
  separate, lower-urgency hygiene task if the operator wants it.
- **C3-C1 remains NO-GO** until the credential distribution gate passes.
  PR #93 remains BLOCKED. Old command 1795063030 stays OUTCOME_UNKNOWN
  and fenced.
