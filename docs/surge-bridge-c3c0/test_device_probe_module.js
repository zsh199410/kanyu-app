"use strict";
/* Issue #73: execute actual status-panel source in isolated VM.
 * Source-free module static contract checks; no real Surge device.
 */
const assert=require("node:assert/strict");
const fs=require("node:fs");
const vm=require("node:vm");
const path=require("node:path");
const here=__dirname;
const SRC=fs.readFileSync(path.join(here,"surge_webview_crypto_status.js"),"utf8");
const MODULE=fs.readFileSync(path.join(here,"issue73_webcrypto_readonly.sgmodule"),"utf8");
let pass=0;
function test(name,fn){fn();pass++;console.log("PASS",name)}
function evalPanel(value,throws=false){
  const data=[];const reads=[];const writes=[];const calls=[];
  vm.runInNewContext(SRC,{
    $persistentStore:{
      read:key=>{reads.push(key);if(throws)throw Error("synthetic failed read");return value;},
      write:(...args)=>writes.push(args)
    },
    $httpClient:{get:()=>calls.push("get"),post:()=>calls.push("post")},
    $notification:{post:()=>calls.push("notify")},
    $done:r=>data.push(r)
  },{timeout:500});
  assert.equal(data.length,1);
  assert.equal(reads.length,1);
  assert.equal(reads[0],"sgbridge_webcrypto_probe_status");
  assert.equal(writes.length,0);
  assert.equal(calls.length,0);
  return data[0];
}
test("status panel shows crypto_ready but not production approval",()=>{
 const p=evalPanel("crypto_ready");assert.match(p.content,/crypto_ready/);
 assert.match(p.content,/NOT release approval/);assert.equal(p.style,"info");
});
test("missing enum returns not_run and never reads token",()=>{
 const p=evalPanel(null);assert.match(p.content,/not_run/);assert.equal(p.style,"alert");
});
test("arbitrary status string never displayed or logged",()=>{
 const secret="TEST-FAKE-SECRET-01234567890123456789";
 const p=evalPanel(secret);
 assert.match(p.content,/invalid_status/);assert.ok(!JSON.stringify(p).includes(secret));
});
test("store read failure yields nonsensitive status",()=>{
 const p=evalPanel(null,true);assert.match(p.content,/status_read_error/);
});
test("all ten published probe enums render harmlessly",()=>{
 const types=[
 "crypto_ready","no_webcrypto","no_text_encoder","sha256_failed",
 "base64_unavailable","base64_failed","ed25519_unavailable",
 "signature_failed","random_unavailable","probe_error"];
 for(const v of types){const p=evalPanel(v);assert.ok(p.content.startsWith(v+" — "));}
});
test("module only adds scripts and a panel, not networking policy",()=>{
 assert.ok(!/^\[(?:General|Rule|Proxy|Proxy Group|MITM|URL Rewrite|Host|Map Local|Cron)\]/mi.test(MODULE));
 assert.match(MODULE,/\[Script\]/);
 assert.match(MODULE,/\[Panel\]/);
 assert.ok(!/update-interval|type=cron|type=event/i.test(MODULE));
});
test("module source URLs are pinned immutable SHAs and two only",()=>{
 const urls=[...MODULE.matchAll(/script-path=(https:\/\/\S+)/g)].map(x=>x[1].split(",")[0]);
 assert.equal(urls.length,2);
 assert.ok(urls.every(u=>/^https:\/\/raw\.githubusercontent\.com\/zsh199410\/kanyu-app\/[a-f0-9]{40}\/docs\/surge-bridge-c3c0\/\S+\.js$/.test(u)));
 assert.match(MODULE,/engine=webview/);
});
test("script and module contain no token/nonce input or device-control API",()=>{
 assert.ok(!/\$httpClient|\$httpAPI|\$surge|console\.log|fetch\s*\(/.test(SRC));
 assert.ok(!/Authorization\s*:|X-Dev-Token|PRIVATE KEY|__PROMOTED__/.test(SRC+MODULE));
});
console.log("SUMMARY",pass,"PASS, 0 FAIL");
