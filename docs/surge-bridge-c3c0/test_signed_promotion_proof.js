"use strict";
/* Synthetic-only Ed25519 proof adversarial tests; no phone/network/secrets. */
const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const {
  PURPOSE, payload, candidateFingerprint, validSignedProof
} = require("./signed_promotion_proof");
const {promote, DEV_KEYS} = require("./promotion_gate");
const TOKEN = "TEST-SYNTHETIC-CANDIDATE-0123456789ABCDEF";
const OTHER = "TEST-SYNTHETIC-OTHER-0123456789ABCDEF";
const OLD = "TEST-SYNTHETIC-OLD-0123456789ABCDEF";
const OLD_ID = "TEST-OLD-TOKEN-ID-001";
const NONCE = "TEST-ONE-TIME-NONCE-0123456789ABCDEF";
const {publicKey,privateKey} = crypto.generateKeyPairSync("ed25519");
const PUB = publicKey.export({type:"spki",format:"pem"});
const WRONG_PUB = crypto.generateKeyPairSync("ed25519").publicKey.export({
  type:"spki",format:"pem"
});

function signed(overrides={}) {
  const now = Date.now();
  const proof = Object.assign({
    purpose:PURPOSE,kind:"dev",ok:true,fingerprint_matches:true,
    token_id:"TEST-NEW-TOKEN-ID-002",
    fingerprint:candidateFingerprint(TOKEN),nonce:NONCE,
    issued_at:now,expires_at:now+60000
  },overrides);
  proof.signature = crypto.sign(null,Buffer.from(payload(proof)),privateKey).toString("base64");
  return proof;
}
function verify(proof,candidate=TOKEN,opts={}) {
  return validSignedProof(proof,Object.assign({
    candidate,oldTokenId:OLD_ID,expectedNonce:NONCE,
    kind:"dev",pinnedPublicKeyPem:PUB,
  },opts));
}
function store(candidate=TOKEN,active=OLD,lastStatus=null) {
  const map = new Map([[DEV_KEYS.activeKey,active]]);
  if(candidate!==null)map.set(DEV_KEYS.candidateKey,candidate);
  if(lastStatus!==null)map.set(DEV_KEYS.statusKey,lastStatus);
  const writes=[];
  return {map,writes,
    read:k=>map.has(k)?map.get(k):null,
    write:(v,k)=>{writes.push(k);map.set(k,v);return true;},
    remove:k=>{map.delete(k);return true;}
  };
}
let pass=0;
function test(name,fn){fn();pass++;console.log("PASS",name)}
test("signed candidate-bound proof accepted",()=>{
  assert.equal(verify(signed()),true);
});
test("self-asserted fingerprint_matches boolean without signature rejected",()=>{
  const p=signed();delete p.signature;
  assert.equal(verify(p),false);
});
test("signed proof for another candidate rejected",()=>{
  assert.equal(verify(signed(),OTHER),false);
});
test("tampering a signed fingerprint or status rejected",()=>{
  const p=signed();p.fingerprint=candidateFingerprint(OTHER);
  assert.equal(verify(p),false);
  const p2=signed();p2.fingerprint_matches=false;
  assert.equal(verify(p2),false);
});
test("wrong signing key rejected even when proof says matched",()=>{
  assert.equal(verify(signed(),TOKEN,{pinnedPublicKeyPem:WRONG_PUB}),false);
});
test("wrong or absent nonce rejected",()=>{
  assert.equal(verify(signed(),TOKEN,{expectedNonce:"TEST-OTHER-NONCE-0123456789"}),false);
  assert.equal(verify(signed(),TOKEN,{expectedNonce:null}),false);
});
test("old exposed token id rejected",()=>{
  assert.equal(verify(signed({token_id:OLD_ID})),false);
});
test("missing old-token identity fails closed even with a valid signature",()=>{
  assert.equal(verify(signed(),TOKEN,{oldTokenId:undefined}),false);
  assert.equal(verify(signed(),TOKEN,{oldTokenId:""}),false);
});
test("expired, too-old, future and non-integer proofs rejected",()=>{
  const now=Date.now();
  for (const p of [
    signed({expires_at:now-1}),
    signed({issued_at:now-26*3600000,expires_at:now+1000}),
    signed({issued_at:now+3600000,expires_at:now+3660000}),
    signed({issued_at:"now"}),
  ]) assert.equal(verify(p),false);
});
test("proof kind and purpose are domain-separated",()=>{
  assert.equal(verify(signed({kind:"localkey"})),false);
  assert.equal(verify(signed({purpose:"unrelated"})),false);
});
test("malformed signature or missing pinned public key rejected",()=>{
  const p=signed();p.signature="not-a-signature";
  assert.equal(verify(p),false);
  assert.equal(verify(signed(),TOKEN,{pinnedPublicKeyPem:null}),false);
});
test("promotion FAILS without verifiable proof and active token unchanged",()=>{
  const s=store();
  const p=signed();delete p.signature;
  const r=promote(s,{keys:DEV_KEYS,proof:p,oldTokenId:OLD_ID,
    expectedNonce:NONCE,pinnedPublicKeyPem:PUB});
  assert.deepEqual(r,{ok:false,status:"promotion_invalid_proof"});
  assert.equal(s.map.get(DEV_KEYS.activeKey),OLD);
  assert.equal(s.map.get(DEV_KEYS.candidateKey),TOKEN);
  assert.equal(s.writes.includes(DEV_KEYS.activeKey),false);
});
test("promotion with valid signed proof succeeds and clears candidate",()=>{
  const s=store();
  const r=promote(s,{keys:DEV_KEYS,proof:signed(),oldTokenId:OLD_ID,
    expectedNonce:NONCE,pinnedPublicKeyPem:PUB});
  assert.deepEqual(r,{ok:true,status:"promotion_done"});
  assert.equal(s.map.get(DEV_KEYS.activeKey),TOKEN);
  assert.equal(s.map.has(DEV_KEYS.candidateKey),false);
});
test("stale promotion_done marker cannot fabricate success when candidate absent",()=>{
  const s=store(null,OLD,"promotion_done");
  const r=promote(s,{keys:DEV_KEYS,proof:signed(),oldTokenId:OLD_ID,
    expectedNonce:NONCE,pinnedPublicKeyPem:PUB});
  assert.deepEqual(r,{ok:false,status:"promotion_no_candidate"});
  assert.equal(s.map.get(DEV_KEYS.activeKey),OLD);
});
test("wrong candidate with otherwise valid signed proof never changes active key",()=>{
  const s=store(OTHER,OLD);
  const r=promote(s,{keys:DEV_KEYS,proof:signed(),oldTokenId:OLD_ID,
    expectedNonce:NONCE,pinnedPublicKeyPem:PUB});
  assert.deepEqual(r,{ok:false,status:"promotion_invalid_proof"});
  assert.equal(s.map.get(DEV_KEYS.activeKey),OLD);
});
console.log("SUMMARY",pass,"PASS, 0 FAIL");
