"use strict";
const assert=require("node:assert/strict");
const fs=require("node:fs");
const path=require("node:path");
const vm=require("node:vm");

const template=fs.readFileSync(path.join(__dirname,"surge_diagnostic_canary.template.js"),"utf8");
const tests=[];
function test(name,fn){tests.push([name,fn]);}
function run({configured=true,legacy="1795063030",
             poll={id:1795063030,actions:[{type:"api",method:"POST"}]},
             status=200,postStatus=200,postBody={diagnostic_stored:true},
             failPoll=false,failPost=false,storeThrow=false}={}) {
  let src=template;
  if(configured){
    src=src.replace("__PRIVATE_HTTPS_BRIDGE_BASE__","https://bridge.example.test")
      .replace("__PRIVATE_DEVICE_TOKEN__","EXAMPLE_FAKE_DEVICE_TOKEN_12345")
      .replace("__EXACT_OLD_BRIDGE_LAST_ID_KEY__","legacy_bridge_checkpoint");
  }
  const calls=[];
  const state={doneCount:0,storeWriteCount:0,logs:[],calls};
  const context={
    console:{log:(s)=>state.logs.push(s)},
    $done:()=>{state.doneCount++;},
    $persistentStore:{
      read:(key)=>{calls.push(["store.read",key]);if(storeThrow)throw Error("store");return legacy;},
      write:()=>{state.storeWriteCount++;throw Error("MUST_NOT_WRITE_STORE");}
    },
    $httpAPI:()=>{throw Error("MUST_NOT_USE_SURGE_API")},
    $httpClient:{
      get:(opts,cb)=>{
        calls.push(["GET",opts]);
        cb(failPoll?"offline":null,{status},JSON.stringify(poll));
      },
      post:(opts,cb)=>{
        calls.push(["POST",opts]);
        cb(failPost?"offline":null,{status:postStatus},JSON.stringify(postBody));
      }
    }
  };
  vm.runInNewContext(src,context,{timeout:1000,filename:"diagnostic-only-canary"});
  return state;
}
test("unconfigured template must not call HTTP or storage",()=>{
  const x=run({configured:false});
  assert.equal(x.doneCount,1);
  assert.equal(x.calls.length,0);
});
test("normal diagnostic reads old ID but never writes it",()=>{
  const x=run();
  assert.equal(x.doneCount,1);
  assert.equal(x.storeWriteCount,0);
  assert.equal(x.calls.filter(([kind])=>kind==="POST").length,1);
  const posted=JSON.parse(x.calls.find(([kind])=>kind==="POST")[1].body);
  assert.equal(posted.legacy_last_id,1795063030);
  assert.equal(posted.command_id,1795063030);
  assert.equal(posted.code,"LEGACY_PENDING_FENCED");
  assert.equal(posted.phase,"none");
});
test("POST target is /diagnostic and never /result",()=>{
  const x=run();
  const requests=x.calls.filter(([kind])=>kind==="GET"||kind==="POST");
  assert.deepEqual(requests.map(([kind,opts])=>kind+":"+new URL(opts.url).pathname),
                   ["GET:/poll","POST:/diagnostic"]);
  assert.equal(x.storeWriteCount,0);
});
test("old action POST is NEVER executed",()=>{
  const x=run({poll:{id:1795063030,actions:[
      {type:"api",method:"POST",path:"/v1/outbound"},
      {type:"mcp",method:"tools/call"}
  ]}});
  assert.equal(x.calls.filter(([kind])=>kind==="POST").length,1);
  assert.equal(x.calls.find(([kind])=>kind==="POST")[1].url,
               "https://bridge.example.test/diagnostic");
});
test("poll server failure prevents diagnostic POST",()=>{
  const x=run({status:503});
  assert.equal(x.doneCount,1);
  assert.equal(x.calls.filter(([kind])=>kind==="POST").length,0);
});
test("poll network failure prevents diagnostic POST",()=>{
  const x=run({failPoll:true});
  assert.equal(x.doneCount,1);
  assert.equal(x.calls.filter(([kind])=>kind==="POST").length,0);
});
test("invalid polled JSON shape prevents diagnostic POST",()=>{
  const x=run({poll:{cmd:{id:1}}});
  assert.equal(x.doneCount,1);
  assert.equal(x.calls.filter(([kind])=>kind==="POST").length,0);
});
test("missing old checkpoint reports UNKNOWN not guessed success",()=>{
  const x=run({legacy:null});
  const posted=JSON.parse(x.calls.find(([kind])=>kind==="POST")[1].body);
  assert.equal(posted.code,"LEGACY_CHECKPOINT_INVALID");
  assert.equal(posted.legacy_last_id,0);
});
test("non-numeric old checkpoint is not trusted",()=>{
  const x=run({legacy:"1795063030garbage"});
  const posted=JSON.parse(x.calls.find(([kind])=>kind==="POST")[1].body);
  assert.equal(posted.code,"LEGACY_CHECKPOINT_INVALID");
});
test("bad persisted store halts without server request",()=>{
  const x=run({storeThrow:true});
  assert.equal(x.doneCount,1);
  assert.equal(x.calls.filter(([kind])=>kind==="GET").length,0);
});
test("diagnostic 503 is not treated as completion",()=>{
  const x=run({postStatus:503});
  assert.equal(x.doneCount,1);
  assert.equal(x.logs.at(-1),"bridge diagnostic canary: DIAGNOSTIC_NOT_ACKED");
});
test("diagnostic network error is not treated as success",()=>{
  const x=run({failPost:true});
  assert.equal(x.logs.at(-1),"bridge diagnostic canary: DIAGNOSTIC_NOT_ACKED");
});
test("diagnostic plain 200 without ACK is not accepted",()=>{
  const x=run({postBody:{ok:true}});
  assert.equal(x.logs.at(-1),"bridge diagnostic canary: DIAGNOSTIC_ACK_INVALID");
});
test("successful diagnostic is explicitly acknowledged",()=>{
  const x=run();
  assert.equal(x.logs.at(-1),"bridge diagnostic canary: DIAGNOSTIC_ACKED");
});
test("runtime cannot write stored last_id through any path",()=>{
  const x=run();
  assert.equal(x.storeWriteCount,0);
  assert.equal(x.calls.filter(([kind])=>kind==="store.read").length,1);
});
(async()=>{
 for(const [name,fn] of tests){fn();process.stdout.write("PASS "+name+"\n");}
 process.stdout.write(tests.length+"/"+tests.length+" Surge diagnostic canary tests passed\n");
})().catch(err=>{process.stderr.write(err.stack+"\n");process.exitCode=1});
