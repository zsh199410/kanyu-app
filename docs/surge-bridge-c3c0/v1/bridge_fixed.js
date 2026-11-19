// v1 CONTROL (C3-B): the v1 fixed bridge used ONLY as the control in
// test_fixed_v2.js V8 (demonstrates the toSec() same-second floor bug).
// Desensitised copy: BASE / DEV / APIKEY are placeholders, as in the
// original. Never deployed, never executed on the phone. Included here so
// the PR #97 package re-runs independently (no ../pr96-c3b dependency).
// Surge Bridge agent (FIXED, C3-B): polls a mailbox, executes commands via the
// local Surge API, posts results back.
//
// DESENSITISED COPY: BASE / DEV / APIKEY below are placeholders. The production
// file keeps its real values; this file never contains them.
// Wire format UNCHANGED: GET /poll, POST /result, local $httpAPI / direct HTTP.
// No change to the poll/dispatch/result request shapes.
//
// Fixes vs the original (PR#85) bridge.js:
//  (R0) DEDUP UNIT NORMALISATION (primary root cause, found by C3-B T27/T28).
//       The legacy last_id can be a MILLISECOND timestamp (13 digits, from an
//       MCP-issued command) while command ids are SECOND timestamps (10 digits).
//       A plain numeric `cmd.id <= last` then blocks every newer second-based
//       command forever. All ordering comparisons now go through toSec().
//  (a)  Promise-level timeout guard (withTimeout) on EVERY await. NOTE: this
//       is a best-effort guard, NOT a hard deadline guarantee — it relies on
//       the host setTimeout firing. If background timers are frozen, no
//       JS-level guard can release the await; that case is
//       RUNTIME_HARD_TIMEOUT_UNPROVEN and must be confirmed from real device
//       script logs. The Surge host cron timeout (120s) remains the outer bound.
//  (b)  Phase observability. Every catch emits a phase; there is no silent
//       catch(_){}. Phase records carry ONLY {phase, desensitised id,
//       exception category, 10s time bucket} — never a body, token, or URI.
//  (c)  Permanent fence for the inherited old command id (PR#96 ledger floor
//       + an exact-id constant). It short-circuits BEFORE any $httpAPI/HTTP
//       action, BEFORE any last_id write, and BEFORE any POST /result, and
//       does not depend on the ledger having been initialised.
//  (d)  Single-$done guarantee (doneOnce + a 100s watchdog under the 120s
//       cron limit). On any path where the script completes, $done is called
//       exactly once; a late callback after $done is dropped, not re-run.
//  (e)  PR#96 result_ready: the result is persisted BEFORE POSTing, and
//       last_id is written ONLY after a strict ACK (200 + accepted:true +
//       acked_id === cmd.id). A lost ACK re-sends the CACHED result; the
//       action is never re-executed.
//  PR#85 outcome_unknown_no_retry is preserved: a timed-out/ambiguous
//  MUTATING call is never blindly retried via a second HTTP mutation.
const BASE = "https://<BRIDGE_BASE>";
const DEV = "<DEV_TOKEN>";
const APIKEY = "<API_KEY>";
const STORE = "sgbridge_last_id";
const LEDGER_KEY = "sgbridge_ledger_v1";
const PHASE_KEY = "sgbridge_phase_v1";
const FENCED_OLD_ID = 1795063030; // inherited pending command; observe only, never execute.

// Production timeouts (the C3-B simulator scales these down for fast tests).
const POLL_TIMEOUT_MS = 35000;
const RESULT_TIMEOUT_MS = 35000;
const HTTPAPI_TIMEOUT_MS = 15000; // backstop behind httpAPI's own 10s guard
const WATCHDOG_MS = 100000; // under the 120s cron limit

// --- phase observability: {phase, id, cat, tb} only ---
// id is a desensitised command id (0 when none). cat is an exception
// category ("none" on the happy path). tb is a 10-second time bucket.
// Never a body, token, proxy node, or URI.
const phases = [];
function phase(name, id, cat) {
  const entry = {
    phase: name,
    id: (typeof id === "number" && Number.isSafeInteger(id)) ? id : 0,
    cat: cat || "none",
    tb: Math.floor(Date.now() / 10000),
  };
  phases.push(entry);
  if (phases.length > 30) phases.shift();
  try {
    $persistentStore.write(JSON.stringify(phases), PHASE_KEY);
  } catch (_e) {
    // Best-effort persist failed. Record it IN MEMORY (direct push, not a
    // recursive phase() call) so the failure is not silently swallowed; the
    // next phase() call retries persisting the whole log.
    phases.push({ phase: "phase_persist_failed", id: 0, cat: "store", tb: Math.floor(Date.now() / 10000) });
    if (phases.length > 30) phases.shift();
  }
  return entry;
}
function phaseErr(name, id, cat) { return phase(name, id, cat || "error"); }

// --- single-$done guarantee ---
let doneCalled = false;
function doneOnce(payload) {
  if (doneCalled) return;
  doneCalled = true;
  try { $done(payload || {}); } catch (_e) { phaseErr("done_failed", 0, "done"); }
}

// --- timestamp normalisation (R0) ---
// Ordering comparisons must not mix millisecond and second timestamps.
// Any id above 1e12 is treated as milliseconds and converted to seconds.
function toSec(id) {
  if (typeof id !== "number" || !Number.isSafeInteger(id)) return 0;
  return id > 1000000000000 ? Math.floor(id / 1000) : id;
}

// --- Promise-level timeout guard ---
// Best-effort only (see header note (a)): if the host setTimeout never
// fires, this race never resolves either. It protects against a dead
// $httpClient/$httpAPI CALLBACK while timers are alive.
function withTimeout(promise, ms, label) {
  let timer;
  const timeout = new Promise((resolve) => {
    timer = setTimeout(() => resolve({ __timeout: true, __label: label }), ms);
  });
  return Promise.race([
    promise.then(
      (v) => { clearTimeout(timer); return v; },
      (e) => { clearTimeout(timer); throw e; }),
    timeout,
  ]);
}

function http(method, url, headers, body) {
  return new Promise((resolve) => {
    const opts = { url: url, headers: headers || {}, timeout: 30 };
    if (body !== undefined) opts.body = typeof body === "string" ? body : JSON.stringify(body);
    const cb = (err, resp, data) => resolve({ err: err ? String(err) : null, status: resp ? resp.status : 0, data: data || "" });
    if (method === "GET") $httpClient.get(opts, cb); else $httpClient.post(opts, cb);
  });
}

function httpAPI(method, path, body) {
  return new Promise((resolve) => {
    if (typeof $httpAPI !== "function") {
      resolve({ kind: "unavailable" });
      return;
    }
    let done = false;
    let timeoutId;
    const finish = (result) => {
      if (done) return;
      done = true;
      if (timeoutId !== undefined) clearTimeout(timeoutId);
      resolve(result);
    };
    timeoutId = setTimeout(() => finish({ kind: "unknown", reason: "timeout" }), 10000);
    try {
      $httpAPI(method, path.replace(/^\//, ""), body || {}, (data) => {
        if (data === undefined || data === null) {
          finish({ kind: "unknown", reason: "empty_callback" });
        } else {
          finish({ kind: "ok", data: data });
        }
      });
    } catch (_e) {
      // A throw does NOT prove the action was never dispatched.
      phaseErr("httpapi_dispatch_error", 0, "dispatch");
      finish({ kind: "unknown", reason: "dispatch_error" });
    }
  });
}

async function api(method, path, body) {
  const verb = String(method).toUpperCase();
  const viaApi = await withTimeout(httpAPI(verb, path, body), HTTPAPI_TIMEOUT_MS, "httpapi");
  if (viaApi && viaApi.__timeout) {
    return { via: "httpAPI", status: 0, err: "httpapi_guard_timeout", pending: true,
             data: { state: "unknown", reason: "guard_timeout" } };
  }
  if (viaApi.kind === "ok") {
    return { via: "httpAPI", data: viaApi.data };
  }
  // A timed-out or ambiguous mutating call may already have been accepted.
  // Never blindly fall back to a second HTTP mutation. (PR#85)
  if (viaApi.kind === "unknown" && !["GET", "HEAD", "OPTIONS"].includes(verb)) {
    return {
      via: "httpAPI", status: 0, err: "outcome_unknown_no_retry",
      pending: true, data: { state: "unknown", reason: viaApi.reason }
    };
  }
  // Original bridge http() only distinguishes GET from POST; every other
  // verb would silently become a POST. Never mutate with the wrong verb.
  if (!["GET", "POST"].includes(verb)) {
    return {
      via: "httpAPI", status: 0, err: "unsupported_http_fallback",
      pending: viaApi.kind === "unknown",
      data: { state: "blocked", reason: "fallback_method_unsupported" }
    };
  }
  // If $httpAPI was truly unavailable, direct HTTP is the one and only
  // attempt. For a read-only GET, retry after ambiguous transport is safe.
  const r = await withTimeout(
    http(verb, "http://127.0.0.1:6171" + path,
      { "X-Key": APIKEY, "Content-Type": "application/json" }, body),
    RESULT_TIMEOUT_MS, "localhttp");
  if (r && r.__timeout) {
    return { via: "http", status: 0, err: "local_http_guard_timeout", pending: true,
             data: { state: "unknown", reason: "guard_timeout" } };
  }
  let data = r.data;
  try { data = JSON.parse(r.data); } catch (_e) { phaseErr("local_parse", 0, "parse"); }
  return { via: "http", status: r.status, err: r.err, data: data };
}

// --- PR#96 durable ledger (fence floor + result_ready) ---
function loadLedger() {
  let raw = null;
  try { raw = $persistentStore.read(LEDGER_KEY); } catch (_e) { phaseErr("ledger_read", 0, "store"); return null; }
  if (!raw) return null;
  try {
    const s = JSON.parse(raw);
    if (!s || s.version !== 1 || !Number.isSafeInteger(s.floor) ||
        !Number.isSafeInteger(s.last_acked_id) || !("pending" in s)) {
      phaseErr("ledger_corrupt", 0, "ledger");
      return null;
    }
    return s;
  } catch (_e) { phaseErr("ledger_parse", 0, "parse"); return null; }
}
function saveLedger(state) {
  $persistentStore.write(JSON.stringify(state), LEDGER_KEY);
}

// POST /result and check the STRICT ACK (PR#96): 200 + accepted:true +
// acked_id === result.id. Anything else is NOT an acknowledgement.
async function sendResult(result) {
  const r = await withTimeout(
    http("POST", BASE + "/result", { "X-Dev-Token": DEV, "Content-Type": "application/json" }, result),
    RESULT_TIMEOUT_MS, "result");
  if (!r || r.__timeout) return { acked: false, reason: "timeout", status: 0 };
  let body = null;
  try { body = JSON.parse(r.data); } catch (_e) { phaseErr("result_parse", result.id, "parse"); }
  if (r.status === 200 && body && body.accepted === true && body.acked_id === result.id) {
    return { acked: true, duplicate: body.duplicate === true, status: 200 };
  }
  return { acked: false, reason: "not_acked", status: r.status || 0 };
}

(async () => {
  const watchdog = setTimeout(() => {
    phaseErr("watchdog", 0, "watchdog");
    doneOnce({});
  }, WATCHDOG_MS);
  try {
    phase("cron_enter", 0, "none");
    // --- legacy last_id (normalised to seconds for ordering, R0) ---
    let last = 0;
    try { last = parseInt($persistentStore.read(STORE) || "0", 10) || 0; }
    catch (_e) { phaseErr("store_read", 0, "store"); doneOnce({}); return; }
    const lastSec = toSec(last);
    // --- ledger: bootstrap the fence floor on first run (PR#96) ---
    let ledger = loadLedger();
    if (!ledger) {
      ledger = { version: 1, floor: FENCED_OLD_ID, last_acked_id: 0, pending: null };
      try { saveLedger(ledger); phase("ledger_bootstrap", FENCED_OLD_ID, "fence"); }
      catch (_e) { phaseErr("ledger_bootstrap_failed", FENCED_OLD_ID, "store"); }
      // The exact-id constant below still fences the old command even if
      // this bootstrap write failed, so the fence never depends on it.
    }
    // --- poll (guarded) ---
    const r = await withTimeout(http("GET", BASE + "/poll", { "X-Dev-Token": DEV }), POLL_TIMEOUT_MS, "poll");
    phase("poll_http_done", 0, "none");
    let cmd = null;
    if (r && r.__timeout) {
      phaseErr("poll_timeout", 0, "timeout");
      // Poll timed out: still try to re-send an unacked cached result below.
    } else {
      try { cmd = JSON.parse(r.data); } catch (_e) { phaseErr("poll_parse", 0, "parse"); }
    }
    phase("cmd_parsed", cmd && cmd.id ? cmd.id : 0, "none");
    // --- PERMANENT FENCE (c): exact-id short-circuit, before ANY action,
    // BEFORE any last_id write, BEFORE any POST /result. Independent of the
    // parse outcome for other commands, of any cache, and of ledger timing.
    if (cmd && cmd.id === FENCED_OLD_ID) {
      phase("legacy_fenced", cmd.id, "fence");
      phase("dedup_decision", cmd.id, "fence");
      doneOnce({});
      return;
    }
    // --- re-send an unacked cached result (PR#96), never re-execute ---
    const pend = ledger.pending;
    if (pend && pend.phase === "result_ready" && pend.result && pend.id !== FENCED_OLD_ID) {
      phase("result_delivery", pend.id, "resend");
      const res = await sendResult(pend.result);
      if (res.acked) {
        ledger.last_acked_id = Math.max(ledger.last_acked_id, pend.id);
        ledger.pending = null;
        try { saveLedger(ledger); } catch (_e) { phaseErr("ledger_write", pend.id, "store"); }
        try { $persistentStore.write(String(pend.id), STORE); } catch (_e) { phaseErr("store_write", pend.id, "store"); }
        phase("result_acked", pend.id, "resend");
      } else {
        phaseErr("result_unacked", pend.id, "ack");
      }
      // A cached result was outstanding: do not dispatch new work this round.
      doneOnce({});
      return;
    }
    if (pend && pend.phase === "result_ready" && pend.id === FENCED_OLD_ID) {
      // Defensive: a cached result for the fenced old id must never be sent.
      phase("legacy_fenced", pend.id, "fence");
      doneOnce({});
      return;
    }
    if (!cmd || !cmd.id) {
      phase("dedup_decision", 0, "none");
      doneOnce({});
      return;
    }
    // --- dedup (R0: normalised to seconds on both sides) ---
    const floorSec = Math.max(toSec(ledger.floor), toSec(ledger.last_acked_id), lastSec);
    if (toSec(cmd.id) <= floorSec) {
      phase("dedup_decision", cmd.id, "duplicate");
      doneOnce({});
      return;
    }
    phase("dedup_decision", cmd.id, "none");
    if (!Array.isArray(cmd.actions)) {
      phaseErr("malformed_actions", cmd.id, "malformed");
      doneOnce({});
      return;
    }
    phase("dispatch_enter", cmd.id, "none");
    // --- claim before dispatch (PR#96): a crash mid-execution leaves the
    // command in_progress and it is never silently re-executed. ---
    ledger.pending = { id: cmd.id, phase: "in_progress" };
    try { saveLedger(ledger); } catch (_e) { phaseErr("ledger_write", cmd.id, "store"); doneOnce({}); return; }
    const outputs = [];
    for (const a of cmd.actions) {
      try {
        if (a.type === "api") {
          outputs.push({ type: "api", path: a.path, result: await api(a.method || "GET", a.path, a.body) });
        } else if (a.type === "mcp") {
          const payload = { jsonrpc: "2.0", id: 1, method: "tools/call",
            params: { name: a.tool, arguments: a.arguments || {} } };
          const rr = await withTimeout(
            http("POST", "http://127.0.0.1:6171/v1/mcp",
              { "X-Key": APIKEY, "Content-Type": "application/json", "Accept": "application/json, text/event-stream" }, payload),
            RESULT_TIMEOUT_MS, "mcp");
          if (rr && rr.__timeout) {
            outputs.push({ type: "mcp", tool: a.tool, status: 0, err: "mcp_guard_timeout", data: "" });
          } else {
            outputs.push({ type: "mcp", tool: a.tool, status: rr.status, err: rr.err, data: (rr.data || "").slice(0, 3000) });
          }
        } else if (a.type === "notify") {
          $notification.post("Surge 远程指令", "", a.text || "done");
          outputs.push({ type: "notify", ok: true });
        } else {
          outputs.push({ type: a.type || "?", error: "unknown action" });
        }
      } catch (_e) { outputs.push({ type: a.type || "?", error: String(_e) }); phaseErr("action_error", cmd.id, "action"); }
    }
    phase("action_complete_or_unknown", cmd.id, "none");
    // --- persist result_ready BEFORE posting (PR#96) ---
    const result = { id: cmd.id, at: Date.now(), outputs: outputs };
    ledger.pending = { id: cmd.id, phase: "result_ready", result: result };
    phase("checkpoint_attempt", cmd.id, "none");
    try { saveLedger(ledger); } catch (_e) { phaseErr("checkpoint_failed", cmd.id, "store"); doneOnce({}); return; }
    // --- POST /result with strict ACK ---
    phase("result_delivery", cmd.id, "none");
    const res = await sendResult(result);
    if (res.acked) {
      try { $persistentStore.write(String(cmd.id), STORE); } catch (_e) { phaseErr("store_write", cmd.id, "store"); }
      ledger.last_acked_id = Math.max(ledger.last_acked_id, cmd.id);
      ledger.pending = null;
      try { saveLedger(ledger); } catch (_e) { phaseErr("ledger_write", cmd.id, "store"); }
      phase("result_acked", cmd.id, "none");
    } else {
      // 503 / 409 / timeout / lost ACK: result stays cached, last_id is NOT
      // advanced. The next run re-sends the CACHED result; never re-executes.
      phaseErr("result_unacked", cmd.id, "ack");
    }
    phase("done_or_catch", cmd.id, "none");
    doneOnce({});
  } catch (_e) {
    phaseErr("outer_catch", 0, "exception");
    phase("done_or_catch", 0, "exception");
    doneOnce({});
  } finally {
    clearTimeout(watchdog);
  }
})();
