# C3-C0 v2.1 -> v2.2 desensitised diff (PR #100 absorbed)

v2.1 SHA `1658cea7ce6566e3a6703f4e962ac9fb37fd0a2b78d96661575a86d23f4f9c9a` (530 lines)
v2.2 SHA `8691e962cba4ab40e961702b7d30090aaaedc29fdbe46b63a257878f9f90abfc` (571 lines)

Source: GPT Draft PR #100 (branch gpt6-issue73-s1-secret-free-adapter-20261119),
applied verbatim via git apply to the private v2.1 (zero conflicts, base SHAs
matched exactly). The hunk below is PR #100's bridge_fixed_v2.js change,
unmodified. Placeholders only; no real token, key, URL, or IP.


```diff
diff --git a/docs/surge-bridge-c3c0/bridge_fixed_v2.js b/docs/surge-bridge-c3c0/bridge_fixed_v2.js
index 8eb9b6d..b4f6313 100644
--- a/docs/surge-bridge-c3c0/bridge_fixed_v2.js
+++ b/docs/surge-bridge-c3c0/bridge_fixed_v2.js
@@ -63,8 +63,20 @@
 //  PR#85 outcome_unknown_no_retry is preserved: a timed-out/ambiguous
 //  MUTATING call is never blindly retried via a second HTTP mutation.
 const BASE = "https://<BRIDGE_BASE>";
-const DEV = "<DEV_TOKEN>";
-const APIKEY = "<API_KEY>";
+// S1 isolated integration: public script carries NO reusable credentials.
+let DEV = null;
+let APIKEY = null;
+const CRED_DEV_KEY = "sgbridge_cred_dev";
+const CRED_LOCAL_KEY = "sgbridge_cred_localkey";
+function readCredential(key) {
+  let value;
+  try { value = $persistentStore.read(key); }
+  catch (_e) { return null; }
+  if (typeof value !== "string" || !value ||
+      value.length > 512 || /[\r\n]/.test(value) ||
+      /^<.*>$/.test(value)) return null;
+  return value;
+}
 const STORE = "sgbridge_last_id";
 const LEDGER_KEY = "sgbridge_ledger_v1";
 const PHASE_KEY = "sgbridge_phase_v1";
@@ -217,6 +229,12 @@ async function api(method, path, body) {
       data: { state: "blocked", reason: "fallback_method_unsupported" }
     };
   }
+  // No public or hard-coded localhost key: fail closed on missing local key.
+  if (!APIKEY) {
+    phaseErr("local_key_missing", 0, "credential");
+    return { via: "http", status: 0, err: "local_key_missing", pending: true,
+             data: { state: "blocked", reason: "local_key_missing" } };
+  }
   // If $httpAPI was truly unavailable, direct HTTP is the one and only
   // attempt. For a read-only GET, retry after ambiguous transport is safe.
   const r = await withTimeout(
@@ -329,6 +347,16 @@ async function resendCached(ledger, pend) {
   }, WATCHDOG_MS);
   try {
     phase("cron_enter", 0, "none");
+    // S1: without a valid device token, do NOT poll, send results,
+    // execute actions, update command state, or fall back to an old token.
+    DEV = readCredential(CRED_DEV_KEY);
+    if (!DEV) {
+      phaseErr("credential_missing", 0, "credential");
+      doneOnce({});
+      return;
+    }
+    APIKEY = readCredential(CRED_LOCAL_KEY); // may be absent; native $httpAPI can still work.
+    phase("credential_present", 0, "none");
     // --- legacy last_id (validated; a non-safe-integer fails closed) ---
     // Mirrors the reference's LEGACY_CHECKPOINT_INVALID: the legacy
     // checkpoint must be a safe integer, or nothing executes.
@@ -345,6 +373,13 @@ async function resendCached(ledger, pend) {
     // --- poll (guarded) ---
     const r = await withTimeout(http("GET", BASE + "/poll", { "X-Dev-Token": DEV }), POLL_TIMEOUT_MS, "poll");
     phase("poll_http_done", 0, "none");
+    // A revoked token cannot silently fall back to legacy credentials.
+    // Retain the mailbox and ledger untouched on authentication rejection.
+    if (r && !r.__timeout && r.status === 403) {
+      phaseErr("auth_forbidden", 0, "credential");
+      doneOnce({});
+      return;
+    }
     let cmd = null;
     if (r && r.__timeout) {
       phaseErr("poll_timeout", 0, "timeout");
@@ -475,6 +510,12 @@ async function resendCached(ledger, pend) {
         if (a.type === "api") {
           outputs.push({ type: "api", path: a.path, result: await api(a.method || "GET", a.path, a.body) });
         } else if (a.type === "mcp") {
+          // MCP uses localhost HTTP. Missing key means no local request.
+          if (!APIKEY) {
+            phaseErr("local_key_missing", cmd.id, "credential");
+            outputs.push({ type: "mcp", error: "local_key_missing" });
+            continue;
+          }
           const payload = { jsonrpc: "2.0", id: 1, method: "tools/call",
             params: { name: a.tool, arguments: a.arguments || {} } };
           const rr = await withTimeout(
```
