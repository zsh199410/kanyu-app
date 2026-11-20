"use strict";
/*
 * Issue #73 / C3-C1 — PURE-JS signed-proof verification REFERENCE ONLY.
 * This file does NOT load dependencies dynamically, request credentials,
 * make HTTP calls, write persistent data, run $done, or mutate proxy config.
 *
 * Dependencies must be bundled and hash-pinned from the vendored sources:
 *   vendor/tweetnacl-fast-1.0.3.js (public domain, Ed25519 verify/SHA-512)
 *   vendor/js-sha256-1.0.0.js (MIT, SHA-256 candidate fingerprint)
 * Both are source-immutable within this Draft PR. No runtime CDN.
 *
 * Independent trusted inputs (NEVER read from proof payload):
 * opts.candidate, opts.expectedNonce, opts.pinnedPublicKeyHex,
 * opts.oldTokenId and opts.kind. Stateless verification alone does NOT
 * provide durable one-time nonce consumption or authorization.
 */
(function (root) {
  const PURPOSE = "issue73/credential-promotion/v1";
  const MAX_AGE_MS = 24 * 60 * 60 * 1000;
  const MAX_FUTURE_SKEW_MS = 5 * 60 * 1000;

  function bytesOfHex(hex) {
    if (typeof hex !== "string" || !/^[0-9a-f]{64}$/i.test(hex))
      return null;
    const out = new Uint8Array(32);
    for (let i = 0; i < 32; i++)
      out[i] = parseInt(hex.slice(2 * i, 2 * i + 2), 16);
    return out;
  }
  function canonicalJson(proof) {
    // Must match signed_promotion_proof.js and the Python issuer EXACTLY.
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
  function decodeSignature(value) {
    if (typeof value !== "string" ||
        !/^[A-Za-z0-9+/]{86}==$/.test(value) ||
        typeof atob !== "function") return null;
    const decoded = atob(value);
    if (typeof decoded !== "string" || decoded.length !== 64) return null;
    const bytes = new Uint8Array(64);
    for (let i = 0; i < 64; i++) {
      const char = decoded.charCodeAt(i);
      if (char > 255) return null;
      bytes[i] = char;
    }
    return bytes;
  }

  function verifySignedProofPureJs(proof, opts) {
    try {
      if (!proof || typeof proof !== "object" || Array.isArray(proof) ||
          !opts || typeof opts !== "object") return false;
      const {candidate, expectedNonce, pinnedPublicKeyHex,
             oldTokenId, kind} = opts;
      const now = opts.now === undefined ? Date.now() : opts.now;
      if (typeof candidate !== "string" || candidate.length < 32 ||
          candidate.length > 256 || !/^[\x21-\x7e]+$/.test(candidate) ||
          /^<.*>$/.test(candidate)) return false;
      if (kind !== "dev" && kind !== "localkey") return false;
      if (proof.purpose !== PURPOSE || proof.kind !== kind ||
          proof.ok !== true || proof.fingerprint_matches !== true)
        return false;
      if (typeof oldTokenId !== "string" || !oldTokenId ||
          typeof proof.token_id !== "string" || !proof.token_id ||
          proof.token_id === oldTokenId) return false;
      if (typeof expectedNonce !== "string" || expectedNonce.length < 16 ||
          proof.nonce !== expectedNonce) return false;
      if (!Number.isSafeInteger(now) ||
          !Number.isSafeInteger(proof.issued_at) ||
          !Number.isSafeInteger(proof.expires_at)) return false;
      if (proof.issued_at > now + MAX_FUTURE_SKEW_MS ||
          now - proof.issued_at > MAX_AGE_MS ||
          proof.expires_at <= now ||
          proof.expires_at < proof.issued_at ||
          proof.expires_at > proof.issued_at + MAX_AGE_MS) return false;
      if (typeof proof.fingerprint !== "string" ||
          !/^[0-9a-f]{64}$/.test(proof.fingerprint) ||
          typeof pinnedPublicKeyHex !== "string" ||
          !/^[0-9a-f]{64}$/i.test(pinnedPublicKeyHex))
        return false;
      if (typeof TextEncoder !== "function" ||
          !root || !root.nacl || !root.nacl.sign ||
          !root.nacl.sign.detached ||
          typeof root.nacl.sign.detached.verify !== "function" ||
          typeof root.sha256 !== "function") return false;
      const expectedFingerprint = root.sha256(candidate);
      if (typeof expectedFingerprint !== "string" ||
          expectedFingerprint !== proof.fingerprint) return false;
      const publicKey = bytesOfHex(pinnedPublicKeyHex);
      const signature = decodeSignature(proof.signature);
      if (!publicKey || !signature) return false;
      return root.nacl.sign.detached.verify(
        new TextEncoder().encode(canonicalJson(proof)),
        signature, publicKey
      ) === true;
    } catch (_e) {
      return false;
    }
  }

  // Pure function: no automatic execution. This source must be bundled
  // into a separately reviewed release artifact, never installed alone.
  root.sgbridgeVerifySignedProofPureJs = verifySignedProofPureJs;
  root.sgbridgeCanonicalProofJsonPureJs = canonicalJson;
})(typeof self === "object" ? self : (typeof globalThis === "object" ? globalThis : this));
