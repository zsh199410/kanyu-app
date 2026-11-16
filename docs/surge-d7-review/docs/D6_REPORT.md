# D6 报告 — GPT D5 复核三项新增风险的最小修复

- 日期：2026-11-16（CST）
- 范围：隔离环境。本地 `~/workspace/p2p3-d6/` 与 VPS `/opt/p2p3-d6/`（D5 树完整复制 + 本次改动；D5 树仅作红对照只读引用，未改动）。
- 合成固件：TEST-NET 192.0.2.0/24 与 198.51.100.0/24、假密码 `TEST-ONLY-NOT-A-REAL-NODE`。无真实节点 URI、订阅 URL、密码、私钥、原始 IP、令牌。
- 生产状态：**生产订阅、生产定时器、手机配置一律未动**。PR #77 仍为 Draft，不合并。无手机原生测试在本轮执行。

本报告逐项回应 GPT D5 复核评论 6897615694（2026-11-16 00:27 CST）的 3 项新增风险。流向证明见 `docs/d6-flow.md`。

---

## 0. 总览

| GPT 要求 | 落地 | 证据 |
|---|---|---|
| ① served 污染后 bridge/HTTP 入口字节不变、污染版不可读；STOP 后隔离/恢复策略 + SHA 证据；served 若可被 HTTP 直读须在切换前阻断 | `pool/sync.py` 加 `_quarantine_and_restore_served()`（隔离 + 恢复）与 symlink 守卫；`systemd/gate-sync.sh` 加 served 暴露守卫；切换手册新增 Phase 0 检查项 | 演练 `drills/d6_item1_served_quarantine.py` 15/15，双环境；红→绿 10/10 |
| ② gate-sync.sh 检查→复制竞争窗口；legacy $OLD 写失败不假成功；桥接校验+复制+最终 SHA 校验进同一锁与同一不可变快照；双目标一致性/回滚 | 新建 `pool/bridge_sync.py`（同一 flock 内重验 + 内存快照 + 双目标写 + 写后重验）；`gate-sync.sh` 重写为调 `bridge_sync` | 演练 `drills/d6_item2_bridge_race.py` 15/15，双环境；红→绿 10/10 |
| ③ gate-publish.sh 退出码语义：区分“本轮已验证发布成功”与“下一轮源组装失败”；timer/监控告警；下一轮不误判 | `gate-publish.sh` 退出码 0/1/2 + 每周期原子写 `$GATE/logs/health.json`；切换手册新增监控接线 | 演练 `drills/d6_item3_publish_exit.py` 五周期序列 17/17，双环境；红→绿 10/10 |
| D5 基线不弄红 | 115 项 → 131 项（+16 项 D6 测试）；跨周期、崩溃窗口、备份恢复、D5 红→绿全部复跑 | 见 §4 |

全套测试（见 §4）本地与 VPS 均为 **131 项**：root 下 OK（跳过 7 项，均为 root 无法真正执行 chmod-000 的用例）；非 root（d5test，uid 1000）下 **131/131 通过、0 跳过**。

固定 SHA（fixture 行固定，各处一致）：v1 source `f6083ad90eac`（44 行）、v2 source `314c25b75017`（43 行，未测）、clean14 `6074082847c3`（14 行）、污染版 `7737d85e5d1e`（15 行）。

---

## 1. 第 1 项：served 污染后隔离 / 恢复

### 代码改动（`pool/sync.py`）

- 新增 `_quarantine_and_restore_served(workdir, chain, admitted, now)`——锁内、永不抛错：
  1. 把当前 served 文件移入 `served/.quarantine/pool-new-<ts>-<sha12>.txt`（600，sidecar 一并移走），典型 served 路径不再暴露污染字节；
  2. 从链已验证的 publish 文件恢复 served（SHA 须等于链 `published_sha` 且行全过 allowlist；tmp+rename+fsync，重读复验，sidecar 一并复制）；
  3. 恢复验不过则 served 路径留空（绝不留未验证字节）、`restored=False`。
- 在 `sync_served_gate_failed` 与 `sync_verify_failed` 两个分支都先隔离/恢复、再进 degraded（STOP），使状态文件记的是恢复后版本而非污染版；结果字典新增 `served_quarantine` / `served_restored` / `served_restored_manifest`。
- 另加符号链接守卫：served 目录或 served 文件是 symlink、或 realpath 不在 served 目录内 → 拒绝 `served_symlink_refused`（锁内、读 served 字节之前）。
- 模块 docstring 已补 D6 说明；D5 的 E3 旧句（“served 保留被污染的 15 行”）在 `docs/cross-cycle-flow.md` §5 标注作废。

### served 暴露路径的阻断（代码 + 接线，不只文字）

- `systemd/gate-sync.sh` 在同步前做 served 暴露守卫（python realpath 比对：served 解析后必须不在 `BRIDGE_DIR` 内，否则拒绝，日志 `served_path_exposure_check`）；`tests/test_d6.py` 有对应拒绝测试（served 在 bridge 目录内 → rc=1）。
- `systemd/switch-runbook.md` §11 新增切换前检查项：核对 nginx/静态托管只映射 bridge 目录，served 目录不在任何 HTTP alias/根路径下。代码守卫防的是“served 被配进 bridge 目录”的误配；“served 目录本身被 HTTP 直读”须在部署时按手册核对。

### 实测数字（协调员亲自复跑，非转述）

- `tests/test_d6.py` 第 1 组 3 项：篡改后隔离+恢复+仍 STOP；served symlink 拒绝；恢复失败时 served 留空。本地与 VPS 全套 131 项内通过。
- 演练 `drills/d6_item1_served_quarantine.py`：本地 15/15，VPS 15/15（`docs/d6-item1-drill-log.json` / `docs/d6-item1-drill-log-vps.json`）。
- 红→绿 `drills/d6_redgreen.py` R1：D5 树 rc=1 但 served 保持污染 `7737d85e5d1e`（15 行）、隔离区空；D6 树 rc=1、served 恢复 `6074082847c3`、隔离区 1 个文件且 SHA 为污染版、degraded=True。

### 诚实边界（实测行为与预期不符处，如实记录，未改代码迎合断言）

- **cycle 间篡改被下一次 sync 覆盖、rc=0 是正确的**：served 路径在每次 sync 都由已验证 publish 文件重写，cycle 间落入的篡改会被覆盖。危险窗口是“sync 周期内”与“post-copy 瞬间”——前者由 sync 间隔界定，后者由本项的隔离/恢复闭合。演练 B 步如实记录了这一行为，未把它写成失败。
- **served 若可被 HTTP 直接读取，cycle 间窗口仍会暴露污染字节。** 阻断靠 §1 的守卫 + 手册检查项，不是靠隔离/恢复本身；隔离/恢复只保证“STOP 之后 served 路径不再暴露污染字节”。
- 隔离区文件只保留污染字节与 sidecar，不自动删除、不自动恢复；恢复走已验证 publish 文件，不走隔离区。

---

## 2. 第 2 项：gate-sync.sh 竞争窗口与 legacy 假成功

### 代码改动

- 新建 `pool/bridge_sync.py`（约 17KB）：`run_bridge_sync(workdir, bridge_dir, old_path, native_record_path, probe_db, lock_timeout, now, pre_bridge_rename_hook)`——同一共享 flock 内：重验 served 实际字节（版本链 + allowlist；失败则隔离/恢复 + 进 degraded，错误码 `bridge_served_chain_*` / `bridge_served_gate_failed`）；读一次 served 字节进内存作不可变快照（后续 bridge 与 legacy 都写这份内存字节，不再重读 served）；bridge 写（tmp+rename+fsync，重读验 SHA；rename 后不符则从内存里的旧 bridge 字节恢复并报 `bridge_sha_mismatch`）；legacy 同法，失败则 bridge 回滚到写前字节并报 `legacy_copy_failed`（`bridge_rolled_back=true`），绝不 rc=0；写后锁内再重读 served，若变了则隔离/恢复 + 进 degraded，报 `served_changed_after_bridge_copy`（bridge 已是验证字节，记 `bridge_updated_verified=true`，run 仍 rc=1）。hook 异常兜住；legacy 父目录缺失时不自动建目录（必须失败，故障注入才有效）。
- `systemd/gate-sync.sh` 重写：加 served 暴露守卫；保留 `pool.sync` 调用与 D5 桥前 SHA 核对（作 tripwire，D5 测试 `test_gate_sync_prebridge_mismatch_refuses` 仍通过）；shell 复制块改为调用 `python3 -m pool.bridge_sync`，按其 rc 退出。
- 双目标一致性定义：bridge 与 legacy 要么同为同一快照字节（SHA 一致），要么 run 失败且 bridge 回滚到写前字节；不存在“bridge 已更新、legacy 静默失败、run 宣称成功”的状态。

### 实测数字（协调员亲自复跑，非转述）

- `tests/test_d6.py` 第 2 组 5 项：bridge_sync 成功；桥前 served 被改；rename 前 served 被重写（hook 注入）；legacy 失败回滚 bridge；bridge served symlink 拒绝。本地与 VPS 全套 131 项内通过。
- 演练 `drills/d6_item2_bridge_race.py`：本地 15/15，VPS 15/15（`docs/d6-item2-drill-log.json` / `docs/d6-item2-drill-log-vps.json`）。两项注入均有 SHA 证据：race 注入后 bridge 仍为 `6074082847c3`、rc=1 `served_changed_after_bridge_copy`、served 已恢复；legacy 注入后 rc=1 `legacy_copy_failed`、bridge 回滚为 `6074082847c3`、legacy 未写入、`gate-sync.log` 里 `synced served_sha` 行仍只有 1 条（仅第一次成功运行）。
- 红→绿 `drills/d6_redgreen.py` R2a/R2b：D5 树 legacy 失败 rc=0 + `old_copy_failed`（红）；D5 树无 `pool.bridge_sync` 模块（红，ImportError）；D6 树 legacy 失败 rc=1 + bridge 回滚（绿）、race 注入 bridge 仍 clean + rc=1（绿）。

### 诚实边界

- race 注入是确定性的 hook（快照后、rename 前）；真实并发写手的时间窗口无法在隔离环境逐毫秒复现，hook 证明的是“即使窗口被命中，bridge 也只收快照字节”。
- legacy 父目录缺失时不自动建目录；部署时 legacy 路径须由人工/安装步骤预建目录，见 `systemd/switch-runbook.md` §11。

---

## 3. 第 3 项：gate-publish.sh 退出码语义

### 代码改动（`systemd/gate-publish.sh` 重写）

- 退出码 0＝门禁通过且组装成功（healthy）；1＝门禁拒绝或预检失败（`gate_refused` / `precheck_failed`，门禁拒绝占优）；2＝门禁通过但组装失败（`published_assembly_failed`）。
- 每周期原子写 `$GATE/logs/health.json`（health、gate_rc、assembly_rc、各 SHA 前缀、`new_source_gated=false`、`assembly_failed`、`src_changed`；预检失败时 gate_rc/assembly_rc=-1）。
- **health 文件名原定 `cycle-health.json`，因与 `cycle-*.json` 周期记录收集规则冲突（测试里 `_cycle_records` 会多收一条），已改名 `health.json`**，`gate-publish.sh`、`tests/test_d5_cycle.py`、`drills/cross_cycle_drill.py` 三处已同步改名。
- timer/监控告警（接线层面，见 `systemd/switch-runbook.md` §11）：监控脚本每周期读 health.json，`health != healthy` 即告警；退出码 2 不触发 timer 失败重试（组装失败重试无意义，须人工修组装器），但须进告警通道；exit=0 不得再被解释为整个周期全部成功。

### 有意的行为变更（测试断言更新，须明说）

- `tests/test_d5_cycle.py`：`test_gate_publish_cycle_record_on_assembly_failure` 的 rc 断言 0→2，补 health.json 断言；`test_gate_publish_writes_cycle_binding_record` 补 healthy 断言。
- `drills/cross_cycle_drill.py`：D2 检查 `d2_publish_revalidates_v1_rc0` 改为 `d2_publish_revalidates_v1_exit2`（rc==2）+ health 断言；E3 步骤补断言（served 恢复为 clean、隔离区 1 个 .txt 且 SHA 为污染版、restored=True）；新增 `_health()` helper。D2 检查改名时曾写错变量名（`_health(ctx)`，`ctx` 未定义），已修为无参 `_health()`。

### 实测数字（协调员亲自复跑，非转述）

- `tests/test_d6.py` 第 3 组 8 项：wrapper 桥同步正常；legacy 失败 rc=1 且 bridge 回滚；served 在 bridge 目录内拒绝；publish 健康 exit 0；组装失败 exit 2；下一周期对撕裂源拒绝 exit 1 且 served/bridge 不变；原子崩溃后下一周期重验 v1 exit 0；门禁拒绝+组装失败 exit 1。本地与 VPS 全套 131 项内通过。
- 演练 `drills/d6_item3_publish_exit.py` 五周期序列：本地 17/17，VPS 17/17（`docs/d6-item3-drill-log.json` / `docs/d6-item3-drill-log-vps.json`）。序列：C1 健康 exit 0 → C2 撕裂组装 exit 2 `published_assembly_failed` → C3 下一周期对撕裂源门禁拒绝 exit 1 `gate_refused`、served/bridge 不变 → C4 原子崩溃 exit 2、$SRC 仍 v1 → C5 重验 v1 exit 0 健康。
- 红→绿 `drills/d6_redgreen.py` R3：D5 树撕裂组装 exit 0、无 health 文件（红）；D6 树 exit 2、health=`published_assembly_failed`、publish SHA 保持 `6074082847c3`（绿）。

---

## 4. D5 基线回归（未弄红）

| 套件 / 演练 | 本地（Python 3.12.3） | VPS（Python 3.13.5） |
|---|---|---|
| 全套 unittest（131 项，D1 24＋D2 39＋D3 23＋D4 7＋D5-D3 14＋D5-cycle 8＋D6 16）root | OK，跳过 7（均为 root 下 chmod-000 用例） | OK，跳过 7 |
| 全套 unittest 非 root（d5test，uid 1000） | **131/131，0 跳过**（`docs/nonroot-test-log.json`） | **131/131，0 跳过**（`docs/nonroot-test-log-vps.json`） |
| 跨周期演练 `drills/cross_cycle_drill.py` | **32/32**（D5 的 30 项 + D6 新增 2 项断言） | **32/32** |
| 崩溃窗口演练 `drills/crash_window_drill.py` N=20 | all_pass，撕裂 0 | all_pass，撕裂 0 |
| 备份恢复演练 `drills/backup_restore_drill.py` | 13/13 + 1 信息项（与 D5 一致） | 13/13 + 1 信息项 |
| D5 红→绿 `drills/cross_cycle_redgreen.py` | 13/13 | 13/13 |
| D6 三项演练 | 15/15、15/15、17/17 | 15/15、15/15、17/17 |
| D6 红→绿 `drills/d6_redgreen.py` | 10/10 | 10/10 |

### 基线时间炸弹（D6 开工时发现，已修，属基线修复非行为改动）

- D6 开工跑 D5 基线时，全套 115 项有 **2 项失败**，不是代码回归，是 fixture 时间炸弹：fixture `native_results_fixture.json` 的 `tested_at=1794684993`，2026-11-16 08:3x 时已老化 104,151 秒（>24h TTL 86,400，超约 4.9 小时），两个走墙钟 `now` 的子进程测试（`test_d1` sim_timers、`test_d2` 并发 publish/sync）被门禁以 `phone_gate_zero_qualified` 拒绝。
- 已修（D6 树内）：测试时把 `tested_at` 刷新为 wall-now − 3600（与 `test_d5_cycle.py` 已有模式一致）；`test_d2` 的后续 in-process `run_sync` 也改用 wall-now（否则 fresh 证据相对 fixture 时钟是「未来」而报 `native_ts_invalid`）；`cross_cycle_drill.py` 的 E 节（in-process + 墙钟 now）同样修了。修完后本地全套 115 项 OK（跳过 7）。
- 影响：D5 树的 fixture 在 2026-11-16 08:3x 后同样会炸（同一 fixture）；D5 的数字是 2026-11-15 当时跑的，不受影响。本修只动测试/演练的时钟，不动门禁逻辑与 TTL。

### 崩溃窗口 phase B 分项差异（实测，非问题）

- N=20 的 phase B（kill 后 STOP 是否存活）分项：本地 stop_survived 4 / completed_ok_overwrites 6；VPS stop_survived 7 / completed_ok_overwrites 3。不变量是 `all_pass=true` 与 `served_sha_unchanged_all=true`。分项差异是 kill 时序（kill_delay_s 0.333 的命中点）所致，不是代码差异。

---

## 5. 红→绿对照摘要（实测，非结论复述）

| 对照 | 旧代码（D5 树，只读引用） | 新代码（D6） |
|---|---|---|
| served post-copy 篡改 | rc=1 `sync_served_gate_failed`，但 served 保持污染 `7737d85e5d1e`（15 行），隔离区空——“最终服务字节已安全”不成立 | rc=1 同错误码，served 恢复 `6074082847c3`（14 行），隔离区 1 个文件且 SHA 为污染版，degraded=True |
| bridge race（快照后改 served） | 无 `pool.bridge_sync` 模块（ImportError）；桥复制是锁外 shell cp，窗口无防护 | hook 注入后 bridge 仍为 `6074082847c3`（只收快照字节），rc=1 `served_changed_after_bridge_copy`，served 已恢复 |
| legacy $OLD 写失败 | rc=0 + 日志 `old_copy_failed`——假成功 | rc=1 `legacy_copy_failed`，bridge 回滚到写前字节（`6074082847c3`），legacy 未写入 |
| 撕裂组装退出码 | gate=0 + assembly=1 仍 exit 0，无 health 文件——组装失败与健康周期无法区分 | exit 2，health=`published_assembly_failed`，publish SHA 保持 `6074082847c3` |

---

## 6. 改动文件清单

| 文件 | 改动 |
|---|---|
| `pool/sync.py` | 新增 `_quarantine_and_restore_served()`、symlink 守卫、两分支先隔离/恢复再 degraded、结果字典三新字段、docstring 补 D6 说明 |
| `pool/bridge_sync.py` | 新建（约 17KB）：同一锁内重验 + 内存快照 + bridge/legacy 双目标写 + 写后重验 + 回滚 |
| `systemd/gate-sync.sh` | 重写：served 暴露守卫、保留 sync 调用与 D5 桥前 SHA 核对、shell 复制块改为调 `pool.bridge_sync` |
| `systemd/gate-publish.sh` | 重写：退出码 0/1/2、每周期原子写 `health.json` |
| `systemd/switch-runbook.md` | 新增 §11（D6 补充）：served 暴露切换前检查、STOP 后隔离/恢复策略、双目标一致性/回滚、退出码 + health 监控 |
| `docs/recovery-runbook.md` | 新增 §S4（served 篡改场景） |
| `docs/cross-cycle-flow.md` | 新增 §5（D6 指针注记：E3 不再保留脏字节） |
| `docs/d6-flow.md` | 新建：三项流向证明 |
| `tests/test_d6.py` | 新建，16 项（第 1 组 3 项、第 2 组 5 项、第 3 组 8 项） |
| `tests/test_d1.py`、`tests/test_d2.py`、`tests/test_d5_cycle.py` | 基线时间炸弹修复（tested_at 刷新为 wall-now − 3600）+ D6 断言更新（rc 0→2、health.json） |
| `drills/cross_cycle_drill.py` | E 节时钟修复 + D2/E3 的 D6 断言更新 + `_health()` helper |
| `drills/d6_item1_served_quarantine.py` | 新建演练（15 项检查） |
| `drills/d6_item2_bridge_race.py` | 新建演练（15 项检查） |
| `drills/d6_item3_publish_exit.py` | 新建演练（17 项检查） |
| `drills/d6_redgreen.py` | 新建红→绿对照（10 项检查，D5 树只读引用） |
| `drills/run_nonroot_tests.sh` | 改为跑全套 discover（131 项），原只跑 37 项专项 |
| `drills/run_vps_all.sh` | 新建：VPS 一键全量复跑脚本 |
| `gpt-d5-review-6887615694.md` | 新建：GPT D5 复核原文存档（2,659 字节） |

---

## 7. 未做 / 残余风险

- 演练全部是合成固件与桩组装器：不证明真实手机测过任何版本，不证明生产 :07/:15 周期的表现。真实切换仍须按 D4/D6 手册走，须新鲜原生整组复测 + GPT 批准 + 机主授权。
- 备份仍未真实 stop→restore→start（桌面演练 13/13 + 1 信息项，与 D5 一致）；21 pinned 的统一门禁、定时器实际接线、DIRECT 三场景及同 SHA Surge 手机原生整组 <300ms 尚无生产闭环；生产现有 65 行与 dry-run 拒绝的差距须在切换窗口前解决。
- served 暴露：代码守卫 + 手册检查项防的是误配与部署时核对；若生产 nginx 配置本身把 served 目录映射为 HTTP 路径，须在切换前按手册改掉——演练不覆盖真实 nginx 配置。
- 隔离区（`served/.quarantine/`）会随篡改次数增长，不自动清理；运维须定期人工清理并记入操作记录。
- `health.json` 是监控信号，不是门禁状态：门禁仍以 `recovery-state.json` / `recovery-anchor.json` 为准；health 文件丢失不影响门禁，只影响监控可见性。
- D5 的 115 项、跨周期 30/30、红→绿 13/13、备份 13/13 基线均已复跑通过（本轮为 131 项、32/32、13/13、13/13+1 信息项）；手机原生复测与 DIRECT 测试不在本轮职责内，未碰生产订阅、未动定时器、未改 pool-new.txt。
