# 生产切换手册：systemd :07/:15 接入 D3 门禁（Issue #73，D4）

> 状态：方案 + 隔离演练通过。**生产未动**。执行须 GPT 批准 + 机主授权，
> 并选手机在场、可立即验收的时点；不在深夜无人值守时做第一次切换。
> 本文件不含任何订阅内容、节点行、密码、令牌、原始 IP。

## 0. 接线总览

```
每小时 :07  (pool-gate-publish.timer)
  gate-publish.sh
    1. 门禁当前源文件 (D3 pool.publish --workdir /opt/pool-gate/state)
         源 = /opt/free-node-program/publish/pool-new.txt (上周期组装的版本)
         证据 = /opt/free-node-program/gate/native-results.json (机主原生测速转录)
         探针 = /opt/probe-service/data/probe.db (仅健康信号)
       -> 门禁通过: 干净子集写 /opt/pool-gate/state/publish/pool-new.txt (+v2 sidecar)
       -> 门禁拒绝: 安全态, served 文件不动 (拒绝是正常态, 见 §2)
    2. 生产组装下一版本 (venv python -m pool.cli publish)
         -> 新的未门禁候选写 /opt/free-node-program/publish/pool-new.txt
         (下一周期门禁的对象; 未经原生测速前它不会被发布)

每 15 分钟 (pool-gate-sync.timer)
  gate-sync.sh
    1. D3 pool.sync --workdir /opt/pool-gate/state (锁内重验链 + 门禁)
       -> 通过: /opt/pool-gate/state/served/pool-new.txt
       -> 拒绝: 保持上一个干净 served 文件
    2. 仅当 rc=0 时, 复制 served -> /opt/surge-bridge/modules/pool-new.txt
       (+ legacy old-pool-file 路径), chmod 644, 验 SHA。
```

部署位置：

| 内容 | 路径 |
|---|---|
| 门禁代码（D3 `pool/` 包原样复制） | `/opt/pool-gate/pool/` |
| 门禁状态（workdir：publish/、served/、lock/、recovery-state.json、recovery-anchor.json） | `/opt/pool-gate/state/` |
| 包装脚本 + 单元 | `/opt/pool-gate/gate-publish.sh`、`/opt/pool-gate/gate-sync.sh`、`/opt/pool-gate/*.service|*.timer` |
| 日志 | `/opt/pool-gate/logs/gate-publish.log`、`/opt/pool-gate/logs/gate-sync.log`（另有 systemd journal） |
| 原生证据（机主测速转录，人工维护） | `/opt/free-node-program/gate/native-results.json` |
| 旧单元（切换时停用，不删除） | `/etc/systemd/system/pool-publish.{service,timer}`、`/etc/systemd/system/pool-sync.{service,timer}` |
| 旧同步脚本（切换时停用，不删除） | `/opt/free-node-program/pool-sync.sh` |

关键事实（切换前必须理解，否则不要执行）：

1. **门禁只认“同一版本的新鲜原生证据”**。`native-results.json` 里
   某次原生测速的 `version_sha` 必须等于当前源文件的 SHA256，且测速
   在 24 小时内、全部通过且 <300ms、无后续失败，门禁才放行对应指纹。
   P0 探针库（probe.db）只是健康信号，**不能**当作原生证据——
   `validate-native-record.py` 只校验转录记录，绝不把探针报告转成
   原生结果。
2. **Gate-first 顺序**。:07 先门禁当前源文件，再组装下一版本。
   原因是组装每小时产生一个新版本 SHA；若先组装再门禁，门禁看到的
   永远是刚出炉、从未被测过的版本，必然拒绝，干净版本永远发不出去。
   Gate-first 让每个版本都有一小时窗口供机主测速：上周期组装的版本
   在本周期被门禁，下周期组装的新版本等下下周期再门禁。
3. **拒绝是正常态，不是故障**。没有新鲜原生证据的版本，门禁拒绝、
   served 文件保持上一个干净版本。池子会变“旧”，但绝不会变“脏”。
   若连续 24 小时无一次门禁通过，池子过期——此时唯一正确的动作是
   机主做一次新的原生整组测速并转录，绝不是绕过门禁。
4. **恢复状态必须显式初始化**（D3）。新部署的门禁在 `init` 之前拒绝
   一切 publish/sync/rollback（`recovery_state_uninitialized`）。
   init 须人工键入 owner ack `OWNER-ACK-INIT-RECOVERY-STATE`，绑定
   当前 served 版本并记审计；定时器单元里**绝不**出现 ack，定时器
   永不调用 init。
5. **钉选无豁免**。门禁对钉选行与轮换行一视同仁（见
   `pinned-wiring/CONFIG-DIFF.md`）。`config.yaml` 里的
   `pinned_protected: true` 目前没有任何代码读取——豁免是
   `pool.cli publish` 的结构（钉选行无条件拼进发布文件），不是这
   个配置项。切换后豁免的消除靠门禁本身，配置项改为 `false` 只是
   记账 + 防未来代码误读。

## 1. 切换前检查（Phase 0，只读；任一项不过即停）

```bash
# 1.1 备份快照已按 backup-drill/PROCEDURE.md 取好并验证通过
ls -l /opt/p2p3-d4/backup-drill/snapshot-*/manifest.json
# 1.2 当前定时器与单元 SHA（与切换前锚点一致）
systemctl list-timers pool-* --no-pager
sha256sum /etc/systemd/system/pool-publish.* /etc/systemd/system/pool-sync.*
# 1.3 探针服务在跑
systemctl is-active probe-service
# 1.4 门禁代码与 PR #77 的 D3 树一致（逐文件 SHA）
diff -r /opt/pool-gate/pool /opt/p2p3-d3/pool --exclude=__pycache__
# 1.5 恢复状态已初始化（或在 Phase 2 做）
python3 -m pool.recovery status --workdir /opt/pool-gate/state
# 1.6 机主在场：能立即做原生整组测速 + 手机刷新验收
# （原生记录覆盖当前源版本的校验在 Phase 3 做，见下）
```

## 2. 部署门禁代码（Phase 1）

```bash
mkdir -p /opt/pool-gate/state /opt/pool-gate/logs
cp -r /opt/p2p3-d3/pool /opt/pool-gate/pool
cp /opt/p2p3-d4/systemd/gate-publish.sh /opt/pool-gate/gate-publish.sh
cp /opt/p2p3-d4/systemd/gate-sync.sh /opt/pool-gate/gate-sync.sh
cp /opt/p2p3-d4/systemd/validate-native-record.py /opt/pool-gate/validate-native-record.py
chmod 755 /opt/pool-gate/gate-publish.sh /opt/pool-gate/gate-sync.sh
chmod 644 /opt/pool-gate/pool/*.py
mkdir -p /opt/free-node-program/gate
# 核对: diff -r /opt/pool-gate/pool /opt/p2p3-d3/pool 应无差异
# 状态目录权限: state/ 700, 其下 recovery-state.json / recovery-anchor.json 由 init 写成 600
```

## 3. 初始化恢复状态（Phase 2，人工，唯一一次）

```bash
cd /opt/pool-gate
python3 -m pool.recovery init --workdir /opt/pool-gate/state \
  --owner-ack OWNER-ACK-INIT-RECOVERY-STATE
# 要求 rc=0, mode=fresh, 绑定当前 served 版本
# (served 当时还是旧文件: /opt/surge-bridge/modules/pool-new.txt 的 SHA;
#  init 时若 state/served 不存在, 先由人工确认当前 served 文件并记入 runbook)
python3 -m pool.recovery status --workdir /opt/pool-gate/state
# 要求 state=ok, stopped=false
```

> 注意：init 绑定的是“当前 served 版本”。若 init 时 served 目录还
> 是空的（门禁从未发布过），init 会以 fresh 模式建立 ok 而不绑定
> served——这是允许的；第一次门禁发布成功后，锚点即绑定该版本。
> init 拒绝已记录的 STOP（删状态文件也洗不掉），见 D3 报告 §2.3。

## 4. 冻结源版本 + 原生测速 + 转录（Phase 3，机主 + 助手）

**顺序不能错**：必须先冻结源版本，再测速。组装每小时产生一个新
版本 SHA；若先测速、后冻结，测速的版本可能在冻结前就被下一个 :07
组装覆盖，记录随即失效（门禁拒绝 `native_version_mismatch`）。
演练 `drills/switch_rehearsal.py` 的 S4a 正是这个陷阱：测了一个
已被取代的版本，门禁照样拒绝。

```bash
# 4.0 先停旧发布定时器，冻结源版本（同步定时器继续跑，继续服务当前文件）
systemctl stop pool-publish.timer
systemctl disable pool-publish.timer
sha256sum /opt/free-node-program/publish/pool-new.txt
wc -l /opt/free-node-program/publish/pool-new.txt
# 记下 SHA 前缀与行数：这就是要测的版本
```

1. 机主在手机上（移动数据，关 Wi-Fi）对上述冻结的版本做一次
   Surge 原生整组测速，等全部出结果，截图（带状态栏时间）。
2. 助手把截图结果逐条转录进
   `/opt/free-node-program/gate/native-results.json`
   （格式 `native-results-v1`，一次 run：`version_sha` = 冻结源文件
   SHA256 全值，`tested_at` = 测速 unix 时间，`results` 逐指纹
   `success`/`ms`；指纹算法与 D3 `pool.phone_gate` 一致）。
3. 校验：

```bash
python3 /opt/pool-gate/validate-native-record.py \
  --record /opt/free-node-program/gate/native-results.json \
  --source-file /opt/free-node-program/publish/pool-new.txt \
  --code-dir /opt/pool-gate --probe-db /opt/probe-service/data/probe.db
# 要求: ok=true, covers_source_version=true, admitted_for_source > 0
# admitted_for_source 应等于截图里 <300ms 的条数；不一致即重核
# 转录，不许改数字凑数。
```

## 5. 安装门禁单元（Phase 4）

```bash
cp /opt/p2p3-d4/systemd/pool-gate-publish.service /etc/systemd/system/
cp /opt/p2p3-d4/systemd/pool-gate-publish.timer /etc/systemd/system/
cp /opt/p2p3-d4/systemd/pool-gate-sync.service /etc/systemd/system/
cp /opt/p2p3-d4/systemd/pool-gate-sync.timer /etc/systemd/system/
systemd-analyze verify /etc/systemd/system/pool-gate-publish.service \
  /etc/systemd/system/pool-gate-publish.timer \
  /etc/systemd/system/pool-gate-sync.service \
  /etc/systemd/system/pool-gate-sync.timer
# 要求无错误输出（无输出即通过）
systemctl daemon-reload
systemctl enable pool-gate-publish.timer pool-gate-sync.timer
# 此时不要 start：先停旧同步定时器（Phase 5），再统一启动，避免双跑
```

## 6. 切换（Phase 5）

```bash
# 6.1 停旧同步定时器（旧发布定时器已在 Phase 3 冻结时停用）
systemctl stop pool-sync.timer
systemctl disable pool-sync.timer
systemctl list-timers pool-* --no-pager
# 要求: pool-publish.timer / pool-sync.timer 不再列出 NEXT 时间

# 6.2 启动门禁定时器
systemctl start pool-gate-publish.timer pool-gate-sync.timer
systemctl list-timers pool-gate-* --no-pager
# 要求: pool-gate-publish.timer NEXT 为下一个 :07,
#      pool-gate-sync.timer NEXT 为下一个 :00/:15/:30/:45
```

## 7. 切换后验收（Phase 6，逐项打勾）

```bash
# 7.1 下一个 :07 后看 gate-publish 日志
tail -5 /opt/pool-gate/logs/gate-publish.log
# 要求: gate rc=0, published_count > 0, 且与 Phase 3 截图的通过条数一致
# 7.2 下一个 :15 后看 gate-sync 日志
tail -5 /opt/pool-gate/logs/gate-sync.log
# 要求: sync rc=0, served_sha 与 bridge 文件 SHA 一致
sha256sum /opt/pool-gate/state/served/pool-new.txt \
  /opt/surge-bridge/modules/pool-new.txt \
  /opt/pool-gate/state/publish/pool-new.txt
# 要求三者 SHA 相同（publish 与 served 相同是 D3 结构；bridge 是复制）
# 7.3 手机刷新“免费节点池”订阅，成员数 = gated 行数；再跑一次原生整组
#     测速：要求 0 失败、0 个 >=300ms（GPT 验收门）
# 7.4 分流抽查：YouTube / Google / Telegram 各打开一次，确认走节点出口
#     （Requests 里 policy 为免费节点池，无 DIRECT）
```

## 8. 下一个 :07 的观察（Phase 7，:07 覆盖不复活的证明）

切换后的**第二个** :07（组装出新版本后）：

```bash
tail -5 /opt/pool-gate/logs/gate-publish.log
# 预期: gate rc=1, error=native_version_mismatch 或 phone_gate_zero_qualified
# (新版本未经原生测速，门禁拒绝是正确的)
sha256sum /opt/pool-gate/state/served/pool-new.txt \
  /opt/surge-bridge/modules/pool-new.txt
# 要求: served 与 bridge 的 SHA 与 Phase 6 验收时完全相同——
#      被拒绝的新版本没有复活任何坏节点，也没有覆盖干净文件
# 之后：机主对新版本做原生测速并转录，下一个 :07 门禁即放行该版本
```

## 9. 回滚（任何验收失败、手机测速失败、DIRECT 泄漏，立即执行）

```bash
# 9.1 停门禁定时器
systemctl stop pool-gate-publish.timer pool-gate-sync.timer
systemctl disable pool-gate-publish.timer pool-gate-sync.timer

# 9.2 恢复旧定时器
systemctl enable pool-publish.timer pool-sync.timer
systemctl start pool-publish.timer pool-sync.timer
systemctl list-timers pool-* --no-pager
# 要求: pool-publish.timer NEXT 为下一个 :07, pool-sync.timer NEXT 为下一个 :15

# 9.3 立即用旧同步脚本恢复一次服务文件（不等下一个 :15）
/opt/free-node-program/pool-sync.sh
sha256sum /opt/free-node-program/publish/pool-new.txt \
  /opt/surge-bridge/modules/pool-new.txt
# 要求两者 SHA 相同（旧行为：served = 当前未门禁发布文件）

# 9.4 恢复配置记账（门禁已停用，豁免随旧定时器恢复而恢复）
#    config.yaml: pinned_protected: false -> true
sed -i 's/^pinned_protected: false/pinned_protected: true/' \
  /opt/free-node-program/config.yaml
grep pinned_protected /opt/free-node-program/config.yaml

# 9.5 手机验收：刷新订阅，成员数回到切换前；原生整组测速确认与切换前一致
# 9.6 门禁代码与状态目录保留在原地（不删除），供事后复盘与再次切换
#     /opt/pool-gate/ 不动；/etc/systemd/system/pool-gate-* 单元保留（disabled）
```

回滚触发条件（任一成立即回滚，不等“再观察一下”）：

- 切换后手机刷新，“免费节点池”组成员数为 0，或 Surge 拒绝加载该组；
- 切换后原生整组测速出现失败节点，或任一节点 ≥300ms；
- 切换后依赖该组的分流实测走了 DIRECT 或走了错误的出口；
- 切换后 Surge 无法启动或配置报错；
- 服务端核对发现 bridge 文件 SHA / 行数与门禁 served 文件不一致，
  且 15 分钟内未自愈；
- gate-publish 日志连续 3 个周期出现非门禁类的错误
  （如 `source_missing`、`recovery_state_*`、`lock_timeout`）。

## 10. 运维说明

- **日志位置**：`/opt/pool-gate/logs/gate-publish.log`、
  `/opt/pool-gate/logs/gate-sync.log`、systemd journal
  （`journalctl -u pool-gate-publish.service`）。
- **状态查询**（不改状态）：
  `python3 -m pool.recovery status --workdir /opt/pool-gate/state`
  （须在 /opt/pool-gate 下运行）。
- **STOP 操作**（出现坏 served 版本时，人工）：
  `python3 -m pool.recovery enter-degraded --workdir /opt/pool-gate/state --reason <原因>`；
  恢复走 `manual-restore` / `clear-stop`（均须 owner ack，见
  `docs/recovery-runbook.md`）。**绝不**通过删状态文件复位 STOP。
- **原生记录更新节奏**：每次机主做原生整组测速后，助手转录并追加
  一个 run 到 `native-results.json`（保留旧 run，供
  subsequent-failure 判定用；不要删除旧 run）。
- **单元加固未做**：本次单元未加 `ProtectSystem` 等加固（加固可能
  挡住对 `/opt/free-node-program` 与 `/opt/surge-bridge` 的写），
  待第一次切换成功后再评估。

## 11. D6 补充（2026-11-16，GPT D5 复核 6887615694）

### 11.1 切换前检查（新增，Phase 0，只读；任一项不过即停）

```bash
# 11.1.1 served 暴露路径：served 目录不得被 HTTP 直接读取
#   核对 nginx 配置：只映射 bridge 目录（如 /opt/surge-bridge/modules/），
#   served 目录（/opt/pool-gate/state/served/）不在任何 alias/root/location 下。
grep -rn "served" /etc/nginx/ /opt/surge-bridge/ 2>/dev/null | grep -v "^Binary"
#   要求：无任何行把 served 目录映射为 HTTP 路径。
#   代码层面的第二道防线：gate-sync.sh 每次同步前做 realpath 比对，
#   served 解析后若在 BRIDGE_DIR 内即拒绝（日志 served_path_exposure_check）。
#   但“served 目录本身被 HTTP 直读”只能在部署时按本条核对，代码守卫防不住
#   nginx 配置本身的映射错误。

# 11.1.2 legacy 路径预建目录（D6：legacy 父目录缺失时不自动建目录，必须失败）
#   核对 legacy 文件父目录存在且可写；不存在时先人工建目录，不要等第一次同步才发现。
ls -ld "$(dirname "$(cat /opt/free-node-program/config/old-pool-file.txt)")"

# 11.1.3 health 监控就位（见 11.4）：监控脚本能读到 $GATE/logs/health.json，
#   且告警通道已验证（人为写一条 health=published_assembly_failed 测试告警能收到）。
```

### 11.2 STOP 后隔离 / 恢复旧版策略（served 篡改场景）

served 被篡改触发 STOP 后，处置顺序（人工，不自动恢复）：

```bash
# 1) 确认 STOP 与隔离证据（只读）
python3 -m pool.recovery status --workdir /opt/pool-gate/state
ls -la /opt/pool-gate/state/served/.quarantine/
#   要求：隔离区有 pool-new-<ts>-<sha12>.txt（600）+ 同名 .manifest.json；
#   served 路径已是恢复后的已验证版本（SHA 等于链 published_sha）；
#   bridge 文件 SHA 与恢复后的 served 一致（未被污染）。

# 2) 查篡改来源：谁在锁外写了 served（审计日志、cron、其他写手）
#   在找到写手并消除之前，不要清 STOP——否则下一轮同步后仍可能再次被篡改。

# 3) 人工恢复审核（同 recovery-runbook.md §S4）：
#   served 已是干净版本、状态仍是 manual-restored-unverified 时，
#   须手机 fresh 原生复测，通过后才能清 STOP 回到 ok。
#   绝不直接删状态文件复位 STOP（见 recovery-runbook.md §7）。
```

### 11.3 双目标一致性 / 回滚（bridge + legacy）

- 一致性定义：bridge 与 legacy 要么同为同一快照字节（SHA 一致），要么 run 失败且 bridge 回滚到写前字节；不存在“bridge 已更新、legacy 静默失败、run 宣称成功”的状态。
- 回滚触发：legacy 写失败（`legacy_copy_failed`）或 bridge 写后验 SHA 不符（`bridge_sha_mismatch`）时，bridge 自动回滚到写前字节，run 以 rc=1 结束；人工只需核对 bridge SHA 回到写前值并修 legacy 路径，不用手动恢复 bridge。
- 核对命令（只读）：

```bash
sha256sum /opt/pool-gate/state/served/pool-new.txt \
  /opt/surge-bridge/modules/pool-new.txt \
  "$(cat /opt/free-node-program/config/old-pool-file.txt)"
#   要求：三者 SHA 一致（均为已验证版本）；不一致即按 11.2 走，不要直接 cp 覆盖。
```

### 11.4 退出码 + health 监控接线

- `gate-publish.sh` 退出码：0＝门禁通过且组装成功；1＝门禁拒绝或预检失败；2＝门禁通过但组装失败。**exit=0 只表示“本轮已验证发布成功”，不得解释为整个周期全部成功。**
- 每周期原子写 `$GATE/logs/health.json`（health、gate_rc、assembly_rc、各 SHA 前缀、`new_source_gated=false`、`assembly_failed`、`src_changed`）。监控脚本每周期读该文件：

```bash
# 监控示例（每 5 分钟跑一次的检查脚本片段，不进 timer 本身）
HEALTH=$(python3 -c "import json; print(json.load(open('/opt/pool-gate/logs/health.json'))['health'])" 2>/dev/null)
case "$HEALTH" in
  healthy) : ;;  # 正常，不告警
  published_assembly_failed)
    echo "ALERT: 下一轮源组装失败，需人工看组装器/磁盘（gate_rc=0，发布本身完好）" ;;
  gate_refused)
    echo "ALERT: 门禁拒绝，看门禁日志与原生证据新鲜度" ;;
  precheck_failed)
    echo "ALERT: 预检失败（源文件缺失/代码缺失）" ;;
  *) echo "ALERT: health 文件缺失或不可读（监控盲区，门禁本身仍以 recovery-state 为准）" ;;
esac
```

- 退出码 2 不触发 timer 的失败重试（组装失败重试无意义，须人工修组装器），但须进告警通道；连续 3 个周期 `published_assembly_failed` 即按 §9 回滚触发条件同等处理（停新发布、人工介入）。
- `health.json` 是监控信号，不是门禁状态：门禁仍以 `recovery-state.json` / `recovery-anchor.json` 为准；health 文件丢失不影响门禁，只影响监控可见性。

## 11.5 D7 补充（2026-11-16，GPT D6 复核 6904538782）

### 11.5.1 served 暴露路径审计已实跑（2026-11-16 16:37，结论：通过）

- 真实 nginx 配置核对（只读，`nginx -t` 语法 OK）：全站共 3 个 server 块；
  唯一静态映射是订阅入口 `location <STATIC_PREFIX>` → `alias <BRIDGE_DIR>`；
  其余 location 全部是 `proxy_pass` 到本机端口（桥 API / 池 UI / 巡检服务），
  无任何 `root`/`alias` 指向 served 目录或 publish 目录，全站 `autoindex` 0 处。
  `nginx.conf` 只 `include conf.d/*.conf`，`.bak*` 文件不加载。
- Live 探针 8 条（GET，只记状态码 + 响应 SHA 前缀 + 字节数，不存响应体）：
  入口 200 且响应 SHA = 磁盘 bridge 文件 SHA = 生产发布文件 SHA
  （2026-11-16 16:07 版，29 行）；`..`、编码 `..`、`.quarantine` 猜测、
  越界到 publish 目录、编码 gate 路径、根路径 served 直读、`..;` 全部 400/404，
  无一返回订阅字节。证据表见 PR `docs/d7-live-probes.json`（已脱敏）。
- **守卫边界（已实证，不是文字）**：`gate-sync.sh` 的 realpath 守卫只覆盖
  served 在 bridge 目录内的误配；独立 HTTP alias 指向 served 目录时守卫
  返回 ok、探针却返回 200（演练 `drills/d7_item1_http_exposure.py` 负对照）。
  因此切换前必须重跑本条审计 + 探针（命令见 `docs/D7_CHECKLIST.md`），
  不能只靠守卫。审计任一项不过即停。

### 11.5.2 双目标一致性核对命令（D7 新增只读工具）

```bash
# 任一时刻核对 served / bridge / legacy 三者是否同为已验证版本：
python3 -m pool.bridge_sync --verify-targets \
  --workdir /opt/pool-gate/state \
  --bridge-dir /opt/surge-bridge/modules \
  --old-path "$(cat /opt/free-node-program/config/old-pool-file.txt)"
#   rc=0 + consistent=true：三者 SHA 均等于链 published_sha。
#   rc=1：看 detail（served_sha_mismatch / bridge_sha_mismatch /
#   legacy_sha_mismatch），按 11.2 走，不要直接 cp 覆盖。
#   特别：bridge 已是新版、legacy 仍是旧版（两 rename 之间进程崩溃）
#   会报 legacy_sha_mismatch；下一轮同步会自动从已验证快照修复 legacy，
#   修完重跑本命令须 rc=0。
```

`bridge_sync` 是同一锁内连续两次原子 rename，**不是**跨两个文件的真正
原子事务（D6 文档措辞已更正）。失败状态均可检测、绝不假成功：
写失败（rename 前/写后 SHA 不符）→ 回滚 + rc=1；两 rename 之间崩溃 →
bridge 新 / legacy 旧 → `verify_targets` 检出 + 下一轮修复。

### 11.5.3 冻结版干净订阅 staging（D7 就绪，生产未动）

- staging 文件在 PR `staging/`：`frozen-clean14-subscription.txt`（14 行，
  SHA `6074082847c3…`，与 D0/D5/D6 演练用的 clean14 字节一致）、
  `frozen-clean14-manifest.json`（冻结时间、来源、SHA、状态）、
  `staging/phone-retest-steps.md`（切换窗口手机复测精确步骤：冻结 →
  同 SHA 原生整组 → DIRECT 三场景 → 回滚）。
- staging 未接入任何生产路径（无定时器、无 nginx 映射、无手机配置引用）；
  真实切换时按同样程序冻结**真实** 14 行并以真实 SHA 为准，
  staging 文件本身是合成固件（TEST-NET），只证明冻结程序与清单格式。
- 切换窗口执行顺序见 `staging/phone-retest-steps.md` §1–§5。
