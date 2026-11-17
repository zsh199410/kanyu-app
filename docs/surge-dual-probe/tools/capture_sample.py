#!/usr/bin/env python3
"""Capture a REAL P0-1 binding sample from an isolated run:
  tasks response (with server-issued pool_sha) -> report POST body ->
  stored DB row. Writes docs/SAMPLE_REQUEST.md.
All data is synthetic fixture data (TEST-NET hosts). Stdlib only.
Usage: python3 tools/capture_sample.py
"""
import hashlib
import json
import os
import sqlite3
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(ROOT, "service"))
import probe_service_dual as dual  # noqa: E402

FIXTURE_POOL = os.path.join(ROOT, "fixtures", "pool-fixture.txt")
DUAL_JS = os.path.join(ROOT, "script", "probe-task-dual.js")
OUT = os.path.join(ROOT, "docs", "SAMPLE_REQUEST.md")

import re
CLIENT_VERSION = re.search(
    r"const CLIENT_VERSION = '(dual-v1-[0-9a-f]{12})';",
    open(DUAL_JS, encoding="utf-8").read()).group(1)


def main():
    tmp = tempfile.mkdtemp(prefix="dual-sample-")
    base = os.path.join(tmp, "probe")
    os.makedirs(os.path.join(base, "config"), exist_ok=True)
    os.makedirs(os.path.join(base, "data"), exist_ok=True)
    with open(os.path.join(base, "config", "probe-path.txt"), "w") as f:
        f.write("testseg12345678")
    pool = os.path.join(tmp, "pool.txt")
    with open(pool, "w") as f:
        f.write(open(FIXTURE_POOL, encoding="utf-8").read())
    dual.BASE = base
    dual.DB_PATH = os.path.join(base, "data", "probe.db")
    dual.POOL_TXT = pool
    pool_sha = hashlib.sha256(open(pool, "rb").read()).hexdigest()

    # 1. tasks response (server-issued pool_sha + batch_id)
    tasks, info = dual.next_tasks_wifi()
    assert info["pool_sha"] == pool_sha, info
    assert re.fullmatch(r"b-[0-9a-f]{16}", info["batch_id"]), info
    tasks_response = {"ok": True, "tasks": tasks[:2], "info": info}

    # 2. report POST body the script would send (echoes pool_sha + batch_id)
    now = int(time.time())
    results = []
    for i, t in enumerate(tasks[:2]):
        results.append({
            "fingerprint": t["fingerprint"],
            "name": t["name"],
            "ts": now - 30 + i,
            "state": "measured",
            "warm_ms": 120,
            "second_request_ms": 95 + i * 10,
            "second_status": 204,
            "success": True,
            "error": None,
            "network_type": "wifi",
            "source_version_sha": info["pool_sha"],
            "batch_id": info["batch_id"],
            "client_version": CLIENT_VERSION,
        })
    report_body = {"results": results}
    out = dual.ingest_wifi(results)
    assert out["accepted"] == 2, out

    # 3. stored row
    conn = sqlite3.connect(dual.DB_PATH)
    cols = [r[1] for r in conn.execute(
        "PRAGMA table_info(probe_reports_wifi)").fetchall()]
    row = conn.execute(
        "SELECT * FROM probe_reports_wifi ORDER BY id LIMIT 1").fetchone()
    conn.close()
    stored = dict(zip(cols, row))

    md = []
    md.append("# P0-1 绑定样本：一条真实请求 JSON 与入库列")
    md.append("")
    md.append("以下全部来自一次隔离运行（合成夹具池，TEST-NET 主机），非手写示例。")
    md.append("")
    md.append("## 两个版本概念的来源与区别")
    md.append("")
    md.append("| 字段 | 值 | 来源 | 含义 |")
    md.append("|---|---|---|---|")
    md.append("| `source_version_sha` | 池文件内容 SHA256（64 hex） | 服务端：发 tasks 时锁定**任务快照**的池 SHA（`info.pool_sha`），脚本原样回填；入库时服务端按批次记录校验，不对照“当前池文件” | **被测节点池的版本**：结果绑定到哪一份池文件快照 |")
    md.append("| `batch_id` | `b-<16 hex>` | 服务端：发 tasks 时锁定批次记录（池 SHA＋指纹集＋有效期），脚本原样回填；入库时服务端按该记录验指纹/版本/时窗/去重键 | **任务批次绑定**：这条结果属于哪一批下发的任务 |")
    md.append("| `client_version` | 脚本构建 ID（`dual-v1-<sha12>`） | 构建时注入：`tools/inject_sha.py` 对脚本文件算 SHA（占位符归一化后前 12 hex） | **手机脚本自身的版本**：哪一份客户端代码发的这条结果 |")
    md.append("")
    md.append("三者绝不混用：脚本构建 ID 不能当池版本；池 SHA 不能标识客户端代码；")
    md.append("没有批次绑定，结果不能证明属于哪一批任务。")
    md.append("关键更正（GPT #6938432964 门禁 1）：真实池 SHA 必须是**任务快照的 SHA**，")
    md.append("不是接收 POST 时的“当前池”SHA。服务端下发批次时锁定完整")
    md.append("`source_version_sha`＋`task_id/batch_id`＋指纹集＋有效期；接收时按绑定记录")
    md.append("验证指纹、版本、时窗与去重键；期间 :07 轮换不得把旧批次记录标成新池合格。")
    md.append("所有不匹配 fail closed。旧蜂窝客户端不发绑定字段时仍可入库（向后兼容）；")
    md.append("一旦发送任一绑定字段，就必须通过批次记录校验。")
    md.append("")
    md.append("## 1. tasks 响应（服务端签发 pool_sha + batch_id）")
    md.append("")
    md.append("```json")
    md.append(json.dumps(tasks_response, indent=2, ensure_ascii=False))
    md.append("```")
    md.append("")
    md.append("## 2. 上报请求体（脚本回填 pool_sha + batch_id 原值 + 自身 client_version）")
    md.append("")
    md.append("```json")
    md.append(json.dumps(report_body, indent=2, ensure_ascii=False))
    md.append("```")
    md.append("")
    md.append("## 3. 入库行（probe_reports_wifi）")
    md.append("")
    md.append("```json")
    md.append(json.dumps(stored, indent=2, ensure_ascii=False, default=str))
    md.append("```")
    md.append("")
    md.append("入库核对：`source_version_sha` == tasks 响应里的 `pool_sha`（该批次锁定")
    md.append("的快照 SHA）；`batch_id` == tasks 响应里的 `batch_id`；`client_version` ==")
    md.append("脚本构建 ID；三者不同值。`network_type` 是客户端声明的标签，")
    md.append("不是原生验证证据（见报告 P0-3 节）。")
    md.append("")
    print(f"CLIENT_VERSION={CLIENT_VERSION}")
    print(f"POOL_SHA={pool_sha}")
    print(f"accepted={out['accepted']}")
    open(OUT, "w", encoding="utf-8").write("\n".join(md))
    print("wrote", OUT)


if __name__ == "__main__":
    main()
