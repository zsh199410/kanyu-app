"""阴性对照测试：3 条近期失败的 trojan 节点，分别用生产与补丁 tester 跑。
用法：python3 test_negative.py <包目录> <输出json>
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
    ("trojan", "103.125.216.11", 443, "NEG-trojan-1"),
    ("trojan", "104.16.174.101", 443, "NEG-trojan-2"),
    ("trojan", "103.133.240.115", 443, "NEG-trojan-3"),
]

records, _ = crawl_records("/opt/free-node-program/sources.yaml")
by_key = {(r["protocol"], r["host"], r["port"]): r for r in records}

results = []
port = 46200
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
