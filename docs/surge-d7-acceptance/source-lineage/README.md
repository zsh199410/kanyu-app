# Source lineage v4 — 节点稳定身份 + 全来源血缘

**离线参考与迁移工具；不改生产，不部署。**
本模块依据 GPT Review 6032131494 收口 v3 的 3 项契约缺陷（见 DESIGN.md）。
评审结论是静态源码审查，不是运行测试结果；本模块的测试证据见下。

## 文件

| 文件 | 说明 |
|---|---|
| `source_lineage.py` | 血缘模块 v4：`config_fingerprint`（HMAC-SHA256，密钥必填，认证变体区分）/ `SourceRegistry` / `record_sighting`（事件级去重、时间单调、证据必填、last_evidence 跟最新观测）/ `primary_source`（仅展示）/ `qualified_source_group`（年龄 0<=age<=TTL，未来时间拒绝）/ `batch_diversity`（passes 必须零拒绝 + `rebuild_batch`）/ `set_source_status` 等 |
| `migrate_node_sources.py` | 幂等迁移 v4：先校验备份 → 事务内建表+回填+验收 → 验收失败回滚；`--check` 只读且有问题时退出 1；已迁移分支按实际结论返回；`--rollback` 须带 `--backup`，默认保留模式（无损），零写入窗口才可整库恢复；`--allow-data-loss` 已删除 |
| `test_source_lineage.py` | 129 个测试，生产快照本地副本上实测（两遍 129/129） |
| `DESIGN.md` | 设计文档（3 项契约逐项对照、现网 schema 核实、部署与回滚） |
| `README.md` | 本文件 |

## 关键规则（v4）

- 稳定身份是配置变体 `(protocol, host, port, config_fingerprint)`；
  指纹 = 本地稳定密钥的 HMAC-SHA256（规范化完整有效配置），密钥必填、
  无无密钥回退；只差认证的配置指纹不同；凭据仅在解析进程内，
  永不入库、永不进 PR。历史三元组回填为 `fingerprint='legacy'`
  （verified=0，无观测时间），绝不臆造成任何变体的证明；旧指纹不自动晋级。
- 主来源仅作展示；多样化只认“合格来源组”（健康独立源、状态 active、
  已确认分组、证据有效且新鲜，年龄 0<=age<=TTL）。同一变体仅计一次。
  active+24h 只是来源预筛，不证明最新抓取仍有该节点或 VPS/手机通过；
  接入时须绑定最新有效抓取批次与真实健康状态。
- 多样化先拒绝重复变体与未知/未验证/暂停/legacy/过期/未来时间候选，
  再按已确认独立来源组计数；未知来源不进分母。**passes 必须零拒绝**；
  发布必须用 `rebuild_batch()` 建新批次重跑，禁止发布原列表。
  补录来源不清除失败史。
- 观测须带真实抓取证据；精确重放与重复 event_id 是 no-op；时间单调，
  乱序证据不能把 last_seen 往回拨，`last_evidence` 只跟最新观测走。
- 迁移：verify 在 commit 之前；`--check` 只读且有问题时退出 1；
  备份唯一命名且先校验；回滚默认保留模式（停用模块调用、保留血缘表
  与历史），零写入窗口才可整库恢复；**没有丢数据开关**。

## 测试

```sh
python3 test_source_lineage.py   # 129/129 PASS（生产快照本地副本；合成节点用 TEST-NET 地址；两遍）
```

重跑测试需自行放一份 `pool-snapshot.db` 在测试文件旁（快照是本地测试
夹具，不随 PR 提交）。HMAC 测试密钥为合成测试密钥，绝不是生产密钥。

## 部署（评审通过后）

停抓取器、停测试器的窗口跑迁移（约 1 分钟，只加新表），再部署抓取器
的 `record_sighting` 调用（抓取器须在解析订阅时算 HMAC 指纹并传
evidence 与 event_id；HMAC 密钥由抓取器安全配置传入）。
回滚默认保留模式；多样化（≥3 独立来源组、任一 ≤1/3）与新鲜性（≤300ms）门槛不变。
