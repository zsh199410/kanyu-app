/* Surge iOS CRON diagnostic-only canary — Issue #73 C.
 * TEMPLATE ONLY, not deployable until Muse privately substitutes the
 * exact trusted base URL, device token and existing store key.
 *
 * This script only reads the legacy persistent key and GETs /poll,
 * then POSTs a bounded diagnostic to /diagnostic. It never uses
 * $httpAPI, never dispatches cmd.actions, never touches last_id or
 * /result, and cannot clear the server's current pending command.
 *
 * If status is not 200, token/path/key invalid, or network fails,
 * it exits fail-closed. No credentials or proxy URLs in logs.
 */
"use strict";
(function () {
  // Substitute PRIVATELY after comparing exact old bridge.js source:
  const BASE_URL = "__PRIVATE_HTTPS_BRIDGE_BASE__";
  const DEVICE_TOKEN = "__PRIVATE_DEVICE_TOKEN__";
  const LEGACY_LAST_ID_KEY = "__EXACT_OLD_BRIDGE_LAST_ID_KEY__";

  let finished = false;
  function done(code) {
    if (finished) return;
    finished = true;
    try { console.log("bridge diagnostic canary: " + code); }
    catch (_) {}
    $done();
  }
  function ready() {
    return /^https:\/\/[^\s?#/]+(?:\:[0-9]{1,5})?(?:\/[^?#]*)?$/.test(BASE_URL)
      && !BASE_URL.includes("__")
      && DEVICE_TOKEN.length >= 16 && !DEVICE_TOKEN.includes("__")
      && /^[a-zA-Z0-9._-]{1,100}$/.test(LEGACY_LAST_ID_KEY)
      && !LEGACY_LAST_ID_KEY.includes("__");
  }
  if (!ready()) { done("NOT_CONFIGURED"); return; }

  let legacyRaw;
  try { legacyRaw = $persistentStore.read(LEGACY_LAST_ID_KEY); }
  catch (_) { done("STORE_UNAVAILABLE"); return; }
  let id = 0;
  let checkpointValid = false;
  if (typeof legacyRaw === "string" && /^\d+$/.test(legacyRaw)) {
    const num = Number(legacyRaw);
    if (Number.isSafeInteger(num) && num >= 0) {
      id = num;
      checkpointValid = true;
    }
  }
  const endpoint = BASE_URL.replace(/\/$/, "");
  const headers = {"X-Dev-Token": DEVICE_TOKEN,
                   "Content-Type": "application/json"};
  // A GET /poll increments legacy poll counters but NEVER modifies cmd
  // or result. It is preferable to a fabricated hard-coded pending id.
  $httpClient.get({
    url: endpoint + "/poll", headers, timeout: 8,
    "auto-redirect": false, "auto-cookie": false,
  }, function (error, response, data) {
    if (finished) return;
    if (error || !response || response.status !== 200) {
      done("POLL_UNAVAILABLE"); return;
    }
    let cmd;
    try { cmd = JSON.parse(data); }
    catch (_) { done("POLL_JSON_INVALID"); return; }
    if (!cmd || !Number.isSafeInteger(cmd.id) || cmd.id < 0) {
      done("POLL_ID_INVALID"); return;
    }
    const diagnostic = {
      code: checkpointValid ? "LEGACY_PENDING_FENCED"
                            : "LEGACY_CHECKPOINT_INVALID",
      command_id: cmd.id,
      legacy_last_id: id,
      phase: "none"
    };
    // This endpoint must have been tested on the PRIVATE server first.
    // Never substitute /result: it can clear the pending old command.
    $httpClient.post({
      url: endpoint + "/diagnostic", headers, timeout: 8,
      "auto-redirect": false, "auto-cookie": false,
      body: JSON.stringify(diagnostic)
    }, function (postError, postResponse, body) {
      if (postError || !postResponse || postResponse.status !== 200) {
        done("DIAGNOSTIC_NOT_ACKED"); return;
      }
      let parsed;
      try { parsed = JSON.parse(body); }
      catch (_) { done("DIAGNOSTIC_ACK_INVALID"); return; }
      done(parsed && parsed.diagnostic_stored === true ?
           "DIAGNOSTIC_ACKED" : "DIAGNOSTIC_ACK_INVALID");
    });
  });
})();
