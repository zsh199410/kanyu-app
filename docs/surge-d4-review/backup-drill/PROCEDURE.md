# 生产备份可恢复性演练（Issue #73，D4）

> 状态：程序 + 隔离演练通过。快照本身含真实订阅与凭据，**只存 VPS
> 600 权限文件**，绝不下载到本地、绝不贴进聊天/日志/Issue。
> 本文件只记录程序、命令与通过标准；计数与 SHA 见演练日志。
> 演练只读生产（SQLite backup API + 文件复制），不改生产、不停
> 定时器。

## 0. 现状（2026-11-15 07:50 实测，只读）

| 项目 | 实测值 |
|---|---|
| 现有备份 `backups/scheme-a-20261105-093314/` | 4 文件（pool.db、pool-new.txt、config.yaml、checksums.txt），2026-11-05，**10 天前** |
| 现有备份 `backup-p1p3-20261113-190706/` | 50 文件（pool.db 13MB、probe.db、pool-new.txt.47、config.yaml、config/、pool-code/），2026-11-13 19:07，**约 36 小时前**，无 checksums 清单 |
| 程序自带回退 | `publish/pool-new.txt.prev`（上一版，仅 1 版） |
| 快照缺口 | 没有“当前版本 + 可校验清单”的定期快照；p1p3 备份无 SHA 清单，无法自证完整 |

结论：**没有一份“当前、可验证”的备份**。D4 演练先验证 p1p3
备份是否可恢复（只读），再建立带清单的快照程序（供切换前执行）。

## 1. 快照程序（`snapshot_backup.py`，切换前执行）

```bash
python3 /opt/p2p3-d4/backup-drill/snapshot_backup.py \
  --out /opt/p2p3-d4/backup-drill/snapshot-<YYYYMMDD-HHMMSS>
```

快照内容（全部只读复制；DB 用 SQLite backup API，避免 WAL 下
直接 cp 的不一致）：

| 来源 | 快照内路径 | 说明 |
|---|---|---|
| `/opt/free-node-program/data/pool.db` | `pool.db` | backup API 一致性复制 |
| `/opt/probe-service/data/probe.db` | `probe.db` | 同上 |
| `/opt/free-node-program/publish/pool-new.txt` | `publish/pool-new.txt` | 当前发布文件 |
| `/opt/free-node-program/publish/pool-new.txt.prev` | `publish/pool-new.txt.prev` | 上一版 |
| `/opt/free-node-program/config.yaml` | `config.yaml` | 含 `pinned_protected` |
| `/opt/free-node-program/config/` | `config/` | 含 ui-password 等凭据文件（600） |
| `/opt/free-node-program/systemd/*` + `/etc/systemd/system/pool-*` | `units/` | 全部定时器/服务单元 |
| `/opt/free-node-program/pool-sync.sh` | `pool-sync.sh` | 旧同步脚本 |

快照同时写 `manifest.json`（每文件 SHA256 + 字节数 + 快照时
live 计数：pool.db 各表行数、发布文件行数与钉选/轮换拆分、
probe.db 计数、定时器列表）。快照目录 700，文件 600。
stdout 只输出 manifest 摘要（计数与 SHA 前缀），不输出文件内容。

## 2. 恢复演练（`restore_verify.py`，快照后立即执行）

```bash
python3 /opt/p2p3-d4/backup-drill/restore_verify.py \
  --snapshot /opt/p2p3-d4/backup-drill/snapshot-<ts> \
  --scratch /opt/p2p3-d4/backup-drill/restore-test-<ts> \
  --code-dir /opt/p2p3-d4
```

步骤与通过标准：

| # | 步骤 | 通过标准 |
|---|---|---|
| 1 | 逐文件验 SHA | 恢复出的每个文件 SHA256 与 manifest 一致 |
| 2 | pool.db 可打开（读写副本） | `sqlite3` 打开成功；各表行数与 manifest 计数一致 |
| 3 | probe.db 可打开 | 同上（表行数一致） |
| 4 | 发布文件可解析 | 行数与 manifest 一致；钉选/轮换拆分一致；0 行不可解析 |
| 5 | config.yaml 可解析 | 顶层键集合与 manifest 一致；`pinned_protected` 值一致 |
| 6 | 门禁 dry-run 一致性 | 用恢复出的 pool-new.txt 与用 live pool-new.txt 的实时复制各跑一次 D3 publish dry-run（fixture 原生记录，版本必然不匹配）：两次 rc 与 error 码**完全相同**（预期均为 rc=1 `phone_gate_zero_qualified`，diag 原因里为 `native_version_mismatch`）。相同 = 恢复件与 live 件字节一致；不同 = 恢复失真 |
| 7 | 现有 p1p3 备份可恢复性（只读） | 其 pool.db 可打开、行数可读；其 pool-new.txt.47 可解析、行数可读；记录年龄；无 manifest 则记“无清单、无法自证完整” |

任一失败即演练**不通过**：停下来查原因，不许以“差不多”放行。

## 3. 恢复路径（真实故障时用，切换手册引用本节）

1. 停相关定时器（`systemctl stop pool-publish.timer pool-sync.timer`
   及门禁定时器，若已切换）。
2. 从快照复制回原位置：`pool.db`（停 UI 服务后复制；或用 SQLite
   backup API 反向恢复）、`publish/pool-new.txt`、`.prev`、
   `config.yaml`、`config/`、单元文件（改动后 `systemctl daemon-reload`）。
3. 按 §2 的 1–5 项逐项核对（SHA、行数、解析）。
4. 重启定时器，观察下一个 :07/:15 周期日志。
5. 手机刷新 + 原生整组测速验收（0 失败、0 个 ≥300ms）。

## 4. 保留与节奏（建议，需机主/GPT 批准后排期）

- 切换前：必须有一次按 §1–§2 通过的快照 + 恢复演练（本次 D4
  演练即为模板）。
- 日常：每日 03:45（全量测试后）自动快照一次，保留 7 天；
  快照脚本本身不依赖门禁（它是恢复门禁的底座）。
- p1p3 式“无清单备份”不再作为恢复依据：新快照一律带
  `manifest.json`，无清单的备份只记“存在、未验证”。
