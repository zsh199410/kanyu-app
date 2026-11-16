# D4 报告：GPT D2 评审（6884522235）的四项“其次”

> 2026-11-15 08:00–08:20 CST 完成。隔离验证通过；**生产未动**
> （无定时器、无配置、无订阅改动；无 GitHub 操作）。
> 本报告不含订阅内容、节点行、密码、令牌、原始 IP；计数与 SHA 前缀见
> 各演练日志。快照本身含真实凭据，只存 VPS 600 权限文件，绝不下载。

## 0. 总览

| # | GPT 要求 | 状态 | 证据 |
|---|---|---|---|
| 1 | 真实 systemd :07/:15 接线 + 回滚方案 | 完成，隔离验证通过 | 单元 4 个 + 包装脚本 2 个 + 切换手册；开关演练 24/24（本地+VPS）；`systemd-analyze verify` 无语法错误 |
| 2 | 生产备份可恢复性演练 | 完成，通过 | 快照 20261115-080044（24 文件，带 manifest）；恢复演练 9/10（唯一未过项为旧备份无清单，属设计内信息项）；p1p3 旧备份可打开、可解析 |
| 3 | 21 钉选取消永久豁免的生产接线 | 完成，隔离验证通过 | 变更方案（CONFIG-DIFF.md）；7/7 钉选门禁测试（本地+VPS，全套 93/93） |
| 4 | 隔离 DIRECT 测试方案 | 完成（方案更新） | D4 版 direct-test-plan.md；未跑手机测试（须机主在手机上跑） |

## 1. systemd :07/:15 接线 + 回滚（`systemd/`）

**交付：**

- `systemd/pool-gate-publish.service` + `.timer`（`:07`，
  RandomizedDelaySec=120，Persistent=true）、
  `systemd/pool-gate-sync.service` + `.timer`（`:0/15:00`，
  Persistent=false）。均为 Type=oneshot，无 Restart。
- `systemd/gate-publish.sh`：**门禁先行**——先用 D3 publish 对当前
  源文件做门禁，通过后才跑生产组装（下一版本）；门禁拒绝即安全态，
  不组装。环境变量可覆盖全部路径（隔离演练用）。
- `systemd/gate-sync.sh`：D3 sync 通过（rc=0）后才复制 served →
  bridge modules + 旧池文件路径（tmp+rename，chmod 644，SHA 核对）。
- `systemd/validate-native-record.py`：校验原生记录格式、逐版本统计、
  覆盖当前源文件版本（走真实 `load_native_allowlist`）；P0 只报健康
  计数，标注“健康信号、永不作为准入证据”，绝不从 probe.db 合成原生证据。
- `systemd/switch-runbook.md`：Phase 0–7 切换手册 + 精确回滚命令。
  关键顺序：**先冻结源版本（停 pool-publish.timer），再做原生测速并
  转录**——先测速后冻结的版本会被下一个 :07 组装替换，记录作废。

**验证（本地 + VPS 各跑一次）：**

- 开关演练 `drills/switch_rehearsal.py`（真实包装脚本 + 真实 D3 代码，
  桩组装器 v1–v8 逐版删失败行）：**24/24**，本地与 VPS 一致。
  场景：S1 门禁 v1 通过（发布 == 14 行干净订阅）、S2 同步通过、
  S3 未测 v2 拒绝（`native_version_mismatch`，served 不变）、
  S4a 旧版本测速不放行新版本、S4b 当前源测速放行、S5 3× 并发
  publish + 3× sync 无 `sync_verify_failed`、S6 回滚演练。
- `systemd-analyze verify`：D4 定时器单独验 **exit=0**；生产单元基线
  exit=0；D4 服务单元的唯一报错是两条 ExecStart 路径不存在
  （`/opt/pool-gate/*.sh`，切换 Phase 1 才部署）——**无语法错误**。
  `--root` 桩根方式不可用（缺 sysinit.target），已放弃，不影响结论。
- 日历表达式核对：`*:07` → 下次 08:07；`*:0/15:00` → 下次 08:15。
- 校验器在 fixture 上：ok=true，覆盖源版本，准入 14、有条件 3、拒绝 30。

**诚实边界：** 单元只在隔离环境验过；真实切换须按手册 Phase 1–7
走，须 GPT 批准 + 机主授权 + 新鲜原生全组测速。门禁拒绝是安全态，
不是故障。

## 2. 生产备份可恢复性演练（`backup-drill/`）

**现状（2026-11-15 07:50 实测）：** 无“当前、可验证”的备份。
scheme-a 备份 10 天前；p1p3 备份（2026-11-13 19:07，50 文件）无
SHA 清单，无法自证完整；程序自带回退只有上一版 `.prev`。

**演练（2026-11-15 08:00 VPS 实跑）：**

- 快照 `snapshot-20261115-080044`：24 文件（pool.db 15MB、probe.db、
  publish/pool-new.txt + .prev、config.yaml、config/ 5 文件、pool-sync.sh、
  单元 14 个），DB 用 SQLite backup API 一致性复制，目录 700 / 文件 600，
  附 `manifest.json`（每文件 SHA256 + 字节数 + live 计数）。
  快照时 live 计数：pool.db 7359 节点 / 25 钉选 / 11 拉黑 / 134720 测试
  记录；发布文件 65 行（21 钉选 / 44 轮换 / 0 拉黑 / 0 不可解析），
  SHA 前缀 `1bd3fec8b92b`——与 07:50 只读巡检一致。
- 恢复演练 `restore_verify.py`：**9/10 通过，总体 ok**。
  通过：SHA 全匹配、pool.db/probe.db 打开且行数一致、发布文件解析一致、
  config 键一致、门禁 dry-run 恢复件与 live 件 verdict 完全相同
  （均为 rc=1 `phone_gate_zero_qualified`，diag 原因
  `native_version_mismatch`）、p1p3 pool.db 可打开（7268 节点、
  25 钉选，36.9 小时前）、p1p3 订阅可解析（47 行）。
  未通过（**设计内信息项，不计入通过门**）：`p1p3_has_manifest`——
  旧备份本来就没有清单，无法自证完整；结论是“p1p3 存在、可恢复、
  但无清单”，不是“p1p3 不可用”。
- 演练发现并已处理：SQLite 打开 WAL 模式 DB 副本会在快照目录里留下
  0 字节 `-wal` 与 32KB `-shm` 副文件（不在 manifest 内）；已删除，
  快照目录现与 manifest 完全一致（24 文件）。

**诚实边界：** 演练只证明“备份可恢复”；恢复到生产的操作（§3 of
PROCEDURE.md）未跑过，须在切换窗口外另做桌面演练。快照含真实凭据，
只存 VPS，永不下载、不贴聊天。

## 3. 21 钉选取消永久豁免（`pinned-wiring/`）

**关键发现：** `pinned_protected: true` 是死配置项——没有任何代码
读取它。豁免是生产 `pool.cli publish` 的结构（钉选行无条件拼入、
超上限只 drop 轮换、winner-clean 只动轮换）。**只改配置项改不了
任何行为**；消除豁免的唯一办法是让发布走 D3 门禁（门禁对钉选行与
轮换行一视同仁）。

**变更（`pinned-wiring/CONFIG-DIFF.md`，生产未改）：**

- `config.yaml`：`pinned_protected: true` → `false`（记账 + 防未来
  代码误读，唯一改生产配置的一处）；
- 与 systemd 切换同一窗口：停旧 publish/sync 定时器（豁免的两个载体
  一起下线），启用门禁定时器；
- 钉选表（25 行）不动、拉黑表不动、轮换准入门不动；未通过的钉选行
  只是本次不发布，不是删除，下次测速通过即恢复。

**验证（`tests/test_d4.py`，7 测试）：**

| # | 证据状态 | 预期 | 实测 |
|---|---|---|---|
| 1 | 新鲜原生通过 | 仅 14 条钉选发布 | 发布 14 行，全为钉选 |
| 2 | 证据过期 25h | 全部拒绝 | rc=1 `phone_gate_zero_qualified` |
| 3 | 钉选原生失败 | 全部拒绝 | rc=1 |
| 4 | 证据属另一版本 | 全部拒绝 | rc=1 |
| 5 | 混合 10/14 通过 | 仅 10 条发布 | 发布 10 行 |
| 6 | 记录缺 5 条结果行 | 缺证据的拒绝，其余 9 条发布 | 发布 9 行 |
| 7 | 旧式未门禁源进 sync | sync 拒绝，served 不动 | rc=1，served SHA 不变 |

本地 7/7；VPS 全套 **93/93 通过（24 D1 + 39 D2 + 23 D3 + 7 D4），
1 跳过**（chmod-000，root 下跳过）。负对照已验：全失败时发布
rc=1，新鲜通过时发布 14 行——测试不是空转。

**切换后预期：** 钉选行数不再恒定 21；每版钉选行数 = 该版本原生
通过的钉选行数。若冻结版本测速里钉选全军覆没，门禁拒绝、旧 served
保留（安全态），须机主重新测速。

## 4. DIRECT 测试方案（`direct-test-plan.md`）

D1 版方案已按 D3 状态更新（D4 变更头列明）：

- 测试本身不碰门禁（测试组走手机侧订阅）；但测试前后须按 D4 口径
  核对 served 版本锚点（SHA + 行数 + 门禁版/旧版注明）；
- 切换后 served 来源为门禁 served 文件 → bridge（目标路径不变，
  SHA 链可验）；
- TEST-SINGLE 须是**当前 served 版本 SHA 下新鲜原生通过**的节点；
- 新增收尾第 5 步：served 文件 SHA 复核（测试不得改变生产 served 文件）；
- 其余步骤、判定标准、诚实边界与 D1 版一致。

**未做：手机测试本身未跑。** 须机主在手机上跑（三种情形各 2–3 分钟），
跑之前助手须先准备好 3 份测试订阅并核对。三种情形全部“不落 DIRECT”
才算证明完成；任一情形落 DIRECT 即为正式切换的阻断项。

## 5. 汇总：D4 之后仍需 GPT / 机主的事

1. **GPT 裁决**：D4 四项是否通过；D3 + D4 是否可进入切换准备。
2. **机主手机**：新鲜原生全组测速（13:24 已 stale；切换前与切换后
   各需一次）+ DIRECT 三种情形测试。
3. **机主授权**：切换窗口（按 switch-runbook.md Phase 0–7 执行）。
4. **未在隔离内验证的**：真实切换（须走手册）、真实恢复到生产
   （须桌面演练）、DIRECT 手机实测、门禁在真实 :07 周期里的表现。
   以上四项均须在生产窗口里做，D4 不代劳、不谎称已验。
