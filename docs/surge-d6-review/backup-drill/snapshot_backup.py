#!/usr/bin/env python3
"""D4 production backup snapshot (read-only on production).

Copies the live production state into an isolated snapshot dir with a
SHA manifest. DBs are copied with the SQLite backup API (WAL-safe);
files are plain copies. NOTHING is written to production paths.

The snapshot CONTAINS real subscription lines and credential files
(config/): it must stay on the VPS, dir 700, files 600. This script
prints ONLY counts and SHA prefixes -- never file contents.

Usage:
  snapshot_backup.py --out /opt/p2p3-d4/backup-drill/snapshot-<ts>
Exit 0 = snapshot complete and manifest written.
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

BASE = "/opt/free-node-program"
PROBE_DB = "/opt/probe-service/data/probe.db"
LINE_RE = re.compile(r"^\s*[^=]+=\s*([A-Za-z0-9_-]+)\s*,\s*([^,\s]+)\s*,\s*(\d+)")


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def backup_sqlite(src, dst):
    con = sqlite3.connect("file:%s?mode=ro" % src, uri=True)
    try:
        dest = sqlite3.connect(dst)
        try:
            con.backup(dest)
        finally:
            dest.close()
    finally:
        con.close()


def db_counts(path):
    con = sqlite3.connect("file:%s?mode=ro" % path, uri=True)
    try:
        tables = [r[0] for r in con.execute(
            "SELECT name FROM sqlite_master WHERE type='table'")]
        return {t: con.execute("SELECT COUNT(*) FROM %s" % t).fetchone()[0]
                for t in tables if t != "sqlite_sequence"}
    finally:
        con.close()


def parse_subscription(path):
    """Counts only: lines, pinned/rotation split by DB keys, unparsed."""
    con = sqlite3.connect("file:%s?mode=ro" % os.path.join(BASE, "data", "pool.db"),
                          uri=True)
    try:
        pinned = {(r[0], r[1], r[2]) for r in con.execute(
            "SELECT protocol,host,port FROM pinned")}
        blocked = {(r[0], r[1], r[2]) for r in con.execute(
            "SELECT protocol,host,port FROM blocklist")}
    finally:
        con.close()
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
            if key in blocked:
                n_blocked += 1
            elif key in pinned:
                n_pin += 1
            else:
                n_rot += 1
    return {"lines": total, "pinned": n_pin, "rotation": n_rot,
            "blocked": n_blocked, "unparsed": n_unparsed}


def main(argv=None):
    ap = argparse.ArgumentParser(description="D4 production snapshot")
    ap.add_argument("--out", required=True)
    args = ap.parse_args(argv)
    out = os.path.abspath(args.out)
    os.makedirs(out, mode=0o700, exist_ok=True)
    manifest = {"snapshot_at": int(time.time()),
                "snapshot_at_cst": time.strftime(
                    "%Y-%m-%d %H:%M:%S", time.localtime()),
                "files": {}, "counts": {}}
    # DBs via backup API.
    for src, name in [(os.path.join(BASE, "data", "pool.db"), "pool.db"),
                      (PROBE_DB, "probe.db")]:
        dst = os.path.join(out, name)
        backup_sqlite(src, dst)
        os.chmod(dst, 0o600)
        manifest["files"][name] = {"bytes": os.path.getsize(dst),
                                   "sha256": sha256_file(dst)}
        manifest["counts"][name] = db_counts(dst)
    # Plain file copies.
    copies = [
        ("publish/pool-new.txt", "publish/pool-new.txt"),
        ("publish/pool-new.txt.prev", "publish/pool-new.txt.prev"),
        ("config.yaml", "config.yaml"),
        ("pool-sync.sh", "pool-sync.sh"),
    ]
    for src_rel, dst_rel in copies:
        src = os.path.join(BASE, src_rel)
        dst = os.path.join(out, dst_rel)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copyfile(src, dst)
        os.chmod(dst, 0o600)
        manifest["files"][dst_rel] = {"bytes": os.path.getsize(dst),
                                      "sha256": sha256_file(dst)}
    # config/ dir (contains credential files -- 600, never printed).
    for root, _dirs, files in os.walk(os.path.join(BASE, "config")):
        for fn in files:
            src = os.path.join(root, fn)
            rel = os.path.relpath(src, BASE)
            dst = os.path.join(out, rel)
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            shutil.copyfile(src, dst)
            os.chmod(dst, 0o600)
            manifest["files"][rel] = {"bytes": os.path.getsize(dst),
                                      "sha256": sha256_file(dst)}
    # Units from both locations.
    for src in ([os.path.join(BASE, "systemd", f)
                 for f in sorted(os.listdir(os.path.join(BASE, "systemd")))]
                + ["/etc/systemd/system/pool-publish.service",
                   "/etc/systemd/system/pool-publish.timer",
                   "/etc/systemd/system/pool-sync.service",
                   "/etc/systemd/system/pool-sync.timer"]):
        if not os.path.isfile(src):
            continue
        rel = "units/" + os.path.basename(src)
        if src.startswith("/etc/"):
            rel = "units/etc-" + os.path.basename(src)
        else:
            rel = "units/prog-" + os.path.basename(src)
        dst = os.path.join(out, rel)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copyfile(src, dst)
        os.chmod(dst, 0o600)
        manifest["files"][rel] = {"bytes": os.path.getsize(dst),
                                  "sha256": sha256_file(dst)}
    # Live counts.
    manifest["counts"]["publish_file"] = parse_subscription(
        os.path.join(BASE, "publish/pool-new.txt"))
    manifest["counts"]["publish_prev"] = parse_subscription(
        os.path.join(BASE, "publish/pool-new.txt.prev"))
    r = subprocess.run(["systemctl", "list-timers", "pool-*", "--no-pager"],
                       capture_output=True, text=True, timeout=60)
    manifest["timers"] = (r.stdout + r.stderr).strip()
    with open(os.path.join(out, "manifest.json"), "w") as f:
        json.dump(manifest, f, indent=1, ensure_ascii=False)
    os.chmod(os.path.join(out, "manifest.json"), 0o600)
    summary = {
        "ok": True,
        "snapshot": out,
        "files": len(manifest["files"]),
        "pool_db_counts": manifest["counts"]["pool.db"],
        "probe_db_counts": manifest["counts"]["probe.db"],
        "publish_file": manifest["counts"]["publish_file"],
        "publish_sha_prefix":
            manifest["files"]["publish/pool-new.txt"]["sha256"][:12],
    }
    print(json.dumps(summary, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
