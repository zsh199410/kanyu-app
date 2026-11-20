# Issue #73 — F3 precise error classification + staging issuance drain gate

Status: **synthetic code-only staging**, NOT installed in the production Bridge or
iPhone. Neither successful local/Actions tests nor a soft-router fallback
provides safe credential promotion authority.

## F3: precise non-secret errors, no relaxation
- `SignedProofIssuer.issue` checks canonical nonce before calling the
  token-lookup callback. A malformed nonce now yields
  `ProofIssuanceError("invalid_challenge")`, with **zero** lookup/signing.
- `AtomicSignedProofIssuer.issue` checks nonce and token/credential binding
  before session authorization. Malformed values now yield
  `ProofIssuanceError("invalid_proof_input")`. No registry writes or signing.
- Truly unknown SQLite transaction or persistence exceptions still fail
  closed as `atomic_commit_unknown`, and unexpected authorization backend
  failures remain `preflight_unknown`. These are NOT silently retried.
- The HTTPS reference still maps failures to its existing generic HTTP
  rejection; it exposes no raw input or secret through error descriptions.
- The changes do not modify raw token storage, signer canonical field order,
  the nonce ledger SQL transaction, credential roles, or current phone scripts.

## Single-process staging drain

`staging_issuance_drain.py` is an explicitly limited **same-process**
admission/drain reference. A real staging HTTP handler must call
`gate.issue(atomic_issuer,...)` for EVERY issue path and use
`gate.guarded_admin_change(action,confirm,...)` for EVERY token
activation/revocation, with the same instance.

Sequence:

1. Freeze new admissions **before** waiting for current issuers.
2. Drain all in-process active issuances within a bounded timeout.
3. Only after zero in-flight calls, perform one server-authorized
   registry admin transition.
4. Require authoritative post-change read-back of token statuses.
5. Reopen only after a successful mutation AND successful read-back.
6. Timeout, ambiguous mutation or failed read-back leaves the gate
   frozen until separate trusted operator reconciliation.

This means a local signer cannot *begin* signing after the drained
revocation boundary if it uses the gate. It **does not** prove that
a proof already signed can never arrive over the network after
revocation, nor that requests in another process/worker or VPS are drained.

## Explicit blockers

- Single-process gate is bypassable if any handler calls the underlying
  issuer directly. Real server integration must prove every route is wrapped.
- A process crash/restart resets this in-memory gate. Production requires
  durable revoked/frozen state, a service ingress fence and revalidation
  against an external epoch/high-water anchor BEFORE accepting traffic.
- Multiple workers/hosts have no shared admission barrier: this reference
  is **not approved** for them. An independent distributed admission
  barrier or single hardened worker and verified process isolation are needed.
- A SQLite snapshot restored from before a nonce consumption/revocation
  can resurrect both. This code provides no rollback-resistant fence.
- Strict revocation must also invalidate already-issued unredeemed
  credentials and drain HTTPS network request handlers at the actual
  production ingress. Client must separately enforce one-use challenge.
- No rotation, live private signing key, real phone credential, token,
  mailbox, proxy group, timer or `/credential-proof` production route is
  modified. Existing code remains `C3-C1=NO-GO`.

## Automated evidence required
- `test_f3_proof_error_classification.py`: 12 real temp SQLite cases.
- `test_staging_issuance_drain.py`: 14 real SQLite, thread and timeout
  cases, including mutation while an issuance lease is held and
  timeout/ambiguous failure keeping admission frozen.
- Existing 21 token-registry and 22 HTTPS tests still must pass.
- `TEST-ACTUAL-IP` or private names/addresses should never be posted in a
  public Issue comment.

Before any live deployment Muse must provide HTTPS staging certificate,
authorized pairing path, single-writer/worker topology, exact code SHA,
dual-token and standby tests, audit/epoch, simulated crash recovery,
drain/read-back status and rollback with no old-token revival.
`PR93_CUTOVER=BLOCKED`, `AUTO_DELETE=OFF`, 21 pins/5 timers preserved,
and unknown old command `1795063030` must never be replayed or cleared.
