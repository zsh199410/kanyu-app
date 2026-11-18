/* Device-side independent security gate — EVENT scripts (type=event).
 *
 * One file, three declarations in device-gate-test.conf:
 *   gate-events-boot    = type=event,event-name=engine-started,   script-path=gate-events.js
 *   gate-events-net     = type=event,event-name=network-changed,  script-path=gate-events.js
 *   gate-events-profile = type=event,event-name=profile-reloaded, script-path=gate-events.js
 *
 * Behaviour (all fail-closed; every branch ends with $done()):
 * - engine-started:   mint a FRESH boot id, DELETE the lease, DELETE the
 *                     last-seen guard, force the select group to REJECT.
 *                     A reboot must never silently trust a pre-reboot
 *                     lease. Traffic stays REJECT until the controller
 *                     re-issues a lease bound to the new boot id.
 * - network-changed:  DELETE the lease, DELETE the last-seen guard, force
 *                     the select group to REJECT. The lease was bound to
 *                     the old network fingerprint; the per-request rule
 *                     script would deny anyway, but the event also removes
 *                     the stale lease and the stale selection so nothing
 *                     lingers.
 * - profile-reloaded: same as network-changed. A reloaded profile may
 *                     have different members/policies; a lease issued
 *                     against the old profile must not survive it.
 * - manually / other: log only; never destroy state on an accidental tap.
 *
 * Official behaviour relied on (manual.nssurge.com, read 2026-11-18):
 * - Events: "network-changed: Triggered when the system network changes."
 *   "engine-started: Triggered once after the Surge engine finishes
 *   starting, when the Network Extension and the active profile are fully
 *   initialized, so $network is ready to read. ... iOS 5.22.0+ Mac 6.9.0+"
 *   "profile-reloaded: Triggered after the active profile is reloaded at
 *   runtime. The initial profile load at engine startup does not count as
 *   a reload; hook engine-started for that. ... iOS 5.22.0+ Mac 6.9.0+"
 *   (scripting/event.html)
 * - "$surge.setSelectGroupPolicy(groupName, policyName): Changes the
 *   selected policy of a select policy group." and "All setters return a
 *   Boolean indicating success." (scripting/api.html)
 * - "$persistentStore.write(data, [key]): ... Passing null as the data
 *   deletes the entry." (scripting/api.html)
 * - "The script must call $done() to complete. The result object is
 *   ignored; a bare $done() is enough." (scripting/event.html)
 *
 * Known limits (UNPROVEN on a real device — see README.md):
 * - engine-started requires Surge iOS 5.22.0+ / Mac 6.9.0+. On older
 *   builds the boot-revocation event never fires and only the lease TTL
 *   bounds the stale-lease window.
 * - Ordering between engine-started and the first rule evaluation after
 *   a reboot is NOT documented. A request evaluated before the event
 *   script runs could still see the old lease + old boot id (both
 *   persisted). The window is bounded by the lease TTL (600 s) and by
 *   the rule script's own checks, but it is NOT proven closed.
 * - $surge.setSelectGroupPolicy() returning false is recorded in the
 *   logbook but cannot be retried from inside the event; the per-request
 *   rule script is the backstop (it denies when the selection is not the
 *   leased proxy).
 *
 * ES5 style (JavaScriptCore), same as gate-script.js.
 */

var GATE_GROUP = "测试安全出口";
var LEASE_KEY = "device-gate-lease-v1";
var BOOT_KEY = "device-gate-boot-v1";
var LASTSEEN_KEY = "device-gate-lastseen-v1";

function mintBootId(nowSeconds) {
  var rand = "";
  var i;
  var chars = "0123456789abcdef";
  for (i = 0; i < 16; i++) {
    rand += chars.charAt(Math.floor(Math.random() * 16));
  }
  return "boot-" + String(nowSeconds) + "-" + rand;
}

function revokeLease(reason) {
  var okSelect = false;
  try { $persistentStore.write(null, LEASE_KEY); } catch (e) {}
  try { $persistentStore.write(null, LASTSEEN_KEY); } catch (e) {}
  try {
    okSelect = $surge.setSelectGroupPolicy(GATE_GROUP, "REJECT");
  } catch (e) {
    okSelect = false;
  }
  try {
    $surge.logbook("gate: revoke lease (" + reason + "), select REJECT=" + okSelect);
  } catch (e) {}
  return okSelect;
}

(function runEventScript() {
  try {
    var name = "";
    try { name = ($event && $event.name) || ""; } catch (e) { name = ""; }

    if (name === "engine-started") {
      var bootId = mintBootId($script.startTime);
      try { $persistentStore.write(bootId, BOOT_KEY); } catch (e) {}
      revokeLease("engine-started");
      try { $surge.logbook("gate: engine-started, new boot " + bootId); } catch (e) {}
    } else if (name === "network-changed" || name === "profile-reloaded") {
      revokeLease(name);
    } else {
      /* manually / notification / unknown: never destroy state. */
      try { $surge.logbook("gate: event " + name + " ignored"); } catch (e) {}
    }
    $done();
  } catch (e) {
    try { $done(); } catch (e2) {}
  }
})();
