"use strict";
/*
 * Issue #73 / C3-C1 safe device capability status panel helper.
 * Reads only ONE non-secret enum emitted by the separate WebView probe.
 * No real credentials, no network, no policy, no active key or device control.
 * Manual panel refresh only. Zero logs.
 */
(function () {
  const key = "sgbridge_webcrypto_probe_status";
  const states = Object.freeze({
    crypto_ready: "WebCrypto available (NOT release approval)",
    no_webcrypto: "WebCrypto API unavailable",
    no_text_encoder: "TextEncoder unavailable or incorrect",
    sha256_failed: "SHA-256 check failed",
    base64_unavailable: "atob unavailable",
    base64_failed: "atob decoding failed",
    ed25519_unavailable: "Ed25519 import unsupported",
    signature_failed: "Ed25519 verification failed",
    random_unavailable: "Secure random API unavailable",
    probe_error: "Probe encountered an error"
  });
  let state = "not_run";
  try {
    const result = $persistentStore.read(key);
    if (typeof result === "string" &&
        Object.prototype.hasOwnProperty.call(states, result)) {
      state = result;
    } else if (result != null) {
      state = "invalid_status";
    }
  } catch (_e) {
    state = "status_read_error";
  }
  $done({
    title: "Issue #73 · WebCrypto",
    content: state + " — " + (states[state] || "Not verified"),
    style: state === "crypto_ready" ? "info" : "warning"
  });
})();
