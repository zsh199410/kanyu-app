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

14 deterministic cases use only synthetic identity fingerprints. The same functions and cases were executed in the isolated JavaScript authoring runtime, 14/14 passed. Node runtime test in the actual trial environment is still pending. Actual adapter, manifest/replay checks, dual-target controls and device end-to-end tests require the exact live trial source; no claim of integrated repair.
