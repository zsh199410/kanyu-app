"use strict";
/* C3-C0 Round 5 — negative control for the signed promotion gate.
 *
 * Five hostile proofs must ALL fail closed through promote():
 * active unchanged, candidate intact, no write to the active key.
 *   1. unsigned proof (signature deleted)
 *   2. wrong signature (signed by a different key)
 *   3. replayed nonce (nonce != the current expected challenge)
 *   4. mismatched candidate fingerprint (proof signed for another candidate)
 *   5. expired proof (expires_at in the past)
 *
 * Synthetic tokens only, mock $persistentStore, no network, no phone.
 * Note: durable replay rejection (remembering used nonces) is NOT
 * implemented in the reference — see PROMOTION_GATE_DESIGN.md Rev 3
 * addendum. Case 3 only proves a proof whose nonce does not match the
 * CURRENT expected challenge is rejected.
 */
const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const {
  PURPOSE, payload, candidateFingerprint,
} = require("./signed_promotion_proof");
const { promote, DEV_KEYS } = require("./promotion_gate");

const CANDIDATE = "TEST-NEG-CONTROL-CANDIDATE-0123456789ABCDEF";
const OTHER = "TEST-NEG-CONTROL-OTHER-0123456789ABCDEF";
const OLD_ACTIVE = "TEST-NEG-CONTROL-OLD-ACTIVE-0123456789ABC";
const OLD_TOKEN_ID = "TEST-NEG-CONTROL-OLD-ID-001";
const NEW_TOKEN_ID = "TEST-NEG-CONTROL-NEW-ID-002";
const NONCE = "TEST-NEG-CONTROL-NONCE-0123456789ABCDEF";
const STALE_NONCE = "TEST-NEG-CONTROL-STALE-NONCE-0123456789";

const { publicKey, privateKey } = crypto.generateKeyPairSync("ed25519");
const PINNED_PEM = publicKey.export({ type: "spki", format: "pem" });
const { privateKey: wrongPrivateKey } =
  crypto.generateKeyPairSync("ed25519");

function signProof(proof, key) {
  proof.signature = crypto
    .sign(null, Buffer.from(payload(proof), "utf8"), key)
    .toString("base64");
  return proof;
}

function baseProof(overrides = {}) {
  const now = Date.now();
  return Object.assign({
    purpose: PURPOSE,
    kind: "dev",
    ok: true,
    fingerprint_matches: true,
    token_id: NEW_TOKEN_ID,
    fingerprint: candidateFingerprint(CANDIDATE),
    nonce: NONCE,
    issued_at: now,
    expires_at: now + 60 * 60 * 1000,
  }, overrides);
}

function mockStore() {
  const map = new Map([
    [DEV_KEYS.candidateKey, CANDIDATE],
    [DEV_KEYS.activeKey, OLD_ACTIVE],
  ]);
  const writes = [];
  return {
    map, writes,
    read: (k) => (map.has(k) ? map.get(k) : null),
    write: (v, k) => { writes.push(k); map.set(k, v); return true; },
    remove: (k) => { map.delete(k); return true; },
  };
}

function expectFailClosed(name, proof) {
  const store = mockStore();
  const r = promote(store, {
    keys: DEV_KEYS,
    proof,
    oldTokenId: OLD_TOKEN_ID,
    expectedNonce: NONCE,
    pinnedPublicKeyPem: PINNED_PEM,
  });
  assert.deepEqual(r, { ok: false, status: "promotion_invalid_proof" },
    name + ": expected promotion_invalid_proof");
  assert.equal(store.map.get(DEV_KEYS.activeKey), OLD_ACTIVE,
    name + ": active token changed");
  assert.equal(store.map.get(DEV_KEYS.candidateKey), CANDIDATE,
    name + ": candidate not intact");
  assert.equal(store.writes.includes(DEV_KEYS.activeKey), false,
    name + ": active key was written");
  console.log("PASS", name);
}

let count = 0;
function check(name, fn) { fn(); count++; }

// 1. Unsigned proof.
check("unsigned proof fails closed", () => {
  const proof = signProof(baseProof(), privateKey);
  delete proof.signature;
  expectFailClosed("unsigned proof", proof);
});

// 2. Wrong signature (signed by a different key).
check("wrong signature fails closed", () => {
  const proof = signProof(baseProof(), wrongPrivateKey);
  expectFailClosed("wrong signature", proof);
});

// 3. Replayed nonce (stale challenge, not the current expected nonce).
check("replayed nonce fails closed", () => {
  const proof = signProof(baseProof({ nonce: STALE_NONCE }), privateKey);
  expectFailClosed("replayed nonce", proof);
});

// 4. Mismatched candidate fingerprint (proof signed for another candidate).
check("mismatched candidate fingerprint fails closed", () => {
  const proof = signProof(
    baseProof({ fingerprint: candidateFingerprint(OTHER) }), privateKey);
  expectFailClosed("mismatched candidate fingerprint", proof);
});

// 5. Expired proof.
check("expired proof fails closed", () => {
  const now = Date.now();
  const proof = signProof(baseProof({
    issued_at: now - 2 * 60 * 60 * 1000,
    expires_at: now - 60 * 1000,
  }), privateKey);
  expectFailClosed("expired proof", proof);
});

console.log("SUMMARY", count, "PASS, 0 FAIL");
