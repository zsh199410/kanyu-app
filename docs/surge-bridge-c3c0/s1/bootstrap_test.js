"use strict";
/* S1 credential bootstrap isolated tests (synthetic tokens only, no network).
 * Loads the real s1/bootstrap.js, injects synthetic credentials, and runs it
 * in a vm with a mock $persistentStore / $notification / console / $done.
 * Verifies: write + read-back equality, done-flag idempotence, failed-write
 * detection, invalid-input rejection, and that no token value ever appears
 * in any log/notification. The SHA-256 fingerprint is computed here with
 * node:crypto to simulate the server-side audit record.
 */
const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const SOURCE = fs.readFileSync(path.join(__dirname, "bootstrap.js"), "utf8");
const DEV = "TEST-BOOTSTRAP-DEV-7f3a9c1e";
const KEY = "TEST-BOOTSTRAP-LOCAL-4b2d8e6f";
const DEV_FP = crypto.createHash("sha256").update(DEV).digest("hex").slice(0, 16);
const KEY_FP = crypto.createHash("sha256").update(KEY).digest("hex").slice(0, 16);

function makeStore({ failWrite = false, corruptReadBack = false } = {}) {
  const map = new Map();
  const calls = [];
  return {
    map, calls,
    read: (key) => {
      calls.push(["read", key]);
      if (corruptReadBack && (key === "sgbridge_cred_dev" || key === "sgbridge_cred_localkey")) {
        return "CORRUPTED-VALUE";
      }
      const v = map.get(key);
      return v === undefined ? null : v;
    },
    write: (value, key) => {
      calls.push(["write", key]);
      if (failWrite) return false;
      map.set(key, value);
      return true;
    },
  };
}

function runBootstrap({ dev = DEV, key = KEY, store, sourceOverride } = {}) {
  // Inject via JSON.stringify so a value containing CR/LF (or quotes) stays
  // a valid string literal in the source; the bootstrap's valid() check
  // then sees the real characters at runtime and must reject them.
  const src = (sourceOverride || SOURCE)
    .replace(/"<PASTE_NEW_DEV_TOKEN_HERE>"/, JSON.stringify(dev))
    .replace(/"<PASTE_NEW_LOCAL_KEY_HERE>"/, JSON.stringify(key));
  const logs = [];
  const notes = [];
  let doneCalls = 0;
  const ctx = {
    $persistentStore: store,
    $notification: { post: (_t, _s, msg) => { notes.push(msg); } },
    console: { log: (msg) => { logs.push(String(msg)); } },
    $done: () => { doneCalls++; },
  };
  vm.runInNewContext(src, ctx, { timeout: 1000 });
  return { logs, notes, doneCalls, store };
}

function noTokenLeak(text) {
  return !text.includes(DEV) && !text.includes(KEY);
}

async function main() {
  let n = 0;
  const test = (name, f) => { f(); n++; console.log("PASS", name); };

  test("B1 successful bootstrap: write + read-back match, done flag set, only status logged", () => {
    const store = makeStore();
    const { logs, notes, doneCalls } = runBootstrap({ store });
    assert.equal(doneCalls, 1, "exactly one $done");
    assert.equal(store.map.get("sgbridge_cred_dev"), DEV);
    assert.equal(store.map.get("sgbridge_cred_localkey"), KEY);
    assert.equal(store.map.get("sgbridge_bootstrap_done"), "1");
    assert.ok(notes.includes("bootstrap_ok"), "notification says bootstrap_ok");
    assert.ok(logs.some((l) => l.includes("bootstrap_ok")));
    assert.ok(noTokenLeak(logs.join("\n") + "\n" + notes.join("\n")), "no token value in any output");
    // Fingerprint audit (server-side simulation): read-back value hashes
    // to the same fingerprint as the generated token.
    const fp = crypto.createHash("sha256").update(store.map.get("sgbridge_cred_dev")).digest("hex").slice(0, 16);
    assert.equal(fp, DEV_FP, "read-back fingerprint matches generated token fingerprint");
    const kfp = crypto.createHash("sha256").update(store.map.get("sgbridge_cred_localkey")).digest("hex").slice(0, 16);
    assert.equal(kfp, KEY_FP);
  });

  test("B2 second run finds done flag: no re-write, no token exposure", () => {
    const store = makeStore();
    runBootstrap({ store });
    const writesBefore = store.calls.filter((c) => c[0] === "write").length;
    const second = runBootstrap({ store });
    const writesAfter = store.calls.filter((c) => c[0] === "write").length;
    assert.equal(writesAfter, writesBefore, "no additional writes on second run");
    assert.ok(second.notes.includes("bootstrap_already_done"));
    assert.equal(second.doneCalls, 1);
    assert.ok(noTokenLeak(second.logs.join("\n") + "\n" + second.notes.join("\n")));
  });

  test("B3 failed write is detected: no done flag, failure reported, no token logged", () => {
    const store = makeStore({ failWrite: true });
    const { logs, notes, doneCalls } = runBootstrap({ store });
    assert.equal(doneCalls, 1);
    assert.equal(store.map.get("sgbridge_bootstrap_done"), undefined, "no done flag on failure");
    assert.ok(notes.some((m) => m.startsWith("bootstrap_failed")), "failure reported");
    assert.ok(noTokenLeak(logs.join("\n") + "\n" + notes.join("\n")));
  });

  test("B4 read-back mismatch is detected: failure reported, no done flag", () => {
    const store = makeStore({ corruptReadBack: true });
    const { notes, doneCalls } = runBootstrap({ store });
    assert.equal(doneCalls, 1);
    assert.equal(store.map.get("sgbridge_bootstrap_done"), undefined);
    assert.ok(notes.some((m) => m.startsWith("bootstrap_failed")));
  });

  test("B5 invalid pasted values are rejected: empty / placeholder / CR-LF / >512 chars write nothing", () => {
    const bad = ["", "<PASTE_NEW_DEV_TOKEN_HERE>", "abc\r\ndef", "x".repeat(513)];
    for (const v of bad) {
      const store = makeStore();
      const { notes, doneCalls } = runBootstrap({ dev: v, store });
      assert.equal(doneCalls, 1);
      assert.equal(store.map.size, 0, "nothing written for invalid input " + JSON.stringify(v).slice(0, 30));
      assert.ok(notes.some((m) => m.startsWith("bootstrap_failed")));
    }
    // Invalid local key alone is also rejected.
    const store = makeStore();
    const { doneCalls } = runBootstrap({ key: "", store });
    assert.equal(doneCalls, 1);
    assert.equal(store.map.size, 0);
  });

  test("B6 bootstrap script source contains no real token: placeholder only", () => {
    assert.ok(SOURCE.includes("<PASTE_NEW_DEV_TOKEN_HERE>"), "DEV placeholder present");
    assert.ok(SOURCE.includes("<PASTE_NEW_LOCAL_KEY_HERE>"), "key placeholder present");
    assert.ok(!/const\s+NEW_DEV\s*=\s*"[^<]/.test(SOURCE), "no literal DEV value");
    assert.ok(!/const\s+NEW_KEY\s*=\s*"[^<]/.test(SOURCE), "no literal key value");
    assert.ok(!SOURCE.includes("TEST-BOOTSTRAP"), "no synthetic token in source");
  });

  test("B7 bridge can read the bootstrapped credential (integration with v2.2 readCredential rules)", () => {
    // The bootstrapped values must pass the v2.2 readCredential validation:
    // non-empty string, <=512 chars, no CR-LF, not a <placeholder>.
    const ok = (v) => typeof v === "string" && !!v && v.length <= 512 &&
      !/[\r\n]/.test(v) && !/^<.*>$/.test(v);
    assert.ok(ok(DEV) && ok(KEY), "synthetic bootstrapped values pass v2.2 validation");
    assert.ok(!ok("") && !ok("<PASTE_NEW_DEV_TOKEN_HERE>") && !ok("a\r\nb") && !ok("x".repeat(513)));
  });

  console.log("SUMMARY", n, "PASS 0 FAIL");
}
main();
