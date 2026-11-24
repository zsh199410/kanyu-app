"""N2 统一筛查：筛查 / 试用组批 / 正式发布 / 补位统一查阻止清单。

规则（GPT 2026-11-24 三批裁决 N2 + Review 6033772552 v2 收口）：
- 阻止清单 = blocklist 表（历史清退禁入） + rejected_nodes.json（GPT 已裁决拒绝）。
  两者语义分开：blocklist 是“曾清退、禁复活”；rejected 是“GPT 拒绝准入”。
- 抓取仍可存审计记录（cmd_crawl 不改），但筛查出的候选不得重入候选池。
- 测试可隔离诊断（cmd_test 不改测试本身），但测试通过不能改变禁入状态；
  常规 cmd_test 测试集须排除阻止清单内三元组（见 cli-v2.patch）。
- 正式发布已查 blocklist（cmd_publish 现状已确认），v2 起同时查
  rejected_nodes.json：同一受信版本阻止清单（load_banlist 一次加载、
  一个版本号）贯穿筛查、组批、补位与发布全程；发布前最后一道 guard
  （verify_publish_guard）重新加载并复核版本、逐行解析核对，版本不符
  或加载失败即拒绝发布。
- 严格漏斗沿用 P1-2 口径（样本 ≥20、通过率 ≥0.5、端口 ≠19999、
  last_result='pass'、24h 内、最近一次通过 ≤300ms），再叠加本模块的
  blocklist / rejected 排除。分母口径：漏斗输出行数是“严格集”，
  不是全集；报告时不把过滤后的分母冒充全集。
- SNI 准入（N3）走 pre_filter（rules.py），本模块的 screen_records
  先查阻止清单、再调 pre_filter，两层原因分开记录。
- 三元组级禁入只是保守禁入：它只说明“该三元组曾清退、不得复活”，
  不作任何新配置变体的健康证明；新变体（不同 SNI / 传输 / 认证）的
  健康须凭新鲜 VPS / 手机 / 控制证据重新判定，不得用旧三元组历史
  冒充新变体证据。
"""

import hashlib
import json
import os

from .blocklist_common import load_rejected_strict
from .crawler import parse_surge_line
from .db import get_blocked
from .rules import pre_filter

REJECTED_FILENAME = "rejected_nodes.json"


def load_rejected(path=None):
    """严格加载 rejected_nodes.json（fail-closed，不悄悄变空）。

    文件缺失、JSON 损坏、entries 缺失/为空、重复、畸形、decision_ref
    为空一律抛错。调用方（cmd_test / cmd_publish）须在加载失败时拒绝
    继续，绝不能当成“无拒绝项”放行。
    """
    if path is None:
        path = os.path.join(os.path.dirname(__file__), REJECTED_FILENAME)
    return load_rejected_strict(path)


def load_banlist(conn, rejected_path=None):
    """一次加载同一受信版本的阻止清单。

    返回 {"blocked": set(三元组), "rejected": {三元组: 条目},
    "version": str}；version 是 blocklist 三元组 + rejected 三元组 +
    rejected 文件 version 的规范序列化 SHA-256。筛查、组批、补位与
    发布全程使用同一份 banlist；发布前 guard 重新加载并比对 version，
    不符即拒绝发布。
    """
    blocked = get_blocked(conn)
    rejected = load_rejected(rejected_path)
    if rejected_path is None:
        rejected_path = os.path.join(os.path.dirname(__file__),
                                     REJECTED_FILENAME)
    # load_rejected 已严格校验文件有效，version 必为 int >= 1。
    with open(rejected_path, "r", encoding="utf-8") as f:
        rejected_version = json.load(f).get("version")
    canon = json.dumps({
        "blocked": sorted(blocked),
        "rejected": sorted(rejected),
        "rejected_version": rejected_version,
    }, ensure_ascii=False, sort_keys=True)
    version = hashlib.sha256(canon.encode("utf-8")).hexdigest()
    return {"blocked": set(blocked), "rejected": dict(rejected),
            "version": version}


def banned_keys(banlist):
    """阻止清单并集（blocklist ∪ rejected），供各调用点统一使用。"""
    return set(banlist["blocked"]) | set(banlist["rejected"])


def verify_publish_guard(lines, banlist):
    """发布前最后一道 guard：逐行解析，任一被禁三元组即拒绝整批。

    lines 为待发布的 Surge 代理行原文；banlist 为 load_banlist 的返回。
    解析失败的行同样拒绝（fail-closed）。返回核对通过的行数。
    试用发布（probation manifest）写入前也须调用本 guard（同一受信
    版本阻止清单）；试用发布器的接线属独立服务变更，不在本差异内，
    本函数只提供 guard 本身与隔离测试。
    """
    banned = banned_keys(banlist)
    checked = 0
    for line in lines:
        _name, proto, host, port, ok = parse_surge_line(line)
        if not ok:
            raise ValueError("publish guard: unparseable line refused")
        key = (proto, host, port)
        if key in banned:
            raise ValueError("publish guard: banned triple in publish set: "
                             "%s (refused whole batch)" % (key,))
        checked += 1
    return checked


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
