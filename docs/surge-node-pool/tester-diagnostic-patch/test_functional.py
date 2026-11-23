"""功能对照测试：同一批节点，分别用生产 tester 与补丁 tester 跑 test_one。

用法：python3 test_functional.py <包目录> <输出json>
包目录为含 pool/ 子包的目录（生产 /opt/free-node-program 或隔离副本）。
验证：result/ms/reason 与生产一致（不改变判定语义）；补丁版 diag 字段齐全。
节点记录来自 crawl_records（只读订阅抓取，不写库、不改生产）。
"""
import json
import os
import sys
import time

PKG = sys.argv[1]
OUT = sys.argv[2]
sys.path.insert(0, PKG)
from pool.tester import test_one
from pool.crawler import crawl_records

CASES = [
    ("vmess", "38.68.135.131", 1270, "HEALTHY-passer"),
    ("vmess", "172.64.145.93", 443, "HEALTHY-candidate"),
    ("vmess", "104.18.42.163", 443, "BAD-canada-403"),
    ("trojan", "152.70.105.42", 8443, "BAD-refused"),
]

records, _ = crawl_records("/opt/free-node-program/sources.yaml")
by_key = {(r["protocol"], r["host"], r["port"]): r for r in records}

results = []
port = 46100
for proto, host, p, label in CASES:
    rec = by_key.get((proto, host, p))
    if not rec:
        results.append({"label": label, "error": "MISSING in crawl"})
        continue
    out = test_one(rec, port)
    port += 1
    if len(out) == 4:
        result, ms, reason, diag = out
        results.append({"label": label, "result": result, "ms": round(ms, 1),
                        "reason": reason, "diag": diag})
    else:
        result, ms, reason = out
        results.append({"label": label, "result": result, "ms": round(ms, 1),
                        "reason": reason, "diag": None})
    time.sleep(1)

with open(OUT, "w") as f:
    json.dump(results, f, ensure_ascii=False, indent=2)
print(json.dumps(results, ensure_ascii=False, indent=2))
