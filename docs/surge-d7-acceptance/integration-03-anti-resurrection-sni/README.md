# 集成-03：持久禁入（N2）+ SNI 准入（N3）

独立差异包（与 PR #125/#126/#127 分离）。只做差异包 + 隔离测试，
不实施生产：不改 live 文件、不写生产 blocklist、不删除任何节点、
不改 unit、不创建密钥、不动 live 探针脚本。

- 建议分支：`integration-03-anti-resurrection-sni`
- 建议目录：`docs/surge-d7-acceptance/integration-03-anti-resurrection-sni/`
  （与 #126/#127 布局一致）
- 基线：live `pool/`（2026-11-24 11:52 取回核对，rules.py / tester.py /
  crawler.py / db.py / cli.py / build_candidate.py / auto_prune.py /
  production_cycle.py / import_per_observation_v2.py /
  import_phone_observations.py 原文在 `work/live/`）

## 1. 改动一览

| 文件 | 性质 | 规模 |
|---|---|---|
| `pool/backfill_blocklist.py` | 新增：N2 回填脚本 | 256 行 |
| `pool/blocklist_backfill_20261121.json` | 新增：25 条逐条审计记录 | 556 行 |
| `pool/screening.py` | 新增：统一筛查（blocklist + rejected + pre_filter + 严格漏斗） | 108 行 |
| `pool/rejected_nodes.json` | 新增：GPT 已裁决拒绝清单（1 条） | 1 行 |
| `pool/unblock_node.py` | 新增：解禁脚本 | 166 行 |
| `pool/rules.py` | 修改：N3（live 186 → 212 行，+26） | 见 `rules-n3.patch` |
| `pool/tester.py` | 修改：N3（live 185 → 207 行，+22） | 见 `rules-n3.patch` |
| `rules-n3.patch` | N3 两文件统一 diff（+48 / −0，纯加法） | 94 行 |
| `tests/test_integration_03.py` | 新增：隔离测试（75 项） | 446 行 |
| `pool/__init__.py`、`pool/crawler.py`、`pool/db.py`、`pool/geo.py` | 未改：live 原文逐字节复制，仅供本包独立导入与测试；合并时若 live 已变，以 live 为准 | — |

## 2. N2 持久禁入

### 2.1 25 条审计（逐条核实，不抄简报）

来源：`/opt/p2p3-single-writer/prune-ledger.jsonl` 原文（DELETE /
ALLOWLIST_DELETE 事件 per_key）+ `allowlist-r1/r2/r3/r4/us20.json`
逐条交叉核对（decision_ref、received_at == ledger retest_ts、
nonce 一致）。核对结果：

- 10 条自动清退（10:55 ×2、12:55 ×4、13:55 ×4）：ledger 事件
  `decision` 为 null，无 #73 评论引用——审计文件如实记
  `decision_ref: null`，不捏造。verdict 区分记录：
  `DELETE_CANDIDATE_PHONE`（2 条，phone_fail_count 3/4）与
  `DELETE_OVER_TARGET`（8 条，超量裁剪按手机失败数排序，count 2，
  其中伊朗14 为 4）。
- 15 条 allowlist 清退（R1–R4 20:01–20:02、美国20 23:42）：
  decision_ref 均为 `zsh199410/kanyu-app#73:7062123606`，
  phone_fail_count 2–5（美国20 为 5）。
- 全部 25 条 first_fail_ts 均为 1795166940（2026-11-20 17:29 CST
  手动上报轮次）。
- 全部 25 条在回填前已回到库存（status 全 candidate），25/25 复活属实。
- 11-06 blocklist 11 行未动（仍在表里）；其中 7 条 ss 202.50.253.x:19999
  在库内且 last_result='pass'，仅靠端口规则挡在严格集外——这正是
  本机制要堵的同类漏洞。

reason 统一为 `phone-fail-20261121`（与 11-06 前例
`phone-fail-20261106` 同制）；逐条原始裁决见审计文件的 verdict /
decision_ref / mechanism 字段。

### 2.2 回填脚本（`backfill_blocklist.py`，仅标准库）

- 默认 `--dry-run`（只读逐条审计）；`--check`（只读完整性验证）；
  `--apply`（写操作）。
- `--apply` 顺序：只读预检（冲突即拒绝，不备份、不写库）→ 备份
  （SHA-256 校验）→ 单事务写 blocklist + audit 行 → 写后验证。
  幂等（重跑 inserted=0）；任一步失败回滚。
- live 路径（`/opt/free-node-program/data/pool.db`）须显式
  `--allow-live` 才接受 `--apply`，且仍须 `--backup` 与 `--by`。
  生产写入须用户明确授权——本差异不执行。
- 不删 nodes / node_tests；只增 blocklist + audit 行。
- audit 行沿用 `db.log_audit` 的行格式，但不用 `log_audit()` 本身
  （它每次调用即 commit，会破坏单事务原子性）。
- 注意：audit 表受既有 30 天保留策略（`db.prune_old`）约束；长期
  审计依据以本 JSON 文件 + prune-ledger.jsonl 为准。

### 2.3 统一筛查（`screening.py`）

- 阻止清单 = blocklist 表 + `rejected_nodes.json`，语义分开：
  blocklist 是“曾清退、禁复活”；rejected 是“GPT 拒绝准入”。
- `screen_records`：阻止清单优先于 pre_filter；被禁入的记录不进
  测试集，也不产生“通过 pre_filter”的假象。
- `strict_candidates`：P1-2 严格漏斗口径（样本 ≥20、通过率 ≥0.5、
  端口 ≠19999、last_result='pass'、24h 内、最近一次通过 ≤300ms）
  + blocklist / rejected 排除，返回（行、被排除行及原因）。
- 抓取仍可存审计记录（cmd_crawl 不改）；测试可隔离诊断
  （cmd_test 不改）；正式发布已查 blocklist（cmd_publish /
  build_candidate.py 现状已确认，不重复改）。
- 漏斗是三元组级视图，不能区分同一三元组的不同配置变体
  （例如有 SNI 与无 SNI 的 vmess 变体）；变体级准入以
  screen_records / pre_filter 为准（见 §3.3）。

### 2.4 解禁（`unblock_node.py`）

- 只接受显式人工调用，不设自动触发；不因重抓、改名、历史 pass
  自动解禁。
- `--apply` 须 `--approved-by` + `--decision-ref` + `--evidence`
  三者齐全；先备份（SHA-256 校验），单事务删 blocklist 行 +
  写 1 行 audit（action=blocklist-unblock）；绝不删 nodes /
  node_tests / 既有 audit 历史；不设 `--allow-data-loss`。
- 三元组在 `rejected_nodes.json` 里时拒绝（须先由 GPT 另行裁决
  移出拒绝清单）；不在 blocklist 里时拒绝（无可解禁之物）。

### 2.5 rejected 清单（`rejected_nodes.json`）

- 1 条：vmess:443（GPT 拒绝，精确三元组见 rejected_nodes.json），
  decision_ref `zsh199410/kanyu-app#73:7115205068`（GPT 2026-11-24
  06:00 裁决不合格；单次复测通过 76.0ms 不自动恢复）。
- 同一 host 不同端口是不同三元组，不自动同拒（该 host 的 :8443 /
  :2083 / :80 行不在清单内）。

## 3. N3 SNI 准入

### 3.1 规则（`_vmess_no_sni`，rules.py 与 tester.py 同款同序）

vmess + TLS + 拨号 host 能解析为 IP 地址 + SNI 缺失/空/空白/
字面 `"<nil>"` → 拒绝准入，原因 `vmess-no-sni`，保留库存。
拨号 host 为合法 DNS hostname 时不拒绝（hostname 本身就是有效
证书身份）。绝不补猜 SNI、绝不跳过证书验证。

- 落点：`pre_filter` vmess 分支末尾（tls → net → uuid 之后），
  不扰动已有原因计数；`_filter_reason` 同款同序同原因串。
- `build_surge_line` vmess 分支加同款防御性检查（未走 pre_filter
  的路径误入时直接抛错、计 build_failed），代码内已标注为可裁剪
  的防御纵深：若 GPT 只要严格的 pre_filter/_filter_reason 范围，
  可删此两行。
- `build_config` 不动（:1270 根因在配置生成，无 SNI 时不设
  server_name 是正确行为；筛查层拒准入即可）。
- 与 #127 的重叠：本补丁以 live 版 rules.py 为基线（不含 #127 的
  B10 改动）。`rules-n3.patch` 的 hunks 与 #127 的 B10 hunks
  行位不重叠（B10 在 trojan/ss 密码分支与 vmess uuid 检查；
  N3 在 vmess 分支 missing-uuid 之后）；若 #127 先合并，N3 调用
  行改插在 comma-uuid 检查之后即可，helper 本身与上下文无关。

### 3.2 影响面（2026-11-24 11:55 新鲜抓取实测，4023 条，10/10 来源）

- vmess+TLS 1015 条，其中无 SNI 619 条（61.0%）。
- 无 SNI 中 IP 拨号 462 条（N3 拒准入：其中 456 条原因
  vmess-no-sni，另 6 条 grpc/h2 被更早的 unsupported-transport 拒，
  合计 462 条全部排除在候选外）；DNS 拨号 157 条（N3 不拒，
  占无 SNI 的 25%——朴素“无 SNI 全拒”会误伤这 157 条）。
- :1270 无 SNI 16 条，全部 IP 拨号，全部被 N3 拒。
- 无 SNI 来源分布：matin-vmess 515、alirewa-config 96、
  chenzhihan-base64 8。
- sni 取值分布：缺失（None）618、字面 `"<nil>"` 1；空字符串在
  抓取解析层已归一为 None（crawler.py:275）。

### 3.3 口径说明（诚实口径）

- 619/1015 是风险口径，不等于全部实测死亡：上游同一三元组在
  不同抓取轮次会以不同 sni 发布（有 SNI 时测得过，通过；无 SNI
  时失败）。实证：某 :1270 三元组在 11-22 全天 fail（curl-failed），
  11-23 14:47–19:47 四次 pass（274–333ms）；
  当前抓取轮次该变体 sni=None。
- DB 严格漏斗是三元组级视图，不能区分变体：9 条回填后严格集里
  4 条是 :1270 三元组，其中 3 条当前变体无 SNI、1 条有 SNI
  （另 1 条 :1270 三元组，sni=xmfhlpy.com，N3 放行）。N3 在记录级
  （新鲜变体）生效，才是正确层。
- 4 条 :1270 的 6/6 对照是该样本证据（P1-3），不是全集结论；
  其他端口须验证（本轮只验证了 :1270 的 16 条与全量分布）。

## 4. 隔离测试（75/75 通过）

运行：`python3 tests/test_integration_03.py`（快照副本
`work/pool-snapshot.db` 2026-11-24 11:52 UTC；脱敏夹具
`work/crawl-20261124-desensitized.json` 4023 条，uuid/password
已替换为占位符；live 库 0 写入——复核时 live blocklist 仍 11、
nodes 7798、0 行新 audit）。

- Part A 回填（17 项）：dry-run 25 absent 0 conflict 且未写库；
  --check 回填前 exit 1、回填后 exit 0；--apply 备份 SHA 一致、
  blocklist 11→36、audit +25、nodes/node_tests 一字节未变、
  逐条 reason/by 正确；幂等重跑 inserted=0 且 audit 不重复；
  冲突（同三元组不同 reason）fail-closed exit 1 且不备份不写库；
  live 路径无 --allow-live 拒绝（exit 2）。
- Part B N3（31 项）：6/6 对照复现（4 条失败变体 sni None/""/空白/
  "<nil>" 双入口同拒 + build_surge_line 抛错；3 条对照 sni=
  xmfhlpy.com 双入口同放）；DNS hostname 不误拒；IPv6 拨号同拒；
  非 TLS 仍走 vmess-non-tls；trojan 不受影响；夹具实测 1015/619/
  462/157 全部复现；:1270 16 条全拒。
- Part C 筛查（10 项）：严格集 21→9，排除 12 条全在 25 条集内，
  5 条复活候选全排除；9 条中 3 条 :1270 无 SNI 变体被 N3 记录级
  排除；合成被拒三元组（strict 资格）被 rejected-gpt 排除。
- Part D 解禁（9 项）：dry-run 不写库；缺三要素拒绝；不在
  blocklist 拒绝；rejected 清单内拒绝；完整参数 --apply 成功，
  blocklist 36→35、audit +1、nodes/node_tests 未动。
- Part E 口径复核（5 项）：见 §5。

## 5. 口径更正（重要）：15→10 是误数，实为 15→4

P1-2 的“15 条可用、其中 5 条复活、真正新合格 10 条”只核对了
R1–R4 allowlist 的 15 条删除，漏了 10:55/12:55/13:55 的 10 条
自动清退。本轮用 25 条全集逐条复核 P1-2 的 16 条新鲜 ≤300ms：

- 16 条中 11 条在 25 条回填集内（其中 6 条是自动清退：
  伊朗12、美国22、伊朗7、伊朗14、美国21、美国43）；
- 1 条为 GPT 已拒（vmess:443，见 rejected_nodes.json）；
- **真正新合格节点 4 条**：au1rxx vmess、chenzhihan trojan、
  matin-ss、matin-vmess 各 1 条（3 个独立组）。
- DB 严格集口径：21 条 → 回填排除 12 条 → 9 条；9 条中 1 条是
  已在正式池的加拿大，3 条 :1270 当前变体无 SNI（N3 记录级排除），
  **补位候选 5 条**（与新鲜口径的 4 条新节点 + 1 条有 SNI 的 :1270
  一致）。

影响：集成-05“先补位后删”（Q4 分支 A，正式池始终 ≥22）仍可行，
但补位池是 5 条不是 10 条；删 4 条香港钉选（香港8/24/25/39）须
先补 ≥4 条，余量只剩 1 条。组批可行性（集成-04）须按 4 条新节点
重算，不得沿用 P1-2 的 10 条口径。

## 6. 22 行下限与补位联动（Q4 分支 A，方案，不执行删除）

- 分支 A：先补位后删，正式池始终 ≥22；或满足相同门禁的原子替换。
- 补位来源：§5 的 5 条候选（须先走试用池手机 5G 验证 + 转正门禁，
  属集成-04/05，不在本差异内）。
- 删除对象（方案）：香港8/24/25/39（可信 cellular 失败 8/8/10/10，
  0 成功）；香港34 保留观察 48 小时（自 2026-11-24 起算，当日有
  Wi-Fi 成功 5 次）；香港/香港2 不动。
- 删除执行时须用户明确下达（人工钉选变更）；AUTO_PRUNE 保持 OFF。

## 7. 未解决阻塞与待定落点

- B1 仍 BLOCKED（探针侧改动不在本差异内；集成-01 的探针侧契约
  变化仍待解决）。
- G6：合格控制清单初始为空（21 钉选全 unknown）；真实 READY
  继续 BLOCKED。
- B5：HMAC 密钥创建与 unit 改动不在本轮生产许可内。
- O1 扩展裁决（GPT 7121245603：trojan gRPC 与 ss 非 AEAD 纳入
  协议兼容性检查）落在 lineage_adapter.admission_gate 的一行扩展
  上，属 #127 的后续或集成-04，不在本差异内实现。
- 删除路径加固（删除与 blocklist 写同一事务）属集成-05/闭环范围，
  本差异不改 auto_prune.py；精确位置：auto_prune.py
  `confirm_prune_publish` / ALLOWLIST_DELETE 处理处（约 1083 /
  1245–1330 行）——saga 设计：先写 blocklist 再发布，失败则
  补偿回滚并报 BLOCKED。
- 25 条回填与正式池变更均须独立 PR、隔离测试及用户明确生产授权。
- 试用池 TTL 2026-11-28；试用探针因池内仅 1 节点已暂停上报。

## 8. 生产状态（本差异未动）

正式池 22 行（21 钉选＋加拿大），SHA
9e44841b177bb40463afb15f27fe2c801c9657257f463289dcea5f8051a1ebd4；
AUTO_PRUNE=OFF；#124 PAUSED；#125 v4 冻结；#126/#127 待 GPT
源码审查；live blocklist 仍 11 行（全是 11-06 的）。
