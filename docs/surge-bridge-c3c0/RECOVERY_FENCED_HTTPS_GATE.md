# Issue #73 — Entire-HTTPS admission + frozen startup recovery (P0 staging)

**This is a staging-only adapter. No live host, Surge device, token,
private key, DNS name, mailbox, proxy group or production service is changed.**

## Real integration gap and repair
Existing `staging_issuance_drain.py` protects `issuer.issue()`, but the
`HTTPSProofService.handle()` path *registers its nonce before calling
the issuer*. Protecting only the signer permits a request to register
a new challenge while revocation is frozen. The separate
`StagingRecoveryFencedHTTPSService` subclass closes this gap:
- One `gate.admission()` wraps the **entire** HTTPS request handler,
  including pairing authentication, canonical nonce registration and
  `AtomicSignedProofIssuer.issue()` in the same process.
- Listener creation defaults to **frozen** (`start_frozen=True`).
  There is no implicit resumption after process restart.
- An operator-supplied signed recovery checkpoint, **independently pinned
  Ed25519 key**, and **independently fetched monotonic epoch** are
  checked against actual token/nonce SQLite contents before reopening.
- A potentially mutating HTTP response (200/403/409/503) immediately
  freezes further requests. **The actual signed HTTP 200 proof is withheld
  until an independently committed signed checkpoint with a strictly
  higher external epoch matches the complete current SQLite state.**
  A failed, missing, stale or ambiguous external write instead returns
  503 and leaves the nonce burned and the gate frozen.
- For denied/unknown requests, no signed proof is released; frozen
  admission requires explicit trusted recovery. A previously pinned
  signing root cannot be swapped during reconciliation.
- Signed-proof failure and stale DB snapshot / stale signed checkpoint
  do not auto-reset the gate or retry a nonce. Admin revoke/activation
  must freeze/drain, verify readback AND verify a fresh external anchor
  before reopening.

## Verification scope
The dedicated isolated CI runs **real HTTPS sockets** with test-only
TLS certificate, independently signed synthetic Ed25519 checkpoints,
synthetic tokens/nonce, and temp SQLite. It exercises:
1. Started-but-frozen listener refuses HTTP with no ledger writes.
2. Wrong pinned recovery key blocks startup.
3. Valid signed recovery permits one TLS proof, then freezes.
4. Recovered fresh signed checkpoint permits a subsequent proof.
5. Unauthenticated calls do not mutate state.
6. Exposed old token rejected; consumed test challenge frozen.
7. Old database snapshot restored after consumption fails recovery.
8. Old signed checkpoint fails against newer external epoch.
9. Concurrent HTTPS signing and admin revoke cannot overlap
   admission; newly arriving requests are refused before nonce writes.
10. Admin external checkpoint verification failure leaves frozen.
11. Real signer failure burns nonce and requires reconciliation.
12. New instance after restart begins frozen again.
13. External commit failure **withholds HTTP 200** and freezes.
14. Reused/non-increasing external epoch withholds HTTP 200.
15. Replacement pinned root cannot silently re-open the gate.
16. Tampered signed anchor blocks resume; correct signed fresh
    anchor allows an explicit operator resume.

Original 14 drain and 17 recovery checkpoint tests also rerun.

## NO-GO boundary

**This adapter is NOT production deployable as supplied.**
- All external epochs, recovery signatures and key material in CI are
  ephemeral and simulated in memory. It does not implement a genuine
  independent rollback-resistant high-water service, signing-key custody,
  or authenticated out-of-band provisioning.
- There is no full DB mutation + external anchor transaction protocol.
  After a successful proof, this adapter deliberately freezes until
  a fresh external anchored state is presented. Consequently it is a
  deliberately slow *demonstration of fail-closed control*, not an
  always-on production endpoint.
- Only one Python process and its shared gate instance are covered.
  A second worker, independent admin connection, external rotation,
  process crash, outstanding network delivery or a second host bypasses
  this in-memory fence. **Every route must be audited**, and a durable
  startup freeze is needed before any live deployment.
- Production TLS/domain/independent pinned key distribution, real device
  Pure-JS verification + device-side durable nonce, authorized pairing,
  true external epoch, two protected cron cycles and rollback verification
  have not been achieved by these tests.
- The detached pure JS verifier's stateless replay behavior remains a
  known limitation.

**Release remains blocked:** `C3-C1=NO-GO`,
`PR93_CUTOVER=BLOCKED`, `AUTO_DELETE=OFF`; 21 pinned nodes, 5 timers
and legacy command `1795063030` (`OUTCOME_UNKNOWN`) unchanged.

VPS validation owner: Muse. In isolated VPS staging, confirm process
topology, singleton admission object, read-only production integrity
checks, SIGTERM clean stop, forced restart initially frozen, and
independent anchor failure-domain. Do not reuse the live production
credentials, public HTTPS port, or active server.

## Signed success must not escape before a durable external anchor

A 200 proof returned to a mobile device can authorize a token change.
Consequently merely freezing admissions **after** sending HTTP 200
would be insufficient: the VPS could fail before recording the consumed
nonce in an independent high-water system. The staged adapter now
performs an injected **trusted external signed-epoch commit** after the
local SQLite transaction and **before exposing HTTP 200**. The adapter
verifies the independently signed state itself; a boolean returned
by the server callback alone cannot bypass cryptographic verification.
An unknown remote commit always withholds the proof and requires operator
reconciliation (no automatic nonce replay).

The integration test's external signer is deliberately ephemeral and
in-memory. It demonstrates this fail-closed behavior but NOT remote
durability, independent failure-domain storage, high availability,
root distribution, or atomic communication with a real control plane.
