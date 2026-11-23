"""向后兼容迁移：给 node_tests 加 8 个可空诊断列（v2，去掉 sb_err）。

幂等：PRAGMA table_info 后仅补缺失的列，已存在的列跳过；可重复执行。
旧记录原样保留，新列全部 NULL（不补造旧 curl exit/stage）。
不改任何现有列、不改索引、不改判活 SQL。

部署门禁（GPT #124 审查要求）：
- 迁移前做 WAL 一致备份（sqlite3 backup API），备份文件与本脚本同一目录；
- 迁移前后跑 integrity_check、行数、关键判活 SQL，结果必须相同；
- 部署顺序：停测试器 → 备份 → 迁移 schema → 部署补丁代码 → 验证 → 启动。
  旧版代码的位置 INSERT（7 值）不能在已迁移的 15 列库上运行（见 --compat-check
  的实测结果），因此 schema 与代码必须在同一停机窗口内一起部署，绝不能
  “先迁 schema、旧代码继续跑”；
- 回滚：恢复备份的 tester.py/db.py/cli.py，并用 --rollback 恢复迁移前
  DB 快照（或保留空列：新列可空，旧代码恢复后若库仍为 15 列则位置 INSERT
  仍会失败，故回滚必须同时恢复 DB 快照）。

用法：
  python3 migrate_diag_columns.py <db_path> [--backup-dir DIR] [--check] [--compat-check] [--rollback SNAPSHOT]
仅在隔离副本上运行验证；生产部署时在停机窗口内执行，绝不在测试器运行时改库。
"""
import argparse
import json
import os
import shutil
import sqlite3
import sys
import time

NEW_COLUMNS = [
    ("curl_exit", "INTEGER"),
    ("http_code", "TEXT"),
    ("stage", "TEXT"),
    ("stage_detail", "TEXT"),
    ("t_lookup_ms", "REAL"),
    ("t_connect_ms", "REAL"),
    ("t_appconnect_ms", "REAL"),
    ("t_total_ms", "REAL"),
]

LIVENESS_SQL = ("SELECT ms FROM node_tests WHERE protocol=? AND host=? AND port=? "
                "AND result='pass' ORDER BY tested_at DESC LIMIT 1")


def _columns(con):
    return {r[1]: {"type": r[2], "notnull": r[3]} for r in con.execute("PRAGMA table_info(node_tests)")}


def _integrity(con):
    row = con.execute("PRAGMA integrity_check").fetchone()
    return row[0] if row else "unknown"


def _liveness_snapshot(con, limit=50):
    keys = [tuple(r) for r in con.execute(
        "SELECT DISTINCT protocol, host, port FROM node_tests "
        "WHERE result='pass' ORDER BY tested_at DESC LIMIT ?", (limit,))]
    out = {}
    for k in keys:
        row = con.execute(LIVENESS_SQL, k).fetchone()
        out["|".join(map(str, k))] = row[0] if row else None
    return out


def _wal_backup(db_path, backup_dir):
    """WAL 一致备份（sqlite3 backup API），返回备份文件路径。"""
    os.makedirs(backup_dir, exist_ok=True)
    ts = time.strftime("%Y%m%dT%H%M%SZ", time.gmtime())
    dst = os.path.join(backup_dir, f"pool.db.pre-migration-{ts}")
    src = sqlite3.connect(db_path)
    dst_con = sqlite3.connect(dst)
    src.backup(dst_con)
    dst_con.close()
    src.close()
    return dst


def migrate(db_path, backup_dir=None):
    """执行迁移。返回报告 dict。先备份（若指定目录），再补列。"""
    report = {"db": db_path, "ts": int(time.time())}
    if backup_dir:
        report["backup"] = _wal_backup(db_path, backup_dir)
    con = sqlite3.connect(db_path)
    report["integrity_before"] = _integrity(con)
    report["rows_before"] = con.execute("SELECT COUNT(*) FROM node_tests").fetchone()[0]
    report["liveness_before"] = _liveness_snapshot(con)
    existing = _columns(con)
    added, skipped = [], []
    for name, typ in NEW_COLUMNS:
        if name in existing:
            skipped.append(name)
        else:
            con.execute(f"ALTER TABLE node_tests ADD COLUMN {name} {typ}")
            added.append(name)
    con.commit()
    report["added"] = added
    report["skipped"] = skipped
    report["rows_after"] = con.execute("SELECT COUNT(*) FROM node_tests").fetchone()[0]
    report["liveness_after"] = _liveness_snapshot(con)
    report["integrity_after"] = _integrity(con)
    cols = _columns(con)
    report["new_columns_nullable"] = all(cols[n]["notnull"] == 0 for n, _ in NEW_COLUMNS)
    report["null_counts"] = {
        n: con.execute(f"SELECT COUNT(*) FROM node_tests WHERE {n} IS NULL").fetchone()[0]
        for n, _ in NEW_COLUMNS}
    report["rows_unchanged"] = report["rows_before"] == report["rows_after"]
    report["liveness_unchanged"] = report["liveness_before"] == report["liveness_after"]
    report["integrity_ok"] = (report["integrity_before"] == "ok"
                              and report["integrity_after"] == "ok")
    con.close()
    return report


def check(db_path):
    """Dry-run：只报告缺失的列，不改任何东西。"""
    con = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
    existing = _columns(con)
    missing = [n for n, _ in NEW_COLUMNS if n not in existing]
    con.close()
    return {"db": db_path, "missing": missing, "present": [n for n, _ in NEW_COLUMNS if n in existing],
            "needs_migration": bool(missing)}


def compat_check(db_path):
    """验证旧版代码的位置 INSERT（7 值）能否在当前库上运行。
    预期：已迁移的 15 列库上会失败（列数不匹配），未迁移的 7 列库上能跑。
    返回实测结果；失败即证明 schema 与代码必须同一停机窗口部署。"""
    con = sqlite3.connect(db_path)
    ncols = len(con.execute("PRAGMA table_info(node_tests)").fetchall())
    try:
        con.execute("SAVEPOINT compat_probe")
        con.execute(
            "INSERT INTO node_tests VALUES (?, ?, ?, ?, ?, ?, ?)",
            ("vmess", "203.0.113.99", 443, int(time.time()), "fail", "curl-failed", 0.0))
        con.execute("ROLLBACK TO compat_probe")
        con.execute("RELEASE compat_probe")
        outcome = {"old_positional_insert_works": True,
                   "note": "old code can run on this schema"}
    except sqlite3.Error as e:
        try:
            con.execute("ROLLBACK TO compat_probe")
            con.execute("RELEASE compat_probe")
        except sqlite3.Error:
            pass
        outcome = {"old_positional_insert_works": False,
                   "error": str(e),
                   "note": "old code CANNOT run on this schema; deploy schema+code atomically in one stopped window"}
    con.close()
    outcome["columns"] = ncols
    return outcome


def rollback(db_path, snapshot):
    """用迁移前快照恢复 DB。先校验快照完整性，再覆盖。返回报告。"""
    if not os.path.exists(snapshot):
        return {"ok": False, "error": f"snapshot not found: {snapshot}"}
    chk = sqlite3.connect(f"file:{snapshot}?mode=ro", uri=True)
    integ = _integrity(chk)
    rows = chk.execute("SELECT COUNT(*) FROM node_tests").fetchone()[0]
    chk.close()
    if integ != "ok":
        return {"ok": False, "error": f"snapshot integrity not ok: {integ}"}
    shutil.copyfile(snapshot, db_path)
    con = sqlite3.connect(db_path)
    after_integ = _integrity(con)
    after_rows = con.execute("SELECT COUNT(*) FROM node_tests").fetchone()[0]
    ncols = len(con.execute("PRAGMA table_info(node_tests)").fetchall())
    con.close()
    return {"ok": after_integ == "ok" and after_rows == rows,
            "snapshot": snapshot, "snapshot_rows": rows,
            "restored_rows": after_rows, "restored_columns": ncols,
            "integrity_after": after_integ}


def main():
    ap = argparse.ArgumentParser(description="node_tests 诊断列迁移（幂等）")
    ap.add_argument("db", help="SQLite 库路径")
    ap.add_argument("--backup-dir", default=None, help="迁移前 WAL 备份目录")
    ap.add_argument("--check", action="store_true", help="Dry-run：只报告缺失列")
    ap.add_argument("--compat-check", action="store_true", help="验证旧版位置 INSERT 能否在当前库运行")
    ap.add_argument("--rollback", default=None, help="用快照恢复 DB（回滚）")
    args = ap.parse_args()
    if args.check:
        print(json.dumps(check(args.db), ensure_ascii=False, indent=2))
    elif args.compat_check:
        print(json.dumps(compat_check(args.db), ensure_ascii=False, indent=2))
    elif args.rollback:
        print(json.dumps(rollback(args.db, args.rollback), ensure_ascii=False, indent=2))
    else:
        print(json.dumps(migrate(args.db, args.backup_dir), ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
