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
assert.equal(calls.length,8);
assert.equal(received[0].observations.length,4);
assert.equal(received[0].pool_sha,sha);
assert.equal(received[0].bearer,'cellular');
assert.equal(received[0].observations[0].probe_mode,'external_policy_id');
assert.equal(data['phone-probe-pending-batch-v1'],null);
console.log('JS mock: iOS6 4 nodes x 2 test targets, SHA verified');
// iOS5 fallback cannot pretend failures are trusted.
context.$httpAPI=(m,p,b,cb)=>cb({'proxies':[]});
calls=[];received=[];DONE=0;
vm.runInNewContext(raw,context,{timeout:5000});
assert.equal(DONE,1);assert.equal(received[0].observations[0].probe_mode,'temporary_policy_descriptor');
assert(calls.every(x=>typeof x['policy-descriptor']==='string'));
console.log('JS mock: iOS5 temporary policy probes are untrusted until device validation');
