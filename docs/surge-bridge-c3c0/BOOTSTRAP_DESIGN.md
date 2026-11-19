# C3-C0 S1 — Secure Credential Bootstrap Design (Round 3)

## Purpose

GPT gate 1 (receipt 7011593598) requires an **executable, non-token-exposing
bootstrap** that writes the new DEV token (and local key) into the device
`$persistentStore`, plus device-side security / cache / log verification.
This design covers the **device side only**. The server-side token-table
change (dual-credential window, revocation of the exposed old DEV token)
is gate 2 and needs separate review; it is NOT part of this design.

## 1. The bootstrap mechanism

### 1.1 What it is

A **one-time Surge script** (`s1/bootstrap.js`) that the owner creates
**locally in the Surge app on the phone**. It is never distributed by URL,
never uploaded to GitHub, and never sent anywhere. The owner:

1. Generates the new DEV token server-side (see §2).
2. In the Surge app, creates a NEW local script and pastes the contents of
   `s1/bootstrap.js` into it.
3. Replaces the two `<PASTE_...>` constants with the new DEV token and the
   local Surge HTTP API key.
4. Runs the script ONCE (manual run in Surge).
5. Reads the output: it must say exactly `bootstrap_ok` and nothing else.
6. **DELETES the script from Surge immediately** (required checklist step).
7. Verifies (§3).

### 1.2 What the script does

- Validates the pasted values: non-empty string, ≤512 chars, no CR-LF,
  not a `<placeholder>`. Invalid input → `bootstrap_failed: invalid_input`,
  nothing written.
- Writes the DEV token to `sgbridge_cred_dev` and the local key to
  `sgbridge_cred_localkey` via `$persistentStore.write`.
- Verifies the write by reading both values back and comparing them
  exactly to the pasted values. A failed write (`write` returns non-`true`
  or throws) or a read-back mismatch → `bootstrap_failed: write_or_verify`,
  no done flag.
- On success, sets `sgbridge_bootstrap_done = "1"`, then logs
  `bootstrap_ok`.
- The **only output** is a status word (`bootstrap_ok` /
  `bootstrap_failed: ...` / `bootstrap_already_done`). The token value
  never appears in any log, notification, or file.
- A second run finds the done flag and does nothing — it cannot re-expose
  or overwrite the credential.

### 1.3 What the script cannot do (honest limits)

- A Surge script **cannot delete itself** (no API for removing a script).
  Manual deletion by the owner is a required checklist step, not an
  automatic guarantee. The done flag is the in-script protection; deletion
  is the owner's step.
- Surge has no built-in crypto/hash API in the scripting environment, so
  the on-device script verifies the write by **read-back equality**, not
  by a SHA-256 fingerprint. The SHA-256 fingerprint is a **server-side
  audit record** (computed where the token was generated); the isolated
  test (`s1/bootstrap_test.js`, B1) verifies that the read-back value
  hashes to the same fingerprint as the generated token, using node:crypto.
- If the owner pastes a token with a trailing newline/whitespace, the
  script source may fail to parse (a raw newline inside a string literal
  is a syntax error). That is fail-closed (nothing is written), but the
  owner must paste cleanly — no trailing newline. The script's `valid()`
  check rejects CR-LF that survives as characters inside the value.

## 2. How the token reaches the owner securely

- The new DEV token is generated **server-side** (random 64-hex string,
  e.g. via a root-only command on the VPS) and stored in a **root-only
  file** (mode 600) on the server. It is never placed in a public URL, a
  chat message, an email, or a GitHub file.
- The owner reads it via **SSH to the server** (from their own computer),
  reading the root-only file. The owner also records the token's SHA-256
  fingerprint (first 16 hex chars) from the server for the audit record.
- The local Surge HTTP API key is already known to the owner (it is in
  Surge's own settings on the phone). The owner pastes the existing key;
  it is not generated server-side.
- The token is copied by the owner **directly into the locally-created
  Surge script** (paste into the editor). It is never transmitted over
  the network by the bootstrap itself — the bootstrap makes **zero
  network requests**.

## 3. Device-side verification

After the bootstrap run and script deletion, the owner (or Muse, from
the server side) verifies:

| Check | How | Expected |
|---|---|---|
| Credential present | Next bridge cron run: phase log shows `credential_present` | Present, no value logged |
| Right token stored | Server-side `/poll` with the new token returns 200 (not 403) | 200; a wrong token would give 403 → bridge logs `auth_forbidden` |
| No token in logs | Bootstrap output is only `bootstrap_ok`; bridge phase log contains no token value | Status words only |
| Script deleted | Surge script list no longer contains the bootstrap script | Deleted |
| No re-exposure | A second run (if the script were still present) logs `bootstrap_already_done` and writes nothing | Done flag set |

**What remains unverified (open items):**
- Whether `$persistentStore` contents are included in iCloud / device
  backups, and whether a backup restore could expose the token. The
  Surge manual does not state this; it is recorded as **unverified**,
  not assumed safe.
- Whether any other app, profile, or log on the device can read the
  Surge app's `$persistentStore`. Same status: **unverified**.
- The functional proof (poll 200) confirms the right token is stored;
  it does not prove the token is absent from every other place on the
  device. That is a device-forensics question, not a script question.

## 4. The `$persistentStore` caveat (explicit)

`$persistentStore` is a **simple persistent key-value API** (Surge
manual: "simple persistent key-value API"). It is **not** a proven secure
hardware keystore / secure enclave. This bootstrap removes the credential
from the **publicly distributed script** — that is the vulnerability
being fixed (the token was in a public URL). It does **not** claim the
credential is stored in a secure enclave. This remains an **open item**
for the C3-C1 gate: the device-side storage must be accepted as a
residual risk, or a stronger mechanism must be found and verified.

## 5. Dual-credential window / revocation (gate 2 — referenced, not designed here)

The S1 Rev 1 plan (`SECURITY_GATE_PLAN.md`) already specifies: the
leaked DEV token is never re-enabled as a rollback credential; rollback
uses a pre-issued new backup token or fail-closed with separate approval;
the 48h dual-token parallel window is an upper bound, not a target.
The **server-side token-table change** (accepting both tokens during the
window, then revoking the old one, with separate rollback evidence) still
needs its own design and review. It is NOT part of this bootstrap design.
On loss of contact, the old exposed token must NOT be routinely revived.

## 6. Isolated verification

`s1/bootstrap_test.js` (7 tests, synthetic tokens only, no network):

| Test | Result |
|---|---|
| B1 successful bootstrap: write + read-back match, done flag set, only status logged; read-back SHA-256 fingerprint matches generated token | PASS |
| B2 second run finds done flag: no re-write, no token exposure | PASS |
| B3 failed write detected: no done flag, failure reported, no token logged | PASS |
| B4 read-back mismatch detected: failure reported, no done flag | PASS |
| B5 invalid pasted values rejected (empty / placeholder / CR-LF / >512 chars): nothing written | PASS |
| B6 bootstrap script source contains no real token: placeholder only | PASS |
| B7 bootstrapped values pass the v2.2 `readCredential` validation rules | PASS |

**Result: 7/7 PASS, 0 FAIL.** Run: `node s1/bootstrap_test.js`.

## 7. Files

- `s1/bootstrap.js` — the one-time bootstrap script (placeholder only).
- `s1/bootstrap_test.js` — isolated tests (7/7).
- `s1/bootstrap_out.json` — test results.
- This file (`BOOTSTRAP_DESIGN.md`).

## 8. Open items (for the C3-C1 gate)

1. `$persistentStore` backup / cross-app exposure: **unverified** (§3).
2. Server-side token-table change (gate 2): needs separate design + review.
3. Real-device bootstrap run: not done (requires the owner to run the
   script once on the phone and delete it; no live action in this round).
4. Real-device loading of the new SHA + two cron cycles observing the
   old pending fenced: not done (C3-C1).
