# Issue #73: authenticated external recovery checkpoint — reference gate

**Status: ISOLATED STAGING REFERENCE ONLY.** This does not create a
production external high-water mark, sign real anchors, or authorize
recovery of the live Bridge, token registry, or nonce ledger.

## Problem

Restoring an old SQLite backup can reactivate revoked tokens and
resurrect previously consumed challenges. Testing that a SQLite
transaction is serializable or `synchronous=FULL` is not sufficient
to prevent this time-travel rollback.

## Implemented evidence component

`recovery_signed_checkpoint.py` verifies a deterministic SHA-256 digest
of a single SQLite read transaction covering:

- ALL server-owned token registry rows, including status, role,
  expiry, revoke timestamps, token ID and SHA-256 fingerprint;
- ALL challenge ledger rows, including hashed nonce, signed candidate
  fingerprint binding, state and consumed timestamp.

It requires a signed Ed25519 checkpoint for that digest **and an
exact expected epoch obtained from a separate authenticated monotonic
control plane**. The pinned Ed25519 verifying key must come from
independent trusted configuration, never from the recovered database,
the checkpoint itself or an untrusted HTTP field.

The checker rejects malformed anchors, missing key/epoch, signature
tampering, an old signed checkpoint with a newer external epoch,
changed DB contents, missing tables, and old DB snapshots. There is
no automatic re-anchoring on failure. Errors are generic; no secret
credential is emitted.

The `test_recovery_signed_checkpoint.py` test fixture generates an
ephemeral Ed25519 signing key and a synthetic trusted epoch in memory.
It demonstrates matching verification, then a real SQLite backup
restore over a revoked/consumed state: an old signed checkpoint is
rejected by the newer epoch and a newer signed checkpoint is rejected
by the restored database digest. **This only proves detection with
independent expected state supplied; no such production control
plane has been provisioned.**

## Non-negotiable integration rules

- The live service must be offline/ingress frozen during restoration.
  It may not accept new proof issuance or token authentication until
  its recovered DB+WAL snapshot matches the authoritative signed
  checkpoint AND the external monotonic high-water epoch.
- A trusted external issuer must commit an epoch/anchor for every
  security-relevant token or nonce mutation, with durable failure
  handling. If the DB transaction succeeds but the external anchor
  commit becomes unknown, keep issuance frozen and reconcile: no
  automatic overwrite, rewind, or self-signing of the restored state.
- The external monotonic epoch and verifying trust root cannot be
  restored from the same VPS/NAS backup or obtained from the
  restored database; the sample does not provide external service
  availability, key custody, epoch issuance or anti-replay itself.
- Signed checkpoint integrity **alone** does not stop replay of
  an old signed checkpoint if the independent epoch is also rolled
  back. That is why the independently authoritative epoch is required.
- This checker only verifies an already-anchored consistent state at
  startup/recovery. It is not a replacement for device nonce consume,
  in-flight signature drain, live ingress fencing, or safely revoking
  an already issued credential.
- Real staging requires proof of separate failure domain, exclusive
  signing/epoch authority, complete deployment graph, recovery
  journal and rollback evidence. A file stored next to `state.json`
  or `token_registry.sqlite` is not an external anchor.

No live host/route/token/key/iPhone state is modified. Status remains
`C3-C1=NO-GO`, `PR93_CUTOVER=BLOCKED`, `AUTO_DELETE=OFF`,
21 pinned nodes and five timers protected; legacy pending
`1795063030` remains `OUTCOME_UNKNOWN` and is not replayed.
