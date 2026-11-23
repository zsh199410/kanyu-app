"""隔离迁移测试 v2（只读生产快照的副本，绝不碰生产库）。

验证：
1. --check dry-run：报告缺失列，不改库。
2. 迁移幂等（跑两次不报错，第二次全部跳过）。
3. 旧记录原样保留（行数不变，新列全部 NULL）。
4. 判活 SQL 结果不变（同一批节点的最新 pass ms，迁移前后一致）。
5. integrity_check 前后均为 ok。
6. record_test 写新列：带 diag 写入诊断值；不带 diag 写 NULL（向后兼容）。
7. record_test 不改变 nodes 健康字段逻辑。
8. 注入回归：即使调用方传入含敏感值的 diag 自由文本字段，也不写入 DB
   （v2 的 record_test 只取白名单字段；sb_err 已从 schema 移除）。
9. 兼容性检查：旧版位置 INSERT（7 值）在已迁移库上失败（实测），
   证明 schema 与代码必须同一停机窗口部署。
10. 回滚：用迁移前快照恢复，列数/行数/完整性回到迁移前。

用法：python3 test_migration.py <隔离DB副本> <隔离包目录> <备份目录>
"""
import json
import os
import shutil
import sqlite3
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from migrate_diag_columns import migrate, check, compat_check, rollback, NEW_COLUMNS

SNAP = sys.argv[1]
PKG = sys.argv[2]
BACKUP_DIR = sys.argv[3]
sys.path.insert(0, PKG)
from pool import db as dbmod

LIVENESS_SQL = ("SELECT ms FROM node_tests WHERE protocol=? AND host=? AND port=? "
                "AND result='pass' ORDER BY tested_at DESC LIMIT 1")


def liveness_snapshot(con, keys):
    out = {}
    for k in keys:
        row = con.execute(LIVENESS_SQL, k).fetchone()
        out["|".join(map(str, k))] = row[0] if row else None
    return out


def run(cmd):
    r = subprocess.run(cmd, capture_output=True, text=True)
    return json.loads(r.stdout)


def main():
    report = {}
    # 0. --check dry-run：迁移前缺 8 列，且不改库
    before_cols = None
    con = sqlite3.connect(SNAP)
    before_cols = len(con.execute("PRAGMA table_info(node_tests)").fetchall())
    before_rows = con.execute("SELECT COUNT(*) FROM node_tests").fetchone()[0]
    keys = [tuple(r) for r in con.execute(
        "SELECT DISTINCT protocol, host, port FROM node_tests "
        "WHERE result='pass' ORDER BY tested_at DESC LIMIT 50")]
    before_live = liveness_snapshot(con, keys)
    con.close()
    chk = run([sys.executable, "migrate_diag_columns.py", SNAP, "--check"])
    assert chk["needs_migration"] is True and len(chk["missing"]) == 8, f"check: {chk}"
    con = sqlite3.connect(SNAP)
    assert len(con.execute("PRAGMA table_info(node_tests)").fetchall()) == before_cols
    con.close()
    report["check_dry_run"] = {"missing": chk["missing"], "changed_nothing": True}
    report["before_rows"] = before_rows
    report["liveness_keys"] = len(keys)

    # 1. 迁移跑两次（幂等），带 WAL 备份
    r1 = migrate(SNAP, BACKUP_DIR)
    r2 = migrate(SNAP)
    report["migrate_run1"] = {"added": r1["added"], "skipped": r1["skipped"],
                              "backup": os.path.basename(r1.get("backup", "")),
                              "integrity_ok": r1["integrity_ok"]}
    report["migrate_run2"] = {"added": r2["added"], "skipped": r2["skipped"]}
    assert r1["added"] == [n for n, _ in NEW_COLUMNS], f"run1 added: {r1['added']}"
    assert r1["rows_unchanged"] and r1["liveness_unchanged"] and r1["integrity_ok"]
    assert r2["added"] == [] and len(r2["skipped"]) == len(NEW_COLUMNS), "not idempotent"
    assert all(v == before_rows for v in r1["null_counts"].values()), "old rows not all NULL"
    report["old_rows_preserved_null"] = True
    report["liveness_unchanged"] = True

    con = sqlite3.connect(SNAP)
    cols = {r[1]: r[3] for r in con.execute("PRAGMA table_info(node_tests)")}
    assert "sb_err" not in cols, "sb_err must not exist in v2 schema"
    report["new_columns_nullable"] = all(cols[n] == 0 for n, _ in NEW_COLUMNS)
    report["sb_err_absent"] = True
    con.close()

    # 2. record_test：带 diag / 不带 diag / 注入 diag
    db = dbmod.connect(SNAP)
    dbmod.record_test(db, "vmess", "203.0.113.10", 443, "fail", "curl-failed", 0.0,
                      {"curl_exit": 97, "http_code": "000", "stage": "socks",
                       "detail": "curl-socks-97", "lookup_ms": 1.2,
                       "connect_ms": 3.4, "appconnect_ms": 0.0, "total_ms": 45.6})
    dbmod.record_test(db, "vmess", "203.0.113.11", 443, "pass", "", 123.4,
                      {"curl_exit": 0, "http_code": "204", "stage": "pass",
                       "detail": "http-204", "lookup_ms": 5.0,
                       "connect_ms": 10.0, "appconnect_ms": 20.0, "total_ms": 123.4})
    dbmod.record_test(db, "vmess", "203.0.113.12", 443, "fail", "curl-failed", 0.0)
    # 注入：调用方传入含敏感值的自由文本字段，必须不写入
    SECRET = "FAKE-SECRET-TOKEN-TEST-ONLY"
    dbmod.record_test(db, "vmess", "203.0.113.13", 443, "fail", "curl-failed", 0.0,
                      {"curl_exit": 97, "http_code": "000", "stage": "socks",
                       "detail": "curl-socks-97", "sb_err": f"token={SECRET} host=evil.example.com",
                       "password": SECRET})
    db.commit()
    row1 = db.execute(
        "SELECT curl_exit, http_code, stage, stage_detail, t_lookup_ms, "
        "t_connect_ms, t_appconnect_ms, t_total_ms FROM node_tests "
        "WHERE host='203.0.113.10'").fetchone()
    row2 = db.execute(
        "SELECT curl_exit, http_code, stage, stage_detail, t_total_ms FROM node_tests "
        "WHERE host='203.0.113.11'").fetchone()
    row3 = db.execute(
        "SELECT curl_exit, http_code, stage, stage_detail FROM node_tests "
        "WHERE host='203.0.113.12'").fetchone()
    row4 = db.execute("SELECT * FROM node_tests WHERE host='203.0.113.13'").fetchone()
    assert row1 == (97, "000", "socks", "curl-socks-97", 1.2, 3.4, 0.0, 45.6), f"diag write: {row1}"
    assert row2 == (0, "204", "pass", "http-204", 123.4), f"pass diag: {row2}"
    assert row3 == (None, None, None, None), f"no-diag should be NULL: {row3}"
    assert SECRET not in repr(row4), f"injected secret leaked into DB row: {row4}"
    assert "evil.example.com" not in repr(row4), "injected host leaked into DB row"
    report["record_test_with_diag"] = True
    report["record_test_without_diag_null"] = True
    report["injection_not_persisted"] = True
    n1 = db.execute("SELECT last_result, pass_count, test_count FROM nodes "
                    "WHERE host='203.0.113.10'").fetchone()
    n2 = db.execute("SELECT last_result, pass_count, test_count FROM nodes "
                    "WHERE host='203.0.113.11'").fetchone()
    assert n1[0] == "fail" and n1[1] == 0 and n1[2] == 1, f"nodes fail row: {n1}"
    assert n2[0] == "pass" and n2[1] == 1 and n2[2] == 1, f"nodes pass row: {n2}"
    report["nodes_health_logic_unchanged"] = True
    db.execute("DELETE FROM node_tests WHERE host LIKE '203.0.113.%'")
    db.execute("DELETE FROM nodes WHERE host LIKE '203.0.113.%'")
    db.commit()
    db.close()

    # 3. 兼容性检查：旧版位置 INSERT 在已迁移库上必须失败
    cc = compat_check(SNAP)
    assert cc["columns"] == 15, f"columns: {cc}"
    assert cc["old_positional_insert_works"] is False, f"compat: {cc}"
    report["compat_check"] = {"columns": cc["columns"],
                              "old_positional_insert_works": False,
                              "error": cc["error"],
                              "conclusion": "schema+code must deploy atomically in one stopped window"}

    # 4. 回滚：用迁移前快照恢复
    snap = r1["backup"]
    rb = rollback(SNAP, snap)
    assert rb["ok"] is True, f"rollback: {rb}"
    assert rb["restored_columns"] == 7, f"restored columns: {rb}"
    assert rb["restored_rows"] == before_rows
    con = sqlite3.connect(SNAP)
    assert len(con.execute("PRAGMA table_info(node_tests)").fetchall()) == 7
    assert con.execute("SELECT COUNT(*) FROM node_tests").fetchone()[0] == before_rows
    assert liveness_snapshot(con, keys) == before_live
    con.close()
    report["rollback"] = {"restored_columns": rb["restored_columns"],
                          "restored_rows": rb["restored_rows"],
                          "liveness_unchanged": True}
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
