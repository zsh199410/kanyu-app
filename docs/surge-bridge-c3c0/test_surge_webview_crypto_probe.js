"use strict";
/* Issue73: VM executes the ACTUAL generic Surge WebView probe source.
 * Node WebCrypto is a test stand-in, NOT a real iPhone execution.
 * No real credentials, network, log output or active policy mutation.
 */
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const { webcrypto } = require("node:crypto");

const SOURCE = fs.readFileSync(path.join(__dirname,
  "surge_webview_crypto_probe.template.js"), "utf8");
const STATUS_KEY = "sgbridge_webcrypto_probe_status";
const FORBIDDEN_KEYS = [
  "sgbridge_cred_dev", "sgbridge_cred_localkey",
  "sgbridge_cred_dev_candidate", "sgbridge_cred_localkey_candidate",
  "last_id", "ledger", "pins", "timers", "state.json"
];

async function execute({
  trigger = "editor", suppliedCrypto = webcrypto,
  suppliedSecureContext = true,
  suppliedEncoder = TextEncoder, suppliedDecoder = atob,
  writeBehavior = "ok",
} = {}) {
  const store = new Map([["sgbridge_cred_dev", "TEST-OLD-ACTIVE-NEVER-TOUCH"],
    ["ledger", "TEST-LEDGER-NEVER-TOUCH"]]);
  const before = new Map(store);
  const writes = [];
  const logs = [];
  let network = 0, doneCount = 0;
  let resolveDone;
  const done = new Promise((resolve) => { resolveDone = resolve; });
  const sandbox = {
    $trigger: trigger,
    isSecureContext: suppliedSecureContext,
    crypto: suppliedCrypto,
    TextEncoder: suppliedEncoder,
    atob: suppliedDecoder,
    $persistentStore: {
      read: (key) => store.has(key) ? store.get(key) : null,
      write: (value, key) => {
        writes.push({key, value});
        if (writeBehavior === "throw") throw new Error("write fails");
        if (writeBehavior === "false") return false;
        store.set(key, value);
        return true;
      }
    },
    $httpClient: {post: () => { network++; },get: () => { network++; }},
    $httpAPI: () => { network++; },
    $notification: {post: () => { logs.push("notification"); }},
    console: {log: (s) => logs.push(String(s)), error: (s) => logs.push(String(s))},
    $done: () => {doneCount++;resolveDone();}
  };

  vm.runInNewContext(SOURCE, sandbox, { timeout: 1000 });
  await Promise.race([
    done,
    new Promise((_, reject) => setTimeout(
      () => reject(new Error("probe did not invoke $done")), 2500)),
  ]);
  assert.equal(doneCount, 1, "must call $done exactly once");
  assert.equal(network, 0, "zero network");
  assert.equal(logs.length, 0, "zero log or notification");
  for (const k of FORBIDDEN_KEYS) {
    assert.ok(writes.every((v) => v.key !== k), "forbidden write to " + k);
  }
  for (const [k, v] of before) assert.equal(store.get(k), v);
  const allowedStatuses = new Set([
    "crypto_ready", "no_webcrypto", "no_text_encoder", "sha256_failed",
    "ed25519_unavailable", "signature_failed", "random_unavailable",
    "base64_unavailable", "base64_failed", "insecure_context",
    "probe_error"
  ]);
  assert.ok(writes.every(({key, value}) =>
    key === STATUS_KEY && allowedStatuses.has(value)),
    "only allowlisted non-secret status");
  return { status: store.get(STATUS_KEY) || null, writes, store };
}

let pass = 0;
async function test(name, fn) {
  await fn();
  pass++;
  console.log("PASS", name);
}

(async () => {
  await test("real Node WebCrypto verifies positive and tampered RFC8032 Ed25519 vector", async () => {
    const r = await execute();
    assert.equal(r.status, "crypto_ready");
    assert.equal(r.writes.length, 1);
  });
  await test("Shortcuts intent is allowed, but no actual user parameter accessed", async () => {
    const r = await execute({trigger: "intent"});
    assert.equal(r.status, "crypto_ready");
  });
  await test("cron trigger rejected with zero state writes", async () => {
    const r = await execute({trigger: null});
    assert.equal(r.status, null);
    assert.equal(r.writes.length, 0);
  });
  await test("HTTP API trigger rejected with zero state writes", async () => {
    const r = await execute({trigger: "http-api"});
    assert.equal(r.status, null);
  });
  await test("panel trigger rejected with zero state writes", async () => {
    const r = await execute({trigger: "button"});
    assert.equal(r.status, null);
  });
  await test("insecure iPhone editor WebView context is distinct and fail closed", async () => {
    const r = await execute({suppliedSecureContext: false});
    assert.equal(r.status, "insecure_context");
    assert.deepEqual(r.writes.map(x=>x.key), [STATUS_KEY]);
  });
  await test("insecure context without subtle still reports insecure_context", async () => {
    const r = await execute({
      suppliedSecureContext: false,
      suppliedCrypto: {getRandomValues: ()=>{}}
    });
    assert.equal(r.status, "insecure_context");
  });
  await test("missing crypto gives nonsecret no_webcrypto", async () => {
    const r = await execute({suppliedCrypto: null});
    assert.equal(r.status, "no_webcrypto");
  });
  await test("missing subtle gives no_webcrypto", async () => {
    const r = await execute({suppliedCrypto: {getRandomValues: ()=>{}}});
    assert.equal(r.status, "no_webcrypto");
  });
  await test("missing TextEncoder is fail closed", async () => {
    const r = await execute({suppliedEncoder: null});
    assert.equal(r.status, "no_text_encoder");
  });
  await test("incorrect UTF8 encoder is rejected", async () => {
    const r = await execute({suppliedEncoder: class {encode(){return new Uint8Array([1])}}});
    assert.equal(r.status, "no_text_encoder");
  });
  await test("missing atob fails before crypto_ready", async () => {
    const r = await execute({suppliedDecoder: null});
    assert.equal(r.status, "base64_unavailable");
  });
  await test("incorrect atob decoding fails before crypto_ready", async () => {
    const r = await execute({suppliedDecoder: () => "incorrect"});
    assert.equal(r.status, "base64_failed");
  });
  await test("broken SHA-256 fails", async () => {
    const r = await execute({suppliedCrypto: {
      subtle: {
        digest: async () => new Uint8Array([1]),
        importKey: webcrypto.subtle.importKey.bind(webcrypto.subtle),
        verify: webcrypto.subtle.verify.bind(webcrypto.subtle),
      }
    }});
    assert.equal(r.status, "sha256_failed");
  });
  await test("Ed25519 unsupported import fails closed", async () => {
    const r = await execute({suppliedCrypto: {subtle: {
      digest: webcrypto.subtle.digest.bind(webcrypto.subtle),
      importKey: async () => {throw Error("unsupported Ed25519")},
      verify: async () => true,
    }}});
    assert.equal(r.status, "ed25519_unavailable");
  });
  await test("Ed25519 wrong verification result fails closed", async () => {
    const r = await execute({suppliedCrypto: {subtle: {
      digest: webcrypto.subtle.digest.bind(webcrypto.subtle),
      importKey: webcrypto.subtle.importKey.bind(webcrypto.subtle),
      verify: async () => false,
    }}});
    assert.equal(r.status, "signature_failed");
  });
  await test("accepts-all verifier fails corrupted-signature check", async () => {
    const r = await execute({suppliedCrypto: {subtle: {
      digest: webcrypto.subtle.digest.bind(webcrypto.subtle),
      importKey: webcrypto.subtle.importKey.bind(webcrypto.subtle),
      verify: async () => true,
    }}});
    assert.equal(r.status, "signature_failed");
  });
  await test("missing secure random fails closed", async () => {
    const r = await execute({suppliedCrypto: {subtle: webcrypto.subtle}});
    assert.equal(r.status, "random_unavailable");
  });
  await test("incorrect random return fails closed", async () => {
    const r = await execute({suppliedCrypto: {
      subtle: webcrypto.subtle,
      getRandomValues: () => new Uint8Array(32),
    }});
    assert.equal(r.status, "random_unavailable");
  });
  await test("status write false does not retrigger any secret or action", async () => {
    const r = await execute({writeBehavior:"false"});
    assert.equal(r.status, null);
    assert.equal(r.writes.length, 1);
  });
  await test("status write throws but $done still called", async () => {
    const r = await execute({writeBehavior:"throw"});
    assert.equal(r.status, null);
    assert.equal(r.writes.length, 1);
  });
  await test("script is source-secret-free and contains no network or device-control API", async () => {
    assert.ok(!/\b(require|fetch|XMLHttpRequest)\s*\(/.test(SOURCE));
    assert.ok(!/\$httpClient|\$httpAPI|\$surge|\$notification|console\.log/.test(SOURCE));
    assert.ok(!/https?:\/\//.test(SOURCE));
    assert.ok(!/PASTE_|X-Dev-Token|X-Key|PRIVATE KEY/.test(SOURCE));
  });
  console.log("SUMMARY", pass, "PASS, 0 FAIL");
})().catch((e) => { console.error("FAIL",e);process.exitCode=1;});
