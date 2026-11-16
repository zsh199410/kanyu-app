# D5 报告 — GPT D3 复核三项补证 + D4 跨周期时序 + 备份恢复核实

- 日期：2026-11-15（CST）
- 范围：隔离环境。本地 `~/workspace/p2p3-d5/` 与 VPS `/opt/p2p3-d5/`（D4 树完整复制 + 本次改动；D4 真实快照目录未复制）。
- 合成固件：TEST-NET 192.0.2.0/24 与 198.51.100.0/24、假密码 `TEST-ONLY-NOT-A-REAL-NODE`。无真实节点 URI、订阅 URL、密码、私钥、原始 IP、令牌。
- 生产状态：**生产订阅、生产定时器、手机配置一律未动**。PR #77 仍为 Draft，不合并。无手机原生测试在本轮执行。

本报告逐项回应 GPT 两条复核：评论 6886420557（D3，2026-11-15 00:13:44Z）三项补证；评论 6887331723（D4，2026-11-15 01:31:01Z）跨周期时序风险（优先项）与备份恢复、生产巡检两项。

---

## 0. 总览

| GPT 要求 | 落地 | 证据 |
|---|---|---|
| D3-① 不可读场景实际跑绿（非 root） | `tests/test_d5_d3.py` 14 项 + `drills/run_nonroot_tests.sh` | 非 root 37/37，exit 0，双环境 |
| D3-② 初始化信任边界 | `init_recovery_state()` 加 `allow_fresh_after_records_loss` + 拒绝路径；`docs/recovery-runbook.md` §0b；负例 A/B | 见 §2 |
| D3-③ 锚点写入顺序与崩溃窗口 | `_TEST_CRASH_POINT` 钩子 + `drills/crash_window_drill.py`（N=20） | 双环境 all_pass，撕裂拒绝 0 次 |
| D4-① 跨周期时序：门禁校验最终服务字节 | `pool/publish.py` 写前校验、`pool/sync.py` served 复核、两脚本周期绑定/桥前核对 | 演练 30/30、红绿 13/13，双环境 |
| D4-② 备份恢复可执行性 | `drills/backup_restore_drill.py` + `drills/snapshot_backup_d5.py` | 13/13 + 1 信息项，双环境 |
| D4-③ 生产 65 行 dry-run 零合格 | 流程要求，已记入 §8；**未跑手机测试** | — |
| DIRECT 三场景最简指引 | `docs/direct-test-onepager.md`（一页，43 行） | 手机实测未做 |

全套测试（见 §7）本地与 VPS 均为 **115 项**：root 下 OK（跳过 7 项，均为 root 无法真正执行 chmod-000 的用例）；非 root（d5test，uid 1000）下 **115/115 通过、0 跳过**。

---

## 1. D3-① 不可读场景实际跑绿（非 root）

### 改动
- `tests/test_d5_d3.py`（新建，14 项）：`test_nonroot_unreadable_state_file`、`test_nonroot_unreadable_state_dir`、`test_nonroot_unreadable_anchor_file`、`test_nonroot_unreadable_anchor_dir`、EACCES/EPERM 注入（`_SimulatedCrash`/`_TEST_CRASH_POINT` 同款钩子）、`test_nonroot_served_unknown_when_served_unreadable`、`test_nonroot_existing_install_records_lost_requires_allow`、`test_nonroot_gate_refuses_on_unreadable_records`，以及 §2/§3 的负例与钩子测试（见下）。
- `drills/run_nonroot_tests.sh`（新建）：建 `d5test` 用户（无 sudo）并以非 root 身份跑 `tests/test_d5_d3.py` + `tests/test_d3.py`，出 JSON 日志（euid、逐项结果、退出码）。

### 实测数字（协调员亲自复跑，非转述）
- 本地（Python 3.12.3）：专项 37/37，exit 0，euid 1000，0 跳过（`docs/nonroot-test-log.json`）。
- VPS（Python 3.13.5）：专项 37/37，exit 0，euid 1000，0 跳过（`docs/nonroot-test-log-vps.json`）。
- 全套 115 项非 root：本地与 VPS 均为 OK、0 跳过（专项 37 项为其子集）。

### 退出码与 SHA 证据
- 不可读状态文件/目录、不可读锚点文件/目录：门禁均拒绝，`recovery_state_uninitialized`，目标文件 SHA 不变（断言在测试内，逐项核对）。
- 目标文件 SHA 不变证据：每项不可读测试前后对 `recovery-state.json` 与 `recovery-anchor.json` 取 SHA，前后一致。

### 诚实边界（实测行为与预期不符处，如实记录，未改代码迎合断言）
- **workdir chmod 000**：实测拒绝码为 `recovery_state_uninitialized`（`os.path.exists()` 在权限不足时返回 False 而非抛错），门禁仍 fail-closed；断言按实际行为写，**未改 D3 读路径**。
- **Linux 下无写权限目录建文件**：报 EACCES 而非 EPERM；断言 `PermissionError` 并记录实际 errno。
- **served 目录 chmod 000**：恢复门禁不查 served，门禁仍开；断言 `_served_binding()` 为空与 `status()` served 为 `unknown-no-evidence`，且 `run_sync` 抛 `PermissionError` 而非 rc=1（sync 里无此映射，如实记录，**未顺手改**）。

---

## 2. D3-② 显式初始化信任边界

### 代码改动（`pool/recovery.py`）
- `init_recovery_state()` 加参数 `allow_fresh_after_records_loss`（默认 False）与拒绝 `init_refused_existing_install_records_lost`：
  - 双记录均缺失 + **无**存活安装痕迹（无 served manifest/sidecar、无 gate 日志、无旧 state 残留）→ fresh 初始化（首次安装路径）。
  - 双记录均缺失 + **有**存活安装痕迹 → 拒绝，除非调用方显式传 `allow_fresh_after_records_loss=True`（人工路径），且人工路径记 `records-loss-recovery` 审计事件。
- CLI `init` 加 `--allow-fresh-after-records-loss`（默认关）。

### 手册（`docs/recovery-runbook.md` 新增 §0b「显式初始化的信任边界」）
- 明确：fresh 重建是**受控人工信任建立**，不能由 timer/service 自动调用；对已有安装误删双记录的情形，要求外部持久部署标记/备份或人工恢复审核。
- 明确：`_served_binding()` 仅取当前 served manifest/sidecar 标识，**不验证原生证据新鲜**；不要描述为“无法绕过 STOP”。
- 明确：首次初始化后发布仍需 fresh native gate；双文件丢失不自动恢复。

### 负例
- **负例 A**：fresh init 后，用 stale 证据 publish → 拒绝，门禁类 `phone_gate_zero_qualified`。
- **负例 B**：双记录丢失时门禁 `recovery_state_uninitialized`；plain init 拒绝 `init_refused_existing_install_records_lost`；显式 `--allow-fresh-after-records-loss` 才可人工重建，并留审计事件。

---

## 3. D3-③ 锚点写入顺序与崩溃窗口

### 代码改动（`pool/recovery.py`）
- `_write_state()` 加测试钩子 `_TEST_CRASH_POINT` + 异常 `_SimulatedCrash`：可在 state 已落盘/anchor 未落盘、anchor 已落盘两个边界点模拟崩溃（确定性，不依赖时序运气）。

### 确定性钩子测试（`tests/test_d5_d3.py` 内）
- state 已落盘、anchor 未落盘时崩溃 → 后续读拒绝（`recovery_state_uninitialized` 或状态/锚点不一致），**不重建 ok**。
- anchor 已落盘时崩溃 → 读出完整一致状态，历史 STOP 保留。
- 后续 init 不会无意清除历史 STOP（断言 STOP 在演练后仍在）。

### 随机 SIGKILL 演练（`drills/crash_window_drill.py`，N=20）
- 本地：all_pass。A 相（state 写期间 kill）STOP 存活 10/10；B 相（anchor 写期间 kill）STOP 存活 7/10，另 3 次为完整 ok 写覆盖（单列不计失败）；撕裂拒绝 0 次；served SHA 全程不变。
- VPS：all_pass。N=20，STOP 存活 14 次，撕裂拒绝 0 次；served SHA 全程不变。
- 撕裂证据来自确定性钩子测试；随机演练的 B 相“存活”比例随 kill 时序波动是预期行为（完整写覆盖是合法结果，不是撕裂）。

---

## 4. D4-① 跨周期时序：门禁校验最终将服务的字节

### 问题
`gate-publish.sh` 是“先用 D3 门禁验证当前源文件，通过后再运行生产组装器生成下一版本”。旧版通过只授权当次、该 source SHA（v1）的发布；若下一版本（v2）与本次手机原生记录绑定的 source SHA 不同，旧版通过不能授权 v2 的发布或被后续 sync 接入。门禁必须校验**最终将服务的字节**，而非只校验组装前的输入。

### 代码改动
- `pool/publish_lock.py`：`_atomic_write_inner()` 新增 `verify`（写前最终字节校验回调）与 `pre_rename_hook`（仅测试用故障注入点）。tmp 写后、rename 前校验失败 → 删 tmp、目标不动；rename 后校验失败 → 从写前快照恢复旧字节与 sidecar 再拒绝（D4 是把已 rename 但未通过校验的字节留在目标里）。
- `pool/publish.py`：`run_publish()` 写前对 tmp 实际字节做两件事再 rename：(a) 重算 published SHA 与版本链 `published_sha` 比对；(b) 对 tmp 实际行重跑 native allowlist。任一不符返回 rc=1、错误码 **`publish_postwrite_verify_failed`**，tmp 删除、目标 SHA 不变。写后重读目标文件再验一次。结果字典新增 `postwrite_verified=true` 与 `published_manifest_after`（写后实际 manifest）。
- `pool/sync.py`：`run_sync()` 复制到 served 之后、返回成功之前，重读 served 实际字节并重跑 `gate_lines(served_lines, admitted)` 与版本链 `published_sha` 核对（不是只比 SHA 是否等于 source）。不符返回 rc=1、错误码 **`sync_served_gate_failed`**，走已有降级路径（`_enter_degraded_inner`，STOP），served 不宣称成功。成功时结果含 `served_verified=true`。
- `systemd/gate-publish.sh`：组装步骤之后（无论成功失败）写 `$GATE/logs/cycle-<ts>-<pid>.json`，含 `gated_source_sha`、`published_sha`、`new_source_sha`、`new_source_gated=false`（明文：本次通过不覆盖新版本）、`assembly_rc`、`assembly_failed`、`src_changed`；日志行同样写清 `new_source_gated=false`。门禁先行顺序未变。
- `systemd/gate-sync.sh`：复制 served→bridge 之前，从 `SYNC_OUT` 取 `served_version_sha`（完整 SHA）与 `sha256sum $SERVED` 实际值比对；不一致拒绝（exit 1，日志 `served_sha_mismatch_before_bridge_copy`），served 与 bridge 均保持原样；已有复制后 bridge SHA 核对不动。

### 端到端演练（`drills/cross_cycle_drill.py`，真实双脚本 + 真实 D5 代码 + 桩组装器）
**30/30 通过，本地与 VPS 一致，SHA 相同**（`docs/cross-cycle-drill-log.json` 与 `-vps.json`）：
- A（基线）：v1 新鲜记录 → :07 publish rc=0（发布 == clean14 `6074082847c3`）→ :15 sync rc=0，bridge == v1。
- B（v1 通过→组装 v2 未测）：v2（`314c25b75017`，无原生证据）→ 下次 :07 publish rc=1 `native_version_mismatch`，publish SHA 仍为 v1；下次 :15 sync rc=0 **仍服务已验证的 v1**（正常服务，不是拒绝 v1）。
- C（对抗 sync 接入）：旧逻辑写手把未测 v2 丢进 `$STATE/publish/` → sync rc=1 拒绝，served/bridge 仍为 v1；红对照 plain cp 把 v2 送上 bridge（bridge SHA 变 v2，43 行），随后门禁 sync 把 v1 恢复上桥。
- D1（组装器撕裂写：截断 $SRC，20 行）→ 下次 publish rc=1，served/bridge 不变。D2（原子组装崩溃只留 `.tmp`，$SRC 仍为 v1）→ 下次 publish 重新验证 v1 通过（rc=0），cycle 记录 `assembly_failed=true`、`new_source_gated=false`。
- E（最终字节故障注入）：tmp 篡改（rename 前）→ rc=1 `publish_postwrite_verify_failed`，目标不变；rename 瞬间篡改 → 同码拒绝，旧字节已恢复；served 篡改 → rc=1 `sync_served_gate_failed` + degraded（`pool_stopped`）。

### 红→绿演示（`drills/cross_cycle_redgreen.py`，D4 树只读引用，未改动）
**13/13 通过，双环境一致**（`docs/cross-cycle-redgreen-log.json` 与 `-vps.json`）：
- 红（D4 代码实测）：盲复制 bridge SHA 变 v2（`314c25b75017`）；publish rename 时篡改后 rc=1 但**目标文件被污染**（SHA `6074082847c3` → `7737d85e5d1e`，15 行）；`sync.py` 无 served 重 gate（grep 0 处，`run_sync(post_copy_hook=…)` 直接 TypeError）；脚本无周期绑定与桥前核对（grep 0 处）。
- 绿（D5 代码）：对应全部为目标 SHA 不变、`sync_served_gate_failed` + degraded、周期记录与桥前核对就位。

### 诚实说明
- 旧代码的门禁本身已能拒绝未测 v2（D2 版本绑定）；红对照不是“旧代码会放行 v2 发布”——旧代码缺口在**最终字节一层**（rename 后才校验且不恢复目标、sync 不重验 served 实际字节、脚本无周期绑定与桥前核对）。报告与流向文档中已如实写清，未夸大。
- 盲 cp 本身在新旧两树上都能把 v2 送上桥（cp 就是 cp）；防线是门禁 sync，不是禁止 cp。红绿演示中已如实标注为红对照。
- E3 之后 served 文件保留被篡改的字节（`7737d85e5d1e`），只记录、不宣称成功；池子进 degraded，需人工按恢复手册处理，演练不自动恢复。
- 全部合成固件与桩组装器：不证明真实手机测过任何版本，不证明生产 :07/:15 周期的表现。真实切换仍须新鲜原生整组复测 + GPT 批准 + 机主授权。

### 逐步 SHA/文件流向证明
见 `docs/cross-cycle-flow.md`（按时间顺序的步骤、读/写文件、SHA 前缀前后、行数、rc、结论）。核心结论：**旧版通过仅授权当次、该 source SHA（v1）的发布，不授权 v2 的发布与接入**；新代码在 publish 写前、写后、sync served 复核、sync 桥前四处校验最终字节。

---

## 5. D4-② 备份恢复可执行性核实（桌面演练）

`drills/backup_restore_drill.py` + `drills/snapshot_backup_d5.py`（D4 快照逻辑隔离改写）。合成规模：pool.db 12 节点 / 3 钉选 / 2 拉黑 / 20 测试记录，发布 8 行（3 钉选 / 5 轮换）。

**13/13 通过 + 1 信息项，本地与 VPS 一致**（`docs/backup-restore-drill-log.json` 与 `-vps.json`）：
- 快照清单完整：15 文件，发布文件 SHA 前缀 `174c9558ff11`，双环境一致。
- WAL 两情形通过：情形一，先清除过期 -wal/-shm 各 22 字节再放回主 DB，恢复后 12 行无残留；情形二，原始 DB + 真实 -wal/-shm 回放得 12 行，checkpoint 后仍 12 行（源 DB 有 4 行未 checkpoint、live -wal 4152 字节，backup API 快照仍拿到 12 行）。
- 服务/定时器恢复后 SHA 一致性：4 个单元 `systemd-analyze verify` exit 码全部为 0；4 单元 + 2 包装脚本 SHA 与 manifest 0 不匹配。
- 门禁 dry-run：快照件与恢复件 verdict 相同（均为 rc=1 `phone_gate_zero_qualified`，预期拒绝，只证恢复无失真）。
- 信息项（不计入通过门，与 D4 的 9/10 口径一致）：旧式无清单备份对照——存在、可恢复，但无 manifest 自证。

### 两个真实发现与修复
1. **只读打开 WAL 副本会留副文件**：只读打开 WAL 副本留下 0 字节 -wal + 32768 字节 -shm，且快照脚本自身的校验读同样会留副文件。D5 快照脚本已改为每次校验读后立即清理并收尾全目录扫一遍，快照后目录内副文件数为 0。
2. **快照 600 权限丢可执行位**：快照把全部文件存为 600，恢复出的包装脚本会失去可执行位，verify 首跑实测报 `is not executable: Permission denied`。恢复步骤已补「恢复后对两个包装脚本重授 +x」并断言可执行。

### 桌面演练边界
- D4 真实快照未读取/复制/下载；「停→恢复→起」只做桌面推演，未实际启停任何真实 systemd 服务/定时器。
- 快照脚本自带隔离守卫：对非隔离根路径拒绝快照（实测 `src_not_isolation_root`，rc=2），防止误对任意目录快照。

---

## 6. DIRECT 三场景最简指引（手机实测未做）

`docs/direct-test-onepager.md`（一页，43 行中文），以 D4 `direct-test-plan.md` 为底压成最简操作：三种情形（情形 A：免费池全灭时确认是不是池子问题；情形 B：怀疑某条规则/分组把流量带偏；情形 C：怀疑 Surge 本身/网络），每种写清要做什么、要记录什么（截图 + 时间 + 状态栏），以及收尾（删测试组、恢复原规则）。**手机实测本身不要做、不要动手机配置**——本轮未执行，等机主定时间。

---

## 7. 测试总表（协调员亲自复验，双环境）

| 套件 | 本地 Python 3.12.3 | VPS Python 3.13.5 |
|---|---|---|
| 全套 unittest（D1 24 + D2 39 + D3 23 + D4 7 + D5-D3 14 + D5-cycle 8 = 115）root | OK（跳过 7） | OK（跳过 7） |
| 全套 115 项非 root（d5test，uid 1000） | OK，0 跳过 | OK，0 跳过 |
| 非 root 专项（D5-D3 14 + D3 23 = 37）`run_nonroot_tests.sh` | 37/37，exit 0 | 37/37，exit 0 |
| 崩溃窗口演练 `crash_window_drill.py` N=20 | all_pass（A 10/10，B 7/10 存活 + 3 完整写覆盖，撕裂 0） | all_pass（存活 14，撕裂 0） |
| 跨周期演练 `cross_cycle_drill.py` | 30/30 | 30/30 |
| 跨周期红绿 `cross_cycle_redgreen.py` | 13/13 | 13/13 |
| 备份恢复演练 `backup_restore_drill.py` | 13/13 + 1 信息项 | 13/13 + 1 信息项 |

注：root 下跳过的 7 项为 1 项 D3 chmod-000 + 6 项 D5-D3 root 无法真正执行 chmod-000 的用例；非 root 下全部跑通，0 跳过。

---

## 8. 诚实边界与未闭合风险

1. **生产仍在提供未被当前手机证据认证的订阅（GPT D4 第 1 项，流程要求）**：生产巡检 65 行但 dry-run `phone_gate_zero_qualified`/`native_version_mismatch`。切换准备须先冻结版本、再做同 SHA 原生整组复测；不要把 14 条旧截图/合成 fixture 当作当前有效记录。**本轮未跑手机测试**。
2. **生产切换未批准**：D4 裁决仍有效——继续隔离验证/准备切换清单，不批准生产切换、不合并 PR。本轮不请求生产切换。
3. **DIRECT 手机测试未做**：指引已备（§6），等机主定时间。
4. **新一轮手机原生整组复测未做**：2026-11-14 13:24 的数据已 stale；切换前与切换后各需一次，等机主定时间。
5. **合成证据边界**：本轮全部证据来自合成固件与桩组装器；不证明真实手机测过任何版本，不证明生产 :07/:15 周期的表现。
6. **served 目录不可读时 sync 抛 PermissionError 而非 rc=1**（§1 诚实边界）：sync 里无此映射，如实记录，未顺手改。
7. **E3 篡改后 served 保留脏字节**：演练池进 degraded，需人工按恢复手册处理，演练不自动恢复。

---

## 9. 改动文件清单（相对 D4 树）

### 代码
- `pool/recovery.py`：`_TEST_CRASH_POINT` 钩子 + `_SimulatedCrash`；`init_recovery_state()` 加 `allow_fresh_after_records_loss` 参数与 `init_refused_existing_install_records_lost` 拒绝；人工路径记 `records-loss-recovery` 审计事件；CLI `init` 加 `--allow-fresh-after-records-loss`。
- `pool/publish_lock.py`：`_atomic_write_inner()` 新增 `verify` 与 `pre_rename_hook` 参数；rename 后校验失败从写前快照恢复旧字节与 sidecar。
- `pool/publish.py`：写前 tmp 实际字节校验（SHA + allowlist），`publish_postwrite_verify_failed`；写后重读再验；结果新增 `postwrite_verified`、`published_manifest_after`。
- `pool/sync.py`：served 实际字节复核（`gate_lines` + 版本链），`sync_served_gate_failed` + 降级；成功含 `served_verified=true`。
- `systemd/gate-publish.sh`：组装后写周期绑定记录 `cycle-<ts>-<pid>.json`（`new_source_gated=false` 等）。
- `systemd/gate-sync.sh`：复制前 served SHA 核对（`served_sha_mismatch_before_bridge_copy` 拒绝）。

### 测试与演练
- `tests/test_d5_d3.py`（新建，14 项）、`tests/test_d5_cycle.py`（新建，8 项）。
- `drills/crash_window_drill.py`（新建）、`drills/run_nonroot_tests.sh`（新建）、`drills/cross_cycle_drill.py`（新建）、`drills/cross_cycle_redgreen.py`（新建）、`drills/backup_restore_drill.py`（新建）、`drills/snapshot_backup_d5.py`（新建）。

### 文档与日志
- `docs/recovery-runbook.md`（新增 §0b）、`docs/cross-cycle-flow.md`（新建）、`docs/backup-restore-drill.md`（新建）、`docs/direct-test-onepager.md`（新建）、`docs/D5_REPORT.md`（本文件）。
- 日志：`docs/nonroot-test-log.json`、`docs/nonroot-test-log-vps.json`、`docs/crash-window-drill-log.json`、`docs/crash-window-drill-log-vps.json`、`docs/cross-cycle-drill-log.json`、`docs/cross-cycle-drill-log-vps.json`、`docs/cross-cycle-redgreen-log.json`、`docs/cross-cycle-redgreen-log-vps.json`、`docs/backup-restore-drill-log.json`、`docs/backup-restore-drill-log-vps.json`。
- GPT 复核原文：`gpt-d3-review-6886420557.md`、`gpt-d4-review-6887331723.md`（公开评论原文存档）。

### 环境备注
- 本地与 VPS 各建无 sudo 的 `d5test` 用户（uid 1000）；本地 `/home/hatch` 与 `/home/hatch/workspace`、VPS `/opt` 加 o+x（仅目录穿越位）。
- VPS 上三脚本经 `cat >` 传输后丢 +x 位（`run_nonroot_tests.sh`、`gate-publish.sh`、`gate-sync.sh`），协调员已补 `chmod +x` 并核对（本地与 VPS 的 gate 脚本均为可执行）。
- 演练工作区 `drills/_d5_work/`（本地与 VPS 各一份合成树）不进入上传包。

---

## 10. 上传清单

上传包 `~/workspace/p2p3-d5-upload/` = D5 树完整脱敏副本（除 `__pycache__` 与 `drills/_d5_work/`），拟上 PR #77 新目录 `docs/surge-d5-review/`。脱敏 grep 全树干净（无真实节点 URI、订阅 URL、密码、私钥、原始 IP、令牌；仅合成标记 192.0.2.x / 198.51.100.0/24 与 `TEST-ONLY-NOT-A-REAL-NODE`；`password=` 命中全是代码模板与 `<redacted>` 字面量）。

**未闭合、需机主执行的操作（仅两项）**：
1. 新原生整组复测（切换前与切换后各一次；先刷新订阅 → 跑全组测速等全部出结果 → 截图发来，带状态栏时间）。
2. DIRECT 手机测试（按 `docs/direct-test-onepager.md` 三场景，机主定时间）。

— Muse
