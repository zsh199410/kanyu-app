/* Issue #73: durable bridge command delivery, transport-agnostic.
 * Isolated implementation for integration into the PRIVATE bridge.js.
 *
 * NEVER reset/rewrite legacy last_id and never auto-execute an inherited
 * pending command on first migration. A cached result may be re-sent but
 * an in_progress command without a result is always OUTCOME_UNKNOWN.
 *
 * Adapter methods:
 *   getLedger(): JSON string|null
 *   putLedger(serialized): boolean (MUST persist before returning true)
 *   getLegacyLastId(): number
 *   poll(): Promise<{id,actions?...}|null>
 *   execute(command): Promise<outputs>
 *   sendResult({id,timestamp,outputs}): Promise<{status,body}>
 *   sendDiagnostic({code,command_id,legacy_last_id,phase}): Promise<void>
 *   lookupReceipt(id, result): Promise<{confirmed:boolean}> (optional)
 * A diagnostic is sent ONLY to a distinct /diagnostic endpoint, NEVER
 * to /result (because the legacy result endpoint clears the mailbox).
 */
"use strict";

const VALID_PHASES = new Set(["in_progress", "result_ready"]);
// Quarantine the incident's inherited command INDEPENDENT of first-run
// mailbox timing, legacy checkpoint units, or ledger contents. It is
// OUTCOME_UNKNOWN; no automatic action execution or /result POST is safe.
const FENCED_LEGACY_COMMAND_ID = 1795063030;

function validId(value) {
  return Number.isSafeInteger(value) && value >= 0;
}
// Historical bridge IDs mix epoch seconds (10-digit) and epoch
// milliseconds (13-digit). Normalize ONLY FOR TEMPORAL ORDERING.
// Keep the ORIGINAL ID in /result, receipt, pending, ledger, and logs.
// Millisecond-based ordering, rather than truncation to seconds,
// preserves distinct ms IDs issued within the same second.
function orderMillis(value) {
  if (!validId(value)) return null;
  if (value >= 1000000000000) return value;
  const ms=value*1000;
  return Number.isSafeInteger(ms) ? ms : null;
}
function newerRawId(a,b) {
  const left=orderMillis(a),right=orderMillis(b);
  if (left===null || right===null) return null;
  return left >= right ? a : b;
}
function saneState(state) {
  if (!state || state.version !== 1 ||
      orderMillis(state.floor) === null ||
      orderMillis(state.last_acked_id) === null ||
      !("pending" in state)) return false;
  if (state.pending === null) return true;
  const p = state.pending;
  return !!p && validId(p.id) && VALID_PHASES.has(p.phase) &&
    (p.phase !== "result_ready" || (
      p.result && p.result.id === p.id &&
      Array.isArray(p.result.outputs) && validId(p.result.timestamp)));
}
function save(io, state) {
  if (!saneState(state) || io.putLedger(JSON.stringify(state)) !== true) {
    throw new Error("durable_checkpoint_failed");
  }
}
async function diagnose(io, code, cmdId, legacyId, phase) {
  // Failure of diagnostics never authorizes mutation or a retry.
  try {
    await io.sendDiagnostic({
      code, command_id: validId(cmdId) ? cmdId : 0,
      legacy_last_id: validId(legacyId) ? legacyId : 0,
      phase: phase || "none"
    });
  } catch (_) {}
}
async function acknowledge(io, state, command, legacyId) {
  let reply;
  try { reply = await io.sendResult(command); }
  catch (_) {
    await diagnose(io, "RESULT_DELIVERY_UNKNOWN", command.id,
                   legacyId, "result_ready");
    return {decision:"RESULT_DELIVERY_UNKNOWN", action_executed:false};
  }
  const body = reply && reply.body;
  // A plain HTTP 200/ok:true is NOT an acknowledgement: the old server
  // accepted mismatched IDs and returned 200 without clearing pending.
  if (!reply || reply.status !== 200 || !body ||
      body.accepted !== true || body.acked_id !== command.id) {
    await diagnose(io, "ACK_UNVERIFIED", command.id, legacyId, "result_ready");
    return {decision:"ACK_UNVERIFIED", action_executed:false};
  }
  save(io, {version:1, floor:state.floor,
            last_acked_id: newerRawId(state.last_acked_id,command.id),
            pending:null});
  return {decision:"ACK_CONFIRMED", action_executed:false};
}

async function reconcileReceipt(io, state, legacyId) {
  const p=state.pending;
  if (!p || p.phase !== "result_ready" ||
      typeof io.lookupReceipt !== "function") return false;
  let checked;
  try { checked=await io.lookupReceipt(p.id,p.result); }
  catch (_) { return false; }
  if (!checked || checked.confirmed !== true) return false;
  save(io,{version:1,floor:state.floor,
           last_acked_id:newerRawId(state.last_acked_id,p.id),
           pending:null});
  await diagnose(io,"RECEIPT_RECONCILED",p.id,legacyId,"result_ready");
  return true;
}

async function runOnce(io) {
  const legacyId = io.getLegacyLastId();
  if (!validId(legacyId)) {
    await diagnose(io, "LEGACY_CHECKPOINT_INVALID", 0,0,"none");
    return {decision:"LEGACY_CHECKPOINT_INVALID",action_executed:false};
  }
  let cmd;
  try { cmd = await io.poll(); }
  catch (_) {
    return {decision:"POLL_FAILED",action_executed:false};
  }
  // This guard deliberately precedes ANY new-ledger bootstrap/reconciliation
  // or dispatch. A bootstrap that observed an empty mailbox must not
  // make the inherited old command executable on the next cron tick.
  if (cmd && cmd.id === FENCED_LEGACY_COMMAND_ID) {
    await diagnose(io,"LEGACY_PENDING_FENCED",cmd.id,legacyId,"none");
    return {decision:"LEGACY_COMMAND_QUARANTINED",action_executed:false};
  }
  const raw=io.getLedger();
  let state;
  if (raw === null || raw === undefined || raw === "") {
    // Empty mailbox first-run: record only the old checkpoint.
    // Pending mailbox first-run: FENCE the inherited command.
    const observed=cmd && validId(cmd.id) ? cmd.id : 0;
    state={version:1,floor:newerRawId(observed,legacyId),
           last_acked_id:0,pending:null};
    try { save(io,state); }
    catch (_) {
      return {decision:"CHECKPOINT_WRITE_FAILED",action_executed:false};
    }
    if (observed !== 0) {
      await diagnose(io,"LEGACY_PENDING_FENCED",observed,legacyId,"none");
      return {decision:"LEGACY_PENDING_FENCED",action_executed:false};
    }
    return {decision:"NO_COMMAND_BOOTSTRAPPED",action_executed:false};
  }
  try { state=JSON.parse(raw); } catch (_) { state=null; }
  if (!saneState(state)) {
    await diagnose(io,"LEDGER_CORRUPT",cmd && cmd.id,legacyId,"none");
    return {decision:"LEDGER_CORRUPT",action_executed:false};
  }
  if (!cmd || !validId(cmd.id) || cmd.id === 0) {
    if (await reconcileReceipt(io,state,legacyId)) {
      return {decision:"RECEIPT_RECONCILED",action_executed:false};
    }
    if (state.pending) {
      await diagnose(io,"PENDING_WITHOUT_COMMAND",
                     state.pending.id,legacyId,state.pending.phase);
      return {decision:"PENDING_WITHOUT_COMMAND",action_executed:false};
    }
    return {decision:"NO_COMMAND",action_executed:false};
  }
  const p=state.pending;
  if (p && p.id !== cmd.id) {
    if (await reconcileReceipt(io,state,legacyId)) {
      return {decision:"RECEIPT_RECONCILED",action_executed:false};
    }
    await diagnose(io,"PENDING_ID_MISMATCH",cmd.id,legacyId,p.phase);
    return {decision:"PENDING_ID_MISMATCH",action_executed:false};
  }
  if (p && p.phase === "in_progress") {
    await diagnose(io,"OUTCOME_UNKNOWN",cmd.id,legacyId,"in_progress");
    return {decision:"OUTCOME_UNKNOWN",action_executed:false};
  }
  if (p && p.phase === "result_ready") {
    // This is a retry of delivery of a CACHED RESULT, NOT a retry of
    // the command or HTTP API action. Server MUST provide idempotent ACK.
    return acknowledge(io,state,p.result,legacyId);
  }
  const current=orderMillis(cmd.id);
  const floor=orderMillis(state.floor);
  const acked=orderMillis(state.last_acked_id);
  const legacy=orderMillis(legacyId);
  if ([current,floor,acked,legacy].some(x=>x===null)) {
    await diagnose(io,"MALFORMED_COMMAND",cmd.id,legacyId,"none");
    return {decision:"MALFORMED_COMMAND",action_executed:false};
  }
  if (current <= Math.max(floor,acked,legacy)) {
    await diagnose(io,"DUPLICATE_OR_FENCED",cmd.id,legacyId,"none");
    return {decision:"DUPLICATE_OR_FENCED",action_executed:false};
  }
  if (!Array.isArray(cmd.actions)) {
    await diagnose(io,"MALFORMED_COMMAND",cmd.id,legacyId,"none");
    return {decision:"MALFORMED_COMMAND",action_executed:false};
  }
  // Persist a CLAIM before dispatch. If the script crashes mid-execution,
  // next invocation leaves the command untouched for human reconciliation.
  const claimed={version:1,floor:state.floor,
    last_acked_id:state.last_acked_id,
    pending:{id:cmd.id,phase:"in_progress"}};
  try { save(io,claimed); }
  catch (_) { return {decision:"CHECKPOINT_WRITE_FAILED",action_executed:false}; }
  let outputs;
  try { outputs = await io.execute(cmd); }
  catch (_) {
    await diagnose(io,"OUTCOME_UNKNOWN",cmd.id,legacyId,"in_progress");
    return {decision:"OUTCOME_UNKNOWN",action_executed:true};
  }
  if (!Array.isArray(outputs)) {
    await diagnose(io,"INVALID_RESULT",cmd.id,legacyId,"in_progress");
    return {decision:"INVALID_RESULT",action_executed:true};
  }
  // Persist result BEFORE network POST. A lost ACK can be re-sent with
  // identical payload; no action is ever re-executed.
  const result={id:cmd.id,timestamp:Math.floor(Date.now()/1000),outputs};
  claimed.pending={id:cmd.id,phase:"result_ready",result};
  try { save(io,claimed); }
  catch (_) {
    await diagnose(io,"RESULT_NOT_DURABLE",cmd.id,legacyId,"in_progress");
    return {decision:"RESULT_NOT_DURABLE",action_executed:true};
  }
  const ack=await acknowledge(io,claimed,result,legacyId);
  return {...ack,action_executed:true};
}
module.exports={runOnce,validId,saneState,orderMillis,newerRawId,FENCED_LEGACY_COMMAND_ID};
