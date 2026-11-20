# C3-C1 Device Evidence Alignment — Desensitized Record Template (Round 5)

## Status: OPEN

`DEVICE_EVIDENCE_CORRELATION=OPEN` (GPT comment 7024105041,
2026-11-20 06:34 CST). The owner reported "真机验收通过" in chat;
that is recorded as `DEVICE_ACCEPTANCE=USER_REPORTED` only. GitHub
Issue #73 has no corresponding desensitized device evidence record.
**This file is a checklist and template. Every field below is
UNVERIFIED. No device evidence is claimed here, and no value below
may be filled in from memory, inference, or an unverified chat
message — only from a real device observation, recorded as a
boolean or a desensitized SHA.**

## Rules for filling this record

1. Never upload real tokens, API keys, phone source scripts, private
   URIs/IPs, or privacy-containing logs (Surge logs, Shortcuts
   history, screenshots with identifiers). Only boolean matrices and
   desensitized SHAs.
2. A field becomes VERIFIED only when the owner (or an approved
   device-side check) supplies the observation and it is recorded
   here with its source and time. Until then it stays UNVERIFIED.
3. "The phone works" is not evidence. Each row must be answered
   separately; a single blanket pass does not close this record.
4. If any row is answered NO, the record stays OPEN and the
   corresponding gate stays NO-GO. Do not average the rows.

## Evidence matrix (all UNVERIFIED)

| # | Field | Expected value / check | Status |
|---|---|---|---|
| 1 | Test time (device acceptance run) | Date + time (CST) the acceptance test ran on the real phone | UNVERIFIED |
| 2 | Running source script SHA | SHA-256 of the bridge script actually running on the phone at test time (desensitized SHA only, never the script itself) | UNVERIFIED |
| 3 | Surge version | Surge TF / App Store version on the phone at test time | UNVERIFIED |
| 4 | iOS version | iOS version on the phone at test time | UNVERIFIED |
| 5 | Cron cycle 1 — poll observed | Phone polled the bridge at least once in a 10-minute cron cycle and returned a 200 with no unexpected dispatch | UNVERIFIED |
| 6 | Cron cycle 2 — poll observed | A second, separate 10-minute cron cycle also polled cleanly (two consecutive cycles) | UNVERIFIED |
| 7 | Old-ID fence — command untouched | Old pending command 1795063030 still present, still `OUTCOME_UNKNOWN`, never replayed / overwritten / cleared during the test | UNVERIFIED |
| 8 | Old-ID fence — result id unchanged | `result` id 1795055213880 unchanged after both cron cycles | UNVERIFIED |
| 9 | Pins intact | All 21 pinned nodes still present in the pool after the test | UNVERIFIED |
| 10 | Timers intact | All 5 production timers still active after the test | UNVERIFIED |
| 11 | Logs privacy check | Device-side logs reviewed: no token, API key, or private URI present in any retained log | UNVERIFIED |
| 12 | Shortcuts history privacy check | Shortcuts input history reviewed: no token or key value retained in history | UNVERIFIED |
| 13 | Cross-script access check | No other script on the device reads the candidate/active credential keys | UNVERIFIED |
| 14 | Backup exposure check | No credential value present in an iOS/iCloud backup or script cache copy | UNVERIFIED |
| 15 | Acceptance scope | Which system the acceptance covered (bridge / node pool / other) and which steps were actually run | UNVERIFIED |

## What closes this record

All 15 rows VERIFIED with source + time, OR an explicit owner/GPT
decision that a specific row is N/A with a recorded reason. Until
then: `DEVICE_EVIDENCE_CORRELATION=OPEN`,
`RELEASE_EVIDENCE_NOT_YET_COMPLETE`, `C3-C1=NO-GO`,
`PR93_CUTOVER=BLOCKED`.

## What this record is NOT

- It is not a claim that the device acceptance passed.
- It is not a substitute for the signed-proof trust chain, the
  persistent server token table, the controlled dual-token window,
  or the independent production rollback drill (all still pending
  per GPT 7024105041).
- It does not authorize any real token promotion, revocation, or
  server deployment. Those need explicit launch approval and staged
  release in the private environment — not one user sentence
  "真机通过".

## Scope clarification addendum (Round 6, 2026-11-20)

**The owner's reported device acceptance covers the NODE POOL
only.** In chat on 2026-11-20 06:30 CST the owner clarified the
"真机验收通过" report with the single word "节点池" (node pool).
That clarification is recorded here as the scope of
`DEVICE_ACCEPTANCE=USER_REPORTED`. It does **NOT** cover any of
the following, and those rows stay UNVERIFIED:

- Ed25519 / WebCrypto support on the phone (Surge WebView
  `engine=webview` capability). The PR #104 probe has NOT been run
  on the real device and is NOT approved for auto-execution. CI
  passing in a Node VM is not device proof.
- The two cron cycles actually verifying the old-ID fence (rows
  5–8). A node-pool acceptance does not substitute for bridge cron
  fence verification.
- The logs / Shortcuts history privacy check (rows 11–14).
- The running source script SHA, Surge version, or iOS version
  (rows 2–4) — no values for these were supplied with the
  node-pool report.

Row 15 (acceptance scope) is therefore recorded as:
**scope = node pool only; bridge / Ed25519 / cron-fence /
logs-privacy scope NOT covered.** The node-pool acceptance and
Ed25519 support are different things and must not be conflated.
Nothing in this addendum invents device evidence; every row
remains UNVERIFIED until the owner supplies the observation from
the real device with source + time.

## Round 9 addendum — first real device-side crypto evidence (2026-11-20 09:31 CST)

**Source: GitHub Issue #73 comment 7027571021** (author zsh199410,
2026-11-20T01:32:48Z = 09:32 CST, titled "机主真机证据｜Issue #73
WebCrypto P0｜2026-11-20 09:31 CST"). The owner manually ran the
unmodified SHA-pinned probe and a separate read-only environment
diagnostic in Surge iOS with **Generic context (`模拟上下文=Generic`)
and WebView engine**, via the script editor. The non-secret values
visible in the supplied device screenshot are:

```text
secure=false
crypto=yes
subtle=no
digest=missing
trigger=editor
[Script Completed]
```

The original probe panel displayed `no_webcrypto`. These rows are
**VERIFIED-DEVICE** — the first real device-side crypto evidence
in this record. Their scope is strictly the **editor-trigger
runtime** shown in the screenshot; nothing here covers any other
trigger context.

| # | Field | Observed value | Status |
|---|---|---|---|
| 16 | Editor WebView secure context | `isSecureContext=false` in Surge iOS script editor, Generic + WebView | VERIFIED-DEVICE (7027571021, 09:31 CST) |
| 17 | `crypto` object present (editor) | `crypto=yes` — the `crypto` object exists | VERIFIED-DEVICE (7027571021) |
| 18 | `crypto.subtle` absent (editor) | `subtle=no` — no `crypto.subtle` in this runtime | VERIFIED-DEVICE (7027571021) |
| 19 | SHA-256 digest unavailable (editor) | `digest=missing` | VERIFIED-DEVICE (7027571021) |
| 20 | `crypto_ready` NOT met (editor) | Probe status is `insecure_context`, not `crypto_ready`; the earlier `no_webcrypto` is now explained by the insecure context, not by hardware limitation | VERIFIED-DEVICE (7027571021) |
| 21 | Module actual manual generic/intent context | NOT separately measured — the screenshot covers the editor trigger only; the module's generic/intent runtime has not been observed | UNVERIFIED |
| 22 | Pure-JS probe on device | NOT run — `PUREJS_DEVICE_PROBE=UNVERIFIED`; the 85,914-byte bundle is CI-only until an owner-run manual test | UNVERIFIED |

**Gate B status: `BLOCKED: EDITOR_WEBVIEW_INSECURE_CONTEXT`.**
The editor WebView has no `crypto.subtle` because the context is
not secure; this does **not** establish that iOS hardware or all
other Surge trigger contexts cannot support Ed25519, and it must
**not** be counted as `crypto_ready`. PR #111 models this as the
`insecure_context` status (distinct from `no_webcrypto`), verified
in isolation (probe 22/22, panel 9/9).

**Overall record status remains OPEN.** The original 15 rows are
still UNVERIFIED, row 21 (generic/intent context) and row 22
(Pure-JS probe) are UNVERIFIED, and `DEVICE_EVIDENCE_CORRELATION`
stays OPEN until those are measured. No device token, private URL,
or sensitive log value was collected or published with this evidence.
