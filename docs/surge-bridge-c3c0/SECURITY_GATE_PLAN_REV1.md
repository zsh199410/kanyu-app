# SECURITY_GATE_PLAN Rev 1 — what changed vs Rev 0

Date: 2026-11-19. Trigger: GPT review 7010615307 (5 findings on the S1
plan). All changes are DESIGN + isolated verification only. No live file
touched, no live credential revoked or rotated, no GitHub post, no phone
contact.

Rev 0 is the version submitted in Draft PR #97 (branch
c3c0-sanitized-v2-review, head a4df7b4). Rev 1 supersedes it and is to be
committed as a follow-up to PR #97. GPT's independent S3 oracle (Draft
PR #98, 28/28) is a separate implementation and is NOT conflated with
Muse's S3 10/10.

## Finding 1 — leaked DEV token must not be a rollback credential

Changed:
- §3.2 R1: a NEW BACKUP token is now generated and held in reserve
  before the cutover starts (precondition P4). It is the rollback
  credential.
- §3.5 rollback: the Rev 0 rollback ("re-add the OLD token, restore the
  OLD script") is REMOVED. Rollback is now path A (activate the
  pre-issued new backup token) or path B (fail-closed, preserve state,
  restore only with separate approval). Re-enabling the leaked old token
  and re-serving the old embedded-token script are EXPLICITLY FORBIDDEN.
- §3.4: the 48-hour parallel window is now stated as an UPPER BOUND,
  not a target; the old token is treated as COMPROMISED from the moment
  the window opens.
- §3.6 A4: now also covers any attempt to re-enable the old token as a
  rollback.
- §5 gate: "rollback re-enabling the leaked old token is explicitly
  forbidden" is now a stated gate condition.

Test: S1-T6 rewritten (rollback via backup token; old token stays 403);
S1-T9 added (no backup token → fail-closed, leaked token not re-enabled).

## Finding 2 — $persistentStore is not a proven secure keystore

Changed:
- New §2.3a: what the store does and does not guarantee. The Surge
  manual calls it a "simple persistent key-value API"
  (https://manual.nssurge.com/scripting/api.html); it is not documented
  as an encrypted/secure keystore. Verification requirements V1–V4 added:
  write path, read scope, leakage surfaces (config export, logs,
  backups — UNVERIFIED where the manual is silent), and read-failure
  behaviour (0 network calls).
- §2.4: read throwing or failing a sanity check now also fails closed
  (new phase `credential_read_failed`).
- §6: the store's security properties are listed as an open item —
  a DESIGN ASSUMPTION until verified, not a verified control.

Test: S1-T10 added (read throws → 0 network calls, `credential_read_failed`,
$done once, server sees nothing).

## Finding 3 — rotation acceptance must not inject/overwrite old command 1795063030

Changed:
- §3.2 R5: the Rev 0 acceptance criterion "(b) every /result is posted
  with the NEW token and is ACKed" is REMOVED. Acceptance is now (a)
  /poll with the new token 200 for 3 rounds, (b) /credential-proof with
  the new token 200 for 3 rounds, (c) zero old-token requests.
- New §3.2a: the /credential-proof endpoint (action-free; proves a token
  is accepted without reading/writing the mailbox, posting a result, or
  issuing a command). It does not exist yet and needs its own design +
  review; until then, acceptance is /poll-only plus deferral of real
  /result ACK verification until the old single-slot audit closes.
- §3.2 R4: /poll is noted as read-only (safe); the phone must NOT post
  any /result during the rotation acceptance window.
- §3.3: C2 changed to /credential-proof; new C6 (the pending old command
  1795063030 is unchanged throughout the rotation).
- §3.1: new preconditions P4 (backup token) and P5 (credential-proof
  endpoint designed/approved, or acceptance deferred).

Test: S1-T4 rewritten (acceptance via poll + credential-proof; legacy
command fenced, 0 results for it, pending unchanged); S1-T11 added
(3 acceptance rounds leave the mailbox untouched).

## Finding 4 — local HTTP API key risk must not be downplayed

Changed:
- §1 row 3: grade changed from "EXPOSED — lower remote value" to
  "EXPOSED — HIGH on-device privilege". The key controls the phone's
  local Surge instance (Surge HTTP API manual,
  https://manual.nssurge.com/tools/http-api.html); a same-device script
  holding it can read/change Surge state. "Localhost-only" limits remote
  reach, not on-device privilege.
- §2.5 and §3.2 R8: the local key is now rotated with the SAME discipline
  and urgency as the DEV token (same window, same revocation verification,
  same audit). Rev 0 "lower urgency" is removed.

Test: no new test (S1-T8 already covers the absent-key fallback); the
change is a grading and scheduling correction, verified by the plan text.

## Finding 5 — idempotency_key hit proves allocation only, not execution/ACK

Changed:
- New §3.7: an idempotency-key hit proves the request was ALLOCATED and
  nothing about execution or /result ACK. The ONLY proof of completion
  is the strict ACK (200 + accepted:true + acked_id === original raw id).
  Raw IDs and strict ACK are preserved everywhere.
- New gate G5 (§5): allocator initialization (first-boot high-water),
  history-compression bound (bounded `keys` map must not drop a key that
  could still be retried), and the cross-restart lock sequence (state
  loaded + lock held before any allocation) each need an INDEPENDENT gate
  (isolated verification, recorded separately) before any S3 production
  step. G5 is a dependency for S3 production, not for the S1 gate itself.

Test: no change to the s1 suite (finding 5 concerns the S3 allocator
design, not the S1 distribution tests); it is recorded as gate G5.

## Files (Rev 1)

| File | SHA-256 |
|---|---|
| SECURITY_GATE_PLAN.md (Rev 1) | c5601e078d83fe3ad5c3a637f680942848d2da6b125fbfa3b292e5f64324813c (Rev 0 was 6a2e44d8…dec43e) |
| s1/test_s1.js (Rev 1) | f98506b5c98447f07bb214171a051cc9f86a6445dbb591209a5effc72e7334d7 |
| s1/s1_out.json (Rev 1) | afe89e5724feb4082e6ab51088b1331c795730bc601ebe0fa3a984df8d0ea767 (11 PASS / 0 FAIL / 0 LIMITATION) |
| s1/README.md (Rev 1) | 28680742da09d09f7ea8e7eea748216b74849cee1adc523f02338457250311ca |

(This file's own SHA is not listed inside itself — it changes with every
edit. The parent agent verifies it from disk when committing to PR #97.)

## Status after Rev 1

- CREDENTIAL_DISTRIBUTION_GATE=BLOCKED (unchanged). C3-C1=NO-GO.
  PR #93 BLOCKED. Old command 1795063030 OUTCOME_UNKNOWN, fenced.
- All 5 GPT findings are addressed in the plan and, where testable, in
  the s1 suite (11/11 PASS). No finding was dropped.
- Open (unverified, not assumed): $persistentStore security properties
  (§2.3a V1–V4); the /credential-proof endpoint design; the server-side
  token-table change; G5 allocator gates.
