"use strict";
/* C3-C0 Round 4 — Item 1: credential provisioning demo (isolated).
 *
 * Walks the full provisioning flow end to end in a mock environment:
 *   Shortcuts intent parameter -> candidate staging (DEV + local key,
 *   independent single-key operations) -> verification (candidates
 *   present, active keys unchanged, status markers) -> the list of
 *   what is STILL UNVERIFIED on the real device.
 *
 * Synthetic tokens only. No network, no phone, no real credentials.
 * The demo prints ONLY non-secret status enums and booleans — never
 * a token, never a digest, never a key value. The two candidate
 * templates are executed for real (vm sandbox), not re-implemented:
 * the demo loads bootstrap_candidate_shortcuts.template.js and
 * bootstrap_candidate_localkey.template.js from this directory.
 *
 * Run: node provisioning_demo.js   (exit 0 on success, 1 on failure)
 */
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const DEV_SRC = fs.readFileSync(path.join(__dirname,
  "bootstrap_candidate_shortcuts.template.js"), "utf8");
const KEY_SRC = fs.readFileSync(path.join(__dirname,
  "bootstrap_candidate_localkey.template.js"), "utf8");

const DEV_STAGED = "sgbridge_cred_dev_candidate";
const DEV_ACTIVE = "sgbridge_cred_dev";
const DEV_STATUS = "sgbridge_cred_bootstrap_status";
const KEY_STAGED = "sgbridge_cred_localkey_candidate";
const KEY_ACTIVE = "sgbridge_cred_localkey";
const KEY_STATUS = "sgbridge_cred_localkey_bootstrap_status";

/* Synthetic tokens only. These values exist ONLY in this process's
 * memory and are never printed, logged, or hashed by the demo. */
const DEV_NEW = "TEST-NEW-DEV-CANDIDATE-0123456789ABCDEF";
const KEY_NEW = "TEST-NEW-LOCALKEY-CANDIDATE-0123456789ABC";
const DEV_OLD = "TEST-ACTIVE-OLD-DEV-0123456789ABCDEF";
const KEY_OLD = "TEST-ACTIVE-OLD-LOCALKEY-0123456789ABCDE";

/* Still unverified on the real device. The demo proves the isolated
 * flow only; every item below needs a separate real-device gate. */
const UNVERIFIED_ON_REAL_DEVICE = [
  "script_run_logs_retention",
  "shortcuts_input_history",
  "cross_script_persistent_store_access",
  "ios_icloud_backup",
  "script_cache_leakage",
  "device_side_log_check",
  "other_scripts_permissions",
  "candidate_key_visibility",
  "production_token_format_window",
  "promotion_gate_approval",
  "server_dual_token_revocation",
  "real_device_staging_run",
  "real_device_loading_two_cron_cycles",
];

/* Runs one candidate-staging template in a Surge-like sandbox.
 * Returns the status enum the template recorded (or "no_status"
 * if the template never wrote one). */
function runTemplate(src, parameter, store) {
  let done = 0;
  const sandbox = {
    $trigger: "intent",
    $intent: { parameter },
    $persistentStore: {
      read: (k) => {
        const v = store.get(k);
        return v === undefined ? null : v;
      },
      write: (value, k) => {
        store.set(k, value);
        return true;
      },
    },
    $done: () => { done += 1; },
  };
  vm.runInNewContext(src, sandbox, { timeout: 1000 });
  if (done !== 1) throw new Error("template did not call $done exactly once");
  const status = store.get(
    src === DEV_SRC ? DEV_STATUS : KEY_STATUS);
  return typeof status === "string" ? status : "no_status";
}

function main() {
  console.log("PROVISIONING_DEMO: start (isolated mock, synthetic tokens only)");
  /* The mock phone already has the OLD active credentials. */
  const store = new Map([[DEV_ACTIVE, DEV_OLD], [KEY_ACTIVE, KEY_OLD]]);

  const devStatus = runTemplate(DEV_SRC, DEV_NEW, store);
  console.log("STEP 1 dev_candidate_staging: " + devStatus);
  const keyStatus = runTemplate(KEY_SRC, KEY_NEW, store);
  console.log("STEP 2 localkey_candidate_staging: " + keyStatus);

  const devPresent = store.get(DEV_STAGED) === DEV_NEW;
  const keyPresent = store.get(KEY_STAGED) === KEY_NEW;
  const devActiveUnchanged = store.get(DEV_ACTIVE) === DEV_OLD;
  const keyActiveUnchanged = store.get(KEY_ACTIVE) === KEY_OLD;
  console.log("VERIFY dev_candidate_present: " + devPresent);
  console.log("VERIFY localkey_candidate_present: " + keyPresent);
  console.log("VERIFY dev_active_unchanged: " + devActiveUnchanged);
  console.log("VERIFY localkey_active_unchanged: " + keyActiveUnchanged);
  console.log("VERIFY dev_status: " + devStatus);
  console.log("VERIFY localkey_status: " + keyStatus);

  console.log("UNVERIFIED_ON_REAL_DEVICE:");
  for (const item of UNVERIFIED_ON_REAL_DEVICE) {
    console.log("- " + item);
  }

  const ok = devStatus === "candidate_staged" &&
    keyStatus === "candidate_staged" &&
    devPresent && keyPresent &&
    devActiveUnchanged && keyActiveUnchanged;
  if (!ok) {
    console.log("PROVISIONING_DEMO: FAIL (a step did not reach candidate_staged)");
    process.exitCode = 1;
    return;
  }
  console.log("PROVISIONING_DEMO: done (0 secrets printed)");
}

main();
