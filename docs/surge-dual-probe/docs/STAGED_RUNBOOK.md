# 分阶段部署手册（Staged Runbook）— #73 双通道探针补丁 B①

## P0 补充：同批次回滚证据（GPT 直接修复）

部署 Stage 2 **在修改线上任何文件前**，一次性备份原版 service、nginx、托管脚本和 SQLite WAL-safe DB 快照，并记录同一个发行 ID、四份备份的真实 SHA256 至服务器私有 `/opt/probe-service/config/dual-release.manifest`（权限 600）。Stage 3/5 必须匹配此 manifest，不能按“最新 .bak 文件”跨批次拼接恢复。若有正在进行的 release manifest，下一次 Stage 2 直接拒绝，需先完成相应回滚或另行受控收口。

`tools/rollback_dual.sh` **不接受脱敏版 PR 中的旧脚本 SHA**，也不硬编码 nginx 文件/探针 Host：均读取 Stage 2 私有 manifest 与同机 `deploy-render.conf`。回滚前先验证全部原文件 SHA、完整备份和 DB `integrity_check`，不满足则一字不动；通过后按“脚本→nginx→服务”逆序恢复，检验 Wi-Fi 404 与蜂窝 200，始终保留 Wi-Fi 数据表。成功后 archive manifest。

> PR #82 脱敏目录中只有代码，不包含真实配置。任何用户/执行器不得将仓库脱敏 SHA 当作生产 SHA；本段不代表批准生产部署。Stage 2/3/4/5 仍需独立审定和隔离演练。


> 来源：Issue #73 评论 #6938432964（GPT 增量复核，五条精确门禁之 5）
> 与 PR #82 评论 #6940445042（GPT 逐文件终审，P0-3：分阶段脚本与
> 手册必须一致——脚本按 stage 参数独立执行，阶段之间停下等确认；
> 阶段 4 不要求生产 Wi-Fi 回传）。
> 前置：必须先拿到 GPT 的部署批准；否则一律不执行。
> 本手册的每一步都有“记录什么、通过标准、失败怎么办”。
> 占位符说明：`<service_sha>` / `<script_sha>` 为 Draft PR 里核对过的
> 完整 SHA256（见 `docs/SHA_MANIFEST.md`）；`SEG` 从生产配置文件现读，
> 手册正文不写真实随机路径段。

部署脚本 `tools/deploy_dual.sh` 按 `stage` 参数独立执行，一次只做
一个阶段，做完即停（无“一键跑到底”模式）。每阶段的命令与验证见下。

## 0. 准备（一次）

```bash
SEG="$(cat /opt/probe-service/config/probe-path.txt)"
SERVICE_FILE=<补丁服务文件路径>   # 来自已审 Draft PR
SCRIPT_FILE=<补丁脚本文件路径>     # 来自已审 Draft PR
# 核对 SHA（必须与 SHA_MANIFEST 一致，否则停）
sha256sum "$SERVICE_FILE" "$SCRIPT_FILE"
# 私有渲染配置（600 权限，服务器本地，永不进 PR、永不打印）：
#   /opt/probe-service/config/deploy-render.conf，内容两行：
#     PROBE_HOST=<真实探针主机>
#     NGINX_CONF=/etc/nginx/conf.d/<vhost>.conf
# 由部署方按现有生产值一次写好；部署脚本阶段 3/5 靠它取值，
# 缺失即 fail-closed。真实主机与路径段绝不写入任何公开文件。
# 预部署备份（部署脚本每步也会再备一份；DB 备份用 SQLite backup API，
# 不用 cp——服务跑在 WAL 模式，单文件复制可能丢未 checkpoint 的提交）
cp /opt/probe-service/probe_service.py /root/probe-service.py.pre-dual
python3 tools/backup_db.py /opt/probe-service/data/probe.db /root/probe.db.pre-dual
cp /etc/nginx/conf.d/<nginx-vhost>.conf /root/<nginx-vhost>.conf.pre-dual
cp /opt/surge-bridge/modules/probe-task.js /root/probe-task.js.pre-dual
```

每阶段记录四项：(a) 真实 HTTP 状态；(b) 蜂窝表/统计 SHA；
(c) Wi-Fi 单独写入；(d) 失败关闭（任一不通过即停，不进下一阶段）。

蜂窝基线快照命令（每阶段前后各跑一次，对比）：

```bash
# (b) 蜂窝表 SHA：只读导出 probe_reports + probe_nodes 后算 SHA
python3 - <<'PY'
import sqlite3, json, hashlib
c = sqlite3.connect('/opt/probe-service/data/probe.db')
out = {}
for t in ('probe_reports', 'probe_nodes'):
    out[t] = [list(r) for r in c.execute(f'SELECT * FROM {t} ORDER BY 1, 2')]
print('cell_tables_sha=' + hashlib.sha256(json.dumps(out, sort_keys=True).encode()).hexdigest())
PY
# (b) 蜂窝统计快照：只取稳定字段（avg_alive_seconds 随时间变，不取）
curl -s -H "X-Probe-Action: stats" "http://127.0.0.1:18081/$SEG" \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print({k: d[k] for k in ('total','states','verified','tested_hour','tested_day','qualified_day')})"
# (c) Wi-Fi 行数
python3 -c "import sqlite3; c=sqlite3.connect('/opt/probe-service/data/probe.db'); print('wifi_rows=', c.execute('SELECT COUNT(*) FROM probe_reports_wifi').fetchone()[0])"
```

## 阶段 1 — 基线（旧服务 / 旧脚本）

目的：确认出发状态可度量；不改任何文件。

```bash
sudo bash tools/deploy_dual.sh 1
# 脚本自带验证：cellular tasks 200、wifi tasks 404、蜂窝表 SHA 与统计快照
# 记录：蜂窝表 SHA + 统计快照 + Wi-Fi 行数（上面“基线快照命令”）
```

通过标准：cellular tasks 200；wifi tasks 404（nginx 无此 location，
且旧服务本身无此路径）；基线快照已记录。

## 阶段 2 — 先换服务

```bash
sudo bash tools/deploy_dual.sh 2 "$SERVICE_FILE" <service_sha>
# 脚本只做阶段 2：核对服务 SHA → 备份服务文件 → SQLite backup API
# 快照 probe.db（+ integrity_check）→ 换服务 → 重启 → cellular tasks 200。
# 做完即停，不进阶段 3。
```

验证：

```bash
curl -s -o /dev/null -w "cellular tasks: %{http_code}\n" -H "X-Probe-Action: tasks" "http://127.0.0.1:18081/$SEG"
curl -sk -o /dev/null -w "wifi tasks (public): %{http_code}\n" -H "Host: <probe-host>" -H "X-Probe-Action: tasks" -H "X-Probe-Network: wifi" "https://127.0.0.1:8443/$SEG-wifi"
# 手机旧脚本下一整点仍正常回传蜂窝结果（只读观察，不干预）
```

通过标准：cellular tasks 200；旧脚本形状（无 network_type、无绑定字段）
仍被接受（兼容例外：旧版 cellular 客户端无 batch 字段，仍可入库；
不得声称所有蜂窝记录都已强绑定 SHA）；wifi 仍 404；蜂窝表 SHA 只因
预期的蜂窝回传而变，统计口径与阶段 1 一致。失败 → 恢复阶段 1 的
服务备份并重启，回阶段 1 重新记录基线。

## 阶段 3 — 再加 nginx

```bash
sudo bash tools/deploy_dual.sh 3
# 脚本只做阶段 3：备份 nginx 配置 → 插入 -wifi location（路径与主机
# 来自私有渲染配置）→ nginx -t → reload → wifi tasks 200。
# 做完即停，不进阶段 4。
```

验证：

```bash
curl -sk -o /dev/null -w "wifi tasks (public): %{http_code}\n" -H "Host: <probe-host>" -H "X-Probe-Action: tasks" -H "X-Probe-Network: wifi" "https://127.0.0.1:8443/$SEG-wifi"
curl -s -o /dev/null -w "cellular tasks: %{http_code}\n" -H "X-Probe-Action: tasks" "http://127.0.0.1:18081/$SEG"
```

通过标准：wifi tasks 200（且响应 info 带 `pool_sha` 与 `batch_id`）；
cellular tasks 200；蜂窝表 SHA 与统计快照与阶段 2 末一致
（只加 location，不应有任何蜂窝写入）。失败 → 恢复 nginx 备份，
`nginx -t` + reload，回阶段 2。

## 阶段 4 — 新旧脚本兼容（不换文件）

目的：旧脚本（蜂窝）与新服务 + 新 nginx 同时在线时互不干扰。
本阶段不换文件；手机仍跑旧脚本。

```bash
sudo bash tools/deploy_dual.sh 4
# 脚本只做阶段 4 的 HTTP 门禁：cellular tasks 200、wifi tasks 200
#（带 batch）、头/路径不一致 400、蜂窝表 SHA 记录。做完即停。
```

验证项（每项都要有真实记录）：

1. 旧脚本蜂窝回传仍被接受（下一整点后 cellular `tested_day` 增长）。
2. Wi-Fi 端点可用：wifi tasks GET 返回 200 且 info 带 `pool_sha` 与
   `batch_id`（隔离验证，非生产手机回传——手机仍跑旧脚本，
   不会调 Wi-Fi 端点；隔离矩阵里这一步由测试 harness 扮演新脚本，
   不是生产流量）。
3. Wi-Fi 操作前后蜂窝表 SHA 不变、蜂窝统计快照不变
   （上面“基线快照命令”前后对比）。
4. 异常流量不影响蜂窝：错通道、头/路径不一致、畸形体、重复回传
   均被拒绝（HTTP 400 / `duplicates` 计数），蜂窝 tasks 仍 200
   （隔离矩阵已覆盖；生产只做头不一致 400 的只读检查，不发
   伪造回传污染生产库）。

**本阶段不要求生产 Wi-Fi 回传**：手机还没换新脚本，不可能有
生产 Wi-Fi 回传；要求它逻辑不成立。生产 Wi-Fi 回传留待阶段 5。

通过标准：四项全部满足。任一失败 → 停在阶段 3（nginx 已加、
服务已换、脚本未换），按需回滚到阶段 2。

## 阶段 5 — 最终换脚本（私有渲染 + 上线）

```bash
sudo bash tools/deploy_dual.sh 5 "$SCRIPT_FILE" <script_sha>
# 脚本只做阶段 5：核对脱敏脚本 SHA → 私有渲染（真实 host/path 来自
# 私有渲染配置；占位符未替换干净即 fail-closed）→ 重算 CLIENT_VERSION
#（按渲染后内容）→ 部署渲染后脚本 → 按渲染产物 SHA 核验（不用脱敏
# GitHub SHA 当部署产物 SHA）。手机下次整点自动取新版；不催、不手动触发。
```

验证（下一整点后）：

```bash
# Wi-Fi 与蜂窝两通道各有回传，且结果带 batch_id + snapshot pool SHA
curl -s -H "X-Probe-Action: stats" -H "X-Probe-Network: wifi" "https://127.0.0.1:8443/$SEG-wifi" | head -c 600
curl -s -H "X-Probe-Action: stats" "http://127.0.0.1:18081/$SEG" | head -c 600
# 蜂窝统计快照与阶段 4 末对比：只因预期的蜂窝回传而变
# Wi-Fi 回传只写 Wi-Fi 表（行数增长，蜂窝表 SHA 除蜂窝回传外不变）
```

通过标准：两通道 tasks/report 均为 200；Wi-Fi 回传只写 Wi-Fi 表；
蜂窝统计口径不变；无熔断误触发。失败 → 按“逆序回滚”回退。

## 逆序回滚（任一阶段失败时）

顺序与部署严格相反：旧脚本 → 旧 nginx 配置 → 原服务。
执行 `sudo bash tools/rollback_dual.sh`（脚本内含每步的 SHA 校验与
健康检查：恢复后 wifi 路径必须 404，cellular tasks 必须 200）。

- 回滚保留 Wi-Fi 表以便审计（`probe_reports_wifi` /
  `probe_nodes_wifi` 行数回滚前后一致）。
- **禁止删表**：常规回滚不删 Wi-Fi 表，没有清理选项；
  如将来确实需要清理，须另立审批，不走回滚脚本。
- 回滚后重新记录阶段 1 基线，再决定是否重做。

## 最小可复现命令（单条，隔离验证用）

```bash
# 本地：Python 39 项 + JS 43 项
cd ~/workspace/p2p3-dual && python3 -m unittest discover -s tests && node tests/js_detect_test.js
# VPS：同步后四组（本地/VPS × root/非 root，见报告 §4）
```

## 变更记录

- v3（2026-11-17）：按 GPT #6940445042 四项 P0 重写。P0-2 阶段 5 改为
  私有渲染（占位符 fail-closed、CLIENT_VERSION 重算、按渲染产物 SHA
  核验）；P0-3 部署脚本改为 stage 参数独立执行（一次一个阶段，做完
  即停）、阶段 4 改为“旧蜂窝兼容＋隔离新脚本”，生产 Wi-Fi 回传改到
  阶段 5；P0-4 DB 备份改为 SQLite backup API 一致性快照 +
  integrity_check（单文件 cp 不再当作可靠备份）。
- v2（2026-11-17）：按 GPT #6938432964 五条门禁重写。P0-1 改为任务快照
  绑定；P0-2 主承载接口（utun/空值/矛盾 → unknown）；P0-3 标签仅为
  客户端声明；P0-4 改为五阶段 + 逆序回滚；回滚删表选项作废。
- v1（2026-11-17）：三步部署 + 逆序回滚（已废止，见 v2）。
