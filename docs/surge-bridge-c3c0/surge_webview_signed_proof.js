"use strict";
/*
 * Issue #73 / C3-C1. REVIEW-ONLY Surge WebView-compatible signed-proof
 * verifier library. No Node require, no network, no store, no $done.
 * Bundling into a separately approved generic script is mandatory;
 * do NOT register this library as an independent Surge script.
 *
 * Trust arguments MUST be sourced independently of the untrusted proof:
 *   candidate: actual staged key read from protected candidate slot
 *   expectedNonce: a fresh challenge generated locally and consumed once
 *   pinnedPublicKeyHex: independently pinned Ed25519 PUBLIC key (not secret)
 *   oldTokenId: known exposed old token ID from trusted local policy
 * Only returns boolean. No credentials logged, sent, returned or changed.
 *
 * Stateless by design: checking nonce equality does NOT enforce one-time
 * consumption. A separately audited durable nonce state machine is needed.
 * Actual iOS support MUST first pass the device WebCrypto capability probe.
 */
(function (root) {
  const PURPOSE = "issue73/credential-promotion/v1";
  const MAX_AGE_MS = 24 * 60 * 60 * 1000;
  const MAX_FUTURE_SKEW_MS = 5 * 60 * 1000;

  function bytesOfHex(hex) {
    if (typeof hex !== "string" || !/^(?:[0-9a-f]{2})+$/i.test(hex))
      return null;
    const out = new Uint8Array(hex.length / 2);
    for (let i = 0; i < out.length; i++) {
      out[i] = parseInt(hex.slice(2 * i, 2 * i + 2), 16);
    }
    return out;
  }
  function hexOfBytes(raw) {
    return Array.from(raw).map((v) => v.toString(16).padStart(2, "0")).join("");
  }
  function canonicalJson(proof) {
    // Exact key order required by signed_promotion_proof.js on PR #103.
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

  async function verifySignedPromotionProof(proof, opts) {
    try {
      if (!proof || typeof proof !== "object" || Array.isArray(proof) ||
          !opts || typeof opts !== "object") return false;
      const {candidate, oldTokenId, expectedNonce,
             pinnedPublicKeyHex, kind} = opts;
      const now = opts.now === undefined ? Date.now() : opts.now;

      if (typeof candidate !== "string" ||
          candidate.length < 32 || candidate.length > 256 ||
          !/^[\x21-\x7e]+$/.test(candidate) || /^<.*>$/.test(candidate))
        return false;
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
          !/^[0-9a-f]{64}$/i.test(pinnedPublicKeyHex) ||
          typeof proof.signature !== "string" ||
          !/^[A-Za-z0-9+/]{86}==$/.test(proof.signature))
        return false;
      if (typeof crypto === "undefined" || !crypto ||
          !crypto.subtle || typeof crypto.subtle.digest !== "function" ||
          typeof crypto.subtle.importKey !== "function" ||
          typeof crypto.subtle.verify !== "function" ||
          typeof TextEncoder !== "function" ||
          typeof atob !== "function") return false;

      const encoder = new TextEncoder();
      const candidateHash = new Uint8Array(
        await crypto.subtle.digest("SHA-256", encoder.encode(candidate)));
      if (hexOfBytes(candidateHash) !== proof.fingerprint) return false;

      const publicBytes = bytesOfHex(pinnedPublicKeyHex);
      if (!publicBytes || publicBytes.length !== 32) return false;
      const decoded = atob(proof.signature);
      if (typeof decoded !== "string" || decoded.length !== 64) return false;
      const signature = new Uint8Array(64);
      for (let i = 0; i < 64; i++)
        signature[i] = decoded.charCodeAt(i);

      const publicKey = await crypto.subtle.importKey(
        "raw", publicBytes, {name:"Ed25519"}, false, ["verify"]);
      return (await crypto.subtle.verify(
        {name:"Ed25519"}, publicKey, signature,
        encoder.encode(canonicalJson(proof)))) === true;
    } catch (_e) {
      return false;
    }
  }

  // Node VM tests use module.exports; WebView can use the global when
  // this source is *bundled in* an explicitly reviewed manual script.
  if (typeof module === "object" && module && module.exports) {
    module.exports = { verifySignedPromotionProof, canonicalJson };
  } else {
    root.sgbridgeVerifySignedPromotionProof = verifySignedPromotionProof;
  }
})(typeof globalThis === "object" ? globalThis : this);
