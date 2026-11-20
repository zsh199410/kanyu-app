# s3/ — Server unique ID allocator isolated verification

Run: `node test_s3.js` (Node.js, no dependencies, no network).
Output: `s3_out.json` + PASS/FAIL lines on stdout.

What it simulates (all synthetic IDs — the base "now" is a fixed synthetic
ms value; no real tokens/URLs):

- The allocator from `ID_ALLOCATOR_DESIGN.md` §2.2 Rev 1:
  `candidate = max(now_ms, last_allocated + 1)`, persisted atomically
  with the mailbox under a mock global lock.
- A mock persistent store (JSON, with a corrupt-state mode and
  persist-failure fault injection: `failNextSave`,
  `persistActuallySucceeded`, `unreadable`).
- Durable idempotency-key tombstones for the 7-day retry horizon
  (`RETRY_HORIZON_MS`), bounded by count (`MAX_TOMBSTONES`, default
  10000) with fail-closed 503 `history_full` when full — no
  auto-eviction (Rev 1, §2.3).
- `commit_state: unknown` + durable reconciliation after a persist
  failure (Rev 1, §2.7): a retry with a different key creates no second
  action until the previous transaction is reconciled with durable
  server-side proof.
- The canonical `orderMillis()` increasing check (and the current raw
  comparison, for contrast).

Tests (14):

| ID | Check |
|---|---|
| S3-T1 | Strictly increasing across 1000 allocations. |
| S3-T2 | No duplicates, 50 allocations in the same millisecond (frozen clock). |
| S3-T3 | No repeats across a simulated restart (persist + reload). |
| S3-T4 | Retry with the same idempotency key returns the same id (no double allocation). |
| S3-T5 | Seconds id normalized to ms for ordering, raw preserved; raw comparison shown wrong in both directions. |
| S3-T6 | New id greater (ms ordering) than any last result id (both s and ms). |
| S3-T7 | Allocator refuses when a pending command exists (409, no state change). |
| S3-T8 | Clock going backwards preserves monotonicity. |
| S3-T9 | Overflow / invalid clock fails closed (503, nothing allocated). |
| S3-T10 | Corrupt allocator state fails closed (no allocation). |
| S3-T11 | (Rev 1) Evicted/expired-key retry explicitly rejected (409 `retry_identity_unknown`), never re-executed — never-issued key and archived tombstone. |
| S3-T12 | (Rev 1) History full fails closed (503 `history_full`), never silently evicts and reissues. |
| S3-T13 | (Rev 1) Persist error leaves `commit_state: unknown`; a retry with a DIFFERENT key creates no second action (reconciliation finds the durably stored command and returns its id). |
| S3-T14 | (Rev 1) Persist error + unreadable durable state fails closed (503), stays unknown. |

Two real bugs were caught and fixed during this round (recorded for
honesty): (1) the idempotency-key check must come BEFORE the
pending-command check, otherwise a legitimate retry is wrongly 409d —
the design doc §2.3 was updated to state the order explicitly; (2) the
mock store's `load()` must catch JSON parse errors instead of throwing,
so a corrupt state is a clean fail-closed rather than a crash.
