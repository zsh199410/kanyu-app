// C3-C0-S3 isolated verification: server unique ID allocator (draft design).
// Node.js, no real tokens/URLs. Synthetic IDs only.
// Simulates: the allocator under a mock global lock + mock atomic persist,
// an idempotency-key map, and the ms-canonical increasing check.
//
// Run: node test_s3.js
// Output: s3_out.json + PASS/FAIL lines on stdout.
"use strict";
const fs = require("node:fs");
const path = require("node:path");

const MAX_SAFE = Number.MAX_SAFE_INTEGER; // 2^53 - 1

// --- canonical ms ordering (same semantics as the phone's orderMillis) ---
function orderMillis(v) {
  if (!Number.isSafeInteger(v) || v <= 0) return null;
  if (v >= 1000000000000) return v;
  const ms = v * 1000;
  return Number.isSafeInteger(ms) ? ms : null;
}

// --- mock persistent store (atomic persist simulation) ---
function makeStore() {
  let data = null; // JSON string, null = no state yet
  return {
    load() {
      if (data === null) return null;
      try { return JSON.parse(data); }
      catch (_) { return { __corrupt: true }; }
    },
    save(obj) { data = JSON.stringify(obj); return true; },
    raw() { return data; },
    corrupt() { data = "{garbage"; },
  };
}

// --- the allocator (draft design, §2.2) ---
// State persisted atomically with the mailbox:
//   { last_allocated: <int>, keys: { <idempotency-key>: <id> } }
function makeAllocator(store) {
  // Load persisted state; fail closed if missing/corrupt.
  let state = store.load();
  if (state === null) {
    state = { last_allocated: 0, keys: {} };
    store.save(state);
  }
  if (typeof state !== "object" || state.__corrupt === true ||
      !Number.isSafeInteger(state.last_allocated)
      || typeof state.keys !== "object") {
    return { ok: false, error: "allocator_state_invalid" };
  }
  return {
    ok: true,
    state,
    store,
    // Allocate a strictly increasing unique ms id. Caller must hold the
    // global lock and persist the returned state atomically.
    allocate(nowMs) {
      if (!Number.isSafeInteger(nowMs) || nowMs <= 0) {
        return { ok: false, error: "invalid_clock" };
      }
      const candidate = Math.max(nowMs, state.last_allocated + 1);
      if (!Number.isSafeInteger(candidate) || candidate > MAX_SAFE) {
        return { ok: false, error: "overflow" };
      }
      state.last_allocated = candidate;
      return { ok: true, id: candidate };
    },
    // Issue a command: idempotent by key, refuses when mailbox is occupied.
    // mailbox: { cmd: null | {id, ...} }, lastResultId: int | 0
    issue(mailbox, lastResultId, idempotencyKey, nowMs) {
      // Idempotency FIRST: a retry with a known key returns the same id
      // even though the mailbox still holds that command as pending.
      if (idempotencyKey && state.keys[idempotencyKey] !== undefined) {
        const id = state.keys[idempotencyKey];
        return { ok: true, code: 200, id, duplicate: true };
      }
      if (mailbox.cmd !== null && mailbox.cmd !== undefined) {
        return { ok: false, code: 409, error: "pending_command_exists" };
      }
      const r = this.allocate(nowMs);
      if (!r.ok) return { ok: false, code: 503, error: r.error };
      if (idempotencyKey) state.keys[idempotencyKey] = r.id;
      // bound the keys map (keep last 100)
      const ks = Object.keys(state.keys);
      if (ks.length > 100) delete state.keys[ks[0]];
      mailbox.cmd = { id: r.id, actions: [{ type: "api", method: "GET" }] };
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
  const mailbox = { cmd: null };
  const key = "idem-key-001";
  const r1 = a.issue(mailbox, 0, key, BASE_MS);
  const cmdAfterFirst = mailbox.cmd ? mailbox.cmd.id : null;
  // retry with the same key while the command is still pending
  const r2 = a.issue(mailbox, 0, key, BASE_MS + 5);
  record("S3-T4", "retry with same idempotency key returns the same id",
    r1.ok && r2.ok && r1.id === r2.id && r2.duplicate === true &&
    mailbox.cmd && mailbox.cmd.id === cmdAfterFirst,
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
  const mailbox = { cmd: { id: 2000000001, actions: [] } };
  const before = a.state.last_allocated;
  const r = a.issue(mailbox, 0, "idem-key-002", BASE_MS);
  record("S3-T7", "allocator refuses when a pending command exists (409)",
    !r.ok && r.code === 409 && r.error === "pending_command_exists" &&
    a.state.last_allocated === before && mailbox.cmd.id === 2000000001,
    "code=" + r.code + " last_allocated-unchanged=" +
    (a.state.last_allocated === before));
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
  a.state.last_allocated = MAX_SAFE;
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

const pass = results.filter(r => r.status === "PASS").length;
const fail = results.filter(r => r.status === "FAIL").length;
const out = { suite: "s3-id-allocator", pass, fail, limitation: 0, results };
fs.writeFileSync(path.join(__dirname, "s3_out.json"),
  JSON.stringify(out, null, 2));
console.log(pass + "/" + (pass + fail) + " s3 tests passed");
if (fail > 0) process.exitCode = 1;
