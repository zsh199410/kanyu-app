/* Device-side independent security gate — RULE script (type=rule).
 *
 * Purpose: per-request, device-local, fail-closed authorisation for the
 * gated select group "测试安全出口". This script is the FIRST rule in
 * device-gate-test.conf; everything that does not match it falls through
 * to FINAL,REJECT. It runs on the device for every new request, with no
 * controller contact in the hot path.
 *
 * Decision model (default deny):
 *   matched = true  ONLY when a lease stored in $persistentStore passes
 *                     EVERY check below, in this run, right now.
 *   matched = false in every other case (no lease, expired lease, STOP,
 *                     SHA mismatch, network change, boot mismatch,
 *                     selection mismatch, clock anomaly, corrupt state,
 *                     any exception). A false result makes Surge continue
 *                     to the next rule, which is FINAL,REJECT.
 *
 * Official behaviour relied on (manual.nssurge.com, read 2026-11-18):
 * - Rule script: "$done({matched: true/false})"; "If the script is missing
 *   or scripting is disabled, the rule is treated as not matched."
 *   (scripting/rule.html) — so a missing/disabled gate script fails
 *   CLOSED by falling through to FINAL,REJECT, provided no earlier rule
 *   can match protected traffic and FINAL is REJECT (enforced by
 *   check_gate_conf.py).
 * - "$done() ... An uncaught exception aborts the session and the script
 *   has no effect." (scripting/api.html) — the glue below still wraps
 *   everything in try/catch and answers matched:false explicitly, so the
 *   outcome does not depend on the undocumented exact fall-through of an
 *   aborted rule script.
 * - $persistentStore: "Simple persistent key-value storage ... Saves data
 *   permanently. Only a string is allowed." (scripting/api.html). The
 *   lease is one JSON string under LEASE_KEY. It SURVIVES reboots, which
 *   is why a boot binding (BOOT_KEY, minted by gate-events.js on
 *   engine-started) is required and why a stale lease alone is never
 *   trusted after a restart.
 * - $surge.selectGroupDetails(): "Returns an object describing all select
 *   groups: {groups: {...}, decisions: {groupName: selectedPolicy}}."
 *   (scripting/api.html). The rule script verifies the group's CURRENT
 *   selection equals the lease proxy; a stale/different selection denies.
 *   Globals are "injected into every script, regardless of type", so
 *   $surge is available to rule scripts per the manual — whether calling
 *   it in the hot path works on a real device is UNPROVEN (see README.md);
 *   if it throws or returns nothing the script denies (fail-closed).
 * - $script.startTime: "The time when the current run started, as UNIX
 *   epoch seconds." (scripting/api.html). Used as `now`; the device clock
 *   is therefore a trust input, mitigated by the clock-anomaly checks.
 * - $network: wifi (ssid, bssid), v4 (primaryAddress, primaryInterface,
 *   primaryRouter), v6, dns, and on iOS cellular-data (carrier, radio).
 *   (scripting/api.html). The lease binds a fingerprint of this object;
 *   any change denies until the controller re-issues.
 *
 * What this script deliberately does NOT do:
 * - No $httpClient / $httpAPI calls in the hot path (the manual says rule
 *   scripts should "avoid asynchronous operations where possible"), so a
 *   dead controller or dead network cannot change the verdict.
 * - No $surge.setSelectGroupPolicy() here: switching groups is the job
 *   of gate-events.js / gate-sweep.js (event/cron context). The rule
 *   script only answers matched true/false.
 * - No DIRECT anywhere: this script can only admit traffic to the gated
 *   select group or deny it to FINAL,REJECT. A selected proxy that fails
 *   is never replaced by DIRECT.
 *
 * Engine: JavaScriptCore (engine=jsc in the profile). Written in ES5
 * style on purpose; no arrow functions, no template literals, no
 * const/let, so it also parses under older JSC builds.
 */

var GATE_GROUP = "测试安全出口";
var LEASE_KEY = "device-gate-lease-v1";
var BOOT_KEY = "device-gate-boot-v1";
var LASTSEEN_KEY = "device-gate-lastseen-v1";

/* Expected candidate-set SHA. Canonical form (same as the Python
 * controller's compute_candidate_sha): SHA-256 of
 * json.dumps(sorted(["Test-Proxy-1","Test-Proxy-2","Test-Proxy-3"]),
 *             ensure_ascii=False, sort_keys=True).
 * A lease carrying any other SHA is refused. */
var EXPECTED_CANDIDATE_SHA = "0543b83dfdd1b7555afbcb76a7b11643d1662f863352710b6bc7d8badd0afabd";

/* Allow-listed proxies. The lease proxy must be one of these AND the
 * group's current selection must equal it. */
var ALLOWED_PROXIES = ["Test-Proxy-1", "Test-Proxy-2", "Test-Proxy-3"];

/* Lease TTL bounds (seconds). Leases are issued with ttl_seconds = 600
 * by the controller; anything outside [1, 3600] is refused as corrupt. */
var MAX_TTL_SECONDS = 3600;

/* Clock-skew tolerance (seconds). A `now` earlier than issued_at by more
 * than this, or earlier than the last seen `now` by more than this, is a
 * clock anomaly and denies. A clock set far FORWARD only makes the lease
 * look expired, which also denies. */
var CLOCK_SKEW_SECONDS = 60;

/* ------------------------------------------------------------------ */
/* Pure decision core: no Surge globals, fully unit-testable.          */
/* decide(lease, ctx) -> {matched: boolean, reason: string}            */
/*   lease: parsed lease object, or null.                              */
/*   ctx: {now, netFp, selected, bootId, lastSeen}                     */
/*     now      - current epoch seconds ($script.startTime)            */
/*     netFp    - fingerprint of the current $network                  */
/*     selected - current select-group decision, or null if unknown    */
/*     bootId   - stored boot token, or null if none                   */
/*     lastSeen - last `now` accepted by this script, or null          */
/* ------------------------------------------------------------------ */

function networkFingerprint(network) {
  var parts = [];
  try {
    if (!network) { return "no-network"; }
    var wifi = network.wifi || {};
    var v4 = network.v4 || {};
    var v6 = network.v6 || {};
    var cell = network["cellular-data"] || network.cellularData || {};
    parts.push("ssid=" + (wifi.ssid || ""));
    parts.push("bssid=" + (wifi.bssid || ""));
    parts.push("v4addr=" + (v4.primaryAddress || ""));
    parts.push("v4if=" + (v4.primaryInterface || ""));
    parts.push("v4router=" + (v4.primaryRouter || ""));
    parts.push("v6addr=" + (v6.primaryAddress || ""));
    parts.push("v6if=" + (v6.primaryInterface || ""));
    parts.push("dns=" + ((network.dns || []).join(",")));
    parts.push("carrier=" + (cell.carrier || ""));
    parts.push("radio=" + (cell.radio || ""));
  } catch (e) {
    return "fp-error";
  }
  return fnv1aHex(parts.join("|"));
}

/* FNV-1a 32-bit, hex. Binding check only, not authentication.
 * NOTE: plain `h * 0x01000193` loses low bits in IEEE-754 doubles
 * (product up to 2^56), so the multiply is done in 16-bit halves to
 * stay exact — this must agree bit-for-bit with the Python oracle in
 * tests/test_device_gate.py::py_fingerprint (parity test). */
function fnv1aHex(str) {
  var h = 0x811c9dc5;
  var i, c;
  for (i = 0; i < str.length; i++) {
    c = str.charCodeAt(i);
    h ^= c;
    h = mul32(h, 0x01000193);
  }
  var hex = h.toString(16);
  while (hex.length < 8) { hex = "0" + hex; }
  return "fnv1a-" + hex;
}

function mul32(a, b) {
  var ah = (a >>> 16) & 0xffff, al = a & 0xffff;
  var bh = (b >>> 16) & 0xffff, bl = b & 0xffff;
  var low = al * bl;
  var mid = ((ah * bl + al * bh) & 0xffff) << 16;
  return (low + mid) >>> 0;
}

function isAllowedProxy(name) {
  var i;
  for (i = 0; i < ALLOWED_PROXIES.length; i++) {
    if (ALLOWED_PROXIES[i] === name) { return true; }
  }
  return false;
}

function deny(reason) {
  return { matched: false, reason: reason };
}

function decide(lease, ctx) {
  if (!lease || typeof lease !== "object") {
    return deny("no-lease");
  }
  if (lease.v !== 1) {
    return deny("bad-lease-version");
  }
  if (!isAllowedProxy(lease.proxy)) {
    return deny("proxy-not-allowed");
  }
  if (lease.candidate_sha !== EXPECTED_CANDIDATE_SHA) {
    return deny("candidate-sha-mismatch");
  }
  if (lease.stopped === true) {
    return deny("stopped");
  }
  if (typeof lease.issued_at !== "number" ||
      typeof lease.expires_at !== "number" ||
      typeof lease.ttl_seconds !== "number") {
    return deny("bad-lease-times");
  }
  if (lease.ttl_seconds <= 0 || lease.ttl_seconds > MAX_TTL_SECONDS) {
    return deny("bad-ttl");
  }
  if (lease.expires_at - lease.issued_at !== lease.ttl_seconds) {
    return deny("ttl-inconsistent");
  }
  if (typeof ctx.now !== "number" || isNaN(ctx.now)) {
    return deny("bad-now");
  }
  /* Clock moved backwards past issuance: the lease cannot predate time. */
  if (ctx.now < lease.issued_at - CLOCK_SKEW_SECONDS) {
    return deny("clock-back-before-issue");
  }
  /* Expired (also the outcome of a clock set far forward). */
  if (ctx.now > lease.expires_at) {
    return deny("lease-expired");
  }
  /* Clock moved backwards past the last accepted `now`. */
  if (typeof ctx.lastSeen === "number" && !isNaN(ctx.lastSeen) &&
      ctx.now < ctx.lastSeen - CLOCK_SKEW_SECONDS) {
    return deny("clock-back-vs-lastseen");
  }
  /* Invalid/error fingerprints must NEVER match, even if issuance and
   * checking both failed in the same way (e.g. fp-error==fp-error). */
  if (typeof lease.net_fp !== "string" ||
      !/^fnv1a-[0-9a-f]{8}$/.test(lease.net_fp) ||
      typeof ctx.netFp !== "string" ||
      !/^fnv1a-[0-9a-f]{8}$/.test(ctx.netFp)) {
    return deny("network-fingerprint-unavailable");
  }
  /* Network environment changed since issuance. */
  if (!lease.net_fp || lease.net_fp !== ctx.netFp) {
    return deny("network-fingerprint-mismatch");
  }
  /* Lease predates the current boot (engine-started mints a new boot id
   * and deletes the lease; if that event did not run, the mismatch is
   * still caught here when the boot id differs — and when it does not
   * differ, the TTL bounds the stale-lease window; see README.md). */
  if (!lease.boot_id || !ctx.bootId || lease.boot_id !== ctx.bootId) {
    return deny("boot-mismatch");
  }
  /* The group's CURRENT selection must be exactly the leased proxy.
   * Unknown selection denies: never assume the group is where we left it. */
  if (!ctx.selected || ctx.selected !== lease.proxy) {
    return deny("selection-mismatch");
  }
  return { matched: true, reason: "lease-valid" };
}

/* ------------------------------------------------------------------ */
/* Surge glue (rule-script entry). Runs on load in a real Surge run.  */
/* In the Node mock harness the same globals are injected before load. */
/* ------------------------------------------------------------------ */

(function runRuleScript() {
  try {
    var raw = $persistentStore.read(LEASE_KEY);
    var lease = null;
    if (raw) {
      try {
        lease = JSON.parse(raw);
      } catch (e) {
        lease = null; /* corrupt lease JSON denies below via no-lease */
        try { console.log("gate: corrupt lease JSON"); } catch (e2) {}
      }
    }
    var bootId = null;
    try { bootId = $persistentStore.read(BOOT_KEY); } catch (e) { bootId = null; }
    var lastSeen = null;
    try {
      var lastRaw = $persistentStore.read(LASTSEEN_KEY);
      if (lastRaw) {
        var parsed = parseInt(lastRaw, 10);
        if (!isNaN(parsed)) { lastSeen = parsed; }
      }
    } catch (e) { lastSeen = null; }

    var selected = null;
    try {
      var details = $surge.selectGroupDetails();
      if (details && details.decisions) {
        selected = details.decisions[GATE_GROUP] || null;
      }
    } catch (e) {
      selected = null; /* unknown selection denies */
    }

    var ctx = {
      now: $script.startTime,
      netFp: networkFingerprint($network),
      selected: selected,
      bootId: bootId,
      lastSeen: lastSeen
    };
    var verdict = decide(lease, ctx);

    if (verdict.matched) {
      /* Best-effort monotonic guard for the next run. A failed write
       * must not change this run's verdict (the lease itself is valid);
       * the clock-back-vs-lastseen check simply has less history then. */
      try { $persistentStore.write(String(ctx.now), LASTSEEN_KEY); } catch (e) {}
    } else {
      try { console.log("gate: deny " + verdict.reason); } catch (e) {}
    }
    $done({ matched: verdict.matched });
  } catch (e) {
    /* Any unexpected failure denies. Per the manual an uncaught
     * exception would abort the session with no effect; answering
     * matched:false explicitly is the deterministic fail-closed path. */
    try { $done({ matched: false }); } catch (e2) {}
  }
})();
