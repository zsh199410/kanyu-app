"use strict";
/* Round 9 cross-review helper: verify a {proof, opts} JSON file with the
 * ACTUAL vendored pure-JS sources in a VM with isSecureContext=false and
 * no crypto.subtle. Prints "VERIFY true" or "VERIFY false".
 * Usage: node test_r9_js_verify_helper.js <proof-json-path>
 * Used by test_r9_cross_review_probes.py (P2/P3) to check the
 * Python-issuer -> pure-JS-verifier cross-language chain. */
const fs = require("fs");
const vm = require("vm");
const path = require("path");
const dir = __dirname;
function read(f) { return fs.readFileSync(path.join(dir, f), "utf8"); }
const ctx = vm.createContext({
  TextEncoder,
  atob: (s) => Buffer.from(s, "base64").toString("binary"),
  console,
});
vm.runInContext("self=globalThis; isSecureContext=false; crypto={};", ctx);
vm.runInContext(read("vendor/tweetnacl-fast-1.0.3.js"), ctx);
vm.runInContext(read("vendor/js-sha256-1.0.0.js"), ctx);
vm.runInContext(read("surge_purejs_signed_proof.review.js"), ctx);
const input = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
const res = vm.runInContext(
  "sgbridgeVerifySignedProofPureJs(" +
    JSON.stringify(input.proof) + "," + JSON.stringify(input.opts) + ")",
  ctx
);
console.log("VERIFY", res === true ? "true" : "false");
