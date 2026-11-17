#!/usr/bin/env node
/* Node tests for probe-task-dual.js (local only; the VPS has no node).
 * J01: detectNetwork decision table.
 * J06: full run simulation with mocked Surge globals:
 *   - wifi run completes via the wifi endpoint with wifi labels;
 *   - cellular run completes via the cellular endpoint;
 *   - unknown network skips with zero HTTP calls (fail-closed);
 *   - mid-run switch wifi->cellular aborts before the next fetch;
 *   - switch during a batch aborts before the report POST.
 * Exit code 0 = all pass, 1 = any failure.
 */
'use strict';
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const JS_PATH = path.join(__dirname, '..', 'script', 'probe-task-dual.js');
const SRC = fs.readFileSync(JS_PATH, 'utf8');

let failures = 0;
function check(name, cond, extra) {
  if (cond) { console.log('ok - ' + name); }
  else { failures++; console.log('FAIL - ' + name + (extra ? ' :: ' + extra : '')); }
}

// ---- extract detectNetwork ----
function extractFunction(src, name) {
  const start = src.indexOf('function ' + name + '()');
  if (start < 0) throw new Error('function not found: ' + name);
  let i = src.indexOf('{', start);
  let depth = 0;
  for (; i < src.length; i++) {
    if (src[i] === '{') depth++;
    else if (src[i] === '}') { depth--; if (depth === 0) return src.slice(start, i + 1); }
  }
  throw new Error('unbalanced braces in ' + name);
}
const detectSrc = extractFunction(SRC, 'detectNetwork');

// ---- J01 decision table (P0-2: primary-bearer judgement, GPT #6938432964) ----
// - primaryInterface pdp_ipN -> cellular, EVEN WITH an SSID present
//   (Wi-Fi associated but not carrying traffic).
// - wifi ONLY when primaryInterface is en0 AND an SSID is present.
// - anything else -> unknown (fail-closed): utun* (VPN tunnel) never
//   implies a bearer, a missing/empty primaryInterface is not guessed,
//   an unrecognised interface name is not guessed, en0 without an SSID
//   is a contradiction, not wifi. Field source: Surge manual,
//   $network.v4.primaryInterface / $network.wifi.ssid (interface NAME
//   values are iOS system names, not Surge-documented constants).
function detectWith(network) {
  const ctx = { $network: network, console };
  vm.createContext(ctx);
  vm.runInContext(detectSrc + '\nthis.__r = detectNetwork();', ctx);
  return ctx.__r;
}
check('J01 cellular: pdp_ip0 + no ssid', detectWith({ v4: { primaryInterface: 'pdp_ip0' }, wifi: {} }) === 'cellular');
check('J01 cellular: pdp_ip3 + ssid null', detectWith({ v4: { primaryInterface: 'pdp_ip3' }, wifi: { ssid: null } }) === 'cellular');
check('J01 cellular: pdp_ip0 + ssid (bearer is cellular)', detectWith({ v4: { primaryInterface: 'pdp_ip0' }, wifi: { ssid: 'HomeWiFi' } }) === 'cellular');
check('J01 cellular: pdp_ip1 + empty ssid', detectWith({ v4: { primaryInterface: 'pdp_ip1' }, wifi: { ssid: '' } }) === 'cellular');
check('J01 cellular: wifi object missing + pdp', detectWith({ v4: { primaryInterface: 'pdp_ip0' } }) === 'cellular');
check('J01 wifi: en0 + ssid', detectWith({ v4: { primaryInterface: 'en0' }, wifi: { ssid: 'HomeWiFi' } }) === 'wifi');
check('J01 unknown: utun0 + ssid (VPN tunnel never implies a bearer)', detectWith({ v4: { primaryInterface: 'utun0' }, wifi: { ssid: 'HomeWiFi' } }) === 'unknown');
check('J01 unknown: utun1 + ssid', detectWith({ v4: { primaryInterface: 'utun1' }, wifi: { ssid: 'HomeWiFi' } }) === 'unknown');
check('J01 unknown: utun0 + no ssid', detectWith({ v4: { primaryInterface: 'utun0' }, wifi: {} }) === 'unknown');
check('J01 unknown: en1 + ssid (unrecognised bearer, not guessed)', detectWith({ v4: { primaryInterface: 'en1' }, wifi: { ssid: 'HomeWiFi' } }) === 'unknown');
check('J01 unknown: en0 + ssid null', detectWith({ v4: { primaryInterface: 'en0' }, wifi: { ssid: null } }) === 'unknown');
check('J01 unknown: no v4 + ssid', detectWith({ wifi: { ssid: 'HomeWiFi' } }) === 'unknown');
check('J01 unknown: no network at all', detectWith({}) === 'unknown');
check('J01 unknown: null network', detectWith(null) === 'unknown');
check('J01 unknown: en0 + no ssid', detectWith({ v4: { primaryInterface: 'en0' }, wifi: {} }) === 'unknown');
check('J01 unknown: v4 present but no primaryInterface', detectWith({ v4: {}, wifi: { ssid: 'HomeWiFi' } }) === 'unknown');
check('J01 unknown: primaryInterface null', detectWith({ v4: { primaryInterface: null }, wifi: { ssid: 'HomeWiFi' } }) === 'unknown');

// ---- J06 full-run simulation ----
const POOL_SHA = 'a'.repeat(64); // mocked server-issued pool content SHA (P0-1)
const BATCH_ID = 'b-' + 'c'.repeat(16); // mocked server-issued batch binding
function runScript(opts) {
  // opts: { network, switchAfterBatch (null|1), switchDuringBatch (bool),
  //         tasksPerFetch, headStatus, poolSha (undefined|null|string),
  //         batchId (undefined|null|string) }
  const calls = { get: [], post: [], head: [], httpAPI: 0 };
  const logs = [];
  let done = false;
  const state = { network: opts.network };
  const tasks = [
    { fingerprint: 'a'.repeat(32), name: 'Fixture1', protocol: 'trojan' },
    { fingerprint: 'b'.repeat(32), name: 'Fixture2', protocol: 'trojan' },
  ];
  const sandbox = {
    $network: state.network,
    $environment: { 'surge-version': '6.100.0' },
    console: { log: (s) => logs.push(String(s)) },
    $done: () => { done = true; },
    $httpAPI: (method, url, params, cb) => {
      calls.httpAPI++;
      cb({ 'external-policies': [
        { group: '免费节点池', name: 'Fixture1', identifier: 'id-Fixture1' },
        { group: '免费节点池', name: 'Fixture2', identifier: 'id-Fixture2' },
      ] });
    },
    $httpClient: {
      get: (o, cb) => {
        calls.get.push({ url: o.url, headers: o.headers });
        const remaining = opts.tasksPerFetch === undefined ? 1 : opts.tasksPerFetch;
        // P0-1: the server issues the pool SHA + batch_id in tasks info;
        // the script echoes both back. opts.poolSha/batchId === undefined
        // -> include them; null -> omit them (server without support).
        const info = { reason: 'ok' };
        if (opts.poolSha !== null) info.pool_sha = opts.poolSha === undefined ? POOL_SHA : opts.poolSha;
        if (opts.batchId !== null) info.batch_id = opts.batchId === undefined ? BATCH_ID : opts.batchId;
        const payload = remaining > 0
          ? { tasks, info }
          : { tasks: [], info };
        if (opts.tasksPerFetch !== undefined) opts.tasksPerFetch = 0;
        cb(null, { status: 200 }, JSON.stringify(payload));
      },
      post: (o, cb) => {
        calls.post.push({ url: o.url, headers: o.headers, body: o.body });
        cb(null, { status: 200 }, JSON.stringify({ ok: true, accepted: 2 }));
      },
      head: (o, cb) => {
        calls.head.push({ url: o.url, policy: o.policy });
        if (opts.switchDuringBatch && calls.head.length === 2) {
          // network flips right after the first node's warm HEAD
          state.network = { v4: { primaryInterface: 'pdp_ip0' }, wifi: {} };
          sandbox.$network = state.network;
        }
        cb(null, { status: opts.headStatus || 204 });
      },
    },
  };
  // keep a handle so the test can flip the network between batches
  sandbox.__flipToCellular = () => {
    state.network = { v4: { primaryInterface: 'pdp_ip0' }, wifi: {} };
    sandbox.$network = state.network;
  };
  vm.createContext(sandbox);
  // hook: after the first report POST, flip the network (mid-run switch)
  const origPost = sandbox.$httpClient.post;
  sandbox.$httpClient.post = (o, cb) => {
    origPost(o, (err, resp, data) => {
      if (opts.switchAfterBatch === 1) sandbox.__flipToCellular();
      cb(err, resp, data);
    });
  };
  vm.runInContext(SRC, sandbox);
  return { calls, logs, done, sandbox };
}

function logHas(logs, needle) { return logs.some((l) => l.includes(needle)); }
function postedBodies(calls) { return calls.post.map((p) => JSON.parse(p.body)); }

const WIFI_NET = { v4: { primaryInterface: 'en0' }, wifi: { ssid: 'HomeWiFi' } };
const CELL_NET = { v4: { primaryInterface: 'pdp_ip0' }, wifi: {} };

// wifi run completes via wifi endpoint
{
  const r = runScript({ network: WIFI_NET, tasksPerFetch: 1 });
  check('J06 wifi run done', r.done);
  check('J06 wifi tasks fetched from -wifi URL',
    r.calls.get.length >= 1 && r.calls.get[0].url.endsWith('-wifi'));
  check('J06 wifi tasks header X-Probe-Network=wifi',
    r.calls.get[0].headers['X-Probe-Network'] === 'wifi');
  check('J06 wifi report posted to -wifi URL',
    r.calls.post.length === 1 && r.calls.post[0].url.endsWith('-wifi'));
  const bodies = postedBodies(r.calls);
  check('J06 wifi results labelled wifi + pool sha + batch + client version',
    bodies.length === 1 && bodies[0].results.every(
      (x) => x.network_type === 'wifi' && x.source_version_sha === POOL_SHA
        && x.batch_id === BATCH_ID
        && /^dual-v1-[0-9a-f]{12}$/.test(x.client_version)));
  check('J06 wifi results carry no interface/ssid fields',
    bodies[0].results.every((x) => !('interface' in x) && !('ssid' in x)));
  check('J06 wifi probes pin node policy, never DIRECT',
    r.calls.head.every((h) => h.policy && h.policy.startsWith('id-')));
  check('J06 wifi log carries network_type wifi', logHas(r.logs, '"network_type":"wifi"'));
}

// cellular run completes via cellular endpoint
{
  const r = runScript({ network: CELL_NET, tasksPerFetch: 1 });
  check('J06 cellular run done', r.done);
  check('J06 cellular tasks fetched from cellular URL',
    r.calls.get.length >= 1 && !r.calls.get[0].url.endsWith('-wifi'));
  check('J06 cellular results labelled cellular + pool sha + batch',
    postedBodies(r.calls)[0].results.every(
      (x) => x.network_type === 'cellular' && x.source_version_sha === POOL_SHA
        && x.batch_id === BATCH_ID));
}

// P0-1: tasks info without pool_sha -> run aborts, zero report POSTs
{
  const r = runScript({ network: WIFI_NET, tasksPerFetch: 1, poolSha: null });
  check('J06 no-pool-sha run done (aborted)', r.done);
  check('J06 no-pool-sha: zero report POSTs', r.calls.post.length === 0);
  check('J06 no-pool-sha logged tasks_error', logHas(r.logs, 'pool_sha'));
}

// P0-1: tasks info without batch_id -> run aborts, zero report POSTs
{
  const r = runScript({ network: WIFI_NET, tasksPerFetch: 1, batchId: null });
  check('J06 no-batch-id run done (aborted)', r.done);
  check('J06 no-batch-id: zero report POSTs', r.calls.post.length === 0);
  check('J06 no-batch-id logged tasks_error', logHas(r.logs, 'batch_id'));
}

// unknown network: fail-closed, zero HTTP calls
{
  const r = runScript({ network: {}, tasksPerFetch: 1 });
  check('J06 unknown run done (skipped)', r.done);
  check('J06 unknown made zero HTTP calls',
    r.calls.get.length === 0 && r.calls.post.length === 0 && r.calls.head.length === 0);
  check('J06 unknown logged fail-closed skip', logHas(r.logs, 'fail-closed'));
}

// mid-run switch wifi -> cellular between batches aborts before next fetch
{
  const r = runScript({ network: WIFI_NET, tasksPerFetch: 1, switchAfterBatch: 1 });
  check('J06 switch run done (aborted)', r.done);
  check('J06 switch logged network_changed', logHas(r.logs, 'network_changed'));
  check('J06 switch: exactly 1 report POST, no 2nd tasks fetch',
    r.calls.post.length === 1 && r.calls.get.length === 1);
}

// switch during a batch aborts before the report POST
{
  const r = runScript({ network: WIFI_NET, tasksPerFetch: 1, switchDuringBatch: true });
  check('J06 in-batch switch run done (aborted)', r.done);
  check('J06 in-batch switch logged network_changed', logHas(r.logs, 'network_changed'));
  check('J06 in-batch switch: batch discarded, zero POSTs', r.calls.post.length === 0);
}

console.log(failures === 0 ? 'ALL JS TESTS PASSED' : failures + ' JS TEST(S) FAILED');
process.exit(failures === 0 ? 0 : 1);
