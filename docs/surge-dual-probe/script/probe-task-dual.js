/*
 Issue #73 P0 revised + dual-channel (B1) patch — ISOLATED, NOT production.
 Phone-side task executor. Runs as a Surge cron script (hourly).
 - Dual-channel: runs on cellular AND on Wi-Fi. Network type is judged at
   run time from the PRIMARY BEARER interface ($network.v4.primaryInterface):
   pdp_ipN -> cellular (even when a Wi-Fi SSID is also present: SSID only
   proves Wi-Fi is associated, not that traffic flows over Wi-Fi); a
   non-cellular primary interface + a Wi-Fi SSID -> wifi. Anything else
   (no v4 info, no primary interface, non-cellular primary with no SSID)
   is unknown and fail-closed: the run is skipped, nothing is reported.
 - Two DIFFERENT version concepts, never mixed:
   * client_version (CLIENT_VERSION) = this script's own build id
     (sha12 of this file, injected at build time). It identifies the
     client code, nothing else.
   * source_version_sha = sha256 of the node-pool file bytes UNDER TEST.
     The server is the authority: it locks the pool SHA + the batch's
     fingerprint set + a validity window when issuing a task batch
     (info.pool_sha + info.batch_id) and the script echoes both values
     back verbatim on every result; the server verifies each result
     against THAT batch record at ingest and rejects anything that does
     not match it. The binding is to the task snapshot, not to the pool
     file as it happens to look when the result arrives.
 - Every result is bound to: network_type (wifi|cellular), source_version_sha
   (pool content SHA from the server), batch_id, client_version, stable
   fingerprint, timestamp, success/fail, ms. network_type is a
   CLIENT-DECLARED label: it says which channel the client claims the
   run used; it is never native full-group verification and never P0
   gate evidence.
 - No SSID, IP, interface identifier or device identity is ever reported.
   The raw interface value is NOT sent anymore; only the derived enum.
 - Wi-Fi results go to the independent wifi endpoint (PROBE_URL + '-wifi')
   and the independent wifi tables server-side; they can never be mistaken
   for cellular evidence and never feed the P0 gate / native acceptance.
 - Probes only provide candidate ranking / health signals. They NEVER prove
   a native full-group <300ms result and NEVER auto-approve candidates.
 - TRUST BOUNDARY: the endpoint path and the X-Probe-Network header are
   client-supplied. They only check LABEL SELF-CONSISTENCY (header agrees
   with path); they CANNOT prove the real transport interface and CANNOT
   catch a switch in the milliseconds between two detections. The server
   therefore records these only as client-reported wifi/cellular probes;
   they are never promoted to native full-group verification and never
   serve as P0 gate evidence.
 - Never falls back to DIRECT: every probe request pins a node policy.
 - Does not modify the production pool or any policy group.
 Requires Surge iOS 6.0.0+.
*/
const GROUP = '免费节点池';
const TEST_URL = 'https://www.gstatic.com/generate_204';
const PROBE_URL = 'https://<probe-host>:8443/<random-path>'; // filled in at deploy time: https://<probe-host>:8443/<random-path>
// CLIENT_VERSION is injected at build time by tools/inject_sha.py:
// sha256 of this file with the placeholder '000000000000', first 12 hex.
// This is the SCRIPT build id. It is NOT the pool content SHA.
const CLIENT_VERSION = 'dual-v1-23113216f849';
const PROBE_URL_WIFI = PROBE_URL.replace(/\/([^/?#]+)$/, '/$1-wifi');
const MAX_BATCHES_PER_RUN = 3;    // safety: at most 3 backfill rounds per hourly run
const REQUEST_TIMEOUT = 3;         // seconds per HEAD

function log(obj) {
  console.log('[issue73] ' + JSON.stringify(obj));
}
function detectNetwork() {
  // Runtime judgement from the PRIMARY BEARER interface, NOT from the
  // mere presence of a cellular interface or a Wi-Fi SSID.
  // Returns 'cellular' | 'wifi' | 'unknown'.
  // Field source (Surge manual, JavaScript API Reference):
  //   $network.v4.primaryInterface, $network.wifi.ssid / .bssid,
  //   $network.v6.primaryInterface, $network.cellular-data (iOS).
  // The INTERFACE NAME values themselves (en0, pdp_ipN, utunN) are iOS
  // system names, not Surge-documented constants, so the rule is
  // deliberately conservative and only recognises two bearers:
  // - cellular: primaryInterface is pdp_ipN. The bearer is cellular
  //   even when a Wi-Fi SSID is also present (Wi-Fi associated but not
  //   carrying traffic, e.g. captive portal / Wi-Fi not usable).
  // - wifi: primaryInterface is en0 AND a Wi-Fi SSID is present.
  // - unknown: everything else -> fail-closed. In particular a utun*
  //   primary interface (VPN tunnel) never implies a bearer, a missing
  //   or empty primaryInterface is not guessed, an unrecognised
  //   interface name is not guessed, and en0 without an SSID is a
  //   contradiction, not wifi. Wi-Fi connected + cellular present is a
  //   normal environment; the primary interface alone decides.
  // Reasoning: an SSID only proves Wi-Fi is ASSOCIATED; it does not
  // prove traffic flows over Wi-Fi. primaryInterface is the bearer
  // that actually carries the traffic. No SSID/IP/device identity is
  // reported.
  try {
    const v4 = $network && $network.v4;
    const iface = v4 && v4.primaryInterface;
    if (typeof iface !== 'string' || !iface) return 'unknown';
    if (/^pdp_ip\d+$/.test(iface)) return 'cellular';
    if (iface !== 'en0') return 'unknown';
    const ssid = $network && $network.wifi && $network.wifi.ssid;
    const hasSsid = typeof ssid === 'string' && ssid.length > 0;
    return hasSsid ? 'wifi' : 'unknown';
  } catch (e) {
    return 'unknown';
  }
}
function channelUrl(networkType) {
  return networkType === 'wifi' ? PROBE_URL_WIFI : PROBE_URL;
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
function fetchTasks(networkType, cb) {
  httpJSON('GET', channelUrl(networkType),
    { 'X-Probe-Action': 'tasks', 'X-Probe-Network': networkType },
    null, (err, resp, data) => {
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
function reportResults(results, networkType, cb) {
  httpJSON('POST', channelUrl(networkType),
    { 'Content-Type': 'application/json', 'X-Probe-Network': networkType },
    { results: results }, (err, resp, data) => {
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
function probeBatch(tasks, idByName, networkType, poolSha, batchId, done) {
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
        // Label bound at run time; no raw identifiers are sent.
        // source_version_sha is the POOL content SHA handed out by the
        // server in this run's tasks info (echoed verbatim, never the
        // script's own build id). batch_id is the task-batch binding
        // the server locked at issuance. client_version is the script
        // build id.
        network_type: networkType,
        source_version_sha: poolSha,
        batch_id: batchId,
        client_version: CLIENT_VERSION,
      });
      next();
    });
  }
  next();
}
function run() {
  const version = ($environment && $environment['surge-version']) || 'unknown';
  const networkType = detectNetwork();
  if (networkType === 'unknown') {
    log({ state: 'skipped', version: version, network_type: networkType,
      reason: 'unknown or ambiguous network (fail-closed)' });
    return $done();
  }
  // enumerate the phone's current external policies once per run
  $httpAPI('GET', '/v1/policies', { include_external: true }, (result) => {
    const entries = result && result['external-policies'];
    if (!Array.isArray(entries)) {
      log({ state: 'unavailable', version: version, network_type: networkType,
        reason: 'external-policies missing: check Surge iOS 6+' });
      return $done();
    }
    const idByName = {};
    entries.forEach((p) => {
      if (p && p.group === GROUP && p.name && p.identifier) idByName[p.name] = p.identifier;
    });
    log({ version: version, network_type: networkType, group: GROUP,
      node_count: Object.keys(idByName).length });
    let batchNo = 0;
    let totalTested = 0;
    let totalQualified = 0;
    function loop() {
      // Re-detect before every batch: a network switch mid-run aborts the
      // run (fail-closed) instead of mislabelling the next batch.
      const nowNet = detectNetwork();
      if (nowNet !== networkType) {
        log({ state: 'network_changed', version: version,
          from_network: networkType, to_network: nowNet,
          note: 'aborted mid-run, unreported results discarded' });
        return $done();
      }
      if (batchNo >= MAX_BATCHES_PER_RUN) {
        log({ state: 'done', network_type: networkType, batches: batchNo,
          tested: totalTested, qualified: totalQualified, note: 'max batches per run' });
        return $done();
      }
      fetchTasks(networkType, (err, payload) => {
        if (err) {
          log({ state: 'tasks_error', network_type: networkType, error: String(err).slice(0, 200) });
          return $done();
        }
        const tasks = (payload && payload.tasks) || [];
        const info = (payload && payload.info) || {};
        // The server is the authority on the pool version under test: it
        // locks the pool file SHA + the batch fingerprint set + a
        // validity window when issuing tasks. Without a well-formed
        // pool_sha AND batch_id the results cannot be bound to any task
        // snapshot, so the run stops here (fail-closed) instead of
        // reporting unbound results.
        const poolSha = info.pool_sha;
        if (typeof poolSha !== 'string' || !/^[0-9a-f]{64}$/.test(poolSha)) {
          log({ state: 'tasks_error', network_type: networkType,
            error: 'tasks info.pool_sha missing or malformed; refusing to report unbound results' });
          return $done();
        }
        if (!tasks.length) {
          log({ state: 'done', network_type: networkType, batches: batchNo,
            tested: totalTested, qualified: totalQualified,
            stop_reason: info.reason || 'no tasks' });
          return $done();
        }
        const batchId = info.batch_id;
        if (typeof batchId !== 'string' || !/^b-[0-9a-f]{16}$/.test(batchId)) {
          log({ state: 'tasks_error', network_type: networkType,
            error: 'tasks info.batch_id missing or malformed; refusing to report unbound results' });
          return $done();
        }
        batchNo++;
        probeBatch(tasks, idByName, networkType, poolSha, batchId, (results) => {
          // Re-detect before reporting: a switch during the batch aborts
          // instead of reporting results under a stale label.
          if (detectNetwork() !== networkType) {
            log({ state: 'network_changed', version: version,
              from_network: networkType, to_network: detectNetwork(),
              note: 'aborted before report, batch results discarded' });
            return $done();
          }
          // Qualified = responsive AND fast (second request < 300ms).
          // A node that answers 204 but takes >= 300ms does NOT count
          // toward the replenishment target. This is a ranking signal only;
          // it never proves native full-group <300ms and never auto-approves
          // any candidate.
          const q = results.filter((r) => r.success && r.second_request_ms !== null && r.second_request_ms < 300).length;
          totalTested += results.length;
          totalQualified += q;
          log({ state: 'batch_done', network_type: networkType, batch: batchNo,
            tested: results.length, qualified: q, info: info });
          reportResults(results, networkType, (rerr, ack) => {
            if (rerr) {
              log({ state: 'report_error', network_type: networkType, error: String(rerr).slice(0, 200) });
              return $done();
            }
            if (ack && ack.circuit_tripped) {
              log({ state: 'done', network_type: networkType, batches: batchNo,
                tested: totalTested, qualified: totalQualified,
                note: 'circuit tripped: possible network issue, backing off' });
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
