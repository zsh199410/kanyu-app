# Issue #73 — All-failure phone batches: same-run control proof (P0)

## Why v2 did not produce useful failure evidence

The old rule was `len(batch)>=3 && all candidate status==failure -> all unknown/possible_network_outage`.
That inference is invalid: a rotating cohort may consist entirely of unreachable proxies while another
working pinned proxy proves the phone can access the internet. Earlier pinned successes **at other
timestamps** are not by themselves same-run connectivity proof. The initial 15 unknowns remain
historical unknown evidence; this fix **does not rewrite or "upgrade" them into trusted failures**.

## Implemented behavior

* Keep the original **4 rotating candidates** per 15-min run and the existing persistent cursor.
* Probe up to **2 separate current-group members** (prefer recently observed reachable names,
  otherwise select independent members in the current SHA-bound subscription) using identical
  HEAD targets and verified `external_policy_id` identifiers.
* Controls never appear as ordinary `observations`. They appear as a bounded
  `network_controls` array; their names must be in the same pool SHA, different from all four
  ordinary candidates and from each other. An HTTP reachability success through one control
  in the same request disproves a *general* phone connectivity outage.
* A group of 4 transport failures + reachable control => **4 trusted failure records**.
* A group of 4 transport failures + no/failed controls => **4 unknown records**, with
  `reason='batch_unverified_network'`. Their `raw_status='failure'` and
  `raw_reason='dual_transport_failure'` remain in staging for diagnosis, but the importer
  still sees normalized unknown and cannot use these to delete nodes.
* Partial success in the four candidates retains individual success/failure/unknown as before.
  No new control is required for such a batch.
* Unknown bearer, unverified iOS 5 policy descriptor, stale SHA, invalid or duplicated
  control identity never counts as connectivity proof. No low-quality failure promotion.
* No stored proxy URI, credential, raw socket error or HTTP request body is sent to GitHub.
  Only the phone's existing private argument token authorizes the HTTPS ingestion.

## Additive SQLite columns

In `phone_observations`:

| Column | Purpose |
|---|---|
| `status` | Normalized and **only** imported deletion evidence if `failure` |
| `reason` | Normalized categoric reason |
| `raw_status` | Individual two-target classification before trust/outage holds |
| `raw_reason` | Individual categorical explanation before holds |
| `control_verified` | 1 iff same-batch independent external policy ID got a reachable result |

Old rows get default `legacy_unknown` / `legacy_unclassified` / 0 as a truthful
legacy marker. **Do not backfill existing old unknowns as failures.**
The importer selects explicit legacy columns and imports only normalized
`status='failure'` with `trusted=1`.

## Real VPS rollout (Muse)

1. Keep `P2P3_ALLOW_AUTO_PRUNE=NO`, current served/staging/HTTP pool in sync, 21 canonical pins
   and single writer. Snapshot receiver, its systemd unit, hosted v2 JS and **online SQLite
   backup** of staging. Verify SQLite integrity, hashes and restore in private isolation.
2. Install verified GitHub commit version of `receiver.py` only, not whole PR#119 or prior
   `production_cycle.py`/`auto_prune.py` (which have local hotfixes). Run isolated
   `python3 -m unittest -v test_receiver.py test_remediation.py` and
   `node test_js.js` **before restart**. Verify the additive column migration and
   backwards-compatible legacy v2 phone POST, unknown-only when no control is present.
3. Restart loopback receiver after backups; keep existing HTTPS bearer token, nginx
   restrictions, importer, 21 pins and subscription exactly as they are.
4. Publish `phone-probe.js` as new, separate `/m/phone-probe-v3.js`.
   Do not overwrite v2, do not expose the token. Verify HTTPS 200,
   exact public SHA-256 and `node --check`. Securely change only the iPhone cron's
   `script-path`, retain `argument` and all other settings, refresh script cache.
   If direct device control is not available, **report honestly that mobile switch is pending**.
5. First phone run: expect 4 ordinary observations and up to 2 separate controls.
   `control_verified=1` on new rows when a control can reach a target. Probe a
   known-good pinned member as control; it must not be counted toward the ordinary
   "five usable rotating nodes" safety threshold. Check both cases:
   - **good control + four candidate transport failures:** 4 normalized trusted failure
     rows, 4 raw failures, same nonce, no replay duplication.
   - **control absent or fails:** 4 normalized unknown, reason
     `batch_unverified_network`, 4 raw transport failures; cannot be pruned.
6. Report **new-only** statistics by normalized status and raw reason, controls successful
   vs failed, ordinary nodes tested/healthy, and `status=unknown/raw_status=failure`
   counts. Continue low-health deletion hold until ordinary pool has defensible
   healthy replacements; do not clear isolate records or fabricate success.
7. On mismatch: revert just the receiver/script from the exact backed-up bytes;
   keep current pool and only single writer online. No DIRECT fallback or pin changes.

## Byte-level release references

Source commit must match PR #122 HEAD (run GitHub SHA verification on release):

- `receiver.py` — UTF-8 **13626 bytes**, SHA-256
  `eb889401efd870c2faf843b98457081369abaddc9bdda503475e6d0f8ad9cd73`
- `phone-probe.js` — UTF-8 **12379 bytes**, SHA-256
  `e2cf9dc123ded21b97357acb91ef49e573132331572d95b89b0f77fb01677df1`

Command from trusted git clone:

```bash
git fetch --no-tags origin issue73-phone-control-p0-20261121
git show FETCH_HEAD:docs/surge-d7-acceptance/phone-telemetry/receiver.py > receiver-v3.py
git show FETCH_HEAD:docs/surge-d7-acceptance/phone-telemetry/phone-probe.js > phone-probe-v3.js
printf '%s  %s\n' 'eb889401efd870c2faf843b98457081369abaddc9bdda503475e6d0f8ad9cd73' receiver-v3.py | sha256sum -c -
printf '%s  %s\n' 'e2cf9dc123ded21b97357acb91ef49e573132331572d95b89b0f77fb01677df1' phone-probe-v3.js | sha256sum -c -
python3 -m py_compile receiver-v3.py
node --check phone-probe-v3.js
```

If a newer HEAD is published, re-compute SHA-256 from that exact commit and do not
reuse an outdated attestation blindly.
