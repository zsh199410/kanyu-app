# D5 备份恢复可执行性桌面演练报告（Issue #73，GPT D4 复核第 2 项）

> 2026-11-15 23:26 CST 完成。隔离演练通过；**生产未动**（未碰
> `/opt/free-node-program/`、`/opt/probe-service/`、`/opt/surge-bridge/`、
> 任何生产定时器与手机配置；未读取 D4 真实快照）。
> 全部数据为合成数据：TEST-NET `192.0.2.x`、假密码
> `TEST-ONLY-NOT-A-REAL-NODE`。本报告不含真实节点 URI、订阅 URL、
> 密码、私钥、原始 IP、令牌；只含计数、SHA 前缀、时间戳、状态名、行数。

## 0. 结论

| 环境 | 检查项（通过门） | 信息项 | 单元 verify | 门禁 dry-run |
|---|---|---|---|---|
| 本地（Python 3.12.3） | **13/13 通过，0 失败** | 1 | 4 个单元 exit 均为 0 | 恢复件 = 快照件（见 §4） |
| VPS（Python 3.13.5） | **13/13 通过，0 失败** | 1 | 4 个单元 exit 均为 0 | 恢复件 = 快照件（同左） |

- 演练脚本：`drills/backup_restore_drill.py`；快照脚本：
  `drills/snapshot_backup_d5.py`（D4 `snapshot_backup.py` 逻辑的隔离改写，
  源路径改为合成 live 树，另加副文件清理，见 §3）。
- 日志：本地 `docs/backup-restore-drill-log.json`（23:26:08 CST），
  VPS `/opt/p2p3-d5/docs/backup-restore-drill-log-vps.json`
  （23:26:25 CST，本地亦存一份 `docs/backup-restore-drill-log-vps.json`）。
- 合成“生产样”规模：pool.db 12 节点（8 已 checkpoint + 4 在 -wal 中）、
  3 钉选、2 拉黑、20 测试记录；probe.db 5 节点、10 报告；
  发布文件 8 行（3 钉选 / 5 轮换 / 0 拉黑 / 0 不可解析）；
  快照 15 文件，附 `manifest.json`（每文件 SHA256 + 字节数 + live 计数），
  目录 700 / 文件 600；发布文件 SHA 前缀 `174c9558ff11`。

## 1. 步骤（按 `backup-drill/PROCEDURE.md` §1–§3 的顺序，隔离版）

1. 造合成 live 树（WAL 模式 pool.db：先写 8 行并 checkpoint，再写 4 行
   只提交不 checkpoint，使其留在 `-wal` 中；快照前 live `-wal` 为 4152 字节）。
2. 用 `snapshot_backup_d5.py` 做快照（DB 用 SQLite backup API 一致性复制）。
3. WAL 三项验证（§3）：快照一致性、过期副文件清除、回放 + checkpoint、
   D4 副文件发现复现与清理。
4. 模拟 live 丢失：把 live 树移走（`live-lost/`），按 §3 顺序恢复——
   停定时器（桌面推演，未发任何真实 systemctl 命令）→ 先恢复 DB →
   再恢复发布文件 / config / 单元 / 包装脚本（恢复包装脚本时重授 +x，
   见 §5）→ daemon-reload（推演）→ 起定时器（推演）。
5. 逐项核对恢复件（SHA、行数、解析、配置键、门禁 dry-run、单元 verify）。
6. 旧式无清单备份对照（信息项，不计入通过门）。

## 2. 逐项结果（两地一致）

| # | 检查项 | 结果 | 证据（计数 / 状态） |
|---|---|---|---|
| 1 | synth_live_built | 通过 | pool.db 12/3/2/20，probe.db 5/10，发布 8 行（3/5），live -wal 4152 字节 |
| 2 | snapshot_manifest_complete | 通过 | 快照 rc=0，15 文件，manifest 齐全 |
| 3 | wal_snapshot_consistent_uncheckpointed_rows | 通过 | 快照 nodes=12，副本 checkpoint 后仍 12，无丢失行 |
| 4 | wal_stale_sidecar_cleared_before_restore | 通过 | 清除过期 -wal/-shm 各 22 字节后恢复，行数 12，恢复后无副文件残留 |
| 5 | wal_replay_then_checkpoint | 通过 | 原始 DB + -wal/-shm 回放得 12 行，checkpoint 后仍 12，关闭后副文件消失 |
| 6 | wal_open_sidecar_reproduced_and_cleaned | 通过 | 只读打开复现 0 字节 -wal + 32768 字节 -shm；删除后快照目录与 manifest 完全一致，pool.db SHA 不变 |
| 7 | live_loss_simulated_and_restored | 通过 | 按 §3 顺序重建 live 树；恢复 DB 时目标目录无过期副文件需清除 |
| 8 | restore_sha_matches_manifest | 通过 | 15 文件 0 不匹配 |
| 9 | restored_db_counts_match | 通过 | pool.db / probe.db 行数与 manifest 一致 |
| 10 | restored_publish_parses | 通过 | 8 行（3 钉选 / 5 轮换 / 0 不可解析），与 manifest 一致 |
| 11 | restored_config_keys_match | 通过 | 顶层键 5 个一致，`pinned_protected: false` 一致 |
| 12 | gate_dry_run_restored_equals_snapshot | 通过 | 快照件与恢复件均为 rc=1 `phone_gate_zero_qualified`，verdict 相同 |
| 13 | units_scripts_sha_match_and_verify | 通过 | 4 单元 + 2 脚本 SHA 全匹配；`systemd-analyze verify` 4 个 exit 均为 0，无语法错误；包装脚本可执行 |
| — | legacy_no_manifest（信息项） | 仅记录 | 旧式备份存在、pool.db 可打开（12 节点）、订阅可解析（8 行），但**无清单、无法自证完整**——与 D4 的 9/10 口径一致，不计入通过门 |

## 3. WAL 副文件处理结论

- **(a) 快照一致性**：源 DB 处于 WAL 模式且 4 行未 checkpoint 时，
  backup API 读出的是包含这 4 行的一致镜像（快照 nodes=12）；
  在副本上 `wal_checkpoint(TRUNCATE)` 后仍为 12 行，**无丢失行**。
- **(b) 恢复时残留副文件，两种情形均验证通过**：
  - 情形一（清除）：恢复目标预置过期 -wal/-shm（各 22 字节垃圾内容），
    恢复流程先清除副文件再放回主 DB，恢复后打开行数 12 且无副文件残留。
  - 情形二（回放）：把 live DB + 其真实 -wal/-shm 原样复制后打开，
    SQLite 回放 -wal 得到 12 行，再 checkpoint 仍为 12 行，关闭后副文件消失。
  - 结论：两条路都走得通；恢复流程采用“先清除过期副文件再放回主 DB”，
    回放只作为副文件与主 DB 配套且未过期时的备选，**不得对来历不明的
    -wal 直接回放**。
- **(c) D4 发现复现与处理**：只读打开 WAL 模式副本会在其目录留下
  0 字节 `-wal` 与 32768 字节 `-shm`（本次复现数值与 D4 一致）。
  处理：打开核对后立即删除副文件，再核对目录与 manifest 完全一致、
  pool.db SHA 不变。**新增发现**：快照脚本自身的校验读
  （`db_counts` 只读打开）与演练第 3 项的校验读同样会留下副文件；
  D5 快照脚本已改为每次校验读后立即清理副文件并在收尾全目录扫一遍
  （本次快照后目录内副文件数为 0），演练第 3 项的校验读后也同样清理。
  建议把“校验读后删副文件”写进 `PROCEDURE.md`，否则快照目录会比
  manifest 多出副文件，无法自证一致。

## 4. 门禁 dry-run 一致性

- 用 D5 `pool.publish.run_publish` + `pool.recovery.init_recovery_state`
  （与 D4 `restore_verify.py` 相同调用方式），以 D5 fixtures 的原生记录
  对快照件与恢复件各跑一次。
- 两地结果相同：快照件 rc=1 `phone_gate_zero_qualified`，恢复件 rc=1
  `phone_gate_zero_qualified`，verdict 完全相同 = 恢复件与快照件字节一致。
- 说明：该拒绝是**预期拒绝**——fixture 原生记录对应另一版本
  （`native_version_mismatch`），不是发布成功；它只证明恢复无失真，
  不证明该版本可发布。

## 5. 服务 / 定时器恢复后 SHA 一致性

- 恢复出的 4 个单元（`pool-gate-publish.service/.timer`、
  `pool-gate-sync.service/.timer`）与 2 个包装脚本
  （`gate-publish.sh`、`gate-sync.sh`）逐个与 manifest SHA 比对：**0 不匹配**。
- `systemd-analyze verify` 逐个单独验恢复出的单元：两地 4 个单元
  exit 均为 0，无语法错误（verify 输出里与本机无关的其他单元报错，
  如 `motd-news.timer`，已在演练中过滤，只计与 `pool-gate-*` 有关的行）。
- **新增发现（恢复流程缺口）**：快照把全部文件存为 600，恢复出的包装脚本
  会失去可执行位，`systemd-analyze verify` 会报
  `Command ... is not executable: Permission denied`（首跑实测）。
  演练的恢复步骤已补上“恢复后对两个包装脚本重授 +x”并断言可执行；
  建议把这一条写进 `PROCEDURE.md` §3，否则真实恢复后服务单元无法启动。
- “停 → 恢复 → 起”只做了桌面推演 + 文件级验证，未实际启停任何真实
  systemd 服务 / 定时器；真实 `:07` / `:15` 周期行为不在本次演练内。

## 6. 旧 p1p3 无清单对照

- 造了一个无 manifest 的旧式备份（只有文件，无清单）：pool.db 可打开
  （12 节点）、订阅可解析（8 行）。结论只能是“**存在、可恢复、但无清单自证**”
  （检查项记为信息项，不计入通过门，与 D4 的 9/10 口径一致）。
- 对照：新快照有清单时，15 文件 SHA 全匹配、行数全匹配，恢复可自证。
  结论：无清单备份只能作“存在性”记录，不能作为恢复依据（与
  `PROCEDURE.md` §4 一致）。

## 7. 未闭合风险（诚实边界）

1. **真实恢复到生产未跑过**：本次只证明“合成快照可恢复”；把真实快照
   恢复到生产的操作（PROCEDURE §3）仍须在切换窗口外另做桌面演练。
2. **真实快照仍只存 VPS**：D4 真实快照含真实凭据，本次演练**未读取、
   未复制、未下载**它；日常快照节奏（每日 03:45、保留 7 天）仍待批准排期。
3. **手册缺两条**：`PROCEDURE.md` §3 须补“校验读后删 -wal/-shm”
   与“恢复包装脚本后重授 +x”，否则真实恢复会留下副文件或起不来服务。
4. **定时器真实周期未验**：`*:07` / `*:0/15:00` 的真实触发、门禁在
   真实 :07 周期里的表现、并发 publish + sync，均不在本次演练内。
5. **dry-run 用的是 fixture 原生记录**：verdict 相同只证恢复无失真；
   真实版本的门禁准入仍须新鲜原生全组测速。

## 8. GPT D4 第 1 项流程要求（记入，不由本演练执行）

- 生产巡检 65 行（21 钉选 + 44 轮换）但 dry-run
  `phone_gate_zero_qualified / native_version_mismatch`，是现网仍在提供
  未被当前手机证据认证的订阅的风险提示，不是已证明 DIRECT 泄漏。
- 切换准备须先**冻结版本，再做同 SHA 原生整组复测**；不要把 14 条旧截图 /
  合成 fixture 当作当前有效记录。手机测试本身不在本次任务内。
