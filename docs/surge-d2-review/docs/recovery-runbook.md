# D2 故障恢复处置手册（Recovery Runbook）

> 适用：D2 隔离代码（`pool/`），生产未动。本文只讲**隔离环境**的处置步骤；
> 生产切换步骤（含 systemd 定时器切换、私有备份、手机验收）见 D2 报告
> §6，切换前须 GPT 批准 + 机主授权。
>
> 核心原则：**旧服务文件被保留时，永远不称它合格**。它的状态只能是
> `stale-not-qualified`（证据过期）、`broken-unqualified`（文件与证据
> 不符）或 `manual-restored-unverified`（人工恢复后、待 fresh 复测）。
> 恢复到 `ok` 的唯一路径：一次新的手机原生复测通过 + 机主明确确认。

## 0. 状态机速查

| 状态 | STOP 标记 | publish/sync | served 文件定性 |
|---|---|---|---|
| `ok` | 否 | 正常（门禁） | `qualified`（门禁当前承认） |
| `degraded` | 是 | 拒绝 `pool_stopped` | `stale-not-qualified` / `broken-unqualified` |
| `manual-restored` | 是 | 拒绝 `pool_stopped` | `manual-restored-unverified` |

查看状态：

```bash
cd /opt/p2p3-d2   # 隔离目录；生产路径不同，勿混
python3 -m pool.recovery status --workdir <workdir> --native-record <record>
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

## 4. 同步校验失败（sync_verify_failed）

**现象**：sync 返回 `sync_verify_failed`，结果里同时给出
`source_sha_before` / `source_sha_after` / `served_manifest_after`
三个 SHA，且恢复状态已自动进入 degraded。

**含义**：复制过程中源文件被锁外写手改了，served 文件已不是门禁
通过的那个版本。sync 已自动停发（STOP 标记已设）。

**处置**：按 S3 处理——`status` 确认 served 定性，`manual-restore`
或 fresh publish 恢复，fresh 复测后 `clear-stop`。不要手动把
served 文件拷回去：那会绕过链校验。

## 5. 常用只读检查（不改变任何状态）

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

## 6. 绝对禁区

- 任何情况下不得删除 `recovery-state.json` 来「清掉」degraded 状态；
  状态只能由 `clear-stop`（+ fresh 证据 + 机主确认）解除。
- 不得把 `served_status` 为 `stale-not-qualified` /
  `broken-unqualified` / `manual-restored-unverified` 的 served 文件
  描述为「合格」「可用」「已验证」。
- 不得在没有 fresh 原生复测的情况下清 STOP。
- 定时器（:07/:15）被 STOP 标记挡住时，不得绕过 `pool_stopped`
  去直接写 publish/ 或 served/ 文件。
