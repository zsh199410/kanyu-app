# 集成-03：持久禁入（N2）+ SNI 准入（N3）

独立差异包（与 PR #125/#126/#127 分离）。只做差异包 + 隔离测试，
不实施生产：不改 live 文件、不写生产 blocklist、不删除任何节点、
不改 unit、不创建密钥、不动 live 探针脚本。

- 建议分支：`integration-03-anti-resurrection-sni`
- 建议目录：`docs/surge-d7-acceptance/integration-03-anti-resurrection-sni/`
  （与 #126/#127 布局一致）
- 基线：live `pool/`（2026-11-24 11:52 取回核对，rules.py / tester.py /
  crawler.py / db.py / cli.py / auto_prune.py /
  production_cycle.py / import_per_observation_v2.py /
  import_phone_observations.py 原文在 `work/live/`；另见
  `work/prod-chain/`：live 单写手链 production_cycle.py /
  legacy_source_adapter.py / pool_db_source.py /
  candidate_contract.py / safe_additions.py / single_writer.py，
  md5 已核对一致）
- **v2（Review 6033772552 收口，2026-11-24 13:xx）**：见 §9。
  本包不再含自写的 `build_candidate.py`——真实组批模块是
  staging 的 `build_candidate.py`（single-writer 目录），v2
  通过 `make_preview` 真实入口测试它，不再用未接线的复刻。

## 1. 改动一览

| 文件 | 性质 | 规模 |
|---|---|---|
| `pool/backfill_blocklist.py` | 新增：N2 回填脚本（v2：Backup API + 事务内重核对 + 逐条 reason + 决策日志） | 384 行 |
| `pool/blocklist_backfill_20261121.json` | 新增：25 条逐条审计记录 | 556 行 |
| `pool/blocklist_common.py` | 新增：严格 rejected 加载、不可变决策日志、SQLite Backup API、严格证书身份校验 | 约 280 行 |
| `pool/screening.py` | 新增：统一筛查（blocklist + rejected + pre_filter + 严格漏斗） | 约 170 行 |
| `pool/rejected_nodes.json` | 新增：GPT 已裁决拒绝清单（1 条） | 1 行 |
| `pool/unblock_node.py` | 新增：解禁脚本（v2：生产路径禁用，仅 dry-run；门控后路径仅隔离演练） | 240 行 |
| `pool/rules.py` | 修改：N3（live 186 → 218 行，v2 严格版） | 见 `rules-n3.patch` |
| `pool/tester.py` | 修改：N3（live 185 → 212 行，v2 严格版） | 见 `rules-n3.patch` |
| `rules-n3.patch` | N3 两文件统一 diff（+48 / −0，纯加法；v2 重新生成，119 行） | 119 行 |
| `cli-v2.patch` | cmd_test / cmd_publish 接入统一阻止清单 + 发布 guard 版本复核（a/pool/cli.py） | 157 行 |
| `pool-db-source.patch` | **v2 新增**：live 发布链 `pool_db_source.read_db_snapshot` 并入 rejected 清单（a/single-writer/pool_db_source.py） | 109 行 |
| `tests/test_integration_03.py` | 隔离测试（v1 75 项，v2 更新为 81 项） | 496 行 |
| `tests/test_integration_03_v2.py` | **v2 新增**：Review 收口针对性测试（Parts F–L，155 项） | 1191 行 |
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

reason 按 verdict 区分（v2 更正，见 §5）：17 条
`phone-fail-20261121`（DELETE_CANDIDATE_PHONE 与 allowlist 清退），
8 条 `over-target-20261121`（DELETE_OVER_TARGET 容量裁剪）。
8 条 DELETE_OVER_TARGET 不得被记为 phone-fail；逐条原始裁决见
审计文件的 verdict / decision_ref / mechanism 字段。

### 2.2 回填脚本（`backfill_blocklist.py`，仅标准库；v2 已加固）

- 默认 `--dry-run`（只读逐条审计）；`--check`（只读完整性验证）；
  `--apply`（写操作）。
- `--apply` 顺序：只读预检（冲突即拒绝，不备份、不写库）→ 备份
  （SQLite Backup API，0600、独占新文件、不覆盖、校验 integrity
  与完整逻辑内容；copy2 只拷主库文件会丢 WAL 已提交数据，v2 已
  弃用）→ BEGIN IMMEDIATE 单事务写 blocklist + audit 行 → 事务内
  重新核对、commit 前验证 blocklist 与对应 audit，失败回滚。
  幂等（重跑 inserted=0）；任一步失败回滚。
- 每次运行向不可变决策日志追加 1 条记录（只追加，0600，拒绝符号
  链接；长期审计不只依赖 30 天清理的 audit 表）。
- live 路径（`/opt/free-node-program/data/pool.db`）须显式
  `--allow-live` 才接受 `--apply`，且仍须 `--backup` 与 `--by`。
  生产写入须用户明确授权——本差异不执行。
- 不删 nodes / node_tests；只增 blocklist + audit 行；无整库恢复
  路径（不提供 `--restore` / 覆盖写回命令）。
- audit 行沿用 `db.log_audit` 的行格式，但不用 `log_audit()` 本身
  （它每次调用即 commit，会破坏单事务原子性）。
- 注意：audit 表受既有 30 天保留策略（`db.prune_old`）约束；长期
  审计依据以本 JSON 文件 + prune-ledger.jsonl + 决策日志为准。

### 2.3 统一筛查（`screening.py`）

- 阻止清单 = blocklist 表 + `rejected_nodes.json`，语义分开：
  blocklist 是“曾清退、禁复活”；rejected 是“GPT 拒绝准入”。
  `load_banlist` 一次加载同一受信版本（version = blocklist 三元组
  + rejected 三元组 + rejected 文件 version 的规范序列化 SHA-256）。
- `screen_records`：阻止清单优先于 pre_filter；被禁入的记录不进
  测试集，也不产生“通过 pre_filter”的假象。
- `strict_candidates`：P1-2 严格漏斗口径（样本 ≥20、通过率 ≥0.5、
  端口 ≠19999、last_result='pass'、24h 内、最近一次通过 ≤300ms）
  + blocklist / rejected 排除，返回（行、被排除行及原因）。
- `load_rejected` 严格加载：文件缺失、JSON 损坏、entries 缺失/
  为空、重复、畸形、decision_ref 为空一律抛错，不悄悄变空。
- `verify_publish_guard`：发布前最后一道 guard，逐行解析核对，
  任一被禁三元组或无法解析的行即拒绝整批。
- 抓取仍可存审计记录（cmd_crawl 不改）；测试可隔离诊断
  （cmd_test 不改测试本身，但常规测试集须排除阻止清单内三元组，
  见 `cli-v2.patch`）；正式发布路径见 §9（live 链 + cli-v2.patch）。
- 漏斗是三元组级视图，不能区分同一三元组的不同配置变体
  （例如有 SNI 与无 SNI 的 vmess 变体）；变体级准入以
  screen_records / pre_filter 为准（见 §3.3）。
- 三元组级禁入只是保守禁入：它只说明“该三元组曾清退、不得复活”，
  不作任何新配置变体的健康证明；新变体的健康须凭新鲜 VPS / 手机 /
  控制证据重新判定，不得用旧三元组历史冒充新变体证据。

### 2.4 解禁（`unblock_node.py`；v2：生产路径已禁用）

- 只接受显式人工调用，不设自动触发；不因重抓、改名、历史 pass
  自动解禁。
- **生产 `--apply` 已禁用**（`PRODUCTION_UNBLOCK_ENABLED=False`）：
  完整参数也拒绝（exit 2，DISABLED），不备份、不写库；仅保留隔离
  dry-run / 演练。未来启用须绑定真实批准记录、精确配置变体的新鲜
  VPS / 手机 / 控制证据及独立审核，保留同入口其他变体禁入，禁止
  用自填字符串充当凭证。
- 门控后路径（仅进程内翻转常量，模拟未来独立审查启用）仍受事务内
  快照比对约束：预读后外部改行 → 拒绝并回滚；决策日志 1 条。
- 三元组在 `rejected_nodes.json` 里时拒绝（须先由 GPT 另行裁决
  移出拒绝清单）；不在 blocklist 里时拒绝（无可解禁之物）。
- 解禁只删 blocklist 行 + 写 1 行 audit（action=blocklist-unblock）；
  绝不删 nodes / node_tests / 既有 audit 历史；不设 `--allow-data-loss`。

### 2.5 rejected 清单（`rejected_nodes.json`）

- 1 条：vmess:443（GPT 拒绝，精确三元组见 rejected_nodes.json），
  decision_ref `zsh199410/kanyu-app#73:7115205068`（GPT 2026-11-24
  06:00 裁决不合格；单次复测通过 76.0ms 不自动恢复）。
- 同一 host 不同端口是不同三元组，不自动同拒（该 host 的 :8443 /
  :2083 / :80 行不在清单内）。
- **注意**：该条不在 live blocklist 表内（表内 11 行全是 11-06 的），
  live 链此前从未读过它；v2 用 `pool-db-source.patch` 把它并入
  live 链的 blocked_keys（见 §9）。

## 3. N3 SNI 准入

### 3.1 规则（`_vmess_no_sni`，rules.py 与 tester.py 同款同序；v2 严格版）

vmess + TLS + 无有效证书身份 → 拒绝准入，原因 `vmess-no-sni`，
保留库存。有效证书身份指严格校验通过的 SNI（合法 DNS hostname
或合法 IP SAN；占位符、空白、非法 hostname、异常 IP 形式一律无效）。
SNI 无效时：拨号 host 为 IP → 拒绝（IP 拨号无 SNI 无法校验）；
拨号 host 为严格合法 DNS hostname → 不拒绝（hostname 本身就是
有效证书身份）；拨号 host 既非 IP 也非合法 DNS → 拒绝（不能只因
ipaddress 抛错就认定是合法 DNS）。绝不补猜 SNI、绝不跳过证书验证。

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
  组合回归见 v2 测试 Part K（B10 / B10-EXTENSION / O1 / N3
  同时生效）。

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
- v2 严格校验不改变上述计数：v2 无效证书身份 619 条与 v1 无 SNI
  619 条一致，157 条 DNS 拨号 host 全部通过严格 DNS 校验，
  292 个非空 SNI 0 个新判无效。

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

## 4. 隔离测试

运行环境：VPS /tmp 隔离（本轮因 /tmp tmpfs 余量不足，改用磁盘
隔离目录 `/root/i03-run/`，TMPDIR 指向其下；live 0 写入）。
快照副本 `work/pool-snapshot.db`（2026-11-24 11:52 UTC；与 v1
快照 md5 一致）；脱敏夹具 `work/crawl-20261124-desensitized.json`
4023 条，uuid/password 已替换为占位符。

- `tests/test_integration_03.py`（v2 更新版）：**81/81 通过**
  （v1 75 项 + v2 新增 6 项：A3 备份 integrity/0600/决策日志/
  逐条 reason、A4 决策日志追加、D5 生产解禁禁用、D6 门控后路径）。
- `tests/test_integration_03_v2.py`（v2 新增）：**155/155 通过**，
  Parts F–L：
  - F WAL 安全备份（Backup API 含 WAL 未 checkpoint 数据；copy2
    对照丢数据；已存在/符号链接/同文件/源缺失拒绝；并发写入下
    备份一致）。
  - G 事务内重核对（同键异 reason 不被 INSERT OR IGNORE 吞掉、
    commit 前验证失败回滚；同 reason 幂等跳过）。
  - H 解禁禁用 + 严格 rejected 加载 + 决策日志 + 无整库恢复路径。
  - I 端到端防复活（真实打补丁 cli：cmd_test 0 行新测被禁三元组；
    cmd_publish 输出 24 行，21 钉选 + 加拿大 + 2 干净轮换，0 被禁；
    guard 版本中途变化即拒发且文件一字节未变）。
  - J N3 严格证书身份负例（占位符/空白/非法 hostname/异常 IP /
    非字符串 SNI / 非法 host；合法 DNS 与 IP SAN 放行；夹具回归
    456 / 157 与 v1 口径一致）。
  - K B10 / B10-EXTENSION / O1 / N3 组合回归（#127 rules 与本包
    rules 组合，12 项全过）。
  - L live 发布链统一阻止清单（pool-db-source.patch + make_preview
    + _preflight，19 项；见 §9）。

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
- verify_promotion.py（试用转正 READY 判定，只读报告）本身不查
  阻止清单：READY ≠ 入池；正式入池的唯一入口是 production_cycle
  的 build_candidate（查 blocked_keys），见 §9。是否在 READY 侧
  也排除被禁三元组，属集成-01/05 的判定口径，不在本差异内改。

## 8. 生产状态（本差异未动）

正式池 22 行（21 钉选＋加拿大），SHA
9e44841b177bb40463afb15f27fe2c801c9657257f463289dcea5f8051a1ebd4；
AUTO_PRUNE=OFF；#124 PAUSED；#125 v4 冻结；#126/#127 v2 待 GPT
复审；live blocklist 仍 11 行（全是 11-06 的）；live 发布链
（production_cycle 每小时 :55）正常运行，12:55 周期
SAME_BYTES_PUBLISHED。

## 9. v2：Review 6033772552 收口（四项，全部最小差异）

### 9.1 P0 写入安全

- backfill 与 unblock 的备份改用 SQLite Backup API（`blocklist_common.sqlite_backup`）：
  独占新备份文件、0600、拒同文件及别名、不覆盖、校验完整逻辑内容
  与 integrity；主库 SHA 相同不证明已提交 WAL 数据包含在备份
  （F1/F2 对照实测：小库未 checkpoint 时 copy2 得空库）。
- 回填冲突预检在 BEGIN IMMEDIATE 之前、写后验证在 commit 后；
  事务内重新核对，commit 前验证 blocklist 与对应 audit，失败回滚；
  同键异 reason 不被 INSERT OR IGNORE 吞掉（Part G）。
- 禁止整库恢复覆盖现有历史：两脚本均无 `--restore` / 覆盖写回
  命令（Part H6 静态 + 行为双重核对）。

### 9.2 P0 解禁安全

- 生产 `--apply` 禁用（`PRODUCTION_UNBLOCK_ENABLED=False`），仅保留
  隔离 dry-run / 演练；未来启用须绑定真实批准记录、精确配置变体
  的新鲜 VPS / 手机 / 控制证据及独立审核，保留同入口其他变体禁入，
  禁止用自填字符串充当凭证。
- `load_rejected` 缺文件时抛错，不返回空集（fail-closed）。
- 事务内比较原 blocklist 记录 / 决策版本后再操作并记录精确 identity；
  决策日志不可变追加（0600，拒绝符号链接），长期审计不只依赖
  30 天清理的 audit 表。

### 9.3 P0 禁止复活覆盖真实消费路径

**live 链核实结果**（只读核对，非推测）：

- live 每小时发布链是 `production_cycle.py --publish`（:55，
  release-ready 已存在，12:55 周期 SAME_BYTES_PUBLISHED），不是
  `pool/cli.py cmd_publish`（后者所属 pool-publish.service 已
  masked，属 legacy 路径；本差异仍用 `cli-v2.patch` 加固它，见下）。
- live 链：`_preflight` → `build_preview` → `make_preview` →
  staging `build_candidate(blocked_keys)` → `safe_overlay` →
  `assess_candidate(blocklisted_names)` → `single_writer.publish`
  （flock + legacy-ban proof + post-write SHA 复核）。
  `blocked_keys` 的唯一来源是 `pool_db_source.read_db_snapshot`
  读 blocklist 表；回填后（11→36）25 条自动被 live 链拒绝，无须
  改调用点。
- **缺口**：`rejected_nodes.json` 在 live 链里从未被读，且被拒三元组
  不在 blocklist 表内——live 链此前不会拒绝它。v2 用
  `pool-db-source.patch`（109 行，单文件单函数最小补丁）把它并入
  `read_db_snapshot` 的 `blocked_keys`，与 `screening.load_banlist`
  共用同一规范版本（banlist_version SHA-256，Part L1 两侧逐字节
  一致）；缺失/损坏即 `SourceRefused`，不悄悄变空。
- 覆盖的真实调用点（隔离实测，Part I + Part L）：
  筛查 `screen_records` / `strict_candidates`（I1/I2）→ legacy
  `cmd_test` / `cmd_publish` + 发布 guard（I5/I6/I7）→ live
  `make_preview` / `build_candidate` 组批与补位（L4：25 条被禁 +
  1 条已拒不得进入，2 条干净候选进入，21 钉选 + 加拿大共 24 行）
  → live `_preflight` 发布前守卫（L5：干净池放行，含被禁钉选名
  的池拒 `blocked_pins_reentered`）。
- **部署顺序**：`rejected_nodes.json` 须先于（或原子随同）
  `pool-db-source.patch` 部署到 `/opt/free-node-program/pool/`；
  否则打补丁后的发布链会因默认 rejected 路径缺失而 fail-closed
  拒绝每个周期（Part L2 实测）。

### 9.4 P1 N3 准入与组合回归

- `_vmess_no_sni` 改为严格版（`is_valid_cert_identity` /
  `is_valid_dns_hostname`）：占位符（大小写不限）、空白、非法
  hostname、异常 IP 形式一律无效；合法 DNS 作证书校验身份（不能
  只因 ipaddress 抛错认定是合法 DNS）；合法 IP SAN 按已明确支持
  契约处理，不推测上游。
- 保留 pre_filter / _filter_reason / build_surge_line 防御纵深，
  不补猜 SNI、不放松 TLS。
- #127 rules.py 与本 PR 重叠、#124 tester.py 仍暂停：只审最小 patch
  （`rules-n3.patch` 重新生成，119 行），禁止用整份旧文件覆盖
  其它差异；组合回归 Part K 验证 B10 / B10-EXTENSION / O1 / N3
  同时生效（12 项全过）。
