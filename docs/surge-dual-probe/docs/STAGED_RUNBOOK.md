# 分阶段部署手册（Staged Runbook）— #73 双通道探针补丁 B①

> 来源：Issue #73 评论 #6938432964（GPT 增量复核，五条精确门禁之 5）。
> 前置：必须先拿到 GPT 的部署批准；否则一律不执行。
> 本手册的每一步都有“记录什么、通过标准、失败怎么办”。
> 占位符说明：`<service_sha>` / `<script_sha>` 为 Draft PR 里核对过的
> 完整 SHA256（见 `docs/SHA_MANIFEST.md`）；`SEG` 从生产配置文件现读，
> 手册正文不写真实随机路径段。

## 0. 准备（一次）

```bash
SEG="$(cat /opt/probe-service/config/probe-path.txt)"
SERVICE_FILE=<补丁服务文件路径>   # 来自已审 Draft PR
SCRIPT_FILE=<补丁脚本文件路径>     # 来自已审 Draft PR
# 核对 SHA（必须与 SHA_MANIFEST 一致，否则停）
sha256sum "$SERVICE_FILE" "$SCRIPT_FILE"
# 预部署备份（部署脚本每步也会再备一份）
cp /opt/probe-service/probe_service.py /root/probe-service.py.pre-dual
cp /opt/probe-service/data/probe.db /root/probe.db.pre-dual
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
curl -s -o /dev/null -w "cellular tasks: %{http_code}\n" -H "X-Probe-Action: tasks" "http://127.0.0.1:18081/$SEG"
curl -sk -o /dev/null -w "wifi tasks (public): %{http_code}\n" -H "Host: <probe-host>" -H "X-Probe-Action: tasks" -H "X-Probe-Network: wifi" "https://127.0.0.1:8443/$SEG-wifi"
# 记录：蜂窝表 SHA + 统计快照 + Wi-Fi 行数（上面“基线快照命令”）
```

通过标准：cellular tasks 200；wifi tasks 404（nginx 无此 location，
且旧服务本身无此路径）；基线快照已记录。

## 阶段 2 — 先换服务

```bash
sudo bash tools/deploy_dual.sh "$SERVICE_FILE" "$SCRIPT_FILE" <service_sha> <script_sha>
# 注意：部署脚本是三步连跑；只做阶段 2 时，跑完第 1 步即停，
# 不要继续第 2/3 步（或按脚本提示分步执行）。
```

验证：

```bash
curl -s -o /dev/null -w "cellular tasks: %{http_code}\n" -H "X-Probe-Action: tasks" "http://127.0.0.1:18081/$SEG"
curl -sk -o /dev/null -w "wifi tasks (public): %{http_code}\n" -H "Host: <probe-host>" -H "X-Probe-Action: tasks" -H "X-Probe-Network: wifi" "https://127.0.0.1:8443/$SEG-wifi"
# 手机旧脚本下一整点仍正常回传蜂窝结果（只读观察，不干预）
```

通过标准：cellular tasks 200；旧脚本形状（无 network_type、无绑定字段）
仍被接受；wifi 仍 404；蜂窝表 SHA 只因预期的蜂窝回传而变，
统计口径与阶段 1 一致。失败 → 恢复阶段 1 的服务备份并重启，
回阶段 1 重新记录基线。

## 阶段 3 — 再加 nginx

```bash
# 部署脚本第 2 步：插入 -wifi location，nginx -t 后 reload
# （若部署脚本已连跑到第 2 步，此处只做验证）
nginx -t && systemctl reload nginx
curl -sk -o /dev/null -w "wifi tasks (public): %{http_code}\n" -H "Host: <probe-host>" -H "X-Probe-Action: tasks" -H "X-Probe-Network: wifi" "https://127.0.0.1:8443/$SEG-wifi"
curl -s -o /dev/null -w "cellular tasks: %{http_code}\n" -H "X-Probe-Action: tasks" "http://127.0.0.1:18081/$SEG"
```

通过标准：wifi tasks 200（且响应 info 带 `pool_sha` 与 `batch_id`）；
cellular tasks 200；蜂窝表 SHA 与统计快照与阶段 2 末一致
（只加 location，不应有任何蜂窝写入）。失败 → 恢复 nginx 备份，
`nginx -t` + reload，回阶段 2。

## 阶段 4 — 新旧脚本兼容

目的：旧脚本（蜂窝）与新脚本（Wi-Fi + 蜂窝）同时在线时互不干扰。
本阶段不换文件，只观察下一整点（或等手机自然回传）。

验证项（每项都要有真实记录）：

1. 旧脚本蜂窝回传仍被接受（cellular `tested_day` 增长）。
2. 新脚本 Wi-Fi 回传进入 `probe_reports_wifi`，`network_type` 为
   客户端声明的 wifi（见报告 P0-3 节：标签≠原生验证）。
3. Wi-Fi 操作前后蜂窝表 SHA 不变、蜂窝统计快照不变
   （上面“基线快照命令”前后对比）。
4. 异常流量不影响蜂窝：错通道、头/路径不一致、畸形体、重复回传
   均被拒绝（HTTP 400 / `duplicates` 计数），蜂窝 tasks 仍 200。

通过标准：四项全部满足。任一失败 → 停在阶段 3（nginx 已加、
服务已换、脚本未换），按需回滚到阶段 2。

## 阶段 5 — 最终换脚本

```bash
# 部署脚本第 3 步：换托管脚本，核对 SHA
cp /opt/surge-bridge/modules/probe-task.js /root/probe-task.js.pre-dual
cp "$SCRIPT_FILE" /opt/surge-bridge/modules/probe-task.js
sha256sum /opt/surge-bridge/modules/probe-task.js   # 必须等于 <script_sha>
chmod 644 /opt/surge-bridge/modules/probe-task.js
# 手机下次整点自动取新版；不催、不手动触发
```

验证（下一整点后）：

```bash
# Wi-Fi 与蜂窝两通道各有回传，且结果带 batch_id + snapshot pool SHA
curl -s -H "X-Probe-Action: stats" -H "X-Probe-Network: wifi" "https://127.0.0.1:8443/$SEG-wifi" | head -c 600
curl -s -H "X-Probe-Action: stats" "http://127.0.0.1:18081/$SEG" | head -c 600
# 蜂窝统计快照与阶段 4 末对比：只因预期的蜂窝回传而变
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
# 本地：Python 27 项 + JS 43 项
cd ~/workspace/p2p3-dual && python3 -m unittest discover -s tests && node tests/js_detect_test.js
# VPS：同步后四组（本地/VPS × root/非 root，见报告 §4）
```

## 变更记录

- v2（2026-11-17）：按 GPT #6938432964 五条门禁重写。P0-1 改为任务快照
  绑定；P0-2 主承载接口（utun/空值/矛盾 → unknown）；P0-3 标签仅为
  客户端声明；P0-4 改为五阶段 + 逆序回滚；回滚删表选项作废。
- v1（2026-11-17）：三步部署 + 逆序回滚（已废止，见 v2）。
