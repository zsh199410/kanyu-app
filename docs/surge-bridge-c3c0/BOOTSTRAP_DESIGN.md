# C3-C0 S1 — Secure Credential Bootstrap Design (Rev 2, Round 3 continued)

## Status

**Rev 2 supersedes Rev 1.** The Rev 1 approach (paste the token into a
one-time script's source, run once, delete the script) is **DEPRECATED**.
It is wrong on the security boundary, and this revision corrects it.
Nothing in Rev 2 claims a device-side verification that has not happened.

- Rev 1: `BOOTSTRAP_DESIGN.md` as committed to PR #97 head `4ef98d4`
  (Round 3), plus `s1/bootstrap.js` + `s1/bootstrap_test.js`.
- Rev 2: this document. Recommended path is now the PR #101 Shortcuts
  candidate bootstrap
  (`bootstrap_candidate_shortcuts.template.js`, head `2e6c44d`).
- Gates unchanged: `C3-C1=NO-GO`, `PR93_CUTOVER=BLOCKED`,
  `CREDENTIAL_DISTRIBUTION_GATE=BLOCKED`, `AUTO_DELETE=OFF`.
  Old single-slot command `1795063030` stays `OUTCOME_UNKNOWN`, fenced.
  No phone action is authorized by this design.

## 0. What was wrong in Rev 1 (the correction)

Rev 1's mechanism was: the owner pastes the new DEV token and the local
key into two constants **inside the script source**, runs the script
once, reads `bootstrap_ok`, then **deletes the script**, treating
deletion as the credential having been cleared.

That is **not a security mechanism**, for three reasons, all grounded in
the Surge manual (GPT receipt 7012275778):

1. **The token sits in the script source.** Surge caches script source
   and retains script-run logs. The official manual gives **no
   guarantee** that deleting a script wipes its cached source or its
   logs. A token pasted into source can therefore survive deletion in a
   cache or a log.
2. **`$persistentStore` keys are cross-script accessible.** The manual
   confirms explicit keys can be accessed by different scripts. Writing
   the credential into the store does not hide it from any other script
   that knows the key name.
3. **Deletion is not a wipe.** Deleting a script does not wipe
   `$persistentStore` and does not wipe logs. "Delete the script" was a
   checklist step, not a guarantee, and Rev 1 presented it as the
   cleanup. That framing was wrong.

Consequences:

- `s1/bootstrap.js` is **DEPRECATED**. It is kept in the tree only as a
  record of the superseded approach, with a `DEPRECATED` header comment.
  Do not use it to bootstrap a credential.
- `s1/bootstrap_test.js` (7/7 PASS) is the isolated verification of the
  **superseded approach's logic only**. It still passes, and it is kept
  as a record. It is not an endorsement of the approach.
- Rev 1's §1.3 already noted that a script cannot delete itself and
  that `$persistentStore` is not a secure enclave. Those caveats were
  correct but insufficient: the design still treated source-pasting +
  manual deletion as the mechanism. Rev 2 removes the mechanism, not
  just the caveats.

## 1. The recommended path: PR #101 Shortcuts candidate bootstrap

### 1.1 What it is

`bootstrap_candidate_shortcuts.template.js` (PR #101, 76 lines, SHA
`6bfa8838…ca7591`, byte-identical to PR #101 head `2e6c44d`) is a
manually invoked Surge **generic script** driven by an ephemeral
Shortcuts **"Ask for Input" parameter supplied at RUN time**
(`$trigger="intent"`, `$intent.parameter`). The parameter is **not**
saved in the Shortcut's configuration and **never appears in the
script source**.

The candidate is staged under a **different key** from the active
token:

| Key | Purpose |
|---|---|
| `sgbridge_cred_dev_candidate` | Staging slot for the new DEV token. The active bridge (v2.2) does **not** read it. |
| `sgbridge_cred_dev` | Active DEV token, read by v2.2 at runtime. **Untouched by this script.** |
| `sgbridge_cred_bootstrap_status` | Non-secret status enum only (see §1.3). |

### 1.2 What the template does

- **Trigger gate:** only `$trigger === "intent"` with a non-null
  `$intent` object proceeds. Editor, HTTP API, cron, panel and unknown
  launches are rejected with `unsupported_trigger` and produce **zero
  state changes** (not even the status marker, because `triggered` is
  only set after the check passes).
- **Validation:** the candidate must be a string, 32–256 chars,
  printable ASCII only (`[\x21-\x7E]`). Anything else →
  `invalid_parameter`, nothing staged.
- **Occupied slot:** an existing candidate different from the new one →
  `candidate_slot_occupied`, no overwrite. The same candidate again →
  `candidate_already_staged` (idempotent), no re-write.
- **Commit:** `$persistentStore.write(candidate, STAGING_KEY)` must
  return strictly `true`, else `candidate_commit_unknown` — **no
  auto-retry**. Read-back must equal the candidate, else
  `candidate_readback_unverified`.
- **Errors:** any exception → `bootstrap_error`. The `finally` block
  writes only the status marker (if triggered) and always calls
  `$done()`.
- **No network, no notification, no shell, no log of the parameter.**
  The source contains no `$httpClient`, no `$httpAPI`, no
  `console.log`, no `$notification`, and no self-delete claim.

### 1.3 What is observable

Only a fixed status enum, written to
`sgbridge_cred_bootstrap_status`: `not_started`,
`unsupported_trigger`, `invalid_parameter`, `candidate_slot_occupied`,
`candidate_already_staged`, `candidate_commit_unknown`,
`candidate_readback_unverified`, `candidate_staged`,
`bootstrap_error`. No token, no digest, no key, no path is ever
logged or stored.

### 1.4 What the template deliberately does NOT do

- It does **not** touch the active token `sgbridge_cred_dev`, the
  ledger, the legacy checkpoint `last_id`, the old single-slot command,
  any timer, or any policy.
- It does **not** promote the candidate to active. Promotion
  (`sgbridge_cred_dev_candidate` → `sgbridge_cred_dev`) is a
  **separate approved gate** (see §4). It must not happen by changing a
  profile or by changing the server token table ahead of approval.
- It does **not** revoke the old exposed token. Revocation is gate 2
  (see §5).
- It does **not** claim script self-deletion or secure-enclave storage.
  On-device deletion of the Shortcut/script and any history must be
  separately checked; deleting a script does not wipe storage.

## 2. How the token reaches the owner securely

Unchanged from Rev 1 (this part was not the error):

- The new DEV token is generated **server-side** (random string) and
  stored in a **root-only file** (mode 600) on the server. It is never
  placed in a public URL, a chat message, an email, or a GitHub file.
- The owner reads it via **SSH to the server** (from their own
  computer), reading the root-only file. The owner also records the
  token's SHA-256 fingerprint (first 16 hex chars) from the server for
  the audit record.
- The owner then types/pastes the token **into the Shortcuts "Ask for
  Input" prompt at run time** — not into any script source, not into
  any saved Shortcut configuration.
- The template itself makes **zero network requests**.

## 3. Cross-review verdict (PR #101, Round 3 continued)

Full diff read at `/tmp/pr101.diff` (256 lines). Files absorbed
byte-identical to PR #101 head `2e6c44d` (verified by reconstructing
from the diff and comparing SHA-256 against the GitHub raw files).

| Check | Verdict |
|---|---|
| Trigger rejection covers all non-intent paths | **PASS.** Editor / HTTP API / cron (null) / panel / unknown all rejected before any write; `triggered` is set only after the check, so rejected runs produce zero state changes. Minor coverage gap: no dedicated test for `$intent === null` / `undefined` with `$trigger === "intent"` (code handles it → `unsupported_trigger`, untested). |
| Candidate validation adequate (length + printable ASCII) | **PASS, with an open item.** 32–256 chars, printable ASCII only; rejects empty / short / CR-LF / non-string / non-ASCII. Open: the production token's actual length and character class must be confirmed against this window **before** use (length + class only, never the value). If the real token were < 32 chars it would be rejected. The template itself notes the exact production format is a separate security requirement. |
| Occupied-slot logic prevents silent overwrite, allows idempotent re-stage | **PASS.** Different existing candidate → `candidate_slot_occupied`, no write. Same candidate → `candidate_already_staged`, no re-write. Non-string or empty existing value → occupied (fail-closed). |
| Write-false / readback-mismatch fail-closed, no auto-retry | **PASS.** Write `!== true` → `candidate_commit_unknown`, no retry. Read-back mismatch → `candidate_readback_unverified`. Write-reaches-disk-then-false → still `unknown` (test confirms the value IS on disk but the status does not claim success). The resulting ambiguity (may or may not be on disk) must be resolved by a separate read-back verification gate. |
| Any path that logs or leaks the parameter, a digest, or a local key | **None found in the template.** No network, no console, no notification, no digest. Status is a fixed enum. Test asserts no token in status / logs / network / write records on all trigger paths. Mock limitation (not a code gap): the test mock records writes as `{key, valueKind}`, so it cannot detect whether the **real Surge runtime** logs `$persistentStore.write` values. That is a device-side open item (§6). |
| Template does not touch active token, ledger, last_id, old slot, timers, policies | **PASS.** Only reads/writes `sgbridge_cred_dev_candidate` and writes the status key. Minor observation: `ACTIVE_KEY` is declared but never referenced in the template (dead constant — documents the active key name). Not a bug. |
| CI workflow | **PASS.** Syntax checks + the 13-case test, `contents: read`, 5-minute timeout. |

Additional notes:

- The template does **not** reject `<...>` placeholder values (unlike
  v2.2's `readCredential`). A `<PASTE...>` value of 32+ printable chars
  would stage. Blast radius is bounded: the bridge would refuse it
  (`credential_missing` → fail-closed) and the candidate slot would be
  occupied until cleared by a separate gate. Not a FAIL, but the
  promotion gate must verify the candidate against the server-issued
  fingerprint before promoting.
- The template cannot distinguish a **manual** Shortcuts intent
  invocation from an **automated** Shortcuts automation invoking the
  same intent. The Shortcut must be invoked manually only; that is a
  device-side governance item, not a code defect.
- A stale/wrong candidate has **no clear path in this script** (by
  design — it prevents silent overwrite). Clearing a stale candidate
  needs a separate approved device-side action; that clearing
  mechanism is itself a gate that needs design.
- The **local key** (`sgbridge_cred_localkey`) has **no approved
  bootstrap path** in PR #101: the template stages only the DEV token.
  The old paste-into-source path for the local key is deprecated along
  with `s1/bootstrap.js`. A Shortcuts candidate path for the local key
  (or an alternative) still needs design. v2.2 can run without the
  local key for native `$httpAPI` calls; the key is only needed for the
  direct-HTTP fallback and MCP, so this is a lower-priority open item,
  not a blocker for the DEV-token path.

## 4. Promotion (separate gate — NOT designed here)

Moving `sgbridge_cred_dev_candidate` → `sgbridge_cred_dev` requires
its own approval and design. It must include:

1. Verification that the staged candidate matches the server-issued
   fingerprint (computed where the token was generated) **before**
   promotion — the promotion step must not trust the candidate on its
   own.
2. A defined promotion action (separate script / manual step) with an
   audit record of what was promoted and when.
3. No activation by changing a profile or by changing the server token
   table ahead of approval.
4. A rollback plan that does **not** re-enable the old exposed token
   (see §5).

## 5. Dual-credential window / revocation (gate 2 — referenced, not designed here)

The S1 Rev 1 plan (`SECURITY_GATE_PLAN.md`) already specifies: the
leaked DEV token is never re-enabled as a rollback credential; rollback
uses a pre-issued new backup token or fail-closed with separate
approval; the 48h dual-token parallel window is an upper bound, not a
target. The **server-side token-table change** (accepting both tokens
during the window, then revoking the old one, with separate rollback
evidence) still needs its own design and review. It is NOT part of this
bootstrap design. **On loss of contact, the old exposed token must NOT
be routinely revived.**

## 6. The `$persistentStore` caveat (explicit) and open device-side items

`$persistentStore` is a **simple persistent key-value API** (Surge
manual). It is **not** a proven secure hardware keystore / secure
enclave. The PR #101 approach removes the credential from the
**publicly distributed script** and from **script source** — that is
the vulnerability being fixed. It does **not** claim the credential is
stored in a secure enclave.

Open items that still need **real-device gates** (none verified in
this round):

1. **Shortcuts input history:** whether iOS Shortcuts retains the
   typed token in run history, suggestions, or recents. **Unverified.**
2. **iOS / iCloud backup:** whether `$persistentStore` contents (and
   any Shortcuts input) are included in device or iCloud backups, and
   whether a backup restore could expose the token. **Unverified.**
3. **Script cache leakage:** whether Surge caches the template source
   or the Shortcuts invocation in a way that retains the parameter.
   The template source contains no token, but the runtime behavior
   needs a device-side check. **Unverified.**
4. **Device-side log check:** whether the real Surge runtime logs
   `$persistentStore.write` values (the isolated test mock cannot
   detect this). **Unverified.**
5. **Other scripts' permissions:** `$persistentStore` keys are
   cross-script accessible; which other scripts on the device could
   read `sgbridge_cred_dev_candidate` (or, after promotion,
   `sgbridge_cred_dev`) has not been audited. **Unverified.**
6. **Candidate key visibility:** same as (5), for the staging key
   specifically — any script that knows the key name can read it.
   **Unverified.**
7. **Production token format vs the 32–256 printable-ASCII window:**
   confirm length + character class before use (§3). **Unverified.**
8. **Local-key bootstrap path:** no approved design (see §3). **Open.**
9. **Promotion gate:** no design yet (see §4). **Open.**
10. **Gate 2 server-side token-table change:** needs separate design +
    review (see §5). **Open.**
11. **Real-device candidate staging run:** not done. **Open (C3-C1).**
12. **Real-device loading of the new SHA + two cron cycles observing
    the old pending fenced:** not done. **Open (C3-C1).**

## 7. Isolated verification

### 7.1 PR #101 candidate bootstrap (recommended path)

`test_bootstrap_candidate_shortcuts.js` (13 tests, synthetic tokens
only, VM mock, no network):

| Test | Result |
|---|---|
| source does not embed raw token, network API calls or self-delete | PASS |
| editor trigger: zero state changes | PASS |
| HTTP API trigger: zero state changes | PASS |
| cron trigger: zero state changes | PASS |
| invalid / empty candidate never staged | PASS |
| valid candidate stages without modifying active token | PASS |
| existing candidate with same value is idempotent | PASS |
| different candidate cannot be silently overwritten | PASS |
| write returns false: record unknown, no extra secret writes | PASS |
| write reaches disk then returns false: still unknown, no auto retry | PASS |
| readback mismatch fails closed | PASS |
| store read exception fails closed | PASS |
| no secret in status, logs, or network on all trigger paths | PASS |

**Result: 13/13 PASS, 0 FAIL.** Run:
`node test_bootstrap_candidate_shortcuts.js`.
Record: `test_bootstrap_candidate_out.json`.
GPT's CI runs 44545672281 / 44545672526 / 44545672479 were all
`completed/success` on PR #101 head `2e6c44d`. Note: GPT's receipt
records that the first CI run had a test-injection bug (`undefined`
defaulting to `"intent"`, causing a false failure); it was fixed and
re-run green. A failed round does not count as a pass.

### 7.2 Deprecated approach (record only)

`s1/bootstrap_test.js` (7 tests, synthetic tokens only): **7/7 PASS**,
still passes after the `DEPRECATED` header was added (comment only, no
behavior change). Kept as a record of the superseded approach's logic.
It does not endorse the approach.

## 8. Files

- `bootstrap_candidate_shortcuts.template.js` — PR #101 template
  (recommended path; SHA `6bfa8838…ca7591`).
- `test_bootstrap_candidate_shortcuts.js` — 13 adversarial tests
  (SHA `5bde1810…8931b56`).
- `test_bootstrap_candidate_out.json` — 13/13 record.
- `ci/issue73-s1-shortcuts-bootstrap.yml` — CI workflow
  (SHA `950e9602…499331`).
- `s1/bootstrap.js` — **DEPRECATED**, kept as a record only.
- `s1/bootstrap_test.js` + `s1/bootstrap_out.json` — record of the
  superseded approach's isolated verification (7/7).
- This file (`BOOTSTRAP_DESIGN.md`, Rev 2).

---

## 9. Rev 2.1 addendum — GPT P0-B1/B2/B3 (review 7012623369, 2026-11-19)

Round 3C. GPT independently reviewed the committed Rev 1/Rev 2
artifacts on PR #97 head `4ef98d4` and raised three P0 bootstrap
findings. This addendum records each finding and its fix. **Rev 2's
body above is not rewritten**; this section appends the corrections.

### 9.1 P0-B1 — explicit withdrawal of the two Rev 1 statements

Rev 2 §0 deprecated the Rev 1 mechanism but did not quote the two
statements it relied on. They are withdrawn here, explicitly:

**WITHDRAWN (not established):**

1. *"The token is NEVER sent over the network, NEVER logged, and
   NEVER written to any file except $persistentStore."*
2. *"token only goes into $persistentStore."*

Both claims came from `s1/bootstrap.js` (SAFETY comment) and Rev 1's
design text. They are **not established**, because the token was
pasted into the script source, and the manual gives no guarantee that
deleting a script wipes its cached source, its logs, editor autosave,
sync copies, backups, screenshots, or Shortcuts inputs. The text of
both statements remains inside `s1/bootstrap.js` only as a record of
the superseded claim — the file is DEPRECATED and must not be used.
The 7 tests in `s1/bootstrap_test.js` only scan the *placeholder
template*, not a real token-populated source or device persistence;
that limitation is acknowledged here and was already recorded in
Rev 2 §0.

**Defect demonstrated:** `test_bootstrap_candidate_regressions.js`
D1/D2 (Section D, labelled DOCUMENTED DEFECT DEMONSTRATION) run the
deprecated script's real logic in a VM mock and prove the defect is
real — see §9.2. The tests pass when the defective behaviour is
observed; they are not gates for the new approach.

### 9.2 P0-B2 — partial updates / completion marker failure

GPT's finding: the deprecated bootstrap writes `sgbridge_cred_dev`
then `sgbridge_cred_localkey` separately; if the first succeeds and
the second fails, the active keys are left partially changed even
though the UI reports failure; it sets `sgbridge_bootstrap_done` but
ignores a `false` return and can emit `bootstrap_ok` without a durable
done marker. Existing test B3 only simulated ALL writes returning
false; it missed partial success.

**Demonstrated (deprecated script):**

- D1: DEV write `true` + local-key write `false` → the active DEV key
  IS changed (new token), the local key keeps its old value, the
  owner is told `bootstrap_failed`, and no done flag is set. A partial
  active-key update despite a failure report.
- D2: both credential writes `true` + done-marker write `false` →
  `bootstrap_ok` is still emitted, but `sgbridge_bootstrap_done` is
  absent. Success reported without a durable completion marker.

**Fixed in the new approach (no two-key atomic write BY DESIGN):**
staging never touches the active keys, so a partial update of ACTIVE
keys is impossible. The regressions in
`test_bootstrap_candidate_regressions.js` prove it:

- (a) R1: DEV staging ok + local-key staging fails, and vice versa —
  **zero writes to either active key** in both directions.
- (b) R2: local-key candidate write committed then returns `false` →
  `candidate_commit_unknown`, exactly 1 write, value on disk, no
  auto-retry.
- (c) R3: both candidates staged + both status-marker writes `false`
  → no candidate rewrite (1 write each), candidates on disk, statuses
  read as absent (not `candidate_staged`), active keys unchanged.
- (d) R4: preloaded active keys (DEV + local key) unchanged after both
  stagings succeed.
- (e) R5/L5: second invocation after an ambiguous commit fails closed
  (`candidate_slot_occupied`), original candidate preserved, zero
  candidate writes on the retry (DEV and local-key variants).
- (f) R6: no token in logs, source, or status on all paths, both
  templates.

Never assume an exception proves storage did not commit: every
write-false case is tested in both flavours (not persisted, and
persisted-then-false). A write that returns `false` but committed is
recorded as `candidate_commit_unknown` and must be resolved by a
separate read-back verification gate, not by an automatic retry.

### 9.3 P0-B3 — premature active-key mutation (staging vs promotion)

GPT's finding: the deprecated bootstrap writes straight to
`sgbridge_cred_dev` / `sgbridge_cred_localkey` even though the server
has not completed dual-token support and safe rotation, bypassing the
candidate→proof→promotion gate.

**Stated explicitly (this addendum, supplementing Rev 2 §1.4/§4/§5):**

- Staging writes **ONLY candidate keys**
  (`sgbridge_cred_dev_candidate`,
  `sgbridge_cred_localkey_candidate`) plus a non-secret status marker.
  It never writes an active key.
- Promotion (candidate → active) is a **separate approved gate** with
  its own design and approval. It must not happen by changing a
  profile or by changing the server token table ahead of approval.
- **No phone provisioning, no public script change, no server token
  enablement, and no credential revocation until explicit approval.**
  The old exposed token must not be routinely revived.

### 9.4 Local-key candidate template (new)

`bootstrap_candidate_localkey.template.js` stages the local key under
`sgbridge_cred_localkey_candidate` using the **same** intent-parameter
mechanism as the PR #101 DEV template (same trigger rejection, same
32–256 printable-ASCII validation, same occupied/idempotent logic,
strict write + read-back, status marker
`sgbridge_cred_localkey_bootstrap_status`). The two candidate stagings
are independent single-key operations; there is no two-key atomic
write, and that is BY DESIGN (active keys are never touched during
staging). Tests L1–L5 in `test_bootstrap_candidate_regressions.js`
cover: valid staging without modifying the active local key;
occupied/idempotent; status-marker failure; write-false without
persisting; ambiguous commit then a different candidate. The local key
is only needed for the direct-HTTP fallback and MCP; v2.2 can run
without it for native `$httpAPI` calls.

### 9.5 CI coverage (evidence gap closed in the workflow)

GPT's finding: the bootstrap 7/7 was Muse's isolated record only —
neither PR #97 workflow executed `s1/bootstrap_test.js`. The S1
adapter workflow (`.github/workflows/issue73-c3c0-s1-adapter.yml`) now
runs **all** bootstrap suites in CI with a nonzero-failure gate (node
exits 1 on an uncaught assertion failure; the regressions file sets
`process.exitCode = 1` when its SUMMARY reports FAIL > 0; the gate
was verified by a forced-failure negative control that exited 1):
`s1/bootstrap_test.js` (7/7, deprecated-approach record),
`test_bootstrap_candidate_shortcuts.js` (13/13),
`test_bootstrap_candidate_regressions.js` (14/14). The workflow's
`docs/surge-bridge-c3c0/**` path filter already covers every one of
these files, so no filter change was needed. **Note:** the 7/7
bootstrap result is isolated-only until this updated workflow runs on
the new PR #97 head; it must not be cited as CI-backed before then.

### 9.6 Gates (unchanged by Round 3C)

`CREDENTIAL_DISTRIBUTION_GATE=BLOCKED`; `C3-C1=NO-GO`;
`PR93_CUTOVER=BLOCKED`; `AUTO_DELETE=OFF`; old command 1795063030
stays `OUTCOME_UNKNOWN`, permanently fenced. The candidate templates
stage only; they do not promote, do not revoke, and do not authorize
any phone action. Real-device gates (Shortcuts input history, iOS
backup, script cache leakage, device-side log check, other scripts'
permissions, candidate key visibility, token format window,
promotion gate, gate 2 server change, real-device staging run,
real-device loading + two cron cycles) remain open — see Rev 2 §6.
