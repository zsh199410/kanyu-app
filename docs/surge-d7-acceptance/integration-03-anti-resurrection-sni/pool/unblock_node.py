#!/usr/bin/env python3
"""N2 解禁：从 blocklist 移除一条三元组（须独立审核与可追溯解除事件）。

只用标准库，不依赖 live pool 包，可在隔离环境独立运行。

用法：
  python3 unblock_node.py --db <pool.db> --protocol ss --host <h> --port <p> \
      --dry-run
  python3 unblock_node.py --db <pool.db> --protocol ss --host <h> --port <p> \
      --apply --backup <backup.db> --approved-by <审核者标识> \
      --decision-ref <裁决引用> --evidence <新鲜 VPS 与手机/控制证据引用>

规则（GPT 2026-11-24 三批裁决 N2）：
- 解禁必须精确身份（protocol/host/port 三元组）；不因重抓、改名、
  历史 pass 自动解禁——本脚本只接受显式人工调用，不设自动触发。
- 执行删除须 --approved-by + --decision-ref + --evidence 三者齐全；
  缺任一即拒绝（exit 2）。
- 只删 blocklist 行 + 写一条 audit 行（action=blocklist-unblock）；
  绝不删 nodes、node_tests 或既有 audit 历史；不设 --allow-data-loss。
- 若三元组同时在 rejected_nodes.json 里，拒绝（须先由 GPT 另行裁决
  将其移出拒绝清单；只解 blocklist 不能恢复候选资格）。
- 若三元组不在 blocklist 里，拒绝（无可解禁之物，fail-closed）。
- --apply 先备份（SHA-256 校验），再单事务执行删除 + 写 audit；
  任一步失败回滚，备份保留。
"""

import argparse
import hashlib
import json
import os
import shutil
import sqlite3
import sys
import time

AUDIT_ACTION = "blocklist-unblock"


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def load_rejected(path):
    if not path or not os.path.exists(path):
        return {}
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
    return {(e["protocol"], e["host"], e["port"]): e
            for e in data.get("entries", [])}


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
        rejected = load_rejected(rejected_path)
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

    if not args.approved_by or not args.decision_ref or not args.evidence:
        print("--apply requires --approved-by, --decision-ref and --evidence")
        return 2
    if not args.backup:
        print("--apply requires --backup <path>")
        return 2
    shutil.copy2(args.db, args.backup)
    if sha256_file(args.db) != sha256_file(args.backup):
        print("BACKUP FAILED: sha256 mismatch; aborting before any write")
        return 1
    print("backup ok: %s" % args.backup)
    try:
        conn = sqlite3.connect(args.db)
        conn.execute("BEGIN IMMEDIATE")
        now = int(time.time())
        cur = conn.execute(
            "DELETE FROM blocklist WHERE protocol=? AND host=? AND port=?",
            key)
        if cur.rowcount != 1:
            raise RuntimeError("delete affected %d rows, want 1"
                               % cur.rowcount)
        detail = {
            "removed_reason": row[0],
            "removed_created": row[1],
            "removed_by": row[2],
            "approved_by": args.approved_by,
            "decision_ref": args.decision_ref,
            "evidence": args.evidence,
        }
        conn.execute(
            "INSERT INTO audit (at, actor, action, detail) VALUES (?, ?, ?, ?)",
            (now, args.approved_by, AUDIT_ACTION,
             json.dumps(detail, ensure_ascii=False)))
        conn.commit()
    except Exception as exc:  # noqa: BLE001 - fail-closed, report and exit 1
        conn.rollback()
        print("UNBLOCK FAILED, rolled back: %r (backup kept at %s)"
              % (exc, args.backup))
        return 1
    finally:
        conn.close()
    conn = sqlite3.connect("file:%s?mode=ro" % args.db, uri=True)
    gone = conn.execute(
        "SELECT COUNT(*) FROM blocklist "
        "WHERE protocol=? AND host=? AND port=?", key).fetchone()[0]
    conn.close()
    if gone:
        print("POST-CHECK FAILED: row still present; backup at %s"
              % args.backup)
        return 1
    print("UNBLOCK OK: %s removed from blocklist; audit row written "
          "(action=%s)" % (key, AUDIT_ACTION))
    return 0


if __name__ == "__main__":
    sys.exit(main())
