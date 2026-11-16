# D7a 报告：GPT D7 裁决 6912114134 的四项闭环（新增证据与修复）

- 日期：2026-11-16（CST）
- PR：#77（Draft，分支 `issue73-surge-d1-review`），D7 head `1521275`
- 范围：只闭合 GPT D7 裁决（评论 6912114134，2026-11-16 09:07 UTC）的 4 项。
**不扩展 D8 功能，不重复 D1–D7 摘要。** 生产订阅、生产定时器、手机配置、
main 分支一律未动；PR 仍为 Draft；不批准生产切换——本轮只交新增证据。
- 双环境：本地 Python 3.12.3 / VPS Python 3.13.5（美国 VPS 38.64.63.148）。
工作树：本地 `~/workspace/p2p3-d7a/`，VPS `/opt/p2p3-d7a/`（已同步）。
上传包：`~/workspace/p2p3-d7a-upload/`（与树逐字节一致，见 §6）。

## 0. 总览：四项状态

| # | GPT 要求 | 本轮交付 | 状态 |
|---|---|---|---|
| 1 | 双目标不一致纳入切换门禁；verify_targets 仅检测不自动修复；不能把“下一轮可修复”视为故障期间零风险 | `pool/bridge_sync.py`：`gate_block()` + `repair_targets()`；`systemd/gate-sync.sh` 最前面接线 gate-block；演练 23/23；单元测试 20 项（全套 161 项内） | 已验（隔离） |
| 2 | HTTP 暴露验证需部署后复跑；核对 nginx 实际生效配置、入口响应 SHA、served/quarantine 不可访问 | `tools/http_recheck.py`（独立脚本，窗口直接可用）；演练 11/11（VPS 真实 nginx + 真实 `nginx -T` 输出，本地 Python 仿真） | 已验（隔离） |
| 3 | 冻结真实版本再测手机；staging clean14 是合成 fixture，不能当真实 14 条节点或原生通过证据 | `tools/freeze_real.py`；VPS 只读实跑真实 manifest：源 29 行 `cdaa94605875`，候选 14 行 `10e52c9643a8`，fresh 2 / stale 12 / partial 0，钉选 14/14，`needs_phone_retest`，`publishable: false` | 已验（只读实跑） |
| 4 | 上线窗口前置；7 项未验逐项附执行人、预期结果、失败回滚条件 | `docs/D7A_ACCEPTANCE.md`（7 项逐项）+ 带 STOP 锁存的五周期序列演练 24/24 | 已验（隔离）+ 7 项待窗口/机主 |

## 1. 第 1 项：双目标不一致纳入切换门禁

### 1.1 代码（`pool/bridge_sync.py`）

- **`gate_block(workdir, bridge_dir, old_path, now)`**：只读检测 + STOP 锁存。
三方 SHA（served / bridge / legacy）与链 `published_sha` 全一致 → rc=0；
任何分歧 → 共享锁内重验一次，仍分歧则 `_enter_degraded_inner`
（`reason=targets_inconsistent:<detail>`）锁存 STOP，rc=1。
锁存后 `publish.py` 拒绝（`pool_stopped`），之后每个:07/:15 周期同样拒绝，
直至人工修复 + `clear_stop`（OWNER_ACK + 新鲜原生证据）。
边界（有意设计）：尚无链时（`served_no_chain` / `chain_unreadable`）直接
放行并记 `skipped=no_chain_nothing_to_block`——无链可比，且此时锁 STOP 会
死锁首次同步（STOP 只能以已验证 served 清除，而 served 尚不存在）；
链有效性仍由 sync/publish 门禁兜底（fail-closed）。
- **`repair_targets(...)`**：唯一修复路径，手动、锁内。served 重验（坏则先
`_quarantine_and_restore_served` 隔离 + 从链已验证 publish 文件恢复；仍坏则
rc=1 `repair_served_unrestorable`）→ 已验证 served 字节内存快照同时写
bridge + legacy（tmp+rename+fsync+写后 SHA 复验，沿用
`_write_bytes_verified`；legacy 写失败则 bridge 回滚）→ `verify_targets`
必须一致才 rc=0，并写 repair manifest JSON（修复前三方 SHA、修复后三方
SHA、时间戳、`repaired_by=manual`）。**repair 本身不清 STOP。**
- CLI：`--gate-block`、`--repair-targets`（需 `--native-record`）、
`--repair-manifest`、`--repaired-by`、`--now`（演练用；生产调用不传即墙钟
时间。补加原因：CLI 测试曾因真实墙钟距 fixture 测试 37.6 小时超 24h TTL
导致 allowlist 0/14 而失败）。
- **`systemd/gate-sync.sh`**：在 `pool.sync` 之前最前面调用 `--gate-block`
（先读 `$OLD_MANIFEST` 取 legacy 路径）；rc≠0 即记日志
`gate_block_refused targets_inconsistent stop_latched sync_not_run
bridge_unchanged` 并 exit 1。
- **D7 文档措辞更正**：`bridge_sync` 是同一锁内连续两次原子 rename，
不是跨文件真正原子事务（D6/D7 措辞已更正）；“下一轮同步会自动修复 legacy”
已作废——门禁 + 手动修复是唯一路径（手册 §11.5.2 末段与新增 §11.5.4）。

### 1.2 演练（`drills/d7a_item1_gate_block.py`，23/23 双环境）

| 场景 | 检查 |
|---|---|
| (a) legacy 写后 SHA 失败留污染 legacy | gate-block rc=1、STOP 已锁存、publish 拒绝、served/bridge SHA 不变、HTTP 入口仍是修复前已验证版 |
| (b) 两 rename 间崩溃（复用 D7 `post_bridge_hook`） | gate-block 检出 `legacy_sha_mismatch`、STOP 锁存、后续发布停止 |
| (c) 受控修复后三方 SHA 一致 + HTTP 入口 SHA 等于修复后 SHA，clear_stop 后下一周期恢复 healthy | 全绿 |
| (d) D7 红对照 | D7 树在同样注入下 gate-block 不存在（下一轮直接修复、无 STOP 锁存）为红；D7a 树为绿 |

HTTP 入口用 `drills/d7_item1_http_exposure.py` 的 SandboxServer
（VPS 真实 nginx 引擎，本地 Python 仿真引擎）。

### 1.3 单元测试（`tests/test_d7a.py`，20 项，全套 161 项内）

gate-block 一致 / legacy 污染锁存 / STOP 后 publish 拒绝 / 崩溃分歧锁存 +
sync 拒绝 / served 篡改锁存 / 无链放行；repair 修复三方一致 + manifest +
STOP 仍锁存、repair + clear_stop 恢复周期、served 坏时隔离恢复、repair 需
native record、无链拒绝；CLI 三段式 gate-block→repair→gate-block 及
verify-targets 仍可用；http_recheck 解析器 4 项；freeze 4 项。

### 1.4 有意的行为变更（已披露）

全套跑时 D6 旧测试 `test_d6.py::TestWrapperBridgeAndExit.
test_wrapper_legacy_failure_fails_and_rolls_back` 失败：该测试期望 legacy
路径指向不存在目录时由 bridge_sync 报 `legacy_copy_failed`；D7a 设计下缺失
legacy 本身就是 `verify_targets` 定义的 `legacy_sha_mismatch`，gate-block
先行拦截并锁存 STOP。已按有意的行为变更更新该测试（断言改为
`targets_inconsistent` + `gate_block_refused` + STOP 锁存 + 下一:07 publish
也拒绝；不变量 rc=1、bridge 保持已验证字节、坏路径不建文件不变）。
更新后全套 161 项全绿。

## 2. 第 2 项：部署后 HTTP 复核脚本（`tools/http_recheck.py`）

独立脚本，无 pool 导入，切换窗口直接可用。输入：nginx -T 生效配置转储
（`--config-dump`，nginx -T 输出或纯 nginx.conf 均可解析）、订阅入口 URL、
期望 SHA、bridge/legacy/served 三路径、`--quarantine-name`、`--extra-probe`
（可重复）。输出单 JSON（脱敏：只含 SHA 前缀、行数、路径名、布尔值，
绝不含完整入口 URL、节点 URI、凭据）。

检查：C1 入口 location 的 alias/root 解析后 realpath 等于 bridge 文件；
C2 无 location 解析进 served 目录或 `.quarantine`、无 `autoindex on`
（每项违规报 location 名）；C3 GET 入口 200 且 body SHA == bridge 文件
SHA == 期望 SHA 三方对照；C4 D7 探针集 7 条（`..`、编码 `..`、越界 publish、
编码 gate 路径、根路径 served 直读、`..;`、`.quarantine` 猜测）+ 额外探针
须全部非 200 或 body SHA 不等；任一失败 rc=1。

演练 `drills/d7a_item2_http_recheck.py`（11/11 双环境）：H 健康态 rc=0 +
入口 SHA 三方一致 + 7 探针全拒 + 无违规；V 独立 alias 指向 served →
rc=1 + 违规点名 `/alias-served/` + 额外探针返回 served 字节 200；
F 修复后重跑 rc=0。VPS 用真实 nginx + 真实 `nginx -T` 输出，
本地用 Python 仿真引擎（conf 文件作 dump）。

## 3. 第 3 项：冻结真实版本（只读实跑）

工具 `tools/freeze_real.py`（只读；`phone_gate` 仅依赖标准库，可直接复用）。
只读读生产源订阅（gate-publish.sh 的 `$SRC` =
`/opt/free-node-program/publish/pool-new.txt`）与手机原生证据
（`--native-record` 可选、probe.db 只读），按最新手机证据选候选 14 行，
写冻结 manifest JSON（600）与真实冻结文件（14 行真实节点 URI，600，
只留 VPS，永不进 PR/上传包/任何输出）。manifest 只含：源文件 SHA、候选
14 行 SHA、行数、每行名字 + 最后原生通过时间 + ms、每行证据状态
（fresh/stale/partial）、21 pinned 豁免核查结果、冻结时间、status。

证据口径：fresh = 24h 内手机通过 <300ms（probe verified 或当前源 SHA 的
native run）；stale = 有通过记录但超 24h 或属旧源版本（09:05/11:24 部分截图
测的是不同源版本，永远不能让当前源版本的行变 fresh）；partial = 无通过证据；
unparseable = 行无法解析。status：`needs_phone_retest` 为默认；仅当全部
14 fresh 且同一 native run（version_sha == 源 SHA、24h 内、通过集覆盖全部
候选）时为 `evidence_fresh`。`publishable` 仅当 status == `evidence_fresh`
且候选无钉选行。

**VPS 只读实跑（2026-11-16 17:25–17:26 CST）**：

| 字段 | 值 |
|---|---|
| 源文件 | `/opt/free-node-program/publish/pool-new.txt`，29 行，SHA `cdaa94605875`（2026-11-16 17:08 定时发布，与 16:07 版同 SHA） |
| 候选 14 行 | SHA `10e52c9643a8` |
| 证据 | fresh 2 / stale 12 / partial 0（09:05 轮在 60 行旧版本上 18 条通过、11:24 轮在 30 行旧版本上 3 条通过，已转录为 `docs/d7a-native-evidence-transcribed.json`，经 VPS 上名字→指纹连接后作为 `--native-record` 传入；两轮测的都不是当前源版本，故一律 stale，不补算通过） |
| fresh 2 条 | 美国13 264ms、美国12 265ms（P0 探针 verified，last_phone_ts 1794808824 前后） |
| 钉选核查 | 钉选表 25 行；源文件内 21 行；候选 14 行**全部是钉选行** |
| status / publishable | `needs_phone_retest` / `false` |
| blockers | `no_fresh_full_group_evidence_for_frozen_sha`、`pinned_exemption_present_in_candidates` |
| 冻结文件 | `/opt/p2p3-d7a/freeze/frozen-real-14.txt`（14 行，600，永留 VPS）；manifest `/opt/p2p3-d7a/freeze/real-freeze-manifest.json`（600）；PR 副本 `docs/d7a-real-freeze-manifest.json`（只含 SHA、名字、ms、状态，无 URI） |

生产只读现状（2026-11-16 17:25）：`/opt/pool-gate` 不存在（门禁未部署）；
旧定时器在跑：`pool-publish.timer`（:07，下次 18:08:51）、
`pool-sync.timer`（:15，下次 17:30:00）、`pool-crawl.timer`、
`pool-test.timer`、`pool-test-full.timer`；`nginx -t` OK。

## 4. 第 4 项：上线窗口前置与 7 项验收单

- `docs/D7A_ACCEPTANCE.md`：D7 清单 7 项未验逐项写清执行人（助手 / 机主 /
GPT 批）、预期结果（含具体 SHA/行数/状态值）、失败回滚条件（任一失败维持
现网并 STOP，不自动放宽）。“旧定时器退场”与“生产:07/:15 周期”附只读
现状核查（见 §3 末）；“真实 stop→restore→start”附 D7 程序演练 12/12
引用并明确生产执行仍待窗口。
- 演练 `drills/d7a_cycles_latch.py`（24/24 双环境）：5 周期:07/:15 序列——
C1 健康、C2 再健康、C3 注入 legacy 分歧 → gate-block 锁存 STOP → 下一:07
publish 拒绝 `pool_stopped` → 下一:15 gate-block 再拒绝 + sync 拒绝 →
served/bridge SHA 全程不变 + HTTP 入口仍是已验证版、C4 受控修复 +
http_recheck 绿 + clear_stop 后下一周期 healthy、C5 再一健康周期证明稳定。

## 5. 全套测试与回归

- 全套 **161 项**（141 基线 + 20 新增 D7a）：本地 root OK（跳过 7，均为
root 下 chmod-000 用例）、本地非 root（d5test，uid 1000）**161/161、0 跳过**。
- VPS：全套 161 项 root OK（跳过 7）、非 root 161/161（0 跳过）；跨周期
37/37、崩溃窗口 N=20 all_pass、备份恢复 13/13+1、D6 三项 24/24、16/16、
17/17、D6 红→绿 10/10、跨周期红→绿 15/15、D7 四项 13/13、15/15、21/21、
12/12、D7 红→绿 4/4、D7a 三项 23/23、11/11、24/24、D7a 红→绿 6/6、
staging 冻结 14 行 SHA `6074082847c3`（未发布、未接线）。
- D7 回归（双环境，逐项复跑）：跨周期 **37/37**、崩溃窗口 N=20 all_pass、
备份恢复 13/13+1、D5 红→绿 13/13、D6 三项 **24/24、16/16、17/17**、
D6 红→绿 10/10、D7 四项 13/13、15/15、21/21、12/12、D7 红→绿 4/4、
跨周期红→绿 **15/15**。
- D7a 新增：item1 演练 23/23、item2 演练 11/11、cycles-latch 24/24、
红→绿 6/6（`drills/d7a_redgreen.py`：D7 树红——item1 演练 ImportError；
D7a 树绿 23/23；API 面；test_d7a 在 D7 树 ImportError、在 D7a 树 20/20）。
- systemd 门禁单元：VPS `systemd-analyze verify` 0 语法错误；仅 2 条预期报错
（ExecStart 路径 `/opt/pool-gate/gate-sync.sh` 与 `gate-publish.sh`
尚未部署）；`gate-sync.sh` / `gate-publish.sh` 语法检查通过。

### 5.1 旧演练按 D7a 行为更新（有意的行为变更，与 §1.4 同类）

VPS 首轮回归发现：D7a 的 gate-block 接线使 5 处旧演练变红（跨周期 21/32、
D6 item1 10/15、item2 14/15、D6 红→绿 9/10、跨周期红→绿 12/13），而全套
161 项单元测试与 D7a 四项演练全绿。对照实验证明是 D7a 行为变更所致、
非环境问题：**同一台 VPS 上 D7 树原样跑跨周期 32/32、D6 item1 15/15 全绿**；
D7a 树在同样注入下 gate-block 先行拦截（`targets_inconsistent`、STOP 锁存），
旧演练期望的“下一轮同步静默修复”不再发生——这正是 GPT D7 裁决第 1 项
要求的（“不能把‘下一轮可修复’视为故障期间零风险”），与 §1.4 的
test_d6.py 更新同类。已按新行为更新 5 处演练（只改与门禁冲突的断言，
不变量——rc=1、bridge 保持已验证字节、坏路径不建文件、污染字节必隔离——
全部保留；隔离文件断言改为按 `quarantine_name` 精确定位，因 C3/B 节修复
已先留一份隔离文件）：

| 演练 | 旧断言（已作废） | 新断言 | 新计数 |
|---|---|---|---|
| `cross_cycle_drill.py` C3 | 盲 cp 后下一 gated sync 静默恢复 v1（rc=0） | gated sync 拒绝分歧（rc=1、STOP 锁存、served/bridge 留 v2）→ 受控 repair（rc=0、三方一致）→ clear_stop → 下一 sync 健康（rc=0、bridge 回 clean14）；E3 隔离断言按 `quarantine_name` 精确定位 | 37/37（+5 项） |
| `d6_item1_served_quarantine.py` B | 下一 sync 静默覆盖篡改（rc=0） | gate-block 拒绝 + STOP 锁存 + 污染 served 原样保留 + bridge 不变 → repair（隔离 600）→ clear_stop → 下一 sync 健康；C 节隔离断言按 `quarantine_name` 精确定位 | 24/24（+9 项） |
| `d6_item2_bridge_race.py` B | legacy 失败报 `legacy_copy_failed` | 缺失 legacy 是 `legacy_sha_mismatch`，gate-block 先行拦截（`gate_block_refused` + STOP 锁存）；bridge 保持已验证字节、legacy 永不写出、不假成功 | 16/16（+1 项） |
| `d6_redgreen.py` R2a | 新树 legacy 失败报 `legacy_copy_failed` | 新树 gate-block 先行拦截（`gate_block_refused`）；rc=1、bridge 保持、不假成功 | 10/10 |
| `cross_cycle_redgreen.py` wrapper | 新树 gated sync 静默恢复 v1 | 新树 gated sync 拒绝分歧（bridge 留 v2）→ repair + clear_stop → 最终 resync 健康 | 15/15（+2 项） |

更新后本地五处全绿（37/37、24/24、16/16、10/10、15/15），VPS 第二轮复跑
同样全绿（§5 首行）。D5/D6 的自愈语义（下一轮自动修复）已被 GPT D7 裁决明确否决，
不再作为验收口径；保留的自愈机制只有 run_sync 内的 served 隔离+恢复
（E3/C 节，恢复后仍进 STOP，不静默放行）。

## 6. 上传包与脱敏

- 上传包 `~/workspace/p2p3-d7a-upload/`（146 文件）与 `~/workspace/p2p3-d7a/` 树逐字节一致
（除 `drills/_d5_work` 演练草稿目录不入包；diff clean）；真实冻结文件不在包内。
- 脱敏 grep 自查：订阅域名 0、UUID 0、节点 URI scheme（trojan/vmess/vless/ss）0；
  唯一 URL 字面是 `http://127.0.0.1`（本地回环，9 处）；另 3 处良性 `://` 字面：`test_d7a.py` 的 manifest 无 URI 断言、`backup_restore_drill.py` 的 `file://` Documentation 模板行、`tools/http_recheck.py` 的 origin 拼接——均非真实节点 URI 或订阅 URL。
- 真实冻结文件（14 行真实节点 URI）**不在**上传包、不在 PR、不在任何输出里；
PR 里只有 `docs/d7a-real-freeze-manifest.json`（SHA、名字、ms、状态）。

## 7. 残余风险与仍需机主做的事

1. **手机原生整组（待机主）**：冻结候选 SHA `10e52c9643a8` 须同 SHA 原生整组
完整测速（0 失败、0 个 ≥300ms）后才有发布资格；09:05/11:24 部分截图不得
补算。候选 14 行全部是钉选行——即使整组通过，发布仍须先取消钉选豁免
（验收单第 2 项），否则 `publishable` 保持 false。
2. **DIRECT 三场景（待机主）**：三份测试订阅须在切换窗口从当时 served 版本现备。
3. **窗口执行项（待 GPT 批 + 机主在场）**：旧定时器退场、真实 stop→restore→start、
生产:07/:15 周期观察、部署后 `tools/http_recheck.py` 复跑——全部按
`docs/D7A_ACCEPTANCE.md` 逐项执行，任一失败维持现网并 STOP。
4. **已知缺口（未修，属设计边界）**：两 rename 间崩溃仍可留 bridge 新 / legacy
旧——D7a 已把该状态纳入门禁（gate-block 锁存 STOP + 手动修复），不再靠
“下一轮自动修复”；故障期间 HTTP 入口仍是修复前已验证版（演练已证），
但不一致窗口内不发布新版本。
5. **D6 旧测试与旧演练行为变更**：见 §1.4（test_d6.py）与 §5.1（5 处演练，
   旧“下一轮静默修复”断言已按 GPT D7 裁决改为门禁+受控修复断言）。
   D5/D6 自愈语义不再作为验收口径。
