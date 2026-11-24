"""Probation promotion checker (read-only). Reports, per probation key, the
trusted phone 5G evidence under the CURRENT probation pool SHA.
READY iff >=1 trusted cellular success (external_policy_id, control_verified=1)
under the current SHA and no trusted cellular failure after the first success.
Old-SHA rows never count (evidence binds to identity key + pool SHA).
Promotion itself is a separate explicit step; this script never writes.

DIAGNOSTIC_PASS (integration-01, Issue #73 G10/Q2) is a DERIVED diagnostic
state, separate from READY: 3 consecutive qualifying successes for the same
candidate identity under the current manifest SHA/generation, trusted
external_policy_id, cellular, both targets reachable (target_reachable),
intervals >=15 min, first-to-last <=24h, TTL not expired. A trusted
failure resets the chain; unknown rows, non-cellular successes (network
switch), missing evidence or a generation change never carry the chain
across. cv=0 successes count as diagnostic successes; formal READY still
needs the independent same-batch control. MANUAL_DIAGNOSTIC_PASS is the
same chain over manual_report rows (trusted=0) and is NOT equivalent to
automatic DIAGNOSTIC_PASS. Both are recorded as derived lines only; no
history row is modified and no manual record becomes trusted.
Manifest generation is required for any DIAGNOSTIC_PASS (absent generation
-> MANIFEST_GENERATION_MISSING); READY stays SHA-bound as before.
Paths may be overridden for isolation testing via PHONE_PROBE_MANIFEST /
PHONE_PROBE_DB; defaults are the live paths.
"""
import json
import os
import sqlite3
import sys
from datetime import date

MANIFEST = os.environ.get("PHONE_PROBE_MANIFEST", "/opt/phone-telemetry/probation-manifest.json")
DB = os.environ.get("PHONE_PROBE_DB", "/opt/phone-telemetry/probation-observations.sqlite3")

MIN_SUCCESS_INTERVAL_S = 900   # >=15 min between consecutive successes
DIAGNOSTIC_WINDOW_S = 86400    # first-to-last success <=24h


def derive_diagnostic_pass(rows):
    """Chain rule (G10/Q2) over time-ordered rows for one candidate identity.

    rows: list of dicts with keys received_at, obs_id, kind, where kind is
      'success' (qualifying success), 'failure', 'unknown' or 'other'
      (a success that does not qualify: wrong bearer/mode/trust).
    A qualifying success joins the chain only if it is >=15 min after the
    previous chain success; a too-close success is skipped (not counted,
    does not reset). Any failure / unknown / non-qualifying success resets
    the chain. Returns (passed, obs_ids_of_the_passing_triple_or_current_run).
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
            if len(run) >= 3:
                return True, [oid for _, oid in run[:3]]
        else:
            run = []
    return False, [oid for _, oid in run]


def classify_chain_row(row, manual=False):
    """Map one observation row to a chain kind.

    Automatic: success iff status='success' AND reason='target_reachable'
    AND trusted=1 AND probe_mode='external_policy_id' AND bearer='cellular'.
    Manual:    success iff status='success' AND reason='target_reachable'
    AND probe_mode='manual_report' AND bearer='cellular' (trusted=0 by
    construction; manual success is never trusted).
    Any failure row (any bearer/mode/trust) or unknown row resets; a success
    that does not qualify (e.g. wifi success = network switch) also resets.
    """
    status, reason, mode, trusted, bearer = row
    if status == "failure":
        return "failure"
    if status == "unknown":
        return "unknown"
    if status == "success" and reason == "target_reachable" and bearer == "cellular":
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
    print("probation SHA:", sha[:12] + "...", "entries:", len(man["entries"]),
          "status:", man["status"], "ttl:", man["ttl"],
          "generation:", generation if generation_ok else "MISSING")
    c = sqlite3.connect("file:%s?mode=ro" % DB, uri=True)
    total = c.execute("SELECT COUNT(*) FROM phone_observations").fetchone()[0]
    print("probation observations total:", total)
    ready = []
    diag_pass = []
    manual_pass = []
    for e in man["entries"]:
        proto, host, port = e["key"].split("|")
        port = int(port)
        rows = c.execute(
            "SELECT status, COUNT(*) FROM phone_observations WHERE protocol=? AND host=? AND port=?"
            " AND trusted=1 AND control_verified=1 AND bearer='cellular'"
            " AND probe_mode='external_policy_id' AND pool_sha=? GROUP BY status",
            (proto, host, port, sha)).fetchall()
        d = dict(rows)
        succ = d.get("success", 0)
        fail = d.get("failure", 0)
        unk = d.get("unknown", 0)
        # first success ts and any trusted cellular failure after it
        # (integration-01: the fail_after query now carries the same
        # control_verified / probe_mode / bearer filter as the success
        # query; a cv=0 or non-cellular failure must not veto READY).
        fs = c.execute(
            "SELECT MIN(received_at) FROM phone_observations WHERE protocol=? AND host=? AND port=?"
            " AND status='success' AND trusted=1 AND control_verified=1 AND bearer='cellular'"
            " AND probe_mode='external_policy_id' AND pool_sha=?",
            (proto, host, port, sha)).fetchone()[0]
        fail_after = 0
        if fs is not None:
            fail_after = c.execute(
                "SELECT COUNT(*) FROM phone_observations WHERE protocol=? AND host=? AND port=?"
                " AND status='failure' AND trusted=1 AND control_verified=1 AND bearer='cellular'"
                " AND probe_mode='external_policy_id' AND received_at>? AND pool_sha=?",
                (proto, host, port, fs, sha)).fetchone()[0]
        verdict = "READY" if (succ >= 1 and fail_after == 0) else "NOT_READY"
        if verdict == "READY":
            ready.append(e["name"])
        print("  %s %s success=%d failure=%d unknown=%d fail_after_first_success=%d -> %s" % (
            e["name"], e["key"], succ, fail, unk, fail_after, verdict))
        # DIAGNOSTIC_PASS (automatic chain) and MANUAL_DIAGNOSTIC_PASS.
        chain_rows = c.execute(
            "SELECT status, reason, probe_mode, trusted, bearer, received_at, id"
            " FROM phone_observations WHERE protocol=? AND host=? AND port=?"
            " AND pool_sha=? ORDER BY received_at, id",
            (proto, host, port, sha)).fetchall()
        auto_rows = [{
            "received_at": r[5], "obs_id": r[6],
            "kind": classify_chain_row(r[:5]),
        } for r in chain_rows]
        man_rows = [{
            "received_at": r[5], "obs_id": r[6],
            "kind": classify_chain_row(r[:5], manual=True),
        } for r in chain_rows]
        auto_ok, auto_ids = derive_diagnostic_pass(auto_rows)
        man_ok, man_ids = derive_diagnostic_pass(man_rows)
        if not generation_ok:
            diag_label = "MANIFEST_GENERATION_MISSING"
        elif not ttl_ok:
            diag_label = ttl_label
        elif auto_ok:
            diag_label = "DIAGNOSTIC_PASS"
            diag_pass.append(e["name"])
        else:
            diag_label = "NOT_READY"
        if man_ok:
            man_label = "MANUAL_DIAGNOSTIC_PASS"
            manual_pass.append(e["name"])
        else:
            man_label = "NOT_READY"
        print("  %s %s diagnostic=%s obs_ids=%s generation=%s ttl=%s" % (
            e["name"], e["key"], diag_label, auto_ids,
            generation if generation_ok else "MISSING", man["ttl"]))
        print("  %s %s manual=%s obs_ids=%s" % (
            e["name"], e["key"], man_label, man_ids))
    print("READY count:", len(ready), ready)
    print("DIAGNOSTIC_PASS count:", len(diag_pass), diag_pass)
    print("MANUAL_DIAGNOSTIC_PASS count:", len(manual_pass), manual_pass)
    print("PROMOTION_CHECK_DONE")
    return 0


if __name__ == "__main__":
    sys.exit(main())
