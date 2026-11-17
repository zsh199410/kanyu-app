#!/usr/bin/env python3
"""Consistent SQLite backup of the live probe DB (GPT #6940445042 P0-4).

The service runs with PRAGMA journal_mode=WAL: a plain `cp probe.db`
can miss commits still sitting in probe.db-wal that have not been
checkpointed, so a file copy is NOT a reliable backup of a live WAL
database. This tool uses the SQLite backup API
(sqlite3.Connection.backup), which copies a transactionally consistent
snapshot INCLUDING un-checkpointed WAL content, then runs
PRAGMA integrity_check on the snapshot and prints its SHA256.
Exit non-zero on any failure (missing source, backup error, or a
failed integrity check).

Usage: python3 tools/backup_db.py <source.db> <dest.db>
Stdlib only.
"""
import hashlib
import os
import sqlite3
import sys


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def backup_db(src_path, dst_path):
    """Return (dest_sha256, integrity_ok). Raises on any failure."""
    if not os.path.isfile(src_path):
        raise FileNotFoundError(f"source DB not found: {src_path}")
    if os.path.abspath(src_path) == os.path.abspath(dst_path):
        raise ValueError("source and destination must differ")
    if os.path.exists(dst_path):
        os.remove(dst_path)
    src = sqlite3.connect(src_path, timeout=30)
    try:
        dst = sqlite3.connect(dst_path, timeout=30)
        try:
            src.backup(dst)
        finally:
            dst.close()
    finally:
        src.close()
    # The snapshot must stand alone as a plain file: drop WAL mode so
    # it never depends on a -wal sidecar that is not part of the backup.
    chk = sqlite3.connect(dst_path, timeout=30)
    try:
        chk.execute("PRAGMA journal_mode=DELETE")
        row = chk.execute("PRAGMA integrity_check").fetchone()
        ok = row is not None and row[0] == "ok"
    finally:
        chk.close()
    if not ok:
        raise RuntimeError(f"integrity_check failed on snapshot: {dst_path}")
    return sha256_file(dst_path), True


def main(argv):
    if len(argv) != 3:
        print(__doc__.strip().splitlines()[-1], file=sys.stderr)
        return 2
    try:
        sha, _ok = backup_db(argv[1], argv[2])
    except Exception as e:
        print(f"backup FAILED: {e}", file=sys.stderr)
        return 1
    print(f"backup ok: {argv[2]} sha256={sha} integrity_check=ok")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
