#!/usr/bin/env python3
"""N2 持久禁入回填：把 2026-11-21 历史清退的 25 条三元组写进 blocklist。

只用标准库，不依赖 live pool 包，可在隔离环境独立运行。

用法（默认只读）：
  python3 backfill_blocklist.py --db <pool.db> --audit blocklist_backfill_20261121.json --dry-run
  python3 backfill_blocklist.py --db <pool.db> --audit <json> --check
  python3 backfill_blocklist.py --db <pool.db> --audit <json> --apply --backup <backup.db> --by <操作者标识>

规则：
- 默认 --dry-run：只读核对，逐条输出审计状态，不写库。
- --check：只读验证回填完整性（25 条全在且逐条 reason 一致才 exit 0）。
- --apply：只读预检（冲突即拒绝，不备份、不写库）→ Backup API 备份
  （含已提交 WAL 数据，独占新建 0600 文件，校验 integrity 与逻辑内容）
  → 单事务写 blocklist + audit 行（事务内重核对 + commit 前验证，
  任一步失败回滚）→ 写后验证；同时向决策日志追加一条不可变运行记录。
  幂等：重跑只插入缺失行。
- 逐条 reason（v2 更正，GPT Review 6033772552）：DELETE_OVER_TARGET
  的 8 条是容量裁剪，reason 为 over-target-20261121，不是手机死亡
  证据；其余 17 条为 phone-fail-20261121。两类都保持禁入（保守禁入），
  但不得混淆事实、不得把回填覆盖成更严格原因；原始 mechanism /
  verdict / 真实 decision_ref 保留在审计文件里，null 不捏造。
- 生产库写入不在默认许可内：--db 指向 live 路径
  /opt/free-node-program/data/pool.db 时，必须显式传 --allow-live，
  且仍须 --backup 与 --by；否则拒绝。
- 不删 nodes 或 node_tests；只增 blocklist + audit 行。
- audit 行写入沿用 db.log_audit 的行格式（at/actor/action/detail），
  但不用 log_audit() 本身（它每次调用即 commit，会破坏单事务原子性）。
  注意：audit 表受既有 30 天保留策略（db.prune_old）约束；长期审计
  依据以本 JSON 文件 + 决策日志 + prune-ledger.jsonl 为准，绝不只依赖
  audit 表。
- 没有整库恢复路径：本脚本不提供任何 --restore / 覆盖写回命令；
  备份文件只供人工在独立审查后恢复，绝不由脚本自动覆盖现有库。
- 互斥说明：本脚本不做“探测有无其他写者”的瞬时检查（那不能代替
  互斥）；写序列化靠 SQLite BEGIN IMMEDIATE，live 跨进程写互斥由
  单写手纪律负责；Backup API 在并发写入下仍给出一致快照。
"""

import argparse
import hashlib
import json
import os
import sqlite3
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from blocklist_common import (  # noqa: E402
    REASON_OVER_TARGET,
    REASON_PHONE_FAIL,
    append_decision_log,
    reason_for_verdict,
    sqlite_backup,
)

LIVE_DB_PATH = "/opt/free-node-program/data/pool.db"
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
    """严格加载审计 JSON：逐条 reason 必须与 verdict 映射一致。"""
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
    entries = data.get("entries")
    if not isinstance(entries, list) or not entries:
        raise ValueError("audit file has no entries list")
    seen = set()
    for e in entries:
        for field in ("name", "protocol", "host", "port", "deleted_at_utc",
                      "mechanism", "verdict", "phone_fail_count", "reason"):
            if field not in e:
                raise ValueError("entry missing field %s: %r" % (field, e))
        if e["protocol"] not in PROTOCOLS:
            raise ValueError("bad protocol: %r" % e)
        if not isinstance(e["port"], int) or isinstance(e["port"], bool) \
                or not 1 <= e["port"] <= 65535:
            raise ValueError("bad port: %r" % e)
        want = reason_for_verdict(e["verdict"])
        if e["reason"] != want:
            raise ValueError(
                "entry reason %r != verdict %r mapping %r: %r"
                % (e["reason"], e["verdict"], want, e))
        key = (e["protocol"], e["host"], e["port"])
        if key in seen:
            raise ValueError("duplicate triple in audit file: %r" % (key,))
        seen.add(key)
    return data, entries


def audit_db(db_path, entries):
    """只读核对：返回 [(entry, status, detail)]，status ∈ present/absent/conflict。

    present 要求行存在且 reason 与该条逐条 reason 一致。
    """
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
            elif row[0] != e["reason"]:
                out.append((e, "conflict",
                            "existing reason=%r (want %r)"
                            % (row[0], e["reason"])))
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
        print("%-10s %-7s %-22s:%-5d %-10s %-22s %s" % (
            e["name"], e["protocol"], e["host"], e["port"], status,
            e["reason"], detail))
    print("summary: present=%d absent=%d conflict=%d total=%d"
          % (n_present, n_absent, n_conflict, len(rows)))
    return n_present, n_absent, n_conflict


def _verify_in_transaction(conn, entries):
    """事务内验证：25 条全在且逐条 reason 一致。返回 (ok, problems)。"""
    problems = []
    for e in entries:
        row = conn.execute(
            "SELECT reason FROM blocklist "
            "WHERE protocol=? AND host=? AND port=?",
            (e["protocol"], e["host"], e["port"])).fetchone()
        if row is None:
            problems.append("missing %s" % (e["name"],))
        elif row[0] != e["reason"]:
            problems.append("reason mismatch %s: %r != %r"
                            % (e["name"], row[0], e["reason"]))
    return (not problems, problems)


def apply_rows(conn, snapshot_rows, entries, by, now):
    """在已 BEGIN IMMEDIATE 的事务内执行回填写入（不 commit，由调用方决定）。

    snapshot_rows 是 BEGIN 之前的只读预检结果。事务内对每条重新核对：
    - 预检 absent、现已存在且 reason 一致 → 视为已写入，跳过插入与 audit
      （并发幂等，不重复写）；
    - 预检 absent、现已存在但 reason 不同 → 抛错（调用方回滚；绝不被
      INSERT OR IGNORE 悄悄吞掉）；
    - 预检 present、现 reason 已变 → 抛错（调用方回滚）。
    写入后在 commit 前再次验证全部 25 条与 audit 行数，失败抛错。
    返回 inserted 行数。
    """
    inserted = 0
    for entry, status, _d in snapshot_rows:
        row = conn.execute(
            "SELECT reason FROM blocklist "
            "WHERE protocol=? AND host=? AND port=?",
            (entry["protocol"], entry["host"], entry["port"])).fetchone()
        if row is not None:
            if row[0] != entry["reason"]:
                raise ValueError(
                    "in-transaction conflict for %s: existing reason=%r "
                    "(want %r); refusing to swallow with INSERT OR IGNORE"
                    % (entry["name"], row[0], entry["reason"]))
            continue  # 已存在且一致：并发幂等，跳过
        if status != "absent":
            raise ValueError(
                "in-transaction state changed for %s: snapshot=%s, now absent"
                % (entry["name"], status))
        cur = conn.execute(
            "INSERT INTO blocklist (protocol, host, port, reason, created, by) "
            "VALUES (?, ?, ?, ?, ?, ?)",
            (entry["protocol"], entry["host"], entry["port"],
             entry["reason"], now, by))
        if cur.rowcount != 1:
            raise RuntimeError("insert affected %d rows, want 1"
                               % cur.rowcount)
        inserted += 1
        detail = {
            "backfill_id": BACKFILL_ID,
            "reason": entry["reason"],
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
    ok, problems = _verify_in_transaction(conn, entries)
    if not ok:
        raise ValueError("in-transaction verification failed: %s" % problems)
    n_audit = conn.execute(
        "SELECT COUNT(*) FROM audit WHERE action=? AND at=? AND actor=?",
        (AUDIT_ACTION, now, by)).fetchone()[0]
    if n_audit != inserted:
        raise ValueError(
            "in-transaction audit count mismatch: wrote %d audit rows, "
            "inserted %d blocklist rows" % (n_audit, inserted))
    return inserted


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
    print("CHECK OK: all %d entries present with per-entry reasons "
          "(phone-fail=%d over-target=%d)"
          % (len(entries),
             sum(1 for e in entries if e["reason"] == REASON_PHONE_FAIL),
             sum(1 for e in entries if e["reason"] == REASON_OVER_TARGET)))
    return 0


def cmd_apply(db_path, entries, backup_path, by, decision_log=None):
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
    # 2) Backup API 备份（含已提交 WAL 数据），独占新建 0600 文件，
    #    校验 integrity 与逻辑内容；绝不覆盖已有文件。
    try:
        backup_sha = sqlite_backup(db_path, backup_path)
    except (OSError, ValueError, sqlite3.Error) as exc:
        print("BACKUP FAILED: %r; aborting before any write" % (exc,))
        return 1
    print("backup ok: %s sha256=%s" % (backup_path, backup_sha[:16]))
    # 3) 单事务写入：事务内重核对 + commit 前验证；任一失败回滚。
    conn = sqlite3.connect(db_path)
    inserted = 0
    try:
        conn.execute("BEGIN IMMEDIATE")
        now = int(time.time())
        inserted = apply_rows(conn, rows, entries, by, now)
        conn.commit()
    except Exception as exc:  # noqa: BLE001 - fail-closed, report and exit 1
        conn.rollback()
        print("APPLY FAILED, rolled back: %r (backup kept at %s)"
              % (exc, backup_path))
        return 1
    finally:
        conn.close()
    # 4) 写后验证：25 条全在且逐条 reason 一致。
    rows2 = audit_db(db_path, entries)
    _p2, n_absent2, n_conflict2 = print_audit(rows2)
    if n_absent2 or n_conflict2:
        print("POST-CHECK FAILED: absent=%d conflict=%d; backup at %s"
              % (n_absent2, n_conflict2, backup_path))
        return 1
    # 5) 不可变决策日志：运行记录只追加，永不截断；不只依赖 30 天 audit 表。
    if decision_log is None:
        decision_log = os.path.join(
            os.path.dirname(os.path.abspath(ARGS.audit)),
            "blocklist_decisions.jsonl")
    try:
        append_decision_log(decision_log, {
            "type": "blocklist-backfill",
            "backfill_id": BACKFILL_ID,
            "at": int(time.time()),
            "actor": by,
            "inserted": inserted,
            "skipped": len(entries) - inserted,
            "total": len(entries),
            "reasons": {
                REASON_PHONE_FAIL: sum(
                    1 for e in entries if e["reason"] == REASON_PHONE_FAIL),
                REASON_OVER_TARGET: sum(
                    1 for e in entries if e["reason"] == REASON_OVER_TARGET),
            },
            "backup_path": backup_path,
            "backup_sha256": backup_sha,
            "audit_json": os.path.abspath(ARGS.audit),
            "note": "over-target entries are capacity trimming, not "
                    "phone-death evidence; all 25 stay banned (conservative).",
        })
    except (OSError, ValueError) as exc:
        print("DECISION LOG FAILED: %r (blocklist already written; "
              "backup at %s; re-run --check to verify)"
              % (exc, backup_path))
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
    ap.add_argument("--decision-log", default=None,
                    help="append-only decision log path (default: "
                         "blocklist_decisions.jsonl next to the audit JSON)")
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
        return cmd_apply(ARGS.db, entries, ARGS.backup, ARGS.by,
                         decision_log=ARGS.decision_log)
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
