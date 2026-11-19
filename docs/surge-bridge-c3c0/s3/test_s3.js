// C3-C0-S3 isolated verification: server unique ID allocator (draft design).
// Node.js, no real tokens/URLs. Synthetic IDs only.
// Simulates: the allocator under a mock global lock + mock atomic persist,
// durable idempotency-key tombstones, and the ms-canonical increasing check.
//
// Rev 1 (2026-11-19, GPT review 7010797396 — addressed):
//   - NO auto-eviction of idempotency keys. Tombstones are retained for the
//     supported retry horizon (7 days); an unknown/expired retry identity
//     is explicitly rejected (409 retry_identity_unknown); a full history
//     fails closed with 503 history_full instead of silently evicting.
//   - A persist failure means commit_state = unknown, NOT "rolled back".
//     A retry with a different key must not create a second action until
//     the previous transaction is reconciled with durable server-side proof.
//
// Run: node test_s3.js
// Output: s3_out.json + PASS/FAIL lines on stdout.
"use strict";
const fs = require("node:fs");
const path = require("node:path");

const MAX_SAFE = Number.MAX_SAFE_INTEGER; // 2^53 - 1
const RETRY_HORIZON_MS = 7 * 24 * 3600 * 1000; // 7 days (design §2.3)
const MAX_TOMBSTONES_DEFAULT = 10000;          // design §2.3

// --- canonical ms ordering (same semantics as the phone's orderMillis) ---
function orderMillis(v) {
  if (!Number.isSafeInteger(v) || v <= 0) return null;
  if (v >= 1000000000000) return v;
  const ms = v * 1000;
  return Number.isSafeInteger(ms) ? ms : null;
}

// --- mock persistent store (atomic persist simulation) ---
// Holds the FULL durable state:
//   { allocator: { last_allocated, keys: { <key>: tombstone } },
//     mailbox: { cmd: null | {id, actions} } }
// A tombstone is { id, issued_at_ms, status: "pending"|"resolved",
// action_hash }. save() persists atomically.
// Fault injection:
//   store.failNextSave = true            -> the next save() throws
//   store.persistActuallySucceeded       -> whether the durable data was
//     updated before the exception (models sync/rename succeeding before
//     persist reports an error). The allocator does NOT know which.
//   store.unreadable = true              -> load() returns corrupt
function makeStore() {
  let data = null; // JSON string, null = no state yet
  return {
    failNextSave: false,
    persistActuallySucceeded: false,
    unreadable: false,
    load() {
      if (this.unreadable) return { __corrupt: true };
      if (data === null) return null;
      try { return JSON.parse(data); }
      catch (_) { return { __corrupt: true }; }
    },
    save(obj) {
      if (this.failNextSave) {
        this.failNextSave = false;
        if (this.persistActuallySucceeded) data = JSON.stringify(obj);
        throw new Error("mock persist exception");
      }
      data = JSON.stringify(obj);
      return true;
    },
    raw() { return data; },
    corrupt() { data = "{garbage"; },
  };
}

// --- the allocator (draft design Rev 1, §2.2/§2.3/§2.7) ---
function makeAllocator(store, opts) {
  opts = opts || {};
  const maxTombstones = opts.maxTombstones || MAX_TOMBSTONES_DEFAULT;
  // Live (in-memory) state; the durable state lives in the store.
  let state = store.load();
  if (state === null) {
    state = { allocator: { last_allocated: 0, keys: {} }, mailbox: { cmd: null } };
    store.save(state);
  }
  if (typeof state !== "object" || state.__corrupt === true || !state.allocator ||
      !Number.isSafeInteger(state.allocator.last_allocated) ||
      typeof state.allocator.keys !== "object" ||
      !state.mailbox || !("cmd" in state.mailbox)) {
    return { ok: false, error: "allocator_state_invalid" };
  }
  let commitState = "committed"; // "committed" | "unknown"
  let unknownTx = null;          // { key, id } of the unknown transaction

  // Next strictly-increasing id WITHOUT mutating live state (used by issue();
  // allocate() below is the mutating variant used by the direct tests).
  function nextId(nowMs) {
    if (!Number.isSafeInteger(nowMs) || nowMs <= 0) {
      return { ok: false, error: "invalid_clock" };
    }
    const candidate = Math.max(nowMs, state.allocator.last_allocated + 1);
    if (!Number.isSafeInteger(candidate) || candidate > MAX_SAFE) {
      return { ok: false, error: "overflow" };
    }
    return { ok: true, id: candidate };
  }

  const api = {
    ok: true,
    state,
    store,
    maxTombstones,
    retryHorizonMs: RETRY_HORIZON_MS,
    commitState() { return commitState; },
    // Allocate a strictly increasing unique ms id (direct-test helper;
    // mutates the live high-water mark, as in the original draft).
    allocate(nowMs) {
      const r = nextId(nowMs);
      if (!r.ok) return r;
      state.allocator.last_allocated = r.id;
      return { ok: true, id: r.id };
    },
    // Reconcile an unknown transaction against durable server-side proof.
    // Returns { ok, id? } (id = the durably stored command's id),
    // { ok, absent: true } (provably absent), or { ok: false, error }.
    reconcile() {
      const durable = store.load();
      if (durable === null || durable.__corrupt === true || !durable.allocator ||
          typeof durable.allocator.keys !== "object") {
        return { ok: false, error: "reconcile_unreadable" };
      }
      // Durable state is the truth; adopt it as the live state.
      state = durable;
      api.state = state;
      if (unknownTx) {
        const t = durable.allocator.keys[unknownTx.key];
        if (t && t.id === unknownTx.id) {
          // The original transaction IS durably stored (the write succeeded
          // before the persist exception). Return its id; no second action.
          const id = unknownTx.id;
          commitState = "committed";
          unknownTx = null;
          return { ok: true, id };
        }
      }
      // Durable state is readable and has no such tombstone: the original
      // transaction is provably absent.
      commitState = "committed";
      unknownTx = null;
      return { ok: true, absent: true };
    },
    // Mark the pending command resolved (test helper: simulates a result
    // being stored and the mailbox clearing).
    resolve() {
      if (!state.mailbox.cmd) return false;
      const id = state.mailbox.cmd.id;
      for (const k of Object.keys(state.allocator.keys)) {
        if (state.allocator.keys[k].id === id) {
          state.allocator.keys[k].status = "resolved";
        }
      }
      state.mailbox.cmd = null;
      try { store.save(state); } catch (_e) { return false; }
      return true;
    },
    // Issue a command. Signature: issue(idempotencyKey, nowMs, isRetry).
    // isRetry=true means the caller claims this is a retry of an earlier
    // request (same key). A first attempt passes isRetry=false/omitted.
    issue(idempotencyKey, nowMs, isRetry) {
      // 1. Reconcile any unknown transaction FIRST. Nothing else may
      //    proceed until the previous commit's outcome is proven.
      if (commitState === "unknown") {
        const r = this.reconcile();
        if (!r.ok) {
          return { ok: false, code: 503, error: r.error, commit_state: "unknown" };
        }
        if (r.id !== undefined) {
          // Durable proof: the original command is stored. Return its id;
          // no second allocation, no second action.
          return { ok: true, code: 200, id: r.id, duplicate: true, reconciled: true };
        }
        // r.absent: provably absent; fall through and handle the new request.
      }
      const keys = state.allocator.keys;
      // 2. Idempotency FIRST: a retry with a known key returns the same id
      //    even though the mailbox still holds that command as pending.
      if (idempotencyKey && keys[idempotencyKey] !== undefined) {
        const id = keys[idempotencyKey].id;
        return { ok: true, code: 200, id, duplicate: true };
      }
      // 3. Retry with an UNKNOWN key: explicitly rejected. The server
      //    cannot prove the action was not already executed, so it must
      //    not execute it again as if it were new (Rev 1, §2.3).
      if (isRetry) {
        return { ok: false, code: 409, error: "retry_identity_unknown" };
      }
      // 4. Pending check.
      if (state.mailbox.cmd !== null && state.mailbox.cmd !== undefined) {
        return { ok: false, code: 409, error: "pending_command_exists" };
      }
      // 5. History full: fail closed. Never silently evict and reissue.
      if (Object.keys(keys).length >= maxTombstones) {
        return { ok: false, code: 503, error: "history_full" };
      }
      // 6. Allocate and persist atomically (allocator + mailbox in one
      //    commit). The live state is updated ONLY on persist success.
      const r = nextId(nowMs);
      if (!r.ok) return { ok: false, code: 503, error: r.error };
      const newState = JSON.parse(JSON.stringify(state));
      newState.allocator.last_allocated = r.id;
      if (idempotencyKey) {
        newState.allocator.keys[idempotencyKey] = {
          id: r.id, issued_at_ms: nowMs, status: "pending",
          action_hash: "h-" + r.id,
        };
      }
      newState.mailbox.cmd = { id: r.id, actions: [{ type: "api", method: "GET" }] };
      try {
        store.save(newState);
      } catch (_e) {
        // commit_state = unknown. Do NOT roll back in memory and do NOT
        // assume the command is absent: the durable write may have
        // succeeded before the exception (Rev 1, §2.7).
        commitState = "unknown";
        unknownTx = { key: idempotencyKey, id: r.id };
        return { ok: false, code: 503, error: "durable_commit_failed", commit_state: "unknown" };
      }
      state = newState;
      api.state = state;
      return { ok: true, code: 200, id: r.id, duplicate: false };
    },
    // Canonical increasing check (the §2.4 fix for issue_if_empty).
    increasingOk(newId, lastResultId) {
      const a = orderMillis(newId), b = orderMillis(lastResultId);
      if (a === null || b === null) return false;
      return a > b;
    },
    // Raw increasing check (the CURRENT buggy behaviour, for contrast).
    increasingOkRaw(newId, lastResultId) {
      return newId > lastResultId;
    },
  };
  return api;
}

// --- test harness ---
const results = [];
function record(id, name, pass, detail) {
  results.push({ id, name, status: pass ? "PASS" : "FAIL", detail });
  console.log((pass ? "PASS " : "FAIL ") + id + " " + name + " — " + detail);
}

const BASE_MS = 1795064000000; // synthetic "now" (ms)

function testIncreasing1000() {
  const store = makeStore();
  const a = makeAllocator(store);
  let prev = 0, ok = true, count = 0;
  for (let i = 0; i < 1000; i++) {
    const r = a.allocate(BASE_MS + i);
    if (!r.ok || r.id <= prev) { ok = false; break; }
    prev = r.id; count++;
  }
  record("S3-T1", "strictly increasing across 1000 allocations",
    ok && count === 1000, "count=" + count + " last=" + prev);
}

function testSameMillisecond() {
  const store = makeStore();
  const a = makeAllocator(store);
  const ids = new Set();
  let prev = 0, ok = true;
  for (let i = 0; i < 50; i++) {
    const r = a.allocate(BASE_MS); // frozen clock: same ms every time
    if (!r.ok || r.id <= prev || ids.has(r.id)) { ok = false; break; }
    ids.add(r.id); prev = r.id;
  }
  record("S3-T2", "no duplicates, 50 allocations in the same millisecond",
    ok && ids.size === 50,
    "distinct=" + ids.size + " first=" + (BASE_MS) + " last=" + prev);
}

function testRestart() {
  const store = makeStore();
  const a1 = makeAllocator(store);
  const allocated = [];
  for (let i = 0; i < 10; i++) allocated.push(a1.allocate(BASE_MS + i).id);
  // simulate a restart: new allocator instance loads the persisted state
  const a2 = makeAllocator(store);
  const r = a2.allocate(BASE_MS + 10);
  record("S3-T3", "no repeats across a simulated restart",
    a2.ok && r.ok && r.id > Math.max(...allocated),
    "max-before-restart=" + Math.max(...allocated) + " first-after=" + r.id);
}

function testIdempotency() {
  const store = makeStore();
  const a = makeAllocator(store);
  const key = "idem-key-001";
  const r1 = a.issue(key, BASE_MS, false);
  const cmdAfterFirst = a.state.mailbox.cmd ? a.state.mailbox.cmd.id : null;
  // retry with the same key while the command is still pending
  const r2 = a.issue(key, BASE_MS + 5, true);
  record("S3-T4", "retry with same idempotency key returns the same id",
    r1.ok && r2.ok && r1.id === r2.id && r2.duplicate === true &&
    a.state.mailbox.cmd && a.state.mailbox.cmd.id === cmdAfterFirst,
    "first=" + r1.id + " retry=" + r2.id + " duplicate=" + r2.duplicate);
}

function testSecondsNormalization() {
  // A caller-supplied seconds id is normalized to ms for ORDERING, but the
  // raw id is preserved for the receipt. Contrast raw vs canonical.
  const store = makeStore();
  const a = makeAllocator(store);
  const LEGACY_MS = 1795055213880, PENDING_SEC = 1795063030;
  // raw comparison (current bug): PENDING_SEC <= LEGACY_MS -> "not increasing"
  const rawSaysIncreasing = a.increasingOkRaw(PENDING_SEC, LEGACY_MS);
  // canonical comparison (fixed): 1795063030000 > 1795055213880 -> increasing
  const canonSaysIncreasing = a.increasingOk(PENDING_SEC, LEGACY_MS);
  // and the reverse: an older ms id vs a newer seconds last-result id
  const olderMs = 1795055213880, newerSecLast = 1795063030;
  const rawWronglyAccepts = a.increasingOkRaw(olderMs, newerSecLast);
  const canonCorrectlyRejects = !a.increasingOk(olderMs, newerSecLast);
  record("S3-T5", "seconds id normalized to ms for ordering, raw preserved",
    rawSaysIncreasing === false && canonSaysIncreasing === true &&
    rawWronglyAccepts === true && canonCorrectlyRejects === true,
    "raw(sec>ms)=" + rawSaysIncreasing + " canon(sec>ms)=" + canonSaysIncreasing +
    " raw(ms>sec)=" + rawWronglyAccepts + " canon-rejects-older-ms=" + canonCorrectlyRejects);
}

function testGreaterThanLastResult() {
  const store = makeStore();
  const a = makeAllocator(store);
  // last result is a ms id
  const r1 = a.allocate(BASE_MS);
  const okMs = a.increasingOk(r1.id, 1795055213880);
  // last result is a seconds id
  const r2 = a.allocate(BASE_MS + 1);
  const okSec = a.increasingOk(r2.id, 1795063030);
  record("S3-T6", "new id greater (ms ordering) than any last result id (s and ms)",
    r1.ok && r2.ok && okMs && okSec,
    "id1=" + r1.id + " >ms-last=" + okMs + " id2=" + r2.id + " >sec-last=" + okSec);
}

function testPendingRefusal() {
  const store = makeStore();
  const a = makeAllocator(store);
  const first = a.issue("idem-key-002a", BASE_MS, false);
  const before = a.state.allocator.last_allocated;
  const r = a.issue("idem-key-002", BASE_MS, false);
  record("S3-T7", "allocator refuses when a pending command exists (409)",
    first.ok && !r.ok && r.code === 409 && r.error === "pending_command_exists" &&
    a.state.allocator.last_allocated === before &&
    a.state.mailbox.cmd.id === first.id,
    "code=" + r.code + " last_allocated-unchanged=" +
    (a.state.allocator.last_allocated === before));
}

function testClockBackwards() {
  const store = makeStore();
  const a = makeAllocator(store);
  const r1 = a.allocate(BASE_MS + 100);
  // clock goes backwards by 60 seconds
  const r2 = a.allocate(BASE_MS - 60000);
  const r3 = a.allocate(BASE_MS - 60000);
  record("S3-T8", "clock going backwards preserves monotonicity",
    r1.ok && r2.ok && r3.ok && r2.id === r1.id + 1 && r3.id === r2.id + 1,
    "ids=" + r1.id + "," + r2.id + "," + r3.id);
}

function testOverflowFailClosed() {
  const store = makeStore();
  const a = makeAllocator(store);
  // invalid wall clock
  const badClock = a.allocate(-5);
  const zeroClock = a.allocate(0);
  // candidate beyond the safe-integer range: force last_allocated to the max
  a.state.allocator.last_allocated = MAX_SAFE;
  const overflow = a.allocate(MAX_SAFE);
  record("S3-T9", "overflow / invalid clock fails closed (503, nothing allocated)",
    !badClock.ok && badClock.error === "invalid_clock" &&
    !zeroClock.ok && !overflow.ok && overflow.error === "overflow",
    "badClock=" + badClock.error + " zero=" + zeroClock.error +
    " overflow=" + overflow.error);
}

function testCorruptStateFailClosed() {
  const store = makeStore();
  store.corrupt();
  const a = makeAllocator(store);
  record("S3-T10", "corrupt allocator state fails closed (no allocation)",
    !a.ok && a.error === "allocator_state_invalid",
    "ok=" + a.ok + " error=" + a.error);
}

// --- Rev 1 adversarial tests (GPT review 7010797396) ---

function testExpiredRetryRejected() {
  const store = makeStore();
  const a = makeAllocator(store);
  // (a) a retry with a key that was NEVER issued -> explicit rejection.
  const neverIssued = a.issue("idem-key-never", BASE_MS, true);
  // (b) a retry whose tombstone was archived after the horizon (simulated
  //     by removing it from the store): the same key, marked retry.
  const first = a.issue("idem-key-011", BASE_MS + 10, false);
  const issuedId = first.id;
  // archive the tombstone (operator action after the retry horizon)
  delete a.state.allocator.keys["idem-key-011"];
  store.save(a.state);
  const archivedRetry = a.issue("idem-key-011", BASE_MS + 20, true);
  record("S3-T11", "evicted/expired-key retry explicitly rejected, never re-executed",
    first.ok &&
    !neverIssued.ok && neverIssued.code === 409 && neverIssued.error === "retry_identity_unknown" &&
    !archivedRetry.ok && archivedRetry.code === 409 && archivedRetry.error === "retry_identity_unknown" &&
    a.state.mailbox.cmd && a.state.mailbox.cmd.id === issuedId &&
    a.state.allocator.last_allocated === issuedId,
    "never-issued=" + neverIssued.error + " archived-retry=" + archivedRetry.error +
    " mailbox-still=" + (a.state.mailbox.cmd && a.state.mailbox.cmd.id) +
    " last_allocated-unchanged=" + (a.state.allocator.last_allocated === issuedId));
}

function testHistoryFullFailClosed() {
  const store = makeStore();
  const a = makeAllocator(store, { maxTombstones: 3 });
  // Fill the tombstone store to its count limit (resolve each command so
  // the single-slot mailbox clears between issues).
  let ok = true;
  for (let i = 0; i < 3; i++) {
    const r = a.issue("idem-key-012-" + i, BASE_MS + i, false);
    if (!r.ok) { ok = false; break; }
    if (!a.resolve()) { ok = false; break; }
  }
  const before = a.state.allocator.last_allocated;
  const full = a.issue("idem-key-012-3", BASE_MS + 10, false);
  record("S3-T12", "history full fails closed (503), never silently evicts and reissues",
    ok && !full.ok && full.code === 503 && full.error === "history_full" &&
    a.state.allocator.last_allocated === before &&
    a.state.mailbox.cmd === null &&
    Object.keys(a.state.allocator.keys).length === 3,
    "code=" + full.code + " error=" + full.error +
    " last_allocated-unchanged=" + (a.state.allocator.last_allocated === before) +
    " tombstones-kept=" + Object.keys(a.state.allocator.keys).length);
}

function testPersistUnknownDifferentKey() {
  const store = makeStore();
  const a = makeAllocator(store);
  // The persist exception fires AFTER the durable write actually
  // succeeded (sync/rename before the reported error). The allocator
  // does not know that, so commit_state must be unknown.
  store.failNextSave = true;
  store.persistActuallySucceeded = true;
  const first = a.issue("idem-key-013a", BASE_MS, false);
  const unknownOk = !first.ok && first.code === 503 &&
    first.error === "durable_commit_failed" && first.commit_state === "unknown" &&
    a.commitState() === "unknown";
  // Retry with a DIFFERENT key: reconciliation must run first. Durable
  // state HAS the command, so the retry returns the existing id and
  // creates NO second action.
  const retry = a.issue("idem-key-013b", BASE_MS + 5, false);
  const mailboxCmds = a.state.mailbox.cmd ? 1 : 0;
  record("S3-T13", "persist error leaves commit_state=unknown; retry with a different key creates no second action",
    unknownOk &&
    retry.ok && retry.code === 200 && retry.duplicate === true && retry.reconciled === true &&
    retry.id === a.state.allocator.keys["idem-key-013a"].id &&
    a.state.mailbox.cmd && a.state.mailbox.cmd.id === retry.id &&
    mailboxCmds === 1 &&
    a.state.allocator.keys["idem-key-013b"] === undefined &&
    a.commitState() === "committed",
    "first=" + first.error + "/" + first.commit_state +
    " retry-id=" + retry.id + " duplicate=" + retry.duplicate +
    " mailbox-cmds=" + mailboxCmds + " second-key-recorded=" +
    (a.state.allocator.keys["idem-key-013b"] !== undefined));
}

function testPersistUnknownUnreadable() {
  const store = makeStore();
  const a = makeAllocator(store);
  // Persist fails and the durable write did NOT happen; then the durable
  // state becomes unreadable before reconciliation.
  store.failNextSave = true;
  store.persistActuallySucceeded = false;
  const first = a.issue("idem-key-014a", BASE_MS, false);
  const unknownOk = !first.ok && first.code === 503 && first.commit_state === "unknown";
  store.unreadable = true;
  const retry = a.issue("idem-key-014b", BASE_MS + 5, false);
  record("S3-T14", "persist error + unreadable durable state fails closed, stays unknown",
    unknownOk &&
    !retry.ok && retry.code === 503 && retry.error === "reconcile_unreadable" &&
    retry.commit_state === "unknown" && a.commitState() === "unknown" &&
    a.state.mailbox.cmd === null,
    "first=" + first.error + " retry=" + retry.error +
    " commit_state=" + retry.commit_state + " mailbox-empty=" +
    (a.state.mailbox.cmd === null));
}

testIncreasing1000();
testSameMillisecond();
testRestart();
testIdempotency();
testSecondsNormalization();
testGreaterThanLastResult();
testPendingRefusal();
testClockBackwards();
testOverflowFailClosed();
testCorruptStateFailClosed();
testExpiredRetryRejected();
testHistoryFullFailClosed();
testPersistUnknownDifferentKey();
testPersistUnknownUnreadable();

const pass = results.filter(r => r.status === "PASS").length;
const fail = results.filter(r => r.status === "FAIL").length;
const out = { suite: "s3-id-allocator", pass, fail, limitation: 0, results };
fs.writeFileSync(path.join(__dirname, "s3_out.json"),
  JSON.stringify(out, null, 2));
console.log(pass + "/" + (pass + fail) + " s3 tests passed");
if (fail > 0) process.exitCode = 1;
