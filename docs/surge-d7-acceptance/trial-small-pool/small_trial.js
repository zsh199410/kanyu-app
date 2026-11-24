/* Offline trial-only reference helper; not a receiver or live deployment.
 * Caller must first authenticate the observation and validate actual manifest bytes,
 * generation, nonce, stable identity and native policy-ID mapping.
 * Never invoke for the production pool. No network, filesystem or publisher access.
 */
function planTrialBatch(verifiedIds, cursor = 0) {
  if (!Array.isArray(verifiedIds) || verifiedIds.length > 6 ||
      !Number.isSafeInteger(cursor) || cursor < 0 ||
      verifiedIds.some(id => typeof id !== "string" || !/^[a-f0-9]{64}$/.test(id)) ||
      new Set(verifiedIds).size !== verifiedIds.length) {
    throw new Error("invalid_trial_snapshot");
  }
  const size = verifiedIds.length;
  if (size === 0) return {ids:[],nextCursor:0,mode:"empty_no_batch"};
  const start = cursor % size;
  const count = Math.min(4, size);
  return {ids:Array.from({length:count}, (_,i)=>verifiedIds[(start+i)%size]),
          nextCursor:(start+count)%size,mode:size < 3 ? "small_diagnostic_only":"existing_receiver_rules"};
}

function smallTrialDiagnostic(rawStatus) {
  if (!["success","failure","unknown"].includes(rawStatus)) throw new Error("invalid_raw_status");
  return {raw_status:rawStatus,
          diagnostic_status:rawStatus === "success" ? "observed_reachable" : "unknown",
          reason:rawStatus === "success" ? "small_trial_reachable" :
                 rawStatus === "failure" ? "small_trial_failure_unverified" : "small_trial_inconclusive",
          promotion_allowed:false,prune_allowed:false};
}

module.exports={planTrialBatch,smallTrialDiagnostic};
