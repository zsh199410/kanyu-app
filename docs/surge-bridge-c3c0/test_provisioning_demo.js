"use strict";
/* C3-C0 Round 4 — Item 1 test: provisioning demo (isolated).
 *
 * Spawns provisioning_demo.js as a child process and asserts on its
 * REAL output: both candidates staged, active keys unchanged, no
 * secret in any output, exit 0. Synthetic tokens only, no network,
 * no phone.
 *
 * The test knows the synthetic token values (they are the demo's
 * inputs) precisely so it can prove none of them appears in the
 * demo's output. A blanket check also rejects any "TEST-" string
 * in the output.
 */
const assert = require("node:assert/strict");
const { spawnSync } = require("node:child_process");
const path = require("node:path");

const DEMO = path.join(__dirname, "provisioning_demo.js");

/* The demo's synthetic inputs — asserted ABSENT from its output. */
const SECRET_VALUES = [
  "TEST-NEW-DEV-CANDIDATE-0123456789ABCDEF",
  "TEST-NEW-LOCALKEY-CANDIDATE-0123456789ABC",
  "TEST-ACTIVE-OLD-DEV-0123456789ABCDEF",
  "TEST-ACTIVE-OLD-LOCALKEY-0123456789ABCDE",
];

const UNVERIFIED_ITEMS = [
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

let count = 0;
function check(name, fn) {
  fn();
  count += 1;
  console.log("PASS", name);
}

const run = spawnSync(process.execPath, [DEMO], { encoding: "utf8" });
const out = run.stdout || "";
const err = run.stderr || "";

check("demo exits 0 with no stderr", () => {
  assert.equal(run.status, 0, "exit code: " + run.status + " stderr: " + err);
  assert.equal(err, "", "stderr must be empty");
});

check("both candidates staged", () => {
  assert.ok(out.includes("STEP 1 dev_candidate_staging: candidate_staged"),
    "DEV candidate step missing");
  assert.ok(out.includes("STEP 2 localkey_candidate_staging: candidate_staged"),
    "local-key candidate step missing");
});

check("verification confirms candidates present, active keys unchanged", () => {
  assert.ok(out.includes("VERIFY dev_candidate_present: true"));
  assert.ok(out.includes("VERIFY localkey_candidate_present: true"));
  assert.ok(out.includes("VERIFY dev_active_unchanged: true"));
  assert.ok(out.includes("VERIFY localkey_active_unchanged: true"));
  assert.ok(out.includes("VERIFY dev_status: candidate_staged"));
  assert.ok(out.includes("VERIFY localkey_status: candidate_staged"));
});

check("demo lists what is still unverified on the real device", () => {
  assert.ok(out.includes("UNVERIFIED_ON_REAL_DEVICE:"));
  for (const item of UNVERIFIED_ITEMS) {
    assert.ok(out.includes("- " + item), "unverified item missing: " + item);
  }
});

check("no secret in any output", () => {
  for (const secret of SECRET_VALUES) {
    assert.equal(out.includes(secret), false,
      "output leaks a synthetic token value");
    assert.equal(err.includes(secret), false,
      "stderr leaks a synthetic token value");
  }
  assert.equal(out.includes("TEST-"), false,
    "output contains a TEST- string");
  assert.equal(err.includes("TEST-"), false,
    "stderr contains a TEST- string");
});

console.log("SUMMARY", count, "PASS, 0 FAIL");
