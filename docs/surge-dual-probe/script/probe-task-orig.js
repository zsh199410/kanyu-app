/*
 Issue #73 P0 revised: dynamic node discovery + backfill patrol.
 Phone-side task executor. Runs as a Surge cron script (hourly).
 - Only runs on confirmed cellular (pdp_ipN, no Wi-Fi SSID).
 - Fetches the next task batch from the VPS (ranked by the server).
 - Tests each node via its Surge identifier (two HEADs, like probe-one.js).
 - Reports results to the VPS; the VPS decides the next batch
   (backfill on all-fail, stop on replenish target, caps, circuit breaker).
 - Never falls back to DIRECT: every probe request pins a node policy.
 - Does not modify the production pool or any policy group.
 Requires Surge iOS 6.0.0+.
*/
const GROUP = '免费节点池';
const TEST_URL = 'https://www.gstatic.com/generate_204';
const PROBE_URL = 'https://<probe-host>:8443/<random-path>'; // filled in at deploy time: https://<probe-host>:8443/<random-path>
const MAX_BATCHES_PER_RUN = 3;    // safety: at most 3 backfill rounds per hourly run
const REQUEST_TIMEOUT = 3;         // seconds per HEAD

function log(obj) {
  console.log('[issue73] ' + JSON.stringify(obj));
}
function isCellular() {
  try {
    const v4 = $network && $network.v4;
    const iface = v4 && v4.primaryInterface;
    const ssid = $network && $network.wifi && $network.wifi.ssid;
    return typeof iface === 'string' && /^pdp_ip\d+$/.test(iface) && !ssid;
  } catch (e) {
    return false;
  }
}
function httpJSON(method, url, headers, body, cb) {
  const opts = { url: url, headers: headers || {}, timeout: 10, 'auto-redirect': false };
  if (body !== undefined && body !== null) {
    opts.body = typeof body === 'string' ? body : JSON.stringify(body);
  }
  if (method === 'GET') {
    $httpClient.get(opts, (err, resp, data) => cb(err, resp, data));
  } else {
    $httpClient.post(opts, (err, resp, data) => cb(err, resp, data));
  }
}
function fetchTasks(cb) {
  httpJSON('GET', PROBE_URL, { 'X-Probe-Action': 'tasks' }, null, (err, resp, data) => {
    if (err || !resp || resp.status !== 200) {
      return cb(new Error('tasks fetch failed: ' + (err ? String(err) : (resp && resp.status))));
    }
    try {
      cb(null, JSON.parse(data));
    } catch (e) {
      cb(e);
    }
  });
}
function reportResults(results, cb) {
  httpJSON('POST', PROBE_URL, { 'Content-Type': 'application/json' }, { results: results }, (err, resp, data) => {
    if (err || !resp || resp.status !== 200) {
      return cb(new Error('report failed: ' + (err ? String(err) : (resp && resp.status))));
    }
    try {
      cb(null, JSON.parse(data));
    } catch (e) {
      cb(e);
    }
  });
}
function probeOne(identifier, cb) {
  const opts = { url: TEST_URL, policy: identifier, timeout: REQUEST_TIMEOUT, 'auto-redirect': false };
  const first = Date.now();
  $httpClient.head(opts, (err, r) => {
    const warmMs = Date.now() - first;
    if (err || !r || r.status !== 204) {
      return cb({ state: 'first_failed', warm_ms: warmMs, second_request_ms: null,
        second_status: (r && r.status) || null, success: false,
        error: err ? String(err).slice(0, 120) : ('status ' + (r && r.status)) });
    }
    const second = Date.now();
    $httpClient.head(opts, (err2, r2) => {
      cb({ state: 'measured', warm_ms: warmMs, second_request_ms: Date.now() - second,
        second_status: (r2 && r2.status) || null,
        success: !err2 && !!r2 && r2.status === 204,
        error: err2 ? String(err2).slice(0, 120) : null });
    });
  });
}
function probeBatch(tasks, idByName, done) {
  const results = [];
  let i = 0;
  function next() {
    if (i >= tasks.length) return done(results);
    const t = tasks[i++];
    const identifier = idByName[t.name];
    if (!identifier) {
      // node vanished from the phone's list between sync and test; skip silently
      return next();
    }
    probeOne(identifier, (m) => {
      results.push({
        fingerprint: t.fingerprint,
        name: t.name,
        ts: Math.floor(Date.now() / 1000),
        state: m.state,
        warm_ms: m.warm_ms,
        second_request_ms: m.second_request_ms,
        second_status: m.second_status,
        success: m.success,
        error: m.error,
        interface: ($network && $network.v4 && $network.v4.primaryInterface) || 'unknown',
      });
      next();
    });
  }
  next();
}
function run() {
  const version = ($environment && $environment['surge-version']) || 'unknown';
  if (!isCellular()) {
    log({ state: 'skipped', version: version, reason: 'not cellular (wifi or unknown interface)' });
    return $done();
  }
  // enumerate the phone's current external policies once per run
  $httpAPI('GET', '/v1/policies', { include_external: true }, (result) => {
    const entries = result && result['external-policies'];
    if (!Array.isArray(entries)) {
      log({ state: 'unavailable', version: version, reason: 'external-policies missing: check Surge iOS 6+' });
      return $done();
    }
    const idByName = {};
    entries.forEach((p) => {
      if (p && p.group === GROUP && p.name && p.identifier) idByName[p.name] = p.identifier;
    });
    log({ version: version, group: GROUP, node_count: Object.keys(idByName).length });
    let batchNo = 0;
    let totalTested = 0;
    let totalQualified = 0;
    function loop() {
      if (batchNo >= MAX_BATCHES_PER_RUN) {
        log({ state: 'done', batches: batchNo, tested: totalTested, qualified: totalQualified, note: 'max batches per run' });
        return $done();
      }
      fetchTasks((err, payload) => {
        if (err) {
          log({ state: 'tasks_error', error: String(err).slice(0, 200) });
          return $done();
        }
        const tasks = (payload && payload.tasks) || [];
        const info = (payload && payload.info) || {};
        if (!tasks.length) {
          log({ state: 'done', batches: batchNo, tested: totalTested, qualified: totalQualified,
            stop_reason: info.reason || 'no tasks' });
          return $done();
        }
        batchNo++;
        probeBatch(tasks, idByName, (results) => {
          // Qualified = responsive AND fast (second request < 300ms).
          // A node that answers 204 but takes >= 300ms does NOT count
          // toward the replenishment target.
          const q = results.filter((r) => r.success && r.second_request_ms !== null && r.second_request_ms < 300).length;
          totalTested += results.length;
          totalQualified += q;
          log({ state: 'batch_done', batch: batchNo, tested: results.length,
            qualified: q, info: info });
          reportResults(results, (rerr, ack) => {
            if (rerr) {
              log({ state: 'report_error', error: String(rerr).slice(0, 200) });
              return $done();
            }
            if (ack && ack.circuit_tripped) {
              log({ state: 'done', batches: batchNo, tested: totalTested,
                qualified: totalQualified, note: 'circuit tripped: possible network issue, backing off' });
              return $done();
            }
            // fetch the next batch (server decides: backfill, stop, or cap)
            loop();
          });
        });
      });
    }
    loop();
  });
}
run();
