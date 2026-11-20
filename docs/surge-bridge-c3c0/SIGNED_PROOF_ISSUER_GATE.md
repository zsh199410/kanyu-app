# Issue #73 — signed proof issuer integrated with durable nonce ledger

**Status: isolated server reference only; NOT deployed or approved for device promotion.**

This closes the gap between the previously isolated SQLite challenge ledger
(PR #106) and the Ed25519 candidate-bound WebView proof verifier (PR #105):
the proof issuer must successfully **consume** the bound random nonce in
SQLite before it signs a proof. A duplicate, expired, invalid or uncommitted
nonce **never authorizes signing**.

## Components and integration

- `signed_proof_issuer.py` uses the real `NonceLedger.consume()` from PR #106
  and a separately supplied `Ed25519PrivateKey` compatible signer; no key,
  private hostname, token, phone log or production value is embedded.
- `TrustedTokenRecord` is an **asserted trustworthy in-process server record**.
  The actual production handler must obtain it by authenticated/authorized
  lookup in the server's durable, audited token table. **Do not construct
  it from HTTP request fields.** Merely receiving a token ID, digest or
  `fingerprint_matches=true` from an untrusted caller proves nothing.
- `signed_proof_issuer.py` rejects old/exposed or revoked tokens, invalid
  token identity, wrong kind, invalid clock/TTL and unregistered nonce.
- Signed JSON field order and binary Ed25519 signature match PR #105:
  `purpose`, `kind`, `ok`, `fingerprint_matches`, `token_id`,
  `fingerprint`, `nonce`, `issued_at`, `expires_at`, and
  `signature` (base64). TTL limited to 60 seconds in this reference.
- The SQLite consume **commits before signing**. A signer crash permanently
  burns the challenge: no silent replay or reissue.
- The issuer never logs, returns or stores the credential's raw value,
  signing private key, or nonce in the SQLite table; the signed response
  necessarily includes the **nonce** because the verifier checks the
  server signature over that bound challenge. This response is sensitive
  operation metadata, not a credential; do not log real values.
- This code is not a production HTTP endpoint and never touches
  the pending command, action queue, result, old last_id, pins or timers.

## Automated evidence

`test_signed_proof_issuer.py` exercises 16 isolated
Python+SQLite cases including genuine Ed25519 signature verification,
duplicate nonce, token kind/identity, revoked/exposed status, expiry,
registry failure, faulty signer after consumed commit, deliberately broken
SQLite and concurrent signers (only one may sign).

`test_signed_proof_interop_fixture.py` creates **ephemeral** Ed25519
keys and synthetic token in a private temporary directory.
`test_signed_proof_issuer_webview.js` invokes it, then verifies its actual
signed JSON using the WebCrypto-compatible verification library. The
WebView test also rejects wrong nonce/candidate, token-ID tampering,
and missing trusted public key. **No real tokens or private keys enter
GitHub/Actions output**.

CI installs a pinned *test-only* `cryptography==46.0.4`. Its presence
does NOT establish the same dependency is deployed or approved on the
production host.

## Release blockers that remain

1. The **real production signing endpoint** with verified device
   authentication, authorization, strict token registry and separated
   signing key material remains unimplemented here.
2. The server's single-host ledger cannot survive arbitrary database
   snapshot rollback without replay risk, and does not offer
   multi-host distributed consensus. Backup/recovery must be audited.
3. A valid signed proof is still replayable on a client that reuses its
   `expectedNonce`. The phone needs a fail-closed, durable one-use
   challenge lifecycle, whose atomicity is **not guaranteed** by Surge
   `$persistentStore` as currently documented.
4. The source-free iPhone `engine=webview` Ed25519/atob capability probe
   has only Node VM results; iPhone proof remains missing.
5. The genuine credential/backup token promotion, old exposed token
   revocation, two cron observations and production rollback require
   distinct authorized device/server checks.

**No-GO remains:** `C3-C1=NO-GO`, `PR93=BLOCKED`,
`AUTO_DELETE=OFF`, old pending command `OUTCOME_UNKNOWN` fenced,
21 protected pinned nodes and five timers untouched.
