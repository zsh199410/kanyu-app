# Issue #73 — C3-C1 server-side durable nonce/replay gate

**Status:** isolated Python 3 + SQLite reference, **not deployed**, not a
real credential-proof endpoint, not a Surge script. Branch is stacked on GPT
Draft PR #105. It does not change the public/prod bridge or the pending
mailbox, and does not activate or revoke any credential.

## Threat and purpose

PR #105 introduced a browser/WebView-compatible Ed25519 proof verifier.
That function checks equality with a caller-supplied expected nonce,
but **can verify the same signed proof more than once** if a caller
reuses its expected nonce. Merely checking a signed nonce is NOT
durable replay prevention.

This PR adds `nonce_ledger_sqlite.py`: a *server-side* durable
challenge registry with an atomic one-time consume operation. The
signed-proof **issuer** must check and persist the consumption
before signing any new proof. It must not sign after a database
exception or ambiguous commit, and must not automatically repeat
a consumed challenge. It is intentionally a reference rather than
an HTTP service; connection to real private server logic must be
separately audited.

## Allowed state transitions

| Existing | Operation | Result |
|---|---|---|
| no row | authenticated register | issued (one-time) |
| issued | duplicate register | reject, no change |
| issued | consume exact nonce+kind+candidate SHA-256+token ID within lifetime | consumed (one-time) |
| issued | consume mismatched / not-yet-issued / expired | reject, no change |
| consumed | any register or consume | reject, never resurrect |
| full/corrupt/unavailable DB | register/consume | fail closed, no proof issuance |
| storage error / failed commit | register/consume | **commit_state_unknown**: stop and reconcile, do not retry automatically |

New challenges must use a 32-byte CSPRNG random nonce encoded as
43-char unpadded canonical base64url. The database stores **only the
SHA-256 digest of nonce bytes**, candidate fingerprint, token ID,
kind, bounded issued/expiry times, and immutable consumed tombstone.
No production DEV/local key values are stored or printed.

SQLite is configured with `BEGIN IMMEDIATE`, WAL, `synchronous=FULL`,
`busy_timeout` and a non-world-accessible parent directory. This
supports **single-host** process/thread serialization and durable
commits subject to filesystem/device guarantees; it is not a
multi-host, replicated or consensus store. A permanent finite
`max_records` bound stops issuance rather than deleting used records.

## Tests

`test_nonce_ledger_sqlite.py` runs actual SQLite file-backed
transactions with 21 independent `unittest` cases, including:
- first registration and one consume; duplicate/replay denial
- mismatched candidate, token ID, credential kind, invalid nonce
- expiration and issuance boundaries
- new SQLite connection and **new OS process** restart proof
- simultaneous consumers and simultaneous registrations, one winner
- injected SQL trigger failure, unknown commit state/fail-closed
- corrupted DB, unsupported schema version, full ledger
- owner-only path / no symlink and nonce-value exclusion from DB

The GitHub CI runs these tests in fresh temporary directories with
Python's standard library, no network/production env/secrets.

## Critical limitations — not cleared by a green CI

1. **Device side remains unimplemented.** This server ledger rejects
   repeated issuance/consumption but cannot prevent a previously signed
   proof from being replayed by a device that reuses its local expected
   nonce. A **device-side durable single-use challenge state machine**
   must be independently designed/verified; Surge
   `$persistentStore` has no established atomic compare-and-swap
   primitive, so do not claim strict concurrency-safe consume there.
2. Registration/consumption methods are only callable by a **trusted,
   authenticated, authorized server handler**. The caller must use
   server-owned wall-clock values, validate the high-entropy candidate,
   pin the expected client/session identity and verify it has not
   been revoked, and require signed issuance; this sample does not
   implement those integrations or cryptographic key management.
3. SQLite DB rollback/restore to a prior snapshot can resurrect
   consumed nonces. Production needs a rollback-resistant epoch/audit
   anchor and a plan preventing any older DB snapshot from being
   reused to issue a proof. Do not restore a nonce DB with ordinary
   code/config rollback.
4. SQLite WAL/SHM plus database must remain on one local durable
   filesystem; backups and crash recovery need a tested consistent
   snapshot process and integrity/fault tests. Cloning it to multiple
   servers is not a distributed one-time consume guarantee.
5. A consumption committed before proof issuance can leave a challenge
   permanently consumed if the signer crashes. That is intentional
   fail-closed behavior: the owner must use a **fresh** challenge under
   separately authorized recovery, not replay the old one. The
   `commit_state_unknown` exception cannot be interpreted as
   proof absent or as confirmed failure.
6. The actual source-free iPhone crypto probe from PR #104 still
   needs measured Surge WebView/Ed25519 compatibility; no PR here
   establishes true-device cryptographic readiness.
7. Production release still requires an independently trusted pinned
   key, real signed `/credential-proof`, durable token table,
   promotion/rollback review, two cron observations and explicit
   staged release approval. The old exposed DEV token must not be
   revived as a normal rollback credential.

**Invariants:** old pending cmd stays `OUTCOME_UNKNOWN` and fenced;
21 pinned nodes/five existing timers untouched;
`BOOTSTRAP_SECURITY_GATE=BLOCKED`, `C3-C1=NO-GO`,
`PR93=BLOCKED`, `AUTO_DELETE=OFF`.

Related: PR #103 signed reference, PR #104 no-secret WebView capability
probe, PR #105 WebCrypto verification library.
