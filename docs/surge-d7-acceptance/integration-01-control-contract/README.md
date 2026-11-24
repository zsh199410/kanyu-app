# Integration-01: 小池对照契约与消费者隔离（独立差异 PR）

Issue #73 · P2 分阶段隔离验收第 ① 项。PR #125 v4 已冻结（HEAD b10670d7），
本差异与 #125 分离，独立分支、独立 Draft PR。GPT 裁决依据：#73 评论
7120382777（2026-11-24 10:40，三批技术裁决：G1–G10、Q1–Q8 等）。

设计来源：`control-design.md`（§2–§7 契约、§8 验收 A1–A18、§9 回滚、
§10 未验证项、§11 可安全修改的文件分级、§12 裁决清单）。

## 本差异做什么

小池（1–6 条）试用池的测量结果从此变得可信：对照目标从试用池内改到
正式池内（正式池有 22 条已知健康节点，天然就是对照池），1–6 条任何
一档都能有合法独立控制；消费侧三处代码只认可信失败
（status='failure' AND control_verified=1 AND probe_mode='external_policy_id'
AND bearer='cellular'），其余失败只作诊断历史，永不进入删除/转正/导入
判定；DIAGNOSTIC_PASS 与 READY 明确分离。

## 文件清单（5 改 + 6 新 + 1 试用 manifest 改动）

| 文件 | 变化 | 说明 |
|---|---|---|
| `receiver.py` | +117/−15 | V2–V7 正式对照校验（env 门控；未设 env 时行为与原版完全一致） |
| `verify_promotion.py` | +185/−41 | fail_after 补同款过滤；新增 DIAGNOSTIC_PASS / MANUAL_DIAGNOSTIC_PASS 派生；路径可用 env 覆盖以便隔离测试 |
| `import_per_observation_v2.py` | +16/−6 | G10 可信失败门；detail 写 control_verified=1（live 导入器） |
| `import_phone_observations.py` | +13/−4 | 同款 G10 门（休眠导入器，同款补丁） |
| `auto_prune.py` | +55/−5 | read_failure_evidence 只认带可信来源记录的失败；未验证行另计 phone_failures_unverified |
| `formal_manifest.py` | 新，203 行 | 正式 manifest 生成器（只读；每小时；pool_sha + 代次 + 成员身份 + 每成员最近可信成功/失败时间） |
| `formal_source_groups.json` | 新，11 行 | 来源组注册表。初始只有加拿大一条有验证证据（G-matin）；其余成员缺席 = unknown（G6） |
| `formal-manifest.json.sample` | 新，9 行 | 生成器在当前 live 数据下的预期输出：22 成员、合格 0（钉选全 unknown，加拿大被试用池排除） |
| `formal_manifest.service` | 新，24 行 | 生成器 oneshot unit 草案（未安装，安装须批准） |
| `formal_manifest.timer` | 新，11 行 | 每小时 timer 草案（未安装，安装须批准） |
| `probation-manifest.json` | +1 行 | 补 `generation: 0`（从 0 起，内容每次变更 +1） |
| `test-i01-control.py` | 新，831 行 | 隔离测试脚本（A1–A18、R1–R8、D1–D11、G1–G5） |

## 关键语义（审阅要点）

1. **接收器 V2–V7**：V2 正式池 SHA + manifest 代次绑定；V3 对照身份与
   正式池条目逐字一致（对照对象须带 protocol/host/port，见下“探针侧
   契约变化”）；V4 对照不在试用池；V5 对照不是本批候选；V6 对照在
   manifest 的 eligible_controls 内；V7 probe_mode='external_policy_id'
   且 ≤2 个。任一步失败 → 422 拒整批，不写行。“丢对照、只收候选”
   的备选方案已否决（G3），不做。
2. **正式 manifest 生成器**：只读正式池 + 只读正式观测库（mode=ro +
   query_only），原子写（临时文件 + os.replace，0600）；代次从 0 起，
   仅池 SHA 变化时 +1，仅健康时间戳变化不递增；C6/C7 健康窗 24h；
   试用池成员默认排除（C2，接收器 V4 仍是权威后备）；注册表缺失时
   全 unknown、合格为空、exit 0（fail-closed，不写库）；绝不成为
   第二正式 publisher（G5：不写池文件、不写观测库、不写任何发布状态）。
3. **消费侧过滤**：三处（verify_promotion / auto_prune / 两导入器）
   统一门禁。`phone_fail_count` 从此只计可信失败；历史 phone_failures
   行因 detail 无 control_verified 字段，在新规下不计入可信失败
   （须在部署说明中明确；nonce 级追认对账不在本差异内）。
4. **DIAGNOSTIC_PASS（G10/Q2）**：同一候选身份、当前 manifest SHA/
   代次、trusted external_policy_id、cellular、双目标成功 3 次，间隔
   ≥15min 且首末 ≤24h 且 TTL 未过；可信失败重置连续计数，
   unknown/证据缺失/网络切换/代次变化不得跨过去累计；派生状态独立
   记录并关联原始观测 ID，不修改历史观测；手动单列
   MANUAL_DIAGNOSTIC_PASS，不等同自动诊断。cv=0 成功可作诊断成功，
   正式 READY 仍需独立同批控制 + 新鲜 VPS ≤300ms + Surge 原生
   <300ms + 全部发布门禁。代次缺失时不给 DIAGNOSTIC_PASS
   （MANIFEST_GENERATION_MISSING）；READY 仍按 SHA 绑定，不动既有语义。
5. **G6 缺口（fail-closed）**：钉选来源组不能由 legacy 回填凭空建立，
   未核实标 unknown，不能作为 C4 独立控制。当前注册表只有加拿大
   一条，合格控制清单初始为空是符合设计的 fail-closed 状态：
   只作诊断，真实 READY 继续 BLOCKED，直到钉选逐条核实分组。

## 探针侧契约变化（不在本差异内，B1 挡住）

- 对照对象须带 protocol/host/port：当前 live 探针只发 name +
  probe_mode + results。B1 后的探针改动须补这三个字段，否则 V3
  无法校验（接收器按正式池逐字核对）。
- C4（对照来源组 ≠ 候选来源组）是选择时不变量：由探针按 manifest
  的 source_group 与候选组过滤后挑选；接收器不校验 C4（候选来源组
  信息不在观测表/批次载荷内），事后可凭批次 + manifest 审计。
  试用 manifest 目前也不带来源组（来源组来自第 ② 项血缘模块），
  探针侧 C4 选择的具体接口在 B1 解开后另立差异。
- 试用脚本第 246 行 `<3` → `<1` 与试用 receiver MIN_POOL 3→1
  的改动也不在本差异内（B3 裁决 (c) 的自动一侧，另立独立 Draft/
  隔离验证）。

## 部署说明（须批准，本 PR 不安装任何东西）

1. 部署 receiver.py（试用接收器 + 正式接收器共用同一文件；正式
   接收器不设新 env 变量，行为不变）与 verify_promotion.py、
   两导入器、auto_prune.py 到对应 live 路径；部署前备份。
2. 部署 formal_manifest.py、formal_source_groups.json 到
   /opt/phone-telemetry/；部署 formal-manifest.json.sample 的内容
   为首版正式 manifest（generation 0）。
3. 试用 manifest 写回 generation: 0（与本 PR 的 probation-manifest.json
   一致）；updated_utc 随部署时间更新。
4. 试用接收器 env 追加（须批准的 unit/env 变更）：
   PHONE_PROBE_FORMAL_POOL=/opt/free-node-program/publish/pool-new.txt
   与 PHONE_PROBE_FORMAL_MANIFEST=/opt/phone-telemetry/formal-manifest.json，
   二者同设或同不设（仅设其一时服务启动即拒绝）；正式 manifest
   或正式池文件不可读时，有对照的批次 422、无对照的批次走传统路径。
5. 安装 formal_manifest.service + formal_manifest.timer（草案在本 PR
   内，安装须批准）；首次运行后核对正式 manifest 内容与样例一致。
6. 部署后复跑：隔离测试脚本（本 PR 内）+ live 端点测试
   test_endpoint.py（PR #118，部署后复跑，不在本差异的隔离测试内）。
7. 回滚：换回旧版 5 个文件、删正式 manifest 相关文件、去 env 变量、
   重启两个接收器；无数据库迁移，已入库观测按 pool_sha 绑定继续有效。

## 不在本差异内的事

- 不改任何 live 文件、定时器、开关；不部署；不删节点；不写
  blocklist；不改 unit；不创建密钥；不动 PR #124；不动 live 探针脚本。
- 不做第 ② 项（来源 hook/规范化/最新批次绑定）、第 ③ 项（持久禁入
  与 SNI 准入）、第 ④ 项（真实合格候选组批）、第 ⑤ 项（正式先补后清）、
  第 ⑥ 项（自动化发布门禁）。
- auto_prune_phone_first.py 未改：它只被休眠的 legacy 导入器引用，
  无任何 live 调用点；同款缺口已在 README 注明，另立差异时处理。

## 隔离测试证据（49/49 通过，VPS /tmp 隔离，live 库 0 写入）

测试脚本：`test-i01-control.py`（本 PR 内）。合成 TEST-NET 身份、
合成 token、loopback 端口 18741–18745；跑完进程全部退出、无监听残留。
live 正式池 SHA 与试用池 SHA 在测试前后一致；G5 为真实数据 dry-run
（只读）。

- A1–A17（接收器正式对照）：17/17。含 A4 对照=试用成员自身拒批
  （control_is_trial_member）、A5 身份不符（unknown_formal_control）、
  A6 不在合格清单（formal_control_not_eligible）、A7a 伪造 SHA /
  A7b 代次不符（stale_formal_pool_sha / stale_formal_generation）、
  A8 无对照向后兼容（cv=0）、A9 3 条全失败+对照成功不降级、A10/A11
  对照失败/无对照整批降级、A12 6 条池采样 4 + 2 正式对照、A13 重复
  nonce、A14 临时描述符对照、A15 3 个对照、A16 正式池变化后旧 SHA
  拒批及恢复后通过、A17 仅时间戳更新代次不变通过、代次无故递增拒批。
- R1–R8（传统模式回归）：8/8。正式接收器（8724）路径未设新 env，
  池内对照、整批降级、重复 nonce、401、422 行为与原版一致；正式
  对照名在传统模式下被拒。
- A18（消费侧过滤）：4/4。A18a：cv=0 失败不否决 READY，且 3 次
  cv=0 成功 = DIAGNOSTIC_PASS；A18b：auto_prune 在 5 行样本中只认
  2 条可信失败、3 条计入 phone_failures_unverified；A18c：v2 导入
  dry-run 只认 1/4，apply 写入 detail 含 control_verified=1；A18d：
  legacy 导入只认 1/4，3 条计入 untrusted_failure_evidence。
- D1–D11（DIAGNOSTIC_PASS 派生）：11/11。含间隔 <15min 不计数、
  可信失败/unknown/网络切换重置、跨度 >24h 不成链、TTL 过期、
  无代次、手动单列不等同自动、恰好 15min 边界、滑动窗口丢弃超
  24h 首条后仍成链。
- G1–G5（生成器）：5/5。含 dry-run 合格 2 条（甲乙）、试用成员
  排除、未知组排除、24h 外成功排除、窗内失败排除；代次两次不变
  仍为 0、池变化后递增为 1；注册表缺失时全 unknown；dry-run 不写
  文件；真实数据 dry-run：22 成员、合格 0、试用排除 1、未知组 21。

## 未解决阻塞（本差异不覆盖）

- **B1 BLOCKED**：试用探针脚本整文件复核只能经 Muse 支持的可信授权/
  安全流程解决，读取被拒就 BLOCKED，不能转述/重取/换入口绕过。
  探针侧改动（对照对象带 protocol/host/port、C4 选择、第二订阅取数、
  控制清单取数、轮换取控制、第 246 行小容量补丁）全部不在本差异内。
- **G6**：合格控制清单初始为空（只有加拿大一条有分组证据，且它
  是试用成员，C2 排除）。钉选分组须逐条真实配置身份 + 可查独立
  来源/运营方证据建立，在第 ② 项或后续差异中补。
- **C4 选择时执行**：依赖探针侧改动（B1），见上。
- **历史 phone_failures 行**：detail 无 control_verified 字段，新规下
  不计入可信失败；nonce 级追认对账不在本差异内。
- **试用池 TTL 2026-11-28**：过期后该试用代次验证资格/转正停止，
  与本差异无关，按 Q7 由获准发布流程处理。
