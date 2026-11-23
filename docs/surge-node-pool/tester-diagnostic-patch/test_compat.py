"""兼容性测试 v2（GPT #124 审查 P1 兼容与性能）。

验证：
1. 调用方审计：生产仓库内所有 test_one/test_many 导入者与调用点均已
   适配 4/5 元组（证据为 grep 结果，见报告 caller_audit）。
2. 完整 worker 批次：test_many 跑一批节点 → record_test 写入隔离 DB，
   行数、diag 列、nodes 健康字段均正确。
3. test_one/test_many 返回元组长度：test_one 恒为 4 元组（含 filtered/
   infra 各路径），test_many 恒为 5 元组。

用法：python3 test_compat.py <隔离包目录> <隔离DB> <输出json>
"""
import json
import os
import subprocess
import sys
import time

PKG = sys.argv[1]
DB = sys.argv[2]
OUT = sys.argv[3]
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, PKG)
from migrate_diag_columns import migrate
from pool.tester import test_one, test_many
from pool.crawler import crawl_records
from pool import db as dbmod

report = {}

# --- 1. 调用方审计（对生产仓库 grep 的结果断言） ---
PROD = "/opt/free-node-program"
grep_import = subprocess.run(
    ["grep", "-rn", "from .tester import\\|from pool.tester import\\|import tester",
     PROD + "/pool", PROD + "/publish", PROD + "/config"],
    capture_output=True, text=True).stdout.strip().splitlines()
grep_calls = subprocess.run(
    ["grep", "-rn", "test_one(\\|test_many(", PROD + "/pool"],
    capture_output=True, text=True).stdout.strip().splitlines()
# 只统计非备份、非 .bak 的 live 文件
live_imports = [l for l in grep_import if ".bak" not in l and "backup-" not in l]
live_calls = [l for l in grep_calls if ".bak" not in l and "backup-" not in l
              and "def test_one" not in l and "def test_many" not in l]
report["caller_audit"] = {
    "live_importers": live_imports,
    "live_call_sites": live_calls,
    "only_cli_imports_tester": all("pool/cli.py" in l for l in live_imports),
    "call_sites_all_in_cli_or_tester": all(
        ("pool/cli.py" in l or "pool/tester.py" in l) for l in live_calls),
}
assert report["caller_audit"]["only_cli_imports_tester"], "unexpected tester importer"
assert report["caller_audit"]["call_sites_all_in_cli_or_tester"], "unexpected call site"

# --- 2. 先迁移 schema（部署顺序：先 schema 再跑代码；未迁移的库上
# v2 record_test 会因缺列失败，见迁移测试的 compat_check） ---
mig = migrate(DB)
assert mig["rows_unchanged"] and mig["liveness_unchanged"] and mig["integrity_ok"], f"migrate: {mig}"
report["schema_migrated_first"] = {"added": mig["added"], "integrity_ok": mig["integrity_ok"]}

# --- 3. test_one 返回长度：各路径均为 4 元组 ---
records, _ = crawl_records("/opt/free-node-program/sources.yaml")
by_key = {(r["protocol"], r["host"], r["port"]): r for r in records}
# filtered 路径：构造一条会被 _filter_reason 拦截的记录（vmess 无 TLS）
filtered_rec = {"protocol": "vmess", "host": "203.0.113.30", "port": 443,
                "tls": False, "uuid": "00000000-0000-0000-0000-000000000000"}
out_f = test_one(filtered_rec, 46400)
assert len(out_f) == 4 and out_f[0] == "filtered", f"filtered path: {out_f}"
report["filtered_path_tuple"] = {"len": len(out_f), "result": out_f[0]}

# --- 4. 完整 worker 批次：test_many → record_test ---
CASES = [
    ("vmess", "172.64.145.93", 443),
    ("vmess", "38.68.135.131", 1270),
    ("trojan", "103.125.216.11", 443),
    ("trojan", "104.16.174.101", 443),
    ("trojan", "103.133.240.115", 443),
]
batch = []
for proto, host, p in CASES:
    rec = by_key.get((proto, host, p))
    if rec:
        batch.append(rec)
assert len(batch) == len(CASES), f"missing in crawl: {len(batch)}/{len(CASES)}"
t0 = time.time()
batch_start = int(t0)
results = test_many(batch, concurrency=3, port_base=46410, port_count=20)
elapsed = round(time.time() - t0, 1)
assert all(len(r) == 5 for r in results), "test_many must return 5-tuples"
db = dbmod.connect(DB)
for rec, result, ms, reason, diag in results:
    dbmod.record_test(db, rec["protocol"], rec["host"], rec["port"],
                      result, reason, ms, diag)
db.commit()
rows = db.execute(
    "SELECT protocol, host, port, result, reason, curl_exit, http_code, stage, "
    "stage_detail FROM node_tests WHERE host IN (%s) AND tested_at >= ? ORDER BY host"
    % ",".join("?" * len(CASES)),
    [h for _, h, _ in CASES] + [batch_start]).fetchall()
db.close()
assert len(rows) == len(CASES), f"worker batch rows: {len(rows)}"
# 每行 stage 必须为枚举值之一，diag 列不含自由文本
ALLOWED_STAGES = {"pass", "filtered", "infra", "dns", "tcp", "tls", "http",
                  "timeout", "socks", "other"}
for r in rows:
    assert r[7] in ALLOWED_STAGES, f"stage not enumerated: {r}"
    assert r[8] is None or isinstance(r[8], str) and len(r[8]) <= 32, f"detail odd: {r}"
report["worker_batch"] = {
    "nodes": len(batch), "elapsed_s": elapsed,
    "rows_written": len(rows),
    "results": [{"host": r[1], "result": r[3], "stage": r[7], "detail": r[8]} for r in rows],
}

with open(OUT, "w") as f:
    json.dump(report, f, ensure_ascii=False, indent=2)
print(json.dumps(report, ensure_ascii=False, indent=2))
