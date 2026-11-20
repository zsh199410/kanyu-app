# Issue #73 — phone-native probe ingestion (P0, staged)

This is **real executable code**, not a production installation receipt. The existing single-writer, served pool and HTTP configuration are unchanged until the operator deploys and validates the independent loopback ingestion service. `receiver.py` records observations to a **separate staging SQLite**, never runs commands, modifies live `pool.db`, or publishes/subtracts nodes.

## Key compatibility fact

The official Surge Manual documents `GET /v1/policies?include_external=true` for **iOS 6.0+**, returning `external-policies` with `{name, group, identifier}`. Use identifier in `$httpClient.head({url, policy:identifier}, cb)`. The owner's Surge iOS **5** cannot be assumed to expose this API. `phone-probe.js` attempts this API and, only if unavailable, falls back to `$httpClient`'s `policy-descriptor` temporary policy constructed locally from the subscription. The receiver **never trusts this fallback as deletion evidence by default**; trusted admission requires a separate on-device verification and `PHONE_PROBE_DESCRIPTOR_ACCEPTED=YES_AFTER_DEVICE_VALIDATION` (off by default). An optional raw success with HTTP response indicates **connectable**, even when latency exceeds 300ms. No proxy passwords or raw policy URIs are sent to the receiver.

Official references:
- https://manual.nssurge.com/tools/http-api.html
- https://manual.nssurge.com/scripting/api.html

## First, verify without touching production

```sh
python3 -m unittest -v test_receiver.py
node test_js.js
```

Receiver properties: bound to `127.0.0.1` only; requires a fresh 32+ character bearer token; timestamp within 5 minutes, 32-hex nonce replay rejection, current pool exact SHA-256 binding, valid name-to-identity resolution (protocol/host/port), two distinct target results, at most 6 observations and 16KiB per request, metadata-only receipts. All storage is a separate mode-600 SQLite. A whole-batch outage converts failure readings to UNKNOWN. A `temporary_policy_descriptor` failure is UNKNOWN until actual iPhone validation.

## Authorized operator deployment sequence (not yet executed)

1. Recheck live US VPS paths, actual running Surge version, working one-publisher state, served/staging/HTTP SHA, 21 pinned members, and rollback snapshot. Install the Python service in a private root-owned directory; generate **a new random dedicated token** into a mode-600 env file; do not reuse the existing Surge `http-api` credential or MITM CA key.
2. Set `PHONE_PROBE_POOL` to the existing public pool bytes path, `PHONE_PROBE_DB` to an isolated new staging database and `PHONE_PROBE_TOKEN` from the private file. Keep `PHONE_PROBE_DESCRIPTOR_ACCEPTED` **unset** until the actual user's iOS 5 policy-descriptor behavior is verified. Start the service **on loopback only**. Never bind to `0.0.0.0`.
3. On the **existing** trusted `sgcmd.vip668.xin:8443` HTTPS reverse proxy, add only a tightly scoped `POST /v1/phone-observations` forwarding route to `127.0.0.1:8724`. Preserve existing `/m/pool-new.txt`, `/m/probe-task.js` and `/poll`/`result`; enforce TLS validation, method restrictions and per-source rate limits; test wrong token, duplicate nonce, stale SHA and excessive body all refuse; ensure request-body and Authorization header are not logged.
4. Publish `phone-probe.js` to a separately versioned URL on that server after verifying its exact SHA. Do not overwrite the existing `probe-task.js`. In the owner's Surge configuration, add one separate 15-minute cron **only after** endpoint/TLS test passes, with a private, newly issued dedicated token passed through the script `argument` parameter. Do not commit the token or include it in a public hosted JS file. Example line **only after live verification**:

   ```ini
   手机节点采集 = type=cron,cronexp="*/15 * * * *",timeout=120,debug=0,wake-system=true,script-path=https://sgcmd.vip668.xin:8443/m/phone-probe-v1.js,script-update-interval=86400,argument=REPLACE_WITH_PRIVATE_ISSUED_TOKEN
   ```

5. On the actual iPhone first verify one **known working** and one **known failing** temporary policy with explicit policy identity, direct vs temporary descriptor behavior, two independent target results, cellular vs Wi-Fi tagging, real SHA, SQLite receipt and correct handling of a background suspension. If iOS 5 descriptor probes don't work or don't match real Smart group routing, leave `PHONE_PROBE_DESCRIPTOR_ACCEPTED` off and continue staging UNKNOWN only; never force auto-removal.
6. Integrate the staging evidence into `auto_prune_phone_first.py` behind a read-only admission/identity validator; **the receiver is not itself a deletion authorizer**. Only a vetted, device-tested, non-pinned node with two independent failing phone windows can be quarantined, then after another verified failed window removed, while preserving 21 pins and backup/rollback/no-DIRECT constraints. `AUTO_DELETE` is still OFF by the strict live-deletion metric until this actually happens.

### What is not yet verified

- The iPhone's exact Surge version and external-policy API support; real device `policy-descriptor` equivalence is unknown.
- The existing VPS command mailbox/HTTP proxy has not been modified. The loopback receiver and public TLS route have **not** been deployed.
- The staging DB has not been linked to live `phone_failures`; no production removal has been performed.

Do not claim any of these are PASS based only on Python unit tests or Node mocks.
