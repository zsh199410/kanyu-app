# legacy-writer-guard（任务 C：复用 PR #80 旧发布器排空检查）

## 来源

- 复用来源：PR #80《[Issue #73 P0] Fail closed until unlocked legacy writers are drained》
- 仓库：`zsh199410/kanyu-app`，分支 `issue73-p0-legacy-writer-interlock`
- Head SHA：`eaa520232af4336e03e83dd4d2f98cac3d8f2d4b`
- 原路径：`docs/surge-d7-acceptance/systemd/legacy-writer-guard.py`
  （blob SHA `5d4a86dea5b79faed304a29e1e0a03a20eb31158`，2026-11-18 经 GitHub 连接器
  `get_file_contents` 读回）
- 本地副本：`legacy-writer-guard.py`（本目录）。除文件头 10 行出处注释外，
  正文与 PR #80 源码逐字节一致，**未改动任何检查逻辑**。
- PR #80 同目录下不存在 `test_legacy_writer_guard.py`、README 或 `.service`
  文件（2026-11-18 逐一查过，均返回不存在），因此本目录的 README 与
  `../tests/test_legacy_writer_guard.py` 为本次任务 C 新写。
- PR #80 保持 Draft，**不自动合并**。

## guard 是什么

一个 fail-closed 的预检脚本：新发布器在写生产订阅文件之前，先证明
**旧的无锁写手在检查瞬间已经排空**。检查任一项不满足即拒绝
（exit 1，JSON `{"ok": false, ...}`），绝不放行。

旧写手（无锁、可与新写手并发写同一生产文件）指：

- 旧发布器：`pool.cli publish`
- 旧同步器：`pool-sync.sh`

## 检查项（全部必须通过才放行）

### 1. 两个旧 timer：`pool-publish.timer`、`pool-sync.timer`

| 属性 | 要求 | 不满足时的 reason |
|---|---|---|
| `LoadState` | `loaded` | `timer_not_loaded` |
| `UnitFileState` | `disabled` | `old_timer_not_disabled` |
| `ActiveState` | `inactive` | `old_timer_not_inactive` |
| `Job` | 为空或 `0` | `old_timer_has_job` |

### 2. 两个旧 service：`pool-publish.service`、`pool-sync.service`

| 属性 | 要求 | 不满足时的 reason |
|---|---|---|
| `LoadState` | `loaded` | `service_not_loaded` |
| `ActiveState` + `SubState` | `inactive` + `dead` | `old_service_not_drained` |
| `MainPID` + `ControlPID` | 均为 `0` | `old_service_pid_present` |
| `Job` | 为空或 `0` | `old_service_has_job` |
| `Result` | `success` | `old_service_result_not_success` |

注意：`Result` 必须为 `success`。旧写手被 SIGTERM/SIGKILL 终止后，
systemd 的 `Result` 会变成 `signal`（且 `SubState` 不为 `dead`），
因此“进程死了”不等于“排空通过”——信号终止属于**负例，必须拒绝**，
见 `../tests/test_legacy_writer_guard.py` 第 3 项。

### 3. 进程表扫描（`ps -eo pid=,args=`）

- 进程表中不得出现 `pool.cli publish` 或 `pool-sync.sh` 的实际写手进程
  （不匹配 guard 自身进程）；出现即 `legacy_writer_process_present`。
- `ps` 输出不是列表时拒绝（`process_scan_invalid`）。

### 4. 检查本身异常必须拒绝

`systemctl` / `ps` 调用失败（非 0 返回码、OSError、超时等）时，
guard 不猜测、不放行，一律返回 `preflight_inspection_failed`。
**检查工具坏了 ≠ 旧写手没了。**

## 双重检查要求（新发布器侧）

仅靠 guard 文件本身不够，生产切换必须做到双重检查：

1. **ExecStartPre**：两个新 gate service 的 `ExecStartPre` 都要调用本 guard，
   guard 拒绝则 service 不启动；
2. **生产包装脚本**：每次生产发布包装脚本的开头也要调用本 guard，
   拒绝则不写 served 文件、不动生产订阅。

两处都拒绝时才算 fail-closed；只装一处等于留了一条无检查的写路径。

## 关键限制（必须遵守，不能据此跳过审批）

1. **只证明检查瞬间**：PR #80 的 guard 只能证明“检查那一刻旧写手已排空”，
   **不等于永久防止旧写手重启**。管理员事后手动启动旧 timer/service、
   或直接跑旧发布器命令，guard 不会、也无法阻止。
2. **新生产切换仍需**：最新快照、唯一写手保证、真实回滚验收。
   本 guard 的通过不能替代其中任何一项，也不能据此跳过审批。
3. **旧的 33/33 持锁模拟结果不得替代**本目录的隔离验证：
   `../tests/test_legacy_writer_guard.py` 的 8 项补充验证必须真实运行、
   逐项有断言（见下）。
4. **不碰生产**：本任务不实际停用旧 timer、不改生产 Surge 配置、
   不删节点、不动 blocklist / STOP / 21 钉选。所有验证均用 mock 的
   systemctl / ps 输出，在沙盒内完成。

## 隔离验证（tests/test_legacy_writer_guard.py）

8 项，全部用可注入的 mock 后端（`check(show=..., processes=...)`，
guard 逻辑不直接调系统命令，便于测试与将来接真实环境）：

1. 旧无锁写手存在时拒绝。
2. 旧写手停止并排空后通过。
3. SIGTERM / SIGKILL 负例（信号终止后状态判断）。
4. 队列中存在 systemd Job 时拒绝。
5. systemctl / ps 失败时拒绝。
6. 排空后再次手动启动旧写手的负例（复查发现写手又出现 → 拒绝）。
7. 检查失败时 HTTP served SHA 不变（guard 拒绝后不写文件；临时文件模拟）。
8. 并发竞争时不允许新旧双写（同一时刻只有一个写手被允许）。

运行方式（本目录外、仓库根测试目录执行）：

```bash
cd ~/workspace/p2p3-dual/surge-d7-acceptance
python3 -m pytest tests/test_legacy_writer_guard.py -v
```

测试日志保存于 `tests/logs/`。

## guard 的注入点（供测试与将来接真实环境）

```python
check(show=unit_state, processes=process_rows)
```

- `show(unit)`：注入一个返回 `systemctl show --property=...` 解析后 dict 的函数；
- `processes()`：注入一个返回 `ps -eo pid=,args=` 行列表的函数。
- 默认后端直接调 `/usr/bin/systemctl` 与 `/usr/bin/ps`（8 秒超时，
  非 0 返回码即抛 `RuntimeError("command_failed")`）。
