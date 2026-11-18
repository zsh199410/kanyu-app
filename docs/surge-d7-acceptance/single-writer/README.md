# single-writer（任务 G：生产发布器单写手锁）

## 问题：guard 只能证明“检查那一刻”，不能序列化写手

任务 C 复用的 PR #80 guard（`../legacy-writer-guard/legacy-writer-guard.py`，
head `eaa52023`，blob `5d4a86dea5b79faed304a29e1e0a03a20eb31158`，检查逻辑零改动）
是一个 fail-closed 的**时间点检查**：两个并发的检查可以同时通过。
第一轮的 `tests/test_legacy_writer_guard.py` 第 8 项已经把这一点写成断言
（两个并发检查都返回 True），并明确指出需要一把锁来补位。

本目录就是那把锁：一个连续的、跨进程有效的排他临界区，把
「guard 检查＋写 served」包在同一个 `flock` 里。

## 临界区流程（`single_writer.py::publish`，全部在锁内）

```
取得写锁 (flock LOCK_EX, 超时 fail-closed)
  → STOP 检查（存在 STOP 即拒绝）
  → PR #80 guard 检查（旧写手在此时已排空）
  → 旧写手禁启证明（见下，超出 flock 的一层）
  → 候选重验（磁盘上的 served SHA 必须仍等于候选所基于的版本；
     候选 SHA 重算；过期候选拒绝）
  → 写入本发布自己的 DB 记录（publish_log，记 id 供回滚）
  → 原子写 staging（tmp + fsync + rename + 目录 fsync），验 SHA
  → 原子写 served，验 SHA
  → 写后复查（guard + 禁启证明各再跑一次；旧写手在窗口内重进
     即恢复旧文件＋删自己的记录＋拒绝）
  → 终验 served / staging SHA
释放锁
```

锁外不存在“检查通过了、还没写”的窗口：检查与写入之间没有
未受控竞态——任何后来者要么等锁，要么超时拒绝；任何过期候选
在锁内重验时被拦下。

## 8 项核实点的对照

| # | 核实点 | 本实现如何满足 | 测试位置 |
|---|---|---|---|
| 1 | 两个新发布任务不能同时写 | 同一把 `flock`，同一时刻只有一个持有者；第二个要么等锁，要么 `lock_timeout` 拒绝 | `test_single_writer.py::test_01`（2 进程竞发，恰 1 胜）、VPS systemd 双 service 并发 |
| 2 | 旧写手无法在切换期间重新进入 | 禁启证明链（见下）＋写后复查；重进即回滚 | `test_single_writer_failures.py::test_f03/f04/f06`、VPS 隔离单元实测 |
| 3 | 多进程检查通过 ≠ 独占写权限 | guard 检查在锁内才作数；锁外通过的检查不授予任何写权限（测试先证两个进程检查同过，再证持锁者之外的发布被 `lock_timeout` 拒绝） | `test_single_writer.py::test_02` |
| 4 | 检查和写入之间无未受控竞态 | 候选重验在锁内：8 进程同版本竞发恰 1 胜、其余 7 个 `stale_current_version`，胜者负载完整 | `test_single_writer.py::test_03` |
| 5 | SIGKILL 后锁释放、无半成品 | `flock` 由内核在进程死亡时释放（SIGKILL 跑不了任何清理代码也一样）；写入是原子的，死在任何一点都只留旧文件或新文件 | `test_single_writer.py::test_05`（本地 SIGKILL）、VPS `systemctl kill -s SIGKILL` 实测 |
| 6 | 文件写入原子性 | 同目录 tmp + fsync + rename + 目录 fsync；失败删 tmp、目标不动；无残留 tmp | `test_single_writer.py::test_04`、`test_single_writer_failures.py::test_f07` |
| 7 | HTTP 对外内容无部分写入 | 同上：nginx/HTTP 读到的永远是旧完整文件或新完整文件；4 读线程 × 30 次发布全程只观测到完整负载 | `test_single_writer.py::test_04`、VPS `http.server` 实测 |
| 8 | 回滚只删自身记录 | 回滚按 id 只删本次 `publish_log` 行；`crawl_log` / `test_log` 在回滚代码里根本不出现；多次故障后旧记录与全部抓取/测试行都在 | `test_single_writer.py::test_07`、`test_single_writer_failures.py::test_f09`、VPS 回滚实测 |

## 旧写手禁启证明：为什么不能只依赖 flock

旧写手（`pool.cli publish`、`pool-sync.sh`）**完全不用锁**：
`cli.py` 与 `pool-sync.sh` 中 `flock` / `fcntl` 出现次数均为 0。
一把新锁约束不了一个从不拿锁的写手。所以禁启必须另外从
systemd 状态本身证明，由 `legacy_ban_proof()` 执行（可注入
`show` / `processes`，默认走真实 `systemctl show` 与 `ps`）：

- 两个旧 timer：`loaded`、`UnitFileState == disabled`、
  `ActiveState == inactive`、无 pending Job；
- 两个旧 service：`loaded`、`inactive` + `dead`、MainPID 与
  ControlPID 均为 0、无 pending Job、`Result == success`，并且
  ——比 guard 多一档——`UnitFileState == disabled`（guard 不查
  service 的 UnitFileState，只查 timer 的）；
- 进程表里没有 `pool.cli publish` 与 `pool-sync.sh` 的实际写手进程；
- 任一检查本身失败（systemctl/ps 出错、超时）即整个证明失败。

**mask 与原文 guard 的冲突（2026-11-18 在 VPS 上实测证实）**：
被 mask 的 service 报告 `LoadState == masked`，而原文 guard 要求
service `LoadState == loaded`，否则以 `service_not_loaded` 拒绝。
也就是说，**一旦把旧 service mask 掉，原文 guard 将永远拒绝，
此后任何发布都无法通过**。
mask 是更强的一档，但它需要先修订 guard（接受 `LoadState ==
masked` 视为已排空），那是超出本轮的单独决定，需 GPT/她批准。
因此本轮的默认证明链用 `disabled`（与原文 guard 兼容的最强链），
`legacy_ban_proof(require_masked_services=True)` 只作为已做该决定、
且不与原文 guard 并用的调用方提供的 opt-in；VPS 测试 S2e 把冲突
双向演示了一遍（mask 后 guard 拒绝、masked 变体证明通过；
unmask 后两者都恢复通过）。

证明在**锁内、写前**跑一次，**写后**再跑一次，失败的环节以
`{"check": ..., "ok": false, "detail": ...}` 逐条记入证据，
供日志与交接核查。**本轮不实际停生产 timer**：生产侧的证明链
只在隔离环境（`/opt/p2p3-single-writer/`、隔离命名的单元
`p2p3-legacy-*` / `p2p3-gate-*`）里对真实 systemd 跑通；
生产 timer 全程保持 active，生产 guard 在 VPS 上实测为拒绝
（`old_timer_not_disabled`），即生产写路径仍被挡住——这正是
本轮的预期结果。

## 与 PR #80 guard 的关系

- guard 文件原样复用，**不改、不抄、不重写检查逻辑**。
  `single_writer.py::load_guard()` 按路径找到它并导入；找不到
  时发布直接拒绝（`guard_unavailable`），绝不无检查放行。
- guard 管“旧写手此刻是否排空”，本模块管“从检查到写完的整段
  时间里谁都不许插进来”。两者缺一不可：只有 guard 没有锁，
  并发检查可同过；只有锁没有 guard，旧写手可以在锁外写同一文件。
- 部署时新 gate service 的 `ExecStartPre` 仍调 guard，
  包装脚本仍先调 guard——本模块在锁内又调一次，三处同一语义。

## 已知界限（不要把本模块当成它不是的东西）

1. **不防 root 手动绕过**：有 root 的人可以直接写 served 文件、
   可以 `unmask` 旧 service。禁启证明防的是 timer/服务“自己”
   重新进入与误操作，不是防有意的 root 破坏。交接时须把
   “旧 timer 保持 disabled、旧 service 保持 masked”写进运维手册，
   并靠定期巡检（guard + 禁启证明）发现偏离。
2. **不防机器断电瞬间的 rename 语义之外的情况**：原子写保证
   “旧完整或新完整”，不保证断电后一定是新文件；这正是
   “写后验 SHA + 不一致即回滚”的存在意义。
3. **锁是 advisory（建议性）的**：只对同样拿这把锁的进程有效。
   旧写手不拿锁，所以才需要禁启证明链；新写手必须全部走
   `publish()`，任何旁路写 served 的脚本都会破坏单写手保证。
4. **本轮未动生产**：未停任何生产 timer，未写生产 served /
   staging，未删节点，未动 blocklist / STOP / 21 钉选。
   生产切换（真正停旧 timer、切新发布器）仍需单独批准，
   本模块只是把切换所需的锁与证明链先在隔离环境里验通。
5. **`systemctl stop` 不产生 `Result=signal`**（本机 systemd 实测）：
   走 stop 作业的 SIGTERM 停掉的 service 事后 `Result` 仍是
   `success`，只有绕开 systemd 直接对 MainPID 下手的 kill
   （如 `kill -9 <pid>`）才会留下 `Result=signal`。因此 guard
   的 `Result` 检查能抓住“被人从外部杀掉的写手”，但抓不住
   “被正常 stop 停掉的写手”——后者要靠 `ActiveState` /
   `SubState` / `MainPID` 的排空检查来覆盖，证明链里四项都有，
   不只依赖 `Result` 一项。

## 文件清单

- `single_writer.py`：锁 + 临界区 + 禁启证明 + 原子写 + 回滚
  （CLI：`publish` / `check`，`--skip-guard` 仅测试模式）。
- `vps_publish_driver.py`：VPS systemd 测试用的驱动（publish /
  hold 两种模式；把隔离单元名注入 guard 与禁启证明）。
- `vps_systemd_test.py`：VPS 隔离环境端到端测试（真实 systemd、
  真实 systemctl / ps 输出作证据）。
- `README.md`：本文件。

## 测试

本地（沙盒，多进程并发）：

```bash
cd ~/workspace/p2p3-dual/surge-d7-acceptance
python3 -m unittest tests.test_single_writer tests.test_single_writer_failures -v
# 或在 tests/ 目录下：
python3 -m unittest test_single_writer test_single_writer_failures -v
```

VPS（隔离目录 `/opt/p2p3-single-writer/`，真实 systemd）：

```bash
# 1. 传文件并核 SHA（见 vps_systemd_test.py 头部说明）
# 2. ssh ... 'python3 /opt/p2p3-single-writer/vps_systemd_test.py'
```

测试日志存 `../tests/logs/`（本地 `test-single-writer-local-*.log`，
VPS `vps-systemd-*.log`）。第一轮的 33/33 持锁模拟结果未被用作
本轮证据；本轮的每一项结论都有本轮真实运行的日志。

## 回执

`[SINGLE_WRITER_LOCK_VALIDATED]`（PASS / FAIL / UNPROVEN / BLOCKED）
的结论与逐项依据见父任务回传报告，不在本 README 里预填。
