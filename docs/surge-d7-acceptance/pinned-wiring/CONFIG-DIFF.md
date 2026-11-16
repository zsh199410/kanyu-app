# 21 钉选取消永久豁免：生产接线变更方案（Issue #73，D4）

> 状态：变更方案 + 隔离验证通过。**生产未动**（`config.yaml` 未改、
> 定时器未改、订阅未改）。执行须 GPT 批准 + 机主授权，与 systemd
> 切换（`systemd/switch-runbook.md`）同一窗口做。
> 本文件不含任何订阅内容、节点行、密码、令牌、原始 IP。

## 0. 生产现状（2026-11-15 07:50 实测，只读）

| 项目 | 实测值 |
|---|---|
| 当前发布文件 `/opt/free-node-program/publish/pool-new.txt` | 65 行，SHA256 前缀 `1bd3fec8b92b`（07:07 定时发布） |
| 其中钉选行 | **21 行**（按 `(protocol, host, port)` 匹配钉选表；0 行被拉黑，0 行不可解析） |
| 其中轮换行 | 44 行 |
| 钉选表 `pinned`（`data/pool.db`） | 25 行，全 trojan（21 行在发布文件内，4 行为仅 DB 钉选） |
| `config.yaml` | `pinned_protected: true`（450 字节） |
| `publish_fresh_hours` | 24 |

## 1. 豁免的真实机制（不是配置项）

`pinned_protected: true` 在 `config.yaml` 第 4 行，但**没有任何代码
读取它**（`pool/*.py` 全文 grep `protected` 零命中）。豁免是
`pool/cli.py::cmd_publish` 的结构：

```python
lines = [pinned file lines not in blocklist]   # 无条件拼入
      + db_pinned_lines                         # 无条件拼入
      + kept_old + new_lines                    # 轮换才过 VPS 门
```

- 钉选行不查任何测试结果、不查新鲜度、不查手机证据；
- 超上限时只 drop 轮换（`keep_pinned` 恒保留）；
- Winner-clean（Scheme B）只动轮换：“只动轮换，钉选永不动”。

结论：**只改 `pinned_protected` 改不了任何行为**。消除豁免的唯一
办法是让发布走 D3 门禁（门禁对钉选行与轮换行一视同仁，只认新鲜
同一版本原生证据）。配置项的改动是记账 + 防未来代码误读。

## 2. 变更内容（切换窗口内执行）

### 2.1 配置 diff（唯一改生产配置的一处）

```diff
--- /opt/free-node-program/config.yaml
+++ /opt/free-node-program/config.yaml
@@
-pinned_protected: true
+pinned_protected: false
```

含义：钉选不再受保护；钉选行与轮换行同过 D3 双门禁。改完后
`config.yaml` 其余 16 个顶层键不动。

### 2.2 定时器接线（与 systemd 切换同一窗口）

- 停用：`pool-publish.timer`、`pool-sync.timer`
  （`pool.cli publish` 的无条件钉选拼装 + `pool-sync.sh` 的盲复制
  同时停用——豁免的两个载体一起下线）。
- 启用：`pool-gate-publish.timer`（:07）、`pool-gate-sync.timer`
  （:00/:15/:30/:45），走 `systemd/gate-publish.sh` /
  `systemd/gate-sync.sh` + D3 `pool.publish` / `pool.sync`。
- 顺序见 `systemd/switch-runbook.md` Phase 3（冻结源版本）→
  Phase 5（切换）。钉选行第一次被门禁是在切换后的第一个 :07：
  只有在冻结版本的原生测速里通过且 <300ms 的钉选行才会被发布。

### 2.3 不改的东西

- 钉选表（`pinned`，25 行）不动；钉选文件不动；`blocklist` 不动。
- 轮换准入门（VPS 握手 ≤300ms、通过率 ≥0.5、24h 新鲜）不动——
  它仍是组装候选的门，D3 原生门禁是发布前的最后一道门。
- 旧单元与旧同步脚本保留在原地（disabled），供回滚。

## 3. 隔离验证（已跑，见 tests/test_d4.py）

验证在隔离 workdir 用 D3 真实入口（`run_publish` / `run_sync`）
跑，候选集按生产结构拼：21 条“钉选”（14 条原生通过 + 7 条原生
失败）+ 23 条“轮换”（其余 fixture 行）。

| # | 证据状态 | 预期 | 实测 |
|---|---|---|---|
| 1 | 新鲜原生通过（<300ms，1 小时前） | 仅 14 条钉选发布，7 条失败钉选 + 23 条轮换拒绝 | 发布 14 行，全为钉选（`test_pinned_admitted_only_on_fresh_evidence`） |
| 2 | 证据过期（25 小时前） | 全部拒绝，零发布 | rc=1 `phone_gate_zero_qualified`，无发布文件 |
| 3 | 钉选原生失败 | 全部拒绝，零发布 | rc=1 `phone_gate_zero_qualified`，无发布文件 |
| 4 | 证据属于另一版本 SHA | 全部拒绝，零发布 | rc=1 `phone_gate_zero_qualified`，无发布文件 |
| 5 | 混合：10 条钉选通过、4 条失败 | 仅 10 条钉选发布 | 发布 10 行，全为钉选 |
| 6 | 记录缺 5 条钉选的结果行 | 缺证据的 5 条拒绝，其余 9 条发布 | 发布 9 行 |
| 7 | 旧式未门禁源文件（含 21 条钉选，无 sidecar）进 sync | sync 拒绝，served 文件不动 | rc=1，served SHA 不变 |

本地：7/7 通过（Python 3.12.3）。VPS 日志见
`docs/pinned-wiring-log-vps.json`（随 D4 演练同步更新）。

## 4. 切换后预期（供验收对照）

- 切换后第一个 :07：发布行数 = 冻结版本原生测速里 <300ms 的
  钉选行 + 轮换行（轮换行还须同时满足“在候选文件里”）。
  若冻结版本测速里钉选全军覆没，发布行数可能为 0——此时门禁
  拒绝、旧 served 文件保留（安全态），不是故障；须机主重新测速。
- 钉选行数不再恒定 21：每版发布里钉选行数 = 该版本原生通过的
  钉选行数，随测速结果波动。
- 钉选表 25 行不动：未通过的钉选行只是本次不发布，不是删除；
  下次测速通过即恢复。

## 5. 回滚（与 systemd 回滚同一窗口，见 switch-runbook.md §9）

```bash
# 5.1 停门禁定时器，恢复旧定时器（豁免随旧 publish 恢复而恢复）
systemctl stop pool-gate-publish.timer pool-gate-sync.timer
systemctl disable pool-gate-publish.timer pool-gate-sync.timer
systemctl enable pool-publish.timer pool-sync.timer
systemctl start pool-publish.timer pool-sync.timer
# 5.2 恢复配置记账
sed -i 's/^pinned_protected: false/pinned_protected: true/' \
  /opt/free-node-program/config.yaml
grep pinned_protected /opt/free-node-program/config.yaml
# 要求输出 pinned_protected: true
# 5.3 立即用旧同步脚本恢复一次服务文件
/opt/free-node-program/pool-sync.sh
sha256sum /opt/free-node-program/publish/pool-new.txt \
  /opt/surge-bridge/modules/pool-new.txt
# 要求两者 SHA 相同
# 5.4 手机验收：刷新订阅，成员数回到切换前（65 行量级）；原生整组
#     测速确认与切换前一致
```

回滚后门禁代码与状态目录保留在原地（`/opt/pool-gate/` 不动），
供复盘与再次切换。
