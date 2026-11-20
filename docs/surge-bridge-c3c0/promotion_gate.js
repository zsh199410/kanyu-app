"use strict";
/* C3-C0 Round 4 — Item 2: staging-to-active promotion gate (isolated sample).
 *
 * Implements the promotion gate from PROMOTION_GATE_DESIGN.md against a
 * mock $persistentStore-like interface { read, write, remove? }.
 * Synthetic tokens only. No network, no phone, no real server call:
 * the /credential-proof proof is a mock object passed in by the
 * caller (see validProof). The gate never touches the mailbox, the
 * ledger, last_id, pins, or timers — it has no code path to them.
 *
 * Statuses are non-secret enums only. No token value, digest, or key
 * value is ever returned, logged, or stored anywhere except the
 * credential keys themselves.
 *
 * Usage:
 *   const { promote, DEV_KEYS, KEY_KEYS } = require("./promotion_gate");
 *   const r = promote(store, { keys: DEV_KEYS, proof, oldTokenId });
 *   // r = { ok: boolean, status: "<enum>" }
 */
const { validSignedProof } = require("./signed_promotion_proof");
const DEV_KEYS = {
  candidateKey: "sgbridge_cred_dev_candidate",
  activeKey: "sgbridge_cred_dev",
  statusKey: "sgbridge_promotion_status",
};
const KEY_KEYS = {
  candidateKey: "sgbridge_cred_localkey_candidate",
  activeKey: "sgbridge_cred_localkey",
  statusKey: "sgbridge_cred_localkey_promotion_status",
};

/* The tombstone written when the store has no remove() method.
 * 12 chars: it can never validate as a candidate (32-256 window),
 * so it can never be mistaken for a real credential. It occupies
 * the slot until a separate approved device-side action clears it. */
const PROMOTED_TOMBSTONE = "__PROMOTED__";

/* Proof freshness window (design choice, see PROMOTION_GATE_DESIGN.md §6). */
const PROOF_FRESH_MS = 24 * 60 * 60 * 1000;
const PROOF_FUTURE_SKEW_MS = 5 * 60 * 1000;

/* v2.2 readCredential rules + the staging template's 32-256
 * printable-ASCII window. Both must hold. */
function validCandidate(value) {
  if (typeof value !== "string" || !value) return false;
  if (value.length > 512) return false;
  if (/[\r\n]/.test(value)) return false;
  if (/^<.*>$/.test(value)) return false;
  if (value.length < 32 || value.length > 256) return false;
  if (!/^[\x21-\x7E]+$/.test(value)) return false;
  return true;
}

/* Cryptographically authenticated reference proof, never a self-asserted
 * fingerprint_matches boolean. The pinned public key and challenge nonce
 * MUST be trusted inputs from outside the response and NOT supplied by
 * the server's proof payload. This is Node-only reference code. */
function validProof(proof, oldTokenId, candidate, expectedNonce, pinnedPublicKeyPem,
                    kind) {
  return validSignedProof(proof, {
    candidate, oldTokenId, expectedNonce, pinnedPublicKeyPem, kind,
  });
}

/* Clears the candidate key. Uses store.remove() when available;
 * otherwise overwrites with the tombstone (see §5 of the design).
 * Returns true on success, false on failure. */
function clearCandidate(store, candidateKey) {
  if (typeof store.remove === "function") {
    try {
      const r = store.remove(candidateKey);
      return r !== false;
    } catch (_e) {
      return false;
    }
  }
  try {
    return store.write(PROMOTED_TOMBSTONE, candidateKey) === true;
  } catch (_e) {
    return false;
  }
}

/* Promotes only when the signed proof verifies against the candidate.
 * A store write may persist and then report failure, so an ambiguous
 * write DOES NOT guarantee the original active value is unchanged.
 * The result must be reconciled before any further rotation. */
function promote(store, { keys, proof, oldTokenId, expectedNonce, pinnedPublicKeyPem }) {
  const { candidateKey, activeKey, statusKey } = keys;
  const kind = candidateKey === DEV_KEYS.candidateKey &&
      activeKey === DEV_KEYS.activeKey && statusKey === DEV_KEYS.statusKey ?
      "dev" : candidateKey === KEY_KEYS.candidateKey &&
      activeKey === KEY_KEYS.activeKey && statusKey === KEY_KEYS.statusKey ?
      "localkey" : null;
  const writeStatus = (s) => {
    try { store.write(s, statusKey); } catch (_e) { /* best-effort */ }
  };
  const fail = (status) => {
    writeStatus(status);
    return { ok: false, status };
  };

  if (!kind) return { ok: false, status: "promotion_invalid_keys" };

  let candidate;
  try {
    candidate = store.read(candidateKey);
  } catch (_e) {
    return fail("promotion_store_error");
  }
  if (candidate === undefined || candidate === null) {
    /* A best-effort status marker is NOT an authorization proof:
     * active state may have changed after a previous promotion. */
    return fail("promotion_no_candidate");
  }
  if (!validCandidate(candidate)) {
    return fail("promotion_invalid_candidate");
  }
  if (!validProof(proof, oldTokenId, candidate, expectedNonce,
                  pinnedPublicKeyPem, kind)) {
    return fail("promotion_invalid_proof");
  }
  let active;
  try {
    active = store.read(activeKey);
  } catch (_e) {
    return fail("promotion_store_error");
  }
  if (active === candidate) {
    writeStatus("promotion_already_active");
    return { ok: true, status: "promotion_already_active" };
  }
  if (active === undefined || active === null) {
    return fail("promotion_no_active");
  }

  /* Write the new active value. A false return cannot prove whether
   * disk committed: read back to disambiguate, and never assume an
   * exception proves storage did not commit. */
  let committed;
  try {
    committed = store.write(candidate, activeKey);
  } catch (_e) {
    return fail("promotion_commit_unknown");
  }
  if (committed !== true) {
    let after;
    try {
      after = store.read(activeKey);
    } catch (_e) {
      return fail("promotion_commit_unknown");
    }
    if (after === candidate) {
      /* Committed despite the false return: ambiguous, do NOT
       * report success and do NOT clear the candidate. */
      return fail("promotion_commit_unknown");
    }
    return fail("promotion_commit_unknown");
  }
  let verified;
  try {
    verified = store.read(activeKey);
  } catch (_e) {
    return fail("promotion_readback_unverified");
  }
  if (verified !== candidate) {
    return fail("promotion_readback_unverified");
  }

  /* Only now, after the read-back verification, clear the candidate.
   * A clear failure does NOT roll back the verified promotion (see
   * design §4): the active token is already the new verified value,
   * the candidate stays intact, and a retry converges to
   * promotion_already_active. */
  if (!clearCandidate(store, candidateKey)) {
    return fail("promotion_candidate_clear_failed");
  }
  writeStatus("promotion_done");
  return { ok: true, status: "promotion_done" };
}

module.exports = {
  promote,
  validCandidate,
  validProof,
  DEV_KEYS,
  KEY_KEYS,
  PROMOTED_TOMBSTONE,
};
