# D2 报告：修复 GPT 对 D1（PR #77）的 3 项代码级阻断

- 任务：GPT D1 代码复核（Issue #73 评论 6881291219，2026-11-15 01:15）
- 范围：**隔离 only**。生产未动（未改生产目录、生产订阅、生产定时器、
  手机配置）；无 GitHub 操作（无分支、无 PR、无评论）。
- 位置：VPS `/opt/p2p3-d2/` 与本地 `~/workspace/p2p3-d2/`（代码树已逐
  文件 SHA 核对一致，日志文件除外——两边日志是各自运行的记录）。
- D1 基础：Draft PR #77，分支 `issue73-surge-d1-review`，head `2d97ec1`。

## 0. 结论先行

3 项阻断全部修复并有红→绿测试覆盖；D1 24 项测试全绿；新增 D2 39 项
测试全绿；定时模拟、恢复演练、崩溃演练在本地与 VPS 双环境全过。
仍未证明的（诚实边界，见 §7）：真实手机新一轮复测、DIRECT 正式组
证据、生产切换——D2 没有改变这些前置条件，也不声称已满足。

## 1. 阻断 1：版本/证据绑定不足 → 版本链（version-chain-v1）

### GPT 指出的缺口

- `run_publish(candidate_lines, source_version_sha)` 把调用方传入的
  SHA 直接用于门禁与 sidecar，未证明该 SHA 对应本次候选源文件的
  实际字节。
- `run_sync` 直接信任命令行 `--source-version`，未核对源文件 sidecar
  中的版本与内容哈希。
- 攻击/误配置场景：旧版合格证据被误贴到新版候选，或被旧逻辑写手
  覆盖的文件，恰有相同指纹的行仍可被放行。

### 改了什么

新增 `pool/version_chain.py`，D1 的 sidecar 升级为 v2：

```
version_chain = {
  "format": "version-chain-v1",
  "source_sha":             # 完整原生测过的源订阅文件字节的 SHA256
  "published_sha":          # 发布子集字节的 SHA256
  "admitted_fingerprints":  # 该版本下 native record 承认的指纹集（已排序）
  "published_fingerprints": # 发布行实际含有的指纹集（admitted 的子集）
  "chain_id":               # sha256(其余四字段的规范 JSON)
}
```

校验（`verify_version_chain`）每次从**实际字节 + native record**
重新验算，绝不信任 sidecar 自述：

1. `chain_id` 重算（sidecar 篡改即现形）；
2. `published_sha == sha256(实际发布行字节)`；
3. `published_fingerprints == 实际发布行的指纹`；
4. `admitted_fingerprints == native record 对该版本的证据集`
   （`evidence_admitted_fps`，见下）；
5. 发布指纹集是承认集的子集。

调用点改动：

- `pool/publish.py`：`run_publish` **强制要求 `source_file`**。
  锁内对实际字节验 `sha256(源文件) == source_version_sha`
  （不符 → `source_version_sha_mismatch`）；候选行须是源文件的
  字节级子集（否则 `candidate_not_in_source`）；重复候选行拒绝；
  无 `source_file` 拒绝 `source_file_required`——不存在无绑定的
  发布路径。发布写 v2 sidecar（含完整链）；stdout 只给链摘要
  （SHA 前缀 + 计数），完整链只在 600 sidecar 里。
- `pool/sync.py`：`--source-version` 改为**可选项**；sidecar 必须带
  v2 链（v1-only → `sync_sidecar_no_version_chain`，缺失 →
  `sync_sidecar_missing`）；链校验失败按具体原因拒绝
  （`sync_chain_chain_id_mismatch` /
  `sync_chain_chain_published_sha_mismatch` /
  `sync_chain_chain_admitted_set_mismatch` 等）；给出
  `--source-version` 时须与 sidecar 的 `source_sha` 一致。
- `pool/rollback.py`：锚点链先验（`rollback_chain_*`），v1-only
  sidecar 拒绝（`anchor_sidecar_v1_no_chain`）；恢复写回时携带锚点
  的链。
- `pool/publish_lock.py`：`write_version_meta` /
  `_atomic_write_inner` / `snapshot_current` 直通 `version_chain`；
  新增 `copy_sidecar`：publish → served 复制文件时**同时复制
  sidecar**，否则 served 目录里的文件无法验链。

### 一个关键设计抉择：链校验不问新鲜度

链校验用的承认集是 `evidence_admitted_fps`
（`pool/native_gate.py` 新增）：同版本最新结果通过、且无后续失
败——**忽略 TTL 与时间戳合法性**。链只证明「文件与证据版本绑定」，
新鲜度由门禁在使用时另行判定。

为什么必须这样：否则 TTL 过期的锚点永远验不过链，恢复路径就断了
（锚点无法被归类为 last-verified-safe）。测试
`test_chain_verification_ignores_ttl` 把这条钉死：过期 25 小时后
链仍验过，但门禁承认 0 条（`native_stale` 14 条）。

### 测试（阻断 1）

| 测试 | 红→绿 |
|---|---|
| `test_chain_roundtrip_verifies`：链构建→校验全过，14/14 | 绿 |
| `test_chain_mutation_breaks_chain_id`：改 source_sha / published_sha / chain_id 任一 → `chain_id_mismatch` | 绿 |
| `test_chain_recomputed_id_cannot_fake_admitted_set`：篡改承认集**并重算 chain_id**（“聪明”篡改）→ `chain_admitted_set_mismatch` | 绿 |
| `test_chain_published_lines_mismatch`：链对另一组行 → `chain_published_sha_mismatch` | 绿 |
| `test_chain_build_rejects_unadmitted_line`：发布含未承认行 → ValueError | 绿 |
| `test_chain_verification_ignores_ttl`：过期后链仍验过、门禁仍拒绝 | 绿 |
| `test_publish_sha_mismatch_refuses`：源文件改一字节、报旧 SHA → `source_version_sha_mismatch`，旧文件不动 | 绿 |
| `test_old_evidence_on_new_version_refuses`：GPT 攻击场景——(a) 新文件报旧 SHA → mismatch；(b) 报新 SHA → 门禁 0 承认（`native_version_mismatch` 44） | 绿 |
| `test_publish_candidate_not_in_source_refuses`：候选含源文件外行 → 拒绝 | 绿 |
| `test_publish_duplicate_candidates_refuses`：重复候选行 → 拒绝 | 绿 |
| `test_publish_without_source_file_refuses`：无 source_file → `source_file_required`，不写文件 | 绿 |
| `test_publish_writes_verifiable_chain`：发布后 sidecar 链可验，摘要前缀与实际 SHA 一致 | 绿 |
| `test_publish_subset_chain`：13 行子集发布，链验过，published_count 13 | 绿 |
| `test_sync_sidecar_tampered_refuses`：改 published_sha → `chain_id_mismatch` | 绿 |
| `test_sync_sidecar_smart_tamper_refuses`：重算 chain_id 的篡改 → `chain_admitted_set_mismatch` | 绿 |
| `test_sync_source_replaced_refuses`：源文件被换成 44 行 legacy → `chain_published_sha_mismatch`，served 不动 | 绿 |
| `test_sync_sidecar_swapped_refuses`：v1 快照 sidecar 换到 v2 文件上 → 链错，served 不动 | 绿 |
| `test_sync_v1_only_sidecar_refuses`：删 version_chain → `sync_sidecar_no_version_chain` | 绿 |
| `test_sync_missing_sidecar_refuses`：删 sidecar → `sync_sidecar_missing` | 绿 |
| `test_sync_caller_version_mismatch_refuses`：调用方版本与 sidecar 不符 → 拒绝 | 绿 |
| `test_sync_without_caller_version_ok`：不给版本也能同步（绑定全来自 sidecar + 实际字节） | 绿 |

## 2. 阻断 2：sync 锁外取 manifest 的竞争窗口 → 全部锁内化

### GPT 指出的缺口

`run_sync` 在取 flock **之前**算 `source_manifest`，锁内才读/复制
源文件，最后用锁外 SHA 校验新服务文件。等待锁期间合法 publish
更新了源文件，sync 会在成功复制新文件后报 `sync_verify_failed`
（文件其实已被更换），错误状态与实际写入不一致。

### 改了什么（`pool/sync.py`）

- manifest、sidecar 读取、链校验、门禁、复制、校验**全部移到持锁
  之后**（`publish.py` 的 `old_manifest` 也一并移入锁内，同类问题）。
- 复制前后用**锁内计算**的 SHA 验证：
  `source_sha_before == served_sha == source_sha_after`。
- 成功/失败一律反映实际已服务版本：结果含 `served_version_sha`
  与锁内 `source_manifest`，两者须一致。
- 复制后校验一旦失败：返回**实际** served manifest、rc=1，并自动
  进入 degraded 状态（STOP 标记，见 §3），绝不谎报成功。
  （实现细节：sync 持锁时调恢复状态写操作用锁内变体
  `_enter_degraded_inner`，公开的 `enter_degraded` 会自己取锁——
  持锁时调它会自锁死锁，已避开。）

### 测试（阻断 2）

| 测试 | 红→绿 |
|---|---|
| `test_sync_queues_behind_publish_lock`：锁被占时 sync 1s 超时失败；释放后同步成功，锁内 source manifest == served manifest | 绿 |
| `test_concurrent_publish_sync_no_false_verify_failure`：锁被占 3 秒期间同时发起 publish(v2)+sync；无论谁先拿到锁，sync 永不报 `sync_verify_failed`，served 是两个合法版本之一，后续一次 sync 收敛到 v2 | 绿 |
| `test_sync_reports_actually_served_version`：两次 sync 的 `served_version_sha` 分别等于 v1 / v2 的实际磁盘 SHA | 绿 |

## 3. 阻断 3：回滚与故障恢复策略冲突 → 显式恢复状态机

### GPT 指出的缺口

`run_rollback` 依赖旧版本原生结果仍在 24h TTL 内且全部通过；真实
紧急故障通常发生在 TTL 已过或新一轮失败后，届时可能完全无法恢复。
不能为通过测试放松 DIRECT 安全门禁，但应明确独立的「恢复到最后
已验证安全版本」策略、失败时停止发布/隔离不合格流量、受控人工
恢复路径；补演练与处置手册。不要将「保留旧服务文件」称为长期合格。

### 改了什么

新增 `pool/recovery.py`（状态机 + CLI `python3 -m pool.recovery`）：

```
ok --enter-degraded--> degraded --manual-restore--> manual-restored
   <--clear-stop (+fresh evidence + owner ack)--
degraded --clear-stop (+fresh evidence + owner ack)--> ok
```

- 状态文件 `recovery-state.json`（600）；所有状态写操作在共享锁内；
  STOP 标记置位时 publish/sync 拒绝 `pool_stopped`。
- `assess_anchors()`：每个锚点分类——`verified_safe`（证据新鲜且
  全过）/ `last_verified_safe`（证据曾全过、现已过期、无后续失败）
  / `unrecoverable`（无 sidecar / 链不验 / 无证据 / 证据说失败）。
  回滚被拒时结果附带评估与推荐动作（`manual-recovery` 或
  `rebuild-from-fresh-native-test`）。
- `manual_restore()`：须机主逐字确认
  `OWNER-ACK-RESTORE-LAST-VERIFIED-SAFE`；只恢复
  last_verified_safe（或 verified_safe）锚点；publish/ 与 served/
  双写、锁内前后 SHA 校验；恢复后状态 `manual-restored`，STOP 不
  解除，served 定性 `manual-restored-unverified`——**永不声称当前合格**。
- `clear_stop()` 回 `ok` 的唯一路径：机主确认
  `OWNER-ACK-CLEAR-STOP` **且** fresh 原生复测通过（门禁当场重算，
  不是调用方断言）。
- `status()` 实时算 served 文件定性：`qualified` /
  `stale-not-qualified`（文件完好、证据过期） /
  `broken-unqualified`（文件与证据不符） /
  `manual-restored-unverified`。`enter_degraded` 本身不碰任何文件。
- `pool/rollback.py`：拒绝时结果附带 `recovery` 评估；恢复同步步骤
  加锁内前后 SHA 校验；恢复写回携带锚点链。

处置手册：`docs/recovery-runbook.md`（S1/S2/S3 分步命令 + sync
校验失败处置 + 只读检查 + 绝对禁区）。

### 演练（`drills/recovery_drill.py`，22/22，双环境）

| 场景 | 检查点 |
|---|---|
| S1 TTL 过期 | 回滚拒绝 `rollback_gate_zero_qualified`；恢复计划指名 last-verified-safe（14 行）；degraded 阻塞 publish/sync；人工恢复错确认串拒绝、对确认串恢复干净；恢复后标 unverified；无 fresh 证据清不了 STOP；fresh 证据后清 STOP、发布恢复 |
| S2 证据缺失 | 回滚拒绝 `rollback_chain_chain_native_record_missing`；计划说 rebuild-from-fresh-native-test、last_verified_safe 为空；degraded；人工恢复拒绝（`anchor_not_restorable`） |
| S3 生产已坏、回滚被拒 | served 被 legacy 44 行覆盖 + 回滚被拒；degraded；status 判 `broken-unqualified`；人工恢复后 served 回干净、标 unverified；fresh 证据后清 STOP；末次 sync 收敛 |

## 4. 口径裁决：双门禁反例测试

GPT 裁决：「同版本最新成功 + 任何后续版本原生失败作废旧成功」原则
上接受；「后续他版本成功不作废旧版」只在旧证据仍新鲜、同指纹参数
与目标源 SHA 均匹配时成立。请给反例测试。

### 改了什么（`pool/native_gate.py`）

后续失败判定由严格 `tested_at > 通过时间戳` 改为 **`>=`**（D2
规则）：同时间戳的失败也作废旧通过。理由：秒级时间戳下「同一秒」
没有真实先后，列表顺序是文件排版产物，不能凌驾于失败之上；
fail-closed 要求矛盾证据一律拒绝。新增 `evidence_admitted_fps`
（TTL 无关的证据集，供链校验用；见 §1）。

### 反例测试结果

| 反例 | 结论 |
|---|---|
| 同指纹参数变更（改密码/sni）→ 新指纹 → 无证据 → 拒绝；候选行不在源文件内 → `candidate_not_in_source` | 绿 |
| 只改显示名 → 同指纹 → 放行（名字不是身份）；同名改参数 → 新指纹 → 拒绝 | 绿 |
| 同时间戳、同版本、结果矛盾（先过后败 / 先败后过）→ **两种顺序一律拒绝**；两轮都过 → 放行（对照） | 绿（见注） |
| 同时间戳、跨版本失败 → 作废旧通过（`subsequent_native_failed` 1 条）；同时间戳、跨版本通过 → 不作废（14 条全留） | 绿 |
| 新版本通过不作废旧版的条件三钉：(a) 旧证据新鲜 + 新版本通过 → 旧版 14 条全留；(b) 源文件已是新版字节、仍报旧 SHA → `source_version_sha_mismatch`；(c) 旧证据过期 + 新版本通过 → 旧版 0 条（`native_stale` 14） | 绿 |
| 时间戳边界：`tested_at == now` 放行；`now+1` 拒绝（`native_ts_invalid`） | 绿 |
| 证据集忽略 TTL：过期后证据集仍是 14 条（链用），门禁承认 0 条（发布用） | 绿 |

注：同时间戳「先败后过」最初按 D1 列表顺序语义期望放行，测试
失败后复核认定 fail-closed 更正确（矛盾证据不应由文件排版顺序
裁决），已修正测试期望并记录在此。代码行为未为测试让步。

## 5. 测试总表（双环境）

| 套件 | 本地 Python 3.12.3 | VPS Python 3.13.5 |
|---|---|---|
| `tests/test_d1.py`（D1 24 项，带入） | 24/24 | 24/24 |
| `tests/test_d2.py`（D2 39 项，新增） | 39/39 | 39/39 |
| **合计** | **63/63** | **63/63** |

D1 套件带入说明（断言未变，调用点适配）：
- `run_publish` 现强制要求 `source_file`：全部 12 处调用点传入
  源文件（44 行固件文件；v2 子集发布传入子集文件）。
- 一处断言随 D2 语义更新：`test_sync_refuses_ungated_source` 中
  legacy 覆盖源文件后，D2 的链校验先于门禁触发（先证来源再看内
  容），错误码由 `sync_gate_source_not_fully_admitted` 变为
  `sync_chain_chain_published_sha_mismatch`；拒绝 + served 不变的
  不变量未变。
- `sim_timers.py` 同步更新：publish 调用传 `--source-file`；
  legacy 检查期望链错误；每轮增加 sidecar 链重验检查。

| 演练 | 本地 | VPS |
|---|---|---|
| `drills/sim_timers.py`（3 轮并发 :07/:15） | 15/15 | 15/15 |
| `drills/recovery_drill.py`（S1/S2/S3） | 22/22 | 22/22 |
| `drills/crash_drill.py`（SIGKILL） | 重拿锁 0.0 秒，文件 SHA 不变 | 重拿锁 0.0 秒，文件 SHA 不变 |

日志：`docs/sim-log.json`（本地）/ `sim-log-vps.json`（VPS）；
`docs/recovery-drill-log.json` / `recovery-drill-log-vps.json`；
`docs/crash-drill-log.json` / `crash-drill-log-vps.json`。
VPS 指纹已核对：`SHA256:Ta2p4Vxhx4aPXOy0e9cC0oKUBhk6qK6JIaoOzQ+bNGM`
（与 TOOLS.md 台账一致）；部署包 SHA 两端一致
（`c76d2ed217b4bba60d8037a5362b1b38bb2f94ea4e76eed7e27e707284e8c001`）。

## 6. 未完成 / 仍需 GPT 与机主的前置（D2 未改变）

- systemd `:07`/`:15` timer/service 切换方案及回退：未在本任务内
  写（属生产切换步骤，须 GPT 批准 + 机主授权后另行交付）。
- 21 pinned 无豁免的生产接线、私有可恢复备份：同上，未动。
- 真实手机新一轮整组测速：未跑（等机主定时间；13:24 已 stale）。
- 隔离 DIRECT 测试：方案在 `docs/direct-test-plan.md`（D1 未变），未跑。
- PR #77 仍 Draft，未合；本次无任何 GitHub 操作。

## 7. 诚实边界（什么仍未证明）

- **固件是合成的**：TEST-NET 主机（192.0.2.x / 198.51.100.x）、
  密码字面量 `TEST-ONLY-NOT-A-REAL-NODE`，只镜像 13:24 原生测试的
  判定结构（名字、原生/P0 毫秒数、通过/超线/失败）。固件
  `tested_at` 取生成时刻，只为让演练可跑——**它不是真实手机证据，
  不重置真实 13:24 的 TTL**。全部 63 项测试与 3 项演练证明的是代码
  路径，不是手机实测。
- 版本链防误配置、不防有写权限的恶意写手（见 §1 威胁模型）；锁只
  约束认锁的写手；sync 门禁是兜底，不是替代——生产切换时必须把
  :07/:15 定时器改成调 D2 路径，否则旧逻辑照样绕过。
- 恢复状态机假设状态文件本身不被删：`recovery-state.json` 被删会
  回到默认 `ok`（fail-open 的唯一口）。缓解：状态文件 600 权限、
  演练与手册均写明禁删；生产部署时应另加状态文件完整性告警（未做，
  属部署前置）。
- 同时间戳跨版本证据的排序仍依赖秒级时间戳：两轮测试落在同一秒
  内时，D2 按 fail-closed 一律以失败为准；更精细的定序（单调 run
  序号）需改 native record 格式，未做——如 GPT 要求，可作 D3。
- 脱敏：树内无真实节点凭证、订阅 URL、原始 IP、令牌（grep 已扫：
  仅 TEST-NET 地址与 TEST-ONLY 字面量；`password=` 命中全是代码
  格式串与文档语句；`OWNER-ACK-*` 是明文确认串，不是密钥）。
