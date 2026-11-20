"use strict";
/* C3-C0 Round 3C — P0-B1/B2/B3 candidate-staging regressions.
 *
 * Synthetic tokens only, VM mock, no network, no phone.
 *
 * Section D — DOCUMENTED DEFECT DEMONSTRATION (deprecated s1/bootstrap.js).
 *   These two tests assert the defect EXISTS in the deprecated script:
 *   they PASS when the defective behaviour is observed. They are NOT
 *   gates for the new approach; they are the proof that GPT's P0-B2
 *   findings are real and that the deprecated script must not be used.
 * Section R — P0-B2 regressions for the NEW candidate-staging approach
 *   (PR #101 DEV template + the local-key companion template).
 *   The new approach has NO two-key atomic write BY DESIGN: staging
 *   never touches the active keys, so a partial update of ACTIVE keys
 *   is impossible. These tests prove that property.
 * Section L — dedicated tests for the local-key candidate template.
 *
 * Never assume an exception proves storage did not commit: every
 * write-false case is tested in both flavours (not persisted, and
 * persisted-then-false).
 */
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const DEV_SRC = fs.readFileSync(path.join(__dirname,
  "bootstrap_candidate_shortcuts.template.js"), "utf8");
const KEY_SRC = fs.readFileSync(path.join(__dirname,
  "bootstrap_candidate_localkey.template.js"), "utf8");
const DEPRECATED_SRC = fs.readFileSync(path.join(__dirname,
  "s1", "bootstrap.js"), "utf8");

const DEV_STAGED = "sgbridge_cred_dev_candidate";
const DEV_ACTIVE = "sgbridge_cred_dev";
const DEV_STATUS = "sgbridge_cred_bootstrap_status";
const KEY_STAGED = "sgbridge_cred_localkey_candidate";
const KEY_ACTIVE = "sgbridge_cred_localkey";
const KEY_STATUS = "sgbridge_cred_localkey_bootstrap_status";
const DONE_KEY = "sgbridge_bootstrap_done";

const DEV_NEW = "TEST-NEW-DEV-CANDIDATE-0123456789ABCDEF";
const DEV_OTHER = "TEST-OTHER-DEV-CANDIDATE-0123456789ABC";
const DEV_OLD = "TEST-ACTIVE-OLD-DEV-0123456789ABCDEF";
const KEY_NEW = "TEST-NEW-LOCALKEY-CANDIDATE-0123456789ABC";
const KEY_OTHER = "TEST-OTHER-LOCALKEY-CANDIDATE-0123456789AB";
const KEY_OLD = "TEST-ACTIVE-OLD-LOCALKEY-0123456789ABCDE";
const ALL_SYNTHETIC = [DEV_NEW, DEV_OTHER, DEV_OLD, KEY_NEW, KEY_OTHER, KEY_OLD];

/* Generic runner for a candidate-staging template (DEV or local-key).
 * writeBehavior / readBehavior are per-key maps:
 *   write: "ok" (default) | "false" (return false, do not persist) |
 *          "writeThenFalse" (persist, then return false) | "throw"
 *   read:  "ok" (default) | "corrupt" (return "mismatch" after a
 *          candidate write) | "throw"
 * Writes are recorded as {key, valueKind} only — the value itself is
 * never recorded, so the test output cannot leak a token. */
function runTemplate(src, {
  trigger = "intent", parameter, store, preload = {},
  writeBehavior = {}, readBehavior = {},
} = {}) {
  const map = store || new Map(Object.entries(preload));
  let done = 0, network = 0;
  const logs = [];
  const writes = [];
  const perKeyWrites = {};
  const sandbox = {
    $trigger: trigger,
    $intent: { parameter },
    $persistentStore: {
      read: (k) => {
        const rb = readBehavior[k];
        if (rb === "throw") throw new Error("synthetic read throw");
        if (rb === "corrupt" && perKeyWrites[k]) return "mismatch";
        const v = map.get(k);
        return v === undefined ? null : v;
      },
      write: (value, k) => {
        writes.push({ key: k, valueKind: typeof value });
        perKeyWrites[k] = (perKeyWrites[k] || 0) + 1;
        const wb = writeBehavior[k];
        if (wb === "throw") throw new Error("synthetic write throw");
        if (wb === "false") return false;
        if (wb === "writeThenFalse") { map.set(k, value); return false; }
        map.set(k, value);
        return true;
      },
    },
    $httpClient: { get: () => { network++; }, post: () => { network++; } },
    $httpAPI: () => { network++; },
    console: {
      log: (...x) => { logs.push(x.join(" ")); },
      error: (...x) => { logs.push(x.join(" ")); },
    },
    $done: () => { done++; },
  };
  vm.runInNewContext(src, sandbox, { timeout: 1000 });
  return { store: map, writes, perKeyWrites, logs, network, done };
}

/* Runner for the DEPRECATED s1/bootstrap.js (defect demonstration only).
 * Injects synthetic credentials into the <PASTE_...> constants via
 * JSON.stringify, exactly like s1/bootstrap_test.js does. */
function runDeprecated({ dev = DEV_NEW, key = KEY_NEW, preload = {},
  writeBehavior = {} } = {}) {
  const src = DEPRECATED_SRC
    .replace(/"<PASTE_NEW_DEV_TOKEN_HERE>"/, JSON.stringify(dev))
    .replace(/"<PASTE_NEW_LOCAL_KEY_HERE>"/, JSON.stringify(key));
  const map = new Map(Object.entries(preload));
  const logs = [];
  const notes = [];
  const writes = [];
  let doneCalls = 0;
  const ctx = {
    $persistentStore: {
      read: (k) => {
        const v = map.get(k);
        return v === undefined ? null : v;
      },
      write: (value, k) => {
        writes.push(k);
        const wb = writeBehavior[k];
        if (wb === "false") return false;
        map.set(k, value);
        return true;
      },
    },
    $notification: { post: (_t, _s, msg) => { notes.push(msg); } },
    console: { log: (msg) => { logs.push(String(msg)); } },
    $done: () => { doneCalls++; },
  };
  vm.runInNewContext(src, ctx, { timeout: 1000 });
  return { store: map, logs, notes, doneCalls, writes };
}

function noSyntheticLeak(text) {
  return ALL_SYNTHETIC.every((t) => !text.includes(t));
}

let pass = 0, fail = 0;
const failures = [];
const testNames = [];
function check(name, fn) {
  testNames.push(name);
  try {
    fn();
    pass++;
    console.log("PASS", name);
  } catch (e) {
    fail++;
    failures.push(name + ": " + (e && e.message));
    console.log("FAIL", name, "-", e && e.message);
  }
}

/* ------------------------------------------------------------------ */
/* Section D — DOCUMENTED DEFECT DEMONSTRATION (deprecated script).   */
/* These tests PASS when the defect is observed. NOT a gate for the   */
/* new approach.                                                      */
/* ------------------------------------------------------------------ */
check("D1 [DEFECT DEMO] deprecated bootstrap: DEV write ok + local-key write false leaves PARTIAL ACTIVE-KEY update despite failure report", () => {
  const r = runDeprecated({
    preload: { [DEV_ACTIVE]: DEV_OLD, [KEY_ACTIVE]: KEY_OLD },
    writeBehavior: { [KEY_ACTIVE]: "false" },
  });
  assert.equal(r.doneCalls, 1, "exactly one $done");
  // THE DEFECT: the active DEV key was already changed even though the
  // operation as a whole failed and reported failure.
  assert.equal(r.store.get(DEV_ACTIVE), DEV_NEW, "active DEV key changed (partial update)");
  assert.equal(r.store.get(KEY_ACTIVE), KEY_OLD, "active local key unchanged (old value kept)");
  assert.ok(r.notes.some((m) => m.startsWith("bootstrap_failed")), "failure reported to the owner");
  assert.equal(r.store.get(DONE_KEY), undefined, "no done flag on failure");
});

check("D2 [DEFECT DEMO] deprecated bootstrap: both credential writes ok + done-marker write false still emits bootstrap_ok with NO durable done marker", () => {
  const r = runDeprecated({
    writeBehavior: { [DONE_KEY]: "false" },
  });
  assert.equal(r.doneCalls, 1, "exactly one $done");
  // THE DEFECT: the done-marker write return value is ignored, so the
  // script reports success without a durable completion marker.
  assert.ok(r.notes.includes("bootstrap_ok"), "bootstrap_ok reported");
  assert.equal(r.store.get(DONE_KEY), undefined, "done marker NOT durable despite bootstrap_ok");
  assert.equal(r.store.get(DEV_ACTIVE), DEV_NEW, "DEV key written");
  assert.equal(r.store.get(KEY_ACTIVE), KEY_NEW, "local key written");
});

/* ------------------------------------------------------------------ */
/* Section R — P0-B2 regressions for the NEW candidate-staging approach */
/* ------------------------------------------------------------------ */
check("R0 both templates: source contains no token, network calls, or self-delete", () => {
  for (const src of [DEV_SRC, KEY_SRC]) {
    for (const t of ALL_SYNTHETIC) assert.equal(src.includes(t), false, "no synthetic token in source");
    assert.equal(src.includes("$httpClient."), false);
    assert.equal(src.includes("$httpAPI("), false);
    assert.equal(src.includes("self-delete()"), false);
    assert.equal(src.includes("console.log"), false);
    assert.equal(src.includes("$notification"), false);
  }
});

check("R1 (a) independence: DEV staging ok + local-key staging fails, and vice versa — ACTIVE keys are NEVER written during staging", () => {
  // Direction 1: DEV stages, local-key staging fails.
  const store1 = new Map([[DEV_ACTIVE, DEV_OLD], [KEY_ACTIVE, KEY_OLD]]);
  const d1 = runTemplate(DEV_SRC, { parameter: DEV_NEW, store: store1 });
  const k1 = runTemplate(KEY_SRC, {
    parameter: KEY_NEW, store: store1,
    writeBehavior: { [KEY_STAGED]: "false" },
  });
  assert.equal(d1.store.get(DEV_STAGED), DEV_NEW);
  assert.equal(d1.store.get(DEV_STATUS), "candidate_staged");
  assert.equal(k1.store.get(KEY_STATUS), "candidate_commit_unknown");
  assert.equal(k1.perKeyWrites[KEY_STAGED], 1);
  // Direction 2: local-key stages, DEV staging fails.
  const store2 = new Map([[DEV_ACTIVE, DEV_OLD], [KEY_ACTIVE, KEY_OLD]]);
  const k2 = runTemplate(KEY_SRC, { parameter: KEY_NEW, store: store2 });
  const d2 = runTemplate(DEV_SRC, {
    parameter: DEV_NEW, store: store2,
    writeBehavior: { [DEV_STAGED]: "false" },
  });
  assert.equal(k2.store.get(KEY_STAGED), KEY_NEW);
  assert.equal(k2.store.get(KEY_STATUS), "candidate_staged");
  assert.equal(d2.store.get(DEV_STATUS), "candidate_commit_unknown");
  assert.equal(d2.perKeyWrites[DEV_STAGED], 1);
  // In BOTH directions, neither active key was ever written.
  for (const r of [d1, k1, k2, d2]) {
    assert.equal(r.writes.filter((w) => w.key === DEV_ACTIVE).length, 0, "no write to active DEV key");
    assert.equal(r.writes.filter((w) => w.key === KEY_ACTIVE).length, 0, "no write to active local key");
  }
  assert.equal(store1.get(DEV_ACTIVE), DEV_OLD);
  assert.equal(store1.get(KEY_ACTIVE), KEY_OLD);
  assert.equal(store2.get(DEV_ACTIVE), DEV_OLD);
  assert.equal(store2.get(KEY_ACTIVE), KEY_OLD);
});

check("R2 (b) local-key candidate write committed then returns false: recorded unknown, exactly 1 write, no auto-retry", () => {
  const r = runTemplate(KEY_SRC, {
    parameter: KEY_NEW,
    writeBehavior: { [KEY_STAGED]: "writeThenFalse" },
  });
  assert.equal(r.perKeyWrites[KEY_STAGED], 1, "exactly one candidate write, no retry");
  assert.equal(r.store.get(KEY_STAGED), KEY_NEW, "value IS on disk (committed) despite the false return");
  assert.equal(r.store.get(KEY_STATUS), "candidate_commit_unknown", "recorded as unknown, not as success");
  assert.equal(r.done, 1);
});

check("R3 (c) both candidates staged + BOTH status-marker writes false: no candidate rewrite, candidates on disk, statuses NOT misreported as staged", () => {
  const store = new Map([[DEV_ACTIVE, DEV_OLD], [KEY_ACTIVE, KEY_OLD]]);
  const d = runTemplate(DEV_SRC, {
    parameter: DEV_NEW, store,
    writeBehavior: { [DEV_STATUS]: "false" },
  });
  const k = runTemplate(KEY_SRC, {
    parameter: KEY_NEW, store,
    writeBehavior: { [KEY_STATUS]: "false" },
  });
  // No candidate rewrite was triggered by the status-marker failure.
  assert.equal(d.perKeyWrites[DEV_STAGED], 1, "DEV candidate written exactly once");
  assert.equal(k.perKeyWrites[KEY_STAGED], 1, "local-key candidate written exactly once");
  // The candidate write result is what matters: both candidates ARE on
  // disk (the template's own read-back verified them before the status
  // write was attempted).
  assert.equal(store.get(DEV_STAGED), DEV_NEW);
  assert.equal(store.get(KEY_STAGED), KEY_NEW);
  // The status must read as missing/unknown, NOT as success.
  assert.equal(store.get(DEV_STATUS), undefined, "DEV status absent, not 'candidate_staged'");
  assert.equal(store.get(KEY_STATUS), undefined, "local-key status absent, not 'candidate_staged'");
  // Active keys untouched.
  assert.equal(store.get(DEV_ACTIVE), DEV_OLD);
  assert.equal(store.get(KEY_ACTIVE), KEY_OLD);
  assert.equal(d.done, 1);
  assert.equal(k.done, 1);
});

check("R4 (d) preloaded active keys stay unchanged during candidate staging (both DEV and local key)", () => {
  const store = new Map([[DEV_ACTIVE, DEV_OLD], [KEY_ACTIVE, KEY_OLD]]);
  const d = runTemplate(DEV_SRC, { parameter: DEV_NEW, store });
  const k = runTemplate(KEY_SRC, { parameter: KEY_NEW, store });
  assert.equal(d.store.get(DEV_STATUS), "candidate_staged");
  assert.equal(k.store.get(KEY_STATUS), "candidate_staged");
  assert.equal(store.get(DEV_ACTIVE), DEV_OLD, "active DEV key value unchanged");
  assert.equal(store.get(KEY_ACTIVE), KEY_OLD, "active local key value unchanged");
});

check("R5 (e) second invocation after ambiguous commit fails closed and must NOT overwrite a different candidate (DEV)", () => {
  const store = new Map([[DEV_ACTIVE, DEV_OLD]]);
  const first = runTemplate(DEV_SRC, {
    parameter: DEV_NEW, store,
    writeBehavior: { [DEV_STAGED]: "writeThenFalse" },
  });
  assert.equal(first.store.get(DEV_STATUS), "candidate_commit_unknown");
  assert.equal(store.get(DEV_STAGED), DEV_NEW, "first candidate IS on disk despite the false return");
  const second = runTemplate(DEV_SRC, {
    parameter: DEV_OTHER, store,
  });
  assert.equal(second.store.get(DEV_STATUS), "candidate_slot_occupied", "second invocation fails closed");
  assert.equal(second.perKeyWrites[DEV_STAGED] || 0, 0, "no candidate write on the second invocation");
  assert.equal(store.get(DEV_STAGED), DEV_NEW, "original candidate preserved");
  assert.equal(store.get(DEV_ACTIVE), DEV_OLD, "active key untouched");
});

check("R6 (f) no token in logs, source, or status on all paths (both templates)", () => {
  const scenarios = [
    {},
    { trigger: "editor" },
    { trigger: "http-api" },
    { trigger: null },
    { parameter: "short" },
    { parameter: "" },
    { parameter: null },
    { writeBehavior: { [DEV_STAGED]: "false" } },
    { writeBehavior: { [DEV_STAGED]: "writeThenFalse" } },
    { readBehavior: { [DEV_STAGED]: "corrupt" } },
    { readBehavior: { [DEV_STAGED]: "throw" } },
  ];
  for (const o of scenarios) {
    const d = runTemplate(DEV_SRC, { parameter: DEV_NEW, ...o });
    const k = runTemplate(KEY_SRC, { parameter: KEY_NEW, ...o });
    for (const r of [d, k]) {
      assert.equal(r.done, 1, "exactly one $done");
      assert.equal(r.network, 0, "zero network calls");
      assert.ok(noSyntheticLeak(r.logs.join(" ")), "no token in logs");
      assert.ok(noSyntheticLeak(JSON.stringify(r.writes)), "no token in write records (valueKind only)");
      assert.ok(noSyntheticLeak(String(r.store.get(DEV_STATUS) || "")), "no token in DEV status");
      assert.ok(noSyntheticLeak(String(r.store.get(KEY_STATUS) || "")), "no token in local-key status");
    }
  }
  for (const src of [DEV_SRC, KEY_SRC]) {
    assert.ok(noSyntheticLeak(src), "no synthetic token in either template source");
  }
});

/* ------------------------------------------------------------------ */
/* Section L — dedicated tests for the local-key candidate template   */
/* ------------------------------------------------------------------ */
check("L1 valid local-key candidate stages without modifying the active local key", () => {
  const r = runTemplate(KEY_SRC, {
    parameter: KEY_NEW,
    preload: { [KEY_ACTIVE]: KEY_OLD },
  });
  assert.equal(r.store.get(KEY_STAGED), KEY_NEW);
  assert.equal(r.store.get(KEY_ACTIVE), KEY_OLD, "active local key untouched");
  assert.equal(r.store.get(KEY_STATUS), "candidate_staged");
  assert.equal(r.done, 1);
});

check("L2 local-key candidate occupied / idempotent", () => {
  const occ = runTemplate(KEY_SRC, {
    parameter: KEY_NEW,
    preload: { [KEY_STAGED]: KEY_OTHER, [KEY_ACTIVE]: KEY_OLD },
  });
  assert.equal(occ.perKeyWrites[KEY_STAGED] || 0, 0, "no write when slot occupied");
  assert.equal(occ.store.get(KEY_STAGED), KEY_OTHER, "other candidate preserved");
  assert.equal(occ.store.get(KEY_STATUS), "candidate_slot_occupied");
  assert.equal(occ.store.get(KEY_ACTIVE), KEY_OLD);
  const idem = runTemplate(KEY_SRC, {
    parameter: KEY_NEW,
    preload: { [KEY_STAGED]: KEY_NEW, [KEY_ACTIVE]: KEY_OLD },
  });
  assert.equal(idem.perKeyWrites[KEY_STAGED] || 0, 0, "no re-write for the same candidate");
  assert.equal(idem.store.get(KEY_STATUS), "candidate_already_staged");
  assert.equal(idem.store.get(KEY_ACTIVE), KEY_OLD);
});

check("L3 local-key status-marker write false: candidate on disk, status absent, no rewrite", () => {
  const r = runTemplate(KEY_SRC, {
    parameter: KEY_NEW,
    writeBehavior: { [KEY_STATUS]: "false" },
  });
  assert.equal(r.perKeyWrites[KEY_STAGED], 1, "candidate written exactly once");
  assert.equal(r.store.get(KEY_STAGED), KEY_NEW, "candidate on disk");
  assert.equal(r.store.get(KEY_STATUS), undefined, "status absent, not misreported as staged");
  assert.equal(r.done, 1);
});

check("L4 local-key write returns false WITHOUT persisting: unknown, exactly 1 write, nothing on disk, no retry", () => {
  const r = runTemplate(KEY_SRC, {
    parameter: KEY_NEW,
    writeBehavior: { [KEY_STAGED]: "false" },
  });
  assert.equal(r.perKeyWrites[KEY_STAGED], 1, "exactly one candidate write, no retry");
  assert.equal(r.store.get(KEY_STAGED), undefined, "nothing on disk");
  assert.equal(r.store.get(KEY_STATUS), "candidate_commit_unknown");
  assert.equal(r.done, 1);
});

check("L5 local-key ambiguous commit then different candidate: occupied, original preserved (local-key variant of R5)", () => {
  const store = new Map([[KEY_ACTIVE, KEY_OLD]]);
  const first = runTemplate(KEY_SRC, {
    parameter: KEY_NEW, store,
    writeBehavior: { [KEY_STAGED]: "writeThenFalse" },
  });
  assert.equal(first.store.get(KEY_STATUS), "candidate_commit_unknown");
  assert.equal(store.get(KEY_STAGED), KEY_NEW, "first candidate IS on disk despite the false return");
  const second = runTemplate(KEY_SRC, {
    parameter: KEY_OTHER, store,
  });
  assert.equal(second.store.get(KEY_STATUS), "candidate_slot_occupied", "second invocation fails closed");
  assert.equal(second.perKeyWrites[KEY_STAGED] || 0, 0, "no candidate write on the second invocation");
  assert.equal(store.get(KEY_STAGED), KEY_NEW, "original candidate preserved");
  assert.equal(store.get(KEY_ACTIVE), KEY_OLD, "active key untouched");
});

console.log("SUMMARY", pass, "PASS", fail, "FAIL");
if (fail > 0) {
  console.log("FAILURES:", failures.join(" | "));
  process.exitCode = 1;
}
