# D4：GPT 对 D2（PR #77）的四项“其次”（隔离实现）

针对 GPT D2 代码复核（Issue #73 评论 6884522235，2026-11-15 05:32）
的四项“其次”要求：真实 systemd :07/:15 接线 + 回滚方案、生产备份
可恢复性演练、21 钉选取消永久豁免的生产接线、隔离 DIRECT 测试方案。
D3（fail-closed 恢复状态）已提交 PR #77（head ba38c745，评论
6886129131）；本目录在 D3 树上实现并验证 D4 四项，**生产一律未动**
（未改生产目录、生产订阅、生产定时器、手机配置；无 GitHub 操作）。

详见 `docs/D4_REPORT.md`。本 README 只给总览与运行方法。

## 0. D4 四项总览

| # | 内容 | 状态 | 证据 |
|---|---|---|---|
| 1 | systemd :07/:15 接线 + 回滚 | 完成，隔离验证通过 | 单元 4 个 + 包装脚本 2 个 + 切换手册；开关演练 24/24（本地+VPS）；`systemd-analyze verify` 无语法错误 |
| 2 | 生产备份可恢复性演练 | 完成，通过 | 快照 20261115-080044（24 文件，带 manifest）；恢复演练 9/10（唯一未过项为旧备份无清单，属设计内信息项） |
| 3 | 21 钉选取消永久豁免 | 完成，隔离验证通过 | 变更方案；7/7 钉选门禁测试（全套 93/93，本地+VPS） |
| 4 | DIRECT 测试方案 | 完成（方案更新） | D4 版 direct-test-plan.md；手机测试未跑（须机主在手机上跑） |

## 1. systemd 接线（`systemd/`）

- `pool-gate-publish.service` / `.timer`（`:07`）、
  `pool-gate-sync.service` / `.timer`（`:0/15:00`），Type=oneshot，无 Restart。
- `gate-publish.sh`：门禁先行——先用 D3 publish 对当前源文件做门禁，
  通过后才跑生产组装（下一版本）；门禁拒绝即安全态，不组装。
- `gate-sync.sh`：D3 sync 通过后才复制 served → bridge + 旧池文件路径。
- `validate-native-record.py`：校验原生记录格式与源版本覆盖；P0 只报
  健康计数，绝不合成原生证据。
- `switch-runbook.md`：Phase 0–7 切换手册 + 精确回滚命令。关键顺序：
  先冻结源版本（停 pool-publish.timer），再做原生测速并转录。
- 演练 `drills/switch_rehearsal.py`：真实包装脚本 + 真实 D3 代码，
  24/24（本地+VPS）。`systemd-analyze verify`：定时器 exit=0；服务单元
  唯一报错是两条 ExecStart 路径尚未部署（切换 Phase 1 才部署），无语法错误。

## 2. 备份演练（`backup-drill/`）

- `snapshot_backup.py`：只读快照（DB 用 SQLite backup API），24 文件 +
  `manifest.json`（SHA256 + 计数），目录 700 / 文件 600，**只存 VPS**。
- `restore_verify.py`：恢复到隔离目录并验证（SHA、DB 行数、订阅解析、
  门禁 dry-run 恢复件与 live 件 verdict 相同）+ p1p3 旧备份只读可恢复性。
- 实跑：快照 20261115-080044（pool.db 7359 节点 / 25 钉选；发布文件
  65 行 = 21 钉选 + 44 轮换，SHA 前缀 `1bd3fec8b92b`）；恢复演练 9/10
  通过（总体 ok；唯一未过为 p1p3 旧备份无清单，属设计内信息项）。
- `PROCEDURE.md`：程序、命令、通过标准、恢复路径、保留节奏。
- 快照含真实凭据，**永不下载、不贴聊天**；本地只存演练日志
  （`backup-drill/restore-log-vps.json`）。

## 3. 21 钉选接线（`pinned-wiring/` + `tests/test_d4.py`）

关键发现：`pinned_protected: true` 是死配置项——没有任何代码读取它；
豁免是生产 `pool.cli publish` 的结构（钉选行无条件拼入）。只改配置项
改不了任何行为；消除豁免的唯一办法是让发布走 D3 门禁。

- `pinned-wiring/CONFIG-DIFF.md`：配置 diff（`pinned_protected: false`）、
  定时器接线、切换后预期、回滚命令。
- `tests/test_d4.py`：7 项钉选门禁测试（新鲜通过 / 过期 / 失败 /
  错版本 / 混合 / 缺结果行 / 旧式源进 sync 拒绝）。本地 7/7；
  VPS 全套 93/93（D1 24 + D2 39 + D3 23 + D4 7），1 跳过。

## 4. DIRECT 测试方案（`direct-test-plan.md`）

D1 版方案按 D3 状态更新：测试本身不碰门禁；测试前后按 D4 口径核对
served 版本锚点（SHA + 行数 + 门禁版/旧版注明）；TEST-SINGLE 须是
当前 served 版本 SHA 下新鲜原生通过的节点；新增收尾 served SHA 复核。
**手机测试未跑**——须机主在手机上跑，跑之前助手先准备好 3 份测试订阅。

## 5. 目录（D4 新增/改动）

```
systemd/
  pool-gate-publish.service / .timer   D4 新增：门禁发布 :07
  pool-gate-sync.service / .timer      D4 新增：门禁同步 :15
  gate-publish.sh / gate-sync.sh       D4 新增：门禁先行包装脚本
  validate-native-record.py            D4 新增：原生记录校验器
  switch-runbook.md                    D4 新增：Phase 0-7 切换 + 回滚手册
backup-drill/
  snapshot_backup.py / restore_verify.py / PROCEDURE.md
  restore-log-vps.json                 VPS 实跑恢复日志（计数/SHA  only）
pinned-wiring/
  CONFIG-DIFF.md                       D4 新增：钉选豁免变更方案
tests/test_d4.py                       D4 新增：7 项钉选门禁测试
drills/switch_rehearsal.py             D4 新增：开关演练（24 场景）
direct-test-plan.md                    D4 更新：D1 方案 + D3 增量
docs/
  D4_REPORT.md                         D4 报告：逐项状态、证据、诚实边界
  D3_REPORT.md / D2_REPORT.md          保留
  switch-rehearsal-log.json / switch-rehearsal-log-vps.json
  （其余 D1-D3 演练日志保留）
pool/ fixtures/ tests/test_d1.py test_d2.py test_d3.py drills/  均继承 D3，未改
```

## 6. 运行（隔离环境）

```bash
python3 -m unittest discover -s tests -v      # 93 项（D1 24 + D2 39 + D3 23 + D4 7）
python3 drills/switch_rehearsal.py --out docs/switch-rehearsal-log.json
# VPS 上（只读生产，演练在 /opt/p2p3-d4 内）：
python3 backup-drill/snapshot_backup.py --out backup-drill/snapshot-<ts>
python3 backup-drill/restore_verify.py --snapshot backup-drill/snapshot-<ts> \
  --scratch backup-drill/restore-test-<ts> --code-dir /opt/p2p3-d4
python3 systemd/validate-native-record.py --record fixtures/native_results_fixture.json \
  --source-file fixtures/pool_44_fixture.txt --code-dir . --probe-db fixtures/p0_fixture.db
```

## 7. 诚实边界（D4 新增部分）

已验证（隔离环境；本地 Python 3.12.3 与 VPS Python 3.13.5 双环境）：
- 开关演练 24/24、钉选门禁 7/7、全套 93/93、备份恢复 9/10、
  `systemd-analyze verify` 无语法错误、校验器 fixture 全对。
- 备份演练用的是**真实生产快照**（VPS 上实跑），不是合成备份；
  快照本身只存 VPS，本地只存日志。

没验证 / 仍需的：
- 真实切换（须 GPT 批准 + 机主授权 + 新鲜原生全组测速，按手册走）。
- 真实恢复到生产（桌面演练未做）。
- DIRECT 手机实测（须机主在手机上跑）。
- 门禁在真实 :07 周期里的表现（须切换后观察）。
- D3 的边界不变：固件是合成的（不是真实手机证据）；锁与链防误配置
  不防有写权限的恶意写手；同时间戳跨版本更精细定序未做。

---

# 以下为 D3 README（保留，供参考）

## D3：修复 GPT 对 D2（PR #77）的唯一 P0 阻断——恢复状态 fail-open（隔离实现）

针对 GPT D2 代码复核（Issue #73 评论 6884522235，2026-11-15 05:32）：
D2 提交已进 PR、红→绿与 63/63、15/15、22/22 是实质进展，但
**recovery-state.json 被删默认 ok 的 fail-open 仍是 P0 阻断**——
要求 D3 以缺失/损坏/不可读/非法状态/原子写中断均 fail-closed 修复，
新部署只能显式初始化（含安全锚点及审计）建立 ok，已部署 STOP 不得
靠删状态文件复位，补红→绿测试、状态持久化与恢复演练，说明初始化
与人工恢复权限边界。本目录在隔离环境实现并验证了该 P0 修复，
**生产一律未动**。

D1（24 项）+ D2（39 项）测试全部保留并全绿。D3 新增 23 项测试 +
状态丢失演练（11 场景）。「其次」项（systemd 接线、备份演练、
21 pinned 接线、DIRECT 测试）已由 D4 完成，见上文与 `docs/D4_REPORT.md`。

（D3 修复细节、目录与运行方法见 `docs/D3_REPORT.md`；D3 README
原文已由 D4 报告与本 README 上半部分承接，此处从略。）
