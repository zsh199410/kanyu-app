"""N2 统一筛查：筛查 / 试用组批 / 正式发布 / 补位统一查阻止清单。

规则（GPT 2026-11-24 三批裁决 N2）：
- 阻止清单 = blocklist 表（历史清退禁入） + rejected_nodes.json（GPT 已裁决拒绝）。
  两者语义分开：blocklist 是“曾清退、禁复活”；rejected 是“GPT 拒绝准入”。
- 抓取仍可存审计记录（cmd_crawl 不改），但筛查出的候选不得重入候选池。
- 测试可隔离诊断（cmd_test 不改），但测试通过不能改变禁入状态。
- 正式发布已查 blocklist（cmd_publish / build_candidate 现状已确认），
  本模块只给筛查、试用组批与补位提供同一入口，不重复改发布路径。
- 严格漏斗沿用 P1-2 口径（样本 ≥20、通过率 ≥0.5、端口 ≠19999、
  last_result='pass'、24h 内、最近一次通过 ≤300ms），再叠加本模块的
  blocklist / rejected 排除。分母口径：漏斗输出行数是“严格集”，
  不是全集；报告时不把过滤后的分母冒充全集。
- SNI 准入（N3）走 pre_filter（rules.py），本模块的 screen_records
  先查阻止清单、再调 pre_filter，两层原因分开记录。
"""

import json
import os

from .db import get_blocked
from .rules import pre_filter

REJECTED_FILENAME = "rejected_nodes.json"


def load_rejected(path=None):
    """返回 {triple: entry}；文件缺失或损坏时 fail-closed（抛错，不静默放行）。"""
    if path is None:
        path = os.path.join(os.path.dirname(__file__), REJECTED_FILENAME)
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
    out = {}
    for e in data.get("entries", []):
        key = (e["protocol"], e["host"], e["port"])
        out[key] = e
    return out


def screen_records(records, blocked, rejected, private_hosts):
    """逐条筛查新鲜抓取记录。

    返回 (kept, excluded)，excluded 为 [(record, reason)]，原因：
    blocklisted / rejected-gpt / pre_filter 原因（含 vmess-no-sni）。
    阻止清单优先于 pre_filter：被禁入的记录不进入测试集，
    也不产生“通过 pre_filter”的假象。
    """
    kept = []
    excluded = []
    for rec in records:
        key = (rec["protocol"], rec["host"], rec["port"])
        if key in blocked:
            excluded.append((rec, "blocklisted"))
            continue
        if key in rejected:
            excluded.append((rec, "rejected-gpt"))
            continue
        ok, reason = pre_filter(rec, private_hosts)
        if not ok:
            excluded.append((rec, reason))
            continue
        kept.append(rec)
    return kept, excluded


def strict_candidates(conn, blocked, rejected, now=None):
    """DB 严格漏斗（P1-2 口径）+ 阻止清单排除。

    返回 (rows, excluded_rows)：rows 为 [(protocol, host, port, source,
    last_pass_ms)]；excluded_rows 为 [(row, reason)]，reason 为
    blocklisted / rejected-gpt。漏斗本身是三元组级视图，不能区分
    同一三元组的不同配置变体（例如有 SNI 与无 SNI 的 vmess 变体）；
    变体级准入以 screen_records / pre_filter 为准。
    """
    import time
    if now is None:
        now = int(time.time())
    sql = """
        SELECT protocol, host, port, source,
          (SELECT ms FROM node_tests
            WHERE protocol=nodes.protocol AND host=nodes.host
              AND port=nodes.port AND result='pass'
            ORDER BY tested_at DESC LIMIT 1) AS last_pass_ms
        FROM nodes
        WHERE status='candidate'
          AND (SELECT COUNT(*) FROM node_tests t
                WHERE t.protocol=nodes.protocol AND t.host=nodes.host
                  AND t.port=nodes.port) >= 20
          AND (CAST(pass_count AS REAL)/NULLIF(test_count,0)) >= 0.5
          AND port != 19999
          AND last_result='pass'
          AND last_test_at >= ? - 86400
          AND (SELECT ms FROM node_tests
                WHERE protocol=nodes.protocol AND host=nodes.host
                  AND port=nodes.port AND result='pass'
                ORDER BY tested_at DESC LIMIT 1) <= 300
    """
    rows = []
    excluded = []
    for r in conn.execute(sql, (now,)):
        key = (r[0], r[1], r[2])
        if key in blocked:
            excluded.append((r, "blocklisted"))
        elif key in rejected:
            excluded.append((r, "rejected-gpt"))
        else:
            rows.append(r)
    return rows, excluded
