"""Probation promotion checker (read-only). Reports, per probation key, the
trusted phone 5G evidence under the CURRENT probation pool SHA and the
CURRENT manifest generation.
PHONE_EVIDENCE_READY (v2, Review 6033276893 fix 4; label renamed in
integration-04 per Review 6034204978 point 1) is a strict gate, not one
success:
  * the diagnostic chain passes (G10/Q2, see derive_diagnostic_pass), AND
  * >=1 trusted cellular success in that chain is control_verified=1, AND
  * no trusted cellular failure after the first success of the chain, AND
  * the manifest TTL is live, AND
  * the manifest has an integer generation and every counted row is bound
    to it (trial_generation == current generation), AND
  * the manifest entry carries a known source_group.
Otherwise NOT_READY (with a reason). The OLD one-success rule is reported
only as a legacy/partial line (LEGACY_PARTIAL), never as
PHONE_EVIDENCE_READY, so no downstream reader can mistake old evidence
for a promotion.
External gates this script CANNOT verify (fresh VPS <=300ms, Surge native
<300ms, publish gates) are printed as NOT_CHECKED_BY_THIS_SCRIPT; a
PHONE_EVIDENCE_READY here is phone evidence only, not a promotion
authorisation. Promotion itself is a separate explicit step; this script
never writes. The bare token READY must NOT appear as a verdict anywhere
in this script's output: old parsers that read "-> READY" as a global
promotion READY would misread it. GLOBAL_READY is a separate line below
and is NOT_EVALUATED here; a global READY requires real identity,
Surge native <300ms, current VPS <=300ms, source diversity, TTL,
blocklist clearance and publish authorisation, ALL passing.

DIAGNOSTIC_PASS (integration-01, Issue #73 G10/Q2) is a DERIVED diagnostic
state, separate from PHONE_EVIDENCE_READY: 3 consecutive qualifying
successes for the same candidate identity under the current manifest
SHA/generation, trusted external_policy_id, cellular, BOTH targets
reachable (dual_target_ok=1), intervals >=15 min, first-to-last <=24h,
last success fresh (<=24h old), TTL not expired. The chain is evaluated
on the LATEST consecutive run: a later failure/unknown resets it, and the
pass is only valid while the run is still the latest (no early return at
the third success). A trusted failure resets the chain; unknown rows,
non-cellular successes (network switch), missing evidence, future-dated
rows or a generation change never carry the chain across. cv=0 successes
count as diagnostic successes; formal PHONE_EVIDENCE_READY still needs a
control_verified success in the chain.
MANUAL_DIAGNOSTIC_PASS is the same chain over manual_report rows
(trusted=0) and is NOT equivalent to automatic DIAGNOSTIC_PASS; it is
also TTL- and generation-bound. Both are recorded as derived lines only;
no history row is modified and no manual record becomes trusted.
Manifest generation is required for any DIAGNOSTIC_PASS (absent generation
-> MANIFEST_GENERATION_MISSING); rows recorded without a generation
(pre-v2 / legacy) are shown as legacy counts and never enter the new
gates -- they are compatible but cannot be back-filled (no fabrication).
Paths may be overridden for isolation testing via PHONE_PROBE_MANIFEST /
PHONE_PROBE_DB; defaults are the live paths.
"""
import json
import os
import sqlite3
import sys
import time
from datetime import date

MANIFEST = os.environ.get("PHONE_PROBE_MANIFEST", "/opt/phone-telemetry/probation-manifest.json")
DB = os.environ.get("PHONE_PROBE_DB", "/opt/phone-telemetry/probation-observations.sqlite3")

MIN_SUCCESS_INTERVAL_S = 900   # >=15 min between consecutive successes
DIAGNOSTIC_WINDOW_S = 86400    # first-to-last success <=24h, and last success <=24h old


def derive_diagnostic_pass(rows, now):
    """Chain rule (G10/Q2) over time-ordered rows for one candidate identity.

    rows: list of dicts with keys received_at, obs_id, kind, where kind is
      'success' (qualifying success), 'failure', 'unknown' or 'other'
      (a success that does not qualify: wrong bearer/mode/trust, single
      target only, or a future-dated row).
    A qualifying success joins the chain only if it is >=15 min after the
    previous chain success; a too-close success is skipped (not counted,
    does not reset). Any failure / unknown / non-qualifying success resets
    the chain. The chain is evaluated on the LATEST run only: this function
    never returns early at the third success, so a later failure/unknown
    invalidates the pass. The passing triple must also be fresh: the last
    success must be within DIAGNOSTIC_WINDOW_S of `now` (and not in the
    future). Returns (passed, obs_ids_of_the_passing_triple,
    obs_ids_of_the_latest_run).
    """
    run = []
    for r in rows:
        if r["kind"] == "success":
            if not run:
                run.append((r["received_at"], r["obs_id"]))
            elif r["received_at"] - run[-1][0] >= MIN_SUCCESS_INTERVAL_S:
                run.append((r["received_at"], r["obs_id"]))
                while len(run) > 1 and run[-1][0] - run[0][0] > DIAGNOSTIC_WINDOW_S:
                    run.pop(0)
            # No early return: keep scanning; a later failure resets.
        else:
            run = []
    if len(run) >= 3 and run[-1][0] - run[0][0] <= DIAGNOSTIC_WINDOW_S:
        last = run[-1][0]
        if 0 <= now - last <= DIAGNOSTIC_WINDOW_S:
            return True, [oid for _, oid in run[:3]], [oid for _, oid in run]
    return False, [oid for _, oid in run[:3]], [oid for _, oid in run]


def classify_chain_row(row, manual=False):
    """Map one observation row to a chain kind.

    row: (status, reason, probe_mode, trusted, bearer, dual_target_ok).
    Automatic: success iff status='success' AND reason='target_reachable'
    AND trusted=1 AND probe_mode='external_policy_id' AND bearer='cellular'
    AND dual_target_ok=1 (BOTH targets reachable; a single-target
    'success' is not auditable proof and does not qualify).
    Manual:    success iff status='success' AND reason='target_reachable'
    AND probe_mode='manual_report' AND bearer='cellular' AND
    dual_target_ok=1 (trusted=0 by construction; manual success is never
    trusted).
    Any failure row (any bearer/mode/trust) or unknown row resets; a success
    that does not qualify (e.g. wifi success = network switch, or single
    target only) also resets.
    """
    status, reason, mode, trusted, bearer, dual = row
    if status == "failure":
        return "failure"
    if status == "unknown":
        return "unknown"
    if (status == "success" and reason == "target_reachable"
            and bearer == "cellular" and dual == 1):
        if manual:
            return "success" if mode == "manual_report" else "other"
        return "success" if (mode == "external_policy_id" and trusted == 1) else "other"
    return "other"


def ttl_status(man):
    """Return (ok, label): ok=False when the manifest TTL is expired or unparseable."""
    try:
        ttl = date.fromisoformat(str(man["ttl"]))
    except (KeyError, ValueError):
        return False, "TTL_INVALID"
    if date.today() > ttl:
        return False, "TTL_EXPIRED"
    return True, "TTL_OK"


def main():
    try:
        man = json.loads(open(MANIFEST, encoding="utf-8").read())
        sha = man["pool_sha"]
    except (OSError, ValueError, KeyError) as e:
        print("MANIFEST_ERROR:", e, file=sys.stderr)
        return 2
    generation = man.get("generation")
    generation_ok = type(generation) is int
    ttl_ok, ttl_label = ttl_status(man)
    now_ts = int(time.time())
    print("probation SHA:", sha[:12] + "...", "entries:", len(man["entries"]),
          "status:", man["status"], "ttl:", man["ttl"],
          "generation:", generation if generation_ok else "MISSING")
    c = sqlite3.connect("file:%s?mode=ro" % DB, uri=True)
    total = c.execute("SELECT COUNT(*) FROM phone_observations").fetchone()[0]
    print("probation observations total:", total)
    # v2 schema detection: pre-v2 DBs lack trial_generation / dual_target_ok.
    # Missing columns mean every row is legacy (never counted by the new
    # gates); the script must not crash on an old DB.
    cols = {r[1] for r in c.execute("PRAGMA table_info(phone_observations)")}
    has_gen = "trial_generation" in cols
    has_dual = "dual_target_ok" in cols
    gen_expr = "trial_generation" if has_gen else "NULL"
    dual_expr = "dual_target_ok" if has_dual else "0"
    ready = []
    diag_pass = []
    manual_pass = []
    for e in man["entries"]:
        proto, host, port = e["key"].split("|")
        port = int(port)
        # All rows for this identity under the current SHA (any generation).
        chain_rows = c.execute(
            "SELECT status, reason, probe_mode, trusted, bearer, received_at, id,"
            " control_verified, %s, %s"
            " FROM phone_observations WHERE protocol=? AND host=? AND port=?"
            " AND pool_sha=? ORDER BY received_at, id" % (gen_expr, dual_expr),
            (proto, host, port, sha)).fetchall()
        # Split: current-generation rows are the only new evidence; legacy
        # rows (NULL generation) and stale-generation rows are tallied
        # separately and never enter the new gates.
        current_rows = []
        legacy_rows = 0
        stale_gen_rows = 0
        for r in chain_rows:
            gen = r[8]
            if gen is None:
                legacy_rows += 1
            elif generation_ok and gen == generation:
                current_rows.append(r)
            else:
                stale_gen_rows += 1

        def to_chain(rows, manual):
            out = []
            for r in rows:
                if r[5] > now_ts:
                    kind = "other"  # future-dated row: invalid evidence
                else:
                    kind = classify_chain_row((r[0], r[1], r[2], r[3], r[4], r[9]), manual=manual)
                out.append({"received_at": r[5], "obs_id": r[6],
                            "kind": kind, "cv": r[7]})
            return out

        auto_rows = to_chain(current_rows, manual=False)
        man_rows = to_chain(current_rows, manual=True)
        auto_ok, auto_ids, auto_run_ids = derive_diagnostic_pass(auto_rows, now_ts)
        man_ok, man_ids, _man_run_ids = derive_diagnostic_pass(man_rows, now_ts)

        # New-gate counts (current generation only, trusted cv=1).
        succ = fail = unk = 0
        for r in current_rows:
            if r[3] == 1 and r[7] == 1 and r[4] == "cellular" and r[2] == "external_policy_id":
                if r[0] == "success":
                    succ += 1
                elif r[0] == "failure":
                    fail += 1
                elif r[0] == "unknown":
                    unk += 1
        # First trusted success (current generation) and any trusted
        # cellular failure after it (fail-closed veto, v1 semantics kept).
        fs = None
        for r in current_rows:
            if (r[0] == "success" and r[3] == 1 and r[7] == 1
                    and r[4] == "cellular" and r[2] == "external_policy_id"):
                if fs is None or r[5] < fs:
                    fs = r[5]
        fail_after = 0
        if fs is not None:
            for r in current_rows:
                if (r[0] == "failure" and r[3] == 1 and r[7] == 1
                        and r[4] == "cellular" and r[2] == "external_policy_id"
                        and r[5] > fs):
                    fail_after += 1
        # Legacy verdict (old one-success rule, any generation, SHA-bound):
        # reported only as LEGACY_PARTIAL, never as PHONE_EVIDENCE_READY.
        legacy_succ = 0
        legacy_fail_after = 0
        legacy_fs = None
        for r in chain_rows:
            if (r[0] == "success" and r[3] == 1 and r[7] == 1
                    and r[4] == "cellular" and r[2] == "external_policy_id"):
                legacy_succ += 1
                if legacy_fs is None or r[5] < legacy_fs:
                    legacy_fs = r[5]
        if legacy_fs is not None:
            for r in chain_rows:
                if (r[0] == "failure" and r[3] == 1 and r[7] == 1
                        and r[4] == "cellular" and r[2] == "external_policy_id"
                        and r[5] > legacy_fs):
                    legacy_fail_after += 1
        legacy_label = ("LEGACY_PARTIAL" if (legacy_succ >= 1 and legacy_fail_after == 0)
                        else "LEGACY_NONE")
        # v2 PHONE_EVIDENCE_READY: all checkable gates must pass. Source group comes from
        # the manifest entry (server-side); unknown/absent -> NOT_READY.
        group = e.get("source_group")
        group_ok = group not in (None, "", "unknown")
        has_cv1_in_chain = any(
            r["cv"] == 1 for r in auto_rows if r["obs_id"] in set(auto_run_ids))
        if not ttl_ok:
            reason = ttl_label
        elif not generation_ok:
            reason = "MANIFEST_GENERATION_MISSING"
        elif not group_ok:
            reason = "SOURCE_GROUP_UNKNOWN"
        elif not auto_ok:
            reason = "NO_DIAGNOSTIC_CHAIN"
        elif not has_cv1_in_chain:
            reason = "NO_CONTROL_VERIFIED_SUCCESS"
        elif fail_after != 0:
            reason = "TRUSTED_FAILURE_AFTER_SUCCESS"
        else:
            reason = "OK"
        verdict = "PHONE_EVIDENCE_READY" if reason == "OK" else "NOT_READY"
        if verdict == "PHONE_EVIDENCE_READY":
            ready.append(e["name"])
        print("  %s %s success=%d failure=%d unknown=%d fail_after_first_success=%d"
              " legacy_rows=%d stale_gen_rows=%d -> %s reason=%s legacy=%s" % (
                  e["name"], e["key"], succ, fail, unk, fail_after,
                  legacy_rows, stale_gen_rows, verdict, reason, legacy_label))
        # DIAGNOSTIC_PASS (automatic chain) and MANUAL_DIAGNOSTIC_PASS.
        if not generation_ok:
            diag_label = "MANIFEST_GENERATION_MISSING"
        elif not ttl_ok:
            diag_label = ttl_label
        elif auto_ok:
            diag_label = "DIAGNOSTIC_PASS"
            diag_pass.append(e["name"])
        else:
            diag_label = "NOT_READY"
        if not generation_ok:
            man_label = "MANIFEST_GENERATION_MISSING"
        elif not ttl_ok:
            man_label = ttl_label
        elif man_ok:
            man_label = "MANUAL_DIAGNOSTIC_PASS"
            manual_pass.append(e["name"])
        else:
            man_label = "NOT_READY"
        print("  %s %s diagnostic=%s obs_ids=%s generation=%s ttl=%s"
              " legacy_rows=%d stale_gen_rows=%d" % (
                  e["name"], e["key"], diag_label, auto_ids,
                  generation if generation_ok else "MISSING", man["ttl"],
                  legacy_rows, stale_gen_rows))
        print("  %s %s manual=%s obs_ids=%s" % (
            e["name"], e["key"], man_label, man_ids))
    print("PHONE_EVIDENCE_READY count:", len(ready), ready)
    print("DIAGNOSTIC_PASS count:", len(diag_pass), diag_pass)
    print("MANUAL_DIAGNOSTIC_PASS count:", len(manual_pass), manual_pass)
    # GLOBAL_READY (integration-04, Review 6034204978 point 1): this
    # script evaluates PHONE evidence only. A global READY requires ALL
    # of: real identity, Surge native <300ms, current VPS <=300ms,
    # source diversity, TTL, blocklist clearance, publish authorisation.
    # TTL is the only one of those this script checks; the rest are
    # NOT_CHECKED_BY_THIS_SCRIPT and GLOBAL_READY is therefore
    # NOT_EVALUATED here -- never infer a global READY from the
    # PHONE_EVIDENCE_READY line above.
    print("GLOBAL_READY: NOT_EVALUATED "
          "(real_identity=NOT_CHECKED_BY_THIS_SCRIPT "
          "surge_native_lt_300ms=NOT_CHECKED_BY_THIS_SCRIPT "
          "current_vps_le_300ms=NOT_CHECKED_BY_THIS_SCRIPT "
          "source_diversity=NOT_CHECKED_BY_THIS_SCRIPT "
          "ttl=CHECKED_BY_THIS_SCRIPT "
          "blocklist=NOT_CHECKED_BY_THIS_SCRIPT "
          "publish_authorisation=NOT_CHECKED_BY_THIS_SCRIPT)")
    print("External gates NOT_CHECKED_BY_THIS_SCRIPT: fresh VPS <=300ms,"
          " Surge native <300ms, publish gates (a PHONE_EVIDENCE_READY"
          " here is phone evidence only, not a promotion authorisation)")
    print("PROMOTION_CHECK_DONE")
    return 0


if __name__ == "__main__":
    sys.exit(main())
