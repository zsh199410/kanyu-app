#!/usr/bin/env python3
"""N2 解禁：从 blocklist 移除一条三元组（须独立审核与可追溯解除事件）。

只用标准库，不依赖 live pool 包，可在隔离环境独立运行。

用法：
  python3 unblock_node.py --db <pool.db> --protocol ss --host <h> --port <p> \
      --dry-run
  python3 unblock_node.py --db <pool.db> --protocol ss --host <h> --port <p> \
      --apply --backup <backup.db> --approved-by <审核者标识> \
      --decision-ref <裁决引用> --evidence <新鲜 VPS 与手机/控制证据引用>

规则（GPT 2026-11-24 三批裁决 N2 + Review 6033772552 v2 收口）：
- v2：生产解禁写入路径暂时禁用（PRODUCTION_UNBLOCK_ENABLED = False）。
  --apply 一律拒绝（exit 2），不备份、不写库；仅保留隔离 dry-run /
  演练。未来重新启用须经独立审查的差异，绑定真实批准记录、精确配置
  变体的新鲜 VPS / 手机 / 控制证据及独立审核，保留同入口其他变体禁入；
  禁止用自填字符串充当凭证。--approved-by / --decision-ref /
  --evidence 三个字符串只是必填的引用字段，不是凭证本身。
- 解禁必须精确身份（protocol/host/port 三元组）；不因重抓、改名、
  历史 pass 自动解禁——本脚本只接受显式人工调用，不设自动触发。
- 执行删除须 --approved-by + --decision-ref + --evidence 三者齐全；
  缺任一即拒绝（exit 2）。
- 只删 blocklist 行 + 写一条 audit 行（action=blocklist-unblock）；
  绝不删 nodes、node_tests 或既有 audit 历史；不设 --allow-data-loss。
- 若三元组同时在 rejected_nodes.json 里，拒绝（须先由 GPT 另行裁决
  将其移出拒绝清单；只解 blocklist 不能恢复候选资格）。
- 若三元组不在 blocklist 里，拒绝（无可解禁之物，fail-closed）。
- rejected 清单加载严格 fail-closed（blocklist_common.load_rejected_strict）：
  文件缺失、entries 缺失/为空、重复、畸形、decision_ref 为空一律抛错，
  绝不悄悄返回空集放行。
- （未来启用时）--apply 先用 Backup API 备份，再在单事务内重核对
  原 blocklist 记录（reason/created/by 须与预读快照一致，否则回滚），
  再执行删除 + 写 audit；任一步失败回滚，备份保留。解除事件同时追加
  到不可变决策日志（只追加，永不截断；不只依赖 30 天清理的 audit 表），
  原回填决策记录永不删除。
- 没有整库恢复路径：本脚本不提供任何 --restore / 覆盖写回命令。
"""

import argparse
import json
import os
import sqlite3
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from blocklist_common import (  # noqa: E402
    append_decision_log,
    load_rejected_strict,
    sqlite_backup,
)

AUDIT_ACTION = "blocklist-unblock"

# v2：生产解禁写入路径暂时禁用。仅保留隔离 dry-run / 演练。
# 重新启用须经独立审查的差异，绑定真实批准记录、精确配置变体的新鲜
# VPS / 手机 / 控制证据及独立审核；禁止用自填字符串充当凭证。
PRODUCTION_UNBLOCK_ENABLED = False


def cmd_apply(db_path, key, snapshot, approved_by, decision_ref, evidence,
              backup_path, decision_log=None):
    """（未来启用时）在单事务内执行解禁；调用前须已核对生产路径已启用。

    snapshot 是 --apply 前只读预读的原 blocklist 行
    (reason, created, by)。事务内重新 SELECT 并与快照逐项比对，
    不一致即抛错（调用方回滚）；绝不只凭 BEGIN 前的快照删除。
    成功后向不可变决策日志追加一条解除记录（只追加，永不截断）。
    返回 0 成功；抛错由调用方回滚并返回 1。
    """
    try:
        backup_sha = sqlite_backup(db_path, backup_path)
    except (OSError, ValueError, sqlite3.Error) as exc:
        print("BACKUP FAILED: %r; aborting before any write" % (exc,))
        return 1
    print("backup ok: %s sha256=%s" % (backup_path, backup_sha[:16]))
    conn = sqlite3.connect(db_path)
    try:
        conn.execute("BEGIN IMMEDIATE")
        now = int(time.time())
        row = conn.execute(
            "SELECT reason, created, by FROM blocklist "
            "WHERE protocol=? AND host=? AND port=?", key).fetchone()
        if row is None:
            raise ValueError(
                "in-transaction state changed: %s no longer in blocklist"
                % (key,))
        if tuple(row) != tuple(snapshot):
            raise ValueError(
                "in-transaction conflict: blocklist row changed since "
                "pre-read (was %r, now %r); refusing to delete on a stale "
                "snapshot" % (tuple(snapshot), tuple(row)))
        cur = conn.execute(
            "DELETE FROM blocklist WHERE protocol=? AND host=? AND port=?",
            key)
        if cur.rowcount != 1:
            raise RuntimeError("delete affected %d rows, want 1"
                               % cur.rowcount)
        detail = {
            "removed_reason": snapshot[0],
            "removed_created": snapshot[1],
            "removed_by": snapshot[2],
            "approved_by": approved_by,
            "decision_ref": decision_ref,
            "evidence": evidence,
        }
        conn.execute(
            "INSERT INTO audit (at, actor, action, detail) VALUES (?, ?, ?, ?)",
            (now, approved_by, AUDIT_ACTION,
             json.dumps(detail, ensure_ascii=False)))
        # commit 前验证：行已删、audit 行已写。
        gone = conn.execute(
            "SELECT COUNT(*) FROM blocklist "
            "WHERE protocol=? AND host=? AND port=?", key).fetchone()[0]
        if gone:
            raise ValueError("in-transaction verification failed: row still "
                             "present before commit")
        n_audit = conn.execute(
            "SELECT COUNT(*) FROM audit WHERE action=? AND at=? AND actor=?",
            (AUDIT_ACTION, now, approved_by)).fetchone()[0]
        if n_audit != 1:
            raise ValueError(
                "in-transaction audit count mismatch: %d" % n_audit)
        conn.commit()
    except Exception as exc:  # noqa: BLE001 - fail-closed, report and exit 1
        conn.rollback()
        print("UNBLOCK FAILED, rolled back: %r (backup kept at %s)"
              % (exc, backup_path))
        return 1
    finally:
        conn.close()
    if decision_log is None:
        decision_log = os.path.join(
            os.path.dirname(os.path.abspath(__file__)),
            "blocklist_decisions.jsonl")
    try:
        append_decision_log(decision_log, {
            "type": "blocklist-unblock",
            "at": int(time.time()),
            "actor": approved_by,
            "triple": list(key),
            "removed_reason": snapshot[0],
            "removed_created": snapshot[1],
            "removed_by": snapshot[2],
            "decision_ref": decision_ref,
            "evidence": evidence,
            "backup_path": backup_path,
            "backup_sha256": backup_sha,
            "note": "original backfill decision record is preserved; "
                    "this unblock record never deletes history.",
        })
    except (OSError, ValueError) as exc:
        print("DECISION LOG FAILED: %r (blocklist row already deleted; "
              "backup at %s)" % (exc, backup_path))
        return 1
    print("UNBLOCK OK: %s removed from blocklist; audit row written "
          "(action=%s)" % (key, AUDIT_ACTION))
    return 0


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--db", required=True)
    ap.add_argument("--protocol", required=True, choices=("ss", "trojan", "vmess"))
    ap.add_argument("--host", required=True)
    ap.add_argument("--port", required=True, type=int)
    ap.add_argument("--rejected-file", default=None,
                    help="rejected_nodes.json path (default: pool/rejected_nodes.json)")
    ap.add_argument("--approved-by", default=None, help="审核者标识（--apply 必填）")
    ap.add_argument("--decision-ref", default=None, help="裁决引用（--apply 必填）")
    ap.add_argument("--evidence", default=None,
                    help="新鲜 VPS 与真实手机/控制证据引用（--apply 必填）")
    ap.add_argument("--backup", default=None, help="备份路径（--apply 必填）")
    ap.add_argument("--decision-log", default=None,
                    help="append-only decision log path (default: "
                         "blocklist_decisions.jsonl next to this script)")
    mode = ap.add_mutually_exclusive_group()
    mode.add_argument("--dry-run", action="store_true", default=True)
    mode.add_argument("--apply", action="store_true")
    args = ap.parse_args(argv)
    key = (args.protocol, args.host, args.port)

    rejected_path = args.rejected_file
    if rejected_path is None:
        rejected_path = os.path.join(os.path.dirname(__file__),
                                     "rejected_nodes.json")
    try:
        rejected = load_rejected_strict(rejected_path)
    except (OSError, ValueError) as exc:
        print("REJECTED FILE INVALID: %r" % (exc,))
        return 2
    if key in rejected:
        print("REFUSED: %s is in rejected_nodes.json (%s); unblocking "
              "blocklist alone does not restore candidacy — a separate GPT "
              "decision is required to remove it from the rejected list"
              % (key, rejected[key].get("decision_ref")))
        return 1

    try:
        conn = sqlite3.connect("file:%s?mode=ro" % args.db, uri=True)
        row = conn.execute(
            "SELECT reason, created, by FROM blocklist "
            "WHERE protocol=? AND host=? AND port=?", key).fetchone()
        conn.close()
    except sqlite3.Error as exc:
        print("DB ERROR: %r" % (exc,))
        return 2
    if row is None:
        print("REFUSED: %s is not in blocklist; nothing to unblock" % (key,))
        return 1
    print("blocklist row: reason=%s created=%s by=%s" % (row[0], row[1], row[2]))

    if not args.apply:
        print("DRY-RUN: would delete the blocklist row and write one audit "
              "row (action=%s); no writes performed" % AUDIT_ACTION)
        return 0

    # v2：生产解禁写入路径暂时禁用，仅保留隔离 dry-run / 演练。
    if not PRODUCTION_UNBLOCK_ENABLED:
        print("DISABLED: production unblock write path is disabled in this "
              "diff (isolation dry-run only). Re-enabling requires a "
              "separately reviewed diff binding a real approval record, "
              "fresh VPS/phone/control evidence for the exact config "
              "variant, and independent review; self-filled strings are "
              "not credentials.")
        return 2
    if not args.approved_by or not args.decision_ref or not args.evidence:
        print("--apply requires --approved-by, --decision-ref and --evidence")
        return 2
    if not args.backup:
        print("--apply requires --backup <path>")
        return 2
    return cmd_apply(args.db, key, tuple(row), args.approved_by,
                     args.decision_ref, args.evidence, args.backup,
                     decision_log=args.decision_log)


if __name__ == "__main__":
    sys.exit(main())
