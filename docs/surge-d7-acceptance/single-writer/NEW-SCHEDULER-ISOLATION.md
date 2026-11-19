# Surge #73：新发布器隔离验收与保守切换手册（2026-11-19）

**当前状态**：GitHub 分支代码已接入旧规则读取、生成候选、
VPS可信新增叠加、单写手锁、STOP、回滚与服务/定时器模板。
**未在 VPS 安装或启用任何新定时器；未停止旧服务。**
此文档是待Muse在受信VPS逐项核实的任务书，不是上线完成回执。

## 系统边界

旧5个timer照常运行，其中 `pool-publish` 和 `pool-sync` 是仅有的两个
可以无锁写 staging/served 的已知旧写手。另3个crawl/test/test-full任务仅
更新SQLite数据。新服务未来独占双文件写入，不需新建第二条sync定时任务。

**保留现网**：实际基线每小时可能变化，曾观察45行 `cd45c960...`、
21条钉选（美国13条、香港8条），但不是硬编码45，也不能拿历史46/52行
备份覆盖现场。

**来源**：`/opt/free-node-program/pool.db`实际路径经Muse确认在
`/opt/free-node-program/data/pool.db`。
`pool_db_source.py`只读mode=ro和query_only，真实
`pool.rules`/`pool.crawler`/`pool.geo`由
`legacy_source_adapter.py`从现有已审安装树导入。
`crawler.crawl_records()`会按旧程序**发远程GET但只取内存候选**，
并非离线模拟。不会运行带写入的`pool.cli publish`。

## 功能语义：为何会有 HOLD

- 当前 F 已被机主豁免继续手工测试，但技术上仍 `UNCALIBRATED`；
  原生失败不可被伪造为手机可信证据，自动永久删除仍关闭。
- `build_candidate`复现旧发布器纯算法（候选预览；旧系统可能剔除一些旧轮换）。
  `safe_additions.safe_overlay`把现有池**每一行原样保留**，只追加
  最多4条同时满足DB 24h pass、通过率≥0.5、最新VPS pass测速≤300ms、
  非blocklist且国家上限未超的真实新节点。无法证明就拒绝并保持旧池。
- 候选缺针、钉选定义变化、未知STOP、源未证明、重复名、缩池、
  国家cap/总cap越界均不允许自动写入。
- 两种独立发布状态：`PR93_APPROVED_SAME_BYTES_ONLY`用于首次无变化切换；
  `PR93_APPROVED_VPS_ADDITIONS`还要求独立的安装源码哈希证明及
  `P2P3_ALLOW_VPS_ADDITIONS=YES_EXPLICITLY`。
  **只有这两种release marker能进入发布程序；文件当前不存在。**
  源文件SHA证明是完整性约束，不代替真机测速；新增不能宣称手机小于300ms。
- 新服务系统行为默认没激活，`production_cycle.py --publish`需要已授权release marker、
  `P2P3_ENABLE_PRODUCTION=YES_EXPLICITLY`、精确 `RUNNING` STOP文件、旧服务已mask排空、
  `single_writer.py check`返回0。失败直接退出78，不写文件。

## D3：VPS受信隔离核对（现在可做，不触碰生产）

1. 将PR #93最新精确HEAD检出到隔离目录，记录`git rev-parse HEAD`
   与7个新程序文件SHA256，且不得在仓库提交实际节点URI或凭据。
2. 查明**旧发布器实际使用的自定义私有主机名单文件路径**。
   `legacy_source_adapter.py`默认只接受 source root 下
   `private-hosts.txt`/`private_hosts.txt` 或 `data/`中同名文件
   **恰好一份**。旧脚本缺文件时会返回空名单，新程序因此选择拒绝，
   不能悄悄放宽。如果旧程序采用其他路径，先向GPT提供
   脱敏`cli.py`调用点再改代码。
3. 在生产订阅稳定的时间窗口（避开旧:07发布与:15同步间隔），
   仅只读运行（命令使用你们受信环境已有的实际路径）：

```bash
cd /tmp/pr93-shadow/docs/surge-d7-acceptance
P2P3_POOL_DB=/opt/free-node-program/data/pool.db \
P2P3_POOL_SERVED=/opt/surge-bridge/modules/pool-new.txt \
P2P3_POOL_STAGING=/opt/free-node-program/publish/pool-new.txt \
/opt/free-node-program/venv/bin/python single-writer/production_cycle.py --inspect-only
```

输出需显示`canonical_pin_count=21`、served/staging hash相同、退出0。
**只读检查不联网**；不打印原始节点。

4. 在**真实联网但不写文件**的预览模式：

```bash
cd /tmp/pr93-shadow/docs/surge-d7-acceptance
/opt/free-node-program/venv/bin/python single-writer/production_cycle.py --preview
```

`--preview`需要同样三个`P2P3_POOL_...`变量；在所见DB、旧规则和远端源
一致的情况下，记录候选数量及是否与现池相同，不输出全量代理行。
若因`private_hosts_path_missing_or_ambiguous`、真实YAML配置解析、固定源名/geo
映射、winner-clean时间窗、`pinned_identity_mismatch`等拒绝，
**保留退出78并报告脱敏原因；不能绕过/移除某层检查**。
定时器尚未安装，旧服务仍活跃，所以也不能`--publish`。

5. **字节级对照不是只比较一次**。对同一批冻结DB/源输入，至少覆盖：
   - 原样候选（45行那轮同SHA）
   - 新增补位发生、数量超过4、国家cap达到边界
   - pinned DB25行但blocklisted4行仅保21
   - winner-clean宽限期前后、过窗失败恢复
   - 源失败、过期测试、STOP丢失、重复名和不完整候选
   - 降级/故障重启，双文件SHA及回滚恢复
   如实际源变化，记录时间和版本，不可拿不同快照的hash要求相等。
   *当前仅现网45行样本同SHA，是D3的一项证据，不是全部D3。*

### 已安装源码完整性校验（只读）

新周期在**执行任何旧源码导入或爬取前**核对`P2P3_LEGACY_SOURCE_SHA256`。
哈希覆盖 `/opt/free-node-program/pool/` 的**全部**`*.py`文件（含
`__init__.py`及传递依赖），而不只是rules/crawler四个文件。
受信VPS上可只读计算该摘要，不输出源码与真实节点：

```bash
/opt/free-node-program/venv/bin/python - <<'PY'
from pathlib import Path
import hashlib
base = Path("/opt/free-node-program/pool")
names = sorted(x.name for x in base.glob("*.py"))
assert {"__init__.py","rules.py","crawler.py","geo.py","winner_clean.py"} <= set(names)
h = hashlib.sha256()
for name in names:
    p = base / name
    assert p.is_file() and not p.is_symlink()
    raw = p.read_bytes()
    h.update(name.encode("utf-8") + b"\\0")
    h.update(len(raw).to_bytes(8, "big"))
    h.update(raw)
print("legacy_source_sha256=" + h.hexdigest())
PY
```

实际哈希只由Muse保存在私有`production.env`（权限600）；
**不要在GitHub发布真实env配置/凭据**。代码发生任何改动
必须重做隔离验收并更新已批准SHA，不能临时跳过哈希核验。
`P2P3_STOP_STATE_FILE`还需Muse找到独立实际RUNNING/STOP状态文件；
状态文件缺失或不为精确`RUNNING`时发布拒绝，不能用默认常量掩盖。

6. 隔离systemd只允许`p2p3-*`测试单元和隔离目录：
   复用已有`single-writer/vps_systemd_test.py`测试真实flock、
   并发、SIGKILL、HTTP读回与回滚。若安装新模板，
   先运行`systemd/install-disabled.sh --dry-run`审查；
   此脚本不停止旧服务。批准D4后才可`--install-disabled`，
   **不能运行`systemctl enable --now p2p3-single-publish.timer`**。

## D4：准备真实切换（需要Muse回执，不能跳）

- 先留新的独立且不会被`.prev`覆盖的现场快照，至少含完整
  served/staging字节、SHA、21pin、systemd unit state和恢复脚本；
  在隔离副本执行恢复验证。旧 `.prev`仅一版，不能当唯一备份。
- 核对实际手机漏网组仍选代理（此前是`美国自动`）、
  出站模式不被意外切换，代理故障无隐式DIRECT。
- 验证新代码确实有可运行的**持续动态生成器**，不再仅是
  `HOLD`或重复同字节写入；新增规则独立审核，
  不得以永久删除解锁作为上线前置。
- 新 service/timer已在VPS安装为**disabled/inactive**，
  `ExecStart`指向真实可用venv，`EnvironmentFile`具有
  真实STOP状态路径、独立单写手DB/锁、受信源代码哈希和recovery配置。
- 现场旧两写定时器仍活跃时，`single_writer.py check`
  **必须返回1**；真正停旧写后、mask旧service且排空时
  再返回0才允许生产写入。不能提前跳过旧写手禁启门。

## D5：仅在D4完整通过时履行机主已有生产授权

先保存新鲜不可覆盖快照，逐一停/disable两个旧直接写timer并排空
旧service和进程、mask旧service；保留3个DB-only timer与bridge/probe；
`single_writer.py check`真实正向0、ban proof全部通过。
首次以当前现场完全同字节candidate发布，核对两个文件及HTTP对外
SHA、21pin无变化，随后验证新timer按计划触发且没有锁争抢。
监测新定时更新或安全HOLD结果；不稳定立刻使用**独立**快照
恢复双文件并恢复前面记录的两个旧timer/service原状态。

**当前不执行D5**：已经获机主切换授权，但技术门禁仍未全部通过，
`PR93 Draft`，现网旧timer继续正常更新。
