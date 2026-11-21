/* Surge iOS phone node observations - staged, does not modify policy/pool.
 * Requires private $argument bearer token and a reverse-proxied HTTPS receiver.
 * Without either a valid token or receiver: NO requests to the receiver.
 * Uses iOS 6 external-policy identifiers when supported. On iOS 5,
 * policy-descriptor probes are marked lower-trust until phone validation.
 */
(function () {
  'use strict';
  var SUB_URL = 'https://sgcmd.vip668.xin:8443/m/pool-new.txt';
  var INGEST_URL = 'https://sgcmd.vip668.xin:8443/v1/phone-observations';
  var GROUP = '免费节点池';
  var BATCH = 4;
  var STORE_INDEX = 'phone-probe-next-index-v1';
  var STORE_QUEUE = 'phone-probe-pending-batch-v1';
  var token = String(typeof $argument === 'string' ? $argument : '').trim();
  var finished = false;
  function done() { if (!finished) { finished = true; $done(); } }
  function log(s) { if (typeof $surge !== 'undefined' && $surge.logbook) $surge.logbook('[phone-probe] ' + s); }
  function isToken(s) { return /^[a-zA-Z0-9_\-.~]{32,160}$/.test(s); }
  if (!isToken(token)) { log('disabled: missing private argument token'); return done(); }
  function request(method, opt, cb) {
    try { $httpClient[method](opt, function (err, response, body) {
      cb(err || null, response && response.status, body);
    }); } catch (e) { cb('script-request-unavailable'); }
  }
  function persist(key, value) { try { return $persistentStore.write(value,key); } catch (e) { return false; } }
  function stored(key) { try { return $persistentStore.read(key); } catch (e) { return null; } }
  function upload(payload, cb) {
    request('post', {url:INGEST_URL,timeout:10,
      headers:{'Content-Type':'application/json','Authorization':'Bearer '+token},
      body:JSON.stringify(payload)}, function (error,status,text) {
        var ok=false;
        try { var result=JSON.parse(text||'{}');
          ok=(!error && status===200 && result.ok===true &&
              (result.receipt==='stored'||result.receipt==='duplicate'));
        } catch(e) {}
        cb(ok,status);
      });
  }
  var queued=stored(STORE_QUEUE);
  if (queued) {
    try {
      var previous=JSON.parse(queued);
      if (previous && previous.schema===1) {
        upload(previous,function (ok,status) {
          if (ok || status===422 || status===409) {
            persist(STORE_QUEUE,null); log('prior batch acknowledged or expired');
          } else { log('retry pending; no new probe'); }
          done();
        });
        return;
      }
    } catch(e) {}
    persist(STORE_QUEUE,null);
  }
  function sha256(s) {
    // Pure JavaScript UTF-8 SHA256; no external library or crypto API.
    var bin=unescape(encodeURIComponent(s));
    var bytes=[],i,j; for(i=0;i<bin.length;i++)bytes.push(bin.charCodeAt(i));
    var bitlen=bytes.length*8; bytes.push(128);
    while(bytes.length%64!==56)bytes.push(0);
    var high=Math.floor(bitlen/0x100000000),low=bitlen>>>0;
    for(i=3;i>=0;i--)bytes.push((high>>>(i*8))&255);
    for(i=3;i>=0;i--)bytes.push((low>>>(i*8))&255);
    var K=[0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2];
    var H=[0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19];
    function r(x,n) {return (x>>>n)|(x<<(32-n));}
    for(i=0;i<bytes.length;i+=64){
      var w=new Array(64);
      for(j=0;j<16;j++){var p=i+4*j;w[j]=((bytes[p]<<24)|(bytes[p+1]<<16)|(bytes[p+2]<<8)|bytes[p+3])>>>0;}
      for(j=16;j<64;j++){
        var x=w[j-15],y=w[j-2];
        w[j]=((w[j-16]+(r(x,7)^r(x,18)^(x>>>3))+w[j-7]+(r(y,17)^r(y,19)^(y>>>10)))>>>0);
      }
      var a=H[0],b=H[1],c=H[2],d=H[3],e=H[4],f=H[5],g=H[6],h=H[7];
      for(j=0;j<64;j++){
        var t1=(h+(r(e,6)^r(e,11)^r(e,25))+((e&f)^(~e&g))+K[j]+w[j])>>>0;
        var t2=((r(a,2)^r(a,13)^r(a,22))+((a&b)^(a&c)^(b&c)))>>>0;
        h=g;g=f;f=e;e=(d+t1)>>>0;d=c;c=b;b=a;a=(t1+t2)>>>0;
      }
      H[0]=(H[0]+a)>>>0;H[1]=(H[1]+b)>>>0;H[2]=(H[2]+c)>>>0;
      H[3]=(H[3]+d)>>>0;H[4]=(H[4]+e)>>>0;H[5]=(H[5]+f)>>>0;
      H[6]=(H[6]+g)>>>0;H[7]=(H[7]+h)>>>0;
    }
    return H.map(function(n){return ('00000000'+n.toString(16)).slice(-8);}).join('');
  }
  function bearer() {
    try {
      var p=String($network.v4.primaryInterface||'');
      if (/^en[0-9]+$/.test(p)) return 'wifi';
      if (/^(pdp_ip|rmnet|ccmni)[0-9]+/.test(p)) return 'cellular';
    } catch(e) {}
    return 'unknown';
  }
  function collect(raw) {
    var members=[], names={};
    raw.split(/\r?\n/).forEach(function (line) {
      line=line.trim(); if (!line || line.charAt(0)==='#') return;
      var k=line.indexOf('='); if (k<=0) return;
      var name=line.slice(0,k).trim(), desc=line.slice(k+1).trim();
      if (!name || !desc || names[name] || !/^(trojan|vmess|ss)\s*,/i.test(desc))return;
      names[name]=true; members.push({name:name,descriptor:desc});
    });
    return members;
  }
  function networkProof(members,sha) {
    var b=bearer(); if(b==='unknown') { log('network bearer unavailable: no failure samples'); }
    $httpAPI('GET','/v1/policies',{include_external:true},function(result) {
      var external=result && result['external-policies'];
      var index={}, mode='temporary_policy_descriptor';
      if (Array.isArray(external)) {
        external.forEach(function(p){
          if(p && p.group===GROUP && typeof p.name==='string' &&
             typeof p.identifier==='string' && p.identifier.indexOf('POLICY::')===0){
            index[p.name]=p.identifier;
          }
        });
        if(Object.keys(index).length===0) {log('external policy identifiers absent: safe fallback');}
        else mode='external_policy_id';
      }
      var offset=parseInt(stored(STORE_INDEX)||'0',10)||0;
      var batch=[];for(var j=0;j<Math.min(BATCH,members.length);j++){
        var m=members[(offset+j)%members.length];
        if(mode==='external_policy_id' && !index[m.name])continue;
        batch.push({name:m.name,descriptor:m.descriptor,identifier:index[m.name]||null});
      }
      persist(STORE_INDEX,String((offset+BATCH)%members.length));
      if(!batch.length){log('no matched pool identities');return done();}
      var targets=[{id:'a',url:'http://captive.apple.com/generate_204'},
                   {id:'b',url:'https://www.gstatic.com/generate_204'}];
      var pending=[],n=0,active=0,ended=0;
      for(var x=0;x<batch.length;x++)for(var y=0;y<2;y++)pending.push({index:x,target:targets[y]});
      var observations=batch.map(function(item){return {name:item.name,probe_mode:mode,results:[]};});
      function testNext() {
        while(active<2 && n<pending.length){
          (function(task){
            var p=batch[task.index];
            var options={url:task.target.url,timeout:6,'auto-redirect':false};
            if(mode==='external_policy_id')options.policy=p.identifier;
            else options['policy-descriptor']=p.descriptor;
            active++;
            request('head',options,function(err,status){
              var state='unknown';
              if(!err && status>=200 && status<400)state='reachable';
              else if(err && /(timeout|timed\s*out)/i.test(String(err)))state='timeout';
              else if(err && /(?:connect|network|unreachable|refused|handshake)/i.test(String(err)))state='transport_error';
              // Strictly categorical diagnostics. Never send raw errors, URLs, IPs, or node credentials.
              var hint=state==='unknown' ? (!err && typeof status==='number' ? 'http_status' :
                             err ? 'other_error' : 'unclassified') : 'none';
              observations[task.index].results.push({id:task.target.id,state:state,hint:hint});
              active--;ended++;
              if(ended===pending.length)send();else testNext();
            });
          })(pending[n++]);
        }
      }
      function send() {
        var ts=Math.floor(Date.now()/1000);
        var nonce=('00000000'+Math.floor(Math.random()*0x100000000).toString(16)).slice(-8)+
                  ('00000000'+Math.floor(Math.random()*0x100000000).toString(16)).slice(-8)+
                  ('00000000'+Math.floor(Math.random()*0x100000000).toString(16)).slice(-8)+
                  ('00000000'+Math.floor(Math.random()*0x100000000).toString(16)).slice(-8);
        var ver='unknown';try{ver=String($environment['surge-version']||'unknown');}catch(e){}
        var payload={schema:1,group:GROUP,timestamp:ts,nonce:nonce,
            pool_sha:sha,bearer:b,surge_version:ver,observations:observations};
        persist(STORE_QUEUE,JSON.stringify(payload));
        upload(payload,function(ok,status){
          if(ok){persist(STORE_QUEUE,null);log('batch received: '+observations.length);}
          else {log('ingest unavailable; pending retained ('+String(status||'net')+')');}
          done();
        });
      }
      testNext();
    });
  }
  request('get',{url:SUB_URL,timeout:10},function(error,status,body){
    if(error||status!==200||typeof body!=='string'||body.length>1024*1024){
      log('subscription unavailable');return done();
    }
    var members=collect(body);
    if(members.length<22){log('subscription incomplete');return done();}
    networkProof(members,sha256(body));
  });
})();
