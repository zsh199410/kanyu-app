// C3-B simulator: isolated Surge environment + mock mailbox for bridge.js.
// All data is synthetic (TEST-NET ids, fake paths). No real tokens, URLs,
// nodes, or command bodies are ever logged or stored here.
// The script under test is loaded from a file path (original private copy or
// the desensitized fixed version) and evaluated in a fresh vm context per run.
"use strict";

const vm = require("vm");
const fs = require("fs");

// ---------------------------------------------------------------------------
// Mock mailbox: emulates mailbox_ack.py semantics (accept_result /
// accept_diagnostic / issue_if_empty / receipt_status) in-process.
// ---------------------------------------------------------------------------
class MockMailbox {
  constructor() {
    this.cmd = null;        // pending command {id, actions} or null
    this.result = null;     // stored result: the exact posted object
    this.diagnostic = null; // last diagnostic record
    this.resultPostCount = 0;
    this.pollCount = 0;
    this.dropAckNext = false;    // store + clear cmd, but drop the HTTP response
    this.persistFailNext = false; // 503 without storing
  }
  setCmd(cmd) { this.cmd = cmd ? { id: cmd.id, actions: cmd.actions } : null; }
  poll() {
    this.pollCount++;
    if (this.cmd) return { status: 200, data: JSON.stringify({ id: this.cmd.id, actions: this.cmd.actions }) };
    return { status: 200, data: JSON.stringify({ id: 0 }) };
  }
  acceptResult(posted) {
    this.resultPostCount++;
    if (this.persistFailNext) {
      this.persistFailNext = false;
      return { status: 503, body: { ok: false, accepted: false, error: "durable_commit_failed", commit_state: "unknown" } };
    }
    if (!posted || typeof posted !== "object" ||
        !Number.isSafeInteger(posted.id) || !Array.isArray(posted.outputs)) {
      return { status: 400, body: { ok: false, accepted: false, error: "bad_result" } };
    }
    if (this.cmd && posted.id === this.cmd.id) {
      this.result = JSON.parse(JSON.stringify(posted)); // store exact payload
      this.cmd = null;
      if (this.dropAckNext) {
        this.dropAckNext = false;
        return { drop: true }; // stored + cleared, response never arrives
      }
      return { status: 200, body: { ok: true, accepted: true, acked_id: posted.id } };
    }
    if (!this.cmd && this.result &&
        JSON.stringify(posted) === JSON.stringify(this.result)) {
      return { status: 200, body: { ok: true, accepted: true, acked_id: posted.id, duplicate: true } };
    }
    return { status: 409, body: { ok: false, accepted: false, error: "pending_id_or_result_mismatch" } };
  }
  acceptDiagnostic(posted) {
    this.diagnostic = JSON.parse(JSON.stringify(posted));
    return { status: 200, body: { ok: true, diagnostic_stored: true } };
  }
}

// ---------------------------------------------------------------------------
// Mock Surge environment. One fresh instance per test run (no leakage).
// cfg:
//   pollOverride: {body, status, err} | null   (override the /poll response)
//   httpGet / httpPost: 'server' | 'never' | 'err' | 'empty' | 'object' | 'throw'
//   httpApi: 'undefined' | 'ok' | 'never' | 'throw' | 'empty'
//   localApi: 'ok' | 'never' | 'err' | 'throw'   (http://127.0.0.1:6171/...)
//   localApiDelayMs: number (real ms before the local API callback fires)
//   httpDelayMs: number (real ms delay before ANY $httpClient callback fires;
//     used to simulate a LATE callback arriving after the script already
//     moved on / called $done)
//   httpApiDelayMs: number (real ms delay before the $httpAPI callback fires)
//   storeReadThrows / storeWriteThrows: bool
//   ledgerWriteFailAfter / ledgerWriteFalseAfter: number (fail only ledger
//     writes after N successful ones; "Fail" throws, "False" returns false)
//   timers: 'fire' | 'throttled'   (mock setTimeout behaviour)
//   timerScale: number (scale factor for mock setTimeout; 0.01 = 100x faster)
//   initialStore: {key: value}     (pre-seeded $persistentStore; ignored if
//     sharedStore is given)
//   sharedStore: Map (reuse a live $persistentStore across runs)
//   sharedMailbox: MockMailbox (reuse a live mailbox across runs)
//   mailboxCmd: {id, actions} | null
//   dropAckNext / persistFailNext: bool (passed to the mailbox)
//   resultOverride: {status, body} (force the /result response)
// ---------------------------------------------------------------------------
function createEnv(cfg) {
  cfg = cfg || {};
  const mailbox = cfg.sharedMailbox || new MockMailbox();
  if (cfg.mailboxCmd) mailbox.setCmd(cfg.mailboxCmd);
  if (cfg.dropAckNext) mailbox.dropAckNext = true;
  if (cfg.persistFailNext) mailbox.persistFailNext = true;

  const store = cfg.sharedStore || new Map(Object.entries(cfg.initialStore || {}));
  // Existing v2 suites use a fully provisioned synthetic phone by default.
  // Explicit injectCredentials:false is reserved for real missing-credential
  // tests, so no test uses a production token or distribution path.
  if (cfg.injectCredentials !== false) {
    if (!store.has("sgbridge_cred_dev")) store.set("sgbridge_cred_dev", "TEST-DEV-MOCK-ONLY");
    if (!store.has("sgbridge_cred_localkey")) store.set("sgbridge_cred_localkey", "TEST-LOCAL-MOCK-ONLY");
  }
  let ledgerWrites = 0; // counts successful writes to the ledger key (see below)
  const outcome = {
    doneCalls: 0,
    donePayloads: [],
    httpCalls: [],      // {method, path} — path only, never headers/bodies
    httpApiCalls: [],   // {method, path}
    dispatches: 0,      // $httpAPI + local-HTTP action attempts
    storeWrites: [],    // {key, valueKind}
    storeReads: [],
    notifications: 0,
    postDoneAttempts: [], // operations attempted after $done (Surge would have terminated)
    droppedLateCallbacks: 0, // callbacks dropped because the script already terminated
    hung: false,
    phases: [],         // phases recorded by the FIXED script (via $persistentStore phase key)
    terminated: false,
  };

  const timerScale = (cfg.timerScale === undefined) ? 0.01 : cfg.timerScale;
  const timers = new Map(); // id -> real timer handle (fire mode)
  let nextTimerId = 1;
  const realSetTimeout = setTimeout;
  const realClearTimeout = clearTimeout;

  function mockSetTimeout(fn, ms) {
    const id = nextTimerId++;
    if (cfg.timers === "throttled") {
      timers.set(id, null); // registered, never fires
      return id;
    }
    const handle = realSetTimeout(() => {
      timers.delete(id);
      try { fn(); } catch (_e) {}
    }, Math.max(0, Math.round((ms || 0) * timerScale)));
    timers.set(id, handle);
    return id;
  }
  function mockClearTimeout(id) {
    if (!timers.has(id)) return;
    const handle = timers.get(id);
    timers.delete(id);
    if (handle) realClearTimeout(handle);
  }
  function teardownTimers() {
    for (const [, handle] of timers) if (handle) realClearTimeout(handle);
    timers.clear();
  }

  function pathOf(url) {
    try {
      const u = new URL(url);
      return u.pathname;
    } catch (_e) {
      return String(url).split("?")[0].replace(/^https?:\/\/[^/]+/, "");
    }
  }

  // $httpClient.get/post: (opts, cb). cb(err, resp, data).
  function httpClientCall(method, opts, cb) {
    if (outcome.terminated) { outcome.postDoneAttempts.push(method + " " + pathOf(opts.url)); return; }
    const path = pathOf(opts.url);
    outcome.httpCalls.push({ method, path });
    const behaviour = (method === "GET") ? (cfg.httpGet || "server") : (cfg.httpPost || "server");
    const fire = (err, status, data) => {
      // A callback arriving after the script already called $done is dropped:
      // in real Surge the script context is torn down at $done, so a late
      // callback has nowhere to go and must cause no side effect.
      const deliver = () => {
        if (outcome.terminated) { outcome.droppedLateCallbacks++; return; }
        try { cb(err || null, err ? null : { status }, data === undefined ? "" : data); } catch (_e) {}
      };
      const delay = cfg.httpDelayMs || 0;
      if (delay > 0) realSetTimeout(deliver, delay);
      else deliver();
    };
    if (behaviour === "never") return; // callback never fires -> hang
    if (behaviour === "throw") throw new Error("mock httpClient throw");
    if (behaviour === "err") { fire("mock network error", 0, ""); return; }
    if (behaviour === "empty") { fire(null, 200, ""); return; }
    if (behaviour === "object") { fire(null, 200, { unexpected: "object-body" }); return; }
    // 'server': route to the mock mailbox / local API by path.
    if (path === "/poll") {
      if (cfg.pollOverride) {
        const o = cfg.pollOverride;
        fire(o.err || null, o.status || 200, o.body === undefined ? "" : o.body);
        return;
      }
      const r = mailbox.poll();
      fire(null, r.status, r.data);
      return;
    }
    if (path === "/result") {
      let posted = null;
      try { posted = JSON.parse(opts.body); } catch (_e) { posted = null; }
      if (cfg.resultOverride) {
        const o = cfg.resultOverride;
        fire(null, o.status || 200, JSON.stringify(o.body || {}));
        return;
      }
      const res = mailbox.acceptResult(posted);
      if (res.drop) return; // stored, but the response never arrives (lost ACK)
      fire(null, res.status, JSON.stringify(res.body));
      return;
    }
    if (path === "/diagnostic") {
      let posted = null;
      try { posted = JSON.parse(opts.body); } catch (_e) { posted = null; }
      const res = mailbox.acceptDiagnostic(posted);
      fire(null, res.status, JSON.stringify(res.body));
      return;
    }
    if (opts.url.indexOf("127.0.0.1:6171") !== -1) {
      // Local Surge API (mock $httpAPI fallback path).
      outcome.dispatches++;
      const lb = cfg.localApi || "ok";
      if (lb === "never") return;
      if (lb === "throw") throw new Error("mock local api throw");
      if (lb === "err") { fire("mock local error", 0, ""); return; }
      const delay = cfg.localApiDelayMs || 0;
      if (delay > 0) realSetTimeout(() => fire(null, 200, JSON.stringify({ ok: true, via: "local-mock" })), delay);
      else fire(null, 200, JSON.stringify({ ok: true, via: "local-mock" }));
      return;
    }
    fire(null, 404, "");
  }

  // $httpAPI: (method, path, body, cb). cb(data).
  function httpApiCall(method, path, body, cb) {
    if (outcome.terminated) { outcome.postDoneAttempts.push("httpAPI " + method + " " + path); return; }
    outcome.httpApiCalls.push({ method, path });
    outcome.dispatches++;
    const mode = cfg.httpApi || "ok";
    if (mode === "never") return; // callback never fires
    if (mode === "throw") throw new Error("mock httpAPI throw");
    const deliver = (data) => {
      if (outcome.terminated) { outcome.droppedLateCallbacks++; return; }
      try { cb(data); } catch (_e) {}
    };
    const delay = cfg.httpApiDelayMs || 0;
    if (mode === "empty") {
      if (delay > 0) realSetTimeout(() => deliver(null), delay);
      else deliver(null);
      return;
    }
    // 'ok'
    if (delay > 0) realSetTimeout(() => deliver({ ok: true, via: "httpAPI-mock" }), delay);
    else deliver({ ok: true, via: "httpAPI-mock" });
  }

  const sandbox = {
    console: { log: () => {}, error: () => {} },
    // NOTE: standard JS intrinsics (parseInt, JSON, Promise, ...) come from
    // the vm context itself; do NOT inject host intrinsics (cross-realm mix).
    setTimeout: mockSetTimeout,
    clearTimeout: mockClearTimeout,
    $httpClient: {
      get: (opts, cb) => httpClientCall("GET", opts, cb),
      post: (opts, cb) => httpClientCall("POST", opts, cb),
    },
    $persistentStore: {
      read: (key) => {
        if (outcome.terminated) { outcome.postDoneAttempts.push("store.read " + key); return null; }
        outcome.storeReads.push(key);
        // Separate credential bootstrap failure from later state-read
        // failure. This preserves the original legacy-last_id fault test
        // while making early credential-read failure independently testable.
        const isCredentialKey = key === "sgbridge_cred_dev" || key === "sgbridge_cred_localkey";
        if (cfg.credentialReadThrows && isCredentialKey) throw new Error("mock credential read throw");
        if (cfg.storeReadThrows && !isCredentialKey) throw new Error("mock state read throw");
        const v = store.get(key);
        return (v === undefined) ? null : v;
      },
      write: (value, key) => {
        if (outcome.terminated) { outcome.postDoneAttempts.push("store.write " + key); return; }
        if (cfg.storeWriteThrows) throw new Error("mock store write throw");
        // ledgerWriteFailAfter / ledgerWriteFalseAfter: fail ONLY writes to
        // the ledger key after N successful ledger writes (bootstrap=1,
        // claim=2, checkpoint=3, ack-clear=4). Fault-injects a single stage
        // without breaking every store write. "Fail" throws; "False"
        // returns false (the PR #99 case: $persistentStore.write returning
        // false is not an exception, yet must block the checkpoint).
        // Real Surge returns true on a successful write.
        if (key === "sgbridge_ledger_v1" &&
            (typeof cfg.ledgerWriteFailAfter === "number" ||
             typeof cfg.ledgerWriteFalseAfter === "number")) {
          ledgerWrites++;
          if (typeof cfg.ledgerWriteFailAfter === "number" &&
              ledgerWrites > cfg.ledgerWriteFailAfter) {
            throw new Error("mock ledger write fails after " + cfg.ledgerWriteFailAfter);
          }
          if (typeof cfg.ledgerWriteFalseAfter === "number" &&
              ledgerWrites > cfg.ledgerWriteFalseAfter) {
            return false;
          }
        }
        store.set(key, String(value));
        outcome.storeWrites.push({ key, valueKind: typeof value });
        if (key === "sgbridge_phase_v1") {
          try { outcome.phases = JSON.parse(value); } catch (_e) {}
        }
        return true; // Surge $persistentStore.write returns true on success.
      },
    },
    $notification: {
      post: () => { outcome.notifications++; },
    },
    $done: (payload) => {
      outcome.doneCalls++;
      outcome.donePayloads.push(payload === undefined ? null : payload);
      outcome.terminated = true; // Surge tears the script down after $done
    },
  };
  // $httpAPI is only present when the config says so (undefined = not a function).
  if (cfg.httpApi !== "undefined") sandbox.$httpAPI = httpApiCall;

  return { sandbox, mailbox, store, outcome, teardownTimers, mockSetTimeout };
}

// ---------------------------------------------------------------------------
// Run one script source in a fresh mock env.
// Returns outcome: {doneCalls, hung, httpCalls, httpApiCalls, dispatches,
//   storeWrites, storeReads, notifications, postDoneAttempts, phases,
//   mailbox: {cmd, result, resultPostCount, pollCount}, storeSnapshot, error}
// opts.watchdogMs: real ms to wait for $done before declaring a hang.
// opts.settleMs: real ms to keep observing AFTER $done is first called, so
//   late callbacks arriving after terminal can be recorded (dropped).
// opts.shared: {store, mailbox} (live objects to reuse across runs).
// ---------------------------------------------------------------------------
async function runScript(source, cfg, opts) {
  opts = opts || {};
  const watchdogMs = opts.watchdogMs || 3000;
  const settleMs = opts.settleMs || 0;
  const runCfg = Object.assign({}, cfg);
  if (opts.shared) {
    runCfg.sharedStore = opts.shared.store;
    runCfg.sharedMailbox = opts.shared.mailbox;
  }
  const env = createEnv(runCfg);
  const ctx = vm.createContext(env.sandbox);
  let runError = null;
  let settled = false;
  let scriptPromise = null;
  try {
    scriptPromise = vm.runInContext(source, ctx, { filename: "bridge-under-test.js" });
    if (scriptPromise && typeof scriptPromise.catch === "function") {
      scriptPromise.catch((e) => { if (!settled) runError = e; });
    }
  } catch (e) {
    runError = e;
  }
  const outcome = env.outcome;
  // Wait for $done or the watchdog, then observe for settleMs more.
  await new Promise((resolve) => {
    const start = Date.now();
    let doneAt = 0;
    const tick = () => {
      if (doneAt === 0 && (outcome.doneCalls > 0 || runError)) doneAt = Date.now();
      if (doneAt !== 0 && Date.now() - doneAt >= settleMs) { settled = true; resolve(); return; }
      if (doneAt === 0 && Date.now() - start >= watchdogMs) { outcome.hung = true; settled = true; resolve(); return; }
      setTimeout(tick, 25);
    };
    tick();
  });
  env.teardownTimers();
  // Snapshot the store (desensitized: keys + value kinds / small scalars only).
  const storeSnapshot = {};
  for (const [k, v] of env.store.entries()) {
    if (k === "sgbridge_last_id") storeSnapshot[k] = v;
    else if (k === "sgbridge_ledger_v1") {
      try {
        const s = JSON.parse(v);
        storeSnapshot[k] = { version: s.version, floor: s.floor, last_acked_id: s.last_acked_id,
          pending: s.pending ? { id: s.pending.id, phase: s.pending.phase, hasResult: !!s.pending.result } : null };
      } catch (_e) { storeSnapshot[k] = "<unparsable>"; }
    } else if (k === "sgbridge_phase_v1") storeSnapshot[k] = "<phase-log:" + outcome.phases.length + " entries>";
    else storeSnapshot[k] = "<" + typeof v + ":" + String(v).length + " chars>";
  }
  return {
    doneCalls: outcome.doneCalls,
    hung: outcome.hung,
    runError: runError ? String(runError) : null,
    httpCalls: outcome.httpCalls,
    httpApiCalls: outcome.httpApiCalls,
    dispatches: outcome.dispatches,
    storeWrites: outcome.storeWrites,
    storeReads: outcome.storeReads,
    notifications: outcome.notifications,
    postDoneAttempts: outcome.postDoneAttempts,
    droppedLateCallbacks: outcome.droppedLateCallbacks,
    phases: outcome.phases,
    mailboxCmd: env.mailbox.cmd,
    mailboxResult: env.mailbox.result,
    mailboxResultPostCount: env.mailbox.resultPostCount,
    mailboxPollCount: env.mailbox.pollCount,
    storeSnapshot,
    _shared: { store: env.store, mailbox: env.mailbox },
  };
}

// Run the script N times sharing ONE live $persistentStore and ONE live
// mailbox (like the phone's store + the server mailbox across cron rounds).
// steps: [{cfg, opts}]. seed: {store: {k:v}, mailboxCmd: {...}} pre-loaded
// into the shared state before step 1. Returns {runs, shared}.
// NOTE: runSeries seeds the shared state from `seed`; a step's initialStore
// is ignored once a shared store exists (the store already has state).
async function runSeries(source, steps, seed) {
  const shared = { store: new Map(Object.entries((seed && seed.store) || {})), mailbox: new MockMailbox() };
  if (seed && seed.mailboxCmd) shared.mailbox.setCmd(seed.mailboxCmd);
  const runs = [];
  for (const step of steps) {
    const out = await runScript(source, step.cfg || {}, Object.assign({}, step.opts || {}, { shared }));
    runs.push(out);
  }
  return { runs, shared };
}

// Scale the fixed script's production timeout constants down for fast tests.
// The delivered bridge_fixed.js keeps production values; only the in-memory
// copy used by the test run is scaled.
function scaleTimeouts(source, scale) {
  return source
    .replace(/POLL_TIMEOUT_MS = \d+/, "POLL_TIMEOUT_MS = " + Math.max(50, Math.round(35000 * scale)))
    .replace(/RESULT_TIMEOUT_MS = \d+/, "RESULT_TIMEOUT_MS = " + Math.max(50, Math.round(35000 * scale)))
    .replace(/HTTPAPI_TIMEOUT_MS = \d+/, "HTTPAPI_TIMEOUT_MS = " + Math.max(50, Math.round(15000 * scale)))
    .replace(/WATCHDOG_MS = \d+/, "WATCHDOG_MS = " + Math.max(200, Math.round(100000 * scale)));
}

module.exports = { MockMailbox, createEnv, runScript, runSeries, scaleTimeouts };
