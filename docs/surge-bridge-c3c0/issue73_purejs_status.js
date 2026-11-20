"use strict";
/* Issue73: read only nonsecret status written by source-pinned manual
 * pure-JS proof capability probe. Never returns credentials or logs.
 */
(function () {
  const states = Object.freeze({
    purejs_verify_ready:"Offline Ed25519 verification works (NOT release approval)",
    signature_failed:"Public test vector verification failed",
    text_encoder_missing:"TextEncoder missing in this script runtime",
    base64_missing:"Base64 decoder missing in this runtime",
    verifier_missing:"Verifier library missing; check bundled source",
    probe_error:"Capability probe error"
  });
  let status = "not_run";
  try {
    const v = $persistentStore.read("sgbridge_purejs_probe_status");
    status = typeof v === "string" && Object.prototype.hasOwnProperty.call(states,v)
      ? v : (v == null ? "not_run" : "invalid_status");
  } catch (_e) {
    status = "read_error";
  }
  $done({
    title:"Issue #73 · PureJS Verify",
    content:status+" — "+(states[status] || "Not verified"),
    style:status==="purejs_verify_ready"?"info":"alert"
  });
})();
