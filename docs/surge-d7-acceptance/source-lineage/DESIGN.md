# Module 2：多来源归属 v3 — 节点稳定身份 + 全来源血缘

## 背景（GPT 裁决三 + Review 6031702642）

`nodes.source` 只存一个来源（最后一次抓取）。v2 曾以 `(protocol, host, port)`
为稳定身份、用 `last_seen` 选主来源、把未知来源计入多样化分母、先 commit
后 verify。GPT Review 6031702642（COMMENTED，2026-11-24 08:23:02）指出 5 项
实质设计缺口，暂不批准迁移或生产接入。本 v3 逐项修复（见下）。

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
  本轮未核实（未读现网抓取器配置），由调用方传入为准。

## 设计 v3

### 1. 稳定身份 = 配置变体（修复缺口 1）

节点稳定身份 = `(protocol, host, port, config_fingerprint)`。

- `config_fingerprint(config)`：对解析后的订阅配置 dict 做 SHA-256，
  输入先去掉凭据字段（password / uuid / id / user / token / secret 等）
  与展示字段（name / remark / url / raw），再按 key 排序做 canonical JSON。
  只差密码或只差 UUID 的两个配置指纹相同；SNI、传输、path、TLS、ALPN、
  flow 任一不同指纹就不同。凭据绝不进入指纹、数据库、日志或 PR。
  传入原始 URI 字符串会抛错——调用方必须先解析订阅行，再传 dict。
- 指纹只能在抓取时算出。历史三元组没有配置数据，**绝不臆造**：
  迁移回填时每个节点只得到一个 `fingerprint='legacy'` 变体
  （verified=0，无观测时间），它永远不能作为任何变体的证明。

### 2. 主来源仅作展示；多样化看“合格来源组”（修复缺口 2）

- `primary_source()` 只返回最近一次见到的来源（任何状态，含 legacy），
  明确标注 DISPLAY ONLY，**不可**用于多样化或发布判定。
- `qualified_source_group()` 是独立判定：某变体当且仅当存在一次
  对该变体的观测，来源同时满足——(a) 已验证（真实指纹 + 真实抓取证据）、
  (b) 注册表里状态为 `active`、(c) 属于一个已确认的独立来源组、
  (d) 新鲜（last_seen 在 `fresh_within_seconds` 内，默认 24h）——
  才算合格，返回该来源组名；否则返回 None。
- `SourceRegistry`（调用方传入）：`groups`（组名 → 来源列表，镜像同组；
  同一来源出现在两个组是配置错误）与 `status`（来源 → active/paused/
  disabled）。未在注册表里的来源状态为 `unverified`，永不合格。
  来源状态变更另有只追加的 `source_status_log` 审计表
  （`set_source_status` / `current_source_status` / `registry_from_log`）。

### 3. 多样化：先拒绝，再计数（修复缺口 3）

`batch_diversity(conn, registry, candidates, now)`：

- 候选是变体列表 `(protocol, host, port, fingerprint)`。
- 先拒绝：重复变体、以及无合格来源组（未知 / 未验证 / 暂停 / 停用 /
  legacy / 过期证据）的候选，全部排除在一切计数之外，并列入
  `rejected`（附原因）。未知来源**不进分母**，不可能再把主导来源稀释过关。
  GPT 的例子 `A,A,B,C,未知,未知` 在 v3 下：未知被拒，A 占 2/4 = 0.5 > 1/3，
  不通过（v2 会算成 2/6 = 1/3 而放行）。
- 每个被接受的变体恰好贡献 1，按其合格来源组计数。
  通过条件：合格来源组数 ≥ 3 且任一组占比 ≤ 1/3（按被接受总数算）。
- 本模块永不碰 `node_tests` / `phone_failures`：补录来源不能清除
  节点自身的失败史。

### 4. 观测记录：事件级去重 + 时间单调 + 真实证据（修复缺口 4）

`record_sighting(conn, protocol, host, port, fingerprint, source, ts, evidence, event_id=None)`：

- 指纹必须是真实 64-hex（`legacy` 只允许迁移回填产生，观测传入即抛错）。
- `evidence`（抓取运行 / 批次 ID）必填、非空；时间戳必须是非负整数。
- 事件级去重：同一 `event_id` 重复提交是 no-op；无 `event_id` 时按
  (变体, 来源, ts) 去重，精确重放也是 no-op（不增计数、不动时间）。
  所有事件写入 `sighting_events` 表备查。
- 时间单调：`first_seen = min(...)`，`last_seen = max(...)`——乱序或重放
  的证据永远不能把 `last_seen` 往回拨。
- 历史 `nodes.source` 回填时只标 `legacy/unverified`，且 first_seen /
  last_seen 置 NULL——节点的全局时间绝不冒充该来源的有效观测时间。

### 5. 迁移：事务内验收 + 可验证备份 + 凭备份回滚（修复缺口 5）

`migrate_node_sources.py`：

- 预检 fail-closed：缺表、缺列、已存在 v2 布局的 `node_sources`（7 列无指纹）、
  或 v3 表结构不符预期，退出 1，一个字节都不动。
- 先备份（SQLite backup API），存到 `--backup-dir` 下唯一时间戳文件名，
  永不覆盖；备份须通过校验（integrity + 行数与现库一致）才继续。
- 建表 + 回填 + 校验全部在一个事务里：**verify 在 commit 之前**；
  任一校验失败即 ROLLBACK，退出 1，不留半截表。
- `--check` 用只读连接（`mode=ro`）打开，什么都不写。
- `--rollback` 必须带 `--backup <文件>`：先校验备份；再检查现库是否有
  备份之后新增的已验证血缘行——有则拒绝（除非显式 `--allow-data-loss`）；
  然后用 backup API 把整个库恢复到备份点并校验。**绝不无保护 DROP TABLE**。
  注意：回滚恢复的是整个库，备份之后测试器/抓取器的写入也会丢失，
  因此迁移须在停抓取器、停测试器的窗口做。

### 新表（v3）

```sql
node_variants   (protocol, host, port, fingerprint, first_seen, last_seen, verified)
  -- fingerprint='legacy' 表示历史变体（无配置、无观测时间、verified=0）
node_sources    (protocol, host, port, fingerprint, source, first_seen, last_seen,
                 sighting_count, verified, last_evidence)
sighting_events (event_id PK, protocol, host, port, fingerprint, source, ts,
                 evidence, recorded_at)
source_status_log (id, source, status, changed_at, reason)  -- 只追加审计
```

## 测试（test_source_lineage.py，86/86 通过）

生产 pool.db 快照的本地副本上实测（7784 节点、247,365 条 node_tests）。
合成节点用 TEST-NET 地址（203.0.113.0/24）与合成配置指纹，不含真实节点身份与凭据。

- 指纹：64-hex、确定性；只差密码/UUID 指纹不变；SNI/传输/path 任一不同
  指纹就变；纯凭据配置与原始 URI 抛错。
- 观测：首次/后续/乱序/更早时间单调性；精确重放与重复 event_id 是 no-op；
  空证据、坏时间戳、legacy 指纹观测均抛错；失败史行数不变。
- 变体：同三元组两指纹 = 两变体；同三元组同指纹两来源 = 一变体两来源行。
- 资格：仅暂停源 / 仅过期证据 / 仅未注册来源均无合格组；暂停+有效源并存
  时取有效组；镜像两源同属一组；主来源展示仍可见暂停源（仅展示）。
- 多样化：GPT 例 `A,A,B,C,未知,未知` 不通过（A 占 2/4）；3 变体/3 组通过；
  重复变体被拒；全不合格则总数 0、不通过；镜像组只计一组；失败史不动。
- 迁移：`--check` 只读（文件哈希不变、不建表）；首次迁移回填 7784 变体/
  7784 来源行、0 已验证行、legacy 行无观测时间、无证据；二次迁移幂等
  （回填 0）；强制校验失败时事务回滚、不留表、备份仍在；已存在 v2 布局
  的表直接 fail-closed；`--rollback` 无 `--backup` 拒绝（exit 2）；
  有备份后新增已验证行时拒绝回滚，加 `--allow-data-loss` 才恢复；
  恢复后行数与 integrity 与备份一致。
- 状态日志：取最新状态、未记录为 unverified、`registry_from_log` 可用、
  坏状态抛错。

## 与生产的关系

- **部署**：先由 GPT 评审本 v3；再在隔离环境验证；通过后在停抓取器、
  停测试器的窗口跑迁移（约 1 分钟，只加新表），然后部署抓取器的
  `record_sighting` 调用（抓取器须在解析订阅时算指纹并传 evidence 与
  event_id；注册表 groups/status 从抓取器配置传入）。
- **回滚**：`--rollback --backup <备份文件>` 恢复整个库到备份点。
- **不降低门槛**：多样化（≥3 独立来源组、任一 ≤1/3）与新鲜性（≤300ms）
  不变；本模块只让来源判定更准确，不放宽任何规则。
- **未核实**：来源启用/暂停状态在抓取器配置文件里的真实存放位置
  （未读现网抓取器配置）；真实试用/抓取流程的端到端集成。
