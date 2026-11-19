# C3-C0-S1 — Credential Security Remediation Plan (SECURITY_GATE_PLAN)

Date: 2026-11-19. Project: PR #96 / Issue #73, C3-C0-S1 (P0, highest).
Scope: DESIGN + isolated verification only. No live file touched, no live
credential revoked or rotated, no GitHub post, no phone contact.
Status: **CREDENTIAL_DISTRIBUTION_GATE=BLOCKED** until the conditions in
§6 are met. C3-C1=NO-GO until this gate passes.

All values below are roles, scopes, and booleans. No credential value, no
real URL, no real path, no IP, and no device identifier appears in this
document. The live script, its download path, and the tokens are referenced
only by role.

## 1. Credential inventory + risk grading

Grading scale: EXPOSED = confirmed reachable by an anonymous party;
POSSIBLY-LEAKED = treat as leaked (cannot prove otherwise);
CONTAINED = not present in any distributed or publicly reachable material;
REVOKED = verified unusable.

| # | Credential (role) | Scope (what it can do) | Where it lives | Used by | Grade | Evidence |
|---|---|---|---|---|---|---|
| 1 | DEV token (device token, long-lived) | GET /poll, POST /result, POST /diagnostic, GET /receipt. CANNOT issue commands (that needs the ADMIN token) and cannot do admin actions. A leaked DEV token lets an attacker impersonate the phone (poll the mailbox, post fake results/diagnostics) but NOT issue new commands. | VPS server config (root-only, 0600); the live bridge.js in plaintext; the phone's downloaded script copy. | The phone's bridge.js cron script (every 10 min). | **EXPOSED** | Anonymous fetch (no auth headers) of the public script URL returns HTTP 200 with the live bridge.js byte-for-byte (SHA matches the live file). The file contains this token in plaintext. The only protection is the obscurity of the download-path hash, which is itself exposed via the unauthenticated module endpoint (see #4). |
| 2 | ADMIN token (admin token, long-lived) | GET /status, POST /issue (issue new commands). This is the highest-privilege credential: whoever holds it can inject arbitrary commands to the phone. | VPS server config (root-only, 0600) ONLY. | The operator / automation that issues commands (authenticated admin channel). | **CONTAINED** | Not present in any distributed script or module. Verified: the live bridge.js and the module file contain no admin credential. MUST NEVER be added to a distributed script. If it ever appears in a distributed file, treat as a critical incident. |
| 3 | Local Surge HTTP API key | Direct HTTP to the phone's localhost Surge HTTP API (127.0.0.1:6171). Only meaningful on the phone itself. | Live bridge.js in plaintext (as the direct-HTTP fallback credential); the phone's Surge HTTP API configuration. | The bridge.js direct-HTTP fallback path (used only when $httpAPI is unavailable). | **EXPOSED (in the public script) — lower remote value** | Same anonymous-fetch evidence as #1: the key is in the publicly served script. Remote exploit value is low because the API listens on localhost only, but the key must still be removed from any distributed script (defense in depth; a localhost-only key in a public file is still a leaked credential). |
| 4 | Script download-path hash (24 chars) | Addresses the public script download. It is NOT a credential, but it is currently the ONLY thing standing between an anonymous party and the file in #1/#3. | VPS server config; the module file (which is itself served unauthenticated). | The phone's module (script-path) and any fetcher of the script. | **NOT SECRET (obscurity only)** | The module file is served unauthenticated and contains the full script download URL. Any party that fetches the module learns the script URL. Randomizing this hash is NOT a fix (see §3.4). |
| 5 | Module download-path hash | Addresses the public module download. Same obscurity-only status as #4. | VPS server config. | The phone's module subscription. | **NOT SECRET (obscurity only)** | Served unauthenticated; the path is guessable from the module subscription flow. |
| 6 | Diagnostic token (C2-B, scoped) | One-time diagnostic POST, time-limited, diagnostic scope only. | Was issued for a single diagnostic run. | The C2-B phone diagnostic. | **REVOKED** | Revocation verified by a 403 on reuse. No longer usable. Not a current risk. Listed here so it is not confused with a live credential. |

### Historical access evidence (current window only)

- Public script + module requests in the observed window: 14 total, 3 distinct
  IPs only — the phone (two carrier IPs) and the VPS itself (the parent
  agent's own anonymous-fetch tests). User-agents: Surge iOS and curl (the
  tests). Script responses: 3x 200, 2x 404 (the 404s were the parent agent's
  own failed-path probes). No unknown third-party IP accessed the script in
  this window.
- **This does NOT prove no leak.** The log window is short and the URL has
  been live longer. The correct grade is "possibly leaked" for the DEV token
  and the local API key: treat them as compromised until rotation completes
  (§4). Do NOT claim "clean" on the basis of a short log window.

### What a leaked DEV token can and cannot do

- CAN: poll the mailbox (read pending commands, including their actions),
  post a fake /result for a pending command (which clears the mailbox slot),
  post fake diagnostics, read /receipt confirmations.
- CANNOT: issue new commands (needs ADMIN), read /status (needs ADMIN),
  change server state beyond the device endpoints, or execute anything on
  the phone (execution happens only in the phone's own script).
- Impact if exploited: an attacker could read pending commands, inject fake
  results that make a real command look completed (clearing the slot), or
  spam diagnostics. They could NOT push a new command to the phone. The
  risk is real but bounded — which is why the gate is BLOCKED (fix before
  C3-C1) rather than an emergency shutdown of the bridge.

## 2. Secret-free script distribution design

### 2.1 Principle

The distributed bridge.js must contain **no long-lived credential**. All
credentials live in the phone's `$persistentStore` (Surge's per-script
persistent key-value store) and are read by the script at runtime. The
distributed script is then safe to fetch anonymously: even if the whole
world downloads it, they learn no credential.

### 2.2 What changes in the script

- The script keeps placeholders for its endpoints (base URL) but reads the
  DEV token and the local HTTP API key from `$persistentStore` at startup:
  - `sgbridge_cred_dev` — the DEV token (device token).
  - `sgbridge_cred_localkey` — the local Surge HTTP API key (only used by
    the direct-HTTP fallback; prefer `$httpAPI`, which needs no key).
- The script NEVER writes a credential to a log, a phase record, a
  diagnostic, or a /result payload. Phase records carry only
  `{phase, id, cat, tb}` (already the rule in v2).
- If a credential is absent, the script fails closed (§2.4).

### 2.3 How the credential gets into $persistentStore the first time

One-time owner step (the owner is the only party that handles the raw
credential; it is never committed to a file, never pasted into a public
Issue/PR, and never embedded in a distributed script):

1. The owner generates (or the operator provides) the NEW device token on
   the trusted VPS (see §4 for the rotation order — the new token is created
   BEFORE the old one is revoked, and both are accepted during the parallel
   window).
2. The owner provisions the new token into the phone by ONE of these
   channels (in preference order):
   - (a) A one-time local bootstrap script run manually on the phone: a
     minimal Surge script that the owner runs once from the Surge app, which
     writes the token (pasted by the owner into the script's local input)
     into `$persistentStore` under `sgbridge_cred_dev`, then the owner
     deletes that bootstrap script. The bootstrap script is never
     distributed, never uploaded, and is deleted immediately after use.
   - (b) If the owner prefers, the same value can be entered through any
     other private, ephemeral channel the owner controls (e.g. a local note
     that is deleted after provisioning). The channel must not be a file
     that is synced, shared, or publicly reachable.
3. The owner verifies provisioning by checking that the next cron round
   produces a `credential_present` phase (visible in the phone's phase log)
   and that the server sees a /poll with the NEW token (see §4.3 for the
   server-side confirmation signals).
4. Fallback if provisioning fails: the script keeps failing closed (no
   network call, visible `credential_missing` phase). The OLD script (with
   the old embedded token) keeps working until the new distribution is
   confirmed — the owner is never left without a working bridge because of
   a failed provisioning step. The rollback is to restore the old script
   (§4.5).

Note: the bootstrap step is the ONLY time the owner handles the raw token.
After provisioning, the token lives only in `$persistentStore` (on the
phone) and in the VPS server config (root-only). It never appears in a
distributed file again.

### 2.4 Fail-closed behaviour when a credential is absent

If `sgbridge_cred_dev` is absent (or empty) at startup:

- The script makes ZERO network calls (no /poll, no /result, no
  diagnostic). It must not attempt an unauthenticated poll.
- It records a visible phase `credential_missing` (phase log only, no
  network) and calls `$done` exactly once.
- It does NOT execute any action, does NOT write `last_id`, and does NOT
  send a /result.
- If the server returns 403 (token revoked / rotated / wrong), the script
  records `auth_forbidden`, does NOT retry with a fallback credential, does
  NOT execute, and calls `$done` exactly once. A 403 is never treated as
  "try the old token" — the script has only the one credential in
  `$persistentStore`.

This guarantees the phone can never be bricked by a missing credential:
the worst case is a visible, diagnosable "no credential" state, and the
old script remains the fallback until the new one is confirmed (§4.5).

### 2.5 Local HTTP API key handling

- Prefer `$httpAPI` (Surge's in-app API), which needs NO key. The v2
  script already does this first.
- The direct-HTTP fallback (127.0.0.1:6171) must read its key from
  `$persistentStore` (`sgbridge_cred_localkey`), never from the distributed
  script. If the key is absent, the fallback is skipped (the action is
  reported as `outcome_unknown_no_retry` / `local_key_missing`, never
  retried blindly).
- The local key is rotated in the phone's Surge HTTP API settings and in
  `$persistentStore` together. Because it is localhost-only, its rotation
  urgency is lower than the DEV token, but it must still leave the
  distributed script.

### 2.6 Download-path authentication

- **Recommended: the distributed script contains no secrets, so anonymous
  fetch is safe.** The /s/ URL can keep its hash (obscurity) but it is no
  longer a security boundary. The security boundary is: (a) the DEV token
  is not in the file, and (b) the server only accepts the token from the
  phone's $persistentStore (i.e. from a party that already holds it).
- **Defense-in-depth (optional, not required for the gate):** a short-lived
  single-use download token for the script (valid ~5 minutes, single use,
  issued over an authenticated channel). This limits bulk harvesting of the
  script file itself, but it is NOT a substitute for removing secrets from
  the script — a leaked download token would still only yield a
  secret-free file.
- **Why randomizing the URL alone is NOT a fix:** the URL is exposed via
  the unauthenticated /module/ endpoint (the module contains the full
  script URL), and any URL can leak via logs, sharing, or observation. A
  secret that is only protected by "nobody knows the URL" is not protected.
  The fix is to remove the secret from the file, not to hide the file.

## 3. Rotation / revocation / parallel-cutover / rollback plan

This plan is a DESIGN. No step here has been executed. No live credential
has been revoked. The plan is ordered so that the bridge never loses
contact: the new credential is verified working BEFORE the old one is
revoked.

### 3.1 Preconditions (all must hold before step 3.2)

- (P1) The secret-free script (v2 + §2) is verified working in isolation
  (see §5): it reads the credential from a mock $persistentStore, polls,
  dispatches, and posts a result with a synthetic token; it fails closed
  with no credential.
- (P2) The server accepts a token table (old + new) during a parallel
  window. This is a server-side change (accept a SET of valid DEV tokens,
  not a single value) that must be reviewed and deployed separately; it
  does NOT change the /poll, /result, or /diagnostic wire format.
- (P3) The abnormal-access audit logging (§3.6) is in place BEFORE
  rotation, so the cutover can be observed and anomalous use of the old
  token after revocation is detectable.

### 3.2 Step-by-step rotation

| Step | Action | Who | Verification (observable signal) |
|---|---|---|---|
| R1 | Generate a NEW DEV token on the trusted VPS. Store it in the server config (root-only). Do NOT put it in any distributed file. | Operator (VPS) | New token exists in server config only. |
| R2 | Server accepts BOTH old and new DEV tokens (parallel window opens). The token table is the only change; wire format unchanged. | Operator (VPS) | A test /poll with the new token returns 200; a test /poll with the old token still returns 200. Both from the trusted VPS only (not from the phone yet). |
| R3 | Owner provisions the NEW token into the phone's $persistentStore via the one-time bootstrap (§2.3). The old token is NOT removed from the phone yet (the old script still has it embedded, but the new script reads only $persistentStore). | Owner (phone, one-time) | Phone phase log shows `credential_present` on the next cron round. |
| R4 | Phone runs the NEW secret-free script (loaded via the /s/ path) and polls with the NEW token. | Phone (cron) | Server access log shows /poll with the NEW token fingerprint succeeding (200) AND the old token fingerprint still succeeding during the window (the old script may still be cached on the phone for one round — this is expected). |
| R5 | Confirmation window: observe N consecutive polling rounds (N=3, i.e. ~30 min) where (a) every /poll uses the NEW token and succeeds, (b) every /result is posted with the NEW token and is ACKed, and (c) ZERO /poll or /result requests arrive with the OLD token fingerprint. | Operator (server log) | The three conditions hold for 3 consecutive rounds. This proves the phone has fully cut over and no longer needs the old token. |
| R6 | Revoke the OLD token server-side (remove it from the accepted token table). The old token is now dead. | Operator (VPS) | A test /poll with the OLD token returns 403 (from the trusted VPS). |
| R7 | Post-revocation watch: monitor for 24 hours. Any /poll or /result with the OLD token fingerprint must return 403 and trigger the alert rule (§3.6). If the phone itself starts failing (403 on the NEW token), that indicates a provisioning error — roll back (§3.5). | Operator (server log + alert) | 24h with zero successful old-token requests and zero new-token 403s. |
| R8 | (Separate, lower urgency) Rotate the local Surge HTTP API key: change it in the phone's Surge settings and in $persistentStore. Remove it from any distributed file. | Owner (phone) | Direct-HTTP fallback (if ever used) succeeds with the new key; the distributed script contains no key. |

### 3.3 Confirmation signals (what proves the phone uses the new credential)

Server-side, all observable without touching the phone:

- (C1) /poll requests carrying the NEW token fingerprint return 200 for
  at least 3 consecutive rounds (~30 min).
- (C2) /result requests carrying the NEW token fingerprint are ACKed
  (200 + accepted:true + acked_id matching) at least once.
- (C3) ZERO /poll or /result requests carrying the OLD token fingerprint
  for the same 3 consecutive rounds (proves the phone no longer uses the
  old token).
- (C4) After R6, a test /poll with the OLD token returns 403 (proves
  revocation took effect).
- (C5) The phone's phase log (read by the owner) shows
  `credential_present` and no `credential_missing` / `auth_forbidden`.

All five must hold before the rotation is declared complete. C1–C4 are
server-side; C5 is phone-side (owner reads the phase log).

### 3.4 What the parallel window is (and is not)

- It IS a period where the server accepts both tokens, so the phone can
  cut over without a flag day and without losing contact.
- It is NOT a period where either token is "less valid". Both are fully
  valid during the window. The window is bounded (target: until R5
  confirmation, then R6 revokes the old token; maximum 48 hours — if
  confirmation has not been achieved in 48h, the operator investigates
  rather than extending the window silently).
- During the window, the old token is still a live credential. The
  abnormal-access audit (§3.6) is the compensating control: any use of
  the old token from an unexpected IP is alerted immediately.

### 3.5 Rollback (and fail-closed behaviour if the phone loses contact)

- **Rollback trigger:** any of (a) the phone's /poll with the NEW token
  returns 403 for 2 consecutive rounds, (b) the phone stops polling
  entirely for 2 consecutive rounds after R3/R4, (c) the owner reports
  the phone shows `auth_forbidden` or `credential_missing` persistently.
- **Rollback action:** re-add the OLD token to the server's accepted token
  table (one config change, server restart/reload). Restore the OLD script
  (the embedded-token version) as the served /s/ file, OR re-provision
  the old token into $persistentStore — whichever restores contact fastest.
  The old script keeps working because the old token is valid again.
- **Fail-closed if the phone loses contact:** the bridge degrades to "no
  contact" (the phone polls, gets 403 or no credential, records a visible
  phase, does nothing). It does NOT execute actions, does NOT clear the
  mailbox, and does NOT brick Surge proxying (the bridge is independent of
  the proxy policy). The node pool, the 5 timers, and the 21 pins are
  unaffected. The operator investigates from the server log; the phone is
  never left in a state where it executes an untrusted command.
- **State protection:** rollback restores ONLY code/config (script file,
  token table). It NEVER backfills or rewrites `state.json`, `last_id`, the
  ledger, or the pending command. The old command stays OUTCOME_UNKNOWN and
  fenced.

### 3.6 Abnormal-access audit (server-side logging + alert rules)

Log (server-side, for every request to /s/, /module/, /poll, /result,
/diagnostic, /issue, /status, /receipt):

- Timestamp (UTC, second precision).
- Client IP.
- User-Agent.
- Endpoint + HTTP result code + bytes.
- Token fingerprint: a truncated hash of the presented token (e.g. the
  first 8 hex chars of SHA-256(token)) — NEVER the full token. For
  requests with no token (e.g. /s/, /module/), log `token: none`.
- For /poll and /result, also log the command/result id (an integer, not
  secret) so a fake-result injection can be correlated.

Alert rules (any one triggers an operator alert):

- (A1) A /poll, /result, or /diagnostic arrives with a valid DEV token
  fingerprint from an IP that is NOT in the known set (the phone's
  carrier IPs, the VPS itself). → Possible token reuse by a third party.
- (A2) /s/ or /module/ is fetched from an IP outside the known set. →
  Possible URL leak / harvesting.
- (A3) A burst of 403s (≥5 in 10 min) on /poll, /result, or /issue. →
  Possible token guessing or a revoked token being retried.
- (A4) Any request with the OLD (revoked) DEV token fingerprint AFTER
  R6. → Someone still holds the old token; investigate.
- (A5) Any /issue attempt that is not from the operator's channel or
  that presents a non-admin token. → Possible command-injection attempt.
- (A6) /poll or /result from an IP that has never been seen before AND
  with a User-Agent that is not the known Surge iOS string. → Possible
  impersonation.

Retention: keep the access log for at least 30 days; review weekly.
The log itself must not contain full tokens (fingerprints only).

## 4. Isolated verification (s1/)

The simulation in `s1/` (Node.js, no real tokens/URLs) verifies the
secret-free distribution end-to-end in isolation. Synthetic tokens only
(e.g. `TEST-DEV-AAA`). See `s1/README.md` and `s1_out.json` for the
per-test results. Summary of what is verified:

| Check | What it proves |
|---|---|
| Static scan: script contains no credential | The distributed script (desensitised, placeholders only) contains no token/key/URL. A grep for credential patterns returns zero matches. |
| Fail-closed with no credential | With an empty mock $persistentStore, the script makes 0 network calls, records `credential_missing`, calls $done exactly once. |
| Normal operation with credential | With the token in mock $persistentStore, the script polls, dispatches, and posts a result; the token is sent only in the auth header, never in a body/log. |
| Rotation cutover (parallel window) | Mock server accepts both old and new tokens; the phone provisions the new token; polls with the new token succeed; old-token polls drop to zero; after revocation the old token gets 403. |
| Old token rejected after revocation | After the mock server revokes the old token, a poll with it returns 403 and the script records `auth_forbidden`, executes nothing, calls $done exactly once. |
| Rollback restores old token | Re-adding the old token to the mock server's accepted set makes polls with it succeed again. |
| Anomalous-access audit | A poll from an unknown IP produces an audit entry with the IP, the token fingerprint (not the full token), and the result code. |
| Local key absent → fallback skipped | With no local key in $persistentStore, the direct-HTTP fallback is skipped and the action is reported as unknown (no blind retry). |

## 5. Gate statement

**CREDENTIAL_DISTRIBUTION_GATE = BLOCKED** until ALL of the following hold:

- (G1) The secret-free distribution (§2) is verified working in
  isolation (§4) — the s1 tests pass.
- (G2) This rotation plan (§3) is approved (by GPT / the operator).
- (G3) The new distribution is confirmed working on the real phone in
  observation mode (C3-C1, read-only first) — i.e. the phone loads the
  secret-free script, shows `credential_present`, and polls with the NEW
  token (C1–C5 in §3.3).
- (G4) The abnormal-access audit (§3.6) is running and has a clean
  baseline (no anomalous entries) before rotation.

Until then: **no live credential is revoked**. The old DEV token stays
valid (it is the only thing keeping the current bridge working). The
exposure is treated as "possibly leaked" and the compensating controls
are the audit logging (§3.6) and the bounded parallel window (§3.4).

C3-C1 remains NO-GO until this gate passes. PR #93 remains BLOCKED.
The 21 pins, 5 timers, and the current node pool are unchanged by this
plan.

## 6. Open items / limitations

- The server-side token-table change (accept a SET of DEV tokens during
  the parallel window) is a production server change that needs its own
  review and isolated test before deployment. It is NOT part of this
  design's isolated verification (the s1 mock server simulates it).
- The one-time bootstrap (§2.3) requires the owner to handle the raw new
  token once. The exact UX (which Surge screen / which script) must be
  confirmed with the owner before C3-C1; the design does not assume a
  particular Surge UI flow.
- The diagnostic token (C2-B) is already revoked; no action needed.
- The ADMIN token rotation is out of scope for this gate (it is contained
  and not in any distributed file). If the operator wants to rotate it as
  hygiene, that is a separate, lower-urgency task.
