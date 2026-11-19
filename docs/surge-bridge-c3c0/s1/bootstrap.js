// One-time Surge credential bootstrap (C3-C0 S1).
//
// PURPOSE: write the NEW DEV token and the local Surge HTTP API key into
// the phone's $persistentStore, so the distributed bridge script
// (bridge_fixed_v2.js, v2.2+) can read them at runtime instead of
// carrying them in the downloaded file.
//
// HOW THE OWNER USES IT (do NOT distribute this script by URL):
//   1. Generate the new DEV token server-side (root-only file on the VPS;
//      never via a public URL, chat, or email). Note its SHA-256
//      fingerprint (first 16 hex chars) from the server for the record.
//   2. In the Surge app on the phone, create a NEW local script and paste
//      THIS file's contents into it. Replace the two <PASTE_...> constants
//      below with the new DEV token and the local API key.
//   3. Run the script ONCE (manual run). Read the notification/log: it
//      must say exactly "bootstrap_ok" and nothing else.
//   4. DELETE this script from Surge immediately (required). A Surge
//      script cannot delete itself; manual deletion is a checklist step.
//   5. Verify: on the next bridge cron run the phase log shows
//      "credential_present", and the server-side /poll returns 200 (not
//      403). That is the functional proof the right token is stored.
//
// SAFETY:
//   - The token is NEVER sent over the network, NEVER logged, and NEVER
//     written to any file except $persistentStore. The only output is a
//     status word ("bootstrap_ok" / "bootstrap_failed: ...").
//   - The script validates the pasted values (non-empty, <=512 chars,
//     no CR-LF, not a <placeholder>) and verifies the write by reading
//     the values back and comparing them exactly.
//   - After a successful run it sets sgbridge_bootstrap_done, so a
//     second run does nothing (it cannot re-expose or overwrite the
//     credential).
//   - $persistentStore is a simple persistent key-value API, NOT a proven
//     secure hardware keystore. This bootstrap removes the credential
//     from the PUBLICLY DISTRIBUTED script; it does NOT claim the
//     credential is stored in a secure enclave. See BOOTSTRAP_DESIGN.md.
(function () {
  var NEW_DEV = "<PASTE_NEW_DEV_TOKEN_HERE>";
  var NEW_KEY = "<PASTE_NEW_LOCAL_KEY_HERE>";
  var DEV_KEY = "sgbridge_cred_dev";
  var LOCAL_KEY = "sgbridge_cred_localkey";
  var DONE_KEY = "sgbridge_bootstrap_done";

  function valid(value) {
    return typeof value === "string" && value.length > 0 &&
      value.length <= 512 && !/[\r\n]/.test(value) &&
      !/^<.*>$/.test(value);
  }
  function log(msg) {
    try { console.log("[sgbridge-bootstrap] " + msg); } catch (_e) {}
    try { $notification.post("Surge Bridge bootstrap", "", msg); } catch (_e) {}
  }

  // Already bootstrapped: do nothing (cannot re-expose or overwrite).
  var done = null;
  try { done = $persistentStore.read(DONE_KEY); } catch (_e) { done = null; }
  if (done) { log("bootstrap_already_done"); $done({}); return; }

  if (!valid(NEW_DEV) || !valid(NEW_KEY)) {
    log("bootstrap_failed: invalid_input");
    $done({});
    return;
  }

  var ok = false;
  try {
    var w1 = $persistentStore.write(NEW_DEV, DEV_KEY);
    var w2 = $persistentStore.write(NEW_KEY, LOCAL_KEY);
    if (w1 === true && w2 === true) {
      var back1 = $persistentStore.read(DEV_KEY);
      var back2 = $persistentStore.read(LOCAL_KEY);
      ok = (back1 === NEW_DEV && back2 === NEW_KEY);
    }
  } catch (_e) { ok = false; }

  if (!ok) {
    log("bootstrap_failed: write_or_verify");
    $done({});
    return;
  }

  try { $persistentStore.write("1", DONE_KEY); } catch (_e) {}
  log("bootstrap_ok");
  $done({});
})();
