"use strict";
/*
 * Issue #73 S1: REVIEW-ONLY Shortcuts candidate-token bootstrap
 * (LOCAL KEY companion to bootstrap_candidate_shortcuts.template.js,
 * PR #101).
 *
 * This source NEVER embeds a key. It is designed for a manually
 * invoked Surge generic script, with an ephemeral Shortcuts
 * "Ask for Input" parameter supplied at RUN time (not saved in the
 * Shortcut's configuration). No phone execution is authorized.
 *
 * The candidate is deliberately staged under a DIFFERENT key from
 * sgbridge_cred_localkey. The active bridge does not consume it.
 * Promotion, device-side privacy validation and old-key revocation
 * are separate approved gates. Do not claim script self-deletion or
 * secure-enclave storage. On-device deletion of the Shortcut/script
 * and any history must be separately checked; deleting a script does
 * not wipe storage.
 *
 * The local key is only needed for the bridge's direct-HTTP fallback
 * and MCP calls; v2.2 can run without it for native $httpAPI calls.
 * Staging it is therefore a lower-priority, independent single-key
 * operation. There is NO two-key atomic write with the DEV candidate
 * staging, and that is BY DESIGN: active keys are never touched
 * during staging, so a partial update of active keys is impossible.
 *
 * Never log or print the parameter, a digest of it, or any local key.
 * There is NO HTTP API, network, notification or shell functionality.
 */
(function () {
  const STAGING_KEY = "sgbridge_cred_localkey_candidate";
  const ACTIVE_KEY = "sgbridge_cred_localkey";
  const STATUS_KEY = "sgbridge_cred_localkey_bootstrap_status";
  let status = "not_started";
  let triggered = false;
  try {
    // Reject script editor, HTTP API, cron, panel, and unknown launches.
    if (typeof $trigger !== "string" || $trigger !== "intent" ||
        typeof $intent !== "object" || $intent === null) {
      status = "unsupported_trigger";
      return;
    }
    triggered = true;
    const candidate = $intent.parameter;
    // Byte-safe printable ASCII key only. Exact production format is a
    // separate security requirement; do not paste actual values here.
    if (typeof candidate !== "string" || candidate.length < 32 ||
        candidate.length > 256 ||
        !/^[\x21-\x7E]+$/.test(candidate)) {
      status = "invalid_parameter";
      return;
    }
    const existing = $persistentStore.read(STAGING_KEY);
    if (existing !== null && existing !== undefined &&
        existing !== candidate) {
      status = "candidate_slot_occupied";
      return;
    }
    if (existing === candidate) {
      status = "candidate_already_staged";
      return;
    }
    // No promotion and no change to the active local key, legacy
    // checkpoint, bridge ledger or live command. Only write candidate key.
    const committed = $persistentStore.write(candidate, STAGING_KEY);
    if (committed !== true) {
      // A failed return cannot prove whether disk committed.
      status = "candidate_commit_unknown";
      return;
    }
    if ($persistentStore.read(STAGING_KEY) !== candidate) {
      status = "candidate_readback_unverified";
      return;
    }
    status = "candidate_staged";
  } catch (_e) {
    status = "bootstrap_error";
  } finally {
    // A nonsecret status marker only. A status save failure must not
    // trigger a retry of candidate writes.
    if (triggered) {
      try { $persistentStore.write(status, STATUS_KEY); } catch (_e) {}
    }
    $done();
  }
})();
