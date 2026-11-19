# C3-C1 Surge WebView signed-proof verifier (offline reference)

**Status:** Review-only library, **NOT an installable or standalone Surge
script**, and not authorization for phone credential promotion.

## Purpose and progress

The standalone probe in Draft PR #104 checks whether the actual Surge
iOS `engine=webview` can import an Ed25519 public key, verify a known
signature, reject a mutated signature, digest SHA-256 and generate a
random nonce. The official Surge manual supports WebAPI for WebView
but actual device Ed25519 support remains unverified.

This Draft adds `surge_webview_signed_proof.js`: a library written with
ordinary Web Crypto APIs, **no Node `require`**, no private keys, no
network, no active/candidate key mutation and no Surge device-control
calls. It is a standalone verification *function*, not a runnable
generic script, and MUST NOT be registered on its own.

## Signed proof contract

Signed data has exactly the same canonical JSON field order as GPT
PR #103's Node Ed25519 reference:

`purpose`, `kind`, `ok`, `fingerprint_matches`, `token_id`,
`fingerprint`, `nonce`, `issued_at`, `expires_at`.

The browser-compatible code validates all of the following:
- `purpose="issue73/credential-promotion/v1"` and `kind` is exactly
  `dev` or `localkey` (domain separation).
- A printable ASCII candidate of length 32–256 not matching a
  `<...>` placeholder; no CR/LF.
- The token ID differs from the trusted **old exposed** token ID.
- An **independently issued expected nonce** exactly equals the
  signed nonce (length >=16) and matches the current attempt.
- Signed issuance is no more than 24 hours old, not more than 5 minutes
  in the future; expiry is strictly later than current time and no
  later than 24 hours after issuance.
- Candidate SHA-256, computed locally by Web Crypto, matches the
  signed token fingerprint.
- An Ed25519 signature over the exact canonical JSON verifies against
  an **independently pinned** 32-byte public key.
- Every missing, malformed or unsupported prerequisite returns
  `false` (fail-closed), never writes a credential or logs its value.

The pinned public key and expected nonce are **NOT** accepted from
the untrusted proof response. A trusted caller must supply them; this
reference intentionally does not implement a trust-root distribution
mechanism, nonce allocation/storage or server request.

## Validation

`test_surge_webview_signed_proof.js` uses a temporary Ed25519 private
key created in CI, signs canonical JSON with Node crypto, then runs
the **actual WebView-compatible verifier code** inside a Node VM with
Web Crypto. It tests positive and negative cases and compares canonical
bytes with PR #103. The test private key exists only for the test
process; there is no production private key in GitHub.

**Known limitation, explicitly tested:** if the caller mistakenly
reuses the same `expectedNonce`, the stateless verifier accepts the
same correctly signed proof again. This is why strict **durable
single-use nonce consumption** remains a separate mandatory server /
device state-machine gate. Matching a nonce is not replay prevention
on its own.

Node VM passing does NOT establish:
- Actual device WebView Ed25519 availability or same behavior.
- Secure pinned public-key distribution or inability to replace the
  remote script itself.
- Origin authentication, single-use nonce storage, candidate promotion
  durability, service-side token table or token revocation.
- Privacy of an actual production token in Surge backups/logs.

## Next actual release gate

1. Validate PR #104's source-free capability probe on real device,
   returning only non-secret status and exact script SHA.
2. Audit a bundled `engine=webview` generic credential-promotion
   script with **independently pinned trust root**, secure nonce
   lifecycle, approved staged candidate and replay state.
3. Integrate real server signing and atomic durable token table, with
   staged and backed-up rollback that cannot reactivate the exposed
   old token.
4. Obtain explicit production release approval, validate two cron
   cycles and old pending fence, only then proceed to controlled
   revocation.

Until then `C3-C1=NO-GO`, `PR93=BLOCKED`,
`BOOTSTRAP_SECURITY_GATE=BLOCKED` and `AUTO_DELETE=OFF`.
21 pinned nodes, 5 timers and the old OUTCOME_UNKNOWN command are untouched.

Official Surge sources:
- https://manual.nssurge.com/scripting/overview.html
- https://manual.nssurge.com/scripting/api.html
