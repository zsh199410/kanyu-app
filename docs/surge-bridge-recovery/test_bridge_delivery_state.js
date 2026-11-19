"use strict";
const assert=require("node:assert/strict");
const {runOnce}=require("./bridge_delivery_state");

const STUCK=1795063030;
function fixture({cmd={id:STUCK,actions:[{type:"api",method:"GET"}]},
                  legacy=0,ledger=null}={}) {
  const f={
    cmd,legacy,ledger,done:0,sent:[],diag:[],reply:null,
    receipt:null,storageFail:false,executeFail:false,
    getLegacyLastId(){return this.legacy},
    getLedger(){return this.ledger},
    putLedger(s){if(this.storageFail)return false;this.ledger=s;return true},
    async poll(){return this.cmd},
    async execute(command){
      this.done++;
      if(this.executeFail) throw Error("simulated script kill");
      return [{ok:true,kind:"GET"}];
    },
    async sendResult(data){
      this.sent.push(JSON.parse(JSON.stringify(data)));
      if(this.reply) return this.reply;
      return {status:200,body:{ok:true,accepted:true,acked_id:data.id}};
    },
    async sendDiagnostic(data){this.diag.push(data)},
    async lookupReceipt(id,result){return this.receipt || {confirmed:false}},
  };
  return f;
}
const tests=[];
function test(name,fn){tests.push([name,fn])}

test("first migration fences the old 12:37 command and records last_id",async()=>{
 const f=fixture({legacy:STUCK});
 const r=await runOnce(f);
 assert.equal(r.decision,"LEGACY_PENDING_FENCED");
 assert.equal(f.done,0);
 assert.equal(f.sent.length,0);
 assert.equal(JSON.parse(f.ledger).floor,STUCK);
 assert.equal(f.diag[0].code,"LEGACY_PENDING_FENCED");
 assert.equal(f.diag[0].legacy_last_id,STUCK);
});
test("23 repeated polls cannot replay an old unknown command",async()=>{
 const f=fixture({legacy:STUCK});
 await runOnce(f);
 for(let i=0;i<23;i++) {
   assert.equal((await runOnce(f)).decision,"DUPLICATE_OR_FENCED");
 }
 assert.equal(f.done,0);
 assert.equal(f.sent.length,0);
});
test("empty first poll initializes safe floor without running actions",async()=>{
 const f=fixture({cmd:{id:0},legacy:100});
 assert.equal((await runOnce(f)).decision,"NO_COMMAND_BOOTSTRAPPED");
 assert.equal(JSON.parse(f.ledger).floor,100);
 f.cmd={id:101,actions:[{type:"api",method:"GET"}]};
 assert.equal((await runOnce(f)).decision,"ACK_CONFIRMED");
 assert.equal(f.done,1);
});
test("new command persists result and acknowledges exactly once",async()=>{
 const f=fixture({legacy:42});
 f.cmd={id:0};
 await runOnce(f);
 f.cmd={id:100,actions:[{type:"api",method:"GET"}]};
 const r=await runOnce(f);
 assert.equal(r.decision,"ACK_CONFIRMED");
 assert.equal(r.action_executed,true);
 assert.equal(f.done,1);
 assert.equal(f.sent.length,1);
 assert.equal(JSON.parse(f.ledger).pending,null);
});
test("missing network ACK caches result, retries only result not action",async()=>{
 const f=fixture({legacy:10,cmd:{id:0}});
 await runOnce(f);
 f.cmd={id:123,actions:[{type:"api",method:"POST"}]};
 f.reply={status:0,body:null};
 assert.equal((await runOnce(f)).decision,"ACK_UNVERIFIED");
 assert.equal(JSON.parse(f.ledger).pending.phase,"result_ready");
 assert.equal(f.done,1);
 const original=JSON.stringify(f.sent[0]);
 f.reply={status:200,body:{ok:true,accepted:true,acked_id:123}};
 assert.equal((await runOnce(f)).decision,"ACK_CONFIRMED");
 assert.equal(f.done,1);
 assert.equal(JSON.stringify(f.sent[1]),original);
 assert.equal(JSON.parse(f.ledger).pending,null);
});
test("plain legacy 200 ok:true is NEVER treated as matched ACK",async()=>{
 const f=fixture({cmd:{id:0}});
 await runOnce(f);
 f.cmd={id:2,actions:[]};
 f.reply={status:200,body:{ok:true}};
 assert.equal((await runOnce(f)).decision,"ACK_UNVERIFIED");
 assert.equal(JSON.parse(f.ledger).pending.phase,"result_ready");
});
test("action crash becomes OUTCOME_UNKNOWN and never retried",async()=>{
 const f=fixture({cmd:{id:0}});
 await runOnce(f);
 f.cmd={id:9,actions:[{type:"api",method:"POST"}]};
 f.executeFail=true;
 assert.equal((await runOnce(f)).decision,"OUTCOME_UNKNOWN");
 f.executeFail=false;
 assert.equal((await runOnce(f)).decision,"OUTCOME_UNKNOWN");
 assert.equal(f.done,1);
 assert.equal(f.sent.length,0);
});
test("no persisted claim means no execution",async()=>{
 const f=fixture({cmd:{id:0}});
 await runOnce(f);
 f.cmd={id:9,actions:[]};
 f.storageFail=true;
 assert.equal((await runOnce(f)).decision,"CHECKPOINT_WRITE_FAILED");
 assert.equal(f.done,0);
});
test("a corrupt ledger never replays a command",async()=>{
 const f=fixture({cmd:{id:99,actions:[{type:"api",method:"POST"}]},ledger:"{garbage"});
 assert.equal((await runOnce(f)).decision,"LEDGER_CORRUPT");
 assert.equal(f.done,0);
});
test("new cmd cannot overwrite an unresolved claimed command",async()=>{
 const f=fixture({cmd:{id:0}});
 await runOnce(f);
 f.cmd={id:9,actions:[]};
 f.executeFail=true;
 await runOnce(f);
 f.cmd={id:10,actions:[]};
 assert.equal((await runOnce(f)).decision,"PENDING_ID_MISMATCH");
 assert.equal(f.done,1);
});
test("lost ACK after server clears cmd reconciles by read-only receipt",async()=>{
 const f=fixture({cmd:{id:0}});
 await runOnce(f);
 f.cmd={id:11,actions:[{type:"api",method:"POST"}]};
 f.reply={status:0,body:{}};
 await runOnce(f);
 f.cmd={id:0};
 f.receipt={confirmed:true};
 assert.equal((await runOnce(f)).decision,"RECEIPT_RECONCILED");
 assert.equal(f.done,1);
 assert.equal(JSON.parse(f.ledger).pending,null);
});
test("no server receipt leaves cached result without re-execution",async()=>{
 const f=fixture({cmd:{id:0}});
 await runOnce(f);
 f.cmd={id:11,actions:[]};
 f.reply={status:0,body:null};
 await runOnce(f);
 f.cmd={id:0};
 assert.equal((await runOnce(f)).decision,"PENDING_WITHOUT_COMMAND");
 assert.equal(f.done,1);
 assert.equal(JSON.parse(f.ledger).pending.phase,"result_ready");
});
test("even if a newer command appears, pending receipt reconciles first",async()=>{
 const f=fixture({cmd:{id:0}});
 await runOnce(f);
 f.cmd={id:11,actions:[{type:"api",method:"POST"}]};
 f.reply={status:0,body:null};
 await runOnce(f);
 f.cmd={id:12,actions:[{type:"api",method:"POST"}]};
 f.receipt={confirmed:true};
 assert.equal((await runOnce(f)).decision,"RECEIPT_RECONCILED");
 assert.equal(f.done,1);
 assert.equal((await runOnce(f)).decision,"ACK_UNVERIFIED");
 assert.equal(f.done,2);
});
test("a diagnostic transport failure never allows command replay",async()=>{
 const f=fixture({legacy:STUCK});
 f.sendDiagnostic=async()=>{throw Error("offline")};
 assert.equal((await runOnce(f)).decision,"LEGACY_PENDING_FENCED");
 assert.equal(f.done,0);
});

(async()=>{
 for(const [name,fn] of tests) {
   await fn();
   process.stdout.write("PASS "+name+"\n");
 }
 process.stdout.write(tests.length+"/"+tests.length+" bridge delivery tests passed\n");
})().catch(err=>{process.stderr.write(String(err.stack||err)+"\n");process.exitCode=1});
