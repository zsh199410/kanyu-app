# C3-C0 VPS Staging Acceptance Report — Issue #73 Round 9

**STAGING_ACCESS=YES** — the trusted US VPS staging environment works end to end.
Real (not simulated) HTTPS/TLS, auth, atomic consume, revocation, restart,
rollback and snapshot-restore evidence below. No production change.

- Date: 2026-11-20, staging run 10:32–10:41 CST
- VPS: US (address redacted), root, Python 3.13.5, cryptography 43.0.0,
  OpenSSL 3.5.7, curl 8.14.1, sqlite3 (Python module) 3.46.1
- Staging dir: `/opt/c3c0-staging/` (0700), data `/opt/c3c0-staging/data/` (0700)
- Staging port: **127.0.0.1:18443** (loopback only; verified, item 9)
- Service PIDs (sequence): 34159 → 35424 → 35816 → 36298 → 37726
  (restarts + one SIGKILL recovery, see "Staging-harness bug found")
- Pre-test snapshot: `/opt/c3c0-staging-snapshot-pre-test.tar.gz`,
  SHA `a037508c4e6b4ad21eaf626db20d77aada5ebbb83ac014a19329ce62cb8dbd44`
- Gates unchanged: `BOOTSTRAP_SECURITY_GATE=BLOCKED`,
  `CREDENTIAL_DISTRIBUTION_GATE=BLOCKED`, `C3-C1=NO-GO`,
  `PR93_CUTOVER=BLOCKED`, `AUTO_DELETE=OFF`
- Issuer used: **PR #109 `AtomicSignedProofIssuer` only** (same-SQLite-transaction
  token check + nonce consume). PR #108 `SignedProofIssuer` is present on the
  staging host ONLY as an import dependency of `credential_proof_https.py`;
  it is NEVER used as an issuer (F2 = CONFIRMED production blocker).

## File SHAs (local vs VPS — all match)

| File | SHA-256 (local = remote) |
|---|---|
| credential_proof_https.py (PR #110) | c638bfdda81641c01ac4f1e20bbefeb41521ba98cbcfeeb03d340c49bc119606 |
| token_registry_sqlite.py (PR #109) | 75c6a06345b19eac02293e69a6124259346446782be001c0f3b20a28c3c35934 |
| atomic_signed_proof_issuer.py (PR #109) | a1e04f1554d02d5c9945119cebd5714f73dfcb8236b2303118d147587785fb66 |
| nonce_ledger_sqlite.py (PR #106) | 96dd9cb645d19c77e415b1ca76c3cad754c6457ea4ed164f2bb1251cf7b75d37 |
| signed_proof_issuer.py (PR #108, import dep only) | a3d5bc5e0b727df0b5090183e1a22aed829564ed224074a3f451802e43b7f128 |

## Synthetic credentials (fingerprints only — no values anywhere)

- Pairing bearer (64 chars, `[A-Za-z0-9_-]`): SHA-256 prefix `b7a07220`
- Token STAGE-OLD-01 (role exposed_old, kind dev): fingerprint prefix `f948c696`
- Token STAGE-NEW-01 (role new, kind dev): fingerprint prefix `7e6110d9`
- Token STAGE-BACKUP-01 (role backup, kind dev): fingerprint prefix `852ed34c`
- Ed25519 test keypair (fresh, independent): public-key SHA-256 prefix `8b647bdb`
- Staging CA cert (CN=staging-test.invalid): SHA-256 fingerprint `5b2c8db31d63e887…`
- Server cert (CN=localhost, SAN DNS:localhost + IP:127.0.0.1): `d7b07f2521236621…`
- Wrong CA cert (CN=staging-wrong.invalid): `0d64232fcd1a66fe…`
- All values were generated fresh on the VPS by `staging_setup.py`. No real
  DEV token, no real local key, no production credential was read, used, or
  copied. `~/workspace/surge-bridge/tokens.env` was never read.

## Verification matrix

### 1. TLS chain — PASS
- `curl --cacert tls/staging-ca.crt` + valid proof body → **HTTP 200** with a
  full signed proof (`purpose=issue73/credential-promotion/v1`, `ok=true`,
  `fingerprint_matches=true`, `token_id=STAGE-NEW-01`).
- `curl --cacert tls/staging-ca-wrong.crt` → **HTTP 000** (TLS handshake
  rejected, no HTTP response).
- `curl` with the default system CA bundle (no `--cacert`) → **HTTP 000**
  (self-signed staging CA not trusted).
- `openssl s_client -CAfile staging-ca.crt` → `Protocol version: TLSv1.3`,
  `Ciphersuite: TLS_AES_256_GCM_SHA384`, `Verification: OK`.
- `openssl s_client -CAfile staging-ca-wrong.crt` → `verify error:num=20:
  unable to get local issuer certificate`, `Verification error`.
- `openssl s_client -tls1_2` → `Protocol version: TLSv1.2`, `Verification: OK`.
- `openssl s_client -tls1_1 -cipher "DEFAULT@SECLEVEL=0"` → server answers
  `tlsv1 alert protocol version` (SSL alert number 70) — **the server
  itself rejects TLS 1.1**. (The plain `-tls1_1` attempt fails on the
  client side first — OpenSSL 3.5 refuses to offer TLS 1.1 — so the
  SECLEVEL=0 run is the real server-side evidence.)

### 2. Auth rejection — PASS
- No `Authorization` header → **401** `{"status":"unauthorized"}`,
  ledger counts unchanged **(1,1)** — no write.
- Wrong pairing bearer (64×`X`) → **401** `{"status":"unauthorized"}`,
  counts unchanged **(1,1)** — no write.
- Correct bearer → proceeds (200, see item 3).

### 3. Independent pinned key — PASS
- Proof for STAGE-NEW-01 → **200**; the Ed25519 signature **verifies
  against the fresh test public key: True** and **fails against a different
  freshly generated public key: False** (wrong-key verification returns
  False, as required). Proof keys: `expires_at, fingerprint,
  fingerprint_matches, issued_at, kind, nonce, ok, purpose, signature,
  token_id`. Counts after: (2,2).

### 4. PR #109 atomic consume + concurrency — PASS
- Two simultaneous POSTs with the **same nonce** (ThreadPoolExecutor, 2
  workers) → codes **[200, 409]**, exactly one proof and one
  `nonce_reused`. Counts (3,3). This is the atomic path: token check and
  nonce consume happen in one `BEGIN IMMEDIATE` transaction, so the second
  request cannot slip through between lookup and consume (the F2 window
  does not exist here).

### 5. Duplicate / replay / revoked / standby — PASS
- Same nonce twice, sequentially → first **200** (signature verifies),
  second **409** `{"status":"nonce_reused"}`, counts unchanged (4,4).
- OLD exposed token request → **403** `{"status":"proof_not_authorized"}`,
  counts (5,4): the nonce is registered/burned (total +1) but never
  consumed — fail-closed, no signature produced.
- Standby BACKUP request (before activation) → **403**, counts (6,4).
  Same burn behavior.

### 6. Dual-token revocation + backup activation — PASS
- Issue with A (STAGE-NEW-01) before activation → **200**, counts (7,5).
- `activate_backup(STAGE-BACKUP-01)` → **True**. Audit after:
  `backup:active 1, exposed_old:active 1, new:revoked 1` — the revoke of
  NEW and the activation of BACKUP happened atomically.
- Issue with A after activation → **403**, counts (8,5).
- Issue with B (STAGE-BACKUP-01) after activation → **200**, signature
  verifies, counts (9,6).
- Mock bridge `authorize(A)` → **403 `token_revoked`**;
  `authorize(B)` → **200 `ok`**.
- `revoke(STAGE-OLD-01)` → **True**. Audit after: `backup:active 1,
  exposed_old:revoked 1, new:revoked 1`.
- Issue with OLD after revoke → **403**, counts (10,6).
- Mock bridge `authorize(OLD)` → **403 `token_revoked`**.
- Final counts at end of item 6: (10,6).

### 7. Restart retention — PASS
- Issued a proof with a known nonce (`_27wXAPY…`, BACKUP) → **200**,
  counts (11,7) before restart.
- Restarted the service (new PID 35424). Counts after restart: **(11,7)** —
  identical. Audit identical.
- Replay of `_27wXAPY…` after restart → **409** `nonce_reused`.
- Issue with revoked OLD after restart → **403**, counts (12,7).
- Fresh proof with BACKUP after restart → **200**, signature verifies,
  counts (13,8).

### 8. Code rollback rehearsal — PASS
- Counts before rollback: (13,8); audit `backup:active 1,
  exposed_old:revoked 1, new:revoked 1`.
- Stopped the service cleanly (SIGTERM), restored `/opt/c3c0-staging/`
  from `/opt/c3c0-staging-snapshot-pre-test.tar.gz` (pre-test state).
- Restored DB verified: counts **(0,0)**, audit `backup:standby 1,
  exposed_old:active 1, new:active 1` — the pre-test state.
- Restarted from the restored state (PID 35816), listening on
  127.0.0.1:18443, counts (0,0).
- Fresh proof with NEW after rollback → **200**, signature verifies,
  counts (1,1).
- Note: the snapshot predates the signal-handler fix below, so the
  restored `staging_server.py` was the pre-fix version; the fix was
  re-applied afterwards (scp) and the service restarted cleanly.

### 9. Binding verification — PASS (with a documented test caveat)
- VPS-side `ss -ltnp`: the ONLY listener on port 18443 is
  `127.0.0.1:18443` (python3, staging PID). **No listener on
  `0.0.0.0:18443` or the public IP.** The `LoopbackTLSServer` constructor
  also raises `public_network_binding_not_authorized` for any host other
  than 127.0.0.1 (code-level enforcement).
- `curl https://<VPS-public-IP>:18443/credential-proof (connection refused, loopback-only service)` (via the egress proxy)
  → **HTTP 000** (connection refused).
- No iptables rule mentions port 18443; no firewall port was opened.
- Caveat: a direct `/dev/tcp` connect from this sandbox "succeeds" even to
  definitely-closed ports (controls: :19999 and :18444 both "succeeded"),
  because the sandbox egress network accepts all outbound TCP SYNs. The
  `/dev/tcp` result is therefore meaningless here and is NOT used as
  evidence; the binding is proven by the VPS-side `ss` output and the
  proxy-mediated curl failure instead.

### 10. Snapshot-restore limitation — DEMONSTRATED (known gap, real in staging)
- DB snapshot taken at counts (1,1), SHA
  `2293562a23b7fa1bb47811b11803e0b5c457e9725e29ec9b381ea88028089dc3`.
- Consumed a fresh nonce `jG2YKS6A…` with NEW → **200**, counts (2,2).
- Replay of `jG2YKS6A…` → **409** `nonce_reused`, counts (2,2).
- Stopped the service, restored the pre-consume DB copy (SHA back to
  `2293562a…`, counts back to (1,1)), restarted (PID 37726).
- Replay of the SAME nonce `jG2YKS6A…` after the restore → **HTTP 200**
  with a valid signature — **the consumed nonce was resurrected**.
  Counts (2,2).
- This proves the documented limitation is real in staging: restoring an
  old SQLite snapshot resurrects consumed nonces (and, by the same
  mechanism, revoked tokens). Production MUST have an independent
  rollback-resistant epoch / high-water mark / audit anchor before any
  cutover. No such mechanism exists in the current modules.

## Staging-harness bug found and fixed (not a GPT module bug)

My own `staging_server.py` signal handler called `server.shutdown()`
directly from the SIGTERM handler. `shutdown()` blocks waiting for
`serve_forever()` to return, but `serve_forever()` is suspended inside
that same handler → deadlock. Observed twice: after `kill <pid>` the
process stayed alive, still bound to 18443, but TLS handshakes timed out
("The handshake operation timed out"); a second server then failed with
`OSError: [Errno 98] Address already in use`. Recovery was `kill -9`.
Fix (applied, in `~/workspace/pr96-c3c0/staging/staging_server.py`):
the handler now starts `server.shutdown()` in a separate daemon thread so
the main loop can notice the flag and exit; `server.server_close()` runs
in the `finally` block. After the fix, SIGTERM stops the service cleanly
("STAGING SERVER EXITED", port freed) — verified three times (items 7, 8,
10 + final stop). The GPT modules themselves were not modified.

## Counts timeline (ledger total, consumed)

Setup (0,0) → 1a (1,1) → 2a/2b (1,1) → 3 (2,2) → 4 (3,3) → 5a (4,4) →
5b (5,4) → 5c (6,4) → 6a (7,5) → 6c (8,5) → 6d (9,6) → 6h (10,6) →
7a (11,7) → restart (11,7) → 7c (12,7) → 7d (13,8) → rollback restore
(0,0) → 8e (1,1) → 10b (2,2) → 10c (2,2) → DB restore (1,1) → 10e (2,2).
Final state at stop: (2,2), audit `backup:standby 1, exposed_old:active 1,
new:active 1` (post-rollback state).

## Remaining blockers (for production — none of these are staging failures)

1. **Rollback-resistant epoch / high-water mark**: item 10 proves a DB
   snapshot restore resurrects consumed nonces and revoked tokens. No
   mechanism for this exists in the current modules. REQUIRED before
   cutover.
2. **In-flight drain**: the registry doc states in-flight signing after a
   committed authorization is NOT stopped by a later revocation.
   Production revocation needs a freeze/drain gate for in-flight issuers.
   NOT tested in staging (it is a design gap, not a code path).
3. **Device generic/intent context**: the owner's real-device evidence
   covers only the editor WebView (`isSecureContext=false`, no
   `crypto.subtle`). The module's actual manual generic/intent context is
   still unmeasured. Pure-JS device probe is UNVERIFIED.
4. **Real production TLS / domain / pinned key distribution**: staging used
   a self-signed cert for `staging-test.invalid` on loopback. A real
   deployment needs a real cert chain, a real domain, and a trusted pinned
   Ed25519 public-key distribution path — none of which exists yet.
5. **F3 (low)**: malformed input maps to `*_commit_unknown` labels; the
   paths are fail-closed, but the labels conflate input errors with
   unknown commit state. Does not block synthetic staging.
6. **PR #108 is a production blocker (F2)**: it must never be deployed as
   a stand-alone issuer. Only the PR #109 atomic path is a staging
   candidate.

## What is NOT verified

- Nothing was tested against the real phone, the real Surge bridge, the
  production HTTPS route, or the node pool. No device-side durable
  one-time nonce consumption was demonstrated.
- The in-flight revocation race (signing completing after revocation
  lands) was not exercised — it is a documented design gap.
- The staging service was never exposed publicly; no external client other
  than the loopback client and the proxy-mediated curl failure was tested.
- No real credential was rotated or revoked. No production state changed.

## Reproduction (exact commands)

SSH pattern (each exec call first saves the egress proxy):
`export ORIG_PROXY="$https_proxy"; ssh -i ~/.ssh/homeline_agent_ed25519 -oProxyCommand="$HOME/workspace/system/ssh-proxy.py %h %p" -o UserKnownHostsFile=/home/hatch/.ssh/known_hosts -p 22222 root@<VPS> '<command>'`

- Setup (once): `cd /opt/c3c0-staging; python3 staging_setup.py`
  (generates synthetic creds + TLS, registers the 3 test tokens)
- Start: `nohup python3 staging_server.py >> server.log 2>&1 < /dev/null &`
- Client: `python3 staging_client.py proof STAGE-NEW-01`
  | `proof-nonce TOKEN_ID NONCE` | `no-auth` | `wrong-auth` | `wrong-ca`
  | `no-ca-verify` | `concurrent [TOKEN_ID]` | `counts`
- Admin: `python3 staging_admin.py counts` | `activate-backup`
  | `revoke TOKEN_ID` | `auth-check TOKEN_ID`
- TLS: `curl --cacert tls/staging-ca.crt -H @/tmp/stage_auth.txt -H
  "Content-Type: application/json" --data @/tmp/stage_body.json
  https://127.0.0.1:18443/credential-proof`
  (body/auth files are generated by a Python one-liner from config.json;
  see the staging scripts)
- Stop: `kill $(cat server.pid)` (clean SIGTERM with the fixed script)
- Snapshot: `tar czf /opt/c3c0-staging-snapshot-pre-test.tar.gz -C /opt c3c0-staging`
- Staging scripts (local copies): `~/workspace/pr96-c3c0/staging/`
  (`staging_setup.py`, `staging_server.py`, `staging_client.py`,
  `staging_admin.py`)

## Production untouched — before/after

| Check | Before (10:30–10:32 CST) | After (10:41 CST) | Match |
|---|---|---|---|
| bridge.js SHA-256 | 466cb56b5877bf2d… (4716 B) | 466cb56b5877bf2d… (4716 B) | YES |
| server.py SHA-256 | 5e73f981296717f3… | 5e73f981296717f3… | YES |
| server PID | 37222, `/usr/bin/python3 /opt/surge-bridge/server.py` | 37222, same cmd (elapsed 15:23:36 → 15:33:16) | YES |
| state cmd id | 1795063030 | 1795063030 | YES |
| state result id | 1795055213880 | 1795055213880 | YES |
| state polls | 2525 | 2526 (one normal poll cycle) | — |
| pinned-nodes.txt SHA | 932c0f0e1c22c6e1… (25 non-empty lines) | 932c0f0e1c22c6e1… (25 lines) | YES |
| timers | 5 (pool-test, pool-sync, pool-publish, pool-crawl, pool-test-full) | 5, same set | YES |

Nothing under `/opt/surge-bridge/` was modified, restarted, or stopped.
No firewall port was opened. No production credential was read or used.
The staging service is STOPPED; `/opt/c3c0-staging/` is left in place with
a README (synthetic-only, not production) for inspection.
