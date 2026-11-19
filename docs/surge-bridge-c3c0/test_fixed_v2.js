// C3-C0 regression suite for the v2 fixed bridge.js (bridge_fixed_v2.js,
// desensitised). Aligned with the PR #96 reference state machine (HEAD
// 7aba9184, bridge_delivery_state.js) adapted to the full phone script.
// Production timeouts are NOT scaled in the source; the mock setTimeout
// scales every timer by timerScale (0.01) — scaling the source too would
// double-scale the named guards (a real bug caught in C3-B F10).
// All commands are synthetic, except the fence tests which MUST use the
// inherited old id 1795063030 (public, GitHub #73) and the real ms last_id
// 1795055213880.
// Run: node test_fixed_v2.js   (writes test_fixed_v2_out.json)
"use strict";

const fs = require("fs");
const path = require("path");
const { MockMailbox, runScript } = require("./simulator");

const V2_RAW = fs.readFileSync(path.join(__dirname, "bridge_fixed_v2.js"), "utf8");
const V1_RAW = fs.readFileSync(path.join(__dirname, "v1", "bridge_fixed.js"), "utf8"); // v1 control, packaged (no ../pr96-c3b dependency)
const V2 = V2_RAW;
const V1 = V1_RAW;

const LAST_MS = "1795055213880"; // phone's real last_id (ms ts, public)
const LEGACY_MS = 1795055213880;
const OLD_ID = 1795063030;       // inherited pending command id (public)
const PENDING_SEC = 1795063030;
const SMALL_LAST = "1000000000";
const GET_CMD = (id) => ({ id, actions: [{ type: "api", method: "GET", path: "/v1/test" }] });

function lastIdWrites(out) {
  return out.storeWrites.filter((w) => w.key === "sgbridge_last_id").length;
}
function resultPosts(out) {
  return out.httpCalls.filter((c) => c.method === "POST" && c.path === "/result").length;
}
function phaseNames(out) { return out.phases.map((p) => p.phase); }
function hasPhase(out, name) { return phaseNames(out).includes(name); }
function phaseKeysClean(out) {
  return out.phases.every((p) => {
    const keys = Object.keys(p).sort().join(",");
    return keys === "cat,id,phase,tb";
  });
}
function readLedger(shared) {
  const raw = shared.store.get("sgbridge_ledger_v1");
  if (raw === undefined) return undefined;
  try { return JSON.parse(raw); } catch (_e) { return "<unparsable>"; }
}

// Bootstrap a shared state on an EMPTY mailbox (ledger created, floor =
// the legacy last_id). Returns {shared, out}.
async function bootstrapShared(lastIdStr) {
  const shared = { store: new Map([["sgbridge_last_id", lastIdStr]]), mailbox: new MockMailbox() };
  const out = await runScript(V2, {}, { shared, watchdogMs: 3000 });
  return { shared, out };
}
// One round against a shared state. cmd: command object, null (empty
// mailbox), or undefined (leave the mailbox as-is).
async function round(shared, cmd, cfg, opts) {
  if (cmd === null) shared.mailbox.setCmd(null);
  else if (cmd !== undefined) shared.mailbox.setCmd(cmd);
  return runScript(V2, cfg || {}, Object.assign({ shared, watchdogMs: 3000 }, opts || {}));
}
// Pre-seed a shared state with a ledger (bypasses bootstrap) + legacy id.
function seededShared(lastIdStr, ledgerObj, cmd) {
  const shared = { store: new Map([["sgbridge_last_id", lastIdStr]]), mailbox: new MockMailbox() };
  if (ledgerObj !== undefined && ledgerObj !== null) {
    shared.store.set("sgbridge_ledger_v1", JSON.stringify(ledgerObj));
  }
  if (cmd) shared.mailbox.setCmd(cmd);
  return shared;
}

const REQUIRED_PHASES = ["cron_enter", "poll_http_done", "cmd_parsed", "dedup_decision",
  "dispatch_enter", "action_complete_or_unknown", "checkpoint_attempt",
  "result_delivery", "done_or_catch"];

let PASS = 0, FAIL = 0, LIMIT = 0;
const results = [];
function record(id, name, gate, ok, detail) {
  results.push({ id, name, gate, pass: ok, detail });
  if (ok) PASS++; else FAIL++;
  console.log(`${ok ? "PASS" : "FAIL"} ${id} [${gate}] ${name}\n     ${detail}`);
}
function recordLimit(id, name, gate, detail) {
  results.push({ id, name, gate, pass: null, limitation: true, detail });
  LIMIT++;
  console.log(`LIMIT ${id} [${gate}] ${name}\n     ${detail}`);
}

async function main() {
  // ================= ORDERING: millisecond-precision canonical ordering =================
  // V1: same-second +1ms dispatches.
  {
    const { shared } = await bootstrapShared(LAST_MS);
    const out = await round(shared, GET_CMD(LEGACY_MS + 1));
    const ledger = readLedger(shared);
    const ok = out.dispatches === 1 && !!out.mailboxResult && out.mailboxResult.id === LEGACY_MS + 1 &&
      out.doneCalls === 1 && ledger && ledger.last_acked_id === LEGACY_MS + 1 && ledger.pending === null;
    record("V1", "same-second +1ms id dispatches (LEGACY_MS+1 vs ms checkpoint)",
      "SAME_SECOND_MS_CASE / ORDERING_CANONICAL_MS", ok,
      `dispatch=${out.dispatches} storedId=${out.mailboxResult && out.mailboxResult.id} done=${out.doneCalls} lastAcked=${ledger && ledger.last_acked_id}`);
  }
  // V2: same-second -1ms is deduped.
  {
    const { shared } = await bootstrapShared(LAST_MS);
    const out = await round(shared, GET_CMD(LEGACY_MS - 1));
    const ok = out.dispatches === 0 && resultPosts(out) === 0 && out.doneCalls === 1 && hasPhase(out, "dedup_decision");
    record("V2", "same-second -1ms id is deduped (LEGACY_MS-1)",
      "SAME_SECOND_MS_CASE / ORDERING_CANONICAL_MS", ok,
      `dispatch=${out.dispatches} resultPOST=${resultPosts(out)} done=${out.doneCalls} dedup_phase=${hasPhase(out, "dedup_decision")}`);
  }
  // V3: a second id for a second containing a newer ms checkpoint is deduped.
  {
    const { shared } = await bootstrapShared(LAST_MS);
    const out = await round(shared, GET_CMD(Math.floor(LEGACY_MS / 1000)));
    const ok = out.dispatches === 0 && resultPosts(out) === 0 && out.doneCalls === 1;
    record("V3", "second id floor(LEGACY_MS/1000) deduped (second holds a newer ms checkpoint)",
      "ORDERING_CANONICAL_MS", ok,
      `cmdSec=${Math.floor(LEGACY_MS / 1000)} dispatch=${out.dispatches} resultPOST=${resultPosts(out)} done=${out.doneCalls}`);
  }
  // V4: mixed s/ms bidirectional.
  {
    const { shared } = await bootstrapShared(LAST_MS);
    const out1 = await round(shared, GET_CMD(PENDING_SEC + 1));
    const ledger1 = readLedger(shared);
    const acked1 = ledger1 && ledger1.last_acked_id;
    const out2 = await round(shared, GET_CMD((PENDING_SEC + 1) * 1000 + 1));
    const ledger2 = readLedger(shared);
    const acked2 = ledger2 && ledger2.last_acked_id;
    const ok = out1.dispatches === 1 && out1.mailboxResult && out1.mailboxResult.id === PENDING_SEC + 1 &&
      acked1 === PENDING_SEC + 1 &&
      out2.dispatches === 1 && out2.mailboxResult && out2.mailboxResult.id === (PENDING_SEC + 1) * 1000 + 1 &&
      acked2 === (PENDING_SEC + 1) * 1000 + 1 &&
      out1.doneCalls === 1 && out2.doneCalls === 1;
    record("V4", "mixed s/ms bidirectional: sec cmd dispatches, then ms cmd dispatches; last_acked_id carries the raw id each time",
      "ORDERING_CANONICAL_MS / LEGACY_FLOOR_MIXED_UNIT_FIXED", ok,
      `sec dispatch=${out1.dispatches} ackedAfterSec=${acked1} | ms dispatch=${out2.dispatches} ackedAfterMs=${acked2}`);
  }
  // V5: equal-value collision — distinct ms ids in the same second are NOT
  // equal; an exactly equal id is deduped (fail-closed).
  {
    const M = 1795055213000; // ms id, second 1795055213
    const { shared } = await bootstrapShared(String(M));
    const out1 = await round(shared, GET_CMD(M + 1));
    const out2 = await round(shared, GET_CMD(M + 2));
    const out3 = await round(shared, GET_CMD(M + 2)); // exactly equal to last_acked_id
    const ok = out1.dispatches === 1 && out2.dispatches === 1 && out3.dispatches === 0 &&
      resultPosts(out3) === 0 && out1.doneCalls === 1 && out2.doneCalls === 1 && out3.doneCalls === 1;
    record("V5", "equal-value collision: M+1 and M+2 (same second) both dispatch; an exactly equal id is deduped",
      "SAME_SECOND_MS_CASE / ORDERING_CANONICAL_MS", ok,
      `M+1 dispatch=${out1.dispatches} | M+2 dispatch=${out2.dispatches} | M+2 again dispatch=${out3.dispatches} resultPOST=${resultPosts(out3)}`);
  }
  // V6: old 13-digit last + future 10-digit cmd dispatches (R0 regression).
  {
    const { shared } = await bootstrapShared(LAST_MS);
    const out = await round(shared, GET_CMD(PENDING_SEC + 1));
    const ok = out.dispatches === 1 && !!out.mailboxResult && out.mailboxResult.id === PENDING_SEC + 1 && out.doneCalls === 1;
    record("V6", "old 13-digit ms last + future 10-digit sec cmd dispatches (R0 regression)",
      "LEGACY_FLOOR_MIXED_UNIT_FIXED", ok,
      `dispatch=${out.dispatches} storedId=${out.mailboxResult && out.mailboxResult.id} done=${out.doneCalls}`);
  }
  // V7: non-safe-integer legacy id fails closed.
  {
    const bad = String(Number.MAX_SAFE_INTEGER + 1); // "9007199254740992"
    const out = await runScript(V2,
      { mailboxCmd: GET_CMD(2000000001), initialStore: { sgbridge_last_id: bad } },
      { watchdogMs: 3000 });
    const ok = out.dispatches === 0 && resultPosts(out) === 0 && out.doneCalls === 1 &&
      hasPhase(out, "legacy_checkpoint_invalid") && out.mailboxPollCount === 0;
    record("V7", "non-safe-integer legacy id fails closed (no action, no poll)",
      "ORDERING_CANONICAL_MS", ok,
      `legacy=${bad} dispatch=${out.dispatches} resultPOST=${resultPosts(out)} done=${out.doneCalls} phase=${hasPhase(out, "legacy_checkpoint_invalid")} polls=${out.mailboxPollCount}`);
  }
  // V8: v1 toSec() bug — the SAME scenario FAILS on v1 and PASSES on v2.
  // Pre-seeded ledger {floor: M, last_acked_id: 0} + legacy last_id M; cmd M+1.
  // v1 floors M and M+1 to the same second and dedup-blocks the newer cmd.
  // v2 orders in ms and dispatches it.
  {
    const M = 1795055213000;
    const ledgerObj = { version: 1, floor: M, last_acked_id: 0, pending: null };
    const shared1 = seededShared(String(M), ledgerObj, GET_CMD(M + 1));
    const outV1 = await runScript(V1, {}, { shared: shared1, watchdogMs: 3000 });
    const shared2 = seededShared(String(M), ledgerObj, GET_CMD(M + 1));
    const outV2 = await runScript(V2, {}, { shared: shared2, watchdogMs: 3000 });
    const ok = outV1.dispatches === 0 && outV2.dispatches === 1 &&
      !!outV2.mailboxResult && outV2.mailboxResult.id === M + 1 &&
      outV1.doneCalls === 1 && outV2.doneCalls === 1;
    record("V8", "v1 toSec() bug demonstrated: M+1 blocked on v1 (same-second floor collision), dispatched on v2",
      "ORDERING_CANONICAL_MS", ok,
      `v1 dispatch=${outV1.dispatches} (blocked) | v2 dispatch=${outV2.dispatches} storedId=${outV2.mailboxResult && outV2.mailboxResult.id} (ms ordering preserves the 1ms distinction)`);
  }

  // ================= FENCE: independent of ledger / bootstrap / cache =================
  // V9: fence before bootstrap — old cmd, NO ledger at all, 23 rounds.
  {
    const shared = { store: new Map([["sgbridge_last_id", LAST_MS]]), mailbox: new MockMailbox() };
    shared.mailbox.setCmd({ id: OLD_ID, actions: [{ type: "api", method: "GET", path: "/v1/outbound" }] });
    let totDispatch = 0, totResult = 0, totLastW = 0, totDone = 0, totHung = 0;
    for (let i = 0; i < 23; i++) {
      const out = await runScript(V2, {}, { shared, watchdogMs: 3000 });
      totDispatch += out.dispatches; totResult += resultPosts(out);
      totLastW += lastIdWrites(out); totDone += out.doneCalls; if (out.hung) totHung++;
    }
    const ok = totDispatch === 0 && totResult === 0 && totLastW === 0 && totDone === 23 && totHung === 0 &&
      shared.store.get("sgbridge_ledger_v1") === undefined &&
      shared.store.get("sgbridge_last_id") === LAST_MS &&
      shared.mailbox.cmd && shared.mailbox.cmd.id === OLD_ID && !shared.mailbox.result;
    record("V9", "fence before bootstrap: 23 rounds old cmd, NO ledger -> fenced, ledger stays null",
      "FENCE_INDEPENDENT_OF_LEDGER", ok,
      `rounds=23 dispatch=${totDispatch} resultPOST=${totResult} lastIdW=${totLastW} done=${totDone} hung=${totHung} ` +
      `ledgerAbsent=${shared.store.get("sgbridge_ledger_v1") === undefined} lastIdUnchanged=${shared.store.get("sgbridge_last_id") === LAST_MS} cmdStillPending=${!!(shared.mailbox.cmd && shared.mailbox.cmd.id === OLD_ID)}`);
  }
  // V10: empty-mailbox first init, then 23 rounds of the old cmd.
  {
    const { shared } = await bootstrapShared(LAST_MS);
    const ledgerBefore = shared.store.get("sgbridge_ledger_v1");
    const floorBefore = readLedger(shared).floor;
    shared.mailbox.setCmd({ id: OLD_ID, actions: [{ type: "api", method: "POST", path: "/v1/outbound" }] });
    let totDispatch = 0, totResult = 0, totLastW = 0, totDone = 0, totHung = 0;
    for (let i = 0; i < 23; i++) {
      const out = await runScript(V2, {}, { shared, watchdogMs: 3000 });
      totDispatch += out.dispatches; totResult += resultPosts(out);
      totLastW += lastIdWrites(out); totDone += out.doneCalls; if (out.hung) totHung++;
    }
    const ok = totDispatch === 0 && totResult === 0 && totLastW === 0 && totDone === 23 && totHung === 0 &&
      shared.store.get("sgbridge_ledger_v1") === ledgerBefore &&
      shared.store.get("sgbridge_last_id") === LAST_MS &&
      shared.mailbox.cmd && shared.mailbox.cmd.id === OLD_ID && !shared.mailbox.result;
    record("V10", "empty-mailbox first init, then 23 rounds old cmd -> all fenced, ledger unchanged",
      "FENCE_INDEPENDENT_OF_LEDGER", ok,
      `rounds=23 dispatch=${totDispatch} resultPOST=${totResult} lastIdW=${totLastW} done=${totDone} hung=${totHung} ` +
      `ledgerUnchanged=${shared.store.get("sgbridge_ledger_v1") === ledgerBefore} floor=${floorBefore}`);
  }
  // V11: pre-stored old result_ready + old cmd polled -> never re-sends.
  {
    const cached = { id: OLD_ID, timestamp: 1795064000, outputs: [{ ok: true }] };
    const ledgerObj = { version: 1, floor: LEGACY_MS, last_acked_id: 0,
      pending: { id: OLD_ID, phase: "result_ready", result: cached } };
    const shared = seededShared(LAST_MS, ledgerObj, { id: OLD_ID, actions: [{ type: "api", method: "POST", path: "/v1/outbound" }] });
    const out = await runScript(V2, {}, { shared, watchdogMs: 3000 });
    const ok = out.dispatches === 0 && resultPosts(out) === 0 && out.doneCalls === 1 && !out.mailboxResult;
    record("V11", "pre-stored old result_ready + old cmd polled -> never re-sends the cached result",
      "FENCE_INDEPENDENT_OF_LEDGER / PR96_DURABLE_ACK", ok,
      `dispatch=${out.dispatches} resultPOST=${resultPosts(out)} done=${out.doneCalls} mailboxResultStored=${!!out.mailboxResult}`);
  }
  // V12: pre-stored old result_ready + EMPTY mailbox -> never re-sends.
  {
    const cached = { id: OLD_ID, timestamp: 1795064000, outputs: [{ ok: true }] };
    const ledgerObj = { version: 1, floor: LEGACY_MS, last_acked_id: 0,
      pending: { id: OLD_ID, phase: "result_ready", result: cached } };
    const shared = seededShared(LAST_MS, ledgerObj, null);
    const out = await runScript(V2, {}, { shared, watchdogMs: 3000 });
    const ok = out.dispatches === 0 && resultPosts(out) === 0 && out.doneCalls === 1 && !out.mailboxResult;
    record("V12", "pre-stored old result_ready + empty mailbox -> never re-sends the cached result",
      "FENCE_INDEPENDENT_OF_LEDGER / PR96_DURABLE_ACK", ok,
      `dispatch=${out.dispatches} resultPOST=${resultPosts(out)} done=${out.doneCalls} mailboxResultStored=${!!out.mailboxResult}`);
  }
  // V13: first-migration fence — a synthetic pending cmd on first run.
  {
    const shared = { store: new Map([["sgbridge_last_id", "1234567"]]), mailbox: new MockMailbox() };
    shared.mailbox.setCmd(GET_CMD(2000000001));
    const out = await runScript(V2, {}, { shared, watchdogMs: 3000 });
    const ledger = readLedger(shared);
    const ok = out.dispatches === 0 && resultPosts(out) === 0 && out.doneCalls === 1 &&
      ledger && ledger.floor === 2000000001 && ledger.last_acked_id === 0 && ledger.pending === null &&
      hasPhase(out, "legacy_fenced");
    record("V13", "first-migration fence: synthetic pending cmd on first run is fenced, floor recorded, not executed",
      "FENCE_INDEPENDENT_OF_LEDGER", ok,
      `dispatch=${out.dispatches} resultPOST=${resultPosts(out)} done=${out.doneCalls} floor=${ledger && ledger.floor} lastAcked=${ledger && ledger.last_acked_id} fencedPhase=${hasPhase(out, "legacy_fenced")}`);
  }

  // ================= DURABLE ACK / PR#85 (resend flows) =================
  async function resendFlow(label, run1cfg) {
    // Step 1: bootstrap on an empty mailbox. Step 2: dispatch + checkpoint,
    // POST fails. Step 3: re-send the cached result, ACK.
    const { shared } = await bootstrapShared(SMALL_LAST);
    shared.mailbox.setCmd(GET_CMD(2000000001));
    const r1 = await runScript(V2, run1cfg, { shared, watchdogMs: 3000 });
    const r2 = await runScript(V2, {}, { shared, watchdogMs: 3000 });
    const totDispatch = r1.dispatches + r2.dispatches;
    const totResult = resultPosts(r1) + resultPosts(r2);
    const ledger = readLedger(shared);
    return { r1, r2, totDispatch, totResult, shared, ledger,
      detail: `${label}: run1 dispatch=${r1.dispatches} resultPOST=${resultPosts(r1)} lastIdW=${lastIdWrites(r1)} done=${r1.doneCalls} | ` +
        `run2 dispatch=${r2.dispatches} resultPOST=${resultPosts(r2)} lastIdW=${lastIdWrites(r2)} done=${r2.doneCalls} | ` +
        `total dispatch=${totDispatch} total resultPOST=${totResult} stored=${!!shared.mailbox.result} ` +
        `lastId=${shared.store.get("sgbridge_last_id")} ledgerPending=${ledger && ledger.pending}` };
  }
  {
    const t = await resendFlow("503", { persistFailNext: true });
    const ok = t.totDispatch === 1 && t.totResult === 2 && t.shared.store.get("sgbridge_last_id") === "2000000001" &&
      !!t.shared.mailbox.result && t.ledger && t.ledger.pending === null;
    record("V14", "result POST 503 -> cached, last_id NOT advanced; run 2 re-sends cached (no re-execution)",
      "PR96_DURABLE_ACK / 503/409/ACK_LOSS", ok, t.detail);
  }
  {
    const t = await resendFlow("409",
      { resultOverride: { status: 409, body: { ok: false, accepted: false, error: "pending_id_or_result_mismatch" } } });
    const ok = t.totDispatch === 1 && t.totResult === 2 && t.shared.store.get("sgbridge_last_id") === "2000000001" &&
      !!t.shared.mailbox.result && t.ledger && t.ledger.pending === null;
    record("V15", "result POST 409 -> cached, last_id NOT advanced; run 2 re-sends cached (no re-execution)",
      "PR96_DURABLE_ACK / 503/409/ACK_LOSS", ok, t.detail);
  }
  {
    const t = await resendFlow("ACK-LOSS", { dropAckNext: true });
    const ok = t.totDispatch === 1 && t.totResult === 2 && t.shared.store.get("sgbridge_last_id") === "2000000001" &&
      !!t.shared.mailbox.result && t.ledger && t.ledger.pending === null;
    record("V16", "ACK loss (server stored, response dropped) -> cached; run 2 re-sends cached, duplicate ACK",
      "PR96_DURABLE_ACK / 503/409/ACK_LOSS", ok, t.detail);
  }
  // V17: PR#85 outcome_unknown_no_retry preserved.
  {
    const { shared } = await bootstrapShared(SMALL_LAST);
    const out = await round(shared,
      { id: 2000000001, actions: [{ type: "api", method: "POST", path: "/v1/test", body: { x: 1 } }] },
      { httpApi: "never", timers: "fire" });
    const localPosts = out.httpCalls.filter((c) => c.method === "POST" && c.path === "/v1/test").length;
    const ok = out.doneCalls === 1 && localPosts === 0 && out.mailboxResult &&
      JSON.stringify(out.mailboxResult.outputs).includes("outcome_unknown_no_retry");
    record("V17", "PR#85 outcome_unknown_no_retry preserved (mutating POST, $httpAPI timeout -> no direct-HTTP retry)",
      "PR85_NO_POST_REPLAY", ok,
      `done=${out.doneCalls} directLocalPOSTs=${localPosts} outcome_unknown_no_retry=${JSON.stringify(out.mailboxResult && out.mailboxResult.outputs).includes("outcome_unknown_no_retry")}`);
  }
  // V18: new synthetic GET-only exactly-once + strict ACK.
  {
    const { shared } = await bootstrapShared(SMALL_LAST);
    const out = await round(shared, GET_CMD(2000000001));
    const ledger = readLedger(shared);
    const ok = out.dispatches === 1 && resultPosts(out) === 1 && !!out.mailboxResult &&
      out.mailboxResult.id === 2000000001 && lastIdWrites(out) === 1 &&
      shared.store.get("sgbridge_last_id") === "2000000001" &&
      ledger && ledger.pending === null && ledger.last_acked_id === 2000000001 && out.doneCalls === 1;
    record("V18", "new synthetic GET-only cmd -> exactly-once dispatch + strict ID ACK",
      "PR96_DURABLE_ACK / WIRE_RAW_ID_PRESERVED", ok,
      `dispatch=${out.dispatches} resultPOST=${resultPosts(out)} storedId=${out.mailboxResult && out.mailboxResult.id} ` +
      `lastId=${shared.store.get("sgbridge_last_id")} ledgerPending=${ledger && ledger.pending} lastAcked=${ledger && ledger.last_acked_id} done=${out.doneCalls}`);
  }

  // ================= $done / phase / late callback / hang =================
  // V19: exception in any stage -> visible phase AND $done exactly once.
  {
    const cases = [
      ["V19a", "store read throws", { storeReadThrows: true }, "store_read", true],
      ["V19b", "poll invalid JSON", { pollOverride: { body: "not-json{{{" } }, "poll_parse", true],
      ["V19c", "action throws (local API throws) -> action_error, result still posted", { httpApi: "undefined", localApi: "throw" }, "action_error", true],
      ["V19d", "checkpoint ledger write throws -> checkpoint_failed, no result", { ledgerWriteFailAfter: 1 }, "checkpoint_failed", true],
      ["V19e", "result POST throws ($httpClient post throws) -> outer_catch", { httpPost: "throw" }, "outer_catch", true],
    ];
    for (const [id, name, cfg, wantPhase, needsCmd] of cases) {
      const { shared } = await bootstrapShared(SMALL_LAST);
      const out = await round(shared, needsCmd ? GET_CMD(2000000001) : null, cfg);
      const ok = out.doneCalls === 1 && hasPhase(out, wantPhase);
      record(id, name, "DONE_AT_MOST_ONCE", ok,
        `done=${out.doneCalls} phase_${wantPhase}=${hasPhase(out, wantPhase)} phases=[${phaseNames(out).join(",")}] dispatch=${out.dispatches} resultPOST=${resultPosts(out)}`);
    }
  }
  // V20: late callback after terminal -> dropped, no side effect.
  {
    const { shared } = await bootstrapShared(SMALL_LAST);
    const out = await round(shared, GET_CMD(2000000001),
      { httpGet: "server", httpDelayMs: 600, timers: "fire" }, { settleMs: 600 });
    const ok = out.doneCalls === 1 && out.droppedLateCallbacks >= 1 && out.postDoneAttempts.length === 0;
    record("V20", "late $httpClient poll callback after terminal -> dropped, no side effect",
      "LATE_CALLBACK_NO_SIDE_EFFECT", ok,
      `done=${out.doneCalls} droppedLate=${out.droppedLateCallbacks} postDoneAttempts=${out.postDoneAttempts.length} dispatch=${out.dispatches} resultPOST=${resultPosts(out)}`);
  }
  // V21: phase trace — all 9 required phases in order, clean keys, no secrets.
  {
    const { shared } = await bootstrapShared(SMALL_LAST);
    const out = await round(shared, GET_CMD(2000000001));
    const names = phaseNames(out);
    const filtered = names.filter((p) => REQUIRED_PHASES.includes(p));
    const inOrder = JSON.stringify(filtered) === JSON.stringify(REQUIRED_PHASES);
    const missing = REQUIRED_PHASES.filter((p) => !names.includes(p));
    const blob = JSON.stringify(out.phases);
    const leak = /(https?:\/\/|DEV_TOKEN|API_KEY|sgcmd|vip668|trojan|vmess|ss:\/\/)/.test(blob);
    const ok = missing.length === 0 && inOrder && phaseKeysClean(out) && !leak && out.doneCalls === 1;
    record("V21", "phase trace: all 9 required phases in order, {phase,id,cat,tb} only, no secrets",
      "PHASE_TRACE_TEST / TRACE_NO_SECRETS", ok,
      `phases=[${names.join(",")}] missing=[${missing.join(",")}] inOrder=${inOrder} keysClean=${phaseKeysClean(out)} leak=${leak} done=${out.doneCalls}`);
  }
  // V22: $httpClient callback never returns, timers NORMAL -> guard releases.
  {
    const { shared } = await bootstrapShared(SMALL_LAST);
    const out = await round(shared, GET_CMD(2000000001), { httpGet: "never", timers: "fire" });
    const ok = !out.hung && out.doneCalls === 1 && hasPhase(out, "poll_timeout") && out.dispatches === 0;
    record("V22", "$httpClient callback never returns, timers NORMAL -> guard releases, $done 1",
      "CALLBACK_NEVER_FIRES_TEST", ok,
      `hung=${out.hung} done=${out.doneCalls} poll_timeout_phase=${hasPhase(out, "poll_timeout")} dispatch=${out.dispatches} resultPOST=${resultPosts(out)}`);
  }
  // V23: callback never returns, timers THROTTLED -> named limitation.
  {
    const { shared } = await bootstrapShared(SMALL_LAST);
    const out = await round(shared, GET_CMD(2000000001), { httpGet: "never", timers: "throttled" });
    recordLimit("V23", "$httpClient callback never returns, timers THROTTLED -> still hangs",
      "JS_TIMER_THROTTLE_TEST / HOST_TIMEOUT_LIMITATION",
      `hung=${out.hung} done=${out.doneCalls}. ` +
      `RUNTIME_HARD_TIMEOUT_UNPROVEN: a Promise.race+setTimeout guard is NOT a hard deadline when background timers are frozen. ` +
      `Only the Surge host cron timeout (120s) bounds it. Real device script logs are the final link to verify this later.`);
  }

  // ================= WIRE: raw IDs preserved =================
  // V24: raw IDs preserved on the wire (seconds and ms), in the ledger, and
  // in ACK matching.
  {
    const { shared } = await bootstrapShared(LAST_MS);
    const out1 = await round(shared, GET_CMD(PENDING_SEC + 1));
    const sent1 = out1.mailboxResult;
    const ledger1 = readLedger(shared);
    const out2 = await round(shared, GET_CMD((PENDING_SEC + 1) * 1000 + 1));
    const sent2 = out2.mailboxResult;
    const ledger2 = readLedger(shared);
    const ok = sent1 && sent1.id === PENDING_SEC + 1 && typeof sent1.id === "number" &&
      ledger1 && ledger1.last_acked_id === PENDING_SEC + 1 &&
      sent2 && sent2.id === (PENDING_SEC + 1) * 1000 + 1 && typeof sent2.id === "number" &&
      ledger2 && ledger2.last_acked_id === (PENDING_SEC + 1) * 1000 + 1 &&
      shared.store.get("sgbridge_last_id") === String((PENDING_SEC + 1) * 1000 + 1);
    record("V24", "raw IDs preserved on the wire: sec and ms cmd ids unchanged in result, ledger, and legacy last_id",
      "WIRE_RAW_ID_PRESERVED", ok,
      `sec sentId=${sent1 && sent1.id} ledgerAcked=${ledger1 && ledger1.last_acked_id} | ` +
      `ms sentId=${sent2 && sent2.id} ledgerAcked=${ledger2 && ledger2.last_acked_id} legacyLastId=${shared.store.get("sgbridge_last_id")}`);
  }
  // V25: mock state isolation. Run A pre-seeds a ledger (so the cmd
  // dispatches on the first run instead of hitting the first-migration
  // fence); run B is a fresh empty store.
  {
    const ledgerA = { version: 1, floor: 1000000000, last_acked_id: 0, pending: null };
    const sharedA = seededShared(SMALL_LAST, ledgerA, GET_CMD(2000000001));
    const a = await runScript(V2, {}, { shared: sharedA, watchdogMs: 3000 });
    const b = await runScript(V2, { mailboxCmd: null, initialStore: {} }, { watchdogMs: 3000 });
    const ok = a.mailboxResult && a.mailboxResult.id === 2000000001 &&
      !b.mailboxResult && !b.mailboxCmd && b.storeSnapshot["sgbridge_last_id"] === undefined &&
      b.doneCalls === 1 && b.dispatches === 0;
    record("V25", "mock state isolation: a dispatching run does not leak into the next fresh run",
      "DONE_AT_MOST_ONCE", ok,
      `A stored=${a.mailboxResult && a.mailboxResult.id} | B stored=${!!b.mailboxResult} B cmd=${!!b.mailboxCmd} B lastId=${b.storeSnapshot["sgbridge_last_id"]} B done=${b.doneCalls}`);
  }

  console.log(`\nV2: PASS=${PASS} FAIL=${FAIL} LIMITATION=${LIMIT} (of ${results.length} checks).`);
  fs.writeFileSync(path.join(__dirname, "test_fixed_v2_out.json"),
    JSON.stringify({ suite: "fixed-v2-regressions", pass: PASS, fail: FAIL, limitation: LIMIT, results }, null, 2));
  // CI gate: a failed check must fail the run (LIMITATIONs do not fail it).
  if (FAIL > 0) process.exitCode = 1;
}

main().catch((e) => { console.error(e); process.exit(1); });
