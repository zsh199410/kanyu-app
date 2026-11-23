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
import hashlib
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
    valid = (report["integrity_ok"] and report["rows_unchanged"]
             and report["liveness_unchanged"] and report["new_columns_nullable"])
    con.close()
    if not valid:
        raise RuntimeError("schema migration validation failed; stop and restore snapshot")
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


def _data_signature(con):
    """按稳定顺序读取所有SQLite表与schema，逐行计算内容摘要（常量内存）。
    与integrity_check配合，防止旧WAL回放造成“恢复成功”的假阳性。
    """
    digest = hashlib.sha256()
    for obj in con.execute(
            "SELECT type, name, tbl_name, sql FROM sqlite_master "
            "ORDER BY type, name, tbl_name").fetchall():
        digest.update(repr(tuple(obj)).encode("utf-8", errors="backslashreplace"))
        digest.update(b"\n")
    tables = [r[0] for r in con.execute(
        "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")]
    for table in tables:
        quoted = '"' + table.replace('"', '""') + '"'
        digest.update(table.encode("utf-8", errors="backslashreplace"))
        digest.update(b"\0")
        try:
            rows = con.execute(f"SELECT rowid, * FROM {quoted} ORDER BY rowid")
        except sqlite3.OperationalError:
            ncols = len(con.execute(f"PRAGMA table_info({quoted})").fetchall())
            if not ncols:
                raise
            order = ",".join(str(i) for i in range(1, ncols + 1))
            rows = con.execute(f"SELECT * FROM {quoted} ORDER BY {order}")
        for row in rows:
            digest.update(repr(tuple(row)).encode("utf-8", errors="backslashreplace"))
            digest.update(b"\n")
    return digest.hexdigest()


def rollback(db_path, snapshot):
    """用SQLite backup API恢复快照，绝不raw-copy主数据库文件。

    生产前置条件：所有测试器timer/service和其他DB写入方均已停止。
    BEGIN IMMEDIATE仅用于检测当前写锁，不能代替外部停机门禁。
    backup API正确处理WAL；恢复后比较全库schema/数据摘要。
    """
    report = {"ok": False, "snapshot": snapshot}
    if not os.path.isfile(snapshot) or not os.path.isfile(db_path):
        return {**report, "error": "snapshot or target DB not found"}
    if os.path.samefile(snapshot, db_path):
        return {**report, "error": "snapshot and target are the same file"}
    src = target = verify = None
    try:
        src = sqlite3.connect(
            f"file:{os.path.abspath(snapshot)}?mode=ro", uri=True, timeout=2)
        snap_integrity = _integrity(src)
        if snap_integrity != "ok":
            return {**report, "error": f"snapshot integrity not ok: {snap_integrity}"}
        snap_rows = src.execute("SELECT COUNT(*) FROM node_tests").fetchone()[0]
        snap_cols = len(src.execute("PRAGMA table_info(node_tests)").fetchall())
        snap_sig = _data_signature(src)
        target = sqlite3.connect(db_path, timeout=0.25)
        target.execute("PRAGMA busy_timeout=250")
        # 有写者时立即拒绝，避免长时间等待或覆盖运行中的写操作。
        target.execute("BEGIN IMMEDIATE")
        target.rollback()
        # 正确处理WAL中的已提交页，而不是shutil.copyfile(db_path)。
        src.backup(target)
        target.close()
        target = None
        verify = sqlite3.connect(db_path, timeout=2)
        after_integrity = _integrity(verify)
        after_rows = verify.execute("SELECT COUNT(*) FROM node_tests").fetchone()[0]
        after_cols = len(verify.execute("PRAGMA table_info(node_tests)").fetchall())
        after_sig = _data_signature(verify)
        ok = (after_integrity == "ok" and after_rows == snap_rows
              and after_cols == snap_cols and after_sig == snap_sig)
        return {
            **report, "ok": ok, "snapshot_rows": snap_rows,
            "restored_rows": after_rows, "snapshot_columns": snap_cols,
            "restored_columns": after_cols, "integrity_after": after_integrity,
            "content_match": after_sig == snap_sig,
            **({} if ok else {"error": "restored DB differs from snapshot"}),
        }
    except (sqlite3.Error, OSError, ValueError) as exc:
        return {**report, "error": f"restore aborted: {type(exc).__name__}: {exc}"}
    finally:
        for con in (verify, target, src):
            if con is not None:
                con.close()

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
        outcome = rollback(args.db, args.rollback)
        print(json.dumps(outcome, ensure_ascii=False, indent=2))
        # CI/systemd/shell must never see success for a failed restore.
        # Keep JSON for human diagnosis, and return a nonzero exit status.
        if not outcome.get("ok", False):
            raise SystemExit(1)
    else:
        print(json.dumps(migrate(args.db, args.backup_dir), ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
