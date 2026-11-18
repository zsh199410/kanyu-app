/* Drop-in replacement for bridge.js httpAPI() and api().
 * Keep the existing http() implementation and existing private APIKEY.
 * A completed non-idempotent API request must never be issued again solely
 * because the initial transport timed out. "Unknown" means it may have run.
 * This file contains no host, secret, or private script-path value.
 */
function httpAPI(method, path, body) {
  return new Promise((resolve) => {
    if (typeof $httpAPI !== "function") {
      resolve({ kind: "unavailable" });
      return;
    }
    let done = false;
    let timeoutId;
    const finish = (result) => {
      if (done) return;
      done = true;
      if (timeoutId !== undefined) clearTimeout(timeoutId);
      resolve(result);
    };
    timeoutId = setTimeout(() => finish({ kind: "unknown", reason: "timeout" }), 10000);
    try {
      $httpAPI(method, path.replace(/^\//, ""), body || {}, (data) => {
        if (data === undefined || data === null) {
          finish({ kind: "unknown", reason: "empty_callback" });
        } else {
          finish({ kind: "ok", data: data });
        }
      });
    } catch (_e) {
      // A throw does NOT prove the action was never dispatched.
      finish({ kind: "unknown", reason: "dispatch_error" });
    }
  });
}

async function api(method, path, body) {
  const verb = String(method).toUpperCase();
  const viaApi = await httpAPI(verb, path, body);
  if (viaApi.kind === "ok") {
    return { via: "httpAPI", data: viaApi.data };
  }
  // A timed-out or ambiguous mutating call may already have been accepted.
  // Never blindly fall back to a second HTTP mutation.
  if (viaApi.kind === "unknown" && !["GET", "HEAD", "OPTIONS"].includes(verb)) {
    return {
      via: "httpAPI", status: 0, err: "outcome_unknown_no_retry",
      pending: true, data: { state: "unknown", reason: viaApi.reason }
    };
  }
  // Original bridge http() only distinguishes GET from POST; every other
  // verb would silently become a POST. Never mutate with the wrong verb.
  if (!["GET", "POST"].includes(verb)) {
    return {
      via: "httpAPI", status: 0, err: "unsupported_http_fallback",
      pending: viaApi.kind === "unknown",
      data: { state: "blocked", reason: "fallback_method_unsupported" }
    };
  }
  // If $httpAPI was truly unavailable, direct HTTP is the one and only
  // attempt. For a read-only GET, retry after ambiguous transport is safe.
  const r = await http(verb, "http://127.0.0.1:6171" + path,
    { "X-Key": APIKEY, "Content-Type": "application/json" }, body);
  let data = r.data;
  try { data = JSON.parse(r.data); } catch (_e) {}
  return { via: "http", status: r.status, err: r.err, data: data };
}
