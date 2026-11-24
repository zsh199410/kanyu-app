# Module 2：多来源归属 v4 — 节点稳定身份 + 全来源血缘

## 背景（GPT 裁决三 + Review 6031702642 → 6032131494）

`nodes.source` 只存一个来源（最后一次抓取）。v3 按 Review 6031702642
修了 5 项缺口；GPT Review 6032131494（COMMENTED，2026-11-24 09:13）
认可模块一参考代码验收通过并冻结，同时指出模块二 v3 仍有 3 项
会影响实际发布和数据安全的契约缺陷，要求只收口这 3 项，不重做
已通过的功能。本 v4 逐项修复（见下）。模块二仍为隔离开发，
暂不批准生产迁移。

## 现网 schema 核实（快照本地副本，只读，2026-11-24）

- `nodes` 主键 `(protocol, host, port)`；列：source、name_hint、first_seen、
  last_seen、last_test_at、last_result、last_reason、pass_count、test_count、
  country、status。**无 SNI / 传输 / TLS / 认证 / 配置原文列**。
- `node_tests`：protocol、host、port、tested_at、result、reason、ms。
- `phone_failures`：protocol、host、port、reported_at、source、detail。
- `sources`：name（PK）、url、last_success、last_count、ok_count、fail_count；
  **无启用/暂停状态列**，快照里 url 全为 NULL；当前 6 个来源。
- 结论：配置指纹只能由抓取器在解析订阅时当场算出，库里算不出来；
  来源启用/暂停状态与分组关系也不在库里，须由调用方从抓取器配置传入，
  本模块不猜测。来源启用/暂停状态在抓取器配置文件里的真实存放位置
  本轮仍未核实（未读现网抓取器配置），由调用方传入为准。

## 设计 v4

### 1. 稳定身份 = 配置变体，HMAC 指纹区分认证变体（修复 v3 缺口 1）

节点稳定身份 = `(protocol, host, port, config_fingerprint)`。

- `config_fingerprint(config, key)`：对解析后的订阅配置 dict 做
  HMAC-SHA256（本地稳定密钥 + canonical JSON）。
  v3 的做法是先剥离 password/uuid 再做无密钥 SHA-256，测试甚至断言
  只差认证的配置指纹相同——这违反“认证变体也须区别”：失效节点
  可能借用另一节点的有效记录。v4 改为：
  - **密钥必填**：key（bytes 或 str，非空）由调用方从抓取器安全配置/
    环境传入；缺 key、空 key 均抛错，**没有任何无密钥回退**，
    绝不用简单无密钥口令散列。
  - **凭据进入 HMAC 输入**：password / uuid 等认证字段保留在 canonical
    输入里，只差认证的两个配置指纹不同；凭据只在解析进程内出现，
    HMAC 输出不泄露输入内容，指纹本身绝不携带凭据，凭据永不入库、
    永不进 PR、永不进日志。
  - **只剥离展示字段**：name / remark / url / raw 等展示字段去掉后
    再哈希；只差展示名的配置指纹相同。
  - **未知字段保守计入**：解析器输出里不认识的字段也进哈希——
    任何差异都产生不同指纹，而不是被静默丢弃。
  - **密钥管理**：密钥存在抓取器的安全配置里，不在仓库、不在库里。
    轮换密钥 = 全部重新算指纹；旧指纹行留在库里作历史变体，随
    last_seen 变旧而失去资格，绝不自动“晋级”为新指纹。
    测试用合成测试密钥，**绝不是生产密钥**。
  - **未核实**：真实抓取器的解析字段集合与值类型规范化（port 取 int、
    tls 取 bool 等）本轮未核实——未读现网抓取器配置；调用方须先规范化
    类型再传 dict，集成时必须核对字段集，不猜。
- 指纹只能在抓取时算出。历史三元组没有配置数据，**绝不臆造**：
  迁移回填时每个节点只得到一个 `fingerprint='legacy'` 变体
  （verified=0，无观测时间），它永远不能作为任何变体的证明。
  旧指纹不自动晋级：v3 的无密钥指纹与 v4 的 HMAC 指纹对同一配置
  是不同的值；v3 从未在生产运行，库里没有 v3 指纹需要迁移；
  即使有，本模块也绝不改写它们。现有失败史仍以旧三元组保守保留，
  换指纹绝不清空 `node_tests` / `phone_failures`。

### 2. 资格 / 批次证据边界（修复 v3 缺口 2）

- `qualified_source_group()`：某变体的观测年龄必须满足
  `0 <= age <= TTL`（默认 24h）。**未来时间戳（age < 0）按无效证据
  拒绝**，与过期证据（age > TTL）同等处理；未来观测被跳过后，
  同一变体更早的有效观测仍可由另一合格来源使该变体合格。
  年龄恰好等于 TTL 仍合格，超过则不合格。
- `record_sighting()`：`last_evidence` 与最新观测绑定。乱序的旧观测
  仍计为新事件（sighting_count 增长，first/last_seen 保持单调），
  但**不得**用旧证据覆盖较新时间的 `last_evidence`；只有时间戳
  不早于当前 `last_seen` 的观测才能更新它。
- `batch_diversity()`：**passes 必须无 rejected**。3 个合格组加 1 个
  未知/重复候选的批次不再通过。结果附带 `accepted_variants`
  （被接受的精确身份列表）与 `publishable`（与 passes 同值）。
  发布必须用 `rebuild_batch()` 从 `accepted_variants` 建一个
  **新批次**，再跑一次 `batch_diversity` 并要求 passes；
  **禁止发布原列表**——原列表仍含被拒绝的条目。
- **active + 24h 只是来源预筛**：它只说明该来源当前处于启用状态
  且在 24 小时内有过观测，**不证明**最新一次成功抓取仍包含该节点，
  也不证明 VPS 或手机通过了它。接入时必须把资格绑定到最新有效
  抓取批次与真实健康状态：只有最新有效抓取批次里确实出现、且
  VPS/手机健康检查通过的节点才能进入发布候选；本模块只做来源
  判定，不代替健康检查。

### 3. 多样化：先拒绝，再计数（v3 已修，v4 收口）

`batch_diversity(conn, registry, candidates, now)`：

- 候选是变体列表 `(protocol, host, port, fingerprint)`。
- 先拒绝：重复变体、以及无合格来源组（未知 / 未验证 / 暂停 / 停用 /
  legacy / 过期证据 / 未来时间证据）的候选，全部排除在一切计数之外，
  并列入 `rejected`（附原因）。未知来源**不进分母**，不可能再把主导
  来源稀释过关。GPT 的例子 `A,A,B,C,未知,未知` 在 v4 下：未知被拒，
  A 占 2/4 = 0.5 > 1/3，不通过。
- 每个被接受的变体恰好贡献 1，按其合格来源组计数。
  通过条件：**零拒绝** 且合格来源组数 ≥ 3 且任一组占比 ≤ 1/3
  （按被接受总数算）。
- 本模块永不碰 `node_tests` / `phone_failures`：补录来源不能清除
  节点自身的失败史。

### 4. 观测记录：事件级去重 + 时间单调 + 真实证据（v3 已修，v4 收口）

`record_sighting(conn, protocol, host, port, fingerprint, source, ts, evidence, event_id=None)`：

- 指纹必须是真实 64-hex（`legacy` 只允许迁移回填产生，观测传入即抛错）。
- `evidence`（抓取运行 / 批次 ID）必填、非空；时间戳必须是非负整数。
- 事件级去重：同一 `event_id` 重复提交是 no-op；无 `event_id` 时按
  (变体, 来源, ts) 去重，精确重放也是 no-op（不增计数、不动时间）。
  所有事件写入 `sighting_events` 表备查。
- 时间单调：`first_seen = min(...)`，`last_seen = max(...)`——乱序或重放
  的证据永远不能把 `last_seen` 往回拨；`last_evidence` 只跟最新观测走。
- 历史 `nodes.source` 回填时只标 `legacy/unverified`，且 first_seen /
  last_seen 置 NULL——节点的全局时间绝不冒充该来源的有效观测时间。

### 5. 迁移与回滚：事务内验收 + 无损回退（修复 v3 缺口 3）

`migrate_node_sources.py`：

- 预检 fail-closed：缺表、缺列、已存在 v2 布局的 `node_sources`（7 列无指纹）、
  或 v3/v4 表结构不符预期，退出 1，一个字节都不动。
- 先备份（SQLite backup API），存到 `--backup-dir` 下唯一时间戳文件名，
  永不覆盖；备份须通过校验（integrity + 行数与现库一致）才继续。
- 建表 + 回填 + 校验全部在一个事务里：**verify 在 commit 之前**；
  任一校验失败即 ROLLBACK，退出 1，不留半截表。
- `--check` 用只读连接（`mode=ro`）打开，什么都不写；**有问题时退出 1**
  （v3 的 bug：problems 非空仍 return 0，已修；integrity 也计入结论）。
- 已迁移分支按实际结论返回：integrity 失败时 `ok=false`、退出 1
  （v3 的 bug：integrity_ok=false 仍返回 ok=true/0，已修）。
- `--rollback` 必须带 `--backup <文件>`，**没有 `--allow-data-loss`
  开关**（已删除；传该参数是 usage 错误，退出 2）。回滚分两种，
  都是无损的：
  - **保留模式（默认）**：只要检测到备份之后的任何写入——
    既有键追加的新事件、来源状态变化、新增的 node_tests /
    phone_failures 记录——整库恢复即被拒绝，**一个字节都不改**：
    血缘表与全部历史保留（向后兼容），操作方停用新模块 / 抓取调用
    即完成回退。报告列出检测到的每一项变化。
  - **整库恢复**：仅适用于备份之后零写入的迁移窗口。须同时满足：
    备份校验通过且是不含血缘表的迁移前备份、写者已停机（先探测写锁）、
    `nodes` / `node_tests` / `phone_failures` 全量内容摘要与备份完全一致、
    血缘表只有迁移回填内容（无已验证行、无事件、无状态日志）。
    恢复后逐项校验与备份一致，否则失败。
  - 迁移后才建的备份（含血缘表）不是迁移前备份，直接拒绝。
- 注意：整库恢复会把整个库恢复到备份点，因此迁移须在停抓取器、
  停测试器的窗口做；保留模式不需要停机（它不改库）。

### 新表（v4 与 v3 相同，未改 schema）

```sql
node_variants   (protocol, host, port, fingerprint, first_seen, last_seen, verified)
  -- fingerprint='legacy' 表示历史变体（无配置、无观测时间、verified=0）
node_sources    (protocol, host, port, fingerprint, source, first_seen, last_seen,
                 sighting_count, verified, last_evidence)
sighting_events (event_id PK, protocol, host, port, fingerprint, source, ts,
                 evidence, recorded_at)
source_status_log (id, source, status, changed_at, reason)  -- 只追加审计
```

## 测试（test_source_lineage.py，129/129 通过，两遍）

生产 pool.db 快照的本地副本上实测（7784 节点、247,365 条 node_tests）。
合成节点用 TEST-NET 地址（203.0.113.0/24）与合成配置指纹，不含真实节点身份与凭据。
HMAC 测试密钥为合成测试密钥，绝不是生产密钥。

- 指纹：64-hex、确定性；**只差密码/UUID 指纹不同**（认证变体区分）；
  只差展示名指纹不变；未知字段进哈希；不同密钥指纹不同；缺 key/
  空 key 抛错；SNI/传输/path 任一不同指纹就变；HMAC 输出与无密钥
  SHA-256 不同（不静默升级）；纯展示配置与原始 URI 抛错；
  非 JSON 值抛错；凭据字符串不出在指纹输出里。
- 观测：首次/后续/乱序/更早时间单调性；**乱序旧观测不覆盖
  last_evidence**，新观测才更新它；精确重放与重复 event_id 是 no-op；
  空证据、坏时间戳、legacy 指纹观测均抛错；失败史行数不变。
- 变体：同三元组两指纹 = 两变体；同三元组同指纹两来源 = 一变体两来源行。
- 资格：仅暂停源 / 仅过期证据 / 仅未注册来源均无合格组；暂停+有效源并存
  时取有效组；镜像两源同属一组；主来源展示仍可见暂停源（仅展示）；
  **仅未来时间证据无合格组**，未来观测被跳过后更早的有效观测仍可合格；
  年龄恰好等于 TTL 合格，超过 1 秒不合格。
- 多样化：GPT 例 `A,A,B,C,未知,未知` 不通过（A 占 2/4）；
  3 变体/3 组通过且 publishable；**3 合格组 + 1 未知不通过，
  3 合格组 + 1 重复不通过**；由 `accepted_variants` 重建的新批次
  重跑通过；原列表 publishable 为 False；重复变体被拒；
  全不合格则总数 0、不通过；镜像组只计一组；失败史不动。
- 迁移：`--check` 只读（文件哈希不变、不建表），**有问题时退出 1**；
  首次迁移回填 7784 变体/ 7784 来源行、0 已验证行、legacy 行无观测时间、
  无证据；二次迁移幂等（回填 0）；**已迁移分支 integrity 失败时退出 1**；
  强制校验失败时事务回滚、不留表、备份仍在；已存在 v2 布局的表直接
  fail-closed；`--rollback` 无 `--backup` 拒绝（exit 2）；
  `--allow-data-loss` 已删除，传它即 usage 错误（exit 2）。
- 回滚（无损）：零写入窗口整库恢复成功，血缘表消失、行数与 integrity
  与备份一致；**既有键追加事件**、**状态变化**、**新增 node_tests 行**
  三种情况整库恢复均被拒绝且数据原样保留（事件计数、状态日志、
  新增测试行都在）；迁移后备份当回滚目标被拒（exit 1）。
- 状态日志：取最新状态、未记录为 unverified、`registry_from_log` 可用、
  坏状态抛错。

## 与生产的关系

- **部署**：先由 GPT 评审本 v4；再在隔离环境验证；通过后在停抓取器、
  停测试器的窗口跑迁移（约 1 分钟，只加新表），然后部署抓取器的
  `record_sighting` 调用（抓取器须在解析订阅时算 HMAC 指纹并传
  evidence 与 event_id；HMAC 密钥由抓取器安全配置传入；注册表
  groups/status 从抓取器配置传入）。
- **回滚**：默认保留模式——停用新模块 / 抓取调用，血缘表与历史保留；
  零写入窗口才可整库恢复到迁移前备份。没有丢数据开关。
- **不降低门槛**：多样化（≥3 独立来源组、任一 ≤1/3）与新鲜性（≤300ms）
  不变；本模块只让来源判定更准确，不放宽任何规则。
- **未核实**：来源启用/暂停状态在抓取器配置文件里的真实存放位置
  （未读现网抓取器配置）；真实抓取器的解析字段集合与值类型规范化；
  HMAC 密钥在生产安全配置里的存放位置；真实试用/抓取流程的端到端集成。
