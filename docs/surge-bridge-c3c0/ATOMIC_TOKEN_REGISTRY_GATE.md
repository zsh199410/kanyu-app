# Issue #73 — Atomic token registry + one-time nonce proof issuance

**Review-only, single-host SQLite demonstration. Not a deployed server or API.**
No production token, private signing key, deployment instruction, real
host name or phone credential is present. **Do not merge into live Bridge
or enable token rotation solely because these tests pass.**

## Why this exists

PR #108's reference issuer looks up token status and consumes its
nonce in separate operations. If the token is revoked in between,
the signer might still issue a proof from stale authorization.

This change adds `token_registry_sqlite.py` and
`atomic_signed_proof_issuer.py`. Both the token status table and the
immutable used-nonce ledger are in **one SQLite database**.

The secure issuance gate is:

1. A separately authenticated and authorized session is checked by
   a **server-owned** callback. The actual HTTP/session/mTLS code is
   NOT included in this PR.
2. Under one `BEGIN IMMEDIATE` transaction, select the exact server
   registry row for token ID, credential kind and high-entropy token
   SHA-256. Only an unexpired **active** new/backup token is eligible;
   an old exposed token, revoked token or standby backup is rejected.
3. In that SAME transaction, consume exactly one unexpired challenge
   bound to nonce, token ID, fingerprint and kind.
4. Only after a successful COMMIT may the private-key signer generate
   an Ed25519 canonical JSON proof compatible with the PR #105
   WebCrypto verifier. On any unknown commit or signing failure,
   **do not issue a proof or retry that nonce**.
5. Registration, revocation and backup activation also use
   `BEGIN IMMEDIATE`, enforcing a serialized order with proof
   consumption on the single host. Revocation is an irreversible
   row status change with timestamp, never deletion.

The DB stores **fingerprints**, not token values; a source-free
server caller supplies the actual high-entropy token only at admin
registration or incoming authentication. Admin operations are
INTERNAL APIs, not exposed as HTTP routes. Synthetic tokens only.

## Token state

| Role | Initial status | Authentication | Proof |
|---|---|---|---|
| exposed_old | active, bounded ≤48h | until explicit revoke or expiry | NEVER |
| new | active, bounded ≤30d in this example | until revoke or expiry | if atomic nonce consumed |
| backup | standby | NO until separately activated | NO until separately activated |
| backup after activation | active | YES | if atomic nonce consumed |

The emergency backup transition revokes the currently active new
token and activates standby backup **in one transaction**.
The previously exposed old token is NEVER reactivated as a fallback.
An explicit revoke requires another eligible non-old active token
for the same credential kind; an expired old token remains denied
even if no administrative revoke has occurred.

## Tests and evidence

`test_atomic_token_registry.py` executes **21 real SQLite** tests:
old/new simultaneous acceptance, bounded expiry, irrevocable status,
replacement requirement, standby denial, backup activation,
duplicate fingerprint and ID constraints, absence of token plaintext
in DB, genuinely signed proof, replay rejection, unauthorized session,
wrong kind/nonce/fingerprint, race between issuers,
injected storage failure, signer crash, invalid expiry and restart.

`test_atomic_token_proof_fixture.py` uses a temporary Ed25519 key and
actual registry+nonce DB to produce a signed synthetic proof.
`test_atomic_token_registry_webview.js` verifies those exact signed
bytes with the WebCrypto-compatible PR #105 library and tests
wrong nonce, candidate, old ID, key and expiry.
All tests are isolated. The CI is read-only and uses a temporary DB.

## Production gates that are STILL OPEN

- This is **not** the real authenticated HTTPS `/credential-proof`
  endpoint. Production must independently authenticate the device,
  use a server-owned token registry and clock, and keep the
  Ed25519 private key out of this public repository.
- A registered old token is exposed: keep its parallel-acceptance
  window as short as approved; the code only enforces a maximum.
  No real token has been registered, switched or revoked.
- **Revocation linearization limitation:** a request whose nonce
  was durably consumed *before* revocation may complete signing
  after revocation. Production should quiesce/drain in-flight signers
  before declaring a strict no-more-signatures revocation barrier,
  or build a transactionally held signing lease. The test only
  proves the SQL transaction order.
- No distributed consensus: multiple host copies of the DB, or
  restoring an old DB snapshot, can reactivate revoked credentials
  and resurrect consumed nonces. Production needs a rollback-resistant
  audit/epoch outside the restored snapshot, and verified backup
  protocol preserving DB+WAL consistency. This reference is not
  authorization for shared NAS/network filesystem deployment.
- PR #104/#107 iPhone `engine=webview` Ed25519/atob probe remains
  unverified on the real device. Client-side durable single-use
  nonce/promotion status also remains unproven, including behavior
  on backup restore and concurrent script execution.
- Old pending one-slot command stays permanently
  `OUTCOME_UNKNOWN` and fenced. Neither this registry nor any
  test reads or writes the actual mailbox/ledger/last_id.
- Strict cutover approval, backup credential, two real cron cycles,
  privacy review and **production rollback evidence** must all be
  completed before real promotion/revocation/deployment.

Release status: `C3-C1=NO-GO`, `PR93=BLOCKED`,
`BOOTSTRAP_SECURITY_GATE=BLOCKED`, `AUTO_DELETE=OFF`.
21 pinned nodes and five existing timers untouched.
