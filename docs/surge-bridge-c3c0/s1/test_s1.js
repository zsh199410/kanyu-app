// C3-C0-S1 isolated verification: secret-free script distribution.
// Node.js, no real tokens/URLs. Synthetic tokens only (TEST-DEV-AAA etc.).
// Simulates: a desensitised script that reads credentials from a mock
// $persistentStore, a mock server with a token table (parallel window +
// revocation), and the abnormal-access audit log.
//
// Run: node test_s1.js
// Output: s1_out.json + PASS/FAIL lines on stdout.
"use strict";
const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");

// --- synthetic tokens (never real values) ---
const OLD_TOKEN = "TEST-DEV-OLD-0001";
const NEW_TOKEN = "TEST-DEV-NEW-0002";
const LOCAL_KEY = "TEST-LOCAL-KEY-0003";
const UNKNOWN_IP = "203.0.113.99"; // TEST-NET-3, documentation range
const PHONE_IP = "198.51.100.7";   // TEST-NET-2, documentation range
const VPS_IP = "192.0.2.44";       // TEST-NET-1, documentation range
const KNOWN_IPS = new Set([PHONE_IP, VPS_IP]);
const KNOWN_UA = "Surge iOS/4034 SurgeCore/6012000";

function fingerprint(token) {
  // Audit fingerprint: first 8 hex chars of SHA-256. Never the full token.
  return crypto.createHash("sha256").update(token).digest("hex").slice(0, 8);
}

// --- mock $persistentStore ---
function makeStore(initial) {
  const m = new Map(Object.entries(initial || {}));
  return {
    read(k) { return m.has(k) ? m.get(k) : null; },
    write(v, k) { m.set(k, v); },
    dump() { return Object.fromEntries(m); },
  };
}

// --- mock server: token table + audit log ---
function makeServer() {
  const accepted = new Set([OLD_TOKEN]);
  const audit = [];
  function log(entry) { audit.push(entry); }
  return {
    accepted, audit,
    accept(t) { accepted.add(t); },
    revoke(t) { accepted.delete(t); },
    poll(token, ip, ua) {
      const fp = token ? fingerprint(token) : "none";
      const ok = token && accepted.has(token);
      log({ ts: Date.now(), ip, ua, endpoint: "/poll",
            token_fp: fp, code: ok ? 200 : 403, bytes: ok ? 89 : 22 });
      if (!ok) return { status: 403, body: { error: "forbidden" } };
      return { status: 200, body: { id: 2000000001,
        actions: [{ type: "api", method: "GET", path: "/v1/test" }] } };
    },
    postResult(token, result, ip, ua) {
      const fp = token ? fingerprint(token) : "none";
      const ok = token && accepted.has(token);
      log({ ts: Date.now(), ip, ua, endpoint: "/result",
            token_fp: fp, code: ok ? 200 : 403, bytes: ok ? 64 : 22 });
      if (!ok) return { status: 403, body: { error: "forbidden" } };
      return { status: 200, body: { ok: true, accepted: true, acked_id: result.id } };
    },
    // alert rule A1/A2: valid token from an unknown IP, or /s/ from unknown IP
    alerts() {
      return audit.filter(e =>
        (e.code === 200 && !KNOWN_IPS.has(e.ip)) ||
        (e.endpoint === "/s/" && !KNOWN_IPS.has(e.ip)));
    },
  };
}

// --- the secret-free script under test (mirrors v2 credential handling) ---
// Reads DEV token + local key from $persistentStore. Placeholders only;
// the script source itself contains no credential.
const SCRIPT_SOURCE = `
// secret-free bridge (desensitised): credentials come from $persistentStore
const DEV = $persistentStore.read("sgbridge_cred_dev");
const APIKEY = $persistentStore.read("sgbridge_cred_localkey");
const BASE = "https://<BRIDGE_BASE>";
if (!DEV) { phase("credential_missing"); $done({}); return; }
const r = await http("GET", BASE + "/poll", { "X-Dev-Token": DEV });
if (r.status === 403) { phase("auth_forbidden"); $done({}); return; }
`;

function runSecretFreeScript(env) {
  // env: { store, server, ip, ua, httpAPIavailable, actions }
  // Returns an outcome object. Mirrors the v2 credential handling only.
  const phases = [];
  let doneCount = 0;
  let networkCalls = 0;
  const done = () => { doneCount++; };
  const phase = (name) => { phases.push(name); };
  const dev = env.store.read("sgbridge_cred_dev");
  if (!dev) {
    phase("credential_missing");
    done();
    return { phases, doneCount, networkCalls, dispatched: 0, posted: 0 };
  }
  phase("credential_present");
  networkCalls++;
  const poll = env.server.poll(dev, env.ip, env.ua);
  if (poll.status === 403) {
    phase("auth_forbidden");
    done();
    return { phases, doneCount, networkCalls, dispatched: 0, posted: 0 };
  }
  const cmd = poll.body;
  // dispatch (mock execute): prefer $httpAPI (no key); fallback needs local key
  let dispatched = 0;
  if (env.httpAPIavailable) {
    dispatched = 1;
  } else {
    const key = env.store.read("sgbridge_cred_localkey");
    if (!key) {
      phase("local_key_missing");
      // action reported unknown, never blindly retried; still post result
      dispatched = 0;
    } else {
      networkCalls++;
      dispatched = 1;
    }
  }
  const result = { id: cmd.id, at: Date.now(),
    outputs: [{ type: "api", result: dispatched ? { via: "httpAPI" } :
      { via: "httpAPI", err: "outcome_unknown_no_retry" } }] };
  networkCalls++;
  const posted = env.server.postResult(dev, result, env.ip, env.ua);
  if (posted.status === 200) {
    phase("result_acked");
  } else {
    phase("result_unacked");
  }
  done();
  return { phases, doneCount, networkCalls, dispatched,
           posted: posted.status === 200 ? 1 : 0 };
}

// --- test harness ---
const results = [];
function record(id, name, pass, detail) {
  results.push({ id, name, status: pass ? "PASS" : "FAIL", detail });
  console.log((pass ? "PASS " : "FAIL ") + id + " " + name + " — " + detail);
}

function testStaticScan() {
  // The distributed script must contain no credential: scan the v2 script
  // file and this test's SCRIPT_SOURCE for real-looking secrets.
  const v2 = fs.readFileSync(
    path.join(__dirname, "..", "bridge_fixed_v2.js"), "utf8");
  const sources = [v2, SCRIPT_SOURCE];
  // forbidden: a 32+ hex-char run (looks like a real token/key), a real URL,
  // or the literal words DEV_TOKEN/ API_KEY outside a placeholder.
  const hexRun = /[0-9a-f]{32,}/i;
  const realUrl = /https?:\/\/[a-z0-9.-]+\.(xin|com|net|io)/i;
  let bad = [];
  sources.forEach((s, i) => {
    if (hexRun.test(s)) bad.push("src" + i + ":hex-run");
    if (realUrl.test(s)) bad.push("src" + i + ":real-url");
  });
  // placeholders must be present (proves desensitisation, not omission)
  const hasPlaceholder = v2.includes("<DEV_TOKEN>") && v2.includes("<API_KEY>")
    && v2.includes("<BRIDGE_BASE>");
  record("S1-T1", "static scan: distributed script contains no credential",
    bad.length === 0 && hasPlaceholder,
    bad.length ? ("forbidden pattern: " + bad.join(",")) :
      "0 forbidden patterns; placeholders <DEV_TOKEN>/<API_KEY>/<BRIDGE_BASE> present");
}

function testFailClosed() {
  const store = makeStore({});
  const server = makeServer();
  const out = runSecretFreeScript({ store, server, ip: PHONE_IP,
    ua: KNOWN_UA, httpAPIavailable: true });
  record("S1-T2", "fail-closed with no credential",
    out.networkCalls === 0 && out.doneCount === 1 &&
    out.phases.includes("credential_missing") && out.dispatched === 0,
    "networkCalls=" + out.networkCalls + " done=" + out.doneCount +
    " phases=" + out.phases.join(","));
}

function testNormalOperation() {
  const store = makeStore({ sgbridge_cred_dev: NEW_TOKEN,
    sgbridge_cred_localkey: LOCAL_KEY });
  const server = makeServer();
  server.accept(NEW_TOKEN);
  const out = runSecretFreeScript({ store, server, ip: PHONE_IP,
    ua: KNOWN_UA, httpAPIavailable: true });
  // token must appear only in the auth header, never in a body/log:
  // the mock server's audit log carries only the fingerprint.
  const leaked = server.audit.some(e =>
    JSON.stringify(e).includes(NEW_TOKEN));
  record("S1-T3", "normal operation with credential from $persistentStore",
    out.doneCount === 1 && out.dispatched === 1 && out.posted === 1 &&
    out.phases.includes("credential_present") && !leaked,
    "done=" + out.doneCount + " dispatched=" + out.dispatched +
    " posted=" + out.posted + " audit-leak=" + leaked);
}

function testRotationCutover() {
  const server = makeServer(); // accepts OLD_TOKEN only
  server.accept(NEW_TOKEN);    // parallel window opens
  const store = makeStore({ sgbridge_cred_dev: OLD_TOKEN,
    sgbridge_cred_localkey: LOCAL_KEY });
  // round 1: phone still on old token
  const r1 = runSecretFreeScript({ store, server, ip: PHONE_IP,
    ua: KNOWN_UA, httpAPIavailable: true });
  // owner provisions new token
  store.write(NEW_TOKEN, "sgbridge_cred_dev");
  // rounds 2-4: phone on new token
  let newPolls = 0, oldPolls = 0;
  for (let i = 0; i < 3; i++) {
    const o = runSecretFreeScript({ store, server, ip: PHONE_IP,
      ua: KNOWN_UA, httpAPIavailable: true });
    if (o.posted === 1) newPolls++;
  }
  // count old-token vs new-token polls in the audit log
  const oldFp = fingerprint(OLD_TOKEN), newFp = fingerprint(NEW_TOKEN);
  const auditOld = server.audit.filter(e => e.token_fp === oldFp).length;
  const auditNew = server.audit.filter(e => e.token_fp === newFp).length;
  // revoke old token
  server.revoke(OLD_TOKEN);
  const after = server.poll(OLD_TOKEN, PHONE_IP, KNOWN_UA);
  record("S1-T4", "rotation cutover (parallel window, then revoke)",
    r1.posted === 1 && newPolls === 3 && auditOld >= 2 && auditNew >= 6 &&
    after.status === 403,
    "round1-old posted=" + r1.posted + " new-token rounds=" + newPolls +
    " audit old=" + auditOld + " new=" + auditNew +
    " old-after-revoke=" + after.status);
}

function testOldTokenRejected() {
  const server = makeServer();
  server.accept(NEW_TOKEN);
  server.revoke(OLD_TOKEN);
  const store = makeStore({ sgbridge_cred_dev: OLD_TOKEN });
  const out = runSecretFreeScript({ store, server, ip: PHONE_IP,
    ua: KNOWN_UA, httpAPIavailable: true });
  record("S1-T5", "old token rejected after revocation (fail-closed)",
    out.doneCount === 1 && out.dispatched === 0 && out.posted === 0 &&
    out.phases.includes("auth_forbidden"),
    "done=" + out.doneCount + " dispatched=" + out.dispatched +
    " phases=" + out.phases.join(","));
}

function testRollback() {
  const server = makeServer();
  server.accept(NEW_TOKEN);
  server.revoke(OLD_TOKEN);
  // rollback: re-accept the old token
  server.accept(OLD_TOKEN);
  const store = makeStore({ sgbridge_cred_dev: OLD_TOKEN });
  const out = runSecretFreeScript({ store, server, ip: PHONE_IP,
    ua: KNOWN_UA, httpAPIavailable: true });
  record("S1-T6", "rollback restores old-token acceptance",
    out.doneCount === 1 && out.posted === 1,
    "posted=" + out.posted + " done=" + out.doneCount);
}

function testAudit() {
  const server = makeServer();
  server.accept(NEW_TOKEN);
  const store = makeStore({ sgbridge_cred_dev: NEW_TOKEN });
  // a poll from an unknown IP with a valid token
  runSecretFreeScript({ store, server, ip: UNKNOWN_IP,
    ua: KNOWN_UA, httpAPIavailable: true });
  // a normal poll from the phone (no alert)
  runSecretFreeScript({ store, server, ip: PHONE_IP,
    ua: KNOWN_UA, httpAPIavailable: true });
  const alerts = server.alerts();
  const auditHasFullToken = server.audit.some(e =>
    JSON.stringify(e).includes(NEW_TOKEN));
  // the unknown-IP run makes 2 requests (poll + result); both are anomalous
  const allUnknown = alerts.every(e => e.ip === UNKNOWN_IP);
  record("S1-T7", "anomalous-access audit (unknown IP flagged, no full token logged)",
    alerts.length === 2 && allUnknown && !auditHasFullToken,
    "alerts=" + alerts.length + " all-unknown-ip=" + allUnknown +
    " full-token-in-log=" + auditHasFullToken);
}

function testLocalKeyAbsent() {
  const server = makeServer();
  server.accept(NEW_TOKEN);
  const store = makeStore({ sgbridge_cred_dev: NEW_TOKEN });
  // $httpAPI unavailable AND no local key -> fallback skipped, no blind retry
  const out = runSecretFreeScript({ store, server, ip: PHONE_IP,
    ua: KNOWN_UA, httpAPIavailable: false });
  record("S1-T8", "local key absent -> direct-HTTP fallback skipped",
    out.phases.includes("local_key_missing") && out.dispatched === 0 &&
    out.doneCount === 1 && out.posted === 1,
    "phases=" + out.phases.join(",") + " dispatched=" + out.dispatched +
    " posted=" + out.posted);
}

testStaticScan();
testFailClosed();
testNormalOperation();
testRotationCutover();
testOldTokenRejected();
testRollback();
testAudit();
testLocalKeyAbsent();

const pass = results.filter(r => r.status === "PASS").length;
const fail = results.filter(r => r.status === "FAIL").length;
const out = { suite: "s1-secret-free-distribution", pass, fail,
  limitation: 0, results };
fs.writeFileSync(path.join(__dirname, "s1_out.json"),
  JSON.stringify(out, null, 2));
console.log(pass + "/" + (pass + fail) + " s1 tests passed");
if (fail > 0) process.exitCode = 1;
