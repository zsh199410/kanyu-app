"use strict";
/* Independent, self-contained regression for the ACTUAL sanitized v2 bridge.
 * No simulator dependency, sockets, real tokens, or phone contact.
 * Specifically tests Surge $persistentStore.write returning false.
 */
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const source = fs.readFileSync(path.join(__dirname, "bridge_fixed_v2.js"), "utf8");
const ID = 1795063031;
const LAST = 1795055213880;

async function run({ failLedgerAt = 0, throwLedgerAt = 0, bootstrap = false } = {}) {
  const store = new Map([["sgbridge_last_id", String(LAST)],
    ["sgbridge_cred_dev", "TEST-DEV-MOCK-ONLY"],
    ["sgbridge_cred_localkey", "TEST-LOCAL-MOCK-ONLY"]]);
  if (!bootstrap) store.set("sgbridge_ledger_v1", JSON.stringify({
    version: 1, floor: LAST, last_acked_id: 0, pending: null
  }));
  let ledgerWrites = 0;
  let dispatches = 0;
  let resultPosts = 0;
  let legacyWrites = 0;
  let doneCalls = 0;
  const cmd = { id: ID, actions: [{ type: "notify", text: "synthetic" }] };
  let finish;
  const donePromise = new Promise(resolve => { finish = resolve; });
  const context = {
    $persistentStore: {
      read: key => store.has(key) ? store.get(key) : null,
      write: (value, key) => {
        if (key === "sgbridge_ledger_v1") {
          ledgerWrites++;
          if (ledgerWrites === throwLedgerAt) throw Error("synthetic_disk_error");
          if (ledgerWrites === failLedgerAt) return false;
        }
        if (key === "sgbridge_last_id") legacyWrites++;
        store.set(key, value);
        return true;
      }
    },
    $httpClient: {
      get: (_opts, cb) => cb(null, { status: 200 }, JSON.stringify(cmd)),
      post: (opts, cb) => {
        resultPosts++;
        const p = JSON.parse(opts.body);
        cb(null, { status: 200 },
           JSON.stringify({ accepted: true, acked_id: p.id }));
      }
    },
    $notification: { post: () => { dispatches++; } },
    $done: () => { doneCalls++; finish(); },
    setTimeout,
    clearTimeout,
    Date,
    JSON,
    Promise,
    Number,
    String,
    Array,
    Math,
    console: { log: () => {} }
  };
  vm.runInNewContext(source, context, { timeout: 1000 });
  await Promise.race([
    donePromise,
    new Promise((_resolve, reject) =>
      setTimeout(() => reject(Error("script_not_done")), 3000))
  ]);
  assert.equal(doneCalls, 1, "exactly one $done");
  return { dispatches, resultPosts, legacyWrites, ledgerWrites, store };
}

async function main() {
  let n = 0;
  const assertCase = async (title, args, expected) => {
    const got = await run(args);
    for (const [k, val] of Object.entries(expected)) {
      assert.equal(got[k], val, title + " " + k);
    }
    n++;
    console.log("PASS", title);
  };
  await assertCase("false return on in_progress blocks dispatch",
    { failLedgerAt: 1 },
    { dispatches: 0, resultPosts: 0, legacyWrites: 0, ledgerWrites: 1 });
  await assertCase("false return on result_ready blocks result delivery",
    { failLedgerAt: 2 },
    { dispatches: 1, resultPosts: 0, legacyWrites: 0, ledgerWrites: 2 });
  await assertCase("exception on in_progress blocks dispatch",
    { throwLedgerAt: 1 },
    { dispatches: 0, resultPosts: 0, legacyWrites: 0, ledgerWrites: 1 });
  await assertCase("false return on first bootstrap blocks progress",
    { bootstrap: true, failLedgerAt: 1 },
    { dispatches: 0, resultPosts: 0, legacyWrites: 0, ledgerWrites: 1 });
  await assertCase("successful checkpoints still dispatch and ACK",
    {},
    { dispatches: 1, resultPosts: 1, legacyWrites: 1, ledgerWrites: 3 });
  console.log("SUMMARY", n, "PASS, 0 FAIL");
}

main().catch(e => { console.error(e.message); process.exitCode = 1; });
