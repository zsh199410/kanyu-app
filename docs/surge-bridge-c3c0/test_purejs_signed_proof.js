"use strict";
/* Issue #73: actual pinned pure-JS vendor sources + verifier in a sandbox
 * with crypto.subtle MISSING and isSecureContext=false. Fake credentials,
 * freshly generated Ed25519 keys only. Synthetic CI, NOT an iPhone pass.
 */
const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");
const path = require("node:path");
const nodeCrypto = require("node:crypto");
const dir = __dirname;
function read(file) { return fs.readFileSync(path.join(dir,file),"utf8"); }
const naclSrc = read("vendor/tweetnacl-fast-1.0.3.js");
const shaSrc = read("vendor/js-sha256-1.0.0.js");
const verifierSrc = read("surge_purejs_signed_proof.review.js");
const now = 1790000000000;
function newRuntime() {
  let network=0, writes=0, logs=0;
  const ctx = vm.createContext({
    TextEncoder,
    atob: s=>Buffer.from(s,"base64").toString("binary"),
    $persistentStore:{read:()=>{writes++;throw Error("unexpected read");},
                      write:()=>{writes++;throw Error("unexpected write");}},
    $httpClient:{get:()=>network++,post:()=>network++},
    $httpAPI:()=>network++,
    fetch:()=>network++,
    console:{log:()=>logs++,error:()=>logs++},
    $done:()=>{throw Error("unexpected execution");},
  });
  vm.runInContext("self=globalThis; isSecureContext=false; crypto={};",ctx);
  vm.runInContext(naclSrc,ctx,{timeout:3000});
  vm.runInContext(shaSrc,ctx,{timeout:3000});
  vm.runInContext(verifierSrc,ctx,{timeout:3000});
  assert.equal(typeof ctx.sgbridgeVerifySignedProofPureJs,"function");
  assert.equal(typeof ctx.nacl.sign.detached.verify,"function");
  assert.equal(typeof ctx.sha256,"function");
  assert.equal(ctx.isSecureContext,false);
  assert.equal(typeof ctx.crypto.subtle,"undefined");
  function check(proof,opts){
    ctx.__proof = proof;
    ctx.__opts = opts;
    const result=vm.runInContext("sgbridgeVerifySignedProofPureJs(__proof,__opts)",ctx,{timeout:3000});
    assert.equal(network,0,"no network");
    assert.equal(writes,0,"no store I/O");
    assert.equal(logs,0,"no logs");
    return result;
  }
  return {ctx,check};
}
function fixture() {
  const kp=nodeCrypto.generateKeyPairSync("ed25519");
  const candidate="TEST-NEW-TOKEN-0123456789ABCDEFabcdef9876543210";
  const opts={
    candidate,
    oldTokenId:"TEST-OLD-ID",
    expectedNonce:"TEST-UNIQUE-CHALLENGE-0123456789ABCDEF",
    pinnedPublicKeyHex:kp.publicKey.export({type:"spki",format:"der"}).subarray(-32).toString("hex"),
    kind:"dev",
    now,
  };
  const proof={
    purpose:"issue73/credential-promotion/v1",
    kind:"dev",ok:true,fingerprint_matches:true,
    token_id:"TEST-NEW-ID",
    fingerprint:nodeCrypto.createHash("sha256").update(candidate).digest("hex"),
    nonce:opts.expectedNonce,
    issued_at:now-1000,
    expires_at:now+60000,
  };
  const canonical=JSON.stringify({
    purpose:proof.purpose,kind:proof.kind,ok:proof.ok,
    fingerprint_matches:proof.fingerprint_matches,
    token_id:proof.token_id,fingerprint:proof.fingerprint,
    nonce:proof.nonce,issued_at:proof.issued_at,
    expires_at:proof.expires_at,
  });
  proof.signature=nodeCrypto.sign(null,Buffer.from(canonical,"utf8"),kp.privateKey).toString("base64");
  return {proof,opts,canonical};
}
let pass=0;
function test(name,fn){fn();pass++;console.log("PASS",name);}
function mutated(original,patch){return Object.assign({},original,patch);}
const {proof,opts,canonical}=fixture();
const rt=newRuntime();
test("insecure WebView context has NO crypto.subtle but both offline primitives loaded",()=>{
  assert.equal(typeof rt.ctx.crypto.subtle,"undefined");
  assert.equal(rt.ctx.isSecureContext,false);
});
test("real Node Ed25519 signature verified via independent pure JS TweetNaCl",()=>{
  assert.equal(rt.check(proof,opts),true);
});
test("canonical JSON is byte-compatible with signed proof issuer",()=>{
  assert.equal(rt.ctx.sgbridgeCanonicalProofJsonPureJs(proof),canonical);
});
test("local SHA256 empty-string known vector",()=>{
  assert.equal(rt.ctx.sha256(""),"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
});
test("corrupted Ed25519 signature rejected",()=>{
  const p=mutated(proof,{signature:proof.signature.replace(/^./, proof.signature[0]==="A"?"B":"A")});
  assert.equal(rt.check(p,opts),false);
});
test("signature of wrong key rejected",()=>{
  const other=fixture();
  assert.equal(rt.check(proof,mutated(opts,{pinnedPublicKeyHex:other.opts.pinnedPublicKeyHex})),false);
});
test("changed candidate rejected by fingerprint binding",()=>{
  assert.equal(rt.check(proof,mutated(opts,{candidate:"TEST-DIFFERENT-NEW-TOKEN-0123456789ABCDEFG"})),false);
});
test("changed fingerprint rejected",()=>{
  assert.equal(rt.check(mutated(proof,{fingerprint:"0".repeat(64)}),opts),false);
});
test("wrong trusted nonce rejected",()=>{
  assert.equal(rt.check(proof,mutated(opts,{expectedNonce:"TEST-DIFFERENT-NONCE-0123456789ABCDEF"})),false);
});
test("tampered signed nonce rejected",()=>{
  assert.equal(rt.check(mutated(proof,{nonce:"TEST-DIFFERENT-NONCE-0123456789ABCDEF"}),opts),false);
});
test("old token id cannot be reused",()=>{
  assert.equal(rt.check(mutated(proof,{token_id:opts.oldTokenId}),opts),false);
});
test("unauthenticated success boolean cannot substitute signature",()=>{
  assert.equal(rt.check(mutated(proof,{signature:null}),opts),false);
  assert.equal(rt.check(mutated(proof,{signature:"A".repeat(86)+"=="}),opts),false);
});
test("expired signed proof rejected",()=>{
  assert.equal(rt.check(proof,mutated(opts,{now:now+120000})),false);
});
test("future issued proof rejected",()=>{
  assert.equal(rt.check(proof,mutated(opts,{now:now-600000})),false);
});
test("wrong purpose/domain rejected",()=>{
  assert.equal(rt.check(mutated(proof,{purpose:"other"}),opts),false);
});
test("different credential kind rejected",()=>{
  assert.equal(rt.check(proof,mutated(opts,{kind:"localkey"})),false);
});
test("invalid trusted inputs fail closed",()=>{
  assert.equal(rt.check(proof,mutated(opts,{oldTokenId:""})),false);
  assert.equal(rt.check(proof,mutated(opts,{expectedNonce:"short"})),false);
  assert.equal(rt.check(proof,mutated(opts,{candidate:"<placeholder>"})),false);
  assert.equal(rt.check(proof,mutated(opts,{pinnedPublicKeyHex:"broken"})),false);
});
test("missing TextEncoder refuses to verify",()=>{
  const saved=rt.ctx.TextEncoder;rt.ctx.TextEncoder=undefined;
  assert.equal(rt.check(proof,opts),false);rt.ctx.TextEncoder=saved;
});
test("missing SHA256 refuses to verify",()=>{
  const saved=rt.ctx.sha256;rt.ctx.sha256=undefined;
  assert.equal(rt.check(proof,opts),false);rt.ctx.sha256=saved;
});
test("missing NaCl refuses to verify",()=>{
  const saved=rt.ctx.nacl;rt.ctx.nacl=undefined;
  assert.equal(rt.check(proof,opts),false);rt.ctx.nacl=saved;
});
test("missing atob refuses to verify",()=>{
  const saved=rt.ctx.atob;rt.ctx.atob=undefined;
  assert.equal(rt.check(proof,opts),false);rt.ctx.atob=saved;
});
test("stateless replay limitation EXPLICIT: same valid proof verifies twice",()=>{
  assert.equal(rt.check(proof,opts),true);
  assert.equal(rt.check(proof,opts),true);
  // This is NOT a positive replay security test: a durable consumed nonce
  // gate is mandatory before enabling credential promotion.
});
test("no network, credential writes, remote CDN, auto-run or device control in wrapper",()=>{
  assert.ok(!/\b(?:fetch|XMLHttpRequest|eval|Function)\s*\(/.test(verifierSrc));
  assert.ok(!/\$persistentStore|\$httpClient|\$httpAPI|\$done\s*\(|console\.log/.test(verifierSrc));
  assert.ok(!/https?:\/\//.test(verifierSrc));
});
console.log("SUMMARY",pass,"PASS, 0 FAIL, 1 KNOWN LIMITATION: stateless replay");
