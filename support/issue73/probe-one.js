/*
 Issue #73 proof of concept. Not a production verifier.
 Requires Surge iOS 6.0.0+.
 Does not post telemetry, change policy groups or modify the feed.
*/
const GROUP = '免费节点池';
const TEST_URL = 'https://www.gstatic.com/generate_204';
function finish(message) {
  console.log('[issue73] ' + JSON.stringify(message));
  $done();
}
$httpAPI('GET','/v1/policies',{include_external:true}, result => {
  try {
    const entries=result && result['external-policies'];
    const version=$environment && $environment['surge-version'] || 'unknown';
    if (!Array.isArray(entries)) {
      return finish({state:'unavailable',version,reason:'external-policies missing: check Surge iOS 6+'});
    }
    const nodes=entries.filter(p=>p && p.group===GROUP && p.name && p.identifier);
    console.log('[issue73] '+JSON.stringify({version,group:GROUP,node_count:nodes.length}));
    if (!nodes.length) return $done();
    const p=nodes[0], first=Date.now();
    const opts={url:TEST_URL,policy:p.identifier,timeout:3,'auto-redirect':false};
    $httpClient.head(opts,(err,r)=>{
      const warmMs=Date.now()-first;
      if (err || !r || r.status!==204) {
        return finish({state:'first_failed',name:p.name,warm_ms:warmMs,
          status:r&&r.status||null,error:err?String(err):null});
      }
      const second=Date.now();
      $httpClient.head(opts,(err2,r2)=>{
        finish({state:'measured',name:p.name,warm_ms:warmMs,
          second_request_ms:Date.now()-second,second_status:r2&&r2.status||null,
          success:!err2&&!!r2&&r2.status===204,
          interface:$network&&$network.v4&&$network.v4.primaryInterface||'unknown',
          note:'NOT native Surge url-test latency; inspect traffic route to exclude DIRECT fallback'});
      });
    });
  } catch(e) {
    finish({state:'error',error:String(e)});
  }
});
