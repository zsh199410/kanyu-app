"use strict";
/*
 * Issue #73, C3-C1: isolated Node reference for a signed promotion proof.
 * NOT an iOS/Surge implementation. A production device must provide
 * independently verified trust anchors and a supported signature verifier.
 * Never use a key/public-key/nonce received in the proof as its own anchor.
 * No network or persistent-store access; no token values returned/logged.
 */
const crypto = require("node:crypto");
const PURPOSE = "issue73/credential-promotion/v1";
const MAX_AGE_MS = 24 * 60 * 60 * 1000;
const MAX_FUTURE_SKEW_MS = 5 * 60 * 1000;

function payload(proof) {
  // Fixed canonical field order; the signer MUST use exactly this encoding.
  return JSON.stringify({
    purpose: proof.purpose,
    kind: proof.kind,
    ok: proof.ok,
    fingerprint_matches: proof.fingerprint_matches,
    token_id: proof.token_id,
    fingerprint: proof.fingerprint,
    nonce: proof.nonce,
    issued_at: proof.issued_at,
    expires_at: proof.expires_at,
  });
}

function candidateFingerprint(candidate) {
  return crypto.createHash("sha256").update(candidate, "utf8").digest("hex");
}

function validSignedProof(proof, {candidate, oldTokenId, expectedNonce, kind,
                                pinnedPublicKeyPem, now = Date.now()} = {}) {
  try {
    if (!proof || typeof proof !== "object" || Array.isArray(proof)) return false;
    if (typeof candidate !== "string" || candidate.length < 32) return false;
    if (kind !== "dev" && kind !== "localkey") return false;
    if (proof.purpose !== PURPOSE || proof.kind !== kind) return false;
    if (proof.ok !== true || proof.fingerprint_matches !== true) return false;
    if (typeof proof.token_id !== "string" || !proof.token_id ||
        proof.token_id === oldTokenId) return false;
    if (typeof expectedNonce !== "string" || expectedNonce.length < 16 ||
        typeof proof.nonce !== "string" || proof.nonce !== expectedNonce) return false;
    if (!Number.isSafeInteger(now) ||
        !Number.isSafeInteger(proof.issued_at) ||
        !Number.isSafeInteger(proof.expires_at)) return false;
    if (proof.issued_at > now + MAX_FUTURE_SKEW_MS ||
        now - proof.issued_at > MAX_AGE_MS ||
        proof.expires_at <= now ||
        proof.expires_at < proof.issued_at ||
        proof.expires_at > proof.issued_at + MAX_AGE_MS) return false;
    if (!/^[0-9a-f]{64}$/.test(proof.fingerprint)) return false;
    const a = Buffer.from(proof.fingerprint, "hex");
    const b = Buffer.from(candidateFingerprint(candidate), "hex");
    if (!crypto.timingSafeEqual(a, b)) return false;
    if (typeof proof.signature !== "string" ||
        !/^[A-Za-z0-9+/]{86}==$/.test(proof.signature)) return false;
    if (typeof pinnedPublicKeyPem !== "string" || !pinnedPublicKeyPem) return false;
    const pub = crypto.createPublicKey(pinnedPublicKeyPem);
    if (pub.asymmetricKeyType !== "ed25519") return false;
    const signature = Buffer.from(proof.signature, "base64");
    if (signature.length !== 64) return false;
    return crypto.verify(null, Buffer.from(payload(proof), "utf8"), pub, signature);
  } catch (_e) {
    return false;
  }
}

module.exports = {PURPOSE, payload, candidateFingerprint, validSignedProof};
