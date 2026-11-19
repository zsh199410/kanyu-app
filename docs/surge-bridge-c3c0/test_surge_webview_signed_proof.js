"use strict";
/*
 * Executes ACTUAL WebView-compatible verifier under Node WebCrypto.
 * Ephemeral Ed25519 key pair generated per CI run; never production keys.
 * Tests use the exact Node canonical contract from PR #103.
 * No HTTP/Surge APIs are reachable in the VM.
 */
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const nodeCrypto = require("node:crypto");
const { PURPOSE, payload, candidateFingerprint } =
  require("./signed_promotion_proof");

const SRC = fs.readFileSync(path.join(__dirname,
  "surge_webview_signed_proof.js"), "utf8");
const {publicKey,privateKey} = nodeCrypto.generateKeyPairSync("ed25519");
const PUB_HEX = publicKey.export({format:"der",type:"spki"}).subarray(-32).toString("hex");
const WRONG_HEX = nodeCrypto.generateKeyPairSync("ed25519").publicKey
  .export({format:"der",type:"spki"}).subarray(-32).toString("hex");
const TOKEN = "TEST-NEW-DEV-CANDIDATE-0123456789ABCDEF";
const LOCAL_KEY = "TEST-NEW-LOCALKEY-CANDIDATE-0123456789ABCD";
const OTHER = "TEST-UNRELATED-CANDIDATE-0123456789ABCDEF";
const OLD_ID = "TEST-OLD-ID-001";
const NEW_ID = "TEST-NEW-ID-002";
const NONCE = "TEST-UNIQUE-CHALLENGE-0123456789ABCDEF";
const NOW = 1800000000000;

function createProof(overrides={}) {
  const p = Object.assign({
    purpose: PURPOSE, kind:"dev", ok:true, fingerprint_matches:true,
    token_id: NEW_ID, fingerprint:candidateFingerprint(TOKEN),
    nonce:NONCE, issued_at:NOW, expires_at:NOW+60000,
  }, overrides);
  p.signature = nodeCrypto.sign(
    null, Buffer.from(payload(p),"utf8"),privateKey).toString("base64");
  return p;
}
function loadRuntime({crypto=nodeCrypto.webcrypto,
                      encoder=TextEncoder, decode=atob}={}) {
  const module = {exports:{}};
  let network=0, write=0, logs=0;
  vm.runInNewContext(SRC,{
    module,
    crypto,
    TextEncoder:encoder,
    atob:decode,
    $persistentStore:{read:()=>{write++},write:()=>{write++}},
    $httpClient:{get:()=>network++,post:()=>network++},
    $httpAPI:()=>network++,
    console:{log:()=>logs++,error:()=>logs++},
  },{timeout:1000});
  return {api:module.exports,counts:()=>({network,write,logs})};
}
const DEFAULT_OPTS = {
  candidate:TOKEN,kind:"dev",oldTokenId:OLD_ID,
  expectedNonce:NONCE,pinnedPublicKeyHex:PUB_HEX,now:NOW,
};
const real=loadRuntime();
const v=(p,o={})=>real.api.verifySignedPromotionProof(p,{...DEFAULT_OPTS,...o});
let pass=0,limitations=0;
async function test(name,fn) {
  await fn();
  console.log("PASS",name);
  pass++;
}
(async()=>{
  await test("genuine Node Ed25519 signature verifies under browser WebCrypto", async()=>{
    assert.equal(await v(createProof()),true);
  });
  await test("canonical bytes exactly match PR103 Node reference", async()=>{
    const p=createProof();
    assert.equal(real.api.canonicalJson(p),payload(p));
  });
  await test("missing signature rejected",async()=>{
    const p=createProof();delete p.signature;
    assert.equal(await v(p),false);
  });
  await test("corrupted signature rejected",async()=>{
    const p=createProof();p.signature=(p.signature[0]==="A"?"B":"A")+p.signature.slice(1);
    assert.equal(await v(p),false);
  });
  await test("wrong trust root rejected",async()=>{
    assert.equal(await v(createProof(),{pinnedPublicKeyHex:WRONG_HEX}),false);
    assert.equal(await v(createProof(),{pinnedPublicKeyHex:null}),false);
  });
  await test("valid signed proof for other candidate rejected",async()=>{
    assert.equal(await v(createProof(),{candidate:OTHER}),false);
  });
  await test("valid signed proof for wrong nonce rejected",async()=>{
    assert.equal(await v(createProof(),{expectedNonce:"WRONG-EXPECTED-NONCE-987654321"}),false);
    assert.equal(await v(createProof(),{expectedNonce:undefined}),false);
  });
  await test("reject proof for old exposed ID or unknown old-ID policy",async()=>{
    assert.equal(await v(createProof({token_id:OLD_ID})),false);
    assert.equal(await v(createProof(),{oldTokenId:undefined}),false);
  });
  await test("reject signed kind and purpose mismatches",async()=>{
    assert.equal(await v(createProof({kind:"localkey"})),false);
    assert.equal(await v(createProof({purpose:"some-other-purpose"})),false);
  });
  await test("local key verified only against its own signed digest and domain",async()=>{
    const p=createProof({kind:"localkey",fingerprint:candidateFingerprint(LOCAL_KEY)});
    assert.equal(await v(p,{kind:"localkey",candidate:LOCAL_KEY}),true);
    assert.equal(await v(p,{kind:"dev",candidate:LOCAL_KEY}),false);
  });
  await test("expired, stale, future and overly long-lived signed proof refused",async()=>{
    const bad=[
      createProof({expires_at:NOW-1}),
      createProof({issued_at:NOW-25*3600000,expires_at:NOW+1000}),
      createProof({issued_at:NOW+3600000,expires_at:NOW+3660000}),
      createProof({issued_at:NOW,expires_at:NOW+25*3600000}),
    ];
    for(const p of bad)assert.equal(await v(p),false);
  });
  await test("malformed timestamp and signature rejected",async()=>{
    const bad=createProof({issued_at:"not-time"});
    assert.equal(await v(bad),false);
    const sig=createProof();sig.signature="bad";
    assert.equal(await v(sig),false);
  });
  await test("malformed candidate tokens refused",async()=>{
    for(const c of ["","short","<FAKE_PLACEHOLDER_0123456789012345>","x".repeat(257),
                    "valid-length-with-newline-01234567\nend"]) {
      assert.equal(await v(createProof(),{candidate:c}),false);
    }
  });
  await test("WebCrypto absent fails closed",async()=>{
    const r=loadRuntime({crypto:null});
    assert.equal(await r.api.verifySignedPromotionProof(createProof(),DEFAULT_OPTS),false);
  });
  await test("TextEncoder absent fails closed",async()=>{
    const r=loadRuntime({encoder:null});
    assert.equal(await r.api.verifySignedPromotionProof(createProof(),DEFAULT_OPTS),false);
  });
  await test("atob absent fails closed",async()=>{
    const r=loadRuntime({decode:null});
    assert.equal(await r.api.verifySignedPromotionProof(createProof(),DEFAULT_OPTS),false);
  });
  await test("signature data with valid base64 shape but wrong contents rejected",async()=>{
    const p=createProof();p.signature=Buffer.alloc(64,7).toString("base64");
    assert.equal(await v(p),false);
  });
  await test("does not expose side-effect or secret APIs",async()=>{
    assert.deepEqual(real.counts(),{network:0,write:0,logs:0});
    assert.ok(!/\b(require|fetch|XMLHttpRequest)\s*\(/.test(SRC));
    assert.ok(!/\$persistentStore|\$httpClient|\$httpAPI|console\.log/.test(SRC));
  });
  await test("documentation limitation: same signed proof passes twice with reused trusted nonce",async()=>{
    // This is NOT a security success: the verifier is intentionally
    // stateless. Production must durably consume nonce before promotion.
    const p=createProof();
    assert.equal(await v(p),true);
    assert.equal(await v(p),true);
    limitations++;
  });
  console.log("SUMMARY",pass,"PASS, 0 FAIL,",limitations,"KNOWN LIMITATION");
})().catch(e=>{console.error("FAIL",e);process.exitCode=1});
