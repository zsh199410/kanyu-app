"use strict";
/* S1 bootstrap adversarial, synthetic-only. Never uses phone or network. */
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const src = fs.readFileSync(path.join(__dirname,
  "bootstrap_candidate_shortcuts.template.js"), "utf8");
const STAGED = "sgbridge_cred_dev_candidate";
const ACTIVE = "sgbridge_cred_dev";
const STATUS = "sgbridge_cred_bootstrap_status";
const TOKEN = "TEST-NEW-DEV-CANDIDATE-0123456789ABCDEF";
const OTHER = "TEST-OTHER-DEV-CANDIDATE-0123456789ABC";
const OLD = "TEST-ACTIVE-OLD-DEV-0123456789ABCDEF";

function run({trigger="intent", parameter=TOKEN, preload={},
               falseCandidate=false, throwRead=false,
               writeThenFalse=false, corruptReadback=false}={}){
  const store = new Map(Object.entries(preload));
  let done=0, network=0, writes=[], logs=[];
  let candidateWrites=0;
  const sandbox={
    $trigger:trigger,
    $intent:{parameter},
    $persistentStore:{
      read:(k)=>{
        if (throwRead && k===STAGED) throw Error("synthetic secret read error");
        if (corruptReadback && k===STAGED && candidateWrites) return "mismatch";
        return store.has(k) ? store.get(k) : null;
      },
      write:(value,k)=>{
        writes.push({key:k, valueKind:typeof value});
        if(k===STAGED){
          candidateWrites++;
          if(falseCandidate){
            if(writeThenFalse) store.set(k,value);
            return false;
          }
        }
        store.set(k,value);
        return true;
      },
    },
    $httpClient:{get:()=>{network++},post:()=>{network++}},
    $httpAPI:()=>{network++},
    console:{log:(...x)=>{logs.push(x.join(" "))},
             error:(...x)=>{logs.push(x.join(" "))}},
    $done:()=>{done++},
  };
  vm.runInNewContext(src,sandbox,{timeout:1000});
  return {store,writes,logs,network,done,candidateWrites};
}
let count=0;
function check(name, fn){
  fn(); count++; console.log("PASS", name);
}
check("source does not embed raw token, network API calls or self-delete",()=>{
  assert.equal(src.includes(TOKEN),false);
  assert.equal(src.includes(OLD),false);
  assert.equal(src.includes("$httpClient."),false);
  assert.equal(src.includes("$httpAPI("),false);
  assert.equal(src.includes("self-delete()"),false);
});
check("editor trigger: zero state changes",()=>{
  const r=run({trigger:"editor"});
  assert.equal(r.writes.length,0);
  assert.equal(r.done,1);
});
check("HTTP API trigger: zero state changes",()=>{
  const r=run({trigger:"http-api"});
  assert.equal(r.writes.length,0);
});
check("cron trigger: zero state changes",()=>{
  const r=run({trigger:undefined});
  assert.equal(r.writes.length,0);
});
check("invalid / empty candidate never staged",()=>{
  for(const parameter of ["", "short", "test\nTOKEN", null, 123]){
    const r=run({parameter});
    assert.equal(r.candidateWrites,0);
    assert.equal(r.store.get(STATUS),"invalid_parameter");
  }
});
check("valid candidate stages without modifying active token",()=>{
  const r=run({preload:{[ACTIVE]:OLD}});
  assert.equal(r.store.get(STAGED),TOKEN);
  assert.equal(r.store.get(ACTIVE),OLD);
  assert.equal(r.store.get(STATUS),"candidate_staged");
  assert.equal(r.done,1);
});
check("existing candidate with same value is idempotent",()=>{
  const r=run({preload:{[STAGED]:TOKEN,[ACTIVE]:OLD}});
  assert.equal(r.candidateWrites,0);
  assert.equal(r.store.get(STATUS),"candidate_already_staged");
  assert.equal(r.store.get(ACTIVE),OLD);
});
check("different candidate cannot be silently overwritten",()=>{
  const r=run({preload:{[STAGED]:OTHER,[ACTIVE]:OLD}});
  assert.equal(r.candidateWrites,0);
  assert.equal(r.store.get(STAGED),OTHER);
  assert.equal(r.store.get(STATUS),"candidate_slot_occupied");
});
check("write returns false: record unknown, no extra secret writes",()=>{
  const r=run({falseCandidate:true});
  assert.equal(r.candidateWrites,1);
  assert.equal(r.store.get(STATUS),"candidate_commit_unknown");
  assert.equal(r.done,1);
});
check("write reaches disk then returns false: still unknown, no auto retry",()=>{
  const r=run({falseCandidate:true,writeThenFalse:true});
  assert.equal(r.candidateWrites,1);
  assert.equal(r.store.get(STAGED),TOKEN);
  assert.equal(r.store.get(STATUS),"candidate_commit_unknown");
});
check("readback mismatch fails closed",()=>{
  const r=run({corruptReadback:true});
  assert.equal(r.candidateWrites,1);
  assert.equal(r.store.get(STATUS),"candidate_readback_unverified");
});
check("store read exception fails closed",()=>{
  const r=run({throwRead:true});
  assert.equal(r.candidateWrites,0);
  assert.equal(r.store.get(STATUS),"bootstrap_error");
});
check("no secret in status, logs, or network on all trigger paths",()=>{
  for(const o of [{},{trigger:"editor"},{parameter:"short"},
    {falseCandidate:true},{throwRead:true},{corruptReadback:true}]){
    const r=run(o);
    assert.equal(r.done,1);
    assert.equal(r.network,0);
    assert.equal(r.logs.join("").includes(TOKEN),false);
    assert.equal(JSON.stringify(r.writes).includes(TOKEN),false);
    assert.equal(String(r.store.get(STATUS)||"").includes(TOKEN),false);
  }
});
console.log("SUMMARY",count,"PASS, 0 FAIL");