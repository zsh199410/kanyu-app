# C3-C0 v2.0 → v2.1 diff — Surge bridge.js (PR #99 absorption + legacy-write check)

Date: 2026-11-19. Round 2 of C3-C0 (GPT receipt 7010810585, PR #97 review).

- v2.0: bridge_fixed_v2.js as submitted to Draft PR #97 (branch
  c3c0-sanitized-v2-review, head a4df7b4), 506 lines, SHA-256
  b3c0b34045d8b4ce (full SHA in C3C0_ROUND2_REPORT.md).
- v2.1: the same file with the PR #99 fix absorbed and the legacy
  last_id write path checked, 530 lines, SHA-256 1658cea7ce6566e3
  (full SHA in C3C0_ROUND2_REPORT.md).

## What changed (3 items)

1. saveLedger() — PR #99 fix, absorbed verbatim. $persistentStore.write
   returns true only on a successful write. A false return is NOT an
   exception, but it must now throw durable_checkpoint_failed, blocking
   every dispatch and /result that relies on the checkpoint. Without this,
   an action could run while in_progress was never persisted, or a
   receipt could be POSTed while result_ready was never persisted.
   Cross-review: the fix is correct and complete for saveLedger — it is
   the only ledger-persisting call, and every caller already catches its
   throw and fails closed (claim → ledger_write, checkpoint →
   checkpoint_failed, bootstrap → ledger_bootstrap_failed, ack-clear →
   ledger_write). Verified by test_store_failure.js (5/5) run against
   the actual v2.1 script, and by a control run that FAILS on the unfixed
   v2.0 (dispatches=1 where 0 is required).
2. Legacy last_id write — checked, no throw guard needed, false return
   now recorded. Two sites (resendCached() and the ACK path) wrote the
   legacy sgbridge_last_id checkpoint. Neither needs the saveLedger
   throw pattern, because the ledger (floor / last_acked_id) is the
   authoritative dedup state, persisted via the now-guarded saveLedger,
   and dedup takes max(floor, acked, legacy) — so a stale legacy value
   cannot cause a re-dispatch of an ACKed command. In resendCached() the
   legacy write is reached only AFTER saveLedger persisted the cleared
   pending + updated last_acked_id. In the ACK path the saveLedger that
   follows persists last_acked_id; if it throws, the result stays cached
   and is re-sent next run, never re-executed. Both sites now call the new
   writeLegacyLastId() helper, which records a false return as a
   store_write phase (same as a thrown write) without changing control
   flow — so a failed legacy write is no longer silently swallowed.
3. No other script change. Wire format, fence, ordering, ACK, phase
   trace, and $done behaviour are unchanged. The v2 regression suite
   still passes 28/0/1 against v2.1.

## Unified diff (desensitised)

```
--- bridge_fixed_v2.js (v2.0, PR #97 head a4df7b4)
+++ bridge_fixed_v2.js (v2.1, C3-C0 Round 2)
@@ -262,7 +262,31 @@
 }
 function saveLedger(state) {
   if (!saneState(state)) throw new Error("durable_checkpoint_failed");
-  $persistentStore.write(JSON.stringify(state), LEDGER_KEY);
+  // PR #99 (GPT): Surge $persistentStore.write returns true only on a
+  // successful write. Returning false is NOT an exception, but it must
+  // block every dispatch and /result that relies on this durable
+  // checkpoint — otherwise an action could run while in_progress was
+  // never persisted, or a receipt could be POSTed while result_ready
+  // was never persisted. Absorbed verbatim from PR #99.
+  const saved = $persistentStore.write(JSON.stringify(state), LEDGER_KEY);
+  if (saved !== true) throw new Error("durable_checkpoint_failed");
+}
+
+// Legacy last_id checkpoint write (secondary to the ledger).
+// v2.1 note: unlike saveLedger, this does NOT throw on a false return.
+// The ledger (floor / last_acked_id) is the authoritative dedup state
+// and is persisted via saveLedger, which now throws on false (PR #99);
+// dedup takes max(floor, acked, legacy), so a stale legacy value cannot
+// cause a re-dispatch of an ACKed command. In resendCached() the legacy
+// write is reached only AFTER saveLedger persisted the cleared pending +
+// updated last_acked_id; in the ACK path the saveLedger that follows
+// persists last_acked_id, and if it throws the result stays cached and
+// is re-sent next run, never re-executed. A false return is recorded as
+// a phase (same as a thrown write) so it is not silently swallowed.
+function writeLegacyLastId(id) {
+  let saved = false;
+  try { saved = $persistentStore.write(String(id), STORE); } catch (_e) { phaseErr("store_write", id, "store"); return; }
+  if (saved !== true) phaseErr("store_write", id, "store");
+}
 
 // POST /result and check the STRICT ACK (PR#96): 200 + accepted:true +
@@ -290,7 +314,7 @@
     if (na !== null) ledger.last_acked_id = na;
     ledger.pending = null;
     try { saveLedger(ledger); } catch (_e) { phaseErr("ledger_write", pend.id, "store"); }
-    try { $persistentStore.write(String(pend.id), STORE); } catch (_e) { phaseErr("store_write", pend.id, "store"); }
+    writeLegacyLastId(pend.id);
     phase("result_acked", pend.id, "resend");
     return true;
   }
@@ -483,7 +507,7 @@
     phase("result_delivery", cmd.id, "none");
     const res = await sendResult(result);
     if (res.acked) {
-      try { $persistentStore.write(String(cmd.id), STORE); } catch (_e) { phaseErr("store_write", cmd.id, "store"); }
+      writeLegacyLastId(cmd.id);
       const na = newerRawId(ledger.last_acked_id, cmd.id);
       if (na !== null) ledger.last_acked_id = na;
       ledger.pending = null;
```

## Verification

- test_store_failure.js (PR #99, fetched from branch
  gpt6-issue73-fix-durable-store-false-20261119): 5/5 PASS against v2.1;
  1/5 FAIL (control) against the unfixed v2.0.
- test_fixed_v2.js: 28 PASS / 0 FAIL / 1 LIMITATION against v2.1
  (unchanged from v2.0).
- Simulator fix required by the PR #99 absorption: the mock
  $persistentStore.write now returns true on success (matching real
  Surge semantics) and gains a ledgerWriteFalseAfter fault-injection
  mode mirroring ledgerWriteFailAfter. Without the return true, every
  saveLedger call would throw in the simulator and the whole v2 suite
  would fail — the mock previously returned undefined.
