/* Trial adapter (reference implementation, isolated, no I/O).
 *
 * Purpose: connect the PR #125 small-pool reference (small_trial.js) to the
 * real trial receiver contract WITHOUT touching the live probe or receiver.
 *
 * Contract (from PR #125 README + receiver behaviour):
 *  - The caller supplies an already-authenticated observation batch: the
 *    receiver has verified bearer, nonce freshness, manifest SHA/generation,
 *    exact node identity and external policy-ID against current source bytes
 *    BEFORE this module is invoked. This module never trusts a
 *    caller-supplied boolean in place of that validation.
 *  - Input here is a *verified snapshot*: {manifestSha, generation,
 *    nodes:[{id (64-hex identity), name}], observations:[{id, rawStatus}]}
 *    where every observation id is already proven to be in the manifest.
 *  - This module only plans the batch and classifies outcomes as
 *    diagnostic-only. It never permits promotion or pruning.
 *  - No network, filesystem, publisher or DIRECT fallback.
 *
 * Usage:
 *   const {planTrialBatch, smallTrialDiagnostic} = require('./small_trial');
 *   const {adaptTrialBatch} = require('./trial_adapter');
 *   const out = adaptTrialBatch(verifiedSnapshot, cursor);
 *   // out = {mode, ids, nextCursor, diagnostics:[{id, diagnostic_status, reason,
 *   //         promotion_allowed:false, prune_allowed:false}], valid:true}
 *   // Throws invalid_trial_snapshot / invalid_observation on bad input.
 */
'use strict';
const {planTrialBatch, smallTrialDiagnostic} = require('./small_trial');

function isHex64(s) {
  return typeof s === 'string' && /^[a-f0-9]{64}$/.test(s);
}

function adaptTrialBatch(snapshot, cursor = 0) {
  if (!snapshot || typeof snapshot !== 'object') throw new Error('invalid_trial_snapshot');
  const {manifestSha, generation, nodes, observations} = snapshot;
  if (!isHex64(manifestSha)) throw new Error('invalid_trial_snapshot');
  if (!Number.isSafeInteger(generation) || generation < 0) throw new Error('invalid_trial_snapshot');
  if (!Array.isArray(nodes) || nodes.length > 6) throw new Error('invalid_trial_snapshot');
  if (!Array.isArray(observations)) throw new Error('invalid_observation');
  const ids = [];
  const seen = new Set();
  const names = new Set();
  for (const n of nodes) {
    if (!n || typeof n !== 'object' || !isHex64(n.id) || typeof n.name !== 'string' || !n.name) {
      throw new Error('invalid_trial_snapshot');
    }
    if (seen.has(n.id)) throw new Error('invalid_trial_snapshot');
    // Policy display names must not ambiguously identify two different nodes.
    if (!n.name.trim() || names.has(n.name)) throw new Error('invalid_trial_snapshot');
    names.add(n.name);
    seen.add(n.id);
    ids.push(n.id);
  }
  const plan = planTrialBatch(ids, cursor);
  const selected = new Set(plan.ids);
  const observed = new Set();
  // Reject duplicate and out-of-batch observations rather than silently
  // overwriting or discarding evidence. Missing observations remain unknown.
  if (observations.length > plan.ids.length) throw new Error('invalid_observation');
  for (const o of observations) {
    if (!o || typeof o !== 'object' || !isHex64(o.id) ||
        !selected.has(o.id) || observed.has(o.id)) {
      throw new Error('invalid_observation');
    }
    if (!['success', 'failure', 'unknown'].includes(o.rawStatus)) {
      throw new Error('invalid_observation');
    }
    observed.add(o.id);
  }
  const byId = new Map(observations.map(o => [o.id, o.rawStatus]));
  const diagnostics = plan.ids.map(id => {
    const raw = byId.has(id) ? byId.get(id) : 'unknown';
    const d = smallTrialDiagnostic(raw);
    return {id, ...d};
  });
  return {
    valid: true,
    manifestSha,
    generation,
    mode: plan.mode,
    ids: plan.ids,
    nextCursor: plan.nextCursor,
    diagnostics,
  };
}

module.exports = {adaptTrialBatch};
