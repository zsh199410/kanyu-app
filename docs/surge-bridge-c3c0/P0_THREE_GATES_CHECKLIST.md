# Issue #73 — P0 three-gate release contract (2026-11-20)

**Current decision: NO-GO.** This is an auditable checklist, not an
authorization to install scripts, run a device workflow, mutate private
VPS settings, promote or revoke a credential, change a timer or delete
any proxy node.

## Gate A — REAL private server HTTPS integration

| Required proof | Status |
|---|---|
| Real HTTPS socket and certificate verification, only synthetic creds | **PASS in isolated CI**: PR #110 |
| Bearer authentication uses a dedicated out-of-band high-entropy pairing secret, never exposed old DEV token | **PASS in isolated CI**, production pairing NOT provisioned |
| Strict JSON, replay 409, unknown old/standby 403, 401 unauthorized, no raw secret in logs | **PASS in isolated CI** |
| Ed25519 signed proof only after durable nonce registration + token/nonce atomic SQLite commit | **PASS in isolated CI** |
| Real server's audited user/device session authentication and pairing delivery | **UNVERIFIED / BLOCKED** |
| Actual private server release branch, HTTPS public certificate, routing, firewall/ACL, DNS, monitoring and tested rollback | **UNVERIFIED / BLOCKED** |
| Real production key custody, independent pinned verifier trust root, private durable token registry | **UNVERIFIED / BLOCKED** |
| Stale SQLite snapshot restore cannot reactivate revoked token or consumed nonce | **UNVERIFIED / BLOCKED** |

PR #110's `credential_proof_https.py` binds **only 127.0.0.1**
using an actual Python TLS socket and an independently created test
certificate. It is **not** a publicly accessible server and MUST NOT
be assumed to be deployed to the owner's real domain or VPS. A future
private integration must be re-reviewed, protected against high-rate
credential-proof requests, tied to an authenticated device identity,
and use an immutable audited token registry. The bearer is a
*separate pairing credential*, not the token candidate or exposed old
bridge token. It cannot be pasted into public source or GitHub comments.

## Gate B — actual iPhone / Surge TF WebCrypto evidence

**2026-11-20 device update:** Owner's script editor with Generic + WebView
reported `isSecureContext=false`, `crypto=yes`, `subtle=no`,
`digest=missing`, `trigger=editor`. The previously installed probe
reported `no_webcrypto`. This is a specific insecure-context failure,
**not** an Ed25519 hardware incompatibility conclusion or production GO.
Updated probe must report `insecure_context`; this change is CI-only
until a separately pinned module build is explicitly installed.

**Only run a separate non-secret manual probe after an approved device
change window.** The script in PR #107 contains no token, API key,
hostname or network call; it tests the local iOS WebView runtime.

Proposed test scope, without installing/replacing production Bridge:
1. Confirm phone's Surge TF build, iOS build and exact probe **source SHA**.
2. Run PR #107's `surge_webview_crypto_probe.template.js` as a
   generic script with **`engine=webview`** via the script editor's
   Evaluate control or an explicit Shortcuts intent.
3. Record only its fixed non-secret enum:
   `crypto_ready`, `insecure_context`, `no_webcrypto`, `no_text_encoder`,
   `base64_unavailable`, `base64_failed`,
   `sha256_failed`, `ed25519_unavailable`,
   `signature_failed`, `random_unavailable`, `probe_error`.
4. Explicitly check the script invoked `$done` and did not access
   the network or change active/candidate credentials, policy groups,
   old pending command, protected pins or five timers.
5. Confirm phone/local run produced **no secret-bearing history/log**.
   Do not paste raw device logs, real token, Shortcuts input history,
   IPs, API endpoints or private source code to public GitHub.

`crypto_ready` on the actual target phone only proves **WebCrypto
capability**, NOT candidate promotion, runtime one-time nonce
durability, privacy of real token input or real Bridge rollout. Earlier
"user-reported phone acceptance" is not an Ed25519 probe result unless
the probe's SHA and status are expressly correlated.

Official Surge source:
- https://manual.nssurge.com/scripting/overview.html
- https://manual.nssurge.com/scripting/generic.html

## Gate C — credentials, revocation and reversible release

**This is a separate owner-approved operational sequence, not an
instruction to perform it now.**

0. Preserve the current read-only evidence first: code SHA, server
   release SHA, hash of backup, previous actual phone evidence, and
   snapshots of mailbox/ledger/last_id, current 21 protected pinned
   nodes and five timers. Do not copy raw tokens into evidence.
1. Stage NEW and BACKUP independently under a private credential
   injection path. Never paste into public script or open GitHub file.
   Verify that old exposed value is no longer embedded in downloadable
   source.
2. Demonstrate a real signed `/credential-proof` with a pinned
   public key, fresh server-registered nonce, verified candidate
   fingerprint and denied replay. Verify registration, issuance and
   consumption persist across safe service restart.
3. Only after a separate approved gate, promote candidate to active.
   A `$persistentStore.write` returning false can have actually
   committed: reconcile readback, do not retry or roll back to exposed
   old credentials automatically.
4. Observe **two actual consecutive ten-minute cron runs** on the
   same installed SHA. Verify signed proof, 200 poll from new token,
   strict idempotence, no leak or unauthorized result. The OLD pending
   command `1795063030` remains **OUTCOME_UNKNOWN forever** and is
   not overwritten, resent, cleared, acknowledged or replayed.
5. Only after the new and fresh standby paths have been tested,
   explicitly approve old exposed token revocation. Test **403**
   on old token and **200** on new token; verify failed old requests
   do not trigger retries or fallback.
6. Run a real controlled rollback rehearsal against a test deployment
   after revocation: use a **different independently issued backup
   token**, never the exposed old token. Verify restoration of code
   while retaining current nonce/credential audit state, and no change
   in 21 pins, five timers, protected mailbox or routing.
7. Signed release receipt must include test timestamps, exact
   SHA, redacted pass/fail matrix, rollback location (not secret), one
   responsible reviewer and owner approval. Private credentials,
   session token, device IDs, internal domains and raw logs must not
   appear in public Issue #73.

**Release automatically remains NO-GO if any item above is unknown,
unverified, failed or not approved.** The single-host SQLite sample
does not prevent restore of an earlier DB snapshot; an independent
rollback-resistant epoch/control plane remains a production prerequisite.

## Fixed protections

- `C3-C1=NO-GO`, `PR93_CUTOVER=BLOCKED`
- `BOOTSTRAP_SECURITY_GATE=BLOCKED`, `AUTO_DELETE=OFF`
- 21 pinned nodes are excluded from auto-removal; existing 5 timers
  remain untouched
- No unexpected DIRECT fallback
- Old one-slot pending command `OUTCOME_UNKNOWN`, no replay/rewrite
- No real token, key, private endpoint or secret log in public PR/Issue

## Dispatch responsibilities

GPT: code review, P0 HTTPS test harness, public CI, regression and
production safety gates.

Muse: review/absorb only **after exact-head comparison**, investigate
private server integration availability and return redacted
device-evidence coverage / production plan. No assumption of direct
phone or VPS access from a GitHub comment.

Device owner: only perform actual phone capability test or
credential rotation after the final reviewed plan and explicit
device-specific approval; no need to share any secret with GitHub.
