/* Mock Surge script runtime for P0-E tests (MOCK ONLY — not a real device).
 *
 * Executes the REAL gate JS files (device-gate/gate-script.js,
 * gate-events.js, gate-sweep.js, and controller-generated issue/read/
 * revoke scripts) inside Node's vm module with mocked Surge globals:
 * $persistentStore (backed by a JSON store file), $network, $script,
 * $request, $event, $surge (selectGroupDetails / setSelectGroupPolicy /
 * logbook), $done, console.log.
 *
 * Usage:
 *   node mock_surge_runtime.js <mode> <scriptPath|-> <storePath> <scenarioPath>
 * Modes:
 *   rule      scriptPath = gate-script.js (rule evaluation)
 *   event     scriptPath = gate-events.js ($event.name from scenario)
 *   cron      scriptPath = gate-sweep.js
 *   evaluate  scriptPath = "-" ; scenario.script_text is executed
 *
 * scenario JSON fields (all optional unless noted):
 *   network    {$network object}
 *   decisions  {groupName: selectedPolicy} for selectGroupDetails()
 *   surgeSetOk bool (default true) — setSelectGroupPolicy return value
 *   now        epoch seconds for $script.startTime (default 1700000000)
 *   scriptName, scriptType
 *   eventName  ($event.name)
 *   request    {$request object}
 *   script_text (evaluate mode only)
 *
 * The store file is read before the run and written back after, so a
 * sequence of runs (e.g. engine-started event, then rule evaluation)
 * shares persistent state exactly like $persistentStore on a device.
 *
 * Output: one JSON object on stdout:
 *   {doneCalled, doneValue, store, surgeCalls, logbook, logs}
 *
 * MOCK BOUNDARY: this proves the JavaScript LOGIC against scripted
 * inputs. It does NOT prove real-device behaviour: rule-script hot-path
 * availability of $surge.selectGroupDetails, $persistentStore.write
 * persistence from an http-api-evaluated script, event ordering vs the
 * first request after boot, and the real evaluate response shape all
 * need a real device (see device-gate/README.md).
 */
"use strict";

const fs = require("fs");
const vm = require("vm");

function main() {
  const mode = process.argv[2];
  const scriptPath = process.argv[3];
  const storePath = process.argv[4];
  const scenarioPath = process.argv[5];
  if (!mode || !scriptPath || !storePath || !scenarioPath) {
    console.error(
      "usage: node mock_surge_runtime.js <rule|event|cron|evaluate> <scriptPath|-> <storePath> <scenarioPath>"
    );
    process.exit(2);
  }

  const scenario = JSON.parse(fs.readFileSync(scenarioPath, "utf-8"));
  let store = {};
  try {
    store = JSON.parse(fs.readFileSync(storePath, "utf-8"));
    if (!store || typeof store !== "object") store = {};
  } catch (e) {
    store = {};
  }

  let source;
  if (mode === "evaluate") {
    source = scenario.script_text || "";
  } else {
    source = fs.readFileSync(scriptPath, "utf-8");
  }

  const now = typeof scenario.now === "number" ? scenario.now : 1700000000;
  const decisions = Object.assign({}, scenario.decisions || {});
  const surgeSetOk = scenario.surgeSetOk !== false;
  const surgeCalls = [];
  const logbook = [];
  const logs = [];
  let doneCalled = false;
  let doneValue = null;

  const sandbox = {
    console: {
      log: function (msg) {
        try {
          logs.push(typeof msg === "string" ? msg : JSON.stringify(msg));
        } catch (e) {
          logs.push(String(msg));
        }
      },
    },
    $persistentStore: {
      read: function (key) {
        const v = store[key];
        return v === undefined ? null : v;
      },
      write: function (data, key) {
        if (data === null || data === undefined) {
          delete store[key];
        } else {
          store[key] = String(data);
        }
        return true;
      },
    },
    $network: scenario.network || {},
    $script: {
      name: scenario.scriptName || "gate",
      type: scenario.scriptType || mode,
      startTime: now,
      sessionID: "mock-session",
    },
    $request: scenario.request || {
      hostname: "example.com",
      destPort: 443,
      protocol: "HTTPS",
    },
    $event: { name: scenario.eventName || "", data: scenario.eventData || {} },
    $cronexp: scenario.cronexp || "*/10 * * * *",
    $surge: {
      selectGroupDetails: function () {
        return { groups: {}, decisions: Object.assign({}, decisions) };
      },
      setSelectGroupPolicy: function (group, policy) {
        surgeCalls.push({ method: "setSelectGroupPolicy", group, policy });
        if (surgeSetOk) decisions[group] = policy;
        return surgeSetOk;
      },
      logbook: function (content) {
        logbook.push(String(content));
      },
    },
    $notification: {
      post: function () {},
    },
    $httpClient: {
      get: function () {
        throw new Error("mock $httpClient not available");
      },
    },
    $httpAPI: function () {
      throw new Error("mock $httpAPI not available");
    },
    $done: function (value) {
      doneCalled = true;
      doneValue = value === undefined ? null : value;
    },
  };
  sandbox.global = sandbox;
  vm.createContext(sandbox);

  let runError = null;
  try {
    vm.runInContext(source, sandbox, { filename: scriptPath });
  } catch (e) {
    runError = String(e && e.stack ? e.stack : e);
  }

  try {
    fs.writeFileSync(storePath, JSON.stringify(store, null, 2));
  } catch (e) {
    /* store write failure must not hide the run result */
  }

  process.stdout.write(
    JSON.stringify({
      doneCalled,
      doneValue,
      store,
      surgeCalls,
      logbook,
      logs,
      runError,
    })
  );
}

main();
