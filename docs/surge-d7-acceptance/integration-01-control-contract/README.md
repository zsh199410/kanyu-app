# Integration-01 v2：PR #126 审查问题收口（Review 6033276893）

Issue #73 · P2 分阶段隔离验收第 ① 项的 v2 更新包。PR #126（分支
integration-01-control-contract，HEAD d67e308，Draft）已建；GPT 源码
Review 6033276893（COMMENTED，2026-11-24 11:35，针对 HEAD d67e308）
首轮审查：隔离成果认可，真实对照资格尚未闭合。裁决：#126 Draft
保留、隔离集成继续，禁止 live 部署或实际转正；#124 PAUSED，#125 v4
冻结，正式 22/21pin/单写手/auto-prune OFF；只提交最小契约修补与
针对性测试；B1 需受支持可信授权，不能绕过。

本包只做审查指出的 5 条有发布风险的增量修复，不重做参考 v4，不动
PR #124/#125/#127，不改任何 live 文件、定时器或开关，不部署、不删
节点、不写 blocklist、不改 unit、不创建密钥、不动 live 探针脚本。
v1 README 见同目录 `README-v1.md`（备份）；v1 报告见
`pr125-integration/integration-01-control-contract.md`。

设计来源：`control-design.md`（§2–§7 契约、§8 验收 A1–A18、§9 回滚、
§10 未验证项、§11 可安全修改的文件分级、§12 裁决清单）。

## v2 文件清单（7 改 + 1 新测试脚本；3 个文件未动）

| 文件 | 变化（相对 v1） | 说明 |
|---|---|---|
| `receiver.py` | +264/−18 | 试用 manifest 绑定（SHA+代次+TTL+来源组）；正式 manifest 资格快照校验与 2h 新鲜度；V8 C4 服务端验证；观测存 trial_generation + dual_target_ok；batches 存两代次 + 控制快照 |
| `verify_promotion.py` | +187/−71 | READY 改为严格门（链通过 + 链内 cv=1 + 无链后可信失败 + TTL + 代次 + 来源组已知）；旧一次成功规则只报 LEGACY_PARTIAL；DIAGNOSTIC_PASS 按最新连续序列评估 + 末次成功 24h 新鲜度；双目标证据；MANUAL 也查 TTL 与代次；legacy/stale 行分别计数 |
| `formal_manifest.py` | +41/−9 | 历史证据绑定当前 formal pool_sha 并拒未来时间行；试用池不可读时 exit 2（fail-closed，不再 WARN 跳过）；输出 qualification_snapshot（snapshot_id + generated_at == updated_at） |
| `import_per_observation_v2.py` | +25/−5 | PRAGMA 探测新列，存在时把 trial_generation + dual_target_ok 写进 phone_failures detail（审计用）；G10 门不变，不新增代次门禁 |
| `import_phone_observations.py` | +30/−10 | 同款：PRAGMA 探测新列，detail 追加 trial_generation + dual_target_ok；G10 门不变 |
| `formal-manifest.json.sample` | +5/−1 | 补 qualification_snapshot（空 eligible 列表 canonical SHA，generated_at == updated_at） |
| `probation-manifest.json` | +2/−1 | Canada 条目补 `"source_group": "G-matin"`（集成-02 注册表：Canada 由 matin-vmess 准入）；generation 保持 0 |
| `test-i01-control-v2.py` | 新，1141 行 | v2 隔离测试脚本（A1–A18、R1–R8、D1–D11、G1–G5 全部重跑 + N1–N15 新增负例）；取代 v1 的 `test-i01-control.py`（上传本包时请从分支删除旧测试文件） |
| `auto_prune.py` | 未动 | v2 无逻辑改动：_is_trusted_phone_failure 与 _staging_phone_check 均与试用代次无关（正式证据来自 8724 正式接收器，行无试用代次；dual_target_ok 是成功证明，不用于失败判定） |
| `formal_source_groups.json` | 未动 | 注册表内容不变 |
| `formal_manifest.service` / `formal_manifest.timer` | 未动 | 生成器 unit/timer 草案不变（未安装，安装须批准） |

## 按审查条目逐项的改动

### 1. C4 必须由接收器验证，不能只靠探针选择

- 接收器新增 V8：控制来源组（来自服务端正式 manifest 的
  eligible_controls 条目）必须已知（缺失/unknown → 422
  `formal_control_group_unknown`），且必须与本批**每一候选**的来源组
  都不同（同组 → 422 `control_same_source_group`；候选组未知 → 422
  `candidate_group_unknown`）。
- 候选来源组由服务端试用 manifest 逐条导出（`trial_groups`：name →
  source_group），绝不采信客户端自报字符串。试用 manifest 未配置而
  批次带对照时拒批（422 `trial_manifest_missing`）。
- 正式 manifest 的 V6 eligible set 改为 identity → source_group 映射
  （`eligible_group_by_identity`），V3/V4/V5 仍用三元组，V7 仍检查
  probe_mode 字符串；通过的控制记入批次 `control_snapshot`（控制
  name/protocol/host/port/source_group + formal_generation +
  formal_pool_sha + trial_generation + trial_pool_sha），随 batches 行
  持久化，可供事后审计。
- 旧正式接收器兼容不变（未设新 env 时走传统路径；无对照批次不消费
  正式 manifest、不校验 C4）。B1/G6 未解时只允许隔离验证契约，禁止
  伪造控制。探针侧契约变化见下“探针侧契约变化（v2 更新）”。

### 2. 试用 generation 进入验证与入库；正式 manifest 另绑资格快照

- 接收器 `validate()` 签名加 `trial_manifest=None`，返回改为
  `(observations, batch_meta)`；观测元组由 10 元扩为 11 元（末位
  `dual_target_ok`）。
- 试用 manifest 绑定（在解析试用池之后、对照处理之前）：manifest 须
  为 dict；其 pool_sha 须等于试用池文件 SHA（否则
  `stale_trial_manifest`）；TTL 须 live（否则 `trial_ttl_expired`，
  TTL 日期为最后有效日，UTC 日期比较）；generation 须为 int（否则
  `trial_generation_missing`）；entries 须为 list；payload 的
  trial_generation 若 present 须为 int 且等于 manifest 代次（否则
  `stale_trial_generation`），若缺失则为 legacy 批次（接受，行存 NULL
  代次）。Handler 在 env 配置了试用 manifest 但不可读/不可解析时，
  全部批次 422（fail-closed）；main() 要求试用 manifest 须与正式
  env 配对（缺正式 env 时设试用 manifest 即 SystemExit）。
- 入库：phone_observations 加 `trial_generation INTEGER`（NULL =
  legacy）、`dual_target_ok INTEGER NOT NULL DEFAULT 0`；batches 加
  `trial_generation INTEGER`、`formal_generation INTEGER`、
  `control_snapshot TEXT`（CREATE TABLE 与增量迁移两处都加；旧库
  用 ALTER TABLE 补列，幂等）。
- 正式 manifest 当前同 SHA 的 eligible_controls 更新不递增
  generation，v2 另绑资格快照：生成器输出
  `qualification_snapshot`（snapshot_id = canonical eligible 列表
  SHA-256，generated_at 与 updated_at 一致）；接收器在有对照的批次
  里校验快照 id（不符 → `formal_manifest_snapshot_mismatch`）、
  updated_at 新鲜度（超前 >300s 或早于 now−7200s → 
  `stale_formal_manifest`，生成器每小时运行，超 2 小时即过期清单）、
  generated_at == updated_at；任一步失败 → 422 拒整批。无对照批次
  不消费正式 manifest（与 v1 的正式 manifest 不可读处理一致）。
- verify_promotion 只取 trial_generation == 当前代次的行计入新判定；
  legacy（NULL）与跨代行分别计数（`legacy_rows` / `stale_gen_rows`），
  永不进入新门；A→B→A 相同字节不再串代。

### 3. 正式控制生成器历史成功绑定当前 formal pool_sha

- `success_24h` / `failure_24h` / `last_failure` 三查询加
  `pool_sha = 当前 formal pool_sha` 过滤与 `received_at <= now`
  （拒未来时间行）；pool_sha 是配置变体身份（同字节 = 同配置）。
- 试用池不可读时由 WARN 跳过改为 exit 2 FAIL-CLOSED（拒绝生成，
  不继续使用过期清单）；无法读取可信试用/正式快照时合格清单置空
  或拒绝生成。正式 22 条容量保护不放宽。
- 输出 manifest 加 `qualification_snapshot`（见条目 2）；docstring
  更新。G6 缺口不变：注册表初始只有加拿大一条，合格控制清单初始
  为空是符合设计的 fail-closed 状态。

### 4. DIAGNOSTIC_PASS / READY 误判收口

- 双目标证据：`classify` 仍保留两目标任一 reachable 即返回
  success/target_reachable 的旧 raw/status 语义，但每观测新增
  `dual_target_ok`（仅两目标 state 全为 reachable 时为 1）；链
  判定（`classify_chain_row`）要求 dual_target_ok==1，单目标
  “成功”不再计入链（N2）。
- 最新连续序列：`derive_diagnostic_pass(rows, now)` 不再达到第三次
  就 return True；全程扫描，任一失败/unknown/不合规成功重置连续
  计数；最后成功须满足 0 <= now − last <= 86400（末次成功 24h
  新鲜度）；未来时间行按 other 处理（不计数、不重置跨代）。
- READY v2 = ttl_ok + generation_ok + 链通过 + 链内至少 1 次 cv=1
  成功 + fail_after（cv=1）== 0 + manifest entry source_group 已知
  非 unknown，否则 NOT_READY 附 reason（TTL_EXPIRED / TTL_INVALID /
  MANIFEST_GENERATION_MISSING / SOURCE_GROUP_UNKNOWN /
  NO_DIAGNOSTIC_CHAIN / NO_CONTROL_VERIFIED_SUCCESS /
  TRUSTED_FAILURE_AFTER_SUCCESS）。旧一次成功规则输出改为单独的
  LEGACY_PARTIAL 行（永不标 READY）；MANUAL_DIAGNOSTIC_PASS 也查
  TTL 与代次绑定 + dual_ok。输出保留原 grep 子串（`-> READY`、
  `diagnostic=DIAGNOSTIC_PASS`、`DIAGNOSTIC_PASS count: 1`、
  `diagnostic=NOT_READY`、`diagnostic=TTL_EXPIRED`、
  `diagnostic=MANIFEST_GENERATION_MISSING`、
  `manual=MANUAL_DIAGNOSTIC_PASS`）。
- 补充的真实负例（N1–N4、N12）：第三次之后失败、仅一目标
  reachable、跨代同 SHA、TTL 过期（READY 与 MANUAL 均为
  TTL_EXPIRED）、legacy 行不计入新判定。
- v1 断言变更说明：A18a 的 v1 断言“cv=0 失败不否决 READY”被最新
  连续序列规则取代——链后失败会重置链，不再是“不否决”；A18a v2
  改为 3 次 cv=0 成功 + 1 次链内 cv=1 成功 = READY +
  DIAGNOSTIC_PASS，另加 legacy 行只报不计数的情形（N1 覆盖链后
  失败的否决）。

### 5. 回退方案：保留新观测与旧消费者安全隔离

- 回滚只恢复 v1 receiver.py；保留 v2 verify_promotion.py、
  auto_prune.py、两导入器——NULL 代次 / dual_target_ok=0 的行按
  legacy 处理，永不计入新判定；永不恢复 v1 消费者（否则新诊断
  失败会重新成为清退证据）；永不整库恢复；永不删行；回滚前后跑
  verify_promotion.py 核对。
- **N15 实测修正（v2 新发现）**：仅恢复 v1 receiver.py 是不够的——
  v1 receiver 的 batches INSERT 写 3 个值，而 v2 库 batches 表有
  6 列，未打补丁的 v1 接收器写不进 v2 库（实测 422，行数不变，
  N15b）。回滚 runbook 必须含 1 行补丁：把 v1 receiver 的
  `INSERT INTO batches VALUES(?,?,?)` 改为显式列名
  `INSERT INTO batches (nonce, received_at, payload_sha)
  VALUES(?,?,?)`（不改 v1 语义）；打补丁后 v1 接收器可写入 legacy
  批次（行存 NULL 代次、dual_target_ok=0），v2 行完好，v2 判定器
  仍正确区分新旧证据（N15c/d）。任何 schema 兼容变更仅在隔离
  验收，不整库恢复。

## 探针侧契约变化（v2 更新，不在本差异内，B1 挡住）

- 对照对象须带 protocol/host/port：当前 live 探针只发 name +
  probe_mode + results。B1 后的探针改动须补这三个字段，否则 V3
  无法校验（接收器按正式池逐字核对）。
- C4 现在由接收器服务端验证（条目 1），探针侧仍须按 manifest 的
  source_group 与候选组过滤后挑选控制（选择时不变量）；接收器
  不校验 C4 的选择过程，只校验结果。试用 manifest 现在带来源组
  （本包 probation-manifest.json 已补 Canada 的 G-matin；其余试用
  成员的来源组来自第 ② 项血缘模块）。
- 试用脚本第 246 行 `<3` → `<1` 与试用 receiver MIN_POOL 3→1
  的改动也不在本差异内（B3 裁决 (c) 的自动一侧，另立独立 Draft/
  隔离验证）。

## 部署说明（须批准，本 PR 不安装任何东西）

1. 部署 receiver.py（试用接收器 + 正式接收器共用同一文件；正式
   接收器不设新 env 变量，行为不变）与 verify_promotion.py、
   两导入器到对应 live 路径；部署前备份。auto_prune.py 未改，不
   用重部署。
2. 部署 formal_manifest.py、formal_source_groups.json 到
   /opt/phone-telemetry/；部署 formal-manifest.json.sample 的内容
   为首版正式 manifest（generation 0，含 qualification_snapshot）。
3. 试用 manifest 写回 generation: 0 与 Canada 的 source_group
   G-matin（与本 PR 的 probation-manifest.json 一致）；updated_utc
   随部署时间更新。
4. 试用接收器 env 追加（须批准的 unit/env 变更）：
   PHONE_PROBE_FORMAL_POOL=/opt/free-node-program/publish/pool-new.txt
   与 PHONE_PROBE_FORMAL_MANIFEST=/opt/phone-telemetry/formal-manifest.json，
   二者同设或同不设（仅设其一时服务启动即拒绝）；新增
   PHONE_PROBE_TRIAL_MANIFEST=/opt/phone-telemetry/probation-manifest.json，
   须与正式 env 配对（缺正式 env 时设试用 manifest 即启动拒绝）；
   正式 manifest 或正式池文件不可读时，有对照的批次 422、无对照
   的批次走传统路径；试用 manifest 不可读时全部批次 422。
5. 安装 formal_manifest.service + formal_manifest.timer（草案在本 PR
   内，安装须批准）；首次运行后核对正式 manifest 内容与样例一致
   （含 qualification_snapshot）。
6. 部署后复跑：隔离测试脚本（本 PR 内）+ live 端点测试
   test_endpoint.py（PR #118，部署后复跑，不在本差异的隔离测试内）。
7. 回滚：换回 v1 receiver.py **并打 1 行 batches-INSERT 补丁**
   （见条目 5）；保留 v2 消费者；删正式 manifest 相关文件、去 env
   变量、重启两个接收器；无整库恢复，已入库观测按 pool_sha +
   generation 绑定继续有效；回滚前后跑 verify_promotion.py 核对。

## 不在本差异内的事

- 不改任何 live 文件、定时器、开关；不部署；不删节点；不写
  blocklist；不改 unit；不创建密钥；不动 PR #124；不动 PR #125；
  不动 PR #127；不动 live 探针脚本。
- 不做第 ② 项（来源 hook/规范化/最新批次绑定，见 PR #127）、
  第 ③ 项（持久禁入与 SNI 准入）、第 ④ 项（真实合格候选组批）、
  第 ⑤ 项（正式先补后清）、第 ⑥ 项（自动化发布门禁）。
- auto_prune_phone_first.py 未改：它只被休眠的 legacy 导入器引用，
  无任何 live 调用点；同款缺口已在 v1 README 注明，另立差异时处理。

## 隔离测试证据（67/67 通过，VPS /tmp 隔离，live 库 0 写入）

测试脚本：`test-i01-control-v2.py`（本 PR 内，取代 v1 的
`test-i01-control.py`）。合成 TEST-NET 身份、合成 token、loopback
端口 18751–18757；跑完进程全部退出、无监听残留。live 正式池 SHA
与试用池 SHA 在测试前后一致（正式池 22 行、试用池 1 行，三库行数
不变）；G5 为真实数据 dry-run（只读）。

- A1–A18（接收器正式对照 + 消费侧过滤）：18/18 重跑无回归。
  A1–A3/A8/A9/A12 另断言行存 trial_generation=0 与 dual_target_ok
  （成功=1、失败=0）；A18a v2：链内 cv=1 成功 = READY（reason=OK，
  legacy=LEGACY_PARTIAL），3 次 cv=0 成功 = DIAGNOSTIC_PASS，
  legacy 行（3 条 NULL 代次 cv=1 成功）只报 LEGACY_PARTIAL、不
  计入新判定；A18b：auto_prune 在 5 行样本中只认 2 条可信失败；
  A18c：v2 导入 dry-run 只认 1/4，apply 写入 detail 含
  control_verified=1 与 trial_generation=null、dual_target_ok=0；
  A18d：legacy 导入只认 1/4，detail 含 trial_generation=None、
  dual_target_ok=0。
- R1–R8（传统模式回归）：8/8。正式接收器（8724）路径未设新 env，
  池内对照、整批降级、重复 nonce、401、422 行为与原版一致；行存
  NULL 代次、dual_target_ok=0（legacy 证据）。
- D1–D11（DIAGNOSTIC_PASS 派生）：11/11 重跑无回归。D6 未来时间
  行被排除后仍为 NOT_READY；D11 t0 改为 now−100000（避免未来时间
  行）；其余含间隔 <15min 不计数、可信失败/unknown/网络切换重置、
  跨度 >24h 不成链、TTL 过期、无代次、手动单列不等同自动、恰好
  15min 边界、滑动窗口丢弃超 24h 首条后仍成链。
- G1–G5（生成器）：5/5 重跑无回归。G1 dry-run 合格 2 条（甲乙）
  且输出含 qualification_snapshot；G5 真实数据 dry-run：22 成员、
  合格 0、试用排除 1、未知组 21、只读不写。
- N1–N15（新增负例）：15/15。N1 第三次成功后失败使
  DIAGNOSTIC_PASS 失效；N2 仅一目标 reachable 不计数；N3 跨代同
  SHA 旧代次行不计数（stale_gen_rows=3）；N4 TTL 过期时 READY 与
  MANUAL 均为 TTL_EXPIRED；N5 C4 同组对照 422
  control_same_source_group；N6 候选组未知 422
  candidate_group_unknown；N7 对照组未知 422
  formal_control_group_unknown；N8 正式 manifest 过期 422
  stale_formal_manifest；N9 资格快照被篡改 422
  formal_manifest_snapshot_mismatch；N10 试用 manifest 无代次 422
  trial_generation_missing；N11 试用代次不符 422
  stale_trial_generation；N12 legacy 行不计入新判定（只报
  LEGACY_PARTIAL）；N13 生成器试用池不可读 exit 2；N14 生成器
  排除未来时间成功行；N15 回滚隔离：未打补丁的 v1 接收器写不进
  v2 库（422，行数不变），打 1 行补丁后写入 legacy 行且 v2 行完好，
  v2 判定器仍区分新旧证据（legacy_rows=1）。
- 首轮 66/67：A18a 初版测试数据把第 4 条 cv=1 成功放在第 3 条后
  仅 600 秒（<15min），按规则正确地不计入链，判定器输出
  NO_CONTROL_VERIFIED_SUCCESS 是正确行为；修正测试数据为间隔
  1200 秒后 67/67 全过。判定器代码未改。

## 未解决阻塞（本差异不覆盖）

- **B1 BLOCKED**：试用探针脚本整文件复核只能经 Muse 支持的可信授权/
  安全流程解决，读取被拒就 BLOCKED，不能转述/重取/换入口绕过。
  探针侧改动（对照对象带 protocol/host/port、C4 选择、第二订阅取数、
  控制清单取数、轮换取控制、第 246 行小容量补丁）全部不在本差异内。
- **G6**：合格控制清单初始为空（只有加拿大一条有分组证据，且它
  是试用成员，C2 排除）。钉选分组须逐条真实配置身份 + 可查独立
  来源/运营方证据建立，在第 ② 项或后续差异中补。
- **C4 选择时执行**：依赖探针侧改动（B1），见上；接收器只校验结果。
- **历史 phone_failures 行**：detail 无 control_verified 字段，新规下
  不计入可信失败；nonce 级追认对账不在本差异内。
- **试用池 TTL 2026-11-28**：过期后该试用代次验证资格/转正停止，
  与本差异无关，按 Q7 由获准发布流程处理。
- **B5**：HMAC 密钥创建与 unit 改动不在本轮生产许可内，本差异只含
  代码与说明；缺密钥 fail-closed。
