"use strict";
/* S1 independent actual-script tests; all credentials synthetic, no network. */
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { MockMailbox, runScript } = require("./simulator");
const source = fs.readFileSync(path.join(__dirname,"bridge_fixed_v2.js"),"utf8");
const OLD = 1795063030, LAST = "1795055213880", NEW = 1795063031001;
const DEV = "TEST-DEV-ROTATED-ONLY";
const KEY = "TEST-LOCAL-MOCK-ONLY";

async function play({dev, key, command, cfg = {}, ledger} = {}) {
  const store = new Map([["sgbridge_last_id", LAST]]);
  if(dev !== undefined) store.set("sgbridge_cred_dev", dev);
  if(key !== undefined) store.set("sgbridge_cred_localkey", key);
  if(ledger) store.set("sgbridge_ledger_v1",JSON.stringify(ledger));
  const mailbox = new MockMailbox();
  if(command) mailbox.setCmd(command);
  const o=await runScript(source, { ...cfg, injectCredentials: false },
    { shared:{store,mailbox},watchdogMs:3000 });
  assert.equal(o.doneCalls, 1, "single done");
  assert.equal(o.hung,false,"no deadlock");
  return {o,store,mailbox};
}
function writes(o,k) {return o.storeWrites.filter(x=>x.key===k).length}
function calls(o,path) {return o.httpCalls.filter(x=>x.path===path).length}
async function main(){
  let n=0; const test=async(name,f)=>{await f();n++;console.log("PASS",name)};
  await test("public v2.1 contains no embedded reusable token/key",()=>{
    assert.doesNotMatch(source,/const DEV\s*=\s*["']/);
    assert.doesNotMatch(source,/const APIKEY\s*=\s*["']/);
    assert.match(source,/sgbridge_cred_dev/);
    assert.match(source,/sgbridge_cred_localkey/);
  });
  await test("no device token -> no network, dispatch, result or legacy writes",async()=>{
    const {o}=await play({command:{id:NEW,actions:[{type:"notify",text:"x"}]}});
    assert.equal(o.httpCalls.length,0);
    assert.equal(o.dispatches,0);
    assert.equal(writes(o,"sgbridge_last_id"),0);
    assert.equal(calls(o,"/result"),0);
    assert.ok(o.phases.some(x=>x.phase==="credential_missing"));
  });
  await test("empty token -> strict fail closed",async()=>{
    const {o}=await play({dev:"",command:{id:NEW,actions:[]}});
    assert.equal(o.httpCalls.length,0);
  });
  await test("storage read throws -> strict fail closed",async()=>{
    const {o}=await play({dev:DEV,cfg:{storeReadThrows:true},command:{id:NEW,actions:[]}});
    assert.equal(o.httpCalls.length,0);
    assert.equal(o.dispatches,0);
  });
  await test("403 never dispatches or sends result",async()=>{
    const {o}=await play({dev:DEV,cfg:{pollOverride:{status:403,body:"forbidden"}},
      command:{id:NEW,actions:[{type:"notify",text:"x"}]}});
    assert.equal(calls(o,"/poll"),1);
    assert.equal(calls(o,"/result"),0);
    assert.equal(o.dispatches,0);
    assert.ok(o.phases.some(x=>x.phase==="auth_forbidden"));
  });
  await test("valid token + native API -> GET and strict ACK with absent local key",async()=>{
    const {o}=await play({dev:DEV,ledger:{version:1,floor:Number(LAST),last_acked_id:0,pending:null},
      command:{id:NEW,actions:[{type:"api",method:"GET",path:"/v1/test"}]}});
    assert.equal(o.dispatches,1);
    assert.equal(calls(o,"/result"),1);
    assert.equal(writes(o,"sgbridge_last_id"),1);
    assert.equal(o.httpCalls.some(x=>x.path==="/v1/test"),false);
  });
  await test("missing local key + $httpAPI absent -> no localhost HTTP",async()=>{
    const {o}=await play({dev:DEV,cfg:{httpApi:"undefined"},ledger:{version:1,floor:Number(LAST),last_acked_id:0,pending:null},
      command:{id:NEW,actions:[{type:"api",method:"GET",path:"/v1/test"}]}});
    assert.equal(o.dispatches,0);
    assert.equal(o.httpCalls.some(x=>String(x.path).includes("127.0.0.1")||x.path==="/v1/test"),false);
    assert.ok(o.phases.some(x=>x.phase==="local_key_missing"));
  });
  await test("missing local key + MCP action -> no localhost call",async()=>{
    const {o}=await play({dev:DEV,ledger:{version:1,floor:Number(LAST),last_acked_id:0,pending:null},
      command:{id:NEW,actions:[{type:"mcp",tool:"synthetic.read"}]}});
    assert.equal(o.dispatches,0);
    assert.equal(calls(o,"/result"),1);
    assert.ok(o.phases.some(x=>x.phase==="local_key_missing"));
  });
  await test("old command still fenced with new credential",async()=>{
    const {o}=await play({dev:DEV,command:{id:OLD,actions:[{type:"notify",text:"old"}]}});
    assert.equal(o.dispatches,0);
    assert.equal(calls(o,"/result"),0);
    assert.equal(writes(o,"sgbridge_last_id"),0);
    assert.ok(o.phases.some(x=>x.phase==="legacy_fenced"));
  });
  await test("403 cannot resend cached result_ready",async()=>{
    const cached={id:NEW,timestamp:1795063100,outputs:[]};
    const {o}=await play({dev:DEV,cfg:{pollOverride:{status:403,body:"blocked"}},
      ledger:{version:1,floor:Number(LAST),last_acked_id:0,pending:{id:NEW,phase:"result_ready",result:cached}}});
    assert.equal(calls(o,"/result"),0);
    assert.equal(o.dispatches,0);
  });
  console.log("SUMMARY",n,"PASS 0 FAIL");
}
main().catch(e=>{console.error(e.stack||e);process.exitCode=1});
