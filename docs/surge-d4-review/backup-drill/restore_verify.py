#!/usr/bin/env python3
"""D4 backup restore verification (read-only on production).

Restores a snapshot (made by snapshot_backup.py) into a scratch dir
and verifies it is actually usable. Also checks the pre-existing
p1p3 backup (read-only) for recoverability.

Verifications (counts/hashes/verdicts only -- never file contents):
  1. every restored file's SHA matches the manifest
  2. restored pool.db opens (read-write copy) with table counts equal
     to the manifest
  3. restored probe.db opens with counts equal to the manifest
  4. restored publish file parses: line count + pinned/rotation split
     equal to the manifest
  5. restored config.yaml top-level keys equal the manifest
  6. gate dry-run consistency: D3 publish dry-run with the RESTORED
     pool-new.txt and with a fresh copy of the LIVE pool-new.txt, both
     against the fixture native record (version mismatch is expected
     for both): the two verdicts (rc + error) must be IDENTICAL.
     Identical = restore is byte-faithful; different = restore lossy.
  7. p1p3 backup (2026-11-13): pool.db opens read-only + counts;
     pool-new.txt.47 parses; age reported; manifest presence reported.

Usage:
  restore_verify.py --snapshot <dir> --scratch <dir> --code-dir <D4 tree>
Exit 0 = all checks pass. Stdout: one JSON object (the log).
"""
import argparse
import hashlib
import json
import os
import re
import shutil
import sqlite3
import subprocess
import sys
import time

LINE_RE = re.compile(r"^\s*[^=]+=\s*([A-Za-z0-9_-]+)\s*,\s*([^,\s]+)\s*,\s*(\d+)")
P1P3 = "/opt/free-node-program/backup-p1p3-20261113-190706"


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def db_counts(path, read_only=True):
    uri = ("file:%s?mode=ro" % path) if read_only else path
    con = sqlite3.connect(uri, uri=True) if read_only else sqlite3.connect(path)
    try:
        tables = [r[0] for r in con.execute(
            "SELECT name FROM sqlite_master WHERE type='table'")]
        return {t: con.execute("SELECT COUNT(*) FROM %s" % t).fetchone()[0]
                for t in tables if t != "sqlite_sequence"}
    finally:
        con.close()


def parse_subscription(path, pinned_keys, blocked_keys):
    n_pin = n_rot = n_blocked = n_unparsed = 0
    total = 0
    with open(path, encoding="utf-8") as f:
        for line in f:
            if not line.strip():
                continue
            total += 1
            m = LINE_RE.match(line)
            if not m:
                n_unparsed += 1
                continue
            key = (m.group(1), m.group(2), int(m.group(3)))
            if key in blocked_keys:
                n_blocked += 1
            elif key in pinned_keys:
                n_pin += 1
            else:
                n_rot += 1
    return {"lines": total, "pinned": n_pin, "rotation": n_rot,
            "blocked": n_blocked, "unparsed": n_unparsed}


def gate_dry_run(code_dir, workdir, source_file, record_path, probe_db):
    """D3 publish dry-run in a scratch workdir. Returns (rc, error)."""
    sys.path.insert(0, code_dir)
    from pool.publish import run_publish  # noqa: E402
    from pool.recovery import OWNER_ACK_INIT, init_recovery_state  # noqa: E402
    rc0, _ = init_recovery_state(workdir, OWNER_ACK_INIT)
    if rc0 != 0:
        return -1, "init_failed"
    source_sha = sha256_file(source_file)
    candidates = [l.rstrip("\n") for l in open(source_file)
                  if l.strip()]
    rc, res = run_publish(workdir, candidates, record_path, source_sha,
                          probe_db=probe_db, source_file=source_file)
    return rc, res.get("error")


def main(argv=None):
    ap = argparse.ArgumentParser(description="D4 restore verification")
    ap.add_argument("--snapshot", required=True)
    ap.add_argument("--scratch", required=True)
    ap.add_argument("--code-dir", required=True)
    args = ap.parse_args(argv)
    checks = []

    def check(name, ok, detail=""):
        checks.append({"check": name, "ok": bool(ok), "detail": str(detail)})
        return bool(ok)

    snap = os.path.abspath(args.snapshot)
    scratch = os.path.abspath(args.scratch)
    manifest = json.load(open(os.path.join(snap, "manifest.json")))
    os.makedirs(scratch, mode=0o700, exist_ok=True)

    # ---- 1. restore + SHA check ----
    restored = {}
    for rel in manifest["files"]:
        src = os.path.join(snap, rel)
        dst = os.path.join(scratch, rel)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copyfile(src, dst)
        restored[rel] = dst
    sha_ok = all(
        sha256_file(restored[rel]) == manifest["files"][rel]["sha256"]
        for rel in manifest["files"])
    check("restore_sha_matches_manifest", sha_ok,
          "files=%d" % len(manifest["files"]))

    # ---- 2/3. DBs open with matching counts ----
    for name in ["pool.db", "probe.db"]:
        try:
            counts = db_counts(restored[name], read_only=False)
            check("%s_opens_counts_match" % name,
                  counts == manifest["counts"][name],
                  str(counts))
        except Exception as e:  # noqa: BLE001
            check("%s_opens_counts_match" % name, False,
                  "%s: %s" % (type(e).__name__, e))

    # ---- 4. publish file parses like the manifest ----
    pool_db = restored["pool.db"]
    con = sqlite3.connect(pool_db)
    try:
        pinned = {(r[0], r[1], r[2]) for r in con.execute(
            "SELECT protocol,host,port FROM pinned")}
        blocked = {(r[0], r[1], r[2]) for r in con.execute(
            "SELECT protocol,host,port FROM blocklist")}
    finally:
        con.close()
    parsed = parse_subscription(restored["publish/pool-new.txt"],
                                pinned, blocked)
    check("publish_parses_like_manifest",
          parsed == manifest["counts"]["publish_file"], str(parsed))

    # ---- 5. config.yaml keys ----
    def top_keys(path):
        keys = []
        with open(path) as f:
            for line in f:
                s = line.strip()
                if s and not s.startswith("#") and ":" in s \
                        and not line.startswith(" "):
                    keys.append(s.split(":")[0].strip())
        return keys

    live_cfg = "/opt/free-node-program/config.yaml"
    check("config_keys_match_live",
          top_keys(restored["config.yaml"]) == top_keys(live_cfg),
          "keys=%d" % len(top_keys(restored["config.yaml"])))

    # ---- 6. gate dry-run consistency (restored vs live copy) ----
    fix = os.path.join(args.code_dir, "fixtures")
    record_path = os.path.join(fix, "native_results_fixture.json")
    probe_db = restored["probe.db"]
    live_copy = os.path.join(scratch, "live-pool-new-copy.txt")
    shutil.copyfile("/opt/free-node-program/publish/pool-new.txt", live_copy)
    wd1 = os.path.join(scratch, "gate-wd-restored")
    wd2 = os.path.join(scratch, "gate-wd-live")
    os.makedirs(wd1, exist_ok=True)
    os.makedirs(wd2, exist_ok=True)
    rc1, err1 = gate_dry_run(args.code_dir, wd1,
                             restored["publish/pool-new.txt"],
                             record_path, probe_db)
    rc2, err2 = gate_dry_run(args.code_dir, wd2, live_copy,
                             record_path, probe_db)
    check("gate_dry_run_restored_equals_live",
          (rc1, err1) == (rc2, err2),
          "restored rc=%s err=%s | live rc=%s err=%s"
          % (rc1, err1, rc2, err2))
    check("gate_dry_run_expected_refusal",
          rc1 == 1 and err1 == "phone_gate_zero_qualified",
          "rc=%s err=%s (diag reasons carry native_version_mismatch)"
          % (rc1, err1))

    # ---- 7. pre-existing p1p3 backup (read-only) ----
    p1p3_db = os.path.join(P1P3, "pool.db")
    p1p3_sub = os.path.join(P1P3, "pool-new.txt.47")
    age_h = None
    try:
        age_h = round((time.time()
                       - os.path.getmtime(p1p3_db)) / 3600, 1)
    except OSError:
        pass
    try:
        counts = db_counts(p1p3_db, read_only=True)
        check("p1p3_pool_db_opens", True,
              "age_h=%s tables=%d nodes=%s pinned=%s"
              % (age_h, len(counts), counts.get("nodes"),
                 counts.get("pinned")))
    except Exception as e:  # noqa: BLE001
        check("p1p3_pool_db_opens", False, "%s: %s" % (type(e).__name__, e))
    try:
        lines = [l for l in open(p1p3_sub, encoding="utf-8") if l.strip()]
        check("p1p3_subscription_parses", len(lines) > 0,
              "lines=%d age_h=%s" % (len(lines), age_h))
    except Exception as e:  # noqa: BLE001
        check("p1p3_subscription_parses", False,
              "%s: %s" % (type(e).__name__, e))
    has_manifest = os.path.exists(os.path.join(P1P3, "manifest.json")) or \
        os.path.exists(os.path.join(P1P3, "checksums.txt"))
    check("p1p3_has_manifest", has_manifest,
          "manifest_or_checksums_present=%s (expected False: no self-check)"
          % has_manifest)

    ok = all(c["ok"] for c in checks
             if c["check"] != "p1p3_has_manifest")
    log = {"drill": "backup_restore", "snapshot": snap,
           "checks": checks,
           "passed": sum(1 for c in checks if c["ok"]),
           "total": len(checks), "ok": ok,
           "note": "p1p3_has_manifest is informational, not a pass/fail "
                   "gate: the old backup has no manifest by construction."}
    print(json.dumps(log, indent=1, ensure_ascii=False))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
