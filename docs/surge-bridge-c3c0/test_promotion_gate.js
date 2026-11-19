"use strict";
/* C3-C0 Round 4 — Item 2 test: staging-to-active promotion gate.
 *
 * Synthetic tokens only, mock $persistentStore, no network, no phone.
 * The gate is required to fail closed at every step: any failure
 * before the read-back verification leaves the active token unchanged
 * and the candidate intact. A mock mailbox state (cmd 1795063030,
 * OUTCOME_UNKNOWN) is snapshotted before and after EVERY test — the
 * gate must never touch it.
 *
 * Store mock: writeBehavior / readBehavior are per-key maps.
 *   write: "ok" (default) | "false" (return false, do not persist) |
 *          "writeThenFalse" (persist, then return false) | "throw"
 *   read:  "ok" (default) | "corrupt" (return "mismatch" after the
 *          active write) | "throw"
 *   remove: "ok" (default) | "false" | "throw" | "absent" (no remove
 *          method at all — tombstone fallback path)
 */
const assert = require("node:assert/strict");
const { promote, validCandidate, validProof, DEV_KEYS, KEY_KEYS,
  PROMOTED_TOMBSTONE } = require("./promotion_gate");

const DEV_NEW = "TEST-NEW-DEV-CANDIDATE-0123456789ABCDEF";
const DEV_OTHER = "TEST-OTHER-DEV-CANDIDATE-0123456789ABC";
const DEV_OLD = "TEST-ACTIVE-OLD-DEV-0123456789ABCDEF";
const KEY_NEW = "TEST-NEW-LOCALKEY-CANDIDATE-0123456789ABC";
const KEY_OLD = "TEST-ACTIVE-OLD-LOCALKEY-0123456789ABCDE";
const OLD_TOKEN_ID = "TEST-OLD-TOKEN-ID-001";
const NEW_TOKEN_ID = "TEST-NEW-TOKEN-ID-002";
const ALL_SYNTHETIC = [DEV_NEW, DEV_OTHER, DEV_OLD, KEY_NEW, KEY_OLD,
  OLD_TOKEN_ID, NEW_TOKEN_ID];

const OLD_CMD_ID = 1795063030;
const OLD_RESULT_ID = 1795055213880;

function mockProof(overrides = {}) {
  return Object.assign({
    ok: true,
    fingerprint_matches: true,
    token_id: NEW_TOKEN_ID,
    issued_at: Date.now(),
  }, overrides);
}

/* Mock $persistentStore. Writes are recorded as {key, valueKind}
 * only — the value itself is never recorded, so test output cannot
 * leak a token. */
function mockStore({ preload = {}, writeBehavior = {}, readBehavior = {},
  removeBehavior = "ok" } = {}) {
  const map = new Map(Object.entries(preload));
  const writes = [];
  const activeWrites = {};
  const store = {
    read: (k) => {
      if (readBehavior[k] === "throw") throw new Error("synthetic read throw");
      if (readBehavior[k] === "corrupt" && activeWrites[k]) return "mismatch";
      const v = map.get(k);
      return v === undefined ? null : v;
    },
    write: (value, k) => {
      writes.push({ key: k, valueKind: typeof value });
      const wb = writeBehavior[k];
      if (wb === "throw") throw new Error("synthetic write throw");
      if (wb === "false") return false;
      if (wb === "writeThenFalse") {
        map.set(k, value);
        activeWrites[k] = (activeWrites[k] || 0) + 1;
        return false;
      }
      map.set(k, value);
      activeWrites[k] = (activeWrites[k] || 0) + 1;
      return true;
    },
    _map: map,
    _writes: writes,
  };
  if (removeBehavior !== "absent") {
    store.remove = (k) => {
      if (removeBehavior === "throw") throw new Error("synthetic remove throw");
      if (removeBehavior === "false") return false;
      map.delete(k);
      return true;
    };
  }
  return store;
}

/* A mock mailbox state. The gate must never touch it. */
function mockMailbox() {
  return {
    cmd: { id: OLD_CMD_ID },
    result: { id: OLD_RESULT_ID },
    polls: 2439,
    pins: ["synthetic-pin-a", "synthetic-pin-b"],
    timers: ["t1", "t2", "t3", "t4", "t5"],
  };
}
function mailboxSnapshot(m) {
  return JSON.stringify(m);
}

let count = 0;
function check(name, fn) {
  fn();
  count += 1;
  console.log("PASS", name);
}

check("happy path: candidate + valid proof -> promoted, candidate cleared, active = new", () => {
  const store = mockStore({ preload: {
    [DEV_KEYS.candidateKey]: DEV_NEW, [DEV_KEYS.activeKey]: DEV_OLD,
  } });
  const mailbox = mockMailbox();
  const before = mailboxSnapshot(mailbox);
  const r = promote(store, { keys: DEV_KEYS, proof: mockProof(), oldTokenId: OLD_TOKEN_ID });
  assert.deepEqual(r, { ok: true, status: "promotion_done" });
  assert.equal(store._map.get(DEV_KEYS.activeKey), DEV_NEW);
  assert.equal(store._map.has(DEV_KEYS.candidateKey), false);
  assert.equal(store._map.get(DEV_KEYS.statusKey), "promotion_done");
  assert.equal(mailboxSnapshot(mailbox), before);
});

check("missing candidate -> fail-closed, active unchanged", () => {
  const store = mockStore({ preload: { [DEV_KEYS.activeKey]: DEV_OLD } });
  const mailbox = mockMailbox();
  const before = mailboxSnapshot(mailbox);
  const r = promote(store, { keys: DEV_KEYS, proof: mockProof(), oldTokenId: OLD_TOKEN_ID });
  assert.deepEqual(r, { ok: false, status: "promotion_no_candidate" });
  assert.equal(store._map.get(DEV_KEYS.activeKey), DEV_OLD);
  assert.equal(store._map.has(DEV_KEYS.candidateKey), false);
  assert.equal(mailboxSnapshot(mailbox), before);
});

check("invalid candidate -> fail-closed, active unchanged, candidate intact", () => {
  const store = mockStore({ preload: {
    [DEV_KEYS.candidateKey]: "short", [DEV_KEYS.activeKey]: DEV_OLD,
  } });
  const r = promote(store, { keys: DEV_KEYS, proof: mockProof(), oldTokenId: OLD_TOKEN_ID });
  assert.deepEqual(r, { ok: false, status: "promotion_invalid_candidate" });
  assert.equal(store._map.get(DEV_KEYS.activeKey), DEV_OLD);
  assert.equal(store._map.get(DEV_KEYS.candidateKey), "short");
});

check("invalid proof (ok=false) -> fail-closed, active unchanged, candidate intact", () => {
  const store = mockStore({ preload: {
    [DEV_KEYS.candidateKey]: DEV_NEW, [DEV_KEYS.activeKey]: DEV_OLD,
  } });
  const r = promote(store, { keys: DEV_KEYS, proof: mockProof({ ok: false }), oldTokenId: OLD_TOKEN_ID });
  assert.deepEqual(r, { ok: false, status: "promotion_invalid_proof" });
  assert.equal(store._map.get(DEV_KEYS.activeKey), DEV_OLD);
  assert.equal(store._map.get(DEV_KEYS.candidateKey), DEV_NEW);
});

check("invalid proof (fingerprint mismatch) -> fail-closed", () => {
  const store = mockStore({ preload: {
    [DEV_KEYS.candidateKey]: DEV_NEW, [DEV_KEYS.activeKey]: DEV_OLD,
  } });
  const r = promote(store, { keys: DEV_KEYS, proof: mockProof({ fingerprint_matches: false }), oldTokenId: OLD_TOKEN_ID });
  assert.deepEqual(r, { ok: false, status: "promotion_invalid_proof" });
  assert.equal(store._map.get(DEV_KEYS.activeKey), DEV_OLD);
});

check("invalid proof (stale, 25h old) -> fail-closed", () => {
  const store = mockStore({ preload: {
    [DEV_KEYS.candidateKey]: DEV_NEW, [DEV_KEYS.activeKey]: DEV_OLD,
  } });
  const r = promote(store, { keys: DEV_KEYS,
    proof: mockProof({ issued_at: Date.now() - 25 * 60 * 60 * 1000 }),
    oldTokenId: OLD_TOKEN_ID });
  assert.deepEqual(r, { ok: false, status: "promotion_invalid_proof" });
  assert.equal(store._map.get(DEV_KEYS.activeKey), DEV_OLD);
});

check("proof for the OLD token id -> fail-closed (never promote the exposed token)", () => {
  const store = mockStore({ preload: {
    [DEV_KEYS.candidateKey]: DEV_NEW, [DEV_KEYS.activeKey]: DEV_OLD,
  } });
  const r = promote(store, { keys: DEV_KEYS,
    proof: mockProof({ token_id: OLD_TOKEN_ID }), oldTokenId: OLD_TOKEN_ID });
  assert.deepEqual(r, { ok: false, status: "promotion_invalid_proof" });
  assert.equal(store._map.get(DEV_KEYS.activeKey), DEV_OLD);
  assert.equal(store._map.get(DEV_KEYS.candidateKey), DEV_NEW);
});

check("active write returns false, not persisted -> commit_unknown, active unchanged, candidate intact", () => {
  const store = mockStore({ preload: {
    [DEV_KEYS.candidateKey]: DEV_NEW, [DEV_KEYS.activeKey]: DEV_OLD,
  }, writeBehavior: { [DEV_KEYS.activeKey]: "false" } });
  const r = promote(store, { keys: DEV_KEYS, proof: mockProof(), oldTokenId: OLD_TOKEN_ID });
  assert.deepEqual(r, { ok: false, status: "promotion_commit_unknown" });
  assert.equal(store._map.get(DEV_KEYS.activeKey), DEV_OLD);
  assert.equal(store._map.get(DEV_KEYS.candidateKey), DEV_NEW);
});

check("active write persisted then returns false -> commit_unknown, NOT reported as success, candidate intact", () => {
  const store = mockStore({ preload: {
    [DEV_KEYS.candidateKey]: DEV_NEW, [DEV_KEYS.activeKey]: DEV_OLD,
  }, writeBehavior: { [DEV_KEYS.activeKey]: "writeThenFalse" } });
  const r = promote(store, { keys: DEV_KEYS, proof: mockProof(), oldTokenId: OLD_TOKEN_ID });
  assert.deepEqual(r, { ok: false, status: "promotion_commit_unknown" });
  /* The value IS on disk despite the false return — the gate must
   * not claim success and must not clear the candidate. */
  assert.equal(store._map.get(DEV_KEYS.activeKey), DEV_NEW);
  assert.equal(store._map.get(DEV_KEYS.candidateKey), DEV_NEW);
});

check("read-back mismatch -> fail-closed, candidate intact", () => {
  const store = mockStore({ preload: {
    [DEV_KEYS.candidateKey]: DEV_NEW, [DEV_KEYS.activeKey]: DEV_OLD,
  }, readBehavior: { [DEV_KEYS.activeKey]: "corrupt" } });
  const r = promote(store, { keys: DEV_KEYS, proof: mockProof(), oldTokenId: OLD_TOKEN_ID });
  assert.deepEqual(r, { ok: false, status: "promotion_readback_unverified" });
  assert.equal(store._map.get(DEV_KEYS.candidateKey), DEV_NEW);
});

check("promotion attempted twice -> second is a no-op (already promoted, candidate gone)", () => {
  const store = mockStore({ preload: {
    [DEV_KEYS.candidateKey]: DEV_NEW, [DEV_KEYS.activeKey]: DEV_OLD,
  } });
  const first = promote(store, { keys: DEV_KEYS, proof: mockProof(), oldTokenId: OLD_TOKEN_ID });
  assert.deepEqual(first, { ok: true, status: "promotion_done" });
  const second = promote(store, { keys: DEV_KEYS, proof: mockProof(), oldTokenId: OLD_TOKEN_ID });
  assert.deepEqual(second, { ok: true, status: "promotion_already_active" });
  assert.equal(store._map.get(DEV_KEYS.activeKey), DEV_NEW);
});

check("no active key -> fail-closed (initial provisioning is a different gate)", () => {
  const store = mockStore({ preload: { [DEV_KEYS.candidateKey]: DEV_NEW } });
  const r = promote(store, { keys: DEV_KEYS, proof: mockProof(), oldTokenId: OLD_TOKEN_ID });
  assert.deepEqual(r, { ok: false, status: "promotion_no_active" });
  assert.equal(store._map.get(DEV_KEYS.candidateKey), DEV_NEW);
});

check("candidate clear fails -> active is the new verified value, candidate intact, retry converges to already-promoted", () => {
  const store = mockStore({ preload: {
    [DEV_KEYS.candidateKey]: DEV_NEW, [DEV_KEYS.activeKey]: DEV_OLD,
  }, removeBehavior: "false" });
  const r = promote(store, { keys: DEV_KEYS, proof: mockProof(), oldTokenId: OLD_TOKEN_ID });
  assert.deepEqual(r, { ok: false, status: "promotion_candidate_clear_failed" });
  assert.equal(store._map.get(DEV_KEYS.activeKey), DEV_NEW);
  assert.equal(store._map.get(DEV_KEYS.candidateKey), DEV_NEW);
  /* Retry: active === candidate, so the gate reports already-promoted. */
  const retry = promote(store, { keys: DEV_KEYS, proof: mockProof(), oldTokenId: OLD_TOKEN_ID });
  assert.deepEqual(retry, { ok: true, status: "promotion_already_active" });
});

check("store without remove() -> tombstone fallback, candidate never validates again", () => {
  const store = mockStore({ preload: {
    [DEV_KEYS.candidateKey]: DEV_NEW, [DEV_KEYS.activeKey]: DEV_OLD,
  }, removeBehavior: "absent" });
  const r = promote(store, { keys: DEV_KEYS, proof: mockProof(), oldTokenId: OLD_TOKEN_ID });
  assert.deepEqual(r, { ok: true, status: "promotion_done" });
  assert.equal(store._map.get(DEV_KEYS.activeKey), DEV_NEW);
  assert.equal(store._map.get(DEV_KEYS.candidateKey), PROMOTED_TOMBSTONE);
  assert.equal(validCandidate(store._map.get(DEV_KEYS.candidateKey)), false);
});

check("local-key pair uses the same gate: happy path", () => {
  const store = mockStore({ preload: {
    [KEY_KEYS.candidateKey]: KEY_NEW, [KEY_KEYS.activeKey]: KEY_OLD,
  } });
  const mailbox = mockMailbox();
  const before = mailboxSnapshot(mailbox);
  const r = promote(store, { keys: KEY_KEYS, proof: mockProof(), oldTokenId: OLD_TOKEN_ID });
  assert.deepEqual(r, { ok: true, status: "promotion_done" });
  assert.equal(store._map.get(KEY_KEYS.activeKey), KEY_NEW);
  assert.equal(store._map.has(KEY_KEYS.candidateKey), false);
  assert.equal(mailboxSnapshot(mailbox), before);
});

check("old command id untouched in every path (mailbox snapshot)", () => {
  const mailbox = mockMailbox();
  const before = mailboxSnapshot(mailbox);
  const cases = [
    mockStore({ preload: { [DEV_KEYS.candidateKey]: DEV_NEW, [DEV_KEYS.activeKey]: DEV_OLD } }),
    mockStore({ preload: { [DEV_KEYS.activeKey]: DEV_OLD } }),
    mockStore({ preload: { [DEV_KEYS.candidateKey]: DEV_NEW, [DEV_KEYS.activeKey]: DEV_OLD },
      writeBehavior: { [DEV_KEYS.activeKey]: "writeThenFalse" } }),
    mockStore({ preload: { [DEV_KEYS.candidateKey]: DEV_NEW, [DEV_KEYS.activeKey]: DEV_OLD },
      removeBehavior: "false" }),
  ];
  for (const store of cases) {
    promote(store, { keys: DEV_KEYS, proof: mockProof(), oldTokenId: OLD_TOKEN_ID });
  }
  assert.equal(mailboxSnapshot(mailbox), before);
  const m = JSON.parse(before);
  assert.equal(m.cmd.id, OLD_CMD_ID);
  assert.equal(m.result.id, OLD_RESULT_ID);
});

check("no secret in any returned result or recorded write", () => {
  const store = mockStore({ preload: {
    [DEV_KEYS.candidateKey]: DEV_NEW, [DEV_KEYS.activeKey]: DEV_OLD,
  } });
  const r = promote(store, { keys: DEV_KEYS, proof: mockProof(), oldTokenId: OLD_TOKEN_ID });
  const blob = JSON.stringify(r) + JSON.stringify(store._writes);
  for (const s of ALL_SYNTHETIC) {
    assert.equal(blob.includes(s), false, "result leaks a synthetic value");
  }
  assert.equal(blob.includes("TEST-"), false, "result contains a TEST- string");
  assert.equal(validProof(mockProof(), OLD_TOKEN_ID), true);
  assert.equal(validProof(mockProof({ token_id: OLD_TOKEN_ID }), OLD_TOKEN_ID), false);
});

console.log("SUMMARY", count, "PASS, 0 FAIL");
