# 旧发布器关键筛选逻辑摘录（cli.py，行号以开发副本为准）

## 入口：`cmd_publish`（276 行起）

读取 `config.yaml`，连接 `data/pool.db`，取：

- `per_country_cap`（默认 40）、`publish_max_lines`（默认 150）
- `vmess_tls_only`（默认 True）
- `private-hosts.txt`（私有 host 排除）、`blocklist`（DB 拉黑表）

## 钉选（无条件发布）

- `pinned_db`：`pinned` 表 `(protocol, host, port) -> name`
- `pinned_lines`：钉选文件（`read_pinned_lines`）
- DB 有、文件无的钉选（`db_only_keys`）同样视为钉选，不得被轮换覆盖或丢弃
- 钉选行在发布时原样保留，不经过任何新鲜度或手机证据检查

## 旧轮换保留 `kept_old`（349–363 行）——本次 P0 根因

上一版发布文件中的轮换行，满足以下条件即**原文保留**（不改名）：

1. `(protocol, host, port)` 不在 blocklist
2. 不在 `db_only_set`
3. 在 `db_pass` 内

## `db_pass` 的定义（326–348 行）——只认 VPS，不认手机

1. `nodes` 表：`last_result='pass' AND last_test_at >= started - publish_fresh_hours*3600`
   （`publish_fresh_hours` 默认 12 小时）
2. 终身通过率 `rate = pass_count / test_count`，须 `>= publish_min_pass_rate`（默认 0.5）
3. `node_tests` 表最新一次 `result='pass'` 的 `ms` 须 `<= publish_max_vps_ms`（默认 300）

**以上三项全部是 VPS 侧 sing-box 握手测试。手机探针（probe.db 的
`probe_nodes` / `probe_reports`，含 quarantined / retired / expired /
verified 状态）在这段逻辑里一次也没有被读取。**

## 新轮换（364–378 行）

`db_pass` 中不在 blocklist / 钉选 / `db_only` / 旧轮换的 key，且有新鲜爬取
记录（`_fresh_records`，仅内存）、通过 `pre_filter`，再经 `rules.assign_names`
命名（旧名与钉选名保留防重名），受 `per_country_cap` 与 `max_lines` 限制。

## 已确认的缺口（2026-11-18 实测）

- 06:07 发布：`pinned 21 + kept_old 30 + new 7 = 58`，`winner_clean_removed 0`。
- 截图 7 个失败节点（香港24/25/34/39、美国14/17/19）全部在池；
  探针侧 0 成功 / 4 失败，其中 5 个已是 quarantined / retired / expired，
  但 `kept_old` 与钉选逻辑均未读取探针状态。
- `pinned_protected: true` 是死配置项，无代码读取；豁免来自发布结构本身。
- 修复方向（待 GPT 定）：发布时以稳定指纹查探针状态，拒绝缺失新鲜合格
  原生测试（24 小时内手机成功且 <300ms）的普通节点；钉选解保护须逐行
  方案＋机主显式批准，不在本包内擅自改动。
