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

D1（24 项）+ D2（39 项）测试全部保留并全绿（仅调用点适配：setUp
末尾加显式 init；见 `docs/D3_REPORT.md` §5）。D3 新增 23 项测试 +
状态丢失演练（11 场景）。「其次」项（systemd 接线、备份演练、
21 pinned 接线、DIRECT 测试）按任务要求不在本轮，列为 D4。

## 0. D3 修复总览：fail-closed 恢复状态

D2 的问题：`pool/recovery.py` 的 `read_state()` 在
recovery-state.json 缺失、损坏、不可读或值非法时返回默认 ok 状态；
`is_stopped()` 据此返回 False，publish/sync 照常进行；`rollback.py`
根本不查恢复状态。删除一个文件就能把一个已记录的 STOP 洗掉。

D3 的修复（详见 `docs/D3_REPORT.md`）：

- **持久锚点**（`recovery-anchor.json`，600、原子写、同锁）：
  每次状态写同时写锚点——最后已知 state/stopped、单调 seq、状态
  文件规范 JSON 的 sha256、served 版本绑定（SHA 前缀 + chain_id +
  时间戳）。单文件丢失/损坏/篡改无法重置 STOP；seq + checksum 能
  发现状态文件被旧副本替换。
- **Fail-closed 读取**：`read_state_strict()` 返回 `(state, error)`；
  `read_state()` 失败时抛 `RecoveryStateError`，永不默认 ok；
  `gate_check()` 是 publish / sync / rollback 三路共用的唯一门禁
  入口；`is_stopped()` 未知即视为 stopped；`status()` 不可建立时
  报 `state=unknown-unsafe`、`stopped=True` 并带 `state_error`。
- **显式初始化**：全新部署门禁拒绝 `recovery_state_uninitialized`。
  ok 只能由 `init_recovery_state(workdir, owner_ack)` 建立，须键入
  owner ack `OWNER-ACK-INIT-RECOVERY-STATE`（人工操作，定时器永不
  调用）。init 写状态 + 锚点，绑定当前 served 版本并记审计条目；
  三种模式：`fresh` / `rebuild-from-anchor` / `rebuild-anchor`。
  init 拒绝：已记录 STOP（删状态文件也洗不掉）、状态文件不可读/
  损坏/非法、served 与现存绑定不一致。
- **STOP 不可重置**：删状态文件而 STOP 已记录时，锚点仍说 stopped，
  门禁拒绝（`recovery_state_missing_stop_recorded`）；init 也拒绝。
- **rollback 查门禁**：持锁后、解析锚点前新增门禁检查。

威胁模型（诚实边界）：双文件设计防**事故与单文件故障**（单文件
丢失/损坏/篡改、写中断、旧文件回滚），**不防**有写权限者刻意删掉
或一致改写两个记录再跑 init 拿 owner ack——那是带审计条目的显式
操作者行为，不是事故；文件检查本身拦不住特权写者（与 D2 版本链
同一边界）。审计轨迹（history、init/rebuild 事件）是该情形的检测
手段。

快速上手（隔离环境）：

```bash
python3 -m pool.recovery init --workdir <workdir> \
    --owner-ack OWNER-ACK-INIT-RECOVERY-STATE
python3 -m unittest discover -s tests -v      # 86 项测试（D1 24 + D2 39 + D3 23）
python3 drills/state_loss_drill.py --out docs/state-loss-drill-log.json
```

## 1. 阻断 1：版本/证据绑定不足 → 版本链（version-chain-v1）

D1 的问题：`run_publish(candidate_lines, source_version_sha)` 直接信任
调用方传入的 SHA；`run_sync` 直接信任 `--source-version`；sidecar 只
是一份可任意配对的声明。旧版合格证据可被误贴到新版候选上。

D2 的修复（`pool/version_chain.py`）：
- `run_publish` 强制要求 `source_file`：在锁内对**实际字节**验
  `sha256(源文件) == source_version_sha`，不符拒绝
  `source_version_sha_mismatch`；候选行须是源文件的字节级子集
  （否则 `candidate_not_in_source`）；无 `source_file` 直接拒绝
  `source_file_required`——不存在无绑定的发布路径。
- 发布写 v2 sidecar：`version_chain = {source_sha, published_sha,
  admitted_fingerprints, published_fingerprints, chain_id}`，其中
  `chain_id = sha256(其余四字段的规范 JSON)`。
- `sync` / `rollback` 不再信任调用方版本：sidecar 链须对实际文件
  字节 + native record **重新验算**（published_sha、chain_id、
  admitted 集合三者全对上才放行）；v1-only sidecar（无链）拒绝；
  `--source-version` 改为可选项，给出时须与 sidecar 一致。
- 链校验**不问新鲜度**（TTL）：链只证明「文件与证据版本绑定」，
  新鲜度由门禁在使用时另行判定——否则 TTL 过期的锚点永远无法被
  归类为 last-verified-safe，恢复路径就断了（见 §3）。

威胁模型（诚实边界）：链防的是**误配置与过期配对**（旧证据贴新版、
sidecar 配被替换的文件、legacy 写手覆盖源文件）。它不防拥有完整
文件写权限的恶意写手——那样的人可以直接写 served 文件，绕过一切
检查；链让这种篡改事后可审计（重算即现形），但不是防线。

## 2. 阻断 2：sync 锁外取 manifest 的竞争窗口 → 全部锁内化

D1 的问题：`run_sync` 在取 flock **之前**算 `source_manifest`，
锁内复制、再拿锁外 SHA 校验 served 文件。等待锁期间合法 publish
更新了源文件，sync 会复制了新文件却报 `sync_verify_failed`——
文件没错，报错是错的，状态与实际服务版本不一致。

D2 的修复（`pool/sync.py`）：
- manifest、sidecar 读取、链校验、门禁、复制、校验**全部移到持锁
  之后**；复制前后用**锁内计算**的 SHA 验证：
  `source_sha_before == served_sha == source_sha_after`。
- 成功/失败一律反映实际已服务版本：结果含 `served_version_sha`
  与锁内 `source_manifest`，两者须一致。
- 复制后校验一旦失败（served 文件已不是门禁通过的版本）：返回
  实际 served manifest、rc=1，并**自动进入 degraded 状态**
  （STOP 标记，见 §3），绝不谎报成功。

## 3. 阻断 3：回滚与故障恢复策略冲突 → 显式恢复状态机

D1 的问题：`run_rollback` 依赖旧版本原生结果仍在 24h TTL 内且全
部通过；真实紧急故障通常发生在 TTL 已过或新一轮失败后，届时完全
无法恢复；且「保留旧服务文件」被说得像长期合格。

D2 的修复（`pool/recovery.py` + `docs/recovery-runbook.md`）：
- 状态机 `ok → degraded → manual-restored → ok`，状态文件
  `recovery-state.json`（600），所有状态写操作都在共享锁内；
  STOP 标记置位时 publish/sync 拒绝 `pool_stopped`。
- `assess_anchors()` 把每个回滚锚点分类：`verified_safe`（证据新鲜
  且全过）、`last_verified_safe`（证据曾全过、现已过期、无后续失
  败）、`unrecoverable`（无 sidecar / 链不验 / 无证据 / 证据说失败）。
  回滚被拒时结果附带这份评估与推荐动作（`manual-recovery` 或
  `rebuild-from-fresh-native-test`），不再只剩一个错误串。
- `manual_restore()`（受控人工恢复）：须机主逐字确认
  `OWNER-ACK-RESTORE-LAST-VERIFIED-SAFE`，只恢复
  last_verified_safe 锚点；恢复后状态仍是 `manual-restored`，
  STOP 不解除，served 文件定性为 `manual-restored-unverified`——
  **永不声称它当前合格**。
- `clear_stop()` 回到 `ok` 的唯一路径：机主确认
  `OWNER-ACK-CLEAR-STOP` **且** fresh 原生复测通过（门禁当场重算）。
- served 文件定性四档（`status()` 实时算）：`qualified` /
  `stale-not-qualified`（文件完好、证据过期） /
  `broken-unqualified`（文件与证据不符） /
  `manual-restored-unverified`。保留旧文件永远不等于合格。

## 4. 双门禁反例测试（GPT 口径裁决）

「同版本最新成功 + 任何后续版本原生失败作废旧成功」原则上已接受；
「后续他版本成功不作废旧版」只在旧证据仍新鲜、同指纹参数与目标
源 SHA 均匹配时成立。D2 用反例测试把边界钉死（`tests/test_d2.py`
`TestDualGateCounterexamples`）：
- 同指纹参数变更：改一个参数（密码/sni）= 新指纹 = 无证据 → 拒绝；
  只改显示名 = 同指纹 → 放行（名字不是身份）。
- 同时间多条结果：同时间戳、同版本、结果矛盾（先过后败 / 先败后过）
  → **一律拒绝**（fail-closed；列表顺序不能凌驾于失败之上）。
  同时间戳、跨版本失败 → 作废旧通过（D2 规则：后续失败按
  `tested_at >= 通过时间戳` 计，不再是严格 `>`）。
- 源版本变化：源文件换了字节、仍报旧 SHA → 拒绝；报新 SHA 但无
  新证据 → 拒绝；旧证据过期 + 新版本通过 → 旧版仍拒绝（新鲜度条件）。

## 5. 目录

```
pool/
  phone_gate.py     D0 严格版（P0 门禁；现仅作 P0 健康信号源）
  native_gate.py    D1 双门禁 + D2：后续失败按 >= 计；新增 evidence_admitted_fps
                    （TTL 无关的证据集，供链校验用）
  publish_lock.py   D0 锁 + D1 锁内写 / 版本 sidecar + D2：sidecar v2 链直通、
                    copy_sidecar（served 目录同步 sidecar）
  version_chain.py  D2 新增：版本链构建 / 校验 / sidecar 读写
  recovery.py       D2 恢复状态机 + D3：锚点 / 严格读 / gate_check /
                    init（显式初始化）/ fail-closed is_stopped / CLI init
  rules.py          D0 select_publish（未变）
  publish.py        D2 发布路径 + D3：门禁改为 gate_check
  sync.py           D2 同步路径 + D3：门禁改为 gate_check
  rollback.py       D2 回滚路径 + D3：新增步骤 2-recovery-gate（持锁后查门禁）
fixtures/           D1 合成固件（已重新生成，tested_at 刷新；池 SHA 不变）
tests/
  test_d1.py        D1 24 项（setUp 加 init）
  test_d2.py        D2 39 项（setUp 加 init）
  test_d3.py        D3 23 项（缺失/损坏/不可读/非法/写中断/篡改/锚点缺失/
                    旧副本替换/STOP 不可洗/rollback 查门禁/init 模式）
drills/
  hold_lock.py      锁持有者（崩溃演练用，未变）
  sim_timers.py     定时模拟（首次 publish 前 init）
  recovery_drill.py D2 恢复演练（每个子目录各 init 一次）
  crash_drill.py    D2 崩溃演练（首次 publish 前 init）
  state_loss_drill.py D3 新增：持久化演练（kill -9/截断/chmod 000）+
                    恢复演练（STOP→删文件→拒绝→手动恢复→fresh 证据→回 ok）
redgreen_d3_demo.py D3 新增：同一场景在 D2 树（红）/ D3 树（绿）对照
docs/
  D3_REPORT.md         本轮报告：逐模式修复、红→绿、测试数、演练、诚实边界
  D2_REPORT.md         D2 报告（保留）
  recovery-runbook.md  故障恢复处置手册（D3 更新：init 程序、权限边界、
                       状态文件丢失 runbook、禁区）
  direct-test-plan.md  D1 手机正式组 DIRECT 证据测试方案（未变，等机主定时间）
  redgreen-d3-log.txt  红→绿日志
  state-loss-drill-log.json / state-loss-drill-log-vps.json
  sim-log.json / sim-log-vps.json
  recovery-drill-log.json / recovery-drill-log-vps.json
  crash-drill-log.json / crash-drill-log-vps.json
```

## 6. 运行

```bash
python3 fixtures/build_fixtures.py            # 生成合成固件
python3 -m unittest discover -s tests -v      # 86 项测试（D1 24 + D2 39 + D3 23）
python3 redgreen_d3_demo.py /opt/p2p3-d2      # D2 树：RED（删状态文件后仍 publish 成功）
python3 redgreen_d3_demo.py /opt/p2p3-d3      # D3 树：GREEN（拒绝 recovery_state_missing）
python3 drills/state_loss_drill.py --out docs/state-loss-drill-log.json
python3 drills/sim_timers.py --workdir /tmp/d3-sim --cycles 3 \
  --candidates fixtures/pool_44_fixture.txt \
  --clean fixtures/clean_14_fixture.txt \
  --native-record fixtures/native_results_fixture.json \
  --source-version <fixture pool SHA> \
  --probe-db fixtures/p0_fixture.db --log docs/sim-log.json
python3 drills/recovery_drill.py --workdir /tmp/d2-rec \
  --candidates fixtures/pool_44_fixture.txt \
  --clean fixtures/clean_14_fixture.txt \
  --native-record fixtures/native_results_fixture.json \
  --source-version <fixture pool SHA> \
  --probe-db fixtures/p0_fixture.db --log docs/recovery-drill-log.json
python3 drills/crash_drill.py --workdir /tmp/d2-crash \
  --clean fixtures/clean_14_fixture.txt \
  --native-record fixtures/native_results_fixture.json \
  --source-version <fixture pool SHA> \
  --source-file fixtures/pool_44_fixture.txt \
  --probe-db fixtures/p0_fixture.db --log docs/crash-drill-log.json
```

## 7. 诚实边界（已验证什么、没验证什么）

已验证（隔离环境，合成固件；本地 Python 3.12.3 与 VPS Python 3.13.5
双环境，详见 `docs/D3_REPORT.md`）：

- D3 fail-closed：状态文件缺失/损坏/不可读/非法/写中断、状态被篡改、
  锚点缺失、状态被旧副本替换、STOP 后删状态文件——publish / sync /
  rollback 全部拒绝，服务文件不动；rollback 首次查门禁。
- D3 显式初始化：未 init 的全新部署三路拒绝；init 须 owner ack，
  记审计条目与 served 绑定；三种模式（fresh / rebuild-from-anchor /
  rebuild-anchor）与四种拒绝（STOP 已记录/状态不可读/served 绑定
  不一致/ack 错误）全部有测试。
- D3 状态丢失演练：kill -9 写中途（旧状态 intact、gate 照常）、
  截断、不可读、STOP→删文件→拒绝→手动恢复→fresh 证据→回 ok，
  11 场景全过。
- D2 全部能力保留：版本链、锁竞争、恢复演练、反例测试，63 项全绿；
  定时模拟、恢复演练、崩溃演练在 D3 代码上重跑全过。
- D1 全部能力保留：24 项 D1 测试全绿；定时模拟 15/15；崩溃恢复
  SIGKILL 后 0.0 秒重拿锁、文件 SHA 不变。

没验证 / 仍需的（与 D1/D2 相同，D3 未改变）：
- **固件是合成的**：TEST-NET 主机 + 假密码，只镜像 13:24 的判定结构；
  固件的 tested_at 取生成时刻，只为让演练可跑——**它不是真实手机证据，
  不重置真实 13:24 的 TTL**。生产切换前后仍各需一次新的手机原生复测。
- 锁只约束认锁的写手；链与锚点防误配置不防有写权限的恶意写手
  （见 §0 威胁模型）。
- 同时间戳跨版本更精细定序（单调 run 序号）未做（GPT 要可作 D3——
  注：D3 任务明确只做 fail-closed，此项不在 D3 内，仍待定）。
- DIRECT 证据：只能按 `docs/direct-test-plan.md` 在手机上实测，尚未跑。
- 生产切换本身：须 GPT 批准 + 完整未脱敏备份 + systemd :07/:15 切换
  方案 + 机主在场验收后才做。本目录不含任何生产切换步骤。
