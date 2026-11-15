# 跨周期时序：逐步 SHA / 文件流向证明（D5）

> Issue #73，GPT D4 复核 6887331723 的跨周期要求。隔离演练证据，
> 全部合成固件（TEST-NET 192.0.2.x、密码 TEST-ONLY-NOT-A-REAL-NODE），
> 生产未动。演练日志：`docs/cross-cycle-drill-log.json`（30/30），
> 红绿对照：`docs/cross-cycle-redgreen-log.json`（13/13）。
> 本文件只含计数、SHA 前缀、时间戳、状态名、行数。

## 0. 版本与 SHA（本次演练实测，fixture 行固定故各处一致）

| 版本 | 内容 | SHA 前缀 | 行数 |
|---|---|---|---|
| v1 source | pool44（44 行合成订阅） | `f6083ad90eac` | 44 |
| v2 source | v1 去掉 1 条失败行 | `314c25b75017` | 43 |
| v3 source | v2 再去掉 1 条失败行 | `d11c91edffa4` | 42 |
| v4 source | v3 再去掉 1 条失败行 | `7d299ca8097a` | 41 |
| clean14 published/served/bridge | v1 原生通过的 14 行 | `6074082847c3` | 14 |
| 截断 $SRC（D1） | v3 前 20 行 | `e38bf1ef3c45` | 20 |
| 被篡改的目标文件（旧代码红对照） | clean14 + 1 条未准入行 | `7737d85e5d1e` | 15 |

原生记录：仅 v1 一次新鲜记录（tested_at = 演练开始前 1 小时，
TTL 24 小时）。v2/v3/v4 没有任何原生记录。

## 1. 逐步流向表（按时间顺序）

| 步骤 | 动作 | 读的文件 | 写的文件 | SHA 前/后（前缀） | 行数 | rc | 结论 |
|---|---|---|---|---|---|---|---|
| A1 :07 publish | 门禁验证当前 $SRC（v1）→ 发布 clean14；组装下一版 v2 | $SRC v1 `f6083ad90eac`、native record（v1） | $STATE/publish/pool-new.txt、`$SRC` | publish：— → `6074082847c3`；$SRC：`f6083ad90eac` → `314c25b75017` | publish 14；$SRC 43 | 0 | v1 通过并发布；组装产出 v2，**本次通过不覆盖 v2** |
| A1 周期记录 | 组装后写 `$GATE/logs/cycle-<ts>-<pid>.json` | — | cycle 记录 | gated_source_sha `f6083ad90eac`、published_sha `6074082847c3`、new_source_sha `314c25b75017` | — | — | `new_source_gated=false` 已写明 |
| A2 :15 sync | sync 重验版本链 + 门禁，复制到 served，再由 gate-sync.sh 核对后复制到 bridge | $STATE/publish/（v1 链） | $STATE/served/、bridge/pool-new.txt | served/bridge：— → `6074082847c3` | 14 | 0 | bridge 服务已验证的 v1 |
| B1 :07 publish | 门禁验证当前 $SRC（v2，未测）→ 拒绝；组装下一版 v3 | $SRC v2 `314c25b75017`、native record（无 v2） | $SRC（组装仍跑） | publish：`6074082847c3` → `6074082847c3`（不变）；$SRC：`314c25b75017` → `d11c91edffa4` | publish 14；$SRC 42 | 1 `native_version_mismatch` | v2 未通过，publish 文件保持 v1 |
| B1 周期记录 | 组装后写 cycle 记录 | — | cycle 记录 | gated_source_sha `314c25b75017`、published_sha ``（空，本次无发布）、new_source_sha `d11c91edffa4` | — | — | `new_source_gated=false`；拒绝也留记录 |
| B2 :15 sync | sync 服务仍已验证的 v1 | $STATE/publish/（v1 链） | served/bridge（重写同一内容） | served/bridge：`6074082847c3` → `6074082847c3`（不变） | 14 | 0 | **sync 仍服务 v1 是正常行为，不是“sync 拒绝了 v1”** |
| C0 对抗植入 | 旧逻辑写手把未测 v2 直接丢进 $STATE/publish/（无版本链 sidecar） | — | $STATE/publish/pool-new.txt | publish：`6074082847c3` → `314c25b75017` | 43 | —（植入动作） | 模拟绕过 publish 的写手 |
| C1 :15 sync | sync 读到无链的 v2 → 拒绝 | $STATE/publish/（v2，无链） | （无） | served/bridge：`6074082847c3` → `6074082847c3`（不变） | 14 | 1（sync 拒绝） | 植入的 v2 未被接入 |
| C2 红对照 | 旧式无门禁复制：plain cp v2 → served/bridge | v2 文件 | served/bridge | bridge：`6074082847c3` → `314c25b75017` | 43 | 0（cp 本身成功） | **红：无门禁时洞存在，v2 上了 bridge** |
| C3 绿恢复 | 下一次门禁 sync | $STATE/publish/（已恢复为 v1 链） | served/bridge | bridge：`314c25b75017` → `6074082847c3` | 14 | 0 | 门禁 sync 把已验证 v1 恢复上桥 |
| D1 组装撕裂 | 组装器写一半崩溃，$SRC 留截断的 v3（20 行）→ 下一次 publish 拒绝 | $SRC 截断 `e38bf1ef3c45` | $SRC（组装器写坏） | publish/served/bridge：`6074082847c3` 不变 | $SRC 20 | 1 `native_version_mismatch` | 撕裂源进不了发布，服务侧不动 |
| D2 原子组装崩溃 | 组装器只留 `$SRC.tmp`（v4），$SRC 仍为 v1 → 下一次 publish 重新验证 v1 通过 | $SRC v1 `f6083ad90eac` | `$SRC.tmp`（残留）、publish（重发 v1） | $SRC：`f6083ad90eac` → `f6083ad90eac`（不变）；publish `6074082847c3` | $SRC 44 | 0（门禁），组装 rc=1 | cycle 记录：`assembly_failed=true`、`src_changed=false`、`new_source_gated=false` |
| E1 publish 写前校验 | tmp 写后、rename 前被篡改（+1 条未准入行） | tmp 文件实际字节 | （无，tmp 已删） | publish：`6074082847c3` → `6074082847c3`（不变） | 14 | 1 `publish_postwrite_verify_failed` | 最终字节校验在 rename 前拦截 |
| E2 publish rename 时篡改 | tmp 在 rename 瞬间被篡改 | tmp/目标实际字节 | （目标恢复为旧字节） | publish：`6074082847c3` → `6074082847c3`（不变） | 14 | 1 `publish_postwrite_verify_failed` | 写后复核拦截，旧字节已恢复 |
| E3 sync served 复核 | served 复制后被篡改（+1 条未准入行） | served 实际字节 | （无成功宣称） | served：`6074082847c3` → `7737d85e5d1e`（篡改后原样保留，未宣称成功） | 15 | 1 `sync_served_gate_failed` | 进入 degraded（STOP），后续 publish/sync 全拒 |

## 2. 旧版通过授权什么、不授权什么

一次 :07 门禁通过，只授权**当次**、**该 source SHA** 的发布：

- 授权：把本次门禁验证过的源版本（本演练为 v1，`f6083ad90eac`）
  的准入子集（clean14，`6074082847c3`）写进 `$STATE/publish/`，
  并由后续 :15 sync 按同一版本链 + 同一原生记录复核后服务。
- 不授权：组装步骤随后产生的**新版本**（v2，`314c25b75017`）的
  发布，也不授权它被后续 sync 接入。v2 必须在下一个周期里用
  属于 v2 自己的新鲜原生记录重新过门禁（本演练 B1：拒绝，
  `native_version_mismatch`；C1：即使直接植入 publish 目录，
  sync 也拒绝）。
- 不授权：任何未经最终字节校验的文件上桥。publish 在 rename 前
  对 tmp 实际字节重算 published SHA 并重跑 allowlist（E1/E2），
  sync 在复制后重读 served 实际字节并重跑 allowlist + 版本链
  published_sha 核对（E3），gate-sync.sh 在复制到 bridge 前再把
  sync 报告的 `served_version_sha` 与 served 文件实际 SHA 比对。
  任一环节不符即拒绝，目标文件不宣称成功。

周期绑定记录（`$GATE/logs/cycle-<ts>-<pid>.json`，组装后无论
成功失败都写）是这条边界的审计锚：每条记录含 `gated_source_sha`
（本次门禁验证的源 SHA）、`published_sha`（本次门禁发布输出的
SHA，拒绝时为空）、`new_source_sha`（组装后 $SRC 的实际 SHA）、
`new_source_gated=false`（明文：本次通过不覆盖新版本）、
`assembly_rc` / `assembly_failed` / `src_changed`。日志行同样写清
`new_source_gated=false`。门禁先行的顺序未变。

## 3. 红→绿对照摘要（实测，非结论复述）

| 对照 | 旧代码（D4 树，只读引用） | 新代码（D5） |
|---|---|---|
| 盲复制 v2 上桥 | bridge SHA 变 `314c25b75017`（43 行），cp rc=0——洞存在 | 同一条 cp 同样会上桥（cp 就是 cp）；绿的是门禁 sync 拒绝植入并把 bridge 恢复为 `6074082847c3` |
| publish rename 时篡改 tmp | rc=1，但目标文件已被污染：SHA `6074082847c3` → `7737d85e5d1e`（15 行），错误 `publish_refused: post-publish verification failed` | rc=1 `publish_postwrite_verify_failed`，目标 SHA 保持 `6074082847c3`（旧字节已恢复） |
| sync served 篡改 | `sync.py` 无 served 重 gate 步骤（grep 0 处），`run_sync()` 无 `post_copy_hook` 参数（调用即 TypeError） | rc=1 `sync_served_gate_failed`，进入 degraded（`pool_stopped`） |
| 周期绑定 / 桥前核对 | `gate-publish.sh` 无 `new_source_gated`（grep 0 处）；`gate-sync.sh` 无 `served_sha_mismatch_before_bridge_copy`（grep 0 处） | 两处均已落地，单元测试覆盖 |

诚实说明：旧代码的门禁本身已能拒绝未测 v2（D2 版本绑定），
红对照不是“旧代码会放行 v2 发布”——旧代码的缺口在**最终字节**
一层：rename 后才校验且不恢复目标文件、sync 不重验 served
实际字节、脚本不记录周期绑定、不在桥前核对 served SHA。D5
补的正是这一层；其余 D2/D3 门禁行为未变。

## 4. 未做 / 边界

- 演练全部是合成固件与桩组装器：不证明真实手机测过任何版本，
  不证明生产 :07/:15 周期的表现。真实切换仍须按 D4 手册走，
  须新鲜原生整组复测 + GPT 批准 + 机主授权。
- E3 之后 served 文件保留被篡改的字节（`7737d85e5d1e`），只记
  录、不宣称成功；池子进入 degraded，需人工按恢复手册处理，
  本演练不自动恢复。
- 周期记录文件名含进程号后缀（`cycle-<ts>-<pid>.json`），避免
  并发 :07 互相覆盖；时间戳本身是秒级 unix 时间。
