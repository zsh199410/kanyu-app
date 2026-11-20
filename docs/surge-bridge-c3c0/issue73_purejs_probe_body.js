"use strict";
/* Issue73 SOURCE-FREE one-shot pure-JS verification capability check.
 * Only TEST dummy credential, public signer key and public signature.
 * Does NOT perform credential promotion, rotation, or live HTTP.
 * Generated bundle also includes source-pinned TweetNaCl.js, js-sha256,
 * and the signed-proof verifier from this Draft PR.
 */
(function () {
  const KEY = "sgbridge_purejs_probe_status";
  let status = "probe_error", permitted = false;
  try {
    if (typeof $trigger !== "string" ||
        ($trigger !== "editor" && $trigger !== "intent")) return;
    permitted = true;
    if (typeof TextEncoder !== "function") {
      status = "text_encoder_missing"; return;
    }
    if (typeof atob !== "function") {
      status = "base64_missing"; return;
    }
    if (typeof sgbridgeVerifySignedProofPureJs !== "function") {
      status = "verifier_missing"; return;
    }
    const candidate = "TEST-NEW-TOKEN-0123456789ABCDEFabcdef9876543210";
    const proof = {
      purpose:"issue73/credential-promotion/v1",
      kind:"dev",ok:true,fingerprint_matches:true,
      token_id:"TEST-NEW-ID",
      fingerprint:"e6f02fc59cdc30547c2e2365f9c586cb57a9b74d2f41945b3d22f474d28f842a",
      nonce:"TEST-UNIQUE-CHALLENGE-0123456789ABCDEF",
      issued_at:1789999999000,
      expires_at:1790000060000,
      signature:"P0IG+fYBFVheYEIRcEdFGDeLDZvykYvzuZnhlBaWwZdjH1jztZCRv6Oz0ks+9i3EvQZRx9+sTOQnwdvPL/wEDA=="
    };
    const opts = {
      candidate,kind:"dev",oldTokenId:"TEST-OLD-ID",
      expectedNonce:proof.nonce,
      pinnedPublicKeyHex:"f762f7e4e64d5541a87628116940dba2f87f31f7e21fa465e56a20863f9cefec",
      now:1790000000000
    };
    const valid = sgbridgeVerifySignedProofPureJs(proof,opts);
    const tampered = Object.assign({},proof,{fingerprint:"0".repeat(64)});
    const invalid = sgbridgeVerifySignedProofPureJs(tampered,opts);
    status = valid === true && invalid === false ?
      "purejs_verify_ready" : "signature_failed";
  } catch (_e) {
    status = "probe_error";
  } finally {
    if (permitted) {
      try { $persistentStore.write(status, KEY); } catch (_e) {}
    }
    $done();
  }
})();
