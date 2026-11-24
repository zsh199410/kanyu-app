#!/usr/bin/env python3
"""N2 持久禁入回填：把 2026-11-21 历史清退的 25 条三元组写进 blocklist。

只用标准库，不依赖 live pool 包，可在隔离环境独立运行。

用法（默认只读）：
  python3 backfill_blocklist.py --db <pool.db> --audit blocklist_backfill_20261121.json --dry-run
  python3 backfill_blocklist.py --db <pool.db> --audit <json> --check
  python3 backfill_blocklist.py --db <pool.db> --audit <json> --apply --backup <backup.db> --by <操作者标识>

规则：
- 默认 --dry-run：只读核对，逐条输出审计状态，不写库。
- --check：只读验证回填完整性（25 条全在且 reason 一致才 exit 0）。
- --apply：先只读预检（冲突即拒绝，不备份、不写库），再把库文件完整
  复制到 --backup（SHA-256 校验一致），最后在一个事务内写 blocklist
  + audit 行；任一步失败即回滚，备份文件保留。
  幂等：重跑只插入缺失行（INSERT OR IGNORE + rowcount 守卫 audit 行）。
- 生产库写入不在默认许可内：--db 指向 live 路径
  /opt/free-node-program/data/pool.db 时，必须显式传 --allow-live，
  且仍须 --backup 与 --by；否则拒绝。
- 不删 nodes 或 node_tests；只增 blocklist + audit 行。
- audit 行写入沿用 db.log_audit 的行格式（at/actor/action/detail），
  但不用 log_audit() 本身（它每次调用即 commit，会破坏单事务原子性）。
  注意：audit 表受既有 30 天保留策略（db.prune_old）约束，长期审计
  依据以本 JSON 文件 + prune-ledger.jsonl 为准。
"""

import argparse
import hashlib
import json
import shutil
import sqlite3
import sys
import time

LIVE_DB_PATH = "/opt/free-node-program/data/pool.db"
REASON = "phone-fail-20261121"
PROTOCOLS = ("ss", "trojan", "vmess")
AUDIT_ACTION = "blocklist-backfill"
BACKFILL_ID = "i03-20261121"


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def load_audit(path):
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
    entries = data.get("entries")
    if not isinstance(entries, list) or not entries:
        raise ValueError("audit file has no entries list")
    if data.get("reason") != REASON:
        raise ValueError("audit reason != %s" % REASON)
    seen = set()
    for e in entries:
        for field in ("name", "protocol", "host", "port", "deleted_at_utc",
                      "mechanism", "verdict", "phone_fail_count"):
            if field not in e:
                raise ValueError("entry missing field %s: %r" % (field, e))
        if e["protocol"] not in PROTOCOLS:
            raise ValueError("bad protocol: %r" % e)
        if not isinstance(e["port"], int) or not 1 <= e["port"] <= 65535:
            raise ValueError("bad port: %r" % e)
        key = (e["protocol"], e["host"], e["port"])
        if key in seen:
            raise ValueError("duplicate triple in audit file: %r" % (key,))
        seen.add(key)
    return data, entries


def audit_db(db_path, entries):
    """只读核对：返回 [(entry, status, detail)]，status ∈ present/absent/conflict。"""
    conn = sqlite3.connect("file:%s?mode=ro" % db_path, uri=True)
    try:
        out = []
        for e in entries:
            row = conn.execute(
                "SELECT reason, created, by FROM blocklist "
                "WHERE protocol=? AND host=? AND port=?",
                (e["protocol"], e["host"], e["port"])).fetchone()
            if row is None:
                out.append((e, "absent", ""))
            elif row[0] != REASON:
                out.append((e, "conflict",
                            "existing reason=%r (want %r)" % (row[0], REASON)))
            else:
                out.append((e, "present",
                            "created=%s by=%s" % (row[1], row[2])))
        return out
    finally:
        conn.close()


def print_audit(rows):
    n_present = n_absent = n_conflict = 0
    for e, status, detail in rows:
        if status == "present":
            n_present += 1
        elif status == "absent":
            n_absent += 1
        else:
            n_conflict += 1
        print("%-10s %-7s %-22s:%-5d %-10s %s" % (
            e["name"], e["protocol"], e["host"], e["port"], status, detail))
    print("summary: present=%d absent=%d conflict=%d total=%d"
          % (n_present, n_absent, n_conflict, len(rows)))
    return n_present, n_absent, n_conflict


def cmd_dry_run(db_path, entries):
    rows = audit_db(db_path, entries)
    _p, _a, n_conflict = print_audit(rows)
    if n_conflict:
        print("FAIL-CLOSED: %d conflict(s); refusing to proceed" % n_conflict)
        return 1
    return 0


def cmd_check(db_path, entries):
    rows = audit_db(db_path, entries)
    _p, n_absent, n_conflict = print_audit(rows)
    if n_conflict or n_absent:
        print("CHECK FAILED: absent=%d conflict=%d" % (n_absent, n_conflict))
        return 1
    print("CHECK OK: all %d entries present with reason %s"
          % (len(entries), REASON))
    return 0


def cmd_apply(db_path, entries, backup_path, by):
    if db_path == LIVE_DB_PATH and not ARGS.allow_live:
        print("REFUSED: %s is the live database; pass --allow-live "
              "explicitly (production write still needs user authorization)"
              % LIVE_DB_PATH)
        return 2
    if not backup_path:
        print("--apply requires --backup <path>")
        return 2
    if not by:
        print("--apply requires --by <operator id>")
        return 2
    # 1) 只读预检：冲突则拒绝，不备份、不写库。
    rows = audit_db(db_path, entries)
    _p, _a, n_conflict = print_audit(rows)
    if n_conflict:
        print("FAIL-CLOSED: %d conflict(s); no backup, no writes" % n_conflict)
        return 1
    # 2) 再备份并校验：备份文件字节必须与源库一致。
    shutil.copy2(db_path, backup_path)
    if sha256_file(db_path) != sha256_file(backup_path):
        print("BACKUP FAILED: sha256 mismatch; aborting before any write")
        return 1
    print("backup ok: %s sha256=%s" % (backup_path, sha256_file(backup_path)[:16]))
    # 3) 单事务写入：blocklist + audit 行；任一失败回滚。
    conn = sqlite3.connect(db_path)
    try:
        conn.execute("BEGIN IMMEDIATE")
        now = int(time.time())
        inserted = 0
        for e in rows:
            entry, status, _d = e
            cur = conn.execute(
                "INSERT OR IGNORE INTO blocklist "
                "(protocol, host, port, reason, created, by) "
                "VALUES (?, ?, ?, ?, ?, ?)",
                (entry["protocol"], entry["host"], entry["port"],
                 REASON, now, by))
            if cur.rowcount == 1:
                inserted += 1
                detail = {
                    "backfill_id": BACKFILL_ID,
                    "reason": REASON,
                    "name": entry["name"],
                    "deleted_at_utc": entry["deleted_at_utc"],
                    "mechanism": entry["mechanism"],
                    "verdict": entry["verdict"],
                    "decision_ref": entry.get("decision_ref"),
                    "phone_fail_count": entry["phone_fail_count"],
                    "first_fail_ts": entry.get("first_fail_ts"),
                    "evidence": entry.get("evidence"),
                }
                conn.execute(
                    "INSERT INTO audit (at, actor, action, detail) "
                    "VALUES (?, ?, ?, ?)",
                    (now, by, AUDIT_ACTION,
                     json.dumps(detail, ensure_ascii=False)))
        conn.commit()
    except Exception as exc:  # noqa: BLE001 - fail-closed, report and exit 1
        conn.rollback()
        print("APPLY FAILED, rolled back: %r (backup kept at %s)"
              % (exc, backup_path))
        return 1
    finally:
        conn.close()
    # 4) 写后验证：25 条全在且 reason 一致。
    rows2 = audit_db(db_path, entries)
    _p2, n_absent2, n_conflict2 = print_audit(rows2)
    if n_absent2 or n_conflict2:
        print("POST-CHECK FAILED: absent=%d conflict=%d; backup at %s"
              % (n_absent2, n_conflict2, backup_path))
        return 1
    print("APPLY OK: inserted=%d skipped=%d total=%d (idempotent re-run "
          "inserts 0)" % (inserted, len(entries) - inserted, len(entries)))
    return 0


def main(argv=None):
    global ARGS
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--db", required=True, help="pool.db path")
    ap.add_argument("--audit", required=True, help="audit JSON path")
    ap.add_argument("--by", default=None,
                    help="operator id recorded in blocklist.by / audit.actor "
                         "(required for --apply)")
    ap.add_argument("--backup", default=None,
                    help="backup file path (required for --apply)")
    ap.add_argument("--allow-live", action="store_true",
                    help="explicitly allow operating on the live DB path")
    mode = ap.add_mutually_exclusive_group()
    mode.add_argument("--dry-run", action="store_true", default=True,
                      help="read-only audit (default)")
    mode.add_argument("--check", action="store_true",
                      help="read-only completeness check")
    mode.add_argument("--apply", action="store_true",
                      help="write blocklist + audit rows in one transaction")
    ARGS = ap.parse_args(argv)
    try:
        _data, entries = load_audit(ARGS.audit)
    except (OSError, ValueError) as exc:
        print("AUDIT FILE INVALID: %r" % (exc,))
        return 2
    if ARGS.check:
        return cmd_check(ARGS.db, entries)
    if ARGS.apply:
        return cmd_apply(ARGS.db, entries, ARGS.backup, ARGS.by)
    return cmd_dry_run(ARGS.db, entries)


def run(argv=None):
    try:
        return main(argv)
    except sqlite3.Error as exc:
        print("DB ERROR: %r" % (exc,))
        return 2
    except OSError as exc:
        print("IO ERROR: %r" % (exc,))
        return 2


if __name__ == "__main__":
    sys.exit(run())
