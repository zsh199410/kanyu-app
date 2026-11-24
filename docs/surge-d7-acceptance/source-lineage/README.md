# Source lineage v3 — 节点稳定身份 + 全来源血缘

**离线参考与迁移工具；不改生产，不部署。**
本模块依据 GPT Review 6031702642 重写 v2 的 5 项设计缺口（见 DESIGN.md）。
评审结论是静态源码审查，不是运行测试结果；本模块的测试证据见下。

## 文件

| 文件 | 说明 |
|---|---|
| `source_lineage.py` | 血缘模块 v3：`config_fingerprint` / `SourceRegistry` / `record_sighting`（事件级去重、时间单调、证据必填）/ `primary_source`（仅展示）/ `qualified_source_group` / `batch_diversity`（先拒绝、再计数）/ `set_source_status` 等 |
| `migrate_node_sources.py` | 幂等迁移 v3：先校验备份 → 事务内建表+回填+验收 → 验收失败回滚；`--check` 只读；`--rollback` 须带 `--backup`，凭备份恢复 |
| `test_source_lineage.py` | 86 个测试，生产快照本地副本上实测 |
| `DESIGN.md` | 设计文档（5 项缺口逐项对照、现网 schema 核实、部署与回滚） |
| `README.md` | 本文件 |

## 关键规则（v3）

- 稳定身份是配置变体 `(protocol, host, port, config_fingerprint)`；
  指纹 = 去凭据后的 canonical 配置 SHA-256，抓取时算出，凭据永不入库。
  历史三元组回填为 `fingerprint='legacy'`（verified=0，无观测时间），
  绝不臆造成任何变体的证明。
- 主来源仅作展示；多样化只认“合格来源组”（健康独立源、状态 active、
  已确认分组、证据有效且新鲜）。同一变体仅计一次。
- 多样化先拒绝重复变体与未知/未验证/暂停/legacy/过期候选，再按已确认
  独立来源组计数；未知来源不进分母。补录来源不清除失败史。
- 观测须带真实抓取证据；精确重放与重复 event_id 是 no-op；时间单调，
  乱序证据不能把 last_seen 往回拨。
- 迁移：verify 在 commit 之前；`--check` 只读；备份唯一命名且先校验；
  回滚凭备份恢复，毁已验证数据时拒绝（除非 `--allow-data-loss`）。

## 测试

```sh
python3 test_source_lineage.py   # 86/86 PASS（生产快照本地副本；合成节点用 TEST-NET 地址）
```

重跑测试需自行放一份 `pool-snapshot.db` 在测试文件旁（快照是本地测试
夹具，不随 PR 提交）。

## 部署（评审通过后）

停抓取器、停测试器的窗口跑迁移（约 1 分钟，只加新表），再部署抓取器
的 `record_sighting` 调用；回滚用 `--rollback --backup <备份文件>`。
多样化（≥3 独立来源组、任一 ≤1/3）与新鲜性（≤300ms）门槛不变。
