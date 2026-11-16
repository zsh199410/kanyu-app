"""D2 recovery drill (GPT D1 review 6881291219, blocker 3).

Exercises the failure-recovery paths end to end, in-process with
explicit `now` (time travel: the drill must reach TTL-expired states
without waiting 24 h):
  S1 TTL-expired: rollback refuses, recovery plan names the
     last-verified-safe anchor; enter-degraded blocks publish/sync;
     manual restore (wrong ack refuses, right ack restores); clear-stop
     refuses without fresh evidence, succeeds after a fresh native run.
  S2 Missing native results: rollback refuses, plan says rebuild from
     a fresh native test; degraded; manual restore refuses (no
     verifiable anchor).
  S3 Production broken but rollback refused: served file is ungated
     legacy lines AND rollback refuses (TTL expired); degraded;
     status says broken-unqualified; manual restore serves the clean
     version again, flagged manual-restored-unverified; fresh evidence
     clears the stop; final sync converges.

Exit code 0 = all checks passed, 1 = any failed.
Writes a JSON log (desensitised: counts, SHA prefixes only).

Usage:
  python3 drills/recovery_drill.py --workdir <dir>
      --candidates <44-line file> --clean <14-line file>
      --native-record <file> --source-version <sha256>
      [--probe-db <file>] [--log <file>]
"""

import argparse
import hashlib
import json
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
D2_ROOT = os.path.dirname(HERE)
sys.path.insert(0, D2_ROOT)

from pool.publish import run_publish  # noqa: E402
from pool.publish_lock import file_manifest  # noqa: E402
from pool.recovery import (  # noqa: E402
    OWNER_ACK_CLEAR, OWNER_ACK_INIT, OWNER_ACK_RESTORE, clear_stop,
    enter_degraded, init_recovery_state, manual_restore, read_state,
    status)
from pool.rollback import run_rollback  # noqa: E402
from pool.sync import run_sync  # noqa: E402


def _read_lines(path):
    with open(path, encoding="utf-8") as f:
        return [l.rstrip("\n") for l in f if l.strip()]


def _fp_of(line):
    from pool.phone_gate import fingerprint_of, parse_surge_line
    _n, proto, host, port, params = parse_surge_line(line)
    return fingerprint_of(proto, host, port, params)


def _write_json(path, obj):
    with open(path, "w", encoding="utf-8") as f:
        json.dump(obj, f)


def _write_lines(path, lines):
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")


def _make_record(lines, pass_fps, version_sha, tested_at):
    results = []
    for line in lines:
        fp = _fp_of(line)
        name = line.split(" = ", 1)[0]
        if fp in pass_fps:
            results.append({"fingerprint": fp, "name": name,
                            "success": True, "ms": 150})
        else:
            results.append({"fingerprint": fp, "name": name,
                            "success": False, "ms": None})
    return {"format": "native-results-v1",
            "runs": [{"version_sha": version_sha, "tested_at": tested_at,
                      "network": "5G cellular pdp_ip0, no Wi-Fi",
                      "surge": "6.100.0 build 4025",
                      "results": results}]}


def main(argv=None):
    ap = argparse.ArgumentParser(description="D2 recovery drill")
    ap.add_argument("--workdir", required=True)
    ap.add_argument("--candidates", required=True)
    ap.add_argument("--clean", required=True)
    ap.add_argument("--native-record", required=True)
    ap.add_argument("--source-version", required=True)
    ap.add_argument("--probe-db", default=None)
    ap.add_argument("--log", default=None)
    args = ap.parse_args(argv)
    workdir = args.workdir
    checks = []

    def check(name, ok, detail=""):
        checks.append({"check": name, "ok": bool(ok), "detail": detail})
        print("[%s] %s %s" % ("PASS" if ok else "FAIL", name, detail))
        return ok

    pool44 = _read_lines(args.candidates)
    clean14 = _read_lines(args.clean)
    with open(args.native_record) as f:
        record = json.load(f)
    tested_at = record["runs"][0]["tested_at"]
    version_sha = args.source_version
    now = tested_at + 3600
    now_stale = tested_at + 25 * 3600
    clean_sha = hashlib.sha256(
        ("\n".join(clean14) + "\n").encode("utf-8")).hexdigest()
    publish_file = os.path.join(workdir, "publish", "pool-new.txt")
    served_file = os.path.join(workdir, "served", "pool-new.txt")

    def seed_v1_v2(wd):
        """Publish v1 clean + sync, then v2 13-line subset publish."""
        # D3: each scenario workdir is UNINITIALIZED until the
        # recovery state is explicitly initialized.
        rc, out = init_recovery_state(wd, OWNER_ACK_INIT)
        assert rc == 0, out
        rc, res = run_publish(wd, clean14, args.native_record, version_sha,
                              probe_db=args.probe_db, now=now,
                              source_file=args.candidates)
        assert rc == 0, res
        rc, res = run_sync(wd, args.native_record, version_sha,
                           probe_db=args.probe_db, now=now)
        assert rc == 0, res
        subset = clean14[:13]
        subset_sha = hashlib.sha256(
            ("\n".join(subset) + "\n").encode("utf-8")).hexdigest()
        subset_path = os.path.join(wd, "subset.txt")
        _write_lines(subset_path, subset)
        record2 = _make_record(subset, {_fp_of(l) for l in subset},
                               subset_sha, tested_at)
        record2_path = os.path.join(wd, "record2.json")
        _write_json(record2_path, record2)
        rc, res = run_publish(wd, subset, record2_path, subset_sha,
                              probe_db=args.probe_db, now=now,
                              source_file=subset_path)
        assert rc == 0, res
        return subset, subset_sha

    def history_snapshot(wd):
        hist = os.path.join(wd, "publish", "history")
        snaps = sorted(f for f in os.listdir(hist) if f.endswith(".txt"))
        assert snaps, "no history snapshot"
        return os.path.join(hist, snaps[-1])

    # ---------------- S1: TTL-expired ----------------
    s1 = os.path.join(workdir, "s1")
    os.makedirs(s1, exist_ok=True)
    seed_v1_v2(s1)
    rc, res = run_rollback(s1, "latest-history", args.native_record,
                           probe_db=args.probe_db, now=now_stale)
    check("s1-rollback-ttl-expired-refuses",
          rc == 1 and res.get("error") == "rollback_gate_zero_qualified",
          "rc=%s error=%s" % (rc, res.get("error")))
    check("s1-recovery-plan-names-last-verified-safe",
          res.get("recovery", {}).get("recommended_action") == "manual-recovery"
          and res["recovery"].get("last_verified_safe", {}).get("lines") == 14,
          "action=%s" % res.get("recovery", {}).get("recommended_action"))
    rc, out = enter_degraded(s1, "ttl expired", now=now_stale)
    check("s1-enter-degraded", rc == 0 and read_state(s1)["stopped"] is True,
          "rc=%s" % rc)
    rc, res = run_publish(s1, clean14, args.native_record, version_sha,
                          probe_db=args.probe_db, now=now_stale,
                          source_file=args.candidates)
    check("s1-publish-refuses-while-stopped",
          rc == 1 and res.get("error") == "pool_stopped", "rc=%s" % rc)
    rc, res = run_sync(s1, args.native_record, version_sha,
                       probe_db=args.probe_db, now=now_stale)
    check("s1-sync-refuses-while-stopped",
          rc == 1 and res.get("error") == "pool_stopped", "rc=%s" % rc)
    anchor = history_snapshot(s1)
    rc, out = manual_restore(s1, anchor, args.native_record, "WRONG-ACK",
                             probe_db=args.probe_db, now=now_stale)
    check("s1-manual-restore-wrong-ack-refuses",
          rc == 1 and out.get("error") == "owner_ack_required", "rc=%s" % rc)
    rc, out = manual_restore(s1, anchor, args.native_record,
                             OWNER_ACK_RESTORE, probe_db=args.probe_db,
                             now=now_stale)
    check("s1-manual-restore-restores-clean",
          rc == 0 and file_manifest(
              os.path.join(s1, "served", "pool-new.txt"))["sha256"] == clean_sha,
          "rc=%s" % rc)
    st = status(s1, args.native_record, probe_db=args.probe_db, now=now_stale)
    check("s1-restored-flagged-unverified",
          st["served_status_live"] == "manual-restored-unverified"
          and st["stopped"] is True,
          "live=%s" % st["served_status_live"])
    rc, out = clear_stop(s1, OWNER_ACK_CLEAR, args.native_record,
                         probe_db=args.probe_db, now=now_stale)
    check("s1-clear-stop-without-fresh-evidence-refuses",
          rc == 1 and out.get("error") == "served_not_currently_qualified",
          "rc=%s" % rc)
    now3 = now_stale + 60
    fresh = _make_record(clean14, {_fp_of(l) for l in clean14},
                         version_sha, now_stale)
    fresh_path = os.path.join(s1, "fresh.json")
    _write_json(fresh_path, fresh)
    rc, out = clear_stop(s1, OWNER_ACK_CLEAR, fresh_path,
                         probe_db=args.probe_db, now=now3)
    check("s1-clear-stop-after-fresh-evidence",
          rc == 0 and read_state(s1)["state"] == "ok", "rc=%s" % rc)
    rc, res = run_publish(s1, clean14, fresh_path, version_sha,
                          probe_db=args.probe_db, now=now3,
                          source_file=args.candidates)
    check("s1-publish-works-after-clear",
          rc == 0 and file_manifest(
              os.path.join(s1, "publish", "pool-new.txt"))["lines"] == 14,
          "rc=%s" % rc)

    # ---------------- S2: missing native results ----------------
    s2 = os.path.join(workdir, "s2")
    os.makedirs(s2, exist_ok=True)
    seed_v1_v2(s2)
    rc, res = run_rollback(s2, "latest-history",
                           os.path.join(s2, "no-such.json"),
                           probe_db=args.probe_db, now=now)
    check("s2-rollback-missing-record-refuses",
          rc == 1 and res.get("error", "").startswith("rollback_chain_"),
          "rc=%s error=%s" % (rc, res.get("error")))
    check("s2-recovery-plan-says-rebuild",
          res.get("recovery", {}).get("recommended_action")
          == "rebuild-from-fresh-native-test"
          and res["recovery"].get("last_verified_safe") is None,
          "action=%s" % res.get("recovery", {}).get("recommended_action"))
    rc, out = enter_degraded(s2, "no native evidence", now=now)
    check("s2-enter-degraded", rc == 0, "rc=%s" % rc)
    anchor2 = history_snapshot(s2)
    rc, out = manual_restore(s2, anchor2, os.path.join(s2, "no-such.json"),
                             OWNER_ACK_RESTORE, probe_db=args.probe_db,
                             now=now)
    check("s2-manual-restore-without-evidence-refuses",
          rc == 1 and out.get("error") == "anchor_not_restorable",
          "rc=%s error=%s" % (rc, out.get("error")))

    # ---------------- S3: production broken, rollback refused ----------------
    s3 = os.path.join(workdir, "s3")
    os.makedirs(s3, exist_ok=True)
    seed_v1_v2(s3)
    legacy = "\n".join(pool44) + "\n"
    with open(os.path.join(s3, "publish", "pool-new.txt"),
              "w", encoding="utf-8") as f:
        f.write(legacy)
    with open(os.path.join(s3, "served", "pool-new.txt"),
              "w", encoding="utf-8") as f:
        f.write(legacy)
    rc, res = run_rollback(s3, "latest-history", args.native_record,
                           probe_db=args.probe_db, now=now_stale)
    check("s3-rollback-refused-on-broken-prod",
          rc == 1 and res.get("error") == "rollback_gate_zero_qualified",
          "rc=%s" % rc)
    rc, out = enter_degraded(s3, "production broken", now=now_stale)
    check("s3-enter-degraded", rc == 0, "rc=%s" % rc)
    st = status(s3, args.native_record, probe_db=args.probe_db, now=now_stale)
    check("s3-served-flagged-broken",
          st["served_status_live"] == "broken-unqualified",
          "live=%s" % st["served_status_live"])
    anchor3 = history_snapshot(s3)
    rc, out = manual_restore(s3, anchor3, args.native_record,
                             OWNER_ACK_RESTORE, probe_db=args.probe_db,
                             now=now_stale)
    check("s3-manual-restore-serves-clean",
          rc == 0 and file_manifest(
              os.path.join(s3, "served", "pool-new.txt"))["sha256"] == clean_sha,
          "rc=%s" % rc)
    st = status(s3, args.native_record, probe_db=args.probe_db, now=now_stale)
    check("s3-restored-flagged-unverified",
          st["served_status_live"] == "manual-restored-unverified",
          "live=%s" % st["served_status_live"])
    now4 = now_stale + 60
    fresh3 = _make_record(clean14, {_fp_of(l) for l in clean14},
                          version_sha, now_stale)
    fresh3_path = os.path.join(s3, "fresh.json")
    _write_json(fresh3_path, fresh3)
    rc, out = clear_stop(s3, OWNER_ACK_CLEAR, fresh3_path,
                         probe_db=args.probe_db, now=now4)
    check("s3-clear-stop-after-fresh-evidence", rc == 0, "rc=%s" % rc)
    rc, res = run_sync(s3, fresh3_path, version_sha,
                       probe_db=args.probe_db, now=now4)
    check("s3-final-sync-converges",
          rc == 0 and file_manifest(
              os.path.join(s3, "served", "pool-new.txt"))["sha256"] == clean_sha,
          "rc=%s" % rc)

    passed = sum(1 for c in checks if c["ok"])
    log = {
        "drill": "recovery",
        "scenarios": ["s1-ttl-expired", "s2-missing-native-results",
                      "s3-production-broken-rollback-refused"],
        "checks": checks,
        "passed": passed,
        "total": len(checks),
        "ok": passed == len(checks),
        "at_cst": time.strftime("%Y-%m-%d %H:%M:%S CST", time.localtime()),
    }
    if args.log:
        with open(args.log, "w", encoding="utf-8") as f:
            json.dump(log, f, ensure_ascii=False, indent=2)
    print("RECOVERY-DRILL: %d/%d checks passed" % (passed, len(checks)))
    return 0 if log["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
