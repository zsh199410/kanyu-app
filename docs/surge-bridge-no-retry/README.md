# Surge Bridge — Non-idempotent command retry fix

## Scope
Based on Issue #73 comment #6967021233, a single `POST /v1/scripting/cron/evaluate` may execute twice: `$httpAPI` times out after 10 seconds, then `api()` falls back to a direct HTTP POST even though the first request may still be running (script 40–55 seconds).

This is a **sanitized drop-in replacement** for **only** `httpAPI()` and `api()` in the existing private `/opt/surge-bridge/bridge.js`. Keep the existing `http()`, `APIKEY`, other script logic and private configuration unchanged. This branch does **not** deploy to the VPS.

## Safety contract
- Callback success: return the initial reply, no fallback.
- Non-idempotent `POST/PUT/PATCH/DELETE` with callback timeout/empty callback/throw: return `{status: 0, err: 'outcome_unknown_no_retry', pending: true}`. **Do not resend**; determine actual completion from device logbook/remote status before another manual attempt.
- `$httpAPI` entirely unavailable: allow exactly one direct HTTP attempt, not a retry.
- Only `GET` may use the legacy direct HTTP fallback after an ambiguous transport timeout. The original `http()` implements just GET vs POST; HEAD, OPTIONS, PUT, PATCH and DELETE are **not retried via direct HTTP**, avoiding accidental method conversion.
- A late callback after timeout is ignored. No promise completion can cause a second mutation.
- Never record or expose real token/URL/node URI. The existing `http()` retains its own configuration.

## Local test
`node docs/surge-bridge-no-retry/test_bridge_api_nonretry.js`

Expected after the latest update: `10/10 bridge API non-retry cases passed`. The earlier exact head passed 6/6 in Muse's local environment. **The new exact head needs a fresh 10/10 run before deployment.** This does not replace a **real private bridge** integration test or iPhone safety verification.

## Pre-deployment gate
Muse must independently compare the original bridge.js `httpAPI()/api()` source to the provided excerpt, check **all callers** for reliance on auto retry and for correct handling of `pending`, run the above Node fixture and private bridge isolation tests, save old bridge SHA and reversible backup, then supply exact head+evidence for separate production approval. Do not automatically merge or deploy this Draft PR. Do not change the free-node production subscription, pinned policies, STOP or DIRECT behavior.
