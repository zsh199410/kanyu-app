"use strict";
/*
 * Issue #73 / C3-C0 Round 6 — WebView verifier replay negative control.
 *
 * Demonstrates the KNOWN LIMITATION of the stateless PR #105 verifier:
 * the SAME valid signed proof, verified twice with the SAME trusted
 * expectedNonce, passes BOTH times. This is NOT a failure of the
 * verifier — it is stateless by design. Production MUST durably
 * consume each nonce once (a separate mandatory server/device
 * state-machine gate); signature verification alone is not
 * replay prevention.
 *
 * Also confirms the nonce binding works: the same proof with a
 * DIFFERENT expectedNonce is rejected, and a different candidate
 * is rejected. No real credentials, no network, no writes, no logs.
 * Ephemeral Ed25519 key pair generated per run; never production keys.
 */
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const nodeCrypto = require("node:crypto");
const { PURPOSE, payload, candidateFingerprint } =
  require("./signed_promotion_proof");

const SRC = fs.readFileSync(path.join(__dirname,
  "surge_webview_signed_proof.js"), "utf8");
const { publicKey, privateKey } = nodeCrypto.generateKeyPairSync("ed25519");
const PUB_HEX = publicKey.export({ format: "der", type: "spki" })
  .subarray(-32).toString("hex");
const TOKEN = "TEST-NEW-DEV-CANDIDATE-0123456789ABCDEF";
const OTHER = "TEST-UNRELATED-CANDIDATE-0123456789ABCDEF";
const OLD_ID = "TEST-OLD-ID-001";
const NEW_ID = "TEST-NEW-ID-002";
const NONCE = "TEST-UNIQUE-CHALLENGE-0123456789ABCDEF";
const NOW = 1800000000000;

function createProof(overrides = {}) {
  const p = Object.assign({
    purpose: PURPOSE, kind: "dev", ok: true, fingerprint_matches: true,
    token_id: NEW_ID, fingerprint: candidateFingerprint(TOKEN),
    nonce: NONCE, issued_at: NOW, expires_at: NOW + 60000,
  }, overrides);
  p.signature = nodeCrypto.sign(
    null, Buffer.from(payload(p), "utf8"), privateKey).toString("base64");
  return p;
}

function loadRuntime() {
  const module = { exports: {} };
  let network = 0, write = 0, logs = 0;
  vm.runInNewContext(SRC, {
    module,
    crypto: nodeCrypto.webcrypto,
    TextEncoder,
    atob,
    $persistentStore: { read: () => { write++; }, write: () => { write++; } },
    $httpClient: { get: () => network++, post: () => network++ },
    $httpAPI: () => network++,
    console: { log: () => logs++, error: () => logs++ },
  }, { timeout: 1000 });
  return { api: module.exports, counts: () => ({ network, write, logs }) };
}

const real = loadRuntime();
const OPTS = {
  candidate: TOKEN, kind: "dev", oldTokenId: OLD_ID,
  expectedNonce: NONCE, pinnedPublicKeyHex: PUB_HEX, now: NOW,
};
const v = (p, o = {}) =>
  real.api.verifySignedPromotionProof(p, { ...OPTS, ...o });

let pass = 0;
async function test(name, fn) {
  await fn();
  pass++;
  console.log("PASS", name);
}

(async () => {
  await test("same valid proof passes twice with reused trusted nonce (KNOWN LIMITATION, not a verifier failure)", async () => {
    const p = createProof();
    assert.equal(await v(p), true);
    assert.equal(await v(p), true);
  });
  await test("same proof rejected with a different expectedNonce (nonce binding works)", async () => {
    const p = createProof();
    assert.equal(await v(p, { expectedNonce: "TEST-OTHER-CHALLENGE-987654321" }), false);
  });
  await test("same proof rejected for a different candidate", async () => {
    const p = createProof();
    assert.equal(await v(p, { candidate: OTHER }), false);
  });
  await test("no side effects during replay control", async () => {
    assert.deepEqual(real.counts(), { network: 0, write: 0, logs: 0 });
  });
  console.log("SUMMARY", pass, "PASS, 0 FAIL, 1 KNOWN LIMITATION (stateless replay)");
})().catch((e) => { console.error("FAIL", e); process.exitCode = 1; });
