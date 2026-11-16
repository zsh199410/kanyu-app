#!/usr/bin/env python3
"""D5 synthetic snapshot (adapted from D4 snapshot_backup.py logic).

Takes a SYNTHETIC live tree (built by drills/backup_restore_drill.py)
and snapshots it into a dir with a SHA manifest. DBs are copied with
the SQLite backup API (WAL-safe); files are plain copies. NOTHING here
touches production paths: --src must be an isolation root, and this
script refuses any src that is not under the drill work root.

All data is synthetic: TEST-NET 192.0.2.x, fake password
TEST-ONLY-NOT-A-REAL-NODE. Stdout prints ONLY counts and SHA prefixes.

Usage:
  snapshot_backup_d5.py --src <synthetic live root> --out <snapshot dir>
Exit 0 = snapshot complete and manifest written.
"""
import argparse
import hashlib
import json
import os
import re
import shutil
import sqlite3
import sys
import time
from datetime import datetime
from zoneinfo import ZoneInfo

CST = ZoneInfo("Asia/Shanghai")

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


def parse_subscription(path, pool_db):
    con = sqlite3.connect("file:%s?mode=ro" % pool_db, uri=True)
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


def _clean_sidecars(path):
    """Remove -wal/-shm left behind by a verification open of a WAL
    DB. A read-only open creates a 0-byte -wal + 32KB -shm next to the
    DB (D4 finding); the snapshot dir must match its manifest exactly,
    so sidecars are deleted right after every verification read.
    Returns the number of files removed."""
    n = 0
    for suf in ("-wal", "-shm"):
        p = path + suf
        if os.path.exists(p):
            os.remove(p)
            n += 1
    return n


def _record(manifest, out, dst_rel):
    dst = os.path.join(out, dst_rel)
    os.chmod(dst, 0o600)
    manifest["files"][dst_rel] = {"bytes": os.path.getsize(dst),
                                  "sha256": sha256_file(dst)}


def main(argv=None):
    ap = argparse.ArgumentParser(description="D5 synthetic snapshot")
    ap.add_argument("--src", required=True,
                    help="synthetic live root (isolation only)")
    ap.add_argument("--out", required=True)
    args = ap.parse_args(argv)
    src = os.path.abspath(args.src)
    out = os.path.abspath(args.out)
    if "/_d5_work/" not in src and not src.endswith("/_d5_work"):
        print(json.dumps({"ok": False,
                          "error": "src_not_isolation_root",
                          "src": src}))
        return 2
    os.makedirs(out, mode=0o700, exist_ok=True)
    manifest = {"snapshot_at": int(time.time()),
                "snapshot_at_cst": datetime.now(CST).strftime(
                    "%Y-%m-%d %H:%M:%S"),
                "synthetic": True,
                "files": {}, "counts": {}}
    pool_db_src = os.path.join(src, "data", "pool.db")
    probe_db_src = os.path.join(src, "data", "probe.db")
    cleaned = 0
    for src_db, name in [(pool_db_src, "pool.db"),
                         (probe_db_src, "probe.db")]:
        dst = os.path.join(out, name)
        backup_sqlite(src_db, dst)
        _record(manifest, out, name)
        manifest["counts"][name] = db_counts(dst)
        cleaned += _clean_sidecars(dst)
    copies = [
        ("publish/pool-new.txt", "publish/pool-new.txt"),
        ("publish/pool-new.txt.prev", "publish/pool-new.txt.prev"),
        ("publish/history/pool-new-prev2.txt",
         "publish/history/pool-new-prev2.txt"),
        ("config.yaml", "config.yaml"),
        ("pool-sync.sh", "pool-sync.sh"),
    ]
    for src_rel, dst_rel in copies:
        s = os.path.join(src, src_rel)
        d = os.path.join(out, dst_rel)
        os.makedirs(os.path.dirname(d), exist_ok=True)
        shutil.copyfile(s, d)
        _record(manifest, out, dst_rel)
    for root, _dirs, files in os.walk(os.path.join(src, "config")):
        for fn in sorted(files):
            s = os.path.join(root, fn)
            rel = os.path.relpath(s, src)
            d = os.path.join(out, rel)
            os.makedirs(os.path.dirname(d), exist_ok=True)
            shutil.copyfile(s, d)
            _record(manifest, out, rel)
    for fn in sorted(os.listdir(os.path.join(src, "systemd"))):
        s = os.path.join(src, "systemd", fn)
        if not os.path.isfile(s):
            continue
        rel = "units/" + fn
        d = os.path.join(out, rel)
        os.makedirs(os.path.dirname(d), exist_ok=True)
        shutil.copyfile(s, d)
        _record(manifest, out, rel)
    manifest["counts"]["publish_file"] = parse_subscription(
        os.path.join(src, "publish", "pool-new.txt"), pool_db_src)
    manifest["counts"]["publish_prev"] = parse_subscription(
        os.path.join(src, "publish", "pool-new.txt.prev"), pool_db_src)
    manifest["units"] = sorted(os.listdir(os.path.join(src, "systemd")))
    # Final sweep: no -wal/-shm may remain anywhere in the snapshot.
    for r, _d, files in os.walk(out):
        for fn in files:
            if fn.endswith("-wal") or fn.endswith("-shm"):
                os.remove(os.path.join(r, fn))
                cleaned += 1
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
        "sidecars_cleaned": cleaned,
    }
    print(json.dumps(summary, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
