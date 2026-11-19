"use strict";
/* Cross-language real proof bytes, no real token/network/key. */
const assert=require("node:assert/strict");
const cp=require("node:child_process");
const fs=require("node:fs");
const path=require("node:path");
const vm=require("node:vm");
const root=__dirname;
const fixture=JSON.parse(cp.execFileSync("python3",[
  path.join(root,"test_signed_proof_interop_fixture.py")
],{cwd:root,encoding:"utf8",timeout:15000,maxBuffer:100000}));
const src=fs.readFileSync(path.join(root,"surge_webview_signed_proof.js"),"utf8");
const {webcrypto}=require("node:crypto");
const sandbox={crypto:webcrypto,TextEncoder,atob,module:{exports:{}}};
vm.runInNewContext(src,sandbox,{timeout:2000});
const verify=sandbox.module.exports.verifySignedPromotionProof;
let count=0;
async function test(name,fn){await fn();count++;console.log("PASS",name)}
const opts={
 candidate:fixture.candidate,kind:"dev",oldTokenId:fixture.oldId,
 expectedNonce:fixture.nonce,pinnedPublicKeyHex:fixture.publicHex,
 now:fixture.now
};
(async()=>{
 await test("Python issuer signature verifies with actual WebCrypto library",async()=>{
   assert.equal(await verify(fixture.proof,opts),true);
 });
 await test("python-issued proof has strict signed canonical field order",async()=>{
   const x=Object.keys(fixture.proof);
   assert.deepEqual(x,["purpose","kind","ok","fingerprint_matches","token_id",
     "fingerprint","nonce","issued_at","expires_at","signature"]);
 });
 await test("proof replay against distinct expected nonce is rejected",async()=>{
   assert.equal(await verify(fixture.proof,{...opts,expectedNonce:"ANOTHER-TRUSTED-NONCE-0123456789"}),false);
 });
 await test("proof for another candidate rejected",async()=>{
   assert.equal(await verify(fixture.proof,{...opts,candidate:"TEST-OTHER-CANDIDATE-0123456789ABCD"}),false);
 });
 await test("tampering signed token identity rejected",async()=>{
   const p={...fixture.proof,token_id:"TAMPERED"};
   assert.equal(await verify(p,opts),false);
 });
 await test("signer key pin is independent of proof; missing key rejected",async()=>{
   assert.equal(await verify(fixture.proof,{...opts,pinnedPublicKeyHex:null}),false);
 });
 await test("cross-language signer exposes no private key or actual token",async()=>{
   const x=JSON.stringify(fixture.proof);
   assert.ok(!x.includes(fixture.candidate));
   assert.ok(!x.includes("PRIVATE KEY"));
 });
 console.log("SUMMARY",count,"PASS, 0 FAIL");
})().catch(e=>{console.error("FAIL",e);process.exitCode=1});
