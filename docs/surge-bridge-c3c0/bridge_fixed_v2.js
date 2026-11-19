// Surge Bridge agent (FIXED v2, C3-C0): polls a mailbox, executes commands via
// the local Surge API, posts results back.
//
// DESENSITISED COPY: BASE / DEV / APIKEY below are placeholders. The production
// file keeps its real values; this file never contains them.
// Wire format UNCHANGED: GET /poll, POST /result, local $httpAPI / direct HTTP.
// No change to the poll/dispatch/result request shapes, except the result
// payload carries `timestamp` (epoch seconds, as in the PR#96 reference) so
// the ledger validator can check it; the server only requires id + outputs.
//
// Alignment with the PR #96 reference state machine (HEAD 7aba9184,
// docs/surge-bridge-recovery/bridge_delivery_state.js). Each change below
// names the reference function it mirrors:
//  (R0b) orderMillis()/newerRawId()/validId() — mirrors the reference's
//       orderMillis/newerRawId/validId. MILLISECOND-precision canonical
//       ordering for ALL comparisons (dedup, floor, last_acked_id,
//       pending.id, legacy last_id). A seconds id converts to ms by x1000;
//       a ms id (>=1e12) stays. Non-safe-integer or overflow returns null
//       and fails closed. Raw IDs are preserved unchanged on the wire
//       (/poll, /result), in the ledger, in ACK matching
//       (acked_id === raw cmd.id), and in receipts.
//       WHY toSec() (v1) WAS WRONG: flooring two distinct ms IDs issued
//       within the same second to the same second value silently dedupes a
//       genuinely newer command (e.g. checkpoint 1795055213880 and a new
//       command 1795055213881 both floor to 1795055213, so v1 would block
//       the newer one). Millisecond ordering preserves the 1ms distinction.
//  (c2)  FENCED_LEGACY_COMMAND_ID exact-id check — mirrors the reference's
//       FENCED_LEGACY_COMMAND_ID guard in runOnce(). It sits IMMEDIATELY
//       after poll, BEFORE any ledger load/bootstrap/reconciliation/
//       dispatch. It short-circuits before any $httpAPI/HTTP action, before
//       any last_id write, and before any POST /result, and does not depend
//       on the ledger existing, on the bootstrap having run, or on
//       parse/cache state.
//  (b0)  Bootstrap floor via newerRawId(observed, legacyId) — mirrors the
//       reference's first-run bootstrap. If the observed cmd is the fenced
//       old id, the fence (c2) already returned before bootstrap, so
//       bootstrap never sees it. A different synthetic pending cmd on first
//       run is fenced (LEGACY_PENDING_FENCED) and the floor is recorded;
//       it is never executed.
//  (s1)  saneState() ledger validation — mirrors the reference's
//       saneState(). A corrupt ledger fails closed (no execution).
//  (c3)  Pre-stored result_ready for the fenced old id is NEVER re-sent —
//       mirrors the reference test "old production command never sends
//       cached result even with a pre-existing result_ready ledger". The
//       fence is checked before the cached-result resend path too.
//  (a)   Promise-level timeout guard (withTimeout) on EVERY await. NOTE:
//       this is a best-effort guard, NOT a hard deadline guarantee — it
//       relies on the host setTimeout firing. If background timers are
//       frozen, no JS-level guard can release the await; that case is
//       RUNTIME_HARD_TIMEOUT_UNPROVEN and must be confirmed from real
//       device script logs. The Surge host cron timeout (120s) remains the
//       outer bound.
//  (b)   Phase observability. Every catch emits a phase; there is no silent
//       catch(_){}. Phase records carry ONLY {phase, desensitised id,
//       exception category, 10s time bucket} — never a body, token, or URI.
//  (d)   Single-$done guarantee (doneOnce + a 100s watchdog under the 120s
//       cron limit). On any path where the script completes, $done is called
//       exactly once; a late callback after $done is dropped, not re-run.
//  (e)   PR#96 result_ready + strict ACK: the result is persisted BEFORE
//       POSTing, and last_id is written ONLY after a strict ACK (200 +
//       accepted:true + acked_id === raw cmd.id). A lost ACK re-sends the
//       CACHED result; the action is never re-executed.
//  PR#85 outcome_unknown_no_retry is preserved: a timed-out/ambiguous
//  MUTATING call is never blindly retried via a second HTTP mutation.
const BASE = "https://<BRIDGE_BASE>";
const DEV = "<DEV_TOKEN>";
const APIKEY = "<API_KEY>";
const STORE = "sgbridge_last_id";
const LEDGER_KEY = "sgbridge_ledger_v1";
const PHASE_KEY = "sgbridge_phase_v1";
const FENCED_LEGACY_COMMAND_ID = 1795063030; // inherited pending command; observe only, never execute.

// Production timeouts (the C3-C0 simulator scales these down for fast tests).
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

// --- timestamp ordering (R0b): millisecond-precision canonical ordering ---
// Mirrors the PR#96 reference orderMillis/newerRawId/validId.
// Historical bridge IDs mix epoch seconds (10-digit) and epoch
// milliseconds (13-digit). Normalize ONLY FOR TEMPORAL ORDERING.
// Keep the ORIGINAL ID in /result, receipt, pending, ledger, and logs.
// Millisecond-based ordering, rather than truncation to seconds,
// preserves distinct ms IDs issued within the same second.
function validId(value) {
  return Number.isSafeInteger(value) && value >= 0;
}
function orderMillis(value) {
  if (!validId(value)) return null;
  if (value >= 1000000000000) return value;
  const ms = value * 1000;
  return Number.isSafeInteger(ms) ? ms : null;
}
function newerRawId(a, b) {
  const left = orderMillis(a), right = orderMillis(b);
  if (left === null || right === null) return null;
  return left >= right ? a : b;
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

// --- PR#96 durable ledger (saneState + fence floor + result_ready) ---
// Mirrors the reference saneState(): version 1, floor and last_acked_id
// must have a valid orderMillis, pending must be null or a valid phase
// with a matching result. A corrupt ledger fails closed (no execution).
const VALID_PHASES = ["in_progress", "result_ready"];
function saneState(state) {
  if (!state || state.version !== 1 ||
      orderMillis(state.floor) === null ||
      orderMillis(state.last_acked_id) === null ||
      !("pending" in state)) return false;
  if (state.pending === null) return true;
  const p = state.pending;
  return !!p && validId(p.id) && VALID_PHASES.indexOf(p.phase) !== -1 &&
    (p.phase !== "result_ready" || (
      p.result && p.result.id === p.id &&
      Array.isArray(p.result.outputs) && validId(p.result.timestamp)));
}
// loadLedger returns: null (absent), { __corrupt: true } (invalid), or the
// validated state object.
function loadLedger() {
  let raw = null;
  try { raw = $persistentStore.read(LEDGER_KEY); } catch (_e) { phaseErr("ledger_read", 0, "store"); return { __corrupt: true }; }
  if (!raw) return null;
  let s = null;
  try { s = JSON.parse(raw); } catch (_e) { phaseErr("ledger_parse", 0, "parse"); return { __corrupt: true }; }
  if (!saneState(s)) { phaseErr("ledger_corrupt", 0, "ledger"); return { __corrupt: true }; }
  return s;
}
function saveLedger(state) {
  if (!saneState(state)) throw new Error("durable_checkpoint_failed");
  $persistentStore.write(JSON.stringify(state), LEDGER_KEY);
}

// POST /result and check the STRICT ACK (PR#96): 200 + accepted:true +
// acked_id === result.id (RAW id). Anything else is NOT an acknowledgement.
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

// Re-send a CACHED result_ready receipt (never re-execute the action).
// Returns true if the cached result is now ACKed and the ledger cleared.
async function resendCached(ledger, pend) {
  phase("result_delivery", pend.id, "resend");
  const res = await sendResult(pend.result);
  if (res.acked) {
    const na = newerRawId(ledger.last_acked_id, pend.id);
    if (na !== null) ledger.last_acked_id = na;
    ledger.pending = null;
    try { saveLedger(ledger); } catch (_e) { phaseErr("ledger_write", pend.id, "store"); }
    try { $persistentStore.write(String(pend.id), STORE); } catch (_e) { phaseErr("store_write", pend.id, "store"); }
    phase("result_acked", pend.id, "resend");
    return true;
  }
  phaseErr("result_unacked", pend.id, "ack");
  return false;
}

(async () => {
  const watchdog = setTimeout(() => {
    phaseErr("watchdog", 0, "watchdog");
    doneOnce({});
  }, WATCHDOG_MS);
  try {
    phase("cron_enter", 0, "none");
    // --- legacy last_id (validated; a non-safe-integer fails closed) ---
    // Mirrors the reference's LEGACY_CHECKPOINT_INVALID: the legacy
    // checkpoint must be a safe integer, or nothing executes.
    let legacyId = 0;
    let rawLegacy = null;
    try { rawLegacy = $persistentStore.read(STORE); } catch (_e) { phaseErr("store_read", 0, "store"); doneOnce({}); return; }
    if (rawLegacy === null || rawLegacy === undefined || rawLegacy === "") {
      legacyId = 0;
    } else {
      const n = Number(rawLegacy);
      if (!validId(n)) { phaseErr("legacy_checkpoint_invalid", 0, "store"); doneOnce({}); return; }
      legacyId = n;
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
    // --- PERMANENT FENCE (c2): exact-id short-circuit, IMMEDIATELY after
    // poll, BEFORE any ledger load/bootstrap/reconciliation/dispatch.
    // Mirrors the reference's FENCED_LEGACY_COMMAND_ID guard in runOnce().
    // Independent of the ledger existing, of the bootstrap having run, and
    // of parse/cache state. The exact-id constant alone fences it.
    if (cmd && cmd.id === FENCED_LEGACY_COMMAND_ID) {
      phase("legacy_fenced", cmd.id, "fence");
      phase("dedup_decision", cmd.id, "fence");
      doneOnce({});
      return;
    }
    // --- ledger: load, or bootstrap on first run (PR#96) ---
    let ledger = loadLedger();
    if (ledger && ledger.__corrupt) {
      phaseErr("ledger_corrupt", cmd && cmd.id ? cmd.id : 0, "ledger");
      doneOnce({});
      return;
    }
    if (ledger === null) {
      // Empty mailbox first-run: record only the old checkpoint.
      // Pending mailbox first-run: FENCE the inherited command.
      // Mirrors the reference bootstrap: floor = newerRawId(observed,
      // legacyId), last_acked_id = 0, pending = null. The exact old id was
      // already fenced above, so bootstrap never sees it.
      const observed = (cmd && validId(cmd.id)) ? cmd.id : 0;
      const floor = newerRawId(observed, legacyId);
      if (floor === null) { phaseErr("ledger_bootstrap_failed", observed, "ledger"); doneOnce({}); return; }
      ledger = { version: 1, floor: floor, last_acked_id: 0, pending: null };
      try { saveLedger(ledger); phase("ledger_bootstrap", floor, "fence"); }
      catch (_e) { phaseErr("ledger_bootstrap_failed", floor, "store"); doneOnce({}); return; }
      if (observed !== 0) {
        // First-migration fence: a command pending at first run is fenced
        // and the floor is recorded; it is never executed.
        phase("legacy_fenced", observed, "fence");
        phase("dedup_decision", observed, "fence");
        doneOnce({});
        return;
      }
      // Empty bootstrap: no command this round. Fall through to the
      // no-command path below (pending is null by construction).
    }
    // --- pre-stored result_ready for the fenced old id must NEVER be
    // re-sent (c3). Mirrors the reference test "old production command
    // never sends cached result even with a pre-existing result_ready
    // ledger". Checked before ANY resend path, independent of the polled cmd.
    if (ledger.pending && ledger.pending.id === FENCED_LEGACY_COMMAND_ID) {
      phase("legacy_fenced", ledger.pending.id, "fence");
      doneOnce({});
      return;
    }
    // --- no command (poll timeout / empty mailbox / parse failure) ---
    if (!cmd || !validId(cmd.id) || cmd.id === 0) {
      const pend = ledger.pending;
      if (pend && pend.phase === "result_ready" && pend.result) {
        await resendCached(ledger, pend);
        doneOnce({});
        return;
      }
      if (pend) {
        // in_progress without a command: outcome unknown, never re-execute.
        phaseErr("pending_without_command", pend.id, pend.phase);
        doneOnce({});
        return;
      }
      phase("dedup_decision", 0, "none");
      doneOnce({});
      return;
    }
    // --- pending id mismatch: a different command is claimed; fail closed.
    // Mirrors the reference PENDING_ID_MISMATCH (no receipt lookup on the
    // phone, so a mismatched claim can never be reconciled here).
    const pend = ledger.pending;
    if (pend && pend.id !== cmd.id) {
      phaseErr("pending_mismatch", cmd.id, "pending");
      doneOnce({});
      return;
    }
    // --- in_progress: outcome unknown, never re-execute. ---
    if (pend && pend.phase === "in_progress") {
      phaseErr("outcome_unknown", cmd.id, "in_progress");
      doneOnce({});
      return;
    }
    // --- result_ready for this cmd: re-send the CACHED result only. ---
    if (pend && pend.phase === "result_ready" && pend.result) {
      await resendCached(ledger, pend);
      doneOnce({});
      return;
    }
    // --- dedup (R0b: millisecond-precision canonical ordering on ALL
    // sides). Mirrors the reference's orderMillis comparison. ---
    const current = orderMillis(cmd.id);
    const floor = orderMillis(ledger.floor);
    const acked = orderMillis(ledger.last_acked_id);
    const legacy = orderMillis(legacyId);
    if (current === null || floor === null || acked === null || legacy === null) {
      phaseErr("malformed_command", cmd.id, "malformed");
      doneOnce({});
      return;
    }
    if (current <= Math.max(floor, acked, legacy)) {
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
    // Result shape mirrors the reference: {id, timestamp (epoch seconds),
    // outputs}. The raw cmd.id is preserved; the server only requires
    // id + outputs.
    const result = { id: cmd.id, timestamp: Math.floor(Date.now() / 1000), outputs: outputs };
    ledger.pending = { id: cmd.id, phase: "result_ready", result: result };
    phase("checkpoint_attempt", cmd.id, "none");
    try { saveLedger(ledger); } catch (_e) { phaseErr("checkpoint_failed", cmd.id, "store"); doneOnce({}); return; }
    // --- POST /result with strict ACK ---
    phase("result_delivery", cmd.id, "none");
    const res = await sendResult(result);
    if (res.acked) {
      try { $persistentStore.write(String(cmd.id), STORE); } catch (_e) { phaseErr("store_write", cmd.id, "store"); }
      const na = newerRawId(ledger.last_acked_id, cmd.id);
      if (na !== null) ledger.last_acked_id = na;
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
