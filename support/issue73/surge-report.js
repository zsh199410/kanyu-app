/* Issue #73 P0: only upload explicitly mapped per-node cached results.
   No active group retest. Configure receiver and token ON THE PHONE; never publish secrets.
   IMPORTANT: test_results output schema must be checked against live JSON.
*/
const ENDPOINT = 'https://YOUR-DOMAIN.example/api/v1/phone';
const TOKEN = 'REPLACE_WITH_32_PLUS_RANDOM_CHARS';
const GROUP = '免费节点池';
const DEVICE = 'my-iphone';

function finish(message) { console.log('[pool-report] ' + message); $done(); }
function networkType() {
  const x = $network || {};
  if (x.wifi && x.wifi.ssid) return 'wifi';
  const c = x['cellular-data'];
  // A SIM may be present while Wi-Fi is active. Do not guess cellular.
  const iface = (x.v4 && x.v4.primaryInterface || '').toLowerCase();
  if (c && c.radio && /^(pdp_ip|rmnet|ccmni)/.test(iface)) return 'cellular';
  return 'unknown';
}
function records(root) {
  // Supported *provisional* shapes only; adapt to a real sanitized test_results sample.
  let data = null;
  if (root && root.groups && root.groups[GROUP]) data = root.groups[GROUP];
  if (!data && root && root[GROUP]) data = root[GROUP];
  if (!data && Array.isArray(root && root.results)) {
    const group = root.results.find(x => x && (x.group === GROUP || x.group_name === GROUP || x.name === GROUP));
    if (group) data = group.data || group.results;
  }
  if (data && data.data) data = data.data;
  if (!data || typeof data !== 'object' || Array.isArray(data)) return [];
  const now = Math.floor(Date.now()/1000);
  return Object.keys(data).flatMap(name => {
    const x = data[name];
    if (!x || typeof x !== 'object') return [];
    // Deliberately *not* using tcp/rtt/receive/available until semantics confirmed.
    const ms = x.latency_ms ?? x.latency ?? x.delay_ms ?? x.delay;
    const ts = x.timestamp ?? x.test_time ?? x.testTime;
    if (typeof ms !== 'number' || !Number.isFinite(ms) || ms < 0 || ms > 30000) return [];
    // An absent test timestamp means cache freshness is unprovable: reject.
    if (typeof ts !== 'number' || ts < now-3600 || ts > now+60) return [];
    if (x.success === false || x.error) return [{name, ts, latency_ms:ms, ok:false}];
    return [{name, ts, latency_ms:ms, ok:true}];
  });
}
if (!ENDPOINT.startsWith('https://') || TOKEN.length < 32 || TOKEN.startsWith('REPLACE_')) {
  finish('configure HTTPS endpoint and upload token first');
} else {
  const network = networkType();
  if (network !== 'cellular') {
    finish('not proven cellular; do not claim mobile-qualified result');
  } else {
    $httpAPI('GET', '/v1/policy_groups/test_results', {}, result => {
      try {
        const observations = records(result);
        if (observations.length === 0) {
          finish('no recognized fresh per-node results; inspect sanitized JSON; no upload');
          return;
        }
        $httpClient.post({url:ENDPOINT,headers:{'Content-Type':'application/json',
          'Authorization':'Bearer '+TOKEN},body:JSON.stringify({
          group:GROUP,device:DEVICE,network,observations})},
          (error,response,data) => finish(error || !response || response.status !== 200 ?
            'upload failed ('+(error || (response && response.status))+')' :
            'uploaded '+observations.length+' observations'));
      } catch (e) {finish('unrecognized API schema: '+String(e));}
    });
  }
}

