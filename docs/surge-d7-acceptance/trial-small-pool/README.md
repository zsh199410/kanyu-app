# #73 trial pool small-batch diagnostic reference

**Offline reference only; no production deployment, no authorization mechanism.**
PR #122 HEAD ef4e255c... contains the *formal* phone probe and receiver.
Both enforce a 22-member minimum. That guard must remain untouched.
The live trial-specific script/receiver were not available for source-level review.
This independent module is NOT a drop-in patch for either live script.

## Contract
- Call planTrialBatch only with stable, distinct 64-hex identity fingerprints from the already verified, current *trial* manifest (max 6).
- Empty trial: no submission. One or two members: plan available nodes, diagnostic-only. Three to six: rotate up to four and delegate to existing receiver rules.
- A 1-2 member result without independent evidence never permits pruning or promotion. Preserve raw failure as diagnostic unknown. Even observed reachable remains diagnostic-only.
- Actual receiver adapter must continue validating authenticated bearer, nonce, manifest SHA/generation, exact identity and external policy-ID against current source bytes. Never trust a caller-supplied boolean in place of validation.
- This does not waive source diversity, freshness, native latency, same-batch controls, writer locks, pin protection, or the existing promotion policy.
- No network or filesystem operations, no publisher calls, no DIRECT fallback.
- Existing 22-member production guard is not changed. No trial/production deployment until actual trial source is available and prior release/authorization gates pass.

## Tests
node test_small_trial.js
node test_trial_adapter.js

14 deterministic cases use only synthetic identity fingerprints. The same functions and cases were executed in the isolated JavaScript authoring runtime, 14/14 passed. **Re-verified with real Node v24.22.1 in VPS isolation: 14/14 passed.**

## v2: adapter integration (trial_adapter.js, ADAPTER.md)
- `adaptTrialBatch(snapshot, cursor)` connects this reference to the real trial receiver contract: it takes an already-authenticated verified snapshot (manifest SHA, generation, nodes, observations) and returns the batch plan + diagnostic-only classifications. It never permits promotion or pruning.
- 12 adapter tests (test_trial_adapter.js) cover: 1-node diagnostic-only, 2-node missing observation, 3-node delegation, empty trial, rejection of unknown-identity observations / bad manifest SHA / negative generation / duplicate node id / 7 nodes / invalid raw status, cursor rotation, and success never permitting promotion. **12/12 passed with real Node v24.22.1 in VPS isolation.**
- The adapter is a pure-function reference. Full integration verification (manifest/replay checks, dual-target controls, device end-to-end) still requires the exact live trial source; no claim of integrated repair.

## v3: GPT review fixes (Review 6031702642, 2026-11-24 08:23)
- GPT fixed two issues directly in trial_adapter.js (commit cca6808, +13/−3): reject duplicate observation IDs, observations outside the selected rotating batch, and duplicate/blank policy names (invalid_trial_snapshot). The old Map logic let a later item with the same ID overwrite the earlier one and silently dropped out-of-batch results.
- GPT added 3 negative tests (commit daa372e, +20): duplicate observations with conflicting or identical statuses, an observation outside the selected rotating batch, and ambiguous policy names (two IDs sharing one name, blank name).
- **Re-verified at HEAD daa372e686fe with real Node v24.22.1 in VPS isolation: small trial 14/14 + adapter 15/15 = 29/29 PASS.** The old 26/26 does not carry over to the new HEAD.
- The component stays a no-I/O reference. It does not prove auth, nonce/replay, manifest SHA/generation, native policy-ID, or dual-target control integration. valid:true is not authorization; the formal 22-node pool gate is unchanged.
