/* Device-side independent security gate — CRON sweep (type=cron).
 *
 * Declaration in device-gate-test.conf:
 *   gate-sweep = type=cron,cronexp="*\/10 * * * *",script-path=gate-sweep.js
 * (every 10 minutes = 6 runs/hour, under the manual's battery-warning
 * threshold of "more than 10 times per hour"; scripting/cron.html).
 *
 * Role: BACKUP ONLY. The per-request rule script (gate-script.js) is the
 * primary gate and checks the lease on every new request; this sweep does
 * NOT replace it and the design never relies on the sweep firing on time
 * (a missed cron fire while the app is suspended only delays cleanup —
 * the rule script still denies expired leases on the next request).
 *
 * Each run:
 * - No lease stored: if the select group currently selects a proxy (not
 *   REJECT), force it to REJECT. A proxy selection with no authorising
 *   lease must not linger.
 * - Lease stored but corrupt / stopped / expired / TTL-insane: delete the
 *   lease (and the last-seen guard) and force the group to REJECT.
 * - Lease stored and not expired: leave the selection alone. Full
 *   validation (network fingerprint, boot id, selection match, clock
 *   anomaly) is the rule script's job on every request, not the sweep's.
 *
 * Official behaviour relied on (manual.nssurge.com, read 2026-11-18):
 * - "A cron script runs on a schedule described by a cron expression."
 *   "A cron script that fires more than 10 times per hour triggers a
 *   battery consumption warning." "The script must call $done() to
 *   complete." (scripting/cron.html)
 * - Cron example switching a select group: "$surge.setSelectGroupPolicy
 *   ('Group', 'Proxy');" (scripting/cron.html)
 * - wake-system: "Without it, a fire time may be missed while the app is
 *   suspended by the system." (scripting/cron.html) — the sweep is
 *   therefore best-effort by design; the rule script is the guarantee.
 *
 * ES5 style (JavaScriptCore), same as gate-script.js.
 */

var GATE_GROUP = "测试安全出口";
var LEASE_KEY = "device-gate-lease-v1";
var LASTSEEN_KEY = "device-gate-lastseen-v1";
var MAX_TTL_SECONDS = 3600;

function forceReject(reason) {
  var ok = false;
  try {
    ok = $surge.setSelectGroupPolicy(GATE_GROUP, "REJECT");
  } catch (e) {
    ok = false;
  }
  try {
    $surge.logbook("gate-sweep: force REJECT (" + reason + ") ok=" + ok);
  } catch (e) {}
  return ok;
}

/* Sweep-level lease check (subset of the rule script's decide()).
 * Returns "ok", "no-lease", or a reason string for a bad lease. */
function sweepCheckLease(raw, now) {
  var lease;
  if (!raw) { return "no-lease"; }
  try {
    lease = JSON.parse(raw);
  } catch (e) {
    return "corrupt-lease";
  }
  if (!lease || typeof lease !== "object" || lease.v !== 1) {
    return "bad-lease";
  }
  if (lease.stopped === true) { return "stopped"; }
  if (typeof lease.issued_at !== "number" ||
      typeof lease.expires_at !== "number" ||
      typeof lease.ttl_seconds !== "number") {
    return "bad-lease-times";
  }
  if (lease.ttl_seconds <= 0 || lease.ttl_seconds > MAX_TTL_SECONDS ||
      lease.expires_at - lease.issued_at !== lease.ttl_seconds) {
    return "bad-ttl";
  }
  if (typeof now !== "number" || isNaN(now)) { return "bad-now"; }
  if (now > lease.expires_at) { return "lease-expired"; }
  return "ok";
}

(function runSweepScript() {
  try {
    var now = $script.startTime;
    var raw = null;
    try { raw = $persistentStore.read(LEASE_KEY); } catch (e) { raw = null; }
    var check = sweepCheckLease(raw, now);

    if (check === "ok") {
      try { $surge.logbook("gate-sweep: lease ok, no action"); } catch (e) {}
      $done();
      return;
    }

    /* Bad or absent lease: remove it (if present) and force REJECT. */
    if (check !== "no-lease") {
      try { $persistentStore.write(null, LEASE_KEY); } catch (e) {}
      try { $persistentStore.write(null, LASTSEEN_KEY); } catch (e) {}
      forceReject(check);
      $done();
      return;
    }

    /* No lease at all: only act if a proxy is currently selected. */
    var selected = null;
    try {
      var details = $surge.selectGroupDetails();
      if (details && details.decisions) {
        selected = details.decisions[GATE_GROUP] || null;
      }
    } catch (e) {
      selected = null;
    }
    if (selected && selected !== "REJECT") {
      forceReject("no-lease-selection-" + selected);
    } else {
      try { $surge.logbook("gate-sweep: no lease, already REJECT"); } catch (e) {}
    }
    $done();
  } catch (e) {
    try { $done(); } catch (e2) {}
  }
})();
