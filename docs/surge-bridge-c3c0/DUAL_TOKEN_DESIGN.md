# C3-C0 — Server Dual-Token and Revocation Design (Round 4)

## Status

Design + isolated executable sample + isolated tests. **Not a production
change.** No server change, no token-table change, no revocation, and
no phone action is authorized by this document. Gates unchanged:
`C3-C1=NO-GO`, `PR93_CUTOVER=BLOCKED`, `BOOTSTRAP_SECURITY_GATE=BLOCKED`,
`AUTO_DELETE=OFF`.

This is launch blocker (3) from GPT receipt 7013674858. It is the
server side of blocker (2) (the promotion gate's `/credential-proof`
depends on the server knowing the new token) and of blocker (1) (the
new token must exist server-side before it can be staged). It does
not depend on blocker (4) (real-device release proof) or (5) (release
checklist / prod rollback), which are NOT built in this round.

## 1. The problem

The DEV token in the public script is EXPOSED (anonymous fetch of the
public script URL returns 200; the file contains the long-lived DEV
token in plaintext). The bridge must move to a new token, but the
phone cannot be switched atomically with the server: the bridge reads
the new token from `$persistentStore` only after the owner stages and
promotes it (blockers 1–2), and the phone polls every 10 minutes.
There is a window in which the server must accept BOTH tokens, and a
point at which the old token must stop working — without ever
stranding the bridge and without ever reviving the old token as a
fallback.

## 2. Token table (design)

The server holds a token table. Each row is:

```
{ id: "<server token id>", fingerprint: "<sha256-hex of the token>",
  status: "active" | "revoked", issued_at: <unix ms>,
  revoked_at: <unix ms | null>, revoked_reason: "<string | null>" }
```

Rules:

- The table is **append-only for audit**: revocation is a status
  change, never a delete. A revoked row stays in the table with its
  `revoked_at` and `revoked_reason`, so any later request with that
  token can be answered 403 with a reason instead of a bare 401.
- The table stores FINGERPRINTS, not token values. The server
  compares `sha256(request token)` against the stored fingerprint.
  A leaked table therefore does not hand out usable tokens.
- During the controlled window the table holds TWO active rows: the
  old exposed token and the new token. The window is bounded: the
  S1 Rev 1 plan sets a **48-hour upper bound** for parallel
  operation. The exact window length is an approval item (§6).
- After the window, the old row is revoked (see §4). Revocation is a
  SEPARATE approved step, not automatic at window start.

## 3. Bridge behavior during the window

- The bridge accepts EITHER token during the window: a `/poll`
  request authenticated with the old token returns 200, and one
  authenticated with the new token returns 200. The bridge itself
  holds only ONE active token at a time (the one promoted by the
  gate, blocker 2); the dual-token support lives on the SERVER, not
  on the phone. The phone does not need to know about the window.
- After revocation (or window expiry), a `/poll` request with the
  old token returns **403**. The bridge's v2.2 403 gate
  (`auth_forbidden`) fails closed: it calls `$done` once and returns
  WITHOUT dispatching, WITHOUT sending `/result`, WITHOUT falling
  back to any other credential, and WITHOUT touching the mailbox or
  the ledger. A 403 never triggers a retry with the old token.
- A request with NO token is rejected (401). A request with an
  UNKNOWN token is rejected (401). Neither is a 403: the distinction
  matters for diagnostics (401 = no such token, 403 = known token,
  revoked or expired).

## 4. Revocation

- Revocation targets the OLD token row only. It is a separate
  approved step, executed after the new token is proven working on
  the real device (the promotion gate's proof + two cron cycles,
  blocker 4). It must NOT be executed early by changing the server
  token table ahead of approval.
- **Expiry fails closed.** If the window ends without an explicit
  revocation, the server MUST reject the old token anyway (403,
  reason `window_expired`). An expired window never silently extends.
  The sample implements this: `authorize()` checks both the explicit
  revocation flag and the window end time.
- **Rollback never revives the old token.** If the new token fails
  after revocation (e.g. the bridge cannot authenticate with it),
  the rollback is to activate a NEW backup token (a third token,
  pre-issued and held unused) — never to re-enable the old exposed
  token. The sample implements `rollbackToBackup()`, which refuses
  any backup value equal to the old token value.
- Revocation does not touch the mailbox: the old single-slot command
  `1795063030` stays `OUTCOME_UNKNOWN` and is never replayed,
  overwritten, or cleared. The sample test asserts this by
  snapshotting a mock mailbox before and after every operation.

## 5. Sequence (approved steps, in order)

```
1. Server issues the NEW token (new row, status active).
   The old row stays active. Window opens (≤48h, approval item).
2. Owner stages the new token as a candidate on the device
   (blocker 1, PR #101 templates). Active token unchanged.
3. Server issues a /credential-proof for the new token's
   fingerprint (blocker 2, §3 of PROMOTION_GATE_DESIGN.md).
4. Owner promotes the candidate to active on the device
   (blocker 2). The bridge now polls with the new token.
5. Real-device proof: new SHA loads, old command stays fenced,
   two cron cycles observed (blocker 4) — NOT in this round.
6. APPROVED revocation of the old token row (this design).
   Old token → 403 from this point on.
7. Window closes. Any later request with the old token → 403
   (revoked, or window_expired if revocation was missed).
```

Steps 5–7 require separate approval and are NOT authorized here.
This document only defines the table, the window, the revocation
semantics, and the rollback rule, and proves them in isolation.

## 6. Open items (all need a real-server / approval gate)

1. Real server token-table implementation (the sample is a mock;
   the production table lives in the private server code).
2. Exact window length (48h is the S1 Rev 1 upper bound, not a
   chosen value) and who approves opening/closing it.
3. `/credential-proof` endpoint implementation and which side
   computes the fingerprint.
4. The backup token: pre-issue it before revocation, hold it unused,
   and prove it authenticates before it is ever needed.
5. Monitoring: alert on 403 spikes after revocation (a spike means
   some client is still on the old token) and on any 401/403 from
   the NEW token (which would mean the promotion broke).
6. The old token's fingerprint must be recorded for the audit trail
   WITHOUT ever writing the old token value into a new file.
7. Real-device proof (blocker 4) and the release checklist /
   prod rollback (blocker 5) — NOT in this round.

## 7. Relation to earlier designs

- S1 Rev 1 (`SECURITY_GATE_PLAN.md`): leaked DEV token never
  re-enabled as a rollback credential (new backup token or
  fail-closed); 48h parallel window is an upper bound; rotation
  acceptance via `/credential-proof`; `$persistentStore` is not a
  proven secure keystore.
- `BOOTSTRAP_DESIGN.md` Rev 2 / 2.1: candidate staging only.
- `PROMOTION_GATE_DESIGN.md` (blocker 2): the device side of this
  design; its proof depends on the server knowing the new token.
