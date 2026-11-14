# D0 v2：定时发布 / 同步锁审计 + 防覆盖演练（GPT 二审第 4 项）

> 日期：2026-11-14 16:19 CST。只读核查生产单元与脚本，未改生产定时器、服务、订阅、手机配置。演练在隔离目录进行。

## 1. 结论先行

**生产 pool-publish 与 pool-sync 不共用同一把 flock 锁——因为两者都不用 flock。**

| 单元 | 定时 | 执行内容 | 用 flock？ | 锁文件 |
|---|---|---|---|---|
| pool-publish.service | 每小时 :07（`OnCalendar=*:07`，`RandomizedDelaySec=120`） | `python -m pool.cli publish` | 否 | 无 |
| pool-sync.service | 每 15 分钟（`OnCalendar=*-*-* *:0/15:00`） | `/opt/free-node-program/pool-sync.sh` | 否 | 无 |

生产防“读到半截文件”的机制不是锁，而是**原子重命名**：
- 发布写文件：`atomic_publish()` 先写 `pool-new.txt.tmp`（写完 fsync、chmod 600），把旧文件拷到 `.prev`，再 `os.rename(tmp, target)` 原子替换，最后 fsync 目录。
- 同步拷文件：`pool-sync.sh` 用 `cp SRC → .sync-new.tmp; chmod 644; mv .sync-new.tmp → DST_NEW`（mv 原子替换），旧池文件同理。

因此同步进程读到的永远是完整旧版或完整新版，不会读到半截文件。但**没有互斥**：若两个发布并发跑（systemd 定时器正常只跑一个，手动触发才可能并发），两者会交错写 `.tmp` 与 `.prev`。D0 的 flock 锁（`publish_lock.py`）是隔离实现，**尚未部署到生产**，它是为生产切换准备的、而非现状。

## 2. 核查证据（只读读取）

### 2.1 systemd 单元

`/etc/systemd/system/pool-publish.service`：
```
[Unit]
Description=Free node program: publish
After=network-online.target
Wants=network-online.target
[Service]
Type=oneshot
WorkingDirectory=/opt/free-node-program
ExecStart=/opt/free-node-program/venv/bin/python -m pool.cli publish
```

`/etc/systemd/system/pool-publish.timer`：`OnCalendar=*:07`，`RandomizedDelaySec=120`，`Persistent=true`。

`/etc/systemd/system/pool-sync.service`：
```
[Unit]
Description=Sync new pool publish to served modules dir
[Service]
Type=oneshot
ExecStart=/opt/free-node-program/pool-sync.sh
```

`/etc/systemd/system/pool-sync.timer`：`OnCalendar=*-*-* *:0/15:00`，`Persistent=false`。

两个单元均无 `ExecStartPre`、`flock`、`LockPersonality` 或任何锁相关指令。

### 2.2 脚本与代码中的 flock 检索

对生产代码做全文检索（`flock` / `fcntl` / `LOCK_EX` / `lock` 文件）：

- `/opt/free-node-program/pool/*.py`：命中均为 blocklist 语义（`blocked`、`get_blocked`、`blocked_skipped`），**无 flock**。
- `/opt/free-node-program/pool-sync.sh`：全文无 flock；同步靠 `cp → .tmp → mv` 原子替换。
- `/opt/free-node-program/pool/publish.py`：`atomic_publish()` 用 `os.rename(tmp, target)` 原子替换；`rollback()` 读 `.prev` 恢复。无 flock。

### 2.3 D0 的锁（隔离实现，未部署）

`/opt/p2p3-d0/pool/publish_lock.py`（隔离目录，600 权限）：

- 一把 flock 文件锁，供 publish / sync / rollback 共用；`fcntl.flock` 非阻塞重试 + 超时（默认 30s），锁文件内写持有者记录（pid、owner、acquired_at）；持有者死亡时内核自动释放 flock（崩溃恢复是 flock 的固有属性，v1 演练已验证：SIGKILL 后 0.0s 重新拿到锁）。
- `.prev` 保护：每次发布先把当前文件拷到 `history/pool-new-<unix-ts>.txt`，保留最新 3 份快照；`.prev` 仍维护以兼容生产 `publish.rollback()`。
- 回滚是 8 步成代码（`rollback_eight_steps`）。

该锁**只存在于隔离目录**，生产 `pool/cli.py` 未调用它。生产切换时须把锁接入 `cmd_publish` 与 `pool-sync.sh`（或由 systemd 单元统一加锁），否则生产仍无互斥。

## 3. 防覆盖演练：门禁拒绝后，下一轮 :07 不覆盖已清理文件

演练脚本 `/opt/p2p3-d0/drill_v2.py`（Part B），日志 `drill-logs-v2/safe-state-v2.json`。

方法：合成全失败探针库（5 节点，最近报告全部失败），对 44 行生产池行（只读）跑收紧后的门禁，模拟两次连续的 :07 定时发布触发。每次触发都从头重新跑门禁，与定时器调用发布的行为一致。

| 触发 | 门禁放行 | 保留行 | 是否拒绝发布 | 旧订阅 SHA | 与首次一致 |
|---|---|---|---|---|---|
| 第 1 次（模拟 :07） | 0 | 0 | 是 | `1360ab7ca83b` | 是 |
| 第 2 次（模拟下一轮 :07） | 0 | 0 | 是 | `1360ab7ca83b` | 是 |

结论：门禁拒绝后，下一轮定时触发仍被门禁拦截，旧文件 SHA 始终不变。**通过。**

**诚实边界：** 这是隔离演练对门禁逻辑的证明。生产上门禁尚未部署，生产 :07 发布目前仍按旧逻辑跑（不读 probe.db），所以生产现状是“下一轮 :07 会按旧逻辑重写”。门禁成为生产行为的前提是 GPT 批准 + 完整备份 + 生产切换（把门禁卡点接入 `cmd_publish`）。在切换完成前，不要宣称生产已被保护。

## 4. 对 GPT 的待确认事项

- 生产切换时，是否接受 D0 的 flock 锁接入方式（`cmd_publish` 与 `pool-sync.sh` 共用同一把锁），还是只依赖现有的原子重命名？
- 若只依赖原子重命名：需确认手动并发触发发布时 `.tmp` / `.prev` 交错的风险是否可接受（定时器本身不会并发）。
- 门禁拒绝发布时，旧订阅继续服务（含未验证/失败节点）只是“保守保持”，不是合规池。零合格超过多久应告警 / 切应急组，需机主定夺（见 safe-state-drill-v2.md 第 6 节）。

## 5. 证据文件

| 文件 | 说明 |
|---|---|
| `drill-logs-v2/safe-state-v2.json` | 演练完整 JSON 日志（Part A/B/C/D/E，600 权限） |
| `/opt/p2p3-d0/drill_v2.py` | 演练脚本（VPS 隔离目录，600 权限） |
| `/opt/p2p3-d0/pool/publish_lock.py` | D0 flock 锁实现（隔离目录，未部署） |
| `safe-state-drill-v2.md` | 零合格安全态与 DIRECT 证据文档 |
| `candidate-v2.txt` / `candidate-v2.json` | 任务 3 的新候选集（15 条） |
