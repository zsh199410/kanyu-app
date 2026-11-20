# C3-C0 — Staging-to-Active Promotion Gate Design (Round 4)

## Status

Design + isolated executable sample + isolated tests. **Not a production
change.** No phone action, no server change, no public script change,
no credential revocation is authorized by this document. Gates
unchanged: `C3-C1=NO-GO`, `PR93_CUTOVER=BLOCKED`,
`BOOTSTRAP_SECURITY_GATE=BLOCKED`, `AUTO_DELETE=OFF`.

This is launch blocker (2) from GPT receipt 7013674858. It depends on
blocker (1) (candidate staging, PR #101 templates + local-key companion)
and on blocker (3) (server dual-token, `DUAL_TOKEN_DESIGN.md`). It does
not depend on blocker (4) (real-device release proof) or (5) (release
checklist / prod rollback), which are NOT built in this round.

## 1. What the gate is

Promotion moves a staged candidate credential into the active slot
the bridge reads (`sgbridge_cred_dev` / `sgbridge_cred_localkey`).
Staging (blocker 1) only writes candidate keys and never touches the
active keys. Promotion is the ONLY path by which an active key may
change, and it runs only when ALL of the conditions in §2 hold. There
is no other writer of the active keys.

## 2. Promotion conditions (all must hold)

(a) **Candidate exists and validates.** The candidate key
    (`sgbridge_cred_dev_candidate` / `sgbridge_cred_localkey_candidate`)
    holds a value that passes the bridge's `readCredential` rules
    (string, non-empty, ≤512 chars, no CR-LF, not a `<...>`
    placeholder) AND the staging template's window (32–256 chars,
    printable ASCII only). If the candidate is absent or invalid, the
    gate fails closed and changes nothing.

(b) **Server-side proof is present.** A `/credential-proof` response
    for the NEW token (see §3). The proof must confirm the server has
    issued a token with this fingerprint, that it is not the old
    exposed token, and that it is fresh. No proof, or an invalid
    proof, fails closed.

(c) **Active token is still the old one.** The active key must hold a
    value that is present and DIFFERENT from the candidate. If the
    active key already equals the candidate, the promotion already
    happened: the gate returns `promotion_already_active` as a
    successful no-op (idempotent). If the active key is absent, the
    gate fails closed (`promotion_no_active`) — initial provisioning
    into an empty slot is a different gate, not this one.

(d) **The promotion write is atomic in the only sense available.**
    Write the new active value, read it back and verify it equals the
    candidate, and ONLY THEN clear the candidate key. Any failure at
    any step before the read-back verification leaves the active token
    unchanged and the candidate intact (fail-closed). See §4 for the
    exact sequence and the clear-failure case.

(e) **The old exposed token is never re-enabled.** The proof's
    `token_id` must not be the old token's id, and the candidate must
    not equal the current active (old) value. Rollback after a failed
    promotion never writes the old exposed token back: the rollback
    path is a NEW backup token (pre-issued, held unused) or
    fail-closed, per S1 Rev 1. There is no code path in the gate that
    writes the old token value anywhere.

(f) **The old command is never touched.** The gate has no code path
    that reads or writes the mailbox, the ledger, `last_id`, pins, or
    timers. The old single-slot command `1795063030` stays
    `OUTCOME_UNKNOWN` and is never replayed, overwritten, or cleared
    during promotion. The sample test asserts this by snapshotting a
    mock mailbox state before and after every promotion attempt.

## 3. `/credential-proof` endpoint contract (design only)

The sample uses a MOCK proof object. No real server call is
implemented, and no real server change is proposed here — the endpoint
is a contract the server side (blocker 3) must implement before a
real promotion can run.

- Request (device → server, over the existing authenticated channel):
  `{ fingerprint: "<sha256-hex of the NEW token>", nonce: "<random>" }`.
  The token VALUE is never sent. Only its SHA-256 fingerprint.
- Response (server → device):
  `{ ok: true, fingerprint_matches: true, token_id: "<server token id>",
    issued_at: <unix ms>, expires_at: <unix ms> }`.
- The gate accepts the proof ONLY if: `ok === true`,
  `fingerprint_matches === true`, `token_id` is a non-empty string
  and is NOT the old token's id, `issued_at` is a number within the
  freshness window (issued within the last 24 hours and not more than
  5 minutes in the future). Any other shape fails closed.
- The fingerprint is computed by the SERVER from the token it issued,
  or by the device from the candidate value — either way, the proof
  binds the candidate to a server-issued token id without ever
  transmitting the token itself. Which side computes the fingerprint
  is an open item for the server-side implementation (blocker 3).

## 4. Promotion sequence (fail-closed at every step)

```
1. candidate = store.read(candidateKey)
   absent/null            -> if the status key reads
                             "promotion_done" (the last promotion
                             completed and nothing has been staged
                             since): promotion_already_active, OK
                             (no-op, idempotent). Otherwise:
                             promotion_no_candidate, FAIL,
                             nothing changed.
2. !validCandidate(candidate)
                          -> promotion_invalid_candidate, FAIL
3. !validProof(proof, oldTokenId)
                          -> promotion_invalid_proof, FAIL
4. active = store.read(activeKey)
   active === candidate   -> promotion_already_active, OK (no-op, idempotent)
   active absent/null     -> promotion_no_active, FAIL
5. committed = store.write(candidate, activeKey)
   throws, or returns !== true:
       read back active:
         === candidate    -> the write DID commit despite the false
                             return: promotion_commit_unknown, FAIL,
                             candidate intact, DO NOT report success,
                             DO NOT clear the candidate.
         === old value    -> the write did not commit:
                             promotion_commit_unknown, FAIL,
                             candidate intact.
6. store.read(activeKey) !== candidate
                          -> promotion_readback_unverified, FAIL,
                             candidate intact.
7. clear the candidate key (see §5)
   clear fails            -> promotion_candidate_clear_failed, FAIL
                             (see below: active is already the new
                             verified value; candidate intact; a
                             retry converges to promotion_already_active)
   clear succeeds         -> promotion_done, OK.
```

Status is written to `sgbridge_promotion_status` (DEV) /
`sgbridge_cred_localkey_promotion_status` (local key) as a non-secret
enum only. A status-write failure is best-effort (ignored) and never
changes the outcome — the outcome is determined by the candidate and
active key states, not by the status marker.

### The clear-failure case

Step 7 runs AFTER the active write has been verified, so a clear
failure cannot leave "the active token unchanged" — the active token
is already the new verified value. This is intentional and safer than
the alternative: rolling back a verified promotion would write the
old value back over a known-good new active token, which is more
dangerous than leaving a stale candidate that EQUALS the active
value. The gate reports `promotion_candidate_clear_failed` (ok=false)
and leaves the candidate intact. A retry then reads
active === candidate and returns `promotion_already_active` (ok=true),
so the operation converges. The stale candidate blocks the NEXT
rotation (the slot reads occupied) until it is cleared by a separate
approved device-side action — that is a known limitation, recorded
in §6.

## 5. The clear problem (open item)

`$persistentStore` has NO documented delete method (only read/write).
The sample's mock store provides `remove(key)`; the gate uses it when
available. When it is not available, the gate falls back to
overwriting the candidate key with the tombstone `"__PROMOTED__"` —
a 12-character value that can never validate as a candidate, so it
can never be mistaken for a real credential. The tombstone occupies
the slot (a later staging attempt reads a different value and gets
`candidate_slot_occupied`), so the production clear mechanism is an
OPEN ITEM for the real-device gate: either a separate approved
device-side action that clears the key, or an accepted tombstone
policy. The sample test proves both paths (remove-capable store and
tombstone fallback).

## 6. Open items (all need a real-device / server gate)

1. `/credential-proof` endpoint implementation on the server
   (blocker 3) and which side computes the fingerprint.
2. Production clear mechanism for the candidate key (§5).
3. Promotion approval UX: who approves, and what evidence they see
   (proof fields + status enums only, never a token value).
4. The 24-hour proof freshness window is a design choice, not a
   verified server policy — confirm against the server's token
   lifetime before use.
5. The candidate validation window (32–256 chars, printable ASCII)
   must be confirmed against the production token's actual format
   (length + character class only, never the value) before use.
6. A stale candidate equal to the active value blocks the next
   rotation until cleared by a separate approved device-side action.
7. Real-device run of the promotion gate and two-cron-cycle
   observation (blocker 4) — NOT done in this round.
8. Monitoring: a promotion attempt that fails closed must be
   visible in device-side status (the status key) without ever
   logging a token value.

## 7. Relation to earlier designs

- S1 Rev 1 (`SECURITY_GATE_PLAN.md`): rollback never re-enables the
  leaked DEV token (new backup token or fail-closed); the 48-hour
  parallel window is an upper bound; rotation acceptance via
  `/credential-proof`.
- `BOOTSTRAP_DESIGN.md` Rev 2 / 2.1: staging writes ONLY candidate
  keys; promotion is a separate approved gate.
- `DUAL_TOKEN_DESIGN.md` (blocker 3): the server side of the
  dual-token window and revocation that this gate's proof depends on.

---

## Round 4 security review addendum — signed proof, fail-closed (2026-11-20)

**This addendum supersedes the older unsigned `/credential-proof`
response and status-only success behavior described in §§2(b), 3, 4.**

The original sample accepted a caller-controlled JSON object containing
`fingerprint_matches:true` but did not authenticate that assertion or
bind it to the staged token. **That does not establish proof**, even
when `token_id` and `issued_at` are present. Do not use the original
unsigned contract to promote an active credential.

The revised *Node-only isolation reference* (`signed_promotion_proof.js`
and `promotion_gate.js`) requires all of the following before any
write of an active key:

1. A pinned, independently trusted **Ed25519 public key** (not returned
   by the proof endpoint); reject missing or wrong key.
2. Ed25519 signature over the canonical proof containing exactly
   `purpose`, `kind` (dev/localkey), `ok`,
   `fingerprint_matches`, `token_id`, `fingerprint`,
   `nonce`, `issued_at`, `expires_at`. Both sides must sign
   and verify **identical canonical bytes**.
3. The fingerprint equals SHA-256 of the **actual candidate** read
   from the local store, and the token ID is not the exposed old ID.
4. A locally generated, cryptographically unpredictable,
   **single-use expected nonce** matches the signed response;
   24-hour maximum issuance age, 5-minute future clock skew, and
   signed expiry in the future and no later than 24 hours after issue.
5. The promotion key set is exactly the intended DEV or local-key
   candidate/active/status triple; other keys fail closed.

A caller-supplied `fingerprint_matches` boolean is never a trust
anchor. An unsigned or replayed response cannot authorize a new
active credential. The mock requires an expected nonce and pinned
public key supplied separately; a real implementation must also
**durably reject a reused challenge** (not yet implemented).

A best-effort `promotion_done` status marker cannot authenticate
the active credential. If the candidate is absent, the revised
reference reports `promotion_no_candidate` even when that status
marker says done. The prior status-only idempotence shortcut is
withdrawn.

**Durability correction:** If a write returned false or read-back was
unverified, the active key **may already have changed**. The older
claim that any failure before verified read-back leaves active
unchanged is *withdrawn*. Report `promotion_commit_unknown` or
`promotion_readback_unverified`, preserve the candidate, and
reconcile durable state; never silently revert to a disclosed token.

**Device release remains blocked.** Node's `crypto` module is not
a Surge scripting API. The production verifier, trusted public key
distribution, nonce storage, real authenticated proof endpoint, and
server-to-device trust chain have not been verified on the phone.
These new files are exclusively isolated evidence, not deployable
phone/bootstrap scripts. Original pending command remains
`OUTCOME_UNKNOWN`; C3-C1 and PR#93 remain blocked.

---

## Rev 3 addendum — explicit withdrawals, verbatim (2026-11-20)

This addendum records, verbatim, the Round 4 statements that are
withdrawn by the PR #103 signed-proof fix. It follows the same
pattern as `BOOTSTRAP_DESIGN.md` Rev 2.1 §9.1 (verbatim withdrawal
with a WITHDRAWN marker). The source of every quote below is the
Round 4 version of this file (SHA
`33098ce21634e4f272ba896fed5be8dc5aaa2e956cb1fc4dc753d1ec152bd73b`)
and of `promotion_gate.js` (SHA
`c3fb617dfeed0f6b5b48eb68af5206da298242aac941aa0700af70b75d11dab0`).
GPT's PR #103 addendum above already supersedes these statements in
prose; this section is the explicit verbatim record.

### W1 — Unsigned `/credential-proof` contract (WITHDRAWN)

Round 4 §3 defined the proof as a caller-controlled JSON object and
accepted it on boolean fields alone:

> Response (server → device):
> `{ ok: true, fingerprint_matches: true, token_id: "<server token id>",
>   issued_at: <unix ms>, expires_at: <unix ms> }`.
>
> The gate accepts the proof ONLY if: `ok === true`,
> `fingerprint_matches === true`, `token_id` is a non-empty string
> and is NOT the old token's id, `issued_at` is a number within the
> freshness window (issued within the last 24 hours and not more than
> 5 minutes in the future). Any other shape fails closed.

**WITHDRAWN.** A self-asserted `fingerprint_matches: true` does not
establish proof: it authenticates neither the issuer's identity, the
signature, nor the binding to the staged candidate. The Round 4
`validProof()` implementation that returned `true` on those booleans
alone is removed (see the absorbed `promotion_gate.js`, which now
delegates to `validSignedProof()` in `signed_promotion_proof.js`).
The signed contract requires: a pinned, independently trusted
Ed25519 public key; an Ed25519 signature over the canonical proof
(`purpose`, `kind`, `ok`, `fingerprint_matches`, `token_id`,
`fingerprint`, `nonce`, `issued_at`, `expires_at`); the fingerprint
equal to SHA-256 of the ACTUAL candidate read from the local store;
the token id not equal to the old exposed id; a locally generated
single-use expected nonce matching the signed response; issuance
within 24 hours, 5-minute future skew, signed expiry in the future
and no later than 24 hours after issue. Without an independent public
key / old token id / signature / candidate, the gate fails closed.

### W2 — "Active value definitely unchanged on failure" (WITHDRAWN)

Round 4 §2(d) guaranteed:

> Write the new active value, read it back and verify it equals the
> candidate, and ONLY THEN clear the candidate key. Any failure at
> any step before the read-back verification leaves the active token
> unchanged and the candidate intact (fail-closed). See §4 for the
> exact sequence and the clear-failure case.

**WITHDRAWN.** A `$persistentStore.write()` that returns `false`
(or throws) may already have committed the new value; a read-back
that cannot be verified leaves the active state UNKNOWN, not
"unchanged". The gate now reports `promotion_commit_unknown` or
`promotion_readback_unverified`, preserves the candidate, and
requires durable-state reconciliation before any further rotation;
it never silently reverts to a disclosed token. The Round 4 §4 step 5
branches that read the active value back and distinguish
"committed despite false return" from "did not commit" remain
accurate as branches — only the blanket guarantee above is
withdrawn.

### W3 — Status-only idempotence shortcut (WITHDRAWN)

Round 4 §4 step 1 allowed a success return with no candidate:

> absent/null            -> if the status key reads
>                            "promotion_done" (the last promotion
>                            completed and nothing has been staged
>                            since): promotion_already_active, OK
>                            (no-op, idempotent). Otherwise:
>                            promotion_no_candidate, FAIL,
>                            nothing changed.

**WITHDRAWN.** A best-effort `promotion_done` status marker cannot
authenticate the active credential: the active state may have
changed after a previous promotion. The revised gate returns
`promotion_no_candidate` (fail-closed) whenever the candidate is
absent, regardless of the status marker. The absorbed
`test_promotion_gate.js` now asserts this (second promotion attempt
returns `{ ok: false, status: "promotion_no_candidate" }`).

### Findings carried forward

(a) `$persistentStore` has NO documented delete method (already
known from Round 4, §5 of this document): the sample clears via
`remove()` when available and otherwise writes the tombstone
`"__PROMOTED__"`. The production clear mechanism remains an OPEN
ITEM for the real-device gate.

(b) The no-candidate success path based on previous status is
removed (see W3 above). Any caller that relied on
`promotion_already_active` as a no-op after a completed promotion
must now treat an absent candidate as `promotion_no_candidate`
and reconcile state from the active key itself.
