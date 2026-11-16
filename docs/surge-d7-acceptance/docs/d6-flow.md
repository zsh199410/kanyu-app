# D6 流向证明：GPT D5 复核三项的最小修复（Issue #73）

- 日期：2026-11-16（CST）
- 范围：隔离环境。本地 `~/workspace/p2p3-d6/` 与 VPS `/opt/p2p3-d6/`（D5 树完整复制 + 本次改动）。
- 合成固件：TEST-NET 192.0.2.0/24、假密码 `TEST-ONLY-NOT-A-REAL-NODE`。无真实节点 URI、订阅 URL、密码、私钥、原始 IP、令牌。
- 生产状态：**生产订阅、生产定时器、手机配置一律未动**。PR #77 仍为 Draft，不合并。无手机原生测试在本轮执行。

固定 SHA（fixture 行固定，各处一致）：

| 内容 | SHA 前缀 | 行数 |
|---|---|---|
| v1 source（44 行） | `f6083ad90eac` | 44 |
| v2 source（43 行，未测） | `314c25b75017` | 43 |
| clean14（已验证发布/服务/桥） | `6074082847c3` | 14 |
| 污染版（clean14 + 1 未准入行） | `7737d85e5d1e` | 15 |

---

## 1. 第 1 项：served 污染后隔离 / 恢复（`pool/sync.py`）

修复：`_quarantine_and_restore_served()`，在锁内、永不抛错：

1. 把当前 served 文件移入 `served/.quarantine/pool-new-<ts>-<sha12>.txt`（600，sidecar 一并移走）——典型 served 路径不再暴露污染字节；
2. 从链已验证的 publish 文件恢复 served（SHA 须等于链 `published_sha` 且行全过 allowlist；tmp+rename+fsync，重读复验，sidecar 一并复制）；
3. 恢复验不过则 served 路径留空（绝不留未验证字节）、`restored=False`。

在 `sync_served_gate_failed` 与 `sync_verify_failed` 两个分支都先隔离/恢复、再进 degraded（STOP），使状态文件记的是恢复后版本而非污染版。另加符号链接守卫：served 目录或 served 文件是 symlink、或 realpath 不在 served 目录内 → 拒绝 `served_symlink_refused`（锁内、读 served 字节之前）。

### 逐步流向（`drills/d6_item1_served_quarantine.py`，15/15，双环境）

| 步骤 | 动作 | served SHA | bridge SHA | rc / 错误 |
|---|---|---|---|---|
| A 基线 | :07 publish + :15 sync，v1 已验证 | `6074082847c3`（14 行） | `6074082847c3`（14 行） | 0 |
| B cycle 间篡改 | 锁外写手向 served 追加 1 未准入行 | `7737d85e5d1e`（15 行） | `6074082847c3` | — |
| B 下一次 sync | sync 从已验证 publish 文件重写 served，篡改被覆盖 | `6074082847c3`（14 行） | `6074082847c3` | **0（正确行为）** |
| C post-copy 篡改（D5 E3 原案） | `run_sync` 复制后、重验前，hook 向 served 追加 1 未准入行 | 恢复后 `6074082847c3`（14 行） | `6074082847c3`（未动） | **1 `sync_served_gate_failed`** |
| C 隔离证据 | 污染字节只在 `served/.quarantine/pool-new-<ts>-7737d85e5d1e.txt`（600），served 路径与 bridge 路径均无污染行；`gate_check` → `pool_stopped` | — | — | STOP |
| D STOP 保持 | 下一次 :15 sync 拒绝，不重服务任何字节 | `6074082847c3` | `6074082847c3` | 1 `pool_stopped` |

### 诚实边界

- **B 步 rc=0 是正确的**：served 路径在每次 sync 都由已验证 publish 文件重写，cycle 间落入的篡改会被下一次 sync 覆盖。危险窗口是“sync 周期内”与“post-copy 瞬间”——前者由 sync 间隔界定，后者由 C 步的隔离/恢复闭合。
- **served 本身若可被 HTTP 直接读取，cycle 间窗口仍会暴露污染字节。** 因此切换前必须阻断该暴露路径，接线层面的方案已落地：`systemd/gate-sync.sh` 在同步前做 served 暴露守卫（python realpath 比对：served 解析后必须不在 `BRIDGE_DIR` 内，否则拒绝，日志 `served_path_exposure_check`）；切换手册新增 Phase 0 检查项（见 `systemd/switch-runbook.md` §11）：核对 nginx/静态托管只映射 bridge 目录，served 目录不在任何 HTTP alias/根路径下。代码守卫防的是“served 被配进 bridge 目录”的误配；“served 目录本身被 HTTP 直读”须在部署时按手册核对，不可只凭文字。
- 隔离区文件只保留污染字节与 sidecar，不自动删除、不自动恢复；恢复走已验证 publish 文件，不走隔离区。

---

## 2. 第 2 项：bridge 竞争窗口与 legacy 假成功（`pool/bridge_sync.py` + `systemd/gate-sync.sh`）

修复：新建 `pool/bridge_sync.py`（`run_bridge_sync()`），**同一共享 flock 内**完成全部桥接步骤：

1. 重验 served 实际字节（版本链 + allowlist；失败则隔离/恢复 + 进 degraded，错误码 `bridge_served_chain_*` / `bridge_served_gate_failed`）；
2. **读一次 served 字节进内存作不可变快照**——后续 bridge 与 legacy 都写这份内存字节，不再重读 served；
3. bridge 写（tmp+rename+fsync，重读验 SHA；rename 后不符则从内存里的旧 bridge 字节恢复并报 `bridge_sha_mismatch`）；
4. legacy 同法写，失败则 bridge 回滚到写前字节并报 `legacy_copy_failed`（`bridge_rolled_back=true`），绝不 rc=0；
5. 写后锁内再重读 served，若变了则隔离/恢复 + 进 degraded，报 `served_changed_after_bridge_copy`（bridge 已是验证字节，记 `bridge_updated_verified=true`，run 仍 rc=1）。

`gate-sync.sh` 已重写：保留 `pool.sync` 调用与 D5 桥前 SHA 核对（作 tripwire）；shell 复制块改为调用 `python3 -m pool.bridge_sync`，按其 rc 退出；新增 served 暴露守卫（见 §1）。

### 逐步流向

#### 2a. SHA 检查后 / bridge rename 前 served 被改写（`drills/d6_item2_bridge_race.py` A 步，in-process hook 注入）

| 步骤 | 动作 | bridge SHA | served SHA | rc / 错误 |
|---|---|---|---|---|
| 基线 | publish + sync，v1 已验证 | — | `6074082847c3` | 0 |
| 注入 | hook 在快照后、rename 前重写 served（追加 1 未准入行） | `6074082847c3`（只收到快照字节） | 恢复后 `6074082847c3` | **1 `served_changed_after_bridge_copy`** |
| 隔离证据 | `served_restored=true`；`gate_check` → `pool_stopped` | — | — | STOP |

#### 2b. legacy copy 失败（`drills/d6_item2_bridge_race.py` B 步，真实 gate-sync.sh）

| 步骤 | 动作 | bridge SHA | legacy | rc / 错误 |
|---|---|---|---|---|
| 基线 | publish + sync，bridge 与 legacy 均为 clean14 | `6074082847c3` | `6074082847c3` | 0 |
| 注入 | legacy manifest 指向不存在的目录 | `6074082847c3`（回滚到写前字节） | 未写入（不存在） | **1 `legacy_copy_failed`** |
| 假成功检查 | `gate-sync.log` 里 `synced served_sha` 行仍只有 1 条（仅第一次成功运行），失败运行未 claim 成功 | — | — | — |

### 诚实边界

- 2a 的注入是确定性的 hook（快照后、rename 前）；真实并发写手的时间窗口无法在隔离环境逐毫秒复现，hook 证明的是“即使窗口被命中，bridge 也只收快照字节”。
- legacy 父目录缺失时不自动建目录（必须失败，故障注入才有效）；部署时 legacy 路径须由人工/安装步骤预建目录，见 `systemd/switch-runbook.md` §11。
- 双目标一致性定义：bridge 与 legacy 要么同为同一快照字节（SHA 一致），要么 run 失败且 bridge 回滚到写前字节；不存在“bridge 已更新、legacy 静默失败、run 宣称成功”的状态。

---

## 3. 第 3 项：gate-publish.sh 退出码语义（`systemd/gate-publish.sh` + `$GATE/logs/health.json`）

修复：退出码与健康文件分开两种状态——

| 退出码 | health | 含义 |
|---|---|---|
| 0 | `healthy` | 门禁通过 **且** 组装成功 |
| 1 | `gate_refused` / `precheck_failed` | 门禁拒绝或预检失败（门禁拒绝占优） |
| 2 | `published_assembly_failed` | 门禁通过但组装失败 |

每周期原子写 `$GATE/logs/health.json`（health、gate_rc、assembly_rc、各 SHA 前缀、`new_source_gated=false`、`assembly_failed`、`src_changed`；预检失败时 gate_rc/assembly_rc=-1）。**exit=0 不得再被解释为整个周期全部成功**：exit=0 只表示“本轮已验证发布成功”；下一轮源组装失败时 exit=2，timer 仍为成功触发（systemd 视角的“跑完了”），监控应看 health.json 而非退出码。

timer/监控告警（接线层面，见 `systemd/switch-runbook.md` §11）：

- 监控脚本每周期读 `$GATE/logs/health.json`：`health != healthy` 即告警（`published_assembly_failed` 为“下一轮源组装失败，需人工看组装器/磁盘”；`gate_refused` 为“门禁拒绝，看门禁日志与原生证据新鲜度”）；
- 退出码 2 不触发 timer 的失败重试（组装失败重试无意义，须人工修组装器），但须进告警通道；
- 下一周期不误判的保证：组装失败不改 publish 文件（原子写：只留 `.tmp` 或撕裂 $SRC 由下一轮门禁拒绝），served/bridge 保持已验证版本。

### 逐步流向（`drills/d6_item3_publish_exit.py`，五周期序列，17/17，双环境）

| 周期 | 组装器模式 | 门禁 | 组装 | exit | health | $SRC 之后 | publish SHA |
|---|---|---|---|---|---|---|---|
| C1 | 正常（产 v2） | 通过 v1 | 成功 | 0 | `healthy` | v2 `314c25b75017` | `6074082847c3` |
| C2 | torn（写 20 行后崩） | 通过 v1 | 失败 | **2** | `published_assembly_failed` | 撕裂 20 行 | `6074082847c3`（不变） |
| C3 | torn（$SRC 仍是撕裂版） | 拒绝（无此版本证据） | 失败 | **1** | `gate_refused` | 撕裂 20 行 | `6074082847c3`（不变） |
| C4 | atomictmp（只留 .tmp） | 通过 v1 | 失败 | **2** | `published_assembly_failed` | 仍 v1 `f6083ad90eac` | `6074082847c3`（不变） |
| C5 | 正常（产 v2） | 通过 v1 | 成功 | **0** | `healthy` | v2 `314c25b75017` | `6074082847c3` |

C3 证明：上一轮组装失败既未被误判为“发布失败”（C2 的发布完好），门禁拒绝也未被误判为“组装问题”（C3 exit=1 且 served/bridge 不变）；C5 证明：组装失败没有毒化下一周期，同一 v1 源重验后仍可 exit=0。

---

## 4. D5 流向表 E3 的更新（D6 指针）

D5 `docs/cross-cycle-flow.md` §4 曾记录：“E3 之后 served 文件保留被篡改的字节（`7737d85e5d1e`），只记录、不宣称成功”。**D6 起该句作废**：同一注入在 D6 下 served 被恢复为 `6074082847c3`，污染字节只存于 `served/.quarantine/`（600）。其余 D5 流向结论不变。
