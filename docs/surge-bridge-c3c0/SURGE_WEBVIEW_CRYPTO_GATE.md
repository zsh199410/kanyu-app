# C3-C1 Surge iOS WebView cryptography capability gate

**Status: review-only.** This is an isolated **capability probe**, not a credential
promotion implementation, production Bridge, server-token change or phone test.
The only public values in the script are RFC 8032 verification test vectors and
the SHA-256 digest of an empty string. They are not credentials.

## Why this exists

The Round-4 promotion sample accepted an unverified boolean
`fingerprint_matches:true`; GPT Draft PR #103 requires an authenticated
Ed25519 signature bound to the actual candidate and a one-time challenge.
Its JavaScript reference uses Node's `crypto`, which **cannot be assumed to
exist in Surge's JavaScript runtime**.

The official Surge manuals document that:
- `engine=webview` enables **standard WebAPI** including `crypto` and
  `TextDecoder`; explicitly configure the engine when WebAPI is required.
- Manual generic scripts may run from Surge's script editor or iOS Shortcuts.
- `$persistentStore` is a simple shared key-value store, **not** an
  independently certified secure keystore.

Official sources:
- https://manual.nssurge.com/scripting/overview.html
- https://manual.nssurge.com/scripting/api.html
- https://manual.nssurge.com/scripting/generic.html

Those statements do NOT establish **Ed25519 support in the exact iOS/WebView
build**, or guarantee secure storage/Shortcuts-input privacy.

## Capability probe

`surge_webview_crypto_probe.template.js` is intended for a **separately approved**
manual test only. Use an ordinary generic script with **`engine=webview`** and
`timeout=12`. Neither installing a script nor invoking it on the real device
is authorized by this Draft PR.

The source requires no arguments and contains no secrets. It checks:
1. Web Crypto `crypto.subtle`, SHA-256 using the public SHA256(empty) vector.
2. `TextEncoder` basic UTF-8 behavior.
3. RFC 8032 Ed25519 public-key import, known-good signature verification,
   and deliberate corrupted-signature rejection.
4. `crypto.getRandomValues` ability to fill a 32-byte nonce buffer.

The only data it may write is a **non-secret status enumeration** at
`sgbridge_webcrypto_probe_status`: `crypto_ready`,
`no_webcrypto`, `no_text_encoder`, `sha256_failed`,
`ed25519_unavailable`, `signature_failed`, `random_unavailable`,
`probe_error`. No network calls, notifications, policy mutation,
Bridge ledger/state access, credential read or write. Unexpected cron/HTTP
API/panel triggers have **zero state writes**, and it calls `$done` once.
It cannot prove whether Surge internally logs raw script evaluations;
there are **no secret inputs** to this probe, so that risk does not
expose production secrets here.

`test_surge_webview_crypto_probe.js` executes this exact source inside
a Node VM with synthetic/mocked WebAPI variants. It asserts positive
real-Node WebCrypto verification, missing/broken primitives, corrupt
signature fail-closed, exactly-once completion, non-secret output and
no writes to active/candidate credentials, old command, pins or timers.
Passing CI proves **only simulated runtime behavior**, not iPhone runtime.

## Required real-device evidence before proceeding

The responsible device operator should return only non-secret metadata:
- Whether the test was actually run, with exact commit SHA and
  `engine=webview` config, Surge build and iOS version.
- One of the **non-secret status enums** and whether `$done` completed.
- Whether no unexpected network/script log/credential/policy changes occurred.
- No actual DEV token, local key, Shortcuts run-input, public/private keys,
  hostnames, IPs, device identifiers or raw logs in public GitHub.

If `crypto_ready` is actually observed, implement a **separate true-device
signed-proof verifier** using supported Web Crypto primitives. Do not promote
a token from the capability probe. If not supported, stop and choose an
independently audited alternative; never weaken signature verification or
fall back to accepting a self-asserted boolean.

## Still blocking deployment

- Trust anchor pinned outside the untrusted HTTP response; signed canonical
  fields identical on server and device; verify candidate-binding signature.
- Single-use nonce created by device and durably rejected on replay; the
  reference PR #103 only checks *equality* with an expected nonce, which
  is **not enough** to prevent reuse across runs.
- Device-side staging privacy audit, bounded dual-token rollout, initial
  provisioning/rotation, and server-side durable token table.
- Old pending command `OUTCOME_UNKNOWN` must remain fenced with no
  command replacement, action replay, result posting or old-token rollback.
- Separate device release and production rollback evidence/approval.

Status remains `C3-C1=NO-GO`, `PR93=BLOCKED`, `AUTO_DELETE=OFF`.
The 21 protected pins and five existing timers are unchanged.
