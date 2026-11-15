# D3 故障恢复处置手册（Recovery Runbook）

> 适用：D3 隔离代码（`pool/`），生产未动。本文只讲**隔离环境**的处置步骤；
> 生产切换步骤（含 systemd 定时器切换、私有备份、手机验收）见 D3 报告
> §8，切换前须 GPT 批准 + 机主授权。
>
> 核心原则：**旧服务文件被保留时，永远不称它合格**。它的状态只能是
> `stale-not-qualified`（证据过期）、`broken-unqualified`（文件与证据
> 不符）或 `manual-restored-unverified`（人工恢复后、待 fresh 复测）。
> 恢复到 `ok` 的唯一路径：一次新的手机原生复测通过 + 机主明确确认。
>
> D3 新增核心原则：**状态不可建立时，一律拒绝，不默认 ok**。状态文件
> 缺失/损坏/不可读/非法、锚点缺失或不一致时，publish / sync /
> rollback 全部拒绝；删状态文件洗不掉 STOP（见 §4）。

## 0. 状态机速查

| 状态 | STOP 标记 | publish/sync | served 文件定性 |
|---|---|---|---|
| `ok` | 否 | 正常（门禁） | `qualified`（门禁当前承认） |
| `degraded` | 是 | 拒绝 `pool_stopped` | `stale-not-qualified` / `broken-unqualified` |
| `manual-restored` | 是 | 拒绝 `pool_stopped` | `manual-restored-unverified` |
| `unknown-unsafe` | 是（视为） | 拒绝（见错误码） | 未知——不作任何定性 |

查看状态：

```bash
cd /opt/p2p3-d3   # 隔离目录；生产路径不同，勿混
python3 -m pool.recovery status --workdir <workdir> --native-record <record>
```

`status` 在状态不可建立时报 `state=unknown-unsafe`、`stopped=True`，
并带 `state_error`（精确错误码，见 D3 报告 §2.6）。这不是一个可以
继续服务的状态——它是「不知道」，必须按 §4 处理。

## 0. 显式初始化（D3 新增）

**什么时候需要 init**：全新部署（workdir 里既无 `recovery-state.json`
也无 `recovery-anchor.json`），或状态文件丢失后按锚点重建（见 §4）。

**init 程序**：

```bash
cd /opt/p2p3-d3
python3 -m pool.recovery init --workdir <workdir> \
    --owner-ack OWNER-ACK-INIT-RECOVERY-STATE
```

- 成功输出含 `mode`：`fresh`（两记录皆无）、`rebuild-from-anchor`
  （状态文件丢失/损坏、锚点完好且未 stopped、served 与锚点绑定一致）、
  `rebuild-anchor`（锚点丢失/损坏、状态文件完好且未 stopped、served
  与状态绑定一致）。
- init 写状态 + 锚点（600 权限、原子写），绑定当前 served 版本
  （SHA + chain_id + 时间戳）并记审计（history）条目。
- init 之后才能 publish/sync/rollback；未 init 前三路一律拒绝
  `recovery_state_uninitialized`。

**权限边界（谁可 init / 谁可手动恢复）**：

| 操作 | 谁可做 | 确认串 | 定时器可否调用 |
|---|---|---|---|
| `init`（建立 ok / 重建） | 机主或机主授权的操作者（人工） | `OWNER-ACK-INIT-RECOVERY-STATE` | **否**——定时器永不调用 init |
| `init --allow-fresh-after-records-loss`（双记录丢失的人工重建） | 机主（人工恢复审核后） | 同上 + 该标志 | **否**——绝不写进 timer/service 默认参数 |
| `enter-degraded`（停发） | 运维/定时器（自动停发路径） | 无（reason 文本即可） | 是 |
| `manual-restore`（恢复锚点） | 机主（人工） | `OWNER-ACK-RESTORE-LAST-VERIFIED-SAFE` | 否 |
| `clear-stop`（回 ok） | 机主（人工，须 fresh 证据） | `OWNER-ACK-CLEAR-STOP` | 否 |

**为什么定时器不能 init**：init 是「宣称这个 workdir 从此刻起可以
服务」的显式人工决定；定时器自动 init 等于把「未知」自动洗成
「ok」，正是 D2 fail-open 的翻版。定时器被门禁挡住时只能停发并
告警，等人工处理。

**init 拒绝时不要绕过**：

- `init_refused_stop_recorded`——锚点（或状态文件）记录了 STOP：
  删状态文件也洗不掉。按 §4 走手动恢复路径，不要反复 init。
- `init_refused_existing_install_records_lost`——两记录皆无，但
  workdir 看起来是已有安装（served/、publish/ 或非空
  publish/history/ 存在）：plain init 拒绝。先从外部持久部署
  标记/备份恢复双记录，或经人工恢复审核后用
  `--allow-fresh-after-records-loss` 再跑 init（见下节信任边界）。
- `init_refused_unreadable_state`——状态文件存在但不可读/损坏/
  非法：先按 §4 刻意移除该文件（这是有意的删除动作，须记入操作
  记录），再由锚点重建。
- `init_anchor_served_mismatch` / `init_state_served_mismatch`——
  served 文件与现存绑定不一致：不要强行 init。改走 fresh 证据 +
  clear-stop 路径（S1 第 5–6 步），或先把 served 文件恢复到锚点
  记录的版本再 init。

## 0b. 显式初始化的信任边界（D5 新增）

**fresh init 是什么**：一次**受控人工信任建立**。操作者凭确认串
`OWNER-ACK-INIT-RECOVERY-STATE` 宣称「这个 workdir 从此刻起可以
服务」。它建立信任，不验证信任——init 之后 publish 仍须过 fresh
native gate（见下），init 本身不证明 served 文件合格。

**定时器/服务绝不能调用 init**：定时器被门禁挡住时只能停发并
告警，等人工处理。定时器自动 init 等于把「未知」自动洗成「ok」，
正是 D2 fail-open 的翻版。`--allow-fresh-after-records-loss` 同
样只许人工在恢复审核后传，绝不许写进任何 timer/service/脚本的
默认参数。

**`_served_binding()` 只取标识，不验证证据新鲜度**：init 绑定的
只是当前 served 文件的 manifest/sidecar 标识（SHA 前缀 +
chain_id + 时间戳）。它不验证原生证据是否新鲜、不验证该版本
是否曾经通过门禁。init 之后 served_status 仍是
`unknown-no-evidence`，publish 仍须 fresh native gate 通过才能
声称合格。不要把「init 成功」读成「served 文件已验证」。

**已有安装误删双记录**：两记录皆无且 workdir 有已有安装迹象
（served/pool-new.txt、publish/pool-new.txt、非空
publish/history/ 三者任一）时，plain init 拒绝
`init_refused_existing_install_records_lost`。恢复路径只有两条：
(1) 从外部持久部署标记/备份恢复双记录；(2) 人工恢复审核后用
`--allow-fresh-after-records-loss` 重跑 init。走 (2) 时新状态会
记一条 `records-loss-recovery` 审计事件（含当时 served SHA 前
缀），served_status 写 `unknown-no-evidence`、
requires_fresh_native_retest 写 True——门禁重开，但 served 版本
在 fresh 原生复测通过前不得声称合格。

**诚实边界：这不是“无法绕过 STOP”**：有写权限者删双记录 + 跑
init（或加 allow 标志）是**显式操作员行为**，代码防不住——文
件检查只能防单文件丢失/损坏/写中断，防不住有写权限的人刻意
重写两份记录。发现靠审计（history 里的 init /
records-loss-recovery 事件、操作记录），不是靠门禁。不要在手
册或汇报里把双记录删除描述为“无法绕过 STOP”；正确的说法是
「删双记录 + init 是带审计的人工操作，事后可查，事前不自动发
生」。

```bash
# 人工恢复审核后的重建（仅人工，绝不进 timer）
python3 -m pool.recovery init --workdir <workdir> \
    --owner-ack OWNER-ACK-INIT-RECOVERY-STATE \
    --allow-fresh-after-records-loss
# 成功后核对：history 里应有一条 records-loss-recovery 事件，
# served_status=unknown-no-evidence，requires_fresh_native_retest=true
python3 -m pool.recovery status --workdir <workdir> --native-record <record>
# 再走一次手机 fresh 原生复测，通过后才能把 served 版本当作合格
```

## 1. 场景 S1：TTL 过期（证据超过 24 小时）

**现象**：回滚拒绝 `rollback_gate_zero_qualified`，结果里 `recovery.recommended_action == "manual-recovery"`，并给出 `last_verified_safe` 锚点（最后验证通过的时间）。

**处置**（每一步都要看到明确输出再做下一步）：

```bash
# 1) 评估锚点：确认 last_verified_safe 存在
python3 -m pool.recovery assess --workdir <workdir> --native-record <record>

# 2) 进入 degraded：停发停同步（不碰任何文件，只写状态）
python3 -m pool.recovery enter-degraded --workdir <workdir> \
    --reason "ttl expired, rollback refused"

# 3) 人工恢复最后已验证安全版本（须逐字输入确认串）
python3 -m pool.recovery manual-restore --workdir <workdir> \
    --anchor <workdir>/publish/history/pool-new-<ts>.txt \
    --native-record <record> \
    --owner-ack OWNER-ACK-RESTORE-LAST-VERIFIED-SAFE

# 4) 核对：served 文件已是干净版本，但状态仍是 manual-restored，
#    publish/sync 仍拒绝 -- 这是故意的，等 fresh 复测
python3 -m pool.recovery status --workdir <workdir> --native-record <record>

# 5) 手机做一次新的原生整组复测，产出新的 native record 文件
#    （fresh.json：同一版本的 run，tested_at 为新时间，全部通过）

# 6) 有 fresh 证据后清 STOP，回到 ok
python3 -m pool.recovery clear-stop --workdir <workdir> \
    --native-record <fresh-record> \
    --owner-ack OWNER-ACK-CLEAR-STOP

# 7) 恢复正常发布（走门禁），再同步一次并核对 SHA
python3 -m pool.publish --workdir <workdir> --candidates <clean> \
    --source-file <source> --native-record <fresh-record> \
    --source-version <sha>
python3 -m pool.sync --workdir <workdir> --native-record <fresh-record>
```

**禁区**：第 6 步之前，绝不要以任何方式声称 restored 版本「已验证合格」；
它只是「已知的最好版本」，fresh 复测通过前一直是 unverified。

## 2. 场景 S2：原生结果缺失（record 文件丢失/损坏/无此版本证据）

**现象**：回滚拒绝 `rollback_chain_chain_native_record_*`，`recovery.recommended_action == "rebuild-from-fresh-native-test"`，`last_verified_safe == null`。

**处置**：

```bash
# 1) 评估确认无任何可恢复锚点
python3 -m pool.recovery assess --workdir <workdir> --native-record <record>

# 2) 进入 degraded，停发停同步
python3 -m pool.recovery enter-degraded --workdir <workdir> \
    --reason "native record missing"

# 3) 不要尝试 manual-restore：它会拒绝（anchor_not_restorable），
#    因为没有任何锚点能被证明匹配证据
# 4) 手机做一次新的原生整组复测，产出新的 native record；
#    用新 record 重新走一次 gated publish + sync（不要复用旧 sidecar）
# 5) 有 fresh 证据且 served 文件通过门禁后，按 S1 第 6 步清 STOP
```

**为什么不能用旧文件顶着**：没有证据，任何旧文件都无法证明它
曾经合格；继续服务它等于无门禁服务。停发 + 等 fresh 复测是唯一
诚实路径。

## 3. 场景 S3：生产已坏、回滚又被拒

**现象**：served 文件已被 legacy 写手覆盖成未门禁内容（44 行），
同时回滚因 TTL 过期被拒。

**处置**：

```bash
# 1) 先确认 served 文件的真实定性（应为 broken-unqualified）
python3 -m pool.recovery status --workdir <workdir> --native-record <record>

# 2) 进入 degraded（停发停同步，防止坏版本被再次同步扩散）
python3 -m pool.recovery enter-degraded --workdir <workdir> \
    --reason "production broken, rollback refused"

# 3) 人工恢复 last_verified_safe（同 S1 第 3 步）
python3 -m pool.recovery manual-restore --workdir <workdir> \
    --anchor <workdir>/publish/history/pool-new-<ts>.txt \
    --native-record <record> \
    --owner-ack OWNER-ACK-RESTORE-LAST-VERIFIED-SAFE

# 4) 核对 served 已是干净版本、状态 manual-restored-unverified
# 5) 手机 fresh 原生复测 -> clear-stop -> 恢复正常发布（同 S1 第 5-7 步）
```

**注意**：第 3 步恢复的是 publish/ 与 served/ 两个文件（含 sidecar）；
恢复后仍需 fresh 复测才能回到 `ok`，不要跳步。

## 4. 状态文件丢失（D3 新增）

**现象**：publish / sync / rollback 拒绝，错误码以 `recovery_state_*`
或 `recovery_anchor_*` 开头；`status` 报 `state=unknown-unsafe`。

**第一步永远是：看错误码，不要猜。**

| 错误码 | 含义 | 处置 |
|---|---|---|
| `recovery_state_uninitialized` | 两记录皆无，全新部署 | §0 init（`fresh`） |
| `recovery_state_missing` | 状态文件缺失，锚点未记录 STOP | init（`rebuild-from-anchor`） |
| `recovery_state_missing_stop_recorded` | 状态文件缺失，**但锚点记录了 STOP** | **不要 init**（init 会拒绝）。按 S1 走：`manual-restore` → fresh 复测 → `clear-stop` |
| `init_refused_existing_install_records_lost` | 两记录皆无，但 workdir 是已有安装（served/publish/history 任一存在） | 不要反复 plain init。按 §0b 走：外部备份/部署标记恢复，或人工审核后 `--allow-fresh-after-records-loss` 重建（带 records-loss-recovery 审计事件） |
| `recovery_state_write_interrupted` | 状态文件缺失但 `.tmp` 残留（原子写中断） | 删掉 `.tmp` 残留（记入操作记录），再 init（`rebuild-from-anchor`）；若锚点也记录了 STOP，按上一行处理 |
| `recovery_state_corrupt` | 状态文件 JSON 解析失败 / 内容不完整 | init 会拒绝（`init_refused_unreadable_state`）。**刻意**移除该文件（记入操作记录），再 init（`rebuild-from-anchor`）；若锚点记录了 STOP，按 S1 处理 |
| `recovery_state_unreadable` | 权限/IO 错误（含文件被目录替换） | 先修权限或移走占位目录，再按 corrupt 一行处理 |
| `recovery_state_illegal` | 未知状态值 / 形状错误 | 同 corrupt 一行 |
| `recovery_state_checksum_mismatch` | 状态文件内容与锚点 sha256 不符（被篡改或被旧副本替换） | **不要直接 init**。先查 history/锚点确认哪一份是新的：若锚点更新（seq 更大）且未 stopped，刻意移除状态文件后 init（`rebuild-from-anchor`）；若锚点记录了 STOP，按 S1 处理；若两份都可疑，按 S2（无可信锚点）处理 |
| `recovery_state_anchor_mismatch` | 状态文件与锚点字段不一致 | 同上一行 |
| `recovery_anchor_missing` | 锚点文件缺失，状态文件完好 | init（`rebuild-anchor`）；若状态文件记录了 STOP，init 会拒绝，按 S1 处理 |
| `recovery_anchor_unreadable` / `_corrupt` / `_illegal` | 锚点不可读 / 解析失败 / 形状错误 | 同上一行（状态文件完好时 init 重建锚点）；若状态文件也坏了，按 S2 处理 |
| `pool_stopped` | 状态本身有效且 stopped | 按 S1 处理（不要 init） |

**处置模板（状态文件丢失、锚点完好、未 stopped）**：

```bash
# 1) 确认错误码与锚点状态
python3 -m pool.recovery status --workdir <workdir> --native-record <record>
#    应看到 state_error=recovery_state_missing，stopped=False 的锚点

# 2) 若有 .tmp 残留，先删掉它（记入操作记录）
rm <workdir>/recovery-state.json.tmp

# 3) init 重建（mode 应为 rebuild-from-anchor）
python3 -m pool.recovery init --workdir <workdir> \
    --owner-ack OWNER-ACK-INIT-RECOVERY-STATE

# 4) 核对状态回 ok，publish/sync 恢复
python3 -m pool.recovery status --workdir <workdir> --native-record <record>
```

**处置模板（STOP 已记录、状态文件丢失）**：

```bash
# 1) 错误码应为 recovery_state_missing_stop_recorded；init 会拒绝
python3 -m pool.recovery init --workdir <workdir> \
    --owner-ack OWNER-ACK-INIT-RECOVERY-STATE
#    -> init_refused_stop_recorded（这是正确行为，不要绕过）

# 2) 按 S1 走 manual-restore -> fresh 复测 -> clear-stop
#    （manual-restore 从锚点的最后已知状态加载，不依赖状态文件）
```

**绝对不要做的事**：

- 不要手写一个 `{"state": "ok", ...}` 的状态文件去「补」——它没有
  锚点，门禁会拒绝（`recovery_anchor_missing`）；即使你同时手写
  锚点，checksum 也会对不上。这正是 D3 要防的。
- 不要为了 init 通过而删锚点：删锚点 + 删状态文件 = 两记录皆无，
  plain init 在已有安装上会以 `init_refused_existing_install_records_lost`
  拒绝（须人工审核 + allow 标志才放行，且留 records-loss-recovery
  审计事件）。删双记录 + 跑 init 是**显式操作者行为**（带审计条
  目），不是事故——手册要求：删锚点前必须确认没有未处理的 STOP
  （查 `status` 的 `state_error` 是否带 `_stop_recorded` 后缀），
  并把删除动作记入操作记录。不要把它描述为“无法绕过 STOP”（见
  §0b 信任边界）。
- `.tmp` 残留不要自动清理：门禁只识别它并拒绝，不自动删除；
  删除是操作者决定（上表 S1b 行）。

## 5. 同步校验失败（sync_verify_failed）

**现象**：sync 返回 `sync_verify_failed`，结果里同时给出
`source_sha_before` / `source_sha_after` / `served_manifest_after`
三个 SHA，且恢复状态已自动进入 degraded。

**含义**：复制过程中源文件被锁外写手改了，served 文件已不是门禁
通过的那个版本。sync 已自动停发（STOP 标记已设）。

**处置**：按 S3 处理——`status` 确认 served 定性，`manual-restore`
或 fresh publish 恢复，fresh 复测后 `clear-stop`。不要手动把
served 文件拷回去：那会绕过链校验。

## 6. 常用只读检查（不改变任何状态）

```bash
# 锚点评估（每个锚点：verified_safe / last_verified_safe / unrecoverable）
python3 -m pool.recovery assess --workdir <workdir> --native-record <record>

# 状态 + served 文件实时定性
python3 -m pool.recovery status --workdir <workdir> --native-record <record>

# 直接验某条 sidecar 链（python）
python3 -c "
from pool.version_chain import read_chain_sidecar, verify_version_chain
meta, chain = read_chain_sidecar('publish', 'pool-new.txt')
lines = [l.rstrip() for l in open('publish/pool-new.txt') if l.strip()]
print(verify_version_chain(chain, lines, 'native-record.json'))
"
```

## 7. 绝对禁区

- 任何情况下不得删除 `recovery-state.json` 来「清掉」degraded 状态；
  状态只能由 `clear-stop`（+ fresh 证据 + 机主确认）解除。D3 下删
  文件也不会清掉 STOP——门禁会拒绝（`recovery_state_missing_stop_recorded`），
  只是多了一次无谓的停发。
- 不得手写状态文件或锚点去「补」丢失的记录；重建只能走 `init`
  （且 init 在 STOP 已记录时拒绝）。
- 不得删除锚点来绕过 `init_refused_stop_recorded`；删锚点前必须
  确认没有未处理的 STOP（见 §4 上表），并把删除记入操作记录。
- 不得把 `served_status` 为 `stale-not-qualified` /
  `broken-unqualified` / `manual-restored-unverified` 的 served 文件
  描述为「合格」「可用」「已验证」。
- 不得在没有 fresh 原生复测的情况下清 STOP。
- 定时器（:07/:15）被 STOP 标记挡住时，不得绕过 `pool_stopped`
  去直接写 publish/ 或 served/ 文件；定时器也不得调用 `init`。
