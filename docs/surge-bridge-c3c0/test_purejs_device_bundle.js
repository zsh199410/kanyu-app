"use strict";
/* Actual reproducible bundled sources in nonsecure VM: NO phone/real keys. */
const assert=require("node:assert/strict");
const fs=require("node:fs");
const path=require("node:path");
const vm=require("node:vm");
const dir=__dirname;
const BUNDLE=fs.readFileSync(path.join(dir,"issue73_purejs_probe_bundled.js"),"utf8");
const PANEL=fs.readFileSync(path.join(dir,"issue73_purejs_status.js"),"utf8");
const MODULE=fs.readFileSync(path.join(dir,"issue73_purejs_readonly.sgmodule"),"utf8");
const KEY="sgbridge_purejs_probe_status";
function run(trigger="editor",withEncoder=true,withAtob=true,writeOK=true){
  const state=new Map([["TEST-ACTIVE-CREDENTIAL","keep-unchanged"]]);
  let writes=[],reads=[],network=0,notifications=0,logs=0,done=0;
  const ctx=vm.createContext({
    $trigger:trigger,
    TextEncoder:withEncoder?TextEncoder:undefined,
    atob:withAtob?(v=>Buffer.from(v,"base64").toString("binary")):undefined,
    $persistentStore:{
      read:k=>{reads.push(k);return state.get(k)||null;},
      write:(v,k)=>{writes.push({v,k});if(writeOK)state.set(k,v);return writeOK;}
    },
    $httpClient:{get:()=>network++,post:()=>network++},
    $httpAPI:()=>network++,
    fetch:()=>network++,
    console:{log:()=>logs++,error:()=>logs++},
    $notification:{post:()=>notifications++},
    $done:()=>done++
  });
  vm.runInContext("self=globalThis;isSecureContext=false;crypto={};",ctx);
  vm.runInContext(BUNDLE,ctx,{timeout:6000});
  assert.equal(network,0);assert.equal(notifications,0);assert.equal(logs,0);
  assert.equal(reads.length,0);
  assert.equal(done,1);
  assert.equal(state.get("TEST-ACTIVE-CREDENTIAL"),"keep-unchanged");
  assert.ok(writes.every(x=>x.k===KEY));
  return {status:state.get(KEY)||null,writes};
}
function panel(value){
  const report=[],reads=[],writes=[],network=[];
  const ctx=vm.createContext({
    $persistentStore:{read:k=>{reads.push(k);return value;},
                      write:()=>writes.push(1)},
    $httpClient:{get:()=>network.push(1)},
    $done:r=>report.push(r)
  });
  vm.runInContext(PANEL,ctx,{timeout:1000});
  assert.deepEqual(reads,[KEY]);
  assert.equal(writes.length,0);assert.equal(network.length,0);
  assert.equal(report.length,1);
  return report[0];
}
let pass=0;
function test(name,fn){fn();pass++;console.log("PASS",name);}
test("real bundle verifies public signed proof in isSecureContext=false without subtle",()=>{
  const r=run();
  assert.equal(r.status,"purejs_verify_ready");
  assert.equal(r.writes.length,1);
});
test("intent manually triggered script also verifies",()=>{
  assert.equal(run("intent").status,"purejs_verify_ready");
});
test("cron trigger rejected without any write",()=>{
  const r=run("cron");
  assert.equal(r.status,null);assert.equal(r.writes.length,0);
});
test("panel trigger rejected without write",()=>{
  const r=run("button");
  assert.equal(r.status,null);assert.equal(r.writes.length,0);
});
test("missing TextEncoder fails closed",()=>{
  assert.equal(run("editor",false).status,"text_encoder_missing");
});
test("missing base64 decoder fails closed",()=>{
  assert.equal(run("editor",true,false).status,"base64_missing");
});
test("persistent store failure does not attempt a second write or action",()=>{
  assert.equal(run("editor",true,true,false).writes.length,1);
});
test("panel correctly displays verified-but-not-release status",()=>{
  const p=panel("purejs_verify_ready");
  assert.match(p.content,/NOT release approval/);
  assert.equal(p.style,"info");
});
test("panel never leaks arbitrary fake secret input",()=>{
  const fake="TEST-FAKE-SECRET-AABBCC";
  const p=panel(fake);
  assert.match(p.content,/invalid_status/);
  assert.ok(!JSON.stringify(p).includes(fake));
});
test("module contains only manual generic scripts with SHA-pinned source",()=>{
  assert.ok(!/^\[(?:General|Rule|Proxy|Proxy Group|MITM|URL Rewrite|Host|Map Local|Cron)\]/mi.test(MODULE));
  assert.ok(!/type=cron|type=event|update-interval/i.test(MODULE));
  const paths=[...MODULE.matchAll(/script-path=(https:\/\/[^,]+)/g)].map(v=>v[1]);
  assert.equal(paths.length,2);
  for(const p of paths) assert.match(p,/^https:\/\/raw\.githubusercontent\.com\/zsh199410\/kanyu-app\/[a-f0-9]{40}\/docs\/surge-bridge-c3c0\/issue73_purejs_[^,]+\.js$/);
  assert.match(MODULE,/engine=webview/);
});
test("no token or private endpoint in manual probe body",()=>{
  const body=fs.readFileSync(path.join(dir,"issue73_purejs_probe_body.js"),"utf8");
  assert.ok(!/\$httpClient|\$httpAPI|\$surge|fetch\s*\(/.test(body));
  assert.ok(!/https?:\/\//.test(body));
  assert.ok(!/Authorization:|X-Dev-Token|PRIVATE KEY/.test(body));
});
console.log("SUMMARY",pass,"PASS, 0 FAIL (synthetic only)");
