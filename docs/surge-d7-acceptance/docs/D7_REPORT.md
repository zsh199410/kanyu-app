# D7 报告 — GPT D6 复核三项上线验收证据（最小范围，不扩展功能）

- 日期：2026-11-16（CST）
- 范围：隔离环境。本地 `~/workspace/p2p3-d7/` 与 VPS `/opt/p2p3-d7/`（D6 树完整复制 + 本次改动；D6 树仅作红对照只读引用，未改动）。
- 合成固件：TEST-NET 192.0.2.0/24 与 198.51.100.0/24、假密码 `TEST-ONLY-NOT-A-REAL-NODE`。无真实节点 URI、订阅 URL、密码、私钥、原始 IP、令牌。
- 生产状态：**生产订阅、生产定时器、手机配置一律未动**。PR #77 仍为 Draft，不合并。无手机原生测试在本轮执行。
- 本报告逐项回应 GPT D6 复核评论 6904538782（2026-11-16 09:09 CST）的 3 项要求。流向证明见 `docs/d7-flow.md`；逐项已验/未验见 `docs/D7_CHECKLIST.md`。

---

## 0. 总览

| GPT 要求 | 落地 | 证据 |
|---|---|---|
| ① HTTP 暴露面：served 与 `.quarantine` 不可从订阅入口直读；realpath 守卫只覆盖 served 在 bridge 内的误配；附 served/bridge/HTTP 实际响应 SHA 对照 | 真实 nginx 审计 + 8 条 live 探针（脱敏证据表）；沙箱演练 + 负对照（守卫盲区实证）；切换手册 §11.5.1 已写审计结论与切换窗口重跑要求 | 演练 `drills/d7_item1_http_exposure.py` 13/13，双环境（VPS 真实 nginx 引擎，本地 Python 仿真引擎） |
| ② 双目标回滚故障：legacy 已 rename 但写后 SHA 失败 / fsync 失败 / 两 rename 间进程崩溃；验证最终状态与下一轮修复；不称跨文件真正原子事务 | `pool/bridge_sync.py` 加 `verify_targets()` 只读检测（+ CLI）与三个 TEST-ONLY hook；D6 文档“ONE atomic unit”措辞更正为“连续两次原子 rename”；切换手册 §11.5.2 加核对命令 | 演练 `drills/d7_item2_legacy_postwrite.py` 15/15，双环境；单元测试 10 项；红→绿 4/4 |
| ③ 上线前置清单：逐项标已验/未验 | `docs/D7_CHECKLIST.md`：3 项本轮已验 + 7 项未验（待切换窗口 5 项、待机主 2 项），生产现状以 2026-11-16 16:37 只读核实为准 | 清单本文；周期演练 21/21、stop→restore→start 演练 12/12（程序层） |
| 补充（机主 16:34 催上线）：冻结干净订阅 + 手机复测就绪并行做 | `staging/` 三件：冻结版干净订阅（clean14，SHA `6074082847c3`，内容不动）+ manifest + 手机复测精确步骤 | 见 §4；staging 未接入任何生产路径 |

全套测试（见 §5）本地与 VPS 均为 **141 项**：root 下 OK（跳过 7 项，均为 root 下 chmod-000 用例）；非 root（d5test，uid 1000）下 **141/141 通过、0 跳过**。

固定 SHA（fixture 行固定，各处一致）：v1 source `f6083ad90eac`（44 行）、v2 source `314c25b75017`（43 行，未测）、clean14 `6074082847c3`（14 行）、污染版 `7737d85e5d1e`（15 行）。

---

## 1. 第 1 项：HTTP 暴露面

### 真实审计（2026-11-16 16:37，只读；结论：通过）

- live `.conf` 4 个（`nginx.conf` 只 `include conf.d/*.conf`，`.bak*` 不加载）；server 块 3 个；**唯一静态映射是订阅入口 `location <STATIC_PREFIX>` → `alias <BRIDGE_DIR>`**；其余 location 全部是 `proxy_pass` 到本机端口；指向 served / publish 目录的 root/alias **0 个**；`autoindex` 开启 **0 处**；`nginx -t` 语法 OK；gate 状态目录 `/opt/pool-gate` **不存在**（切换前）。
- Live 探针 8 条（GET，只记状态码 + 响应 SHA 前缀 + 字节数，响应体哈希后丢弃）：入口 200，响应 SHA = 磁盘 bridge 文件 SHA = 生产发布文件 SHA（2026-11-16 16:07 版，29 行，SHA 前缀 `cdaa94605875`）；`..`、编码 `..`、`.quarantine` 猜测、越界到 publish 目录、编码 gate 路径、根路径 served 直读、`..;` 全部 400/404，无一返回订阅字节。证据表 `docs/d7-live-probes.json`（已脱敏：无主机名、无订阅 URL、无节点、无凭据、无随机路径 token）。

### 沙箱演练（`drills/d7_item1_http_exposure.py`，13/13 双环境）

- 同映射沙箱服务：入口 200 + SHA == clean14；6 条穿越路径全拒绝；`.quarantine` 猜测 404。
- 引擎：VPS 为**真实 nginx**（沙箱配置，两 server 块），本地为 Python `http.server` 仿真（同路由语义）；两引擎 verdict 一致。
- 负对照（**守卫盲区实证**）：独立 alias 指向 served 目录时，`gate-sync.sh` realpath 守卫返回 `ok`（盲区），探针却返回 200 且 SHA == served SHA。因此防暴露的控制是“切换前审计 + 探针”，不是守卫；切换窗口须重跑审计 + 探针。

### 诚实边界

- 审计与探针是 2026-11-16 16:37 的快照：nginx 配置或 bridge 目录结构若在切换窗口前变了，须重跑；`docs/D7_CHECKLIST.md` §2 已把重跑列为窗口动作。
- 探针只覆盖了 8 条路径模式（GPT 点名的 served / `.quarantine` 直读与穿越类）；未做全量模糊测试。live 审计（唯一静态映射）是覆盖性的，探针是抽查性的。
- served 路径本身尚未部署（`/opt/pool-gate` 不存在）：本次证明的是“当前映射下 served 路径无 HTTP 入口 + 未来路径不在任何映射下”；部署后须按手册 §11.5.1 再核一次。

## 2. 第 2 项：双目标回滚故障注入

### 代码改动（`pool/bridge_sync.py`，最小）

- 新增 `verify_targets(workdir, bridge_dir, old_path=None)`——只读：served / bridge / legacy 三者 SHA 对链 `published_sha`；consistent 当且仅当三者全等；分歧 detail 为 `served_sha_mismatch` / `bridge_sha_mismatch` / `legacy_sha_mismatch`。CLI：`python3 -m pool.bridge_sync --verify-targets ...`（rc 0=一致，1=分歧），供切换窗口人工核对（手册 §11.5.2）。
- 新增三个 TEST-ONLY hook（生产调用一律传 None）：`bridge_post_rename_hook` / `legacy_post_rename_hook`（rename 后、写后 SHA 校验前调用，可破坏刚 rename 的文件以证明校验能抓住）；`post_bridge_hook`（bridge rename 校验通过后、legacy 写之前调用；抛错即向外传播，模拟两 rename 间进程崩溃——`finally` 释放 flock，真实 SIGKILL 时由内核释放 flock，下一轮仍可获取锁）。
- **措辞更正**：D6 文档“Bridge and legacy are updated as ONE atomic unit”作废，改为“连续两次原子 rename，不是跨两个文件的真正原子事务”（GPT D6 原话）。成功路径语义未变。

### 实测数字（协调员亲自复跑，非转述）

- 演练 `drills/d7_item2_legacy_postwrite.py`：本地 15/15，VPS 15/15（`docs/d7-item2-drill-log.json` / `docs/d7-item2-drill-log-vps.json`）。
  - A legacy 写后 SHA 失败：rc=1 `legacy_copy_failed`，bridge 回滚到写前字节，legacy 持污染字节（SHA `7737d85e5d1e`，可检测），`verify_targets` rc=1；下一轮 rc=0，两目标 clean14，`verify_targets` consistent。
  - B bridge 写后 SHA 失败：rc=1 `bridge_sha_mismatch`，bridge 恢复写前字节，legacy 未动；下一轮 rc=0。
  - C 两 rename 间崩溃（子进程）：子进程 rc!=0；bridge=新快照 clean14，legacy=写前旧版；`verify_targets` rc=1 `legacy_sha_mismatch`；下一轮 rc=0，锁未堵。
  - D legacy 写 fsync 失败（mock `os.fsync`）：单元测试复跑通过，rc=1 `legacy_copy_failed`，bridge 回滚；下一轮 rc=0。
- `tests/test_d7.py` 10 项：上述四注入的 in-process 版 + `verify_targets` 四态 + 守卫边界两项。本地与 VPS 全套 141 项内通过。
- 红→绿 `drills/d7_redgreen.py` 4/4：D6 树 `verify_targets` ImportError（红）；D7 树 15/15（绿）。

### 诚实边界

- C 的“崩溃”是 hook 抛错（异常向上传播），不是真实 SIGKILL：区别仅在于 `finally: lock.release()` 是否执行；flock 在两种情况下都会释放（进程内 finally / 内核在进程死后释放），下一轮能获取锁已由演练证明（C 下一轮 rc=0）。真实 SIGKILL 的磁盘状态与 hook 抛错一致（bridge 已 rename、legacy 未写）。
- fsync 注入是 mock（按调用序第 4 次 `os.fsync` 抛错），不是真实磁盘故障；证明的是代码路径（失败 → 回滚 + rc=1），不是硬件行为。
- `verify_targets()` 是只读检测，不自动修复：修复靠下一轮同步从已验证快照重写（演练 A/C 已证明）。

## 3. 第 3 项：上线前置清单

全文见 `docs/D7_CHECKLIST.md`。状态总表：

| # | 项 | 状态 |
|---|---|---|
| 1 | HTTP 暴露面 | 已验（本轮） |
| 2 | 双目标回滚故障注入 | 已验（本轮） |
| 3 | 本清单 | 已验（本文档） |
| 4 | 生产 vs dry-run 差距（生产 29 行，16:07，SHA `cdaa94605875`；GPT 评论“60 行”已过时） | 未验—待切换窗口 |
| 5 | 21 pinned 全部取消豁免 | 未验—待切换窗口 |
| 6 | 旧写手 / 定时器退场（旧 timer 16:37 确认在跑；门禁单元 `systemd-analyze verify` 0 语法错误，仅 2 条预期报错——ExecStart 路径尚未部署） | 未验—待切换窗口 |
| 7 | 真实 stop→restore→start（程序 12/12 已验；生产执行未验） | 未验—待切换窗口 |
| 8 | :07/:15 连续周期与回滚 SHA（程序 21/21 + 跨周期 32/32 已验；生产周期表现未验） | 未验—待切换窗口 |
| 9 | 手机原生整组 <300ms（同 SHA 冻结版） | 未验—待机主 |
| 10 | DIRECT 三场景 | 未验—待机主 |

09:05 轮（46 行见 18 过 28 失败、14 行未拍）与 11:24 轮（新版后半段 16 行 3 过 13 失败、前半段 14 行未拍）**绝不当成全组验收**（清单 §2 第 9 行已钉死）。

## 4. 冻结干净订阅 + 手机复测就绪（补充优先级）

- `staging/frozen-clean14-subscription.txt`：14 行，SHA `6074082847c3…`，与 D0/D5/D6 演练用的 clean14 **字节一致、内容不动**；`staging/frozen-clean14-manifest.json`：冻结时间、来源、SHA、状态 `frozen-staging, NOT published`、`wired_to_production: false`。
- `staging/phone-retest-steps.md` §1–§5：冻结 → 同 SHA 原生整组 → DIRECT 三场景 → 回滚 → 切换完成确认。GPT 一批 D7 即可按此跑，不用再等一轮准备。
- 诚实边界：staging 文件是**合成固件**（TEST-NET，假密码），只证明冻结程序与清单格式；真实切换时按同样程序冻结**真实** 14 行并以真实 SHA 为准。三份 DIRECT 测试订阅（全失败 3 条 / 空组 0 行 / 单节点 1 条）须在切换窗口从当时的 served 版本现备，本轮未备。

## 5. 回归（D6 基线未弄红）

| 套件 / 演练 | 本地（Python 3.12.3） | VPS（Python 3.13.5） |
|---|---|---|
| 全套 unittest（141 项，D1 24＋D2 39＋D3 23＋D4 7＋D5-D3 14＋D5-cycle 8＋D6 16＋D7 10）root | OK，跳过 7（均为 root 下 chmod-000 用例） | OK，跳过 7 |
| 全套 unittest 非 root（d5test，uid 1000） | **141/141，0 跳过**（`docs/nonroot-test-log.json`） | **141/141，0 跳过**（`docs/nonroot-test-log-vps.json`） |
| 跨周期演练 `drills/cross_cycle_drill.py` | **32/32** | **32/32** |
| 崩溃窗口演练 `drills/crash_window_drill.py` N=20 | all_pass，撕裂 0（phase B stop_survived 7） | all_pass，撕裂 0（phase B stop_survived 4） |
| 备份恢复演练 `drills/backup_restore_drill.py` | 13/13 + 1 信息项 | 13/13 + 1 信息项 |
| D5 红→绿 `drills/cross_cycle_redgreen.py` | 13/13 | 13/13 |
| D6 三项演练 | 15/15、15/15、17/17 | 15/15、15/15、17/17 |
| D6 红→绿 `drills/d6_redgreen.py` | 10/10 | 10/10 |
| D7 四项演练 | 13/13、15/15、21/21、12/12 | 13/13、15/15、21/21、12/12 |
| D7 红→绿 `drills/d7_redgreen.py` | 4/4 | 4/4 |

### 崩溃窗口 phase B 分项差异（实测，非问题）

- N=20 的 phase B（kill 后 STOP 是否存活）分项：本地 stop_survived 7 / VPS 4（D6：本地 4 / VPS 7）。不变量是 `all_pass=true` 与 `served_sha_unchanged_all=true`。分项差异是 kill 时序所致，不是代码差异。

## 6. 红→绿对照摘要（实测，非结论复述）

| 对照 | 旧代码（D6 树，只读引用） | 新代码（D7） |
|---|---|---|
| legacy 写后 SHA 失败 | 无 hook 可注入；`_write_bytes_verified` 的写后校验存在但未被演练证明 | hook 破坏刚 rename 的 legacy → rc=1 `legacy_copy_failed`，bridge 回滚，下一轮修复 |
| bridge 写后 SHA 失败 | 同上（未被演练证明） | hook 破坏刚 rename 的 bridge → rc=1 `bridge_sha_mismatch`，bridge 恢复 |
| 两 rename 间崩溃 | 无 hook、无检测工具；最终状态（bridge 新 / legacy 旧）不可一键核对 | hook 模拟崩溃 → `verify_targets` 检出 `legacy_sha_mismatch`，下一轮修复 |
| `verify_targets` | 无此函数（ImportError） | 只读检测 + CLI，`--verify-targets` rc 0/1 |
| “ONE atomic unit”措辞 | D6 文档称双目标为一个原子单元 | 更正为连续两次原子 rename，非真正跨文件原子事务 |

## 7. 改动文件清单

| 文件 | 改动 |
|---|---|
| `pool/bridge_sync.py` | D7：`verify_targets()` + CLI `--verify-targets`；`_write_bytes_verified` 加 `post_rename_hook`；`run_bridge_sync` 加 `bridge_post_rename_hook` / `legacy_post_rename_hook` / `post_bridge_hook`；docstring 更正原子性措辞 |
| `systemd/switch-runbook.md` | 新增 §11.5：审计实测结论 + 探针要求、§11.5.2 `verify_targets` 核对命令、§11.5.3 冻结 staging 说明 |
| `tests/test_d7.py` | 新建，10 项（第 2 项 4 项、第 2 项检测 4 项、第 1 项守卫边界 2 项） |
| `drills/d7_item1_http_exposure.py` | 新建演练（13 项检查；VPS 真实 nginx 引擎，本地 Python 仿真引擎） |
| `drills/d7_item2_legacy_postwrite.py` | 新建演练（15 项检查；支持 `--code-root` 供红→绿） |
| `drills/d7_cycles_0715.py` | 新建演练（21 项检查；:07/:15 周期序列） |
| `drills/d7_stop_restore_start.py` | 新建演练（12 项检查；两轮 stop→restore→start） |
| `drills/d7_redgreen.py` | 新建红→绿对照（4 项检查） |
| `drills/run_vps_all.sh` / `drills/run_nonroot_tests.sh` | D7 路径 + 演练清单更新（141 项） |
| `staging/frozen-clean14-subscription.txt` | 新建：clean14 冻结版（字节一致，SHA `6074082847c3`） |
| `staging/frozen-clean14-manifest.json` | 新建：冻结清单 |
| `staging/phone-retest-steps.md` | 新建：切换窗口手机复测精确步骤 §1–§5 |
| `docs/D7_REPORT.md` / `docs/D7_CHECKLIST.md` / `docs/d7-flow.md` | 新建：本报告 / 前置清单 / 流向证明 |
| `docs/d7-live-probes.json` | 新建：live 审计 + 探针证据表（已脱敏） |
| `docs/d7-item1-drill-log.json` / `docs/d7-item2-drill-log.json` / `docs/d7-cycles-drill-log.json` / `docs/d7-stop-restore-log.json` / `docs/d7-redgreen-log.json`（+ `-vps.json` 各一） | 新建：D7 演练日志（本地 + VPS） |
| `docs/nonroot-test-log.json` / `docs/cross-cycle-drill-log.json` / `docs/crash-window-drill-log.json` / `docs/backup-restore-drill-log.json` / `docs/cross-cycle-redgreen-log.json` / `docs/d6-item*-drill-log.json` / `docs/d6-redgreen-log.json`（+ `-vps.json` 各一） | 本轮复跑更新 |
| `gpt-d6-review-6904538782.md` | 新建：GPT D6 复核原文存档 |

## 8. 未做 / 残余风险

- 演练全部是合成固件与桩组装器：不证明真实手机测过任何版本，不证明生产 :07/:15 周期的表现。真实切换仍须按手册走，须 GPT 批准 + 机主授权 + 新鲜原生全组测速。
- 清单 7 项未验（§3）：生产 vs dry-run 差距、21 pinned 豁免、旧定时器退场、真实 stop→restore→start、生产 :07/:15 周期表现、手机原生整组、DIRECT 三场景。任一未闭合即不切换。
- served 暴露：审计 + 探针是 2026-11-16 16:37 的快照；nginx 配置或 bridge 目录结构若变，切换窗口须重跑。隔离区（`served/.quarantine/`）不自动清理，须人工定期清理。
- `verify_targets()` 只检测、不自动修复；修复靠下一轮同步。`health.json` 是监控信号，不是门禁状态。
- D6 的 131 项、跨周期 32/32、红→绿 10/10、备份 13/13 基线均已复跑通过（本轮为 141 项、32/32、10/10、13/13+1 信息项）；手机原生复测与 DIRECT 测试不在本轮职责内，未碰生产订阅、未动定时器、未改 pool-new.txt。
