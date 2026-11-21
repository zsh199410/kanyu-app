const fs=require('fs'),crypto=require('crypto'),vm=require('vm'),assert=require('assert');
const raw=fs.readFileSync('phone-probe.js','utf8');
const pool=Array.from({length:25},(_,i)=>`美国${i} = ss, 192.0.2.${i+1}, ${10001+i}, password=pw`).join('\n')+'\n';
const sha=crypto.createHash('sha256').update(pool).digest('hex');
let calls=[],data={},received=[],DONE=0;
const context={
  $argument:'X'.repeat(48),$environment:{'surge-version':'6.0.0'},
  $network:{v4:{primaryInterface:'pdp_ip0'}},
  $persistentStore:{read:k=>data[k]||null,write:(v,k)=>{data[k]=v;return true;}},
  $surge:{logbook:()=>{}},$done:()=>{DONE++},
  $httpAPI:(method,path,body,cb)=>cb({'external-policies':Array.from({length:25},(_,i)=>({name:`美国${i}`,group:'免费节点池',identifier:`POLICY::${i}`}))}),
  $httpClient:{
    get:(options,cb)=>cb(null,{status:200},pool),
    head:(options,cb)=>{calls.push(options);cb(null,{status:204},'')},
    post:(options,cb)=>{received.push(JSON.parse(options.body));cb(null,{status:200},JSON.stringify({ok:true,receipt:'stored'}))}
  }
};
vm.runInNewContext(raw,context,{timeout:5000});
assert.equal(DONE,1);
assert.equal(calls.length,12);
assert.equal(received[0].observations.length,4);
assert.equal(received[0].network_controls.length,2);
assert(received[0].network_controls.every(x=>x.probe_mode==='external_policy_id'));
assert(received[0].network_controls.every(x=>!received[0].observations.some(y=>y.name===x.name)));
assert.equal(received[0].pool_sha,sha);
assert.equal(received[0].bearer,'cellular');
assert.equal(received[0].observations[0].probe_mode,'external_policy_id');
assert.equal(data['phone-probe-pending-batch-v1'],null);
console.log('JS mock: iOS6 4 rotating nodes + 2 network controls, all policy IDs and SHA verified');
// iOS5 fallback cannot pretend failures are trusted.
context.$httpAPI=(m,p,b,cb)=>cb({'proxies':[]});
calls=[];received=[];DONE=0;
vm.runInNewContext(raw,context,{timeout:5000});
assert.equal(DONE,1);assert.equal(received[0].observations[0].probe_mode,'temporary_policy_descriptor');
assert.equal(calls.length,8);
assert.equal(received[0].network_controls,undefined);
assert(calls.every(x=>typeof x['policy-descriptor']==='string'));
console.log('JS mock: iOS5 temporary policy probes remain untrusted with no false network controls');
// Fresh iOS6 batch: 4 rotating members fail, two independent known-good
// controls reach their targets in the same execution. Keep them separate.
context.$httpAPI=(m,p,b,cb)=>cb({'external-policies':Array.from({length:25},(_,i)=>({name:`美国${i}`,group:'免费节点池',identifier:`POLICY::${i}`}))});
context.$httpClient.head=(options,cb)=>{
  calls.push(options);
  const n=parseInt(options.policy.slice('POLICY::'.length),10);
  if(n>=8 && n<=11) cb('timeout',null,'');
  else cb(null,{status:204},'');
};
calls=[];received=[];DONE=0;
vm.runInNewContext(raw,context,{timeout:5000});
assert.equal(DONE,1);
assert.equal(calls.length,12);
assert.equal(received[0].observations.length,4);
assert.equal(received[0].network_controls.length,2);
assert(received[0].observations.every(x=>x.results.every(r=>r.state==='timeout')));
assert(received[0].network_controls.every(x=>x.results.some(r=>r.state==='reachable')));
console.log('JS mock: rotating transport failures and same-batch reachable controls remain distinct');
