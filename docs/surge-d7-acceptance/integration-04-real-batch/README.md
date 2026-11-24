# 集成-04「真实组批」差异包

建议分支：`integration-04-real-batch`
建议目录：`docs/surge-d7-acceptance/integration-04-real-batch/`
状态：Draft（待 GPT 评审）。生产未动。

## 审查依据

- GPT-6 Review 6034205305（PR #127 v2，2026-11-24 13:33）：要点 1（统一规范化口径）、
  要点 2（最新成功完整抓取批次）、要点 3（真实事务证据）。
- GPT-6 Review 6034204978（PR #126 v2，2026-11-24 13:33）：要点 1（PHONE_EVIDENCE_READY
  标签）、要点 3（导入器按 trial_generation 真实筛选）。
- GPT-6 评论 7123361053（#73，2026-11-24 13:52，「集成-04/05 执行重点确认」）：
  实际候选计算（只读入口，逐条排除原因 + 当前可组批数，零批报零）与分组轮询子批次
  隔离测试。三个 v2 HEAD 未变化；已冻结模块不再重复审查。

## 本轮做的五项（原任务）+ 两项（7123361053 追加）

1. **统一规范化口径**（#127 要点 1）：新增 `pool/normalize.py`——枚举字段
   （vmess net、trojan t_type、ss method）strip + 小写；已知 token 等价；未知但格式良好
   的 token 保持小写原样判 unknown；非字符串/纯空白/含内部空白或控制字符判 invalid；
   传输缺失默认 tcp；ss method 缺失判 invalid（无默认方法）。认证字段（password、uuid）
   永不归一化，只做原值检查；凭据值永不进原因 detail。gate / pre_filter / tester /
   build 四处共用同一契约；security 不归一化（D2 冻结，gate 唯一执行方且大小写敏感）。
   SNI 由 #128 N3 严格校验，不在此模块归一化。
2. **最新成功完整抓取批次**（#127 要点 2）：新增 `pool/batch_state.py`（BatchCollector、
   commit_batch、qualified_batch_members、prune_batches）+ `pool/migrate_batch_state.py`
   （迁移脚本，照 v4 范式：--check 只读、--dry-run、备份先行且校验、无整库恢复、
   无 --allow-data-loss）。每源只认最新一次完整抓取的成员集合：失败/部分解析/hook
   异常/disabled/缺 key（no_module）/schema 未迁移都不能凭 24h 旧 sighting 获资格；
   消失的变体直接不在新成员集里；消费只读最新完整批次且重查 24h 窗与当前来源状态。
   暂停两来源（chenzhihan-base64、matin-ss）仅筛查层：抓取与血缘照常记录，消费侧
   BLOCKED；独立性保守分组不变。
3. **真实事务证据**（#127 要点 3）：`LineageRecorder` 新增 defer 模式（collect +
   flush）；`cmd_crawl` 重构为内存收集 + 显式事务：网络 I/O 期间零 DB 写、不持写锁；
   抓取完成后一次 BEGIN IMMEDIATE 提交 nodes upsert + sources 更新 + lineage flush +
   batch commit + run 行；事务内任何错误全部回滚，再以独立短事务写一条 ok=False 的
   失败 run 行；成功后独立短事务 prune_batches。SAVEPOINT 逐行写路径仅保留给 #127 v2
   套件与直接诊断，生产 cmd_crawl 不再使用。
4. **PHONE_EVIDENCE_READY 标签**（#126 要点 1）：`verify_promotion.py` 的裸 verdict
   READY 改为 PHONE_EVIDENCE_READY；输出新增 GLOBAL_READY: NOT_EVALUATED 行，逐项列
   七个全局门（真实身份、原生<300、当前 VPS≤300、来源多样性、TTL、禁入、发布授权）
   及状态（仅 TTL 由本脚本查，其余 NOT_CHECKED_BY_THIS_SCRIPT）；输出中不再出现裸
   READY verdict token，旧解析器无法误读。
5. **导入器按 trial_generation 真实筛选**（#126 要点 3）：新增 `phone_evidence.py`
   （classify_row / classify_failure_detail，两导入器与 auto_prune 共用同一分类器）。
   整数代次 = 试用证据，永不导入（skipped trial_generation_bound）；null 代次 =
   正式历史证据，单列兼容，继续走 G10 门，导入后 detail 显式标记
   evidence_class=formal_historical。消费侧 `auto_prune._is_trusted_phone_failure`
   同样排除 trial_bound 行（只减不增：无代次标记的旧行仍走原 G10 检查，A18b 不变）；
   分类器缺失时（只拷 auto_prune.py 的旧布局）回退到 #04 前 G10 行为，不崩溃。
   回退到旧导入器也无法复活试用行（旧导入器从不写试用行）。
6. **实际候选计算**（7123361053 追加 1）：新增 `pool/candidates.py`，只读入口
   （`python3 -m pool.candidates --db ... --registry ... [--rejected ...]
   [--admission ...]`，DB 以 mode=ro 打开，字节级只读已测）。输入：最新完整批次 +
   配置身份（HMAC 指纹）+ 统一准入结果 + 持久禁入清单（DB blocklist 表，可并
   rejected_nodes.json 严格加载）。输出：每条候选的准入/排除判定与固定原因口径、
   按独立来源组的多样化统计、当前可组批数（≥3 独立组、每组 ≤1/3，贪心三元组打包；
   可组批数为 0 时如实报 0，不凑数）。准入无输入时回退到血缘证明（node_sources
   行证明该成员在抓取时通过 gate）；既无输入又无血缘证明则 admission_unknown 排除。
7. **分组轮询子批次**（7123361053 追加 2）：`candidates.partition_sub_batches()`
   按组轮询交错、切分子批次，每轮为独立控制（C4）预留 control_slots（默认 run_cap 6
   留 1）。子批次只用于轮询验证：publish_eligible=False；完整候选集的多样性与可组批数
   始终按完整集合算，不按子批重算；子批结果不进发布判定（试用失败行在消费侧已排除，
   见第 5 项）；G6=0 时仍只能诊断，真实 READY 保持 BLOCKED（verify_promotion 的 C4
   门未变：链内须有 control_verified 成功）。

## 明确不做（仍阻塞，见报告）

- #126 要点 2：C4 完整配置变体与实际 native policy-ID 绑定（须 B1/G6 解锁）。
- #128 Review 6034205620 的三项：sqlite_backup 全表摘要校验、DB 内同事务决策记录 /
  outbox、同一 banlist 版本从预检到最终发布锁内复核（集成-05 发布安全门）。
- B5 真实密钥安全配置与 unit 改动（须授权）。
- 任何生产部署、live 库写入、探针改动、节点删除、回填、解禁。

## 文件清单

新增（`new-modules-i04.patch`，/dev/null diff）：
- `pool/normalize.py`——统一规范化契约。
- `pool/batch_state.py`——批次状态机 + 提交/消费/清理。
- `pool/migrate_batch_state.py`——批次表迁移脚本。
- `pool/candidates.py`——只读候选计算 + 分组轮询子批次 + CLI 入口。
- `phone_evidence.py`——证据分类（导入器与 auto_prune 共用）。
- `tests/test_integration_04.py`——新套件（160 项，见报告）。
- `tests/test-i04-regressions.py`——v1/v2 回归跑器（基线 + 合并布局）。

修改（各 .patch 文件，基底见括号内）：
- `pool/cli.py`（#127 v2）——`cli-i04-batch.patch`：cmd_crawl 显式事务 + BatchCollector 接线。
- `pool/crawler.py`（#127 v2）——`crawler-i04-batch.patch`：逐源 unparsed / observation_errors 计数。
- `pool/rules.py`（#127 v2）——`rules-i04-normalize.patch`：N3 严格版 + 归一化（B10-EXTENSION 与 N3 合并）。
- `pool/tester.py`（#128 v2）——`tester-i04-normalize.patch`：归一化 + 密码 "," 原因词统一 + uuid 检查。
- `pool/lineage_adapter.py`（#127 v2）——`lineage-adapter-i04-defer.patch`：归一化 gate/canonical + defer/collect/flush。
- `verify_promotion.py`（#126 v2）——`verify-promotion-i04-label.patch`：PHONE_EVIDENCE_READY + GLOBAL_READY 节。
- `import_phone_observations.py`、`import_per_observation_v2.py`（#126 v2）——`importers-i04-generation.patch`：代次分类 + 证据类标记。
- `auto_prune.py`（#126 v2）——`auto-prune-i04-trial.patch`：消费侧排除 trial_bound 行。

未改动基线文件（随包提供，供回归与审查对照，不在 patch 内）：
`pool/migrate_node_sources.py`（#125 v4 冻结）、`pool/screening.py`、`pool/backfill_blocklist.py`、
`pool/unblock_node.py`、`pool/rejected_nodes.json`、`pool/blocklist_backfill_20261121.json`（#128 v2）、
`pool/__init__.py`、`pool/db.py`、`pool/geo.py`、`pool/publish.py`、`receiver.py`、`formal_manifest.py`、
`formal-manifest.json.sample`、`formal_source_groups.json`、`source_groups.json`、
`probation-manifest.json`、`formal_manifest.service`、`formal_manifest.timer`。
补丁验证：基底文件 + 全部 .patch 应用后，16 个文件与本包逐字节一致
（`git apply --check` 全过，`cmp` 全一致）。

## 测试

- 新套件：`python3 tests/test_integration_04.py`（VPS 隔离 157/157；本沙盒 160/160，
  含 C8 三项）。
  分节：N 归一化组合回归（大小写/空白/非法值 + N3 叠加）、B 批次状态机、
  T 显式事务（成功/事务内失败零证据/缺 key）、P 标签（无裸 READY token）、
  I 导入器与回退消费侧、 C 候选计算与子批次（零批报零、CLI 只读）。
- 回归：`python3 tests/test-i04-regressions.py`（VPS 隔离，基线 + 合并布局；
  详见报告）。两处已取代断言仅改 scratch 副本，原套件文件不动：
  #126 A18a 的 "-> READY" 改为 "-> PHONE_EVIDENCE_READY"；
  #128 K7 前半改为断言合并后 rules.py 同时含 N3 与 comma-uuid。
- 测试全部在 VPS /root 隔离目录跑，live 库 0 写入；测试前后 live 状态复核一致
  （正式池 22 行 SHA 9e44841b…、blocklist 11 行、nodes 7800）。

## 未解决阻塞（摘要，详见报告）

- B1、G6 仍 BLOCKED：C4 完整配置变体与实际 native policy-ID 绑定未做；G6 合格控制
  清单初始为空；正式控制生成器历史成功不绑定当前 formal pool_sha。
- #128 三项发布安全门属集成-05，未在本轮做。
- B5 真实密钥安全配置与 unit 改动未授权。
- 试用池 TTL 2026-11-28；补位储备未通过转正；正式池保持 22 条，自动删除关闭。
