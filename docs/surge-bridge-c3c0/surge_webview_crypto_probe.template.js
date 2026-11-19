"use strict";
/*
 * Issue #73 / C3-C1 — non-secret Surge iOS WebView crypto capability probe.
 * REVIEW ONLY. No production credentials, no network, no token storage,
 * no policy change, no device action. The owner may run on the real device
 * ONLY after a separate explicit C3-C1 test approval.
 *
 * Required Surge declaration: type=generic, engine=webview, timeout=12
 * Trigger: Surge script editor (test) or a manual Shortcuts intent.
 * A cron/event/http-api/panel invocation changes no state.
 *
 * Written status key contains ONLY a fixed non-secret enum:
 *   crypto_ready; no_webcrypto; no_text_encoder; sha256_failed;
 *   ed25519_unavailable; signature_failed; random_unavailable;
 *   base64_unavailable; base64_failed; probe_error
 * No secret input; no HTTP/Surge device-control APIs; no console output.
 *
 * Ed25519 RFC 8032 §7.1 test vector #1: public key and signature are
 * PUBLIC test vectors, not credentials. A deliberately corrupted signature
 * must be rejected. This checks runtime API support, NOT server trust.
 */
(async function () {
  const STATUS_KEY = "sgbridge_webcrypto_probe_status";
  let status = "probe_error";
  let permitted = false;
  function bytes(hex) {
    if (typeof hex !== "string" || hex.length % 2 ||
        !/^[0-9a-f]*$/i.test(hex)) throw new Error("fixture_invalid");
    const out = new Uint8Array(hex.length / 2);
    for (let i = 0; i < out.length; i++)
      out[i] = parseInt(hex.substring(i * 2, i * 2 + 2), 16);
    return out;
  }
  function hexOf(values) {
    return Array.from(values).map((v) => v.toString(16).padStart(2, "0")).join("");
  }

  try {
    if (typeof $trigger !== "string" ||
        ($trigger !== "editor" && $trigger !== "intent")) return;
    permitted = true;

    if (typeof crypto === "undefined" || !crypto ||
        !crypto.subtle || typeof crypto.subtle.digest !== "function" ||
        typeof crypto.subtle.importKey !== "function" ||
        typeof crypto.subtle.verify !== "function") {
      status = "no_webcrypto";
      return;
    }
    if (typeof TextEncoder !== "function") {
      status = "no_text_encoder";
      return;
    }

    const encoded = new TextEncoder().encode("abc");
    if (hexOf(encoded) !== "616263") {
      status = "no_text_encoder";
      return;
    }

    // PR #105's WebView verifier decodes the signed proof via atob.
    // A positive probe must not be possible when atob is absent or broken.
    if (typeof atob !== "function") {
      status = "base64_unavailable";
      return;
    }
    if (atob("AQIDBA==") !== String.fromCharCode(1, 2, 3, 4)) {
      status = "base64_failed";
      return;
    }

    const hashed = new Uint8Array(
      await crypto.subtle.digest("SHA-256", new Uint8Array(0)));
    if (hexOf(hashed) !==
        "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855") {
      status = "sha256_failed";
      return;
    }

    const publicKey = bytes(
      "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a");
    const signature = bytes(
      "e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901" +
      "555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b");

    let key;
    try {
      key = await crypto.subtle.importKey(
        "raw", publicKey, { name: "Ed25519" }, false, ["verify"]);
    } catch (_e) {
      status = "ed25519_unavailable";
      return;
    }

    const emptyMessage = new Uint8Array(0);
    const valid = await crypto.subtle.verify(
      { name: "Ed25519" }, key, signature, emptyMessage);
    const altered = signature.slice();
    altered[0] ^= 1;
    const invalid = await crypto.subtle.verify(
      { name: "Ed25519" }, key, altered, emptyMessage);
    if (valid !== true || invalid !== false) {
      status = "signature_failed";
      return;
    }

    if (typeof crypto.getRandomValues !== "function") {
      status = "random_unavailable";
      return;
    }
    const nonce = new Uint8Array(32);
    if (crypto.getRandomValues(nonce) !== nonce || nonce.length !== 32) {
      status = "random_unavailable";
      return;
    }

    status = "crypto_ready";
  } catch (_e) {
    status = "probe_error";
  } finally {
    if (permitted) {
      try { $persistentStore.write(status, STATUS_KEY); } catch (_e) {}
    }
    $done();
  }
})();
