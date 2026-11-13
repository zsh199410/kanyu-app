# Issue #73 — Surge 手机可信观测与节点池服务（隔离试验版）

> 2026-11-13。**没有修改线上 VPS、Surge 或 `main` 分支。**
> 统计已修正：**29 Trojan + 1 VMess + 17 SS = 47**。

## 与现有系统的关系

此目录不是未知旧代码的“补丁”。仓库 `zsh199410/kanyu-app` 是 iOS 应用仓库，未找到节点池服务端源代码。这里提供 **Python 3.10+ 标准库独立最小可运行参考服务**及 **Surge 只读缓存观察脚本**。Muse 拿到原 VPS 代码后，需要把候选数据映射接入，不得直接覆盖现有发布目录。

| 部分 | 已实现 | 尚需线上验证 |
|---|---|---|
| P0 | 手机 `$httpAPI(GET, /v1/policy_groups/test_results)`、HTTPS Bearer 回传、严格校验、SQLite 去重、只上传已识别且有时间戳的逐节点结果 | 手机实际 JSON 结构、真实字段含义、测试时间戳、蜂窝网络识别、后台定时执行与上传连通性 |
| P1 | 钉选与轮换统一以最近 **24h** 手机合格记录准入，取消永久特权 | 21 条钉选的真实手机结果 |
| P2 | 导入 VPS 握手成功率 / 真正的代理 HTTP 成功率 / 延迟 P90 / 24h 样本数，`status` 标注 PASS/FAIL/UNKNOWN | 现有 sing-box 检测产生真实 `http_ok` 的接入；暂不以 VPS PASS 代替手机验证 |
| P3 | `PENDING -> VERIFIED -> PROBATION -> QUARANTINED -> RETIRED` 状态、排除无验证节点、原子输出、无有效节点不覆盖旧发布 | 72 小时在真实重庆移动网络上验收、故障回滚、历史结果的生命周期 |
| P4 | 没有默认接入 VLESS | iOS Surge >= 6.0.0 后小批灰度、转换格式和实际测试 |

**根本限制**：只从 `url-test` **已有缓存**读结果，并不保证每个节点都有最近一次测试。若接口不提供逐节点可判定延迟与真实测试时间，脚本选择 **不上报**，不能假装实现 100% 自动终审。第一次接入手机真实 JSON 之前 P0 不可宣称已完成。

## P0 手机脚本

1. 用 `surge-report.js`，把 `ENDPOINT` 指向有可信 TLS 的 `/api/v1/phone`，`TOKEN` 填入 32 位以上随机令牌，`GROUP` 保持 `免费节点池`，不要公开这些机密。
2. **先人工单次运行**，配合只读 `$httpAPI(GET,...)` 检查真实 JSON。不知道输出结构前，允许它显示 `no recognized fresh per-node results`，但不会伪造成功。
3. 确认记录含每个节点名称、真实延迟（单位毫秒）、**缓存测试的真实发生时间**、成功状态后，再调整 `records()` 对真实结构解析。
4. 自动运行方式用现有 Surge 的定时任务配置复用，不增加任何常驻测速组。建议脚本频率 30–60 分钟且不触发 `POST /v1/policy_groups/test`。
5. 脚本仅在可证明蜂窝连接时上传。iOS 隐私限制导致网络不能准确识别时标 `unknown` 并停止，而不是误记成重庆移动。如果经真实设备验证了可靠判别方式再调整。

参考文档：<https://manual.nssurge.com/tools/http-api.html>、<https://manual.nssurge.com/scripting/api.html>。

## P1–P3 服务端安装／回滚（**先在测试目录**）

```bash
# 在能控制的 Ubuntu/Debian VPS 上，Python >= 3.10
python3 -m venv .venv
. .venv/bin/activate
export SURGE_REPORT_TOKEN="$(python3 -c 'import secrets; print(secrets.token_urlsafe(32))')"
# 将令牌安全传给手机，不能写入公开仓库。生产环境从 root-only 环境文件/秘密管理器读取。
python3 pool.py --db ./trial.sqlite3 import ./candidates.example.json
python3 pool.py --db ./trial.sqlite3 serve --host 127.0.0.1 --port 8765
# 另一个终端：在确认有手机记录后再运行
python3 pool.py --db ./trial.sqlite3 status
python3 pool.py --db ./trial.sqlite3 publish ./trial.surge.list
```

将 `127.0.0.1:8765` 放在现有 Nginx/Caddy HTTPS 反向代理之后；不要直接在公网暴露明文 HTTP。保留现有生产订阅，不要自动切换。**上线前先备份旧订阅、数据库及生成脚本**。将正式发布文件只读对比并抽查 `Surge` 能正常解析，再通过原现有发布系统替换，能立即回滚到备份。

`candidates.example.json` 只是伪造示例，替换为现有采集程序的 JSON 导出；不要把真实节点的密码提交到 GitHub。

### 候选数据约定

每个候选必须提供 `name`、完整 `line`、`class` (`pinned`/`rotating`) 和真实的 `vps_checks`；每条检测包含 Unix 秒 `ts`、布尔 `handshake_ok`、毫秒 `latency_ms`、布尔 `http_ok`。这里的 `http_ok` 必须是**经该代理转发的目标 HTTP 成功**，不是仅与代理服务器握手。连续时间窗只评估最近 24h，少于 3 次返回 `UNKNOWN`。具体阈值在 72 小时手机结果统计后再调。

### 当前状态规则

- 没有手机观测：`PENDING`，不入生产订阅。
- 最新手机测试通过、蜂窝、延迟严格低于 300ms、最近 24 小时：`VERIFIED`，准入。
- 新结果失败、网络非蜂窝、或过期：`PROBATION`，暂停发布但保留库存。
- 在最新成功之后连续两次失败：`QUARANTINED`。
- 在最新成功之后连续三次失败、且失败跨度至少 30 分钟：`RETIRED`。禁止仅因美国 VPS 的一次失败退休节点。
- 真正持续失败且没有前置成功记录才可退休；未知不等于死亡。旧版脚本只传胜者也无法给所有其它节点判死。
- 若没有已验证节点，**拒绝更新发布文件**，保留旧文件且发出告警。注意保留旧文件并不保证旧节点仍能用；`url-test` 全部失效或空组时可能回退 `DIRECT`，必须在生产单独设置拒绝式防直连防护。仅靠脚本无法满足“一个生产组 + 必然不会 DIRECT”的全部要求。

**重要的探索矛盾：** 如果强制生产列表只允许已手机证实的节点，同时禁止新增测速组、手机单独测速，那么新节点永远不会获得首次手机验证。需明确授权小批次试用候选（例如 3 个、独立短时窗口），或者允许手机受控的按需探测；否则只能维护已经成功过的节点，而无法持续扩池。

## 测试

```bash
python3 -m unittest discover -s tests -v
node --check surge-report.js
```

测试只覆盖本地状态机，不覆盖真实手机 API、重庆移动网络、真实节点协议质量或 VPS 部署。

## SSH 密钥被拒的恢复顺序（不靠商家网页控制台）

1. **首先核查本地认证错误**（Windows PowerShell）：

```powershell
ssh -V
ssh-add -l
ssh -vvv -o IdentitiesOnly=yes -o PreferredAuthentications=publickey -i "$env:USERPROFILE\.ssh\id_ed25519" root@VPS_IP
ssh-keygen -y -f "$env:USERPROFILE\.ssh\id_ed25519"
```

检查私钥路径、文件权限、密钥类型、目标 IP 和端口，`root` 是否实际账号，是否在对应用户的 `authorized_keys` 里。不要把私钥或完整 debug 日志贴到公开 Issue；必要时删除 IP、用户名、用户名路径、指纹。试探其它**已有授权**账号/端口或旧机器 SSH agent、VS Code/终端中尚存的连接，不能尝试绕过权限验证。

2. **存在有效会话或其它授权通道时**：通过该会话修复对应用户的 `~/.ssh/authorized_keys`、权限（家目录/`.ssh`/文件所有权、`700`/`600`）及 `sshd` 设置；先 `sshd -t`，保留现有连接，再开第二个连接验证，避免自锁。
3. **有已部署云主机代理、自动化、备份或服务商 API 授权**：可经这些既有管理通道注入新公钥、恢复快照或使用离线磁盘修复；API 仍是商家**控制平面**，只是无需网页控制台。
4. **没有有效 SSH 会话、备用授权用户、管理代理或云服务 API**：不能靠公网“找回”私钥或绕过 SSH 认证。只能通过服务商救援模式/API/支持工单恢复，或把程序迁到另一台你有权限的服务器。千万不要重装导致订阅源、数据库与令牌丢失。

## VLESS（待确认 iOS 版本后才开始）

Surge 官方文档列明 iOS 6.0.0+ 支持 `vless` / REALITY。只试 RAW+REALITY+Vision（示例在官方文档），要求 UUID、SNI、Reality 公钥、short-id、flow 正确；不支持 XHTTP / HTTPUpgrade / mKCP / VLESS Encryption。**不允许把 sing-box 任意 VLESS 链接简单替换成 Surge 行**。初期 3–5 个候选、单独统计，不全量切换，保留当前回滚版本。

官方：<https://manual.nssurge.com/policies/vless.html>。
