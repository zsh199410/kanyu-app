// C3-C0-S1 isolated verification: secret-free script distribution.
// Rev 1 (2026-11-19, addresses GPT review 7010615307).
// Node.js, no real tokens/URLs. Synthetic tokens only (TEST-DEV-AAA etc.).
// Simulates: a desensitised script that reads credentials from a mock
// $persistentStore, a mock server with a token table (parallel window +
// revocation), a /credential-proof endpoint (action-free), and the
// abnormal-access audit log. The mock mailbox holds the legacy pending
// command 1795063030 (OUTCOME_UNKNOWN) by default, so the tests prove the
// rotation acceptance never touches it.
//
// Run: node test_s1.js
// Output: s1_out.json + PASS/FAIL lines on stdout.
"use strict";
const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");

// --- synthetic tokens (never real values) ---
const OLD_TOKEN = "TEST-DEV-OLD-0001";       // leaked token (revoked in tests)
const NEW_TOKEN = "TEST-DEV-NEW-0002";       // rotation target
const BACKUP_TOKEN = "TEST-DEV-BACKUP-0004"; // pre-issued rollback token
const LOCAL_KEY = "TEST-LOCAL-KEY-0003";
const LEGACY_CMD_ID = 1795063030; // old pending command, OUTCOME_UNKNOWN
const SYNTH_CMD_ID = 2000000001;  // synthetic dispatchable command
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
function makeStore(initial, opts) {
  const m = new Map(Object.entries(initial || {}));
  const throwOnRead = !!(opts && opts.throwOnRead);
  return {
    read(k) {
      if (throwOnRead) throw new Error("store read failed");
      return m.has(k) ? m.get(k) : null;
    },
    write(v, k) { m.set(k, v); },
    dump() { return Object.fromEntries(m); },
  };
}

// --- mock server: token table + mailbox + audit log ---
// pendingId defaults to the legacy command 1795063030 (OUTCOME_UNKNOWN).
function makeServer(pendingId) {
  const accepted = new Set([OLD_TOKEN]);
  const audit = [];
  const resultsPosted = []; // {id, token_fp}
  const proofCalls = [];    // {token_fp, code}
  const pending = { id: pendingId === undefined ? LEGACY_CMD_ID : pendingId,
    actions: [{ type: "api", method: "GET", path: "/v1/test" }] };
  function log(entry) { audit.push(entry); }
  return {
    accepted, audit, resultsPosted, proofCalls, pending,
    accept(t) { accepted.add(t); },
    revoke(t) { accepted.delete(t); },
    poll(token, ip, ua) {
      const fp = token ? fingerprint(token) : "none";
      const ok = token && accepted.has(token);
      log({ ts: Date.now(), ip, ua, endpoint: "/poll",
            token_fp: fp, code: ok ? 200 : 403, bytes: ok ? 89 : 22 });
      if (!ok) return { status: 403, body: { error: "forbidden" } };
      // /poll is read-only: it returns the pending command without
      // modifying the mailbox slot.
      return { status: 200, body: { id: pending.id, actions: pending.actions } };
    },
    // Action-free credential proof: proves the token is accepted WITHOUT
    // touching the mailbox, the pending command, or any result.
    credentialProof(token, ip, ua) {
      const fp = token ? fingerprint(token) : "none";
      const ok = token && accepted.has(token);
      log({ ts: Date.now(), ip, ua, endpoint: "/credential-proof",
            token_fp: fp, code: ok ? 200 : 403, bytes: ok ? 64 : 22 });
      proofCalls.push({ token_fp: fp, code: ok ? 200 : 403 });
      if (!ok) return { status: 403, body: { error: "forbidden" } };
      return { status: 200, body: { ok: true, token_fp: fp, ts: Date.now() } };
    },
    postResult(token, result, ip, ua) {
      const fp = token ? fingerprint(token) : "none";
      const ok = token && accepted.has(token);
      log({ ts: Date.now(), ip, ua, endpoint: "/result",
            token_fp: fp, code: ok ? 200 : 403, bytes: ok ? 64 : 22 });
      if (!ok) return { status: 403, body: { error: "forbidden" } };
      resultsPosted.push({ id: result.id, token_fp: fp });
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
// the script source itself contains no credential. Fences the legacy
// command 1795063030 (never dispatches it, never posts a result for it).
const SCRIPT_SOURCE = `
// secret-free bridge (desensitised, rev 1): credentials come from $persistentStore
let DEV = null;
try { DEV = $persistentStore.read("sgbridge_cred_dev"); }
catch (e) { phase("credential_read_failed"); $done({}); return; }
if (!DEV) { phase("credential_missing"); $done({}); return; }
const r = await http("GET", BASE + "/poll", { "X-Dev-Token": DEV });
if (r.status === 403) { phase("auth_forbidden"); $done({}); return; }
if (r.body.id === 1795063030) { phase("old_cmd_fenced"); $done({}); return; }
// ... dispatch + strict ACK (see v2) ...
`;

function runSecretFreeScript(env) {
  // env: { store, server, ip, ua, httpAPIavailable }
  // Returns an outcome object. Mirrors the v2 credential handling only.
  const phases = [];
  let doneCount = 0;
  let networkCalls = 0;
  const done = () => { doneCount++; };
  const phase = (name) => { phases.push(name); };
  let dev = null;
  try {
    dev = env.store.read("sgbridge_cred_dev");
  } catch (e) {
    phase("credential_read_failed");
    done();
    return { phases, doneCount, networkCalls, dispatched: 0, posted: 0,
             fenced: 0 };
  }
  if (!dev) {
    phase("credential_missing");
    done();
    return { phases, doneCount, networkCalls, dispatched: 0, posted: 0,
             fenced: 0 };
  }
  phase("credential_present");
  networkCalls++;
  const poll = env.server.poll(dev, env.ip, env.ua);
  if (poll.status === 403) {
    phase("auth_forbidden");
    done();
    return { phases, doneCount, networkCalls, dispatched: 0, posted: 0,
             fenced: 0 };
  }
  const cmd = poll.body;
  // Fence the legacy command: never dispatch it, never post a result.
  if (cmd.id === LEGACY_CMD_ID) {
    phase("old_cmd_fenced");
    done();
    return { phases, doneCount, networkCalls, dispatched: 0, posted: 0,
             fenced: 1 };
  }
  // dispatch (mock execute): prefer $httpAPI (no key); fallback needs local key
  let dispatched = 0;
  if (env.httpAPIavailable) {
    dispatched = 1;
  } else {
    let key = null;
    try { key = env.store.read("sgbridge_cred_localkey"); } catch (e) { key = null; }
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
           posted: posted.status === 200 ? 1 : 0, fenced: 0 };
}

// Action-free credential proof (rotation acceptance step, operator side):
// proves the token is accepted without touching the mailbox.
function runCredentialProof(env) {
  const dev = env.store.read("sgbridge_cred_dev");
  const r = env.server.credentialProof(dev, env.ip, env.ua);
  return { status: r.status, networkCalls: 1 };
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
  const server = makeServer(SYNTH_CMD_ID);
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
  // Rev 1: the mailbox holds the legacy command 1795063030 throughout.
  // Acceptance is /poll + /credential-proof (action-free). NO /result is
  // posted for the legacy command, and it is never dispatched.
  const server = makeServer(); // pending = LEGACY_CMD_ID, accepts OLD only
  server.accept(NEW_TOKEN);    // parallel window opens
  const store = makeStore({ sgbridge_cred_dev: OLD_TOKEN,
    sgbridge_cred_localkey: LOCAL_KEY });
  // round 1: phone still on old token
  const r1 = runSecretFreeScript({ store, server, ip: PHONE_IP,
    ua: KNOWN_UA, httpAPIavailable: true });
  // owner provisions new token
  store.write(NEW_TOKEN, "sgbridge_cred_dev");
  // rounds 2-4: phone on new token — poll + credential-proof each round
  let newPolls = 0, newProofs = 0;
  for (let i = 0; i < 3; i++) {
    const o = runSecretFreeScript({ store, server, ip: PHONE_IP,
      ua: KNOWN_UA, httpAPIavailable: true });
    if (o.fenced === 1) newPolls++;
    const p = runCredentialProof({ store, server, ip: PHONE_IP,
      ua: KNOWN_UA });
    if (p.status === 200) newProofs++;
  }
  // count old-token vs new-token successful audit entries (before revoke)
  const oldFp = fingerprint(OLD_TOKEN), newFp = fingerprint(NEW_TOKEN);
  const auditOldOk = server.audit.filter(e => e.token_fp === oldFp &&
    e.code === 200).length;
  const auditNewOk = server.audit.filter(e => e.token_fp === newFp &&
    e.code === 200).length;
  const pendingUnchanged = server.pending.id === LEGACY_CMD_ID;
  const noLegacyResult = server.resultsPosted.filter(
    r => r.id === LEGACY_CMD_ID).length === 0;
  // revoke old token
  server.revoke(OLD_TOKEN);
  const after = server.poll(OLD_TOKEN, PHONE_IP, KNOWN_UA);
  record("S1-T4", "rotation cutover (parallel window, credential-proof, then revoke)",
    r1.fenced === 1 && newPolls === 3 && newProofs === 3 &&
    auditOldOk === 1 && auditNewOk === 6 &&
    pendingUnchanged && noLegacyResult && after.status === 403,
    "round1-old fenced=" + r1.fenced + " new-polls=" + newPolls +
    " new-proofs=" + newProofs + " audit old-ok=" + auditOldOk +
    " new-ok=" + auditNewOk + " pending-unchanged=" + pendingUnchanged +
    " no-legacy-result=" + noLegacyResult +
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

function testRollbackBackupToken() {
  // Rev 1: rollback uses the pre-issued NEW BACKUP token. The leaked old
  // token is NEVER re-enabled.
  const server = makeServer(SYNTH_CMD_ID);
  server.accept(NEW_TOKEN);
  server.revoke(OLD_TOKEN);
  // rollback: activate the pre-issued backup token (never the old one)
  server.accept(BACKUP_TOKEN);
  const store = makeStore({ sgbridge_cred_dev: BACKUP_TOKEN });
  const out = runSecretFreeScript({ store, server, ip: PHONE_IP,
    ua: KNOWN_UA, httpAPIavailable: true });
  const oldStillDead = server.poll(OLD_TOKEN, PHONE_IP, KNOWN_UA).status === 403;
  record("S1-T6", "rollback via pre-issued backup token (old token stays revoked)",
    out.doneCount === 1 && out.posted === 1 && oldStillDead,
    "posted=" + out.posted + " done=" + out.doneCount +
    " old-token-still-403=" + oldStillDead);
}

function testRollbackNoBackupFailClosed() {
  // Rev 1 (new): no backup token available -> fail-closed, state preserved,
  // leaked token NOT re-enabled.
  const server = makeServer();
  server.accept(NEW_TOKEN);
  server.revoke(OLD_TOKEN);
  // phone still holds only the revoked old token; no backup provisioned
  const store = makeStore({ sgbridge_cred_dev: OLD_TOKEN });
  const out = runSecretFreeScript({ store, server, ip: PHONE_IP,
    ua: KNOWN_UA, httpAPIavailable: true });
  const pendingUnchanged = server.pending.id === LEGACY_CMD_ID;
  const nothingPosted = server.resultsPosted.length === 0;
  // and the empty-store branch: no credential at all -> 0 network calls
  const store2 = makeStore({});
  const out2 = runSecretFreeScript({ store: store2, server, ip: PHONE_IP,
    ua: KNOWN_UA, httpAPIavailable: true });
  record("S1-T9", "rollback with no backup token -> fail-closed (leaked token not re-enabled)",
    out.doneCount === 1 && out.dispatched === 0 && out.posted === 0 &&
    out.phases.includes("auth_forbidden") && pendingUnchanged &&
    nothingPosted && out2.networkCalls === 0 &&
    out2.phases.includes("credential_missing"),
    "revoked-token run: done=" + out.doneCount + " dispatched=" +
    out.dispatched + " posted=" + out.posted + " pending-unchanged=" +
    pendingUnchanged + " results-posted=" + server.resultsPosted.length +
    " | empty-store run: networkCalls=" + out2.networkCalls);
}

function testAudit() {
  const server = makeServer(SYNTH_CMD_ID);
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
  const server = makeServer(SYNTH_CMD_ID);
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

function testCredentialReadThrows() {
  // Rev 1 (new, finding 2 V4): $persistentStore.read throws -> the script
  // must send NO request, record credential_read_failed, $done exactly once.
  const store = makeStore({}, { throwOnRead: true });
  const server = makeServer();
  const out = runSecretFreeScript({ store, server, ip: PHONE_IP,
    ua: KNOWN_UA, httpAPIavailable: true });
  record("S1-T10", "credential read throws -> 0 network calls (fail-closed)",
    out.networkCalls === 0 && out.doneCount === 1 &&
    out.phases.includes("credential_read_failed") &&
    out.dispatched === 0 && out.posted === 0 &&
    server.audit.length === 0,
    "networkCalls=" + out.networkCalls + " done=" + out.doneCount +
    " phases=" + out.phases.join(",") + " server-audit-entries=" +
    server.audit.length);
}

function testAcceptanceNeverTouchesMailbox() {
  // Rev 1 (new, finding 3): 3 acceptance rounds (poll + credential-proof
  // with the new token) must leave the legacy pending command untouched:
  // same id, still pending, still OUTCOME_UNKNOWN, 0 results posted,
  // 0 commands issued, 0 dispatches.
  const server = makeServer(); // pending = LEGACY_CMD_ID
  server.accept(NEW_TOKEN);
  const store = makeStore({ sgbridge_cred_dev: NEW_TOKEN });
  let fenced = 0, proofs = 0, dispatched = 0, posted = 0;
  for (let i = 0; i < 3; i++) {
    const o = runSecretFreeScript({ store, server, ip: PHONE_IP,
      ua: KNOWN_UA, httpAPIavailable: true });
    fenced += o.fenced; dispatched += o.dispatched; posted += o.posted;
    const p = runCredentialProof({ store, server, ip: PHONE_IP,
      ua: KNOWN_UA });
    if (p.status === 200) proofs++;
  }
  const pendingUnchanged = server.pending.id === LEGACY_CMD_ID;
  const noResults = server.resultsPosted.length === 0;
  const proofCallsAllOk = server.proofCalls.length === 3 &&
    server.proofCalls.every(c => c.code === 200);
  record("S1-T11", "rotation acceptance never touches the mailbox",
    fenced === 3 && proofs === 3 && dispatched === 0 && posted === 0 &&
    pendingUnchanged && noResults && proofCallsAllOk,
    "fenced=" + fenced + " proofs=" + proofs + " dispatched=" +
    dispatched + " posted=" + posted + " pending-id=" +
    server.pending.id + " results-posted=" + server.resultsPosted.length +
    " proof-calls=" + server.proofCalls.length);
}

testStaticScan();
testFailClosed();
testNormalOperation();
testRotationCutover();
testOldTokenRejected();
testRollbackBackupToken();
testRollbackNoBackupFailClosed();
testAudit();
testLocalKeyAbsent();
testCredentialReadThrows();
testAcceptanceNeverTouchesMailbox();

const pass = results.filter(r => r.status === "PASS").length;
const fail = results.filter(r => r.status === "FAIL").length;
const out = { suite: "s1-secret-free-distribution",
  revision: "rev1 (GPT review 7010615307)",
  pass, fail, limitation: 0, results };
fs.writeFileSync(path.join(__dirname, "s1_out.json"),
  JSON.stringify(out, null, 2));
console.log(pass + "/" + (pass + fail) + " s1 tests passed (rev1)");
if (fail > 0) process.exitCode = 1;
