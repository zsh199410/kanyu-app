# D7a 上线验收单（Issue #73，GPT D7 裁决 6912114134）

- 日期：2026-11-16（CST）
- 范围：D7 清单 7 项未验的逐项闭合条件。状态口径与 D7 清单一致：
  **已验** = 隔离实测通过（本地 Python 3.12.3 + VPS Python 3.13.5，
  合成固件 TEST-NET）；**未验—待切换窗口** = 需在切换窗口对生产执行；
  **未验—待机主** = 需机主在手机上执行。隔离证据不等于生产或手机通过。
- 铁律：任一验收项失败，维持现网并 STOP（或保持未切换），不自动放宽、
  不降门禁、不改口径。生产订阅、生产定时器、手机配置、main 分支一律不动；
  PR #77 仍为 Draft。
- 真实冻结（本轮已做，只读）：源订阅 29 行，SHA `cdaa94605875`
  （2026-11-16 17:08 定时发布，与 16:07 版同 SHA）；候选 14 行，
  SHA `10e52c9643a8`；证据 fresh 2 / stale 12 / partial 0；
  钉选表 25 行，源文件内 21 行，候选 14 行**全部是钉选行**；
  状态 `needs_phone_retest`，`publishable: false`。冻结文件只在 VPS
  （`/opt/p2p3-d7a/freeze/frozen-real-14.txt`，600）；清单在 PR
  `docs/d7a-real-freeze-manifest.json`（只含 SHA、名字、ms、状态）。

## 1. 生产 vs dry-run 差距（未验—待切换窗口）

| 字段 | 内容 |
|---|---|
| 执行人 | 助手（窗口执行）+ GPT 批 |
| 现状 | 生产 29 行（SHA `cdaa94605875`）；dry-run 合成 v1 44 行 / clean14。dry-run 从未跑过生产字节 |
| 预期结果 | 切换窗口：冻结源版本并记 SHA（本轮已冻结：源 `cdaa94605875`，候选 `10e52c9643a8`）→ 同 SHA 原生整组复测（第 6 项）→ 门禁版发布**冻结版字节**（不是重新组装的版本）；发布后 bridge 文件 SHA == 冻结候选 SHA `10e52c9643a8`，served / legacy 三方一致（`--verify-targets` rc=0） |
| 失败回滚 | 任一 SHA 对不上（发布后 bridge != `10e52c9643a8`、三方不一致、门禁拒绝）→ 维持现网 29 行订阅并 STOP；按手册 §11.5.4 受控修复，不手工 cp、不重跑发布掩盖 |

## 2. 21 pinned 全部取消豁免（未验—待切换窗口）

| 字段 | 内容 |
|---|---|
| 执行人 | 助手（窗口执行）+ GPT 批 |
| 现状 | 代码已验（D4 钉选门禁 7/7，全套 161 项内）；生产发布仍走旧程序（`pinned_protected` 为死配置，钉选行无条件拼入）。本轮只读核查：钉选表 25 行；当前源文件 29 行中有 **21 行是钉选行**；冻结候选 14 行**全部是钉选行**（`pinned_in_candidates: 14`） |
| 预期结果 | 发布走 D3 门禁（不再拼入任何豁免行）；切换后原生整组复测证明钉选行同样受门禁约束（钉选行中无原生证据者不得出现在发布版中）；`--verify-targets` rc=0；冻结清单的 `publishable` 由 false 变 true 的唯一路径是：钉选豁免取消 + 同 SHA 全组原生证据 fresh |
| 失败回滚 | 任一钉选行未经门禁进入发布版 → 该版本作废，维持现网并 STOP；不“先发布再补证据” |

## 3. 旧定时器退场（未验—待切换窗口）

| 字段 | 内容 |
|---|---|
| 执行人 | 助手（窗口执行） |
| 现状（2026-11-16 17:25 只读核查） | 旧定时器在跑：`pool-publish.timer`（:07，下次 18:08:51，上次 17:08:26）、`pool-sync.timer`（:15，下次 17:30:00，上次 17:15:27）、`pool-crawl.timer`（上次 17:13:11）、`pool-test.timer`（上次 16:42:37）、`pool-test-full.timer`（上次 03:30:49）。门禁单元 `systemd-analyze verify` 见本轮 D7a 报告 §5（0 语法错误；仅预期报错——ExecStart 路径尚未部署） |
| 预期结果 | 按手册 §9：停旧 `pool-publish` / `pool-sync`（旧写手退场），启门禁 `pool-gate-publish.timer`（:07）/ `pool-gate-sync.timer`（:15）；交接后 `systemctl list-timers` 显示门禁 timer 在跑、旧 timer 不在跑；连续两个周期 `health.json` 为 healthy |
| 失败回滚 | 交接后任一周期 health != healthy，或旧 timer 仍在写生产订阅 → 立即按手册 §9 回滚（停门禁 timer、启旧 timer、恢复旧订阅文件），维持现网并 STOP；不双写手并行 |

## 4. 真实 stop→restore→start（程序已验 / 生产执行未验—待切换窗口）

| 字段 | 内容 |
|---|---|
| 执行人 | 助手（窗口执行） |
| 现状 | 程序：隔离演练 12/12（两轮，`drills/d7_stop_restore_start.py`，本轮复跑）+ 备份恢复 13/13+1 信息项（本轮复跑）。生产执行未做 |
| 预期结果 | 在切换窗口对真实生产目录做一次 stop→restore→start（按 `backup-drill/PROCEDURE.md` §3）：先完整备份并验证可恢复（manifest + SHA）→ STOP → 从备份恢复 → 服务重启后 `health.json` healthy、served/bridge SHA 回到备份前的值；全程记录时间戳与 SHA |
| 失败回滚 | 备份不可恢复、恢复后 SHA 对不上、服务起不来 → 停在恢复前状态，维持现网并 STOP；不带病切换 |

## 5. 生产 :07/:15 周期表现（程序已验 / 生产周期表现未验—待切换窗口）

| 字段 | 内容 |
|---|---|
| 执行人 | 助手（窗口执行后观察）+ GPT 批 |
| 现状 | 程序：周期演练 21/21（`drills/d7_cycles_0715.py`，本轮复跑）+ 跨周期 32/32（本轮复跑）+ D6 五周期序列 17/17（本轮复跑）+ **D7a 带 STOP 锁存的五周期序列 24/24**（`drills/d7a_cycles_latch.py`：健康 → 注入不一致 → gate-block 锁存 STOP → 下一 :07 拒绝、下一 :15 拒绝、served/bridge SHA 全程不变 → 受控修复 + HTTP 复核绿 → clear_stop → 下一周期 healthy）。生产：切换后未观察 |
| 预期结果 | 切换后连续两个 :07/:15 周期 `health.json` 均为 healthy；任一周期失败时 served/bridge SHA 回到上一好版本（回滚 SHA 有记录）；门禁拒绝时（无新鲜原生证据）周期健康地拒绝（`gate_refused`，served 不变），不算故障 |
| 失败回滚 | 连续两个周期任一失败且 SHA 未回到上一好版本 → 按手册 §9 回滚到切换前订阅 + 旧定时器，维持现网并 STOP |

## 6. 手机原生整组 <300ms（同 SHA 冻结版）（未验—待机主）

| 字段 | 内容 |
|---|---|
| 执行人 | 机主（手机）+ 助手（冻结与核对） |
| 现状 | 冻结候选 14 行 SHA `10e52c9643a8`；证据 fresh 2（美国13 264ms、美国12 265ms，P0 探针 2026-11-16 06:00 前后）、stale 12（09:05 轮在 60 行旧版本上通过，11:24 轮在 30 行旧版本上通过——**旧版本证据绝不当成通过**，已按 stale 如实标记）。09:05 轮（46 行见 18 过 28 失败、14 行未拍）与 11:24 轮（后半段 16 行 3 过 13 失败、前半段 14 行未拍）**绝不当成全组验收** |
| 预期结果 | 按 `staging/phone-retest-steps.md` §1–§2：刷新订阅到冻结版（SHA `10e52c9643a8`）→ 手机原生整组完整测速，**0 失败且 0 个 ≥300ms**，截图带状态栏时间；助手核对：实测版本 SHA == 冻结 SHA，HTTP 最终响应 SHA == 批准版本 SHA |
| 失败回滚 | 任一失败或 ≥300ms → 不切换，维持现网 29 行；冻结版作废，需重新冻结 + 重新整组复测；不“只换掉失败的几条就发布” |

## 7. DIRECT 三场景（未验—待机主）

| 字段 | 内容 |
|---|---|
| 执行人 | 机主（手机）+ 助手（备订阅） |
| 现状 | 方案就绪（`staging/phone-retest-steps.md` §3，D4 一页版）。三份测试订阅（全失败 3 条 / 空组 0 行 / 单节点 1 条）须在切换窗口从当时的 served 版本现备，未备 |
| 预期结果 | 三情形全部不落 DIRECT（不断连、不走直连出口），判定标准与记录格式按一页版；三份订阅在窗口现备并记 SHA |
| 失败回滚 | 任一情形落 DIRECT → 不切换，维持现网；查清是规则还是组配置问题后再议，不绕过 |

## 附：D7a 本轮已验（隔离证据，不等于生产/手机通过）

| # | 项 | 证据 |
|---|---|---|
| A1 | 双目标不一致纳入切换门禁（GPT 第 1 项） | `pool/bridge_sync.py` gate-block + repair_targets；演练 `drills/d7a_item1_gate_block.py` 23/23（双环境）；单元测试 20 项（全套 161 项内）；红→绿 6/6 |
| A2 | 部署后 HTTP 复核脚本（GPT 第 2 项） | `tools/http_recheck.py`；演练 `drills/d7a_item2_http_recheck.py` 11/11（双环境；VPS 真实 nginx + 真实 `nginx -T` 输出，本地 Python 仿真） |
| A3 | 冻结真实版本（GPT 第 3 项，只读） | `tools/freeze_real.py`；VPS 实跑：源 29 行 `cdaa94605875`，候选 14 行 `10e52c9643a8`，fresh 2 / stale 12 / partial 0，钉选 14/14，状态 `needs_phone_retest`，`publishable: false`；冻结文件只在 VPS（600） |
| A4 | 本验收单 + 带 STOP 锁存的跨周期序列（GPT 第 4 项） | 本文档；演练 `drills/d7a_cycles_latch.py` 24/24（双环境） |
