"use strict";
/* Real atomic SQLite approval -> Python Ed25519 -> browser WebCrypto VM.
 * All input is ephemeral and synthetic; never a production credential.
 */
const assert = require("node:assert/strict");
const cp = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const {webcrypto} = require("node:crypto");

const here = __dirname;
const fixture = JSON.parse(cp.execFileSync("python3",
  [path.join(here, "test_atomic_token_proof_fixture.py")],
  {cwd: here, timeout: 15000, encoding: "utf8", maxBuffer: 100000}));
const source = fs.readFileSync(
  path.join(here, "surge_webview_signed_proof.js"), "utf8");
const sandbox = {module:{exports:{}},crypto:webcrypto,TextEncoder,atob};
vm.runInNewContext(source,sandbox,{timeout:2000});
const verify = sandbox.module.exports.verifySignedPromotionProof;
const opts = {candidate:fixture.candidate,kind:"dev",
  oldTokenId:fixture.old_id,expectedNonce:fixture.nonce,
  pinnedPublicKeyHex:fixture.public_hex,now:fixture.now};

let passed = 0;
async function test(name,fn){await fn();passed++;console.log("PASS",name)}
(async()=>{
  await test("atomically authorized Python signature verifies in WebCrypto",async()=>{
    assert.equal(await verify(fixture.proof,opts),true);
  });
  await test("new token proof cannot be used with old-token identity",async()=>{
    assert.equal(await verify(fixture.proof,{...opts,oldTokenId:fixture.proof.token_id}),false);
  });
  await test("tampered candidate fingerprint rejected",async()=>{
    assert.equal(await verify({...fixture.proof,fingerprint:"0".repeat(64)},opts),false);
  });
  await test("wrong trusted nonce rejected",async()=>{
    assert.equal(await verify(fixture.proof,{...opts,
      expectedNonce:"SYNTHETIC-OTHER-NONCE-01234567890"}),false);
  });
  await test("wrong pinned public key rejected",async()=>{
    assert.equal(await verify(fixture.proof,{...opts,
      pinnedPublicKeyHex:"ff".repeat(32)}),false);
  });
  await test("expired proof rejected",async()=>{
    assert.equal(await verify(fixture.proof,{...opts,
      now:fixture.proof.expires_at}),false);
  });
  await test("issuer fixture contains no credential material in signed output",async()=>{
    assert.ok(!JSON.stringify(fixture.proof).includes(fixture.candidate));
    assert.ok(!JSON.stringify(fixture).includes("PRIVATE KEY"));
  });
  console.log("SUMMARY",passed,"PASS, 0 FAIL");
})().catch(e=>{console.error("FAIL",e);process.exitCode=1});
