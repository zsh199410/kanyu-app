# Issue #73 — monotonic external-witness protocol reference (NOT LIVE)

## Purpose

Muse's real US VPS isolated staging proved a serious rollback weakness:
after a valid 200 signature and repeat 409, restoring a pre-consumption
SQLite backup lets the *same nonce* obtain another 200 signature.
That is a confirmed production NO-GO blocker.

The existing PR114 `recovery_signed_checkpoint.py` can detect a
restored/old state **only if** an independently authoritative epoch and
signed checkpoint are provided. This PR adds a concrete *reference*
write/compare protocol for that external witness, with staged signer
ordering and testable deny paths.

## What is actually implemented

- `IndependentWitnessTestDouble` stores a monotonic epoch, latest
  logical token+nonce state digest, independently retained consumed nonce
  SHA256 tombstones, and revoked token ID tombstones. Uses SQLite
  `BEGIN IMMEDIATE`, WAL, FULL sync and a compare-and-swap expected
  state digest. The `bootstrap` step is explicit and one-time.
- `WitnessedAtomicService` uses PR109 `AtomicSignedProofIssuer`, PR113
  in-process `IssuanceDrainGate`, and PR114 `logical_state_sha256`.
  Registration changes are sealed by the witness. The nonce and token
  are atomically consumed in the business database; **the independent
  witness must commit its nonce tombstone and updated state digest
  before the Ed25519 private signer is invoked**.
- Admin role transitions are required to freeze, drain all active
  issuances, execute the trusted SQLite change, commit the witness
  state/tombstone and independently read back before unfreezing. Failure
  or unknown status freezes admission.
- At every registration/issue boundary, the current actual business
  database digest must exactly equal the witness's last committed digest,
  else reject before any signer/nonce write. Restoring only the old
  business SQLite DB therefore blocks both the old nonce and any new
  nonce.
- Synthetic tests use real disk SQLite backup/restore and real Ed25519
  signatures; a witness timeout after local consume produces no
  signature, leaves digest disagreement and prevents further signing.

## Known limitations — READ BEFORE DEPLOYMENT

**This is NOT an independent external high-water service.** The code uses
two SQLite databases in two temporary directories on the *same CI host*,
only to model a separately durable service. In real production the
witness must be a separately authenticated, monotonic, rollback-
resistant authority **outside the VPS/NAS failure and restore domain**,
with its own signing root/cert pinning, access controls, backup policy
and evidence that it cannot be rewound alongside the business database.

An explicit negative test restores BOTH database files from matching
old snapshots and shows the identical nonce can be signed again.
This is an **expected known security limitation**, not a positive replay
protection result. Simply moving the witness SQLite file to a different
directory on the same VPS is insufficient.

The reference is not an HTTP handler. The existing PR110
`HTTPSProofService.handle()` still uses its original unwrapped ledger
and issuer. It MUST NOT be deployed with this class merely imported:
every nonce registration, signer, admin/revoke, restart/restore ingress
and every worker/process MUST be routed through the corresponding
witness+gate operations. The wrapper is **single-process**; other
workers bypass its mutex and drain barrier, so production requires a
hardened single-writer process topology or fully tested distributed
fencing/transaction protocol.

The current service has no authenticated witness network protocol,
independently pinned key or remote witness receipts, remote failure
injection, signed recovery-root provisioning, genuine mobile
one-use nonce state or TLS/production domain. Witness readback of one
state SHA does not in itself authenticate a remote service. No external
secret or production token is read or published.

The cross-store business SQLite COMMIT and witness COMMIT cannot be
atomic in this reference. Failures between them are intentionally
fail-closed and require trusted operator reconciliation. Never
automatically re-bootstrap or overwrite an anchor to match a
previously restored state. Any network timeout/unknown witness COMMIT
must block signature issuance; no retry on the same nonce.

Revocation may not cancel **already delivered** signed proofs or
device-side stale nonce acceptance. Existing proof verification
requires separate client durable single-use/revocation checks. The
reference test deliberately verifies an old signature remains
cryptographically valid after server-side revocation.

## Required Round 10–11 real staging evidence

1. Muse absorbs only reviewed file blobs; preserve his PR97 base changes.
2. Create an authenticated monotonic witness in a **separate failure
   domain** and prove independent epoch survives a full business VPS
   database/container rollback. Without that, mark `EXTERNAL_EPOCH=BLOCKED`.
3. Test loopback HTTPS handlers all use witness registration and gated
   signers; revoke/backup admin is inaccessible via untrusted HTTP.
4. Inject witness downtime and *unknown commit* between business nonce
   consumption and signature, then restart the service: no proof
   emitted; restored old nonce denied or service kept frozen.
5. Test drained in-flight issuance, SIGTERM/SIGKILL, multiple worker
   processes, and daemon startup before HTTP listener.
6. Verify old signed proof client acceptance requires a separately
   persisted device one-time nonce gate. Pure-JS device probe still
   unverified on real iPhone.

Protected production state stays `C3-C1=NO-GO`,
`PR93_CUTOVER=BLOCKED`, `AUTO_DELETE=OFF`, 21 pinned proxy nodes,
five timers unchanged; old `1795063030` remains `OUTCOME_UNKNOWN`
and never replayed/cleared.
