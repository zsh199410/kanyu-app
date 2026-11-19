# Issue #73 · Bridge durable acknowledgement recovery

**STATUS 2026-11-19: DRAFT CODE + MOCK TESTS ONLY. NOT DEPLOYED.** This
fix is independent of Surge node-pool PR #93. It does **not** authorize
production unit cutover, phone configuration changes, replay of old
commands, alteration of 21 pinned nodes, or automatic node deletion.

## Evidence and the precise defect

Trusted VPS report [Issue #73 #7003401053](https://github.com/zsh199410/kanyu-app/issues/73#issuecomment-7003401053):
* Phone's cron fires /poll every 10 minutes; the same id `1795063030`
  has been returned 23 times since 12:37 but there have been no
  matching `/result` requests. The server has exactly **one** pending
  command and one result slot, no historical queue. That old command
  is a GET /v1/outbound, but its outcome remains **UNKNOWN**.
* Private phone bridge.js writes persistent `last_id` **before** POST
  /result, and swallows outer exceptions. This can permanently skip a
  command if the result POST is lost or its execution is interrupted.
* `last_id >= id` proves checkpoint persistence, **not successful
  command execution**. `last_id < id` does not alone prove an action
  threw, because the top-level parse or storage path may have failed.
* `/poll` 200 proves phone cron/poll transport, NOT action execution.
  No new bridge.js was downloaded on Nov 19; the Nov 18 4716-byte
  PR #85 script remains cached.

## Surgical two-part protocol patch (no reset, no replay)

### Server integration (do not deploy until original private source audited)

Use `mailbox_ack.py` pure transitions inside the trusted VPS
`server.py`'s already authenticated, serialized, atomic JSON state
handler. No new external Python dependency.

1. Replace the **old** `POST /result` branch with
   `accept_result(state, json_body, now=time.time())`.
   **Persist returned `new_state` via the original atomic state save
   BEFORE returning 200** if `should_save=True`. An id mismatch MUST
   be HTTP 409 and MUST NOT overwrite the single result slot or clear
   pending cmd. Same-id+same-output retry gets an idempotent 200
   `{accepted:true,acked_id:<id>}` without another write.
2. Add an authenticated device-token `POST /diagnostic` branch using
   `accept_diagnostic(...)`; it updates only one bounded diagnostic
   record, **never** `cmd` or `result`. This is how the phone can
   disclose last_id without the owner manually reading local storage.
   It must not send proxy credentials, full URL, token or action output.
3. Add authenticated read-only `GET /receipt?id=<id>` based on
   `receipt_status(state,id,posted_result)`. Because full result may
   be sensitive, **do not put result/outputs in a query string**.
   Instead, in the private implementation use a body-hash
   (SHA-256 over stable canonical JSON) as a short opaque confirmation
   key or a bodyless device-token-authenticated endpoint returning only
   whether that exact ID is the last accepted result. If using
   bodyless match, only return confirmed for the last accepted ID,
   with the obvious limitation that result payload identity is not
   verified. The pure helper compares the full object internally;
   wire adapter must be audited before deployment.
4. Harden admin `POST /issue` to use `issue_if_empty`. Legacy
   last-write-wins **overwrote earlier unknown commands**. Never
   overwrite the current `1795063030` until its outcome is
   reconciled and its evidence archived via an explicitly audited
   administrative procedure.
5. Existing device/admin token checks, server lock, file atomic save,
   nginx host and path routing **must remain unchanged**. Avoid
   logging the full /result payload.

### Phone integration (do not load until server routes proven)

`bridge_delivery_state.js` is a transport-independent **reference
module** with Node `module.exports`. **It is not a standalone
Surge script**: Muse must integrate its `runOnce(io)` function into
the existing private 4716-byte `bridge.js`, supplying real adapters
around the existing token-backed `$httpClient`, persistent storage,
`api`, `mcp` and per-action logic. Preserve PR #85's
non-idempotent POST no-retry behavior.

Implement adapter functions:
* `getLegacyLastId()`: read existing persistent key **only**.
  Do not reset, decrement or replace it.
* `getLedger()/putLedger()`: a **new distinct persistent key** for
  version-1 delivery ledger. The put operation must return `true`
  only after storage reports synchronous success. Never silently
  return true on storage exception or failure.
* `poll()`: same authenticated existing /poll HTTP GET.
* `execute(cmd)`: existing per-action handlers. Throw/error does NOT
  trigger an automatic execution retry; report OUTCOME_UNKNOWN.
* `sendResult(payload)`: POST to updated /result. Verify
  `HTTP 200 AND accepted:true AND acked_id === cmd.id`.
  Legacy `{ok:true}` alone is NOT an ACK.
* `sendDiagnostic(payload)`: send code, id, legacy_last_id and phase
  to new /diagnostic endpoint; do NOT send it to /result.
* `lookupReceipt(id,result)`: optional safe authenticated read
  to reconcile server-accepted /result if transport ACK was lost.
  It MUST return `confirmed:true` only with positive server proof.

State rules:
* **First run with pending cmd:** fence it as `LEGACY_PENDING_FENCED`;
  record its ID and legacy_last_id in the new diagnostics channel,
  **NO action or /result**, no mailbox or old last_id mutation.
  The existing cmd `1795063030` stays OUTCOME_UNKNOWN.
* **First run with empty mailbox:** bootstrap fence to old last_id,
  then future new IDs may be handled normally.
* **New ID:** write `in_progress` BEFORE executing. Script crash
  leaves an unambiguous *unknown outcome* record, not a permission
  to execute it a second time.
* **Finished command:** persist `result_ready` with bounded
  original outputs BEFORE sending /result. Network failure only
  resends the saved result; it NEVER re-executes the command.
  Server duplicate is idempotently ACKed, not overwritten.
* **ACK lost after server cleared cmd:** use read-only receipt lookup,
  or keep the result protected and report UNKNOWN. Never infer
  completion from an empty mailbox.
* **Concurrent script instances:** runtime must be verified to
  serialize execution or a server-side atomic claim is required.
  Existing 10-minute cron/120-second timeout reduces overlap but is
  **not proof of mutual exclusion**. Do not deploy action-executing
  mode unless tested.

## Deployment and recovery gates

1. Muse first audits exact original private `bridge.js` and
   `server.py` handlers; keep the existing private
   credentials and paths locally. Do not copy real files to public
   GitHub. Run Node and Python isolated tests, plus **old-protocol
   compatibility and race/crash/clock tests** in isolated simulation.
2. Back up server.py, state.json and bridge.js **byte for byte** in
   a root-only off-publish location, record file SHA, permissions,
   current pending ID, result ID, cron schedule, recent download size
   and /poll+/result counts. Backup server+client separately.
3. Deploy **server support first**, in a bounded rollout with
   restart/reload only after validating code syntax, token
   authentication (unknown token must get 403), result ID mismatch
   409, duplicate 200 with matched ack, /diagnostic non-clearing,
   and /receipt read-only behavior. Roll back server if it breaks
   existing polling/serving, restore backup state on transaction
   error. Never discard `cmd=1795063030`.
4. Deploy phone *diagnostic-only* bridge canary next. The old
   pending ID remains fenced. Require a verified current /s/
   download **of the new script SHA** and a new diagnostic report
   containing actual `legacy_last_id`, phase and pending ID.
   **Do not assume a cron run implies the new script was fetched**.
   Server state must still have same cmd and result. No action
   invoked, no /result POST made by this canary.
5. Distinguish last_id vs pending ID and inspect script exception
   path. Then **separately reconcile** the 12:37 unknown command
   without replay. Only when state, action result and rollback
   evidence permit, allow a new unique **GET-only** diagnostic
   command with ID greater than migration fence; no POST/PUT/DELETE,
   no node-test/selection/routing change, no clearing the queue
   as a side effect of diagnostics.
6. Only after the bridge returns *fresh* `GET /v1/outbound`,
   `GET /v1/rules`, `GET /v1/profiles/current?sensitive=0`,
   and selected policy state with real response time and ID
   can the owner's D4 anti-DIRECT gate be re-evaluated. Normal
   selection `美国自动` does not prove an absolute fail-closed
   invariant if future manual selection or nested policy changes.

**Do not update the 21 pins, node pools, STOP, timer states or live
Surge rule/profile as part of this bridge repair.** This remains a
Draft fix; PR #93 cutover is BLOCKED until evidence is obtained.

## Tests

```sh
node --check docs/surge-bridge-recovery/bridge_delivery_state.js
node docs/surge-bridge-recovery/test_bridge_delivery_state.js
python3 -m unittest discover -s docs/surge-bridge-recovery -p 'test_mailbox_ack.py' -v
```

The tests use synthetic TEST-NET payloads/IDs. They do not connect
to the owner's phone, VPS, mailbox, or proxy subscription.
