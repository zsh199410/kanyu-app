# D3：修复 GPT 对 D2（PR #77）的唯一 P0 阻断——恢复状态 fail-open（隔离实现）

针对 GPT D2 代码复核（Issue #73 评论 6884522235，2026-11-15 05:32）：
D2 提交已进 PR、红→绿与 63/63、15/15、22/22 是实质进展，但
**recovery-state.json 被删默认 ok 的 fail-open 仍是 P0 阻断**——
要求 D3 以缺失/损坏/不可读/非法状态/原子写中断均 fail-closed 修复，
新部署只能显式初始化（含安全锚点及审计）建立 ok，已部署 STOP 不得
靠删状态文件复位，补红→绿测试、状态持久化与恢复演练，说明初始化
与人工恢复权限边界。本目录在隔离环境实现并验证了该 P0 修复，
**生产一律未动**（未改生产目录、生产订阅、生产定时器、手机配置；
无 GitHub 操作）。

D1（24 项）+ D2（39 项）测试全部保留并全绿（仅调用点适配：
setUp 末尾加显式 init；见 §5）。D3 新增 23 项测试 + 状态丢失演练
（11 场景）。「其次」项（systemd 接线、备份演练、21 pinned 接线、
DIRECT 测试）按任务要求不在本轮，列为 D4。

## 1. 漏洞根因（D2）

`pool/recovery.py` 的 `read_state()` 在 recovery-state.json 缺失、
损坏、不可读或值非法时返回默认 ok 状态；`is_stopped()` 据此返回
False，于是 publish/sync 照常进行。`rollback.py` 在 D2 中根本不查
恢复状态。删除一个文件就能把一个已记录的 STOP 洗掉——这就是 GPT
指出的 P0。

## 2. 修复设计

### 2.1 持久锚点（recovery-anchor.json）

每次状态写入同时写 `recovery-anchor.json`（600 权限、原子
tmp+rename、与状态写在同一把 flock 内），内容：

- 最后已知 `state` / `stopped`、单调 `seq`（每次状态写自增）；
- 状态文件规范 JSON 的 `state_sha256`；
- served 版本绑定：`served_sha_prefix` + `served_chain_id` +
  `served_at`（记录时的时间戳）。

单文件丢失/损坏/篡改无法重置 STOP；`seq` + checksum 能发现状态
文件被旧副本替换（见测试 stale-state-file-replaced-by-older-copy）。

### 2.2 Fail-closed 读取

- `read_state_strict(workdir)` 返回 `(state, error)`：状态文件有效、
  锚点一致、且状态为 ok 时才放行；其余一律返回精确错误码。
- `read_state()` 改为失败时抛 `RecoveryStateError`，**永不默认 ok**。
- `gate_check(workdir)` 返回 `(allowed, error, state)`，是 publish /
  sync / rollback 三路共用的唯一门禁入口。
- `is_stopped()` 改为 fail-closed：未知即视为 stopped。
- `status()` 永不抛错：不可建立时报 `state=unknown-unsafe`、
  `stopped=True` 并带 `state_error`。

### 2.3 显式初始化

全新部署（无状态文件也无锚点）门禁拒绝
`recovery_state_uninitialized`。ok 只能由
`init_recovery_state(workdir, owner_ack)` 建立：

- 须键入 owner ack `OWNER-ACK-INIT-RECOVERY-STATE`（人工操作，
  定时器永不调用；ack 错误 → `owner_ack_required`）。
- init 写状态 + 锚点，绑定当前 served 版本（SHA + chain_id + 时间戳）
  并记审计（history）条目。三种模式：
  - `fresh`（两记录皆无）；
  - `rebuild-from-anchor`（状态文件丢失/损坏、锚点完好且未 stopped、
    served 与锚点绑定一致）；
  - `rebuild-anchor`（锚点丢失/损坏、状态文件完好且未 stopped、
    served 与状态绑定一致）。
- init 拒绝：锚点或状态文件记录了 STOP（`init_refused_stop_recorded`，
  删状态文件也洗不掉 STOP）、状态文件存在但不可读/损坏/非法
  （`init_refused_unreadable_state`，须先按手册刻意移除该文件）、
  served 与现存绑定不一致（`init_anchor_served_mismatch` /
  `init_state_served_mismatch`，改走 fresh 证据 + clear-stop 路径）。
- CLI：`python3 -m pool.recovery init <workdir> --ack <ACK>`。

### 2.4 STOP 不可重置

删状态文件而 STOP 已记录时，锚点仍说 stopped，门禁拒绝
（`recovery_state_missing_stop_recorded`）；init 也拒绝
（`init_refused_stop_recorded`）。状态转移（enter_degraded /
manual_restore / clear_stop）用 `_load_state_for_transition()`：
状态文件不可读时回退到锚点的最后已知状态，都不可用时用
fail-closed 骨架（默认 degraded / stopped=True）——因为每个转移
写出的都是 fail-closed 状态（degraded，或凭 fresh 证据 + owner ack
的 ok）。

### 2.5 锚点更新规则

锚点只由状态转移与 init 更新；publish / sync 不更新锚点。
re-init 时 served 若与锚点绑定正向不一致则拒绝，fallback 是
fresh 证据 + clear-stop。re-init 的 served 检查规则：锚点 served
SHA 非空且 served 文件存在但 SHA 不同 → 拒绝；锚点 served SHA
为空 → 直接进行并重新锚定到当前 served 文件。

### 2.6 错误码一览

| 错误码 | 含义 |
| --- | --- |
| `recovery_state_uninitialized` | 无状态文件也无锚点：全新部署，需显式 init |
| `recovery_state_missing` | 状态文件缺失（锚点未记录 STOP） |
| `recovery_state_write_interrupted` | 状态文件缺失但 `.tmp` 残留（原子写中断） |
| `recovery_state_unreadable` | 权限/IO 错误（含文件被目录替换） |
| `recovery_state_corrupt` | JSON 解析失败 / 内容不完整 |
| `recovery_state_illegal` | 未知状态值 / 形状错误 |
| `recovery_state_checksum_mismatch` | 状态文件内容与锚点 sha256 不符 |
| `recovery_state_anchor_mismatch` | 状态文件与锚点字段（state/stopped/seq）不一致 |
| `recovery_anchor_missing` | 锚点文件缺失 |
| `recovery_anchor_unreadable` / `_corrupt` / `_illegal` | 锚点不可读 / 解析失败 / 形状错误 |
| `*_stop_recorded` 后缀 | 任一码在 surviving anchor（或 state）记录了 STOP 时附加 |
| `pool_stopped` | 已记录的 STOP（状态本身有效且 stopped） |
| `init_refused_stop_recorded` | init 遇到已记录的 STOP |
| `init_refused_unreadable_state` | init 遇到不可读/损坏/非法状态文件 |
| `init_anchor_served_mismatch` / `init_state_served_mismatch` | re-init 时 served 与现存绑定不一致 |
| `owner_ack_required` | init ack 错误或缺失 |

## 3. 逐模式修复（spec 1 全部 5 类 + 锚点 2 类）

| 失败模式 | D2 行为 | D3 行为 | 测试 |
| --- | --- | --- | --- |
| 状态文件缺失 | 默认 ok，publish 成功 | 拒绝 `recovery_state_missing` | test_missing_state_file_refuses_all_three |
| JSON 损坏 | 默认 ok | 拒绝 `recovery_state_corrupt` | test_corrupt_state_file_refuses_all_three |
| 不可读（权限/IO） | 默认 ok | 拒绝 `recovery_state_unreadable` | test_unreadable_state_file_refuses_all_three（目录替换法，主）+ test_unreadable_state_file_chmod000_refuses（chmod 000，root 下 skip） |
| 非法状态值 | 默认 ok | 拒绝 `recovery_state_illegal` | test_illegal_state_value_refuses_all_three |
| 原子写中断（.tmp 残留） | 默认 ok | 拒绝 `recovery_state_write_interrupted` | test_torn_write_refuses_all_three |
| 状态文件被篡改 | 无锚点，照读 | 拒绝 `recovery_state_checksum_mismatch` | test_checksum_mismatch_refuses_all_three |
| 锚点缺失 | 无锚点概念 | 拒绝 `recovery_anchor_missing` | test_anchor_missing_refuses_all_three |
| 状态文件被旧副本替换 | 照读旧状态 | 拒绝 `recovery_state_anchor_mismatch_stop_recorded`（seq 不符） | test_stale_state_file_replaced_by_older_copy_refuses |
| STOP 后删状态文件 | 默认 ok，STOP 被洗掉 | 拒绝 `recovery_state_missing_stop_recorded`；init 也拒绝 | test_stop_survives_state_file_deletion + test_init_cannot_launder_stop |
| rollback 不查门禁 | D2 rollback 直接恢复锚点 | 持锁后、解析锚点前查 gate_check | test_rollback_consults_gate |

publish / sync / rollback 三路在拒绝时均不改 publish 与 served 文件
（测试中核对 SHA 不变）。

## 4. 红→绿证据

`tests/test_d3.py` 按「在 D2 树上失败、在 D3 树上通过」设计：

- 行为测试只用 D2 已有 API（publish/sync/rollback/read_state/
  is_stopped/status）：在 D2 上因 publish 成功（或错误码不对）而失败。
- 需要 D3 新 API（init / gate_check / RecoveryStateError）的测试
  先断言 HAS_D3：在 D2 上 import 失败即红。
- 红跑法：把 `tests/test_d3.py` 拷进 D2 树副本的 tests/ 目录跑
  （不改 D2 原树）。完整日志见 `docs/redgreen-d3-log.txt`。

| 环境 | 结果 |
| --- | --- |
| D2 树（红） | 23 项：22 失败、0 错误、1 跳过（chmod 000，root 下 skip） |
| D3 树（绿） | 23 项：22 通过、0 失败、1 跳过（同上） |

另有独立演示 `redgreen_d3_demo.py`（同一场景在 D2/D3 两树上跑）：

- D2 树：seed rc=0，删状态文件，publish rc=0 → RED-defect-reproduced。
- D3 树：init rc=0 fresh，seed rc=0，删状态文件，publish rc=1
  `recovery_state_missing` → GREEN-refused。

## 5. 测试数（本地 + VPS）

本地（Python 3.12.3）：

| 套件 | 结果 |
| --- | --- |
| D1（tests/test_d1.py） | 24/24 |
| D2（tests/test_d2.py） | 39/39 |
| D3（tests/test_d3.py） | 22/23 通过、1 跳过（chmod 000，root 下 skip；目录替换法已覆盖该模式） |
| 合计 | **85/86 通过、1 跳过、0 失败** |

VPS（Python 3.13.5）：

| 套件 | 结果 |
| --- | --- |
| D1 | 24/24 |
| D2 | 39/39 |
| D3 | 22/23 通过、1 跳过（同上） |
| 合计 | **85/86 通过、1 跳过、0 失败** |

D1/D2 适配说明（仅改调用点与 harness，不动断言——与 D2 前例一致）：
`tests/test_d1.py`、`tests/test_d2.py` 的 setUp 末尾调用
`init_recovery_state(workdir, OWNER_ACK_INIT)`（全新 workdir 本来
就是未初始化，门禁会拒绝 publish/sync/rollback，不 init 则 63 项
全挂）；`drills/sim_timers.py`、`drills/crash_drill.py`、
`drills/recovery_drill.py` 同样在首次 publish 前 init。
`tests/test_d3.py` 的 D3TestBase **不**自动 init，各测试显式控制
初始化。

## 6. 演练

### 6.1 状态丢失演练（drills/state_loss_drill.py）

本地 + VPS 各跑一次，11 场景全部通过（日志
`docs/state-loss-drill-log.json`；VPS 日志
`docs/state-loss-drill-log-vps.json`）：

| 场景 | 结果 |
| --- | --- |
| S1 kill -9 写中途 | .tmp 残留、旧状态文件 SHA 不变、gate 仍按旧状态放行（原子 rename 未发生，正确） |
| S1b 状态缺失 + .tmp 残留 | 三路拒绝 `recovery_state_write_interrupted` |
| S2 状态文件截断为 0 字节 | 三路拒绝 `recovery_state_corrupt` |
| S2b init 拒 corrupt 状态文件 | `init_refused_unreadable_state`；刻意移除后按锚点重建 |
| S3 状态文件不可读 | 三路拒绝 `recovery_state_unreadable`（root 下用目录替换法；非 root 用 chmod 000） |
| S4 STOP + 删状态文件 | 三路拒绝 `recovery_state_missing_stop_recorded` |
| S4b init 不能洗 STOP | `init_refused_stop_recorded` |
| S4c 手动恢复（确认串） | manual_restore rc=0 |
| S4d fresh 证据清 STOP | clear_stop rc=0 |
| S4e 状态回 ok | 状态 ok |
| S4f 恢复后三路 | publish/sync/rollback 全部 rc=0 |

### 6.2 其他演练（D1/D2 演练在 D3 代码上重跑）

- 定时模拟 `drills/sim_timers.py`：本地 16/16，VPS 16/16。
- 恢复演练 `drills/recovery_drill.py`：本地 22/22，VPS 22/22。
- 崩溃演练 `drills/crash_drill.py`：SIGKILL 后 0.0 秒重拿锁，
  文件 SHA 不变（本地 + VPS）。

## 7. 威胁模型（诚实边界）

双文件设计防的是**事故与单文件故障**：

- 单文件丢失、单文件损坏/篡改、写中断、旧文件回滚、状态文件被
  目录替换、权限丢失——全部 fail-closed，publish/sync/rollback
  拒绝，且 STOP 不可被删文件洗掉。
- 锚点与状态文件**不在同一写操作中同时损坏**的前提下，任一文件
  的问题都能被另一文件发现。

它**不防**以下情形：

- 有写权限者刻意删掉或一致改写**两个**记录，再跑 init 拿 owner
  ack——那是带审计条目（history 的 init 事件）的显式操作者行为，
  不是事故；文件检查本身拦不住特权写者（与 D2 版本链同一边界：
  防误配置，不防恶意写手）。审计轨迹（状态文件内 history、
  init/rebuild 事件）是该情形的检测手段。
- 两文件同时损坏且锚点也无法重建：门禁拒绝，需人工按手册走
  fresh 证据 + clear-stop 路径（见 `docs/recovery-runbook.md` §4）。
- 状态文件与锚点**同时**被旧副本替换（双文件回滚）：seq 与
  checksum 只能发现单文件回滚；双文件一致回滚在设计上不可区分
  于「本来就是旧状态」。缓解：状态文件 600 权限、history 审计、
  以及部署时把 workdir 纳入备份（备份演练属 D4）。

## 8. 仍未证明（诚实边界，D3 不变）

- **无真实手机复测**：全部证据是合成固件（TEST-NET 主机、
  TEST-ONLY 密码、tested_at=now 由固件生成时间决定）。固件跑通
  只证明代码路径，不证明真实手机测过任何节点；合成
  tested_at=now 不是真实手机证据，不重置 13:24 TTL。
- **无生产切换**：生产订阅、生产定时器、手机配置一律未动；
  systemd :07/:15 接线、备份可恢复性演练、21 pinned 生产接线、
  DIRECT 正式组证据——均未改变，属 D4，须 GPT 批准 + 机主授权
  后另行交付。
- **同时间戳跨版本更精细定序**（单调 run 序号）未做（GPT 要可作
  D3——注：D3 任务明确只做 fail-closed，此项不在 D3 内，仍待定）。
- chmod 000 测试在 root 下 skip：root 能读穿 chmod 000 是内核
  行为，不是代码缺陷；该模式由目录替换法确定性覆盖（本地 +
  VPS 均为 root 运行，故两边都 skip 该单项）。
- `recovery-state.json.tmp` 残留的清理：门禁只识别它并拒绝，
  不自动删除（删除是操作者决定，见 runbook §4）；残留 .tmp
  不影响 gate 对完好状态文件的判定。

## 9. 文件清单（D3 树）

```
~/workspace/p2p3-d3/  (VPS /opt/p2p3-d3/ 同步一致)
pool/recovery.py          # 核心：锚点 + 严格读 + gate_check + init
pool/publish.py           # 门禁改为 gate_check
pool/sync.py              # 门禁改为 gate_check
pool/rollback.py          # 新增步骤 2-recovery-gate
tests/test_d1.py          # 24 项（setUp 加 init）
tests/test_d2.py          # 39 项（setUp 加 init）
tests/test_d3.py          # 23 项（新增）
drills/sim_timers.py      # 首次 publish 前 init
drills/crash_drill.py     # 首次 publish 前 init
drills/recovery_drill.py  # 每个子目录各 init 一次
drills/state_loss_drill.py# 新增：持久化 + 恢复演练（11 场景）
redgreen_d3_demo.py       # 新增：D2 红 / D3 绿对照演示
docs/D3_REPORT.md         # 本文件
docs/recovery-runbook.md  # 更新：init 程序、权限边界、状态文件丢失 runbook
docs/redgreen-d3-log.txt  # 红→绿日志
docs/state-loss-drill-log.json      # 本地演练日志
docs/state-loss-drill-log-vps.json  # VPS 演练日志
README.md                 # 更新：init + D3 说明
```

脱敏：全树仅 TEST-NET 与 TEST-ONLY 字面量，无真实节点凭证、订阅
地址、原始 IP、令牌。
