# C3-C0-S3 — Server Unique ID Allocator (DRAFT DESIGN + isolated tests)

Date: 2026-11-19. Project: PR #96 / Issue #73, C3-C0-S3.
Scope: DRAFT DESIGN + isolated verification only. No production file
touched, no production state modified, no GitHub post, no phone contact.
Status: DESIGN ONLY — production implementation needs a separate review
(see §6).

All IDs below are synthetic examples. No credential, URL, IP, or device
identifier appears in this document.

## 1. The gap (verified read-only against the live server code)

The live server (`mailbox_ack.py`, `server_http_commit.py`) does NOT
generate command IDs. `POST /issue` accepts a caller-supplied `command.id`:

- `_valid_id(v)`: `type(v) is int and 0 < v <= 2**53 - 1`. Any safe integer
  is accepted; there is no check that it is a timestamp, no check that it
  is unique, and no allocation.
- `issue_if_empty` rejects only if (a) a pending command already exists
  (409 `pending_command_exists`), or (b) the new id is not strictly
  greater than the last stored result id (409 `command_id_not_increasing`).
- The increasing check at (b) is a **raw numeric comparison**:
  `command["id"] <= old_result["data"]["id"]`. It is unit-blind — the
  same bug class as the original phone dedup that caused this incident:
  - A millisecond last-result id (13 digits) blocks any newer
    seconds id (10 digits), because the seconds value is numerically
    smaller even though it is temporally newer.
  - Conversely, a seconds last-result id does NOT block a millisecond id
    that is temporally older, because the millisecond value is numerically
    larger.
- Two callers issuing seconds-precision IDs in the same second produce
  the SAME id. The single-slot mailbox prevents two commands being pending
  simultaneously, but it does not prevent the same id being reused for two
  different commands at different times (e.g. after the first command's
  result is stored and the slot clears, a second caller issuing the same
  seconds id would be rejected by the increasing check only if a result
  with that id exists — if the first command was fenced/skipped and never
  produced a result, the duplicate id can be accepted later, creating
  receipt ambiguity: two different commands, one id).
- There is no persisted allocator state. If the server restarts, nothing
  prevents re-allocating an id that was already used (the only guard is
  the last-result comparison, which depends on a result existing).

Consequence: the server cannot currently guarantee that command IDs are
unique or strictly increasing. The phone script must not depend on
server-side uniqueness (it already fails closed on an exactly equal id),
but the server should be fixed so the guarantee holds by construction.

## 2. Draft design: server-side unique ID allocator

### 2.1 Where it lives

- Inside the existing server, under the existing global request lock and
  the existing atomic persist (`persist(next_state)`). Allocation and
  mailbox write happen in ONE atomic commit: the allocator reads the
  current state, allocates the id, stores the command, and persists — all
  while holding the lock. No separate lock, no new process, no new store.
- Allocator state is persisted in the same `state.json`, under a new key
  `allocator`, so it is atomically committed together with the mailbox:
  `allocator: { last_allocated_ms: <int>, keys: { <idempotency-key>: <tombstone> } }`.
  A tombstone is `{ id, issued_at_ms, status: "pending" | "resolved",
  action_hash }` (see §2.3). The map is bounded by count and fails
  closed when full — see §2.3.
- If `state.json` is missing or corrupt, or the allocator state is absent
  or invalid, allocation FAILS CLOSED (503, do not allocate, do not store
  a command). Never guess a starting id.

### 2.2 Allocation algorithm (strictly increasing unique millisecond integers)

```
allocate(now_ms, last_allocated):
    # now_ms = int(time.time() * 1000) — wall-clock milliseconds.
    # last_allocated = persisted highest id ever allocated (0 if none).
    if not (0 < now_ms <= 2**53 - 1): fail closed (503)
    candidate = max(now_ms, last_allocated + 1)
    if candidate > 2**53 - 1: fail closed (503)
    new_last_allocated = candidate
    return candidate
```

Why this works:

- **Strictly increasing:** `candidate >= last_allocated + 1`, always.
  Every allocated id is greater than every previously allocated id.
- **Unique:** strict increase implies uniqueness (no two allocations can
  return the same value).
- **Same-millisecond safe:** if 50 allocations happen in the same
  millisecond, the first gets `now_ms`, the second gets `now_ms + 1`,
  the third `now_ms + 2`, and so on. The ids are still millisecond-range
  integers (13 digits) and strictly increasing. There is no separate
  per-ms sequence counter to persist — the `+1` IS the sequence.
- **Clock skew safe:** if the wall clock goes backwards,
  `max(now_ms, last_allocated + 1)` still returns `last_allocated + 1`,
  so monotonicity is preserved. If the clock jumps forward, the new id
  is the new wall-clock ms (which is greater than `last_allocated`).
- **Restart safe:** `last_allocated` is persisted atomically with the
  mailbox. After a restart the allocator reloads it and continues above
  it. It can never re-allocate an id that was already handed out.
- **Millisecond integers:** the returned id is always a 13-digit ms-range
  integer (while wall-clock ms stays below 2^53, i.e. for ~285,000 years).
  This matches the phone's `orderMillis()` canonical ordering: a server
  allocated id is already in ms, so no conversion is needed on the phone.
- **Fail-closed:** if the wall clock is invalid, if the candidate would
  exceed the safe-integer range, or if the allocator state is missing /
  corrupt, allocation returns 503 and no command is stored.

### 2.3 Idempotency (retried /issue must not allocate twice)

- The caller supplies an `Idempotency-Key` header (or an
  `idempotency_key` field in the JSON body) with every /issue request.
  The key must be a client-generated unique string (e.g. a UUID).
  A retry of the same request MUST reuse the same key; a new request
  MUST use a fresh key. The caller also sends `retry: true` on a retry
  (and `retry: false` or omits it on a first attempt), so the server can
  tell a retry from a genuinely new request.
- The server persists the mapping `keys[idempotency_key] -> tombstone`
  (and the command) in the allocator state, atomically with the command.
  A tombstone is `{ id, issued_at_ms, status: "pending" | "resolved",
  action_hash }` — it records the request identity, not just the id, so
  a replay can be recognised even after the command itself resolves.
- **Order matters: the idempotency-key check comes BEFORE the
  pending-command check.** A retry with a known key is for the command
  that is already pending, so it must return the same id — it must NOT
  be rejected as `pending_command_exists`. (This ordering was caught by
  the isolated test S3-T4: checking "pending" first wrongly 409s a
  legitimate retry.)
- On a retry with the same key:
  - If the key is known AND the mapped command is still pending, return
    200 with the SAME command (same id) — do not allocate a new id, do
    not overwrite the mailbox.
  - If the key is known AND the command has already been resolved (a
    result exists with that id), return 200 with the stored result
    reference (or 409 `already_resolved` — the exact code is a production
    detail; the invariant is: no second allocation, no second execution).
  - If the key is unknown, allocate normally.
- **Durable tombstones, no silent eviction (GPT review 7010797396 —
  addressed).** The `keys` map is NOT auto-evicted. Tombstones are
  retained for the supported retry horizon
  `RETRY_HORIZON_MS = 7 days` (604800000 ms), which must be at least as
  long as the longest supported client retry window (the bridge's
  operational retry window is minutes to hours; 7 days exceeds it by
  orders of magnitude). The map is bounded by count as well
  (`MAX_TOMBSTONES = 10000`, ~100 bytes each — a few MB at most).
  When the map is FULL (count limit reached), allocation FAILS CLOSED
  with 503 `history_full` — it never silently evicts a tombstone and
  reissues the action. A full history is an operator event (archive /
  extend the store), not a reason to replay a non-idempotent action.
  Tombstones older than the horizon are NOT deleted by the allocator;
  expiry is an operator/archival decision, recorded, and never applied
  while a retry could still be in flight.
- **Unknown / expired retry identities are explicitly rejected (GPT
  review 7010797396 — addressed).** If a request is marked
  `retry: true` but its key is NOT in the tombstone store (unknown, or
  the tombstone was archived after the horizon), return 409
  `retry_identity_unknown` — do NOT allocate a fresh id and do NOT
  execute the action as if it were new. The server cannot prove the
  action was not already executed, so it must not execute it again.
  A first attempt (`retry: false` / absent) with an unknown key is a
  new request and is allocated normally (subject to the history-full
  503 above). This is why the client retry window must be shorter than
  the horizon and retries must reuse the same key: the guarantee holds
  only inside the horizon, and the server enforces the boundary by
  rejecting out-of-horizon retries instead of silently treating them
  as new requests.

### 2.4 Ordering check fix (required production change)

Change `issue_if_empty`'s increasing check from the raw comparison to
millisecond-canonical ordering:

```
# BEFORE (unit-blind, buggy):
if command["id"] <= old_result["data"]["id"]: -> 409

# AFTER (canonical ms ordering):
if orderMillis(command["id"]) <= orderMillis(old_result["data"]["id"]): -> 409
```

where `orderMillis(v)` is the same function as the phone's: ms ids stay,
seconds ids convert by x1000, non-safe-integers return null (fail closed
with 400). With the allocator in place, all NEW ids are ms and strictly
increasing, so the check will pass for allocator-issued ids; the
canonical comparison is still required so that OLD commands (which may
carry seconds ids) are compared correctly against ms last-result ids.

### 2.5 What does NOT change

- **Old commands keep their original raw IDs** for receipts and ACKs.
  The allocator never rewrites history. `accept_result` still matches on
  exact raw id equality (`pending.id == result.id`), and `receipt_status`
  still confirms by exact raw id. No migration of existing ids.
- **Wire format unchanged.** /issue still accepts a JSON command with an
  `id` field; the only change is that the server now ALLOCATES the id
  (the caller may omit it, or the server overwrites a caller-supplied id
  with the allocated one — see §2.6). /poll, /result, /diagnostic,
  /receipt are untouched.
- **Single-slot mailbox unchanged.** `pending_command_exists` (409) still
  applies: the allocator refuses to allocate when a command is already
  pending. Allocation happens only when the mailbox is empty.
- **The phone script does not change for this.** The phone already uses
  `orderMillis()` and fails closed on equal ids. The allocator is a
  server-side guarantee; the phone's defence in depth stays as is.

### 2.6 Caller-supplied id: ignore or reject?

Two options; the design recommends (a):

- (a) **Server allocates, caller id ignored.** The caller omits `id` (or
  sends any value) and the server returns the allocated id in the 200
  response (`{"ok": true, "issued": true, "id": <allocated>}`). The
  caller uses the returned id for tracking. This is simplest and removes
  the whole class of caller-side unit mistakes. Recommended.
- (b) **Server allocates, caller id rejected if present.** The caller
  must omit `id`; if it sends one, return 400. Stricter, but breaks
  existing callers that send an id. Not recommended as a first step.

Under (a), a caller that still sends a seconds id gets it replaced by the
allocated ms id; the response tells it the real id. No caller can inject
a colliding or non-monotonic id.

### 2.7 Failure modes (all fail closed)

| Situation | Behaviour |
|---|---|
| Mailbox already has a pending command | 409 `pending_command_exists`. No allocation, no state change. |
| Allocator state missing/corrupt | 503. No allocation, no command stored. |
| Wall clock invalid (<=0 or > 2^53-1 ms) | 503. No allocation. |
| Candidate would exceed 2^53-1 | 503. No allocation. (Not reachable in practice for ms timestamps.) |
| Persist fails after allocation | 503 `durable_commit_failed`, `commit_state: "unknown"`. A persist exception does NOT prove the command was not stored: filesystem sync/rename may succeed *before* persist reports an exception (PR#96 `server_http_commit.py` documents this). The allocator therefore does NOT roll back in memory and does NOT assume the command is absent. The transaction is marked unknown and must be **reconciled** before any further allocation: re-read the durable state; if it contains the command (same idempotency key / same id), return that id — the original allocation succeeded; if it is readable and contains no such command, the original transaction is provably absent and a new allocation may proceed; if it is unreadable or corrupt, fail closed with 503 and stay unknown. **A retry with a DIFFERENT idempotency key must not create another action until this reconciliation proves the previous transaction's outcome with durable server-side proof** (GPT review 7010797396 — addressed). |
| Retry with a known idempotency key | Same id returned, no second allocation, no second command. |
| Retry marked `retry: true` with an unknown/expired key | 409 `retry_identity_unknown`. No allocation, no execution (GPT review 7010797396 — addressed). |
| Tombstone history full (count limit reached) | 503 `history_full`. No eviction, no reissue (GPT review 7010797396 — addressed). |
| Retry with an evicted/unknown key while a command is pending | 409 `pending_command_exists`. |
| Caller sends a seconds id (option a) | Ignored; server allocates an ms id and returns it. |

## 3. Isolated verification (s3/)

The simulation in `s3/` (Node.js, no real tokens/URLs, mock persistent
store + mock global lock) verifies the allocator. See `s3/README.md` and
`s3_out.json`. Summary:

| Check | What it proves |
|---|---|
| Strictly increasing across 1000 allocations | Every allocated id is greater than the previous one. |
| No duplicates, 50 allocations in the same millisecond | Mock clock frozen at one ms value; all 50 ids distinct and increasing. |
| No repeats across a simulated restart | Allocator state persisted, process "restarted" (new instance loads the persisted state), next id is above all previously allocated ids. |
| Retry with the same idempotency key returns the same id | No double allocation; the mailbox still holds exactly one command. |
| Caller-supplied seconds id normalized to ms for ordering, raw id preserved for receipt | A seconds id is converted by x1000 for the increasing check; the stored command and the receipt keep the caller's raw id. |
| New id always greater (ms ordering) than any existing last result id (both s and ms) | With a ms last-result id and with a seconds last-result id, the allocated id is greater in ms ordering. |
| Allocator refuses when a pending command exists (409) | No allocation, no state change, mailbox untouched. |
| Clock going backwards preserves monotonicity | Mock clock set backwards; the next allocated id is still above the previous one. |
| Overflow / invalid clock fails closed | Candidate beyond the safe-integer range (or an invalid wall clock) returns 503 and allocates nothing. |
| Retry with an evicted/expired key (marked `retry: true`) is explicitly rejected, never re-executed | A retry whose key is not in the tombstone store returns 409 `retry_identity_unknown`; zero dispatches, no new allocation, mailbox unchanged. |
| History full fails closed (503), never silently evicts and reissues | With the tombstone store at its count limit, a new first-attempt request returns 503 `history_full`; no allocation, no command stored. |
| Persist error leaves `commit_state: unknown`; a retry with a DIFFERENT key creates no second action until reconciled | After a persist exception, the allocator re-reads durable state: if the command is durably present, the retry returns the existing id (no second action); if durable state is unreadable, it fails closed 503 and stays unknown. |

## 4. Required production changes (not done here)

This is a draft. The following must be done (and reviewed separately)
before the allocator is deployed to production:

1. Implement `allocate()` in the server (inside the existing global lock
   + atomic persist), with the `allocator` key in `state.json`.
2. Change `issue_if_empty`'s increasing check to `orderMillis`
   (§2.4). Add the `orderMillis` helper to the server (same semantics as
   the phone's).
3. Add idempotency-key handling to /issue (§2.3 Rev 1), with durable
   tombstones for the 7-day retry horizon, explicit rejection of
   unknown/expired retry identities (409 `retry_identity_unknown`), and
   fail-closed 503 `history_full` when the tombstone store is full.
   No auto-eviction.
4. Change /issue so the server allocates the id (option (a) in §2.6) and
   returns it; update all callers to use the returned id (and to stop
   generating their own seconds/ms ids).
5. Isolated tests for the production implementation (port the s3 suite to
   the real server code), plus a restart test on a staging copy of
   `state.json`.
6. A migration note: existing pending command 1795063030 keeps its raw id
   and stays OUTCOME_UNKNOWN and fenced; the allocator never touches it.
   The first allocator-issued id must be greater (ms ordering) than
   every existing id (last result 1795055213880 ms, pending 1795063030 s
   → 1795063030000 ms), which holds automatically because wall-clock ms
   is already above both.

## 5. What this design deliberately does NOT do

- It does not change the phone script (the phone already handles mixed
  units via `orderMillis()` and fails closed on equal ids).
- It does not rewrite, migrate, or re-issue any existing command id.
- It does not add a new network endpoint or change the /poll, /result,
  /diagnostic, or /receipt wire format.
- It does not use the wall clock as the sole uniqueness source (the
  persisted high-water mark + `+1` is what guarantees uniqueness even
  when the clock is frozen or goes backwards).

## 6. Gate statement

**ID_ALLOCATOR_DESIGN = DRAFT Rev 1 (isolated tests pass, production not
implemented).** Rev 1 (2026-11-19) addresses GPT review 7010797396:
§2.3 auto-eviction replaced by durable tombstones + explicit rejection
of unknown/expired retries + fail-closed 503 when history is full;
§2.7 "persist fails = rolled back" replaced by `commit_state: unknown`
+ durable reconciliation. The design is ready for review. Production
implementation requires the separate review in §4 and must not be done
as an experiment on live state. The phone-side fix (v2) does not depend
on the allocator: it fails closed on equal ids and orders by ms
regardless of how the id was produced.
