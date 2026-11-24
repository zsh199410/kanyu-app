# Module 2：多来源归属 — 节点稳定身份 + 全来源血缘

## 问题（GPT 裁决三，评论 7115166096）

`nodes.source` 只存一个来源（最后一次抓取）。同一节点出现在多个上游时，
只有最后抓取的来源被保留，之前的来源记录丢失。后果：

- 37.19.198.236 在库里的来源从 alirewa-config 变成了 chenzhihan-base64
  （已暂停来源），按“暂停来源排除”规则被误排除，尽管它也来自 alirewa-config。
- 无法区分“节点只在来源 A 出现过”和“节点在 A 和 B 都出现过、最后一次是 A”。
- 多样化计数可能把同身份多抓取误算为多独立来源。

## 设计

### 稳定身份

节点稳定身份 = `(protocol, host, port)`，即 `nodes` 表的主键。
失败史（`node_tests`、`phone_failures`）本来就按该三元组建索引，与来源无关，
换来源不会清空失败史。

### 新表 node_sources（血缘）

```sql
CREATE TABLE IF NOT EXISTS node_sources (
  protocol TEXT NOT NULL,
  host TEXT NOT NULL,
  port INTEGER NOT NULL,
  source TEXT NOT NULL,
  first_seen INTEGER NOT NULL,
  last_seen INTEGER NOT NULL,
  sighting_count INTEGER NOT NULL DEFAULT 1,
  PRIMARY KEY (protocol, host, port, source),
  FOREIGN KEY (protocol, host, port) REFERENCES nodes(protocol, host, port)
);
CREATE INDEX IF NOT EXISTS idx_node_sources_identity
  ON node_sources(protocol, host, port, last_seen);
CREATE INDEX IF NOT EXISTS idx_node_sources_source
  ON node_sources(source, last_seen);
```

- 每个 (身份, 来源) 一行，记录首次/末次见到时间与见到次数。
- `nodes.source` 保留，作为“最后一次见到来源”的缓存（向后兼容），不再是唯一真相。

### 规则

1. **记录**（`record_sighting`）：节点从某来源被抓取时 upsert 该 (身份, 来源) 行，
   重复见到则 `sighting_count + 1` 并刷新 `last_seen`。不碰 `nodes`/`node_tests`/`phone_failures`。
2. **主来源**（`primary_source`）：血缘行中 `last_seen` 最大的来源；
   并列时 `sighting_count` 大者胜，再并列时来源名字典序最小者胜（确定性）。
3. **多样化计数**（`batch_diversity`）：一批候选节点按各自**主来源**计数，
   每个节点恰好贡献 1。无血缘行的节点计入 `None`，不增加 distinct 来源数。
   通过条件：distinct 主来源 ≥ 3 且任一主来源占比 ≤ 1/3。
4. **同身份多抓取不算多独立来源**：一个节点在 2 个来源出现过，仍是 1 个节点，
   多样化计数只算它的主来源。`distinct_source_count` 仅作报告用，不参与多样化判定。
5. **换来源不清空失败史**：`node_tests` 与 `phone_failures` 按身份键控，迁移与 upsert 均不改动它们。

### 迁移（migrate_node_sources.py）

- 幂等：建表 + 索引 + 从 `nodes.source` 回填（每个现有节点一行，
  first_seen/last_seen 取 nodes 的值，sighting_count=1）。
- 校验（fail-closed）：迁移前后 `nodes`/`node_tests`/`phone_failures` 行数不变、
  判活抽样不变、`integrity_check` 为 ok；任一不满足则退出码 1。
- `--check` 为 dry-run；`--rollback` 删表（`nodes`/`node_tests`/`phone_failures` 不动）。
- **不需要停机做迁移本身**（只加新表、不改现有表），但回填期间抓取器若写入新节点，
  须在回填后补一次 upsert（或停抓取器跑迁移）。部署时建议停抓取器，操作约 1 分钟。

## 测试（test_source_lineage.py，24/24 通过）

在生产 pool.db 快照的本地副本上实测（7784 节点、247,365 条 node_tests、70 条 phone_failures）：

- dry-run 不改库；迁移跑两次幂等（第二次回填 0 行）；回填行数 = 节点数（7784）；
  回填来源与 `nodes.source` 抽样一致；迁移前后行数与判活抽样不变。
- upsert：同一身份从 2 个来源记录 → 2 行血缘；重复见到 sighting_count 递增、last_seen 刷新。
- 主来源 = 最近一次见到；distinct 来源计数仅作报告。
- 换来源不清空失败史（node_tests/phone_failures 行数不变）。
- 多样化：3 节点 / 3 主来源通过；2 主来源不通过；1 主来源不通过；
  多来源节点只计一次（向主来源）；单节点多来源 distinct=1 不是 2；
  无血缘节点不增加 distinct 来源数。
- 回滚：删表后行数与 integrity 不变，合成节点保留。

## 与生产的关系

- **部署**：先由 GPT 评审本模块与测试；再在隔离环境验证；通过后在停抓取器窗口跑迁移
  （约 1 分钟，只加新表），然后部署抓取器的 `record_sighting` 调用。
- **回滚**：删 `node_sources` 表即可（`DROP TABLE`）；`nodes`/`node_tests`/`phone_failures`
  从未被改动，无需恢复。
- **不降低门槛**：多样化规则（≥3 来源、任一 ≤1/3）与新鲜性（≤300ms）不变；
  本模块只让来源判定更准确，不放宽任何规则。
