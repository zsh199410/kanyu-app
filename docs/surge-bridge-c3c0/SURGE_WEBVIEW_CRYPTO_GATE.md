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
5. `atob` presence **and correct RFC 4648 base64 decoding**, which PR #105's
   signature verifier requires. Without this check, a previous `crypto_ready`
   result was insufficient to establish that all verifier primitives exist.

The only data it may write is a **non-secret status enumeration** at
`sgbridge_webcrypto_probe_status`: `crypto_ready`,
`no_webcrypto`, `no_text_encoder`, `sha256_failed`,
`ed25519_unavailable`, `signature_failed`, `random_unavailable`,
`base64_unavailable`, `base64_failed`, `insecure_context`, `probe_error`. No network calls, notifications, policy mutation,
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

## Round 6 F1 resolved (2026-11-20)

Muse's review F1 noted the missing `atob` prerequisite. This revision
adds fail-closed states for missing/broken `atob` and two direct-VM negative
tests. The accepted `crypto_ready` status now covers base64 decoding as
well as Ed25519/SHA-256/randomness. It remains an isolated test, not a real
Surge device result or production credential-promotion authorization.

## 2026-11-20 — Actual iPhone editor WebView secure-context observation

The owner manually ran the unmodified SHA-pinned probe and a separate
read-only environment diagnostic with **Generic** context and **WebView**
engine on iPhone Surge. The non-secret values visible in the supplied
device screenshot are:

```text
secure=false
crypto=yes
subtle=no
digest=missing
trigger=editor
```

The original probe panel displayed `no_webcrypto`. In this precise
**editor-triggered runtime**, `isSecureContext=false` explains the missing
`crypto.subtle`; it does **not** establish that iOS hardware or all other
Surge trigger contexts cannot support Ed25519. The probe now explicitly
reports `insecure_context` when `isSecureContext === false`, even when
a synthetic environment exposes `crypto.subtle`; the ordinary
`no_webcrypto` diagnostic remains for other absence cases. Two regression
cases model the observed device inputs. The status panel renders this
enumeration in alert style without claiming release approval.

**Gate B remains BLOCKED**: real signed-proof verification and device-side
single-use nonce durability remain unproven. Existing installed module URLs
are immutable/pinned: a new module release is needed before this diagnostic
change is shown on the actual phone. No production mobile action or
credential handling is authorized by this code-only PR.
