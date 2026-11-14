# D0 v2：零合格安全态演练 + DIRECT 证据（GPT 二审第 3、4 项）

> 日期：2026-11-14 16:19 CST。隔离演练，未改生产目录、生产订阅、生产定时器、手机配置。演练脚本 `/opt/p2p3-d0/drill_v2.py`，日志 `/opt/p2p3-d0/drill-logs-v2/safe-state-v2.json`（本地副本 `drill-logs-v2/safe-state-v2.json`）。
>
> 关键结论先行：
> - 门禁全失败时拒绝发布、旧订阅 SHA 不变；连续两次模拟 :07 定时触发均被门禁拦截，SHA 始终不变。**A、B 均通过。**
> - 死代理对照失败（curl rc=7，http 000），直接取回 204（rc=0，http 204）。**C、D 均通过，证明演练传输无 DIRECT 回退。**
> - 正向 204 经节点出口：**v2 未能重证。** 当前门禁放行的 15 条全是 trojan，trojan 在 VPS 出口上全部握手失败（服务端 HTTP 400 拒绝，已用 香港36 手动复核）。池子里已无 vmess 行（44 行中 0 条 vmess），probe 库中 3 条 vmess 全部 retired。**v1 的 vmess 204 证据（78.5ms，exit-verify-full.json）仍然成立，但所用的 vmess 节点现已退役。** 下方第 5 节给出 vmess 节点重新入池后重证的精确步骤。

## 1. 演练环境与方法

| 项 | 值 |
|---|---|
| 演练脚本 | `/opt/p2p3-d0/drill_v2.py`（600 权限，隔离目录） |
| 生产池（只读） | `/opt/free-node-program/publish/pool-new.txt`，44 行，SHA256 `1360ab7ca83b75427a616c03c84bcdf69bd9a0af3aee69befd849636db9421d6` |
| 门禁版本 | 收紧后版（`ts <= now`，`ORDER BY ts DESC, id DESC`），任务 1 完成版 |
| 探针 URL | `https://www.gstatic.com/generate_204`（与手机探针脚本同一 URL） |
| sing-box | `/usr/local/bin/sing-box` 1.13.14 |
| 旧订阅副本 | 演练工作目录内的生产池副本（隔离路径，不发布到生产地址） |

日志只含行数、SHA256 前 12 位、名字、耗时、返回码。不含节点行、主机、密码、URI、token、订阅 URL。

## 2. Part A：门禁全失败 → 拒绝发布，旧订阅保留

方法：构造合成探针库（5 个节点，最近一条报告全部为失败，`success=0`，`error="HTTP request timeout"`，`interface=pdp_ip0`），对 44 行生产池行跑门禁。

| 检查 | 结果 |
|---|---|
| 门禁放行指纹数 | 0 |
| 门禁保留行数 | 0（44 行全被挡下） |
| 门禁拒绝原因 | `latest_failed: 5` |
| 发布是否拒绝 | 是（零合格，不调用 atomic_publish，不写目标文件） |
| 旧订阅 SHA 前后 | `1360ab7ca83b` → `1360ab7ca83b`，**不变** |

结论：零合格时门禁拒绝发布，旧订阅原样保留。**通过。**

## 3. Part B：定时防覆盖演练（两次模拟 :07 触发）

方法：模拟两次连续的 :07 定时发布触发。每次触发都从头重新跑门禁（fresh `load_verified`），与定时器调用 `python -m pool.cli publish` 的行为一致。两次之间旧文件不动。

| 触发 | 门禁放行 | 保留行 | 是否拒绝 | 旧订阅 SHA | 与首次是否一致 |
|---|---|---|---|---|---|
| 第 1 次（模拟 :07） | 0 | 0 | 是 | `1360ab7ca83b` | 是 |
| 第 2 次（模拟下一轮 :07） | 0 | 0 | 是 | `1360ab7ca83b` | 是 |

结论：门禁拒绝后，下一轮定时触发仍被门禁拦截，旧文件 SHA 始终不变，**不会**被空/坏订阅覆盖。**通过。**

补充说明（见 timer-lock-audit.md）：生产上门禁尚未部署（D0 仍在隔离目录），所以这只是隔离演练对门禁逻辑的证明，不是生产现状。生产切换后，门禁将作为 `cmd_publish` 的卡点，上述行为即为生产行为。

## 4. Part C/D：DIRECT 对照（死代理 + 直接取回）

| 检查 | 方法 | 结果 |
|---|---|---|
| C 死代理对照 | curl 经 SOCKS5 代理 `127.0.0.1:45991`（该端口无任何监听）取 generate_204 | curl rc=7，http=000，**失败**。若传输有 DIRECT 回退，该请求会经直连成功——它没有。 |
| D 直接取回对照 | 直接 curl（不经代理）取同一 URL | curl rc=0，http=204。证明 C 的失败是死代理所致，不是网络或目标站问题。 |

结论：演练传输无 DIRECT 回退；死代理时请求失败而非悄悄走直连。**C、D 均通过。**

## 5. Part E：正向 204 经节点出口（v2 未能重证，原因如实说明）

方法：取当前门禁放行的第一条（美国9 🇺🇸，trojan，指纹前缀 `dfbd0c105a35`），用 scratch sing-box 起一个**仅含该节点出站**的配置（无 direct 出站，`route.final=node`），经它取 generate_204。

| 检查 | 结果 |
|---|---|
| 节点 | 美国9 🇺🇸，trojan，`dfbd0c105a35` |
| sing-box 配置 | 仅 1 个 trojan 出站，`route.final=node`，无 direct 出站 |
| curl 结果 | rc=97，http=000，71.8ms |
| sing-box 日志 | `connection: open connection to www.gstatic.com:443 using outbound/trojan[node]: unexpected HTTP response status: 400` |

**为什么失败：** trojan 服务端以 HTTP 400 拒绝 VPS 出口的握手。这不是配置错误，也不是门禁缺陷——同一问题在 2026-11-14 10:44 已确认（12 条手机验证通过的 trojan 在 VPS 上全部握手失败），本次又用 香港36 🇭🇰 手动复核（同样 400）。trojan 节点的最终验收只能在手机原生测速上做，VPS 出口不能代替。

**为什么 v2 没有 vmess 可试：** 当前门禁放行的 15 条**全部是 trojan**（见 candidate-v2.txt）。生产池 44 行中 **0 条 vmess**。probe 库中仅有的 3 条 vmess（美国21、未知、加拿大2）**全部 retired**。v1 演练用的 vmess 节点（204，78.5ms，exit-verify-full.json）现已退役。

**结论：** v2 的正向 204 腿未能重证。这是一个**已查明的环境限制**（trojan 不可在 VPS 出口验证 + 当前无 vmess 可用），不是门禁逻辑问题。v1 的正向证据仍然成立，但其节点已退役，需在 vmess 节点重新入池并获门禁放行后重证。

**重证的精确步骤（vmess 节点重新入池后）：**
1. 确认 `candidate-v2.txt`（重跑任务 3）中出现至少 1 条 vmess 行。
2. 在 VPS 上跑：`cd /opt/p2p3-d0 && python3 exit_verify.py --max-attempts 3 --port-base 45200 --log-name exit-verify-v3`。
   该脚本自动取门禁放行行、起 scratch sing-box（无 direct 出站）、取 generate_204，并做死代理与直接取回对照。
3. 通过标准：至少 1 条 vmess 经节点出口取回 HTTP 204，且死代理对照失败（rc != 0，http 000）、直接取回 204。
4. 若 trojan 仍为唯一协议，跳过正向腿并如实记录（同本次），不要用 trojan 的失败冒充“传输有问题”。

## 6. 本次演练未证明的事（诚实边界）

- **未证明 Surge 正式策略组在全失败时的行为。** 演练证明的是 VPS 侧门禁与传输逻辑，不是手机 Surge 的 `smart` 组在组员全失败时是否落 DIRECT。Surge 侧的行为只能在手机上实测（或由机主授权后改分流并实测）。D0 不擅自改业务分流。
- **未证明生产切换后的行为。** 门禁尚未部署到生产；生产 :07 定时发布目前仍按旧逻辑跑（不读 probe.db）。本演练证明的是隔离门禁的逻辑，生产切换须经 GPT 批准 + 完整备份后进行。
- **未证明单节点 / SUBSTITUTE 场景。** 本次只做了全失败（0 合格）场景。单节点发布与 SUBSTITUTE 行为未单独演练——v1 已有单节点演练（gate-single.json，通过），SUBSTITUTE 属于 Surge 手机侧配置，不在 VPS 演练范围内。

## 7. 证据文件

| 文件 | 说明 |
|---|---|
| `drill-logs-v2/safe-state-v2.json` | 本次演练完整 JSON 日志（600 权限） |
| `/opt/p2p3-d0/drill_v2.py` | 演练脚本（600 权限，VPS 隔离目录） |
| `/opt/p2p3-d0/drill-logs-v2/safe-state-v2.json` | 同上，VPS 侧 |
| `drill-logs-v2/exit-verify-v2.json` | 2026-11-14 16:17 的 exit_verify.py 全量运行日志（3 次 trojan 尝试全部 rc=97/000，verdict=FAIL，原因同第 5 节） |
| `candidate-v2.txt` / `candidate-v2.json` | 任务 3 的新候选集（15 条，全 trojan） |
