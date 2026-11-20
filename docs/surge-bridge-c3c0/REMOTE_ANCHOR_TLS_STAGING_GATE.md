# Issue #73 — Remote signed anchor over actual HTTPS (STAGING ONLY)

**No production host or device has been modified.** This adds a
dual-loopback-HTTPS *protocol demonstration* against temporary SQLite
and synthetic credentials, built on PR #115's **start-frozen** full
request gate. Neither listener is exposed to a public IP.

## Structure and trust boundaries

- `remote_anchor_https_staging.py` contains
  `AnchorAuthorityStore`, `LoopbackAnchorTLSServer`, and
  `PinnedAnchorTLSClient`.
- The authority is a separate localhost TLS endpoint on its own port,
  backed by a separate test SQLite path and an ephemeral **authority
  signing key** (not the credential proof signing key).
- The authority has **no HTTP bootstrap, reset, rewind or delete API**.
  Bootstrap requires a privileged, explicit, offline-only call.
- `GET /head` returns the last state digest and epoch in an Ed25519
  signed recovery checkpoint. `POST /advance` requires exact
  `expected_epoch`, exact previous SHA256 state digest and a
  different new SHA256 digest, and uses SQLite `BEGIN IMMEDIATE` CAS
  before increasing the epoch exactly one. A stale/duplicate
  request returns 409 with no epoch increment.
- Both API routes require an independent bearer over
  TLS1.2+ and the client explicitly disables proxy environment
  variables for these localhost requests.
- The client requires a trusted CA plus independently pinned Ed25519
  public key; it verifies exact checkpoint signature against the
  **actual business SQLite state digest** before PR115 can reopen.
- The client callback `commit_and_fetch_anchor(ledger)` makes an
  explicit state-CAS request, verifies the signed response, then
  returns a `(record, epoch)` tuple for PR115 to **independently**
  reverify before exposing any HTTP 200 signed-proof response.
- A lost acknowledgement, timeout, stale CAS or tampered root
  raises a nonsecret error, so PR115 returns 503, freezes the
  entire HTTPS request ingress and never retries the same nonce.
  Reconciliation requires fetching a fresh signed remote head and
  matching the local database; no automatic re-bootstrap.

## Evidence and limits

Dedicated CI uses real TLS sockets, server-side persistence,
synthetic pairings, two independent *in-process* endpoints and
ephemeral Ed25519 keys. It tests correct signed proof after
commit, stale/duplicate requests, wrong bearer/CA/public key,
response-loss-after-COMMIT, old business SQLite restored from a
real backup, startup default freeze, offline bootstrap restriction,
server re-instantiation preserving epoch, and explicit correlated
snapshot rollback negative control.

**Do not call this a separate VPS or real external authority.** Both
endpoints run on the SAME CI host and the entire test fixture may be
rolled back. A negative test explicitly restores the authority
database alongside old epoch; the old epoch reappears. Therefore the
production-proof property still requires a genuinely independent
failure/backup/administrator domain.

The authority accepts new SHA256 digests from an authenticated
client. It does not independently inspect or authorize the business
database's underlying mutations. A compromised client with a valid
bearer could submit arbitrary state hashes. A production trusted
authority needs provisioning/role separation, authenticated session
and independent security invariants and a durable signed audit log.
This reference has no key custody service, remote signing HSM,
distributed high-water protection, secure deployment, backup
policies, production certificate trust path, or phone-side
single-use nonce consumption. Do not use any real token or key.

## Required real VPS staging gate

- Host the witness on a **different failure/backup domain** than the
  business VPS; confirm no common snapshot/backup/credential
  rollback. Provide issuer-side peer authentication, TLS and Ed25519
  root pin distribution through an independently audited channel.
- Server startup must begin frozen (PR115). Only an authenticated
  remotely signed and DB-matching `/head` permits explicit reopen.
- Test 200 proof withholding when remote commit times out, remote
  reboots or rejects CAS. Reopen only after independently signed
  readback of the durable epoch and exact business state.
- Test revoked/consumed nonce after business VPS rollback, witness
  VPS independent reboot, out-of-order in-flight concurrent requests
  and SIGKILL; all endpoint bypasses fail closed.
- Agree on a single canonical ingress gate/issuer path: PR115
  defaults frozen and withholds HTTP 200; PR116 adds a separate
  witness test double. Do NOT stack two unrelated admission objects
  or swap the unsafe default-open reference into production.

**GATES:** `EXTERNAL_EPOCH_PROVISIONED=NOT_VERIFIED`,
`REMOTE_TLS_ANCHOR_CI!=PRODUCTION`,
`PUREJS_DEVICE_PROBE=UNVERIFIED`,
`DEVICE_DURABLE_NONCE=UNVERIFIED`,
`C3-C1=NO-GO`, `PR93_CUTOVER=BLOCKED`,
`AUTO_DELETE=OFF`. Preserve 21 protected pinned nodes,
five timers and old command `1795063030` OUTCOME_UNKNOWN.
