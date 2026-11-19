#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""D4 independent pre-cutover snapshot, with read-only source operations.

Default --check touches NO files. Explicit --capture writes ONLY to a
new, private snapshot directory under an operator-supplied backup root,
never to served, staging, legacy pool DB or systemd. The source pool must
be byte-identical on both paths and stable across repeated reads.
--verify runs an intentionally corrupted recovery drill in a TEMP dir,
never writes live pool. Do NOT consider this a systemd recovery drill.

No node lines, credentials, IPs or full configuration contents on stdout.
Never install or enable the new publisher in this script.
"""
from __future__ import annotations
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import uuid
from urllib.parse import quote

UNITS = (
    "pool-publish.timer", "pool-sync.timer",
    "pool-crawl.timer", "pool-test.timer", "pool-test-full.timer",
    "pool-publish.service", "pool-sync.service",
)
PROPS = ("LoadState", "UnitFileState", "ActiveState", "SubState",
         "MainPID", "ControlPID", "Job", "Result")
MAX_POOL_BYTES = 2 * 1024 * 1024


class SnapshotRefused(ValueError):
    pass


def _check_file(path):
    p = Path(path)
    if not p.is_absolute() or p.is_symlink() or not p.is_file():
        raise SnapshotRefused("unsafe_source_path")
    return p


def _stable_read(path):
    p = _check_file(path)
    stat_before = p.stat()
    if not 0 < stat_before.st_size <= MAX_POOL_BYTES:
        raise SnapshotRefused("pool_size_out_of_range")
    # O_NOFOLLOW stops symlink substitution after the pre-stat check.
    flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
    fd = os.open(p, flags)
    try:
        actual = os.fstat(fd)
        if ((stat_before.st_dev, stat_before.st_ino) !=
                (actual.st_dev, actual.st_ino)):
            raise SnapshotRefused("pool_inode_changed_during_read")
        data = os.read(fd, MAX_POOL_BYTES + 1)
        if (len(data) != actual.st_size or
                actual.st_size > MAX_POOL_BYTES):
            raise SnapshotRefused("pool_read_incomplete")
        after = os.fstat(fd)
        if (after.st_mtime_ns != actual.st_mtime_ns or
                after.st_size != actual.st_size):
            raise SnapshotRefused("pool_modified_during_read")
    finally:
        os.close(fd)
    return data


def _sha(data):
    return hashlib.sha256(data).hexdigest()


def pool_state(served_path, staging_path):
    served = _stable_read(served_path)
    staging = _stable_read(staging_path)
    if served != staging:
        raise SnapshotRefused("served_staging_not_identical")
    # Detect legacy refresh between reads; never snapshot mixed versions.
    if _stable_read(served_path) != served or _stable_read(staging_path) != staging:
        raise SnapshotRefused("pool_changed_during_snapshot")
    try:
        lines = [x for x in served.decode("utf-8").splitlines()
                 if x.strip() and not x.lstrip().startswith("#")]
    except UnicodeDecodeError as exc:
        raise SnapshotRefused("invalid_pool_encoding") from exc
    names = [x.partition("=")[0].strip() for x in lines]
    if not lines or any("=" not in x or not n for x,n in zip(lines,names)):
        raise SnapshotRefused("invalid_proxy_lines")
    if len(names) != len(set(names)):
        raise SnapshotRefused("duplicate_proxy_names")
    return served, {
        "sha256": _sha(served), "line_count": len(lines),
        "byte_length": len(served), "served_staging_equal": True,
    }


def read_unit_states(*, runner=subprocess.run):
    result = {}
    for unit in UNITS:
        cmd = ["/usr/bin/systemctl", "show", "--no-pager",
               "--property=" + ",".join(PROPS), unit]
        response = runner(cmd, capture_output=True, text=True,
                          timeout=8, check=False)
        if response.returncode != 0:
            raise SnapshotRefused("systemctl_read_failed")
        pairs = {}
        for line in response.stdout.splitlines():
            if "=" in line:
                k,v = line.split("=",1)
                if k in PROPS:
                    pairs[k]=v.strip()
        if not all(x in pairs for x in ("LoadState","UnitFileState","ActiveState")):
            raise SnapshotRefused("systemctl_metadata_incomplete")
        result[unit]=pairs
    return result


def read_db_backup(source, destination):
    """SQLite online backup into a new PRIVATE file, source read-only."""
    p=_check_file(source)
    uri = "file:" + quote(str(p.resolve()), safe="/") + "?mode=ro"
    conn = sqlite3.connect(uri, uri=True, timeout=5)
    copy = None
    try:
        conn.execute("PRAGMA query_only=ON")
        copy = sqlite3.connect(str(destination), timeout=10)
        conn.backup(copy, pages=128, sleep=0.1)
        if copy.execute("PRAGMA quick_check").fetchone()[0] != "ok":
            raise SnapshotRefused("db_backup_integrity_failed")
        copy.commit()
    finally:
        if copy is not None:
            copy.close()
        conn.close()
    os.chmod(destination, 0o600)
    return _hash_file(destination)


def _hash_file(path):
    h=hashlib.sha256()
    with open(path, "rb") as f:
        for b in iter(lambda:f.read(1024*1024), b""):
            h.update(b)
    return h.hexdigest()


def _write_new(path, content):
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "wb") as out:
        out.write(content)
        out.flush()
        os.fsync(out.fileno())


def capture(*, served_path, staging_path, db_path, backup_root,
            unit_reader=read_unit_states):
    """Explicit snapshot only. Never modifies the VPS original paths."""
    root=Path(backup_root)
    if (not root.is_absolute() or root.is_symlink() or not root.is_dir()
            or root.resolve() in (Path("/tmp"),Path("/var/tmp"),Path("/"))):
        raise SnapshotRefused("unsafe_backup_root")
    if os.stat(root).st_mode & 0o077:
        raise SnapshotRefused("backup_root_not_private")
    pool, facts=pool_state(served_path,staging_path)
    states=unit_reader()
    stamp=datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    target=root/("d4-"+stamp+"-"+uuid.uuid4().hex[:12])
    target.mkdir(mode=0o700)
    try:
        _write_new(target/"served.bin",pool)
        _write_new(target/"staging.bin",pool)
        db_sha=read_db_backup(db_path,target/"pool.sqlite3")
        if pool_state(served_path,staging_path)[0] != pool:
            raise SnapshotRefused("source_changed_after_db_backup")
        doc={
            "schema":1,"captured_utc":datetime.now(timezone.utc).isoformat(),
            "pool": facts, "db_snapshot_sha256":db_sha,
            "unit_states":states,"original_paths":{
                "served":str(served_path),"staging":str(staging_path),
                "db":str(db_path)},
            "rollback_mode":"MANUAL_RESTORE_AFTER_STOP_WRITERS",
            "production_mutated":False,
        }
        _write_new(target/"manifest.json",json.dumps(doc,sort_keys=True,
                         ensure_ascii=True,indent=2).encode("utf-8"))
        # Not a replacement for off-host backup or filesystem immutable bit:
        # files mode0400 prevents accidental overwrite by normal processes.
        for f in target.iterdir():
            f.chmod(0o400)
        target.chmod(0o500)
        return target, facts
    except BaseException:
        shutil.rmtree(target, ignore_errors=True)
        raise


def verify(snapshot):
    """Purely local recovery drill into a temporary directory."""
    p=Path(snapshot)
    if not p.is_absolute() or p.is_symlink() or not p.is_dir():
        raise SnapshotRefused("snapshot_not_found")
    m=json.loads((p/"manifest.json").read_text(encoding="utf-8"))
    if m.get("schema")!=1 or m.get("production_mutated") is not False:
        raise SnapshotRefused("invalid_manifest")
    original=(p/"served.bin").read_bytes()
    stage=(p/"staging.bin").read_bytes()
    expected=m["pool"]["sha256"]
    if original!=stage or _sha(original)!=expected:
        raise SnapshotRefused("pool_snapshot_sha_mismatch")
    if _hash_file(p/"pool.sqlite3")!=m["db_snapshot_sha256"]:
        raise SnapshotRefused("db_snapshot_sha_mismatch")
    with tempfile.TemporaryDirectory(prefix="d4-restore-drill-") as d:
        a,b=Path(d)/"served",Path(d)/"staging"
        a.write_bytes(b"CORRUPTED")
        b.write_bytes(b"DIFFERENT")
        shutil.copyfile(p/"served.bin",a)
        shutil.copyfile(p/"staging.bin",b)
        if a.read_bytes()!=original or b.read_bytes()!=original:
            raise SnapshotRefused("isolation_restore_failed")
    return {
        "snapshot_verified":True,"isolation_restore_drill":True,
        "db_backup_verified":True,"pool_sha_prefix":expected[:12],
        "pool_line_count":m["pool"]["line_count"],
        "production_mutated":False,
        "production_systemd_restored":False,
    }


def main(argv=None):
    parser=argparse.ArgumentParser()
    mode=parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--check",action="store_true")
    mode.add_argument("--capture",action="store_true")
    mode.add_argument("--verify",metavar="SNAPSHOT_DIR")
    parser.add_argument("--served")
    parser.add_argument("--staging")
    parser.add_argument("--db")
    parser.add_argument("--backup-root")
    args=parser.parse_args(argv)
    try:
        if args.verify:
            data=verify(args.verify)
        elif args.check:
            if not args.served or not args.staging:
                raise SnapshotRefused("missing_pool_paths")
            _pool,data=pool_state(args.served,args.staging)
            data={**data,"decision":"READ_ONLY_D4_BASELINE",
                  "production_mutated":False}
        else:
            if not all((args.served,args.staging,args.db,args.backup_root)):
                raise SnapshotRefused("missing_backup_arguments")
            path, facts = capture(served_path=args.served,
                staging_path=args.staging,db_path=args.db,
                backup_root=args.backup_root)
            data={"snapshot_dir":str(path),"pool_sha_prefix":facts["sha256"][:12],
                  "pool_line_count":facts["line_count"],
                  "decision":"INDEPENDENT_SNAPSHOT_CREATED",
                  "production_mutated":False}
    except (OSError,SnapshotRefused,ValueError,sqlite3.Error,
            subprocess.TimeoutExpired,KeyError,TypeError):
        print('{"ok":false,"decision":"D4_SNAPSHOT_BLOCKED"}')
        return 78
    print(json.dumps({"ok":True,**data},sort_keys=True))
    return 0


if __name__=="__main__":
    sys.exit(main())
