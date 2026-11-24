# Module 1：试用池小容量兼容 — 适配器集成设计

## 现状

PR #125 已有参考组件（`small_trial.js`）：`planTrialBatch` + `smallTrialDiagnostic`，
14 个确定性合成测试在作者运行时通过。本轮在真实 Node v24.22.1 下复测：**14/14 通过**。

PR #125 的 README 明确：这只是离线参考组件，不是 live 探针/接收器的直接补丁。
实际试用适配器集成尚未完成（需要真实的试用源、manifest/replay 校验、双目标对照与设备端到端测试）。

## 本轮新增

### trial_adapter.js（参考实现，纯函数，无 I/O）

`adaptTrialBatch(snapshot, cursor)`：把 PR #125 的小池参考组件接到真实试用接收器的契约上。

**输入**（已验证快照，调用方须先完成接收器侧验证）：
- `manifestSha`：64 位十六进制，当前试用 manifest 的 SHA。
- `generation`：非负整数，manifest 代次。
- `nodes`：最多 6 个，`{id (64-hex 身份), name}`，id 互不相同。
- `observations`：`[{id, rawStatus}]`，每个 id 必须在 manifest 内，rawStatus 只能是 success/failure/unknown。

**调用方责任（接收器侧，在调用本模块前完成，模块内不重复做）**：
- 验证 bearer 已鉴权、nonce 新鲜未重放、manifest SHA/代次与当前源字节一致、
  节点身份精确匹配、external policy-ID 映射正确。
- 绝不以调用方提供的布尔值代替上述验证。

**输出**：
- `{valid:true, manifestSha, generation, mode, ids, nextCursor, diagnostics}`。
- `mode`：0 条 `empty_no_batch`；1–2 条 `small_diagnostic_only`；3–6 条 `existing_receiver_rules`。
- `diagnostics`：每条 `{id, raw_status, diagnostic_status, reason, promotion_allowed:false, prune_allowed:false}`。
- 小池结果一律 diagnostic-only：即使 observed_reachable 也不允许转正或删除。

**失败时抛错**：`invalid_trial_snapshot`（manifest/节点非法）或 `invalid_observation`（观测非法）。

### 测试（test_trial_adapter.js，12/12 通过）

- 1 条节点 diagnostic-only，success 记 observed_reachable，promotion/prune 均为 false。
- 2 条节点，缺失观测记 unknown。
- 3 条节点走 existing_receiver_rules。
- 0 条节点无批次。
- 拒绝未知身份的观测、坏 manifest SHA、负代次、重复节点 id、7 个节点、非法 rawStatus。
- 游标在小池内轮转。
- success 在小池里也绝不允许转正。

## 与生产的关系

- **不改生产**：本模块是纯函数参考实现，不改 live 试用探针脚本、不改接收器、不改订阅、不改发布器、不改开关。
- **部署路径**：先由 GPT 评审本模块与测试；再在隔离环境用真实试用源做适配器集成验证
  （manifest/replay 校验、双目标对照、设备端到端）；通过后才可按发布门禁部署到试用探针。
- **回滚**：本模块未部署，无需回滚。若将来部署后发现问题，恢复旧版探针脚本即可（探针是无状态脚本，接收器侧无 schema 变更）。
- **限制**：小池观测本身不能作为转正或删除依据；正式入池仍须手机 5G 真实成功与 manifest/SHA/identity 校验。
