# 可信 Surge 原生测速采集链路 (native-evidence)

任务 B 交付: 候选冻结 / 原生测速采集 / 证据校验 / 影子审计。
全部 Python 3 标准库, 不联网, 不读 / 不写生产路径,
不改生产 Surge 配置、不停生产 timer、不删节点。

## 文件

| 文件 | 作用 |
| --- | --- |
| `candidate-freeze.py` | B1 候选冻结: `freeze_candidate()` / `verify_candidate()` |
| `native-collector.py` | B2 原生测速采集: `build_evidence_chain()` / `judge_evidence()` / `check_batch_limits()` / `post_timeout_policy()`；F 轮新增 `apply_calibration()` / `apply_loaded_proof()` / `validate_loaded_proof_fields()` |
| `evidence-validator.py` | B3 证据校验 + 影子审计: `validate_evidence()` / `audit_shadow()` / `run_example()`；F 轮新增 `loaded_proof_ok` 一致性检查 |
| `phone-loaded-proof.py` | F2 手机已加载订阅证明: `verify_byte_level()` / `verify_loaded_members()` / `classify_loaded_proof()` / `attach_loaded_proof()` |
| `calibration.py` | F3 口径对照校准: `parse_api_latency()` / `build_paired_row()` / `calibrate()` / `measurement_verified_from_calibration()` |
| `stability-ranker.py` | 48小时同网络分轨稳定性排名：连接成功率优先、300ms仅优选目标、独立15分钟窗口去重、任何结果均不授权删除 |
| `api-capability-report.json` | F1 只读查询真实原始响应 (脱敏后) |
| `README.md` | 本说明 |
| `isolated-evidence-example/` | 示例入口产出的隔离证据 (运行后生成, 非生产路径) |

## 数据链

```
VPS 生成订阅字节
  -> candidate-freeze.freeze_candidate(bytes, source_revision)
       产出冻结记录: candidate_id / payload_sha256 / member_set_sha256 /
       candidate_created_at / source_revision / policy_fingerprint
  -> 手机 Surge 加载该候选, 原生测速
       (1) VPS 已生成的订阅  (冻结 payload_sha256)
       (2) HTTP 实际返回的订阅 (下发时实测响应字节 SHA, 须与 (1) 比对)
       (3) 手机实际加载的订阅  (phone_loaded_sha, 须手机端独立验证)
       三者缺一不可, 不得由 (1)==(2) 推断 (3) 已加载。
  -> native-collector.build_evidence_chain(...) 组装证据记录
  -> native-collector.judge_evidence(...) 判定 verdict
  -> evidence-validator.validate_evidence(record, candidate_record)
       校验 schema / 绑定 / 时效 / phone 限制 / 钉选保护
  -> evidence-validator.audit_shadow(...) 影子审计十项计数,
       只写隔离证据目录, 判定 removal_candidates 与 decision
```

候选内容变化、指纹不一致、成员变化时, 旧冻结记录立即失效,
基于它的测试结果失去生产准入资格 (validator 强制执行)。

## phone_loaded_sha 为 UNKNOWN 的含义与限制

- `phone_loaded_sha` 只有手机端独立上报 / 独立读取到的已加载订阅 SHA
  才能填入 64 位 SHA-256 值。
- 无法独立验证时必须记 `"UNKNOWN"`, 不得伪造已验证。
- `"UNKNOWN"` 的证据:
  - 可以保留为测量记录 (延迟数字本身如实记录);
  - **禁止用于生产下架** (validator 的 `eligible_for_removal` 为 False);
  - 延迟 <300ms 时也不能判为合格 (`judge_evidence()` 判 `UNVERIFIED`),
    因为无法确认手机加载的是同一候选。
- 沙盒内无真机: 测试与示例中的 `phone_loaded_sha` 必须为 `"UNKNOWN"`,
  这是诚实结论, 不是缺陷。真机验证链路接通后才可填入真实 SHA。

## 只读影子筛选：可以执行，但**绝不修改生产**（2026-11-19）

两个纯 Python 标准库文件：
- `shadow-selection-plan.py`：基于 `stability-ranker.py` 汇总按网络分轨的节点候选排序、可信失败的建议排除、高延迟复测；输出 `publishable=false`、`production_write_authorized=false`、`production_delete_authorized=false`。21条钉选缺失、STOP 或状态未知时所有候选不可放行。
- `shadow-readonly-cli.py`：受信私有环境从标准输入读取一份**已脱敏** JSON 清单，输出不含节点名、节点URI、真实IP或密码的统计报告到标准输出。不打开生产文件、不发网络请求、不写文件、不触发测速POST。用于验收和审计，不是发布器。

输入 JSON 必须包括：
`candidate_names`（完整且去重的节点名称列表）、
`pinned_names`（真实21个受保护名称）、
`evidence_records`（原生采集证据；缺可信证明用空列表）、
`frozen_payload_sha`（源候选冻结字节的64位小写SHA256）、
`network_bearer`（wifi/cellular）、`stop_status`（RUNNING/STOP）。
**请只在受信的本地设备上生成并保管清单**，不把任何实际节点URL、口令、
手机完整配置、原始证据提交到 GitHub。没有可靠手机来源证明时
`evidence_records=[]`，输出 `verified_observation_nodes=0`、
`eligible_shadow_count=0`，这是诚实结果，不代表可用池为空。

离线执行（先在受信机准备非生产的 `/tmp/shadow-input.json`）：

```bash
cd docs/surge-d7-acceptance
python3 native-evidence/shadow-readonly-cli.py \
  < /tmp/shadow-input.json
python3 -m unittest discover -s tests -p 'test_shadow*.py' -v
```

当前**没有**将此模块部署到 VPS 定时服务或改动手机 Surge 配置。
GitHub Actions 测试只使用 TEST-NET 虚构样例，不能当成生产池节点质量证据。
要启用生产自动筛选，先完成可信样本覆盖和发布器数据链的独立证明，
以及旧写手排空/防 DIRECT/回滚验收与机主单独批准。
永久节点删除另行门禁，不能因为当前 `proposed_active_exclusion_count>0`
就自动编辑 served/staging。

## 节点即时筛选策略（机主 2026-11-19 更新）

- **可信原生连接测速失败**（同一冻结候选、真实手机加载字节证明、
  API口径已校准、同一bearer的实际失败）：直接标记
  `FAILED_EXCLUDED`，**立即从自动可用候选剔除，不参与自动选路**，
  无需先累计8次。该行为不等于从订阅永久删除。
- **测速成功但 >=300ms**：仍是成功连接，置
  `retest_high_latency=True`，安排复测并降低优选顺序，不因高延迟删除。
- **复测重新成功**：撤销之前的 `FAILED_EXCLUDED`，但样本不足时
  继续 `INSUFFICIENT_EVIDENCE`，而不是强行标为优选。
- **数据缺失、Smart组只返回赢家、未知语义、phone_loaded_sha=UNKNOWN**：
  无法认定真实测速失败，也不能据此剔除或删除。Wi-Fi和蜂窝必须分开判断。
- **21条钉选成员保护**：失败可以暂停自动选中，但不能自动从订阅删除、
  修改钉选、取消STOP或触碰生产数据。永久删除仍要求独立发布门禁。
- 上述逻辑目前落在只读 `stability-ranker.py` 分类器中：
  `exclude_from_active_selection` 与 `retest_high_latency` 是候选筛选
  的**建议输出**，尚未接入日用配置生产发布，不能宣称真机池已自动执行。

## 判定标准 (judge_evidence / validate_evidence)

| 情形 | verdict |
| --- | --- |
| schema 缺字段 / 类型错误 | `UNVERIFIED` |
| policy_identifier 与当前策略不一致 (版本不一致) | `UNVERIFIED` |
| 已过期 (TTL 24h) | `UNVERIFIED` |
| 原生语义未校准 (`measurement_verified` 为 False) | `UNVERIFIED` |
| 延迟 <300ms, 且语义已校准、手机加载已验证、未过期 | `PASS` (合格候选条件之一, 不是生产准入) |
| 延迟 <300ms 但 phone_loaded_sha 为 UNKNOWN | `UNVERIFIED` |
| 延迟 >=300ms | `ABOVE_TARGET` (超过优选目标，但连接正常，保留并降低优先级；原始延迟保留) |
| 超时或失败 (`latency_ms` 为 null 且 raw_result 有明确失败信号) | `FAIL` (原始失败证据保留) |
| 未测试 (`latency_ms` 为 null 且无失败信号) | `UNKNOWN` |

补充硬规则:

- `latency_ms` 为 null 时 verdict 不得为合格。
- `latency_ms` 只取 `raw_result` 中显式的数值型 `latency_ms`,
  没有即为 null, 绝不从其他字段推导、绝不编造延迟。
- 21 条钉选即使测速失败也不能由清理器删除 (validator 强制)。
- 可用于生产下架的“可信失败证据”须同时满足:
  绑定一致 + 未过期 + `measurement_verified=True` +
  `phone_loaded_sha` 已验证 + 失败信号真实
  (仅原生连接失败的多次独立可信样本；单次超时或 >=300ms 不可下架) + 非钉选。
  任一不满足即不计入 `removal_candidates`。
- **当前独立修复版主动锁定 `eligible_for_removal=False`，任何单次证据均不可触发自动删除。**
  即使多个时段持续失败，目前也只进入 `QUARANTINE_REVIEW`，须另行实现并验证
  跨时段删除许可、来源可信度、回滚与21钉选完整性才能启用删除。
- `ABOVE_TARGET` 不等于 `FAIL`；历史 `FAIL_LATENCY` 仅保留旧记录解析兼容，
  新版本不再生成该状态。
- STOP 状态下 `removal_candidates` 强制为 0, decision 为 `NO_SAFE_REMOVAL`。

## Surge API 测试值与手机界面显示值的语义对照

> **未校准结论 (当前状态): `measurement_verified` 必须保持 `False`。**

- Surge API / 测试接口返回的 `round-one-total`、`available`、`tcp`、
  `receive` 等字段, **均不等于** Smart 组内显示分。
- Smart 组报的是**第二轮分数**, 第一轮总值 (`round-one-total`) 只是
  第一轮的汇总, 不是组内显示的那个数字。
- `available` 是数值型毫秒 (不是布尔值), 同样不等于组内显示分。
- 在“API 值如何映射到手机界面显示值”完成对照校准之前,
  任何由这些字段直接得出的“延迟”都不能当作手机显示延迟使用,
  `measurement_verified` 保持 `False`, 判定一律 `UNVERIFIED`。
- 校准工作须用真机对照实测完成 (同一节点同一时间 API 值 vs 界面显示值),
  校准通过后才可将 `measurement_verified` 置为 `True`,
  并把校准方法与对照样本写入本 README 的校准记录节。
  在此之前, 本链路只产出“未验证的原始测量记录”, 不产出生产准入结论。

## F 校准首轮：只读 API 能力探测（2026-11-19）

代码入口：`f-readonly-api-probe.py`。这一步**只确认 API 能返回何种
字段**，不触发测速，不构成 F CALIBRATED，不修改订阅/节点/配置。
必须在与 iPhone 同一可信私网的机器（或已有的受信桥接主机）执行；
不支持从公开互联网直接访问手机的 HTTP API。

```bash
export SURGE_API_BASE="http://<phone-private-ip>:6171"
read -rs -p 'Surge API key: ' SURGE_API_KEY; printf '\n'
export SURGE_API_KEY
SURGE_GROUP_NAME='免费节点池' python3 native-evidence/f-readonly-api-probe.py \
  > /tmp/surge-f-get-only-redacted.json
unset SURGE_API_KEY
```

首轮只读 GET：`/v1/policies?include_external=true`、
`/v1/policy_groups`、
`/v1/policy_groups/test_results?group_name=免费节点池`。
如明确指定 `SURGE_POLICY_NAME`，再额外探测该策略的
`/v1/policies/detail`。输出仅含响应类型、有限键名、项目数量、
已知数值型延迟字段；**不含原始节点名、地址、URI、凭据、
identifier 或完整 API 原文**。出错也不回显响应体，不自动重试，
`post_count=0`，一律 `calibration_verdict=UNCALIBRATED`。
只把脱敏输出送到 Issue #73；真实 API 数据只留私有环境。

**注意：此 GET 探测若仍无逐节点数值，就必须先验证单节点测试接口
真实可寻址，再执行首个受控 POST（至多1个 identifier，每小时最多
1批，超时不重发），并与当时手机界面读数配对。不能把多个
手动截图、自动组赢家或自写 HTTP 请求当作真正 API/UI 配对。**
官方参考：https://manual.nssurge.com/tools/http-api.html 与
https://manual.nssurge.com/tools/testing.html 。

## F 轮实测结论 (2026-11-18 20:25–20:40 CST, 真机只读查询)

> 本节为任务 F 的实测结论, 证据见 `api-capability-report.json`
> (脱敏后)。有副作用 POST **未做** (0 次), 生产零改动。

### F1 只读查询: 能获取什么、不能获取什么

经 Surge 桥下发 7 次只读 GET (桥指令 1795004725、1795005131,
全部 `via=httpAPI`, 无 POST):

| 查询 | 真实结果 |
| --- | --- |
| `GET /v1/policy_groups/select` (无参数) | `{"policy": null}`——不带 group_name 时不返回选中状态 |
| `GET /v1/policy_groups/select?group_name=免费节点池` | `{"policy": "香港2 🇭🇰"}`——池组当前选中该成员 (显示名) |
| `GET /v1/policy_groups` | 18 条规则; `免费节点池` 规则下 30 条, 全部 enabled、全部 isGroup=false, 类型 Trojan 23 / Shadowsocks 5 / VMess 2; 条目字段只有 enabled / isGroup / lineHash / name / typeDescription |
| `GET /v1/external_resources` | `defines` 108 项, 全部 ready=true、updating=false; 类型 script 87 / ruleset 18 / policy-group 2 / data 1; 2 个 policy-group 资源的 updatedAt 为 2026-11-18 14:44:22 与 19:55:17 CST |
| `GET /v1/profiles/current?sensitive=0` | profile 全文 1786 行、originalProfile 150 行; 无 managed-config 行、无 pool-new 字样; 不含任何已加载订阅字节 SHA |
| `GET /v1/policies` | 18 个策略组、22 个直连代理 (仅记数量); 不返回池成员 |
| `GET /v1/policy_groups/test_results?group_name=免费节点池` | 只返回两个 Smart 组当前选中策略 (`日本自动` / `美国自动` 各 1 个), **没有**逐节点延迟字段 (无 round-one-total / available / tcp / receive / latency_ms) |

**Surge 版本号: 无法获取。** 7 次响应全文检索 `version` 键为 0 命中,
本轮 5 个端点不提供版本号。

**能获取的已加载信息:** 策略组当前选中策略、已加载成员名/类型/
启用状态、策略组与直连代理名列表、外部资源 ready 与 updatedAt、
当前配置全文。
**不能获取的已加载信息:** 手机端已加载订阅字节 SHA (无任何端点返回)、
订阅源 URL 的 SHA、逐节点 API 延迟字段 (按本轮查法)、手机界面显示的
延迟数字 (须人工读数)。

### F2 phone_loaded_sha: 字节证明不可行, 弱证明成立

- **字节级证明 (BYTE_PROOF): 不可行。** 7 次响应中没有任何字段含
  手机端已加载订阅字节 SHA, `phone_loaded_sha` 保持 `"UNKNOWN"`,
  不得伪造。
- **弱证明 (MEMBERS_VERIFIED): 成立 (真实数据回放验证)。**
  手机端 `免费节点池` 成员名集合 (30 名) 与源端 served 池文件成员名集合
  逐名一致, 类型分布一致 (Trojan 23 / Shadowsocks 5 / VMess 2);
  成员名集合 SHA-256 均为
  `a1f9f711b716316b2564bc59ebfab90f2e7ec2e9de5ad5f48434dc5c979f8063`。
  该结论由 `phone-loaded-proof.classify_loaded_proof()` 在真实响应上
  回放得出, 代码见 `phone-loaded-proof.py`, 测试见
  `tests/test_phone_loaded_proof.py` (含 mock 回放)。
- 弱证明只证明“成员名一致”, 不证明字节一致 (同名成员可对应不同
  URI/密码/参数)。`loaded_members_verified=True`,
  但 `phone_loaded_sha` 仍为 `"UNKNOWN"`,
  `production_admission` 恒为 `"PENDING_REVIEW"`——生产准入资格须单独审查,
  校验器仍判 `eligible_for_removal=False`, 不可据此下架。
- 证明等级: `BYTE_PROOF` (唯一能填真实 SHA) >
  `MEMBERS_VERIFIED` (弱证明, 准入待审查) > `UNVERIFIED`。
  配置文件内容 / ready 状态 / updatedAt / 源端 SHA 一律不算已加载证明,
  `classify_loaded_proof()` 会逐项记入 `insufficient_sources`。

### F3 口径对照校准: UNCALIBRATED (未校准)

- 配对样本 0 行 (无手机界面人工读数), 未达最少 3 行要求。
- `test_results` 按本轮查法不返回逐节点 API 延迟字段, 无法构造
  API 值 vs UI 显示值的配对行。
- 结论: `calibration_verdict=UNCALIBRATED`,
  `measurement_verified` 保持 `False`,
  证据判定维持 `UNVERIFIED`, 决策维持 `NO_SAFE_REMOVAL`。
- 校准通过条件 (见 `calibration.py`): ≥3 行同节点、同 bearer、
  同 test_url 口径 (HTTP 与 HTTPS 分开) 的配对样本, 且界面显示值恒等于
  某一 API 字段 (残差逐样本为 0)、映射唯一; 否则为 UNCALIBRATED,
  同一 API 值对应不同 UI 值时为 CONTRADICTED。
- 下一步校准须机主在手机上人工读数 (见“机主最短操作指令”):
  同一节点、同一时间、同一网络下, 抄下 API 值与界面显示值各 3 组,
  再由 `calibrate()` 判定映射。

### 机主最短操作指令 (校准用, 仅 1 次, 隔离 profile 载入后)

> 前置: 隔离 profile 已载入手机且 `免费节点池` 成员与待测候选一致;
> 未确认前不测。手机保持蜂窝数据 (不要切 Wi-Fi), 不要改生产配置。

1. 打开 Surge → 免费节点池组, 任选 1 条轮换节点 (不要选钉选),
   记下组内显示的延迟数字 (如实抄, 精确到毫秒)。
2. 立即在同一节点上触发一次原生测速 (组内下拉/测速按钮),
   再次记下组内显示的延迟数字。
3. 把“同一节点名 + 测试前后界面延迟 + 蜂窝/Wi-Fi + 时间”发回。
   **必须重复同一条非钉选节点至少 3 次，且各轮都要能独立对应 API 侧
   同一节点、同一测试 URL、同一网络的原始测速结果**。不能拿 3 个
   不同节点各测一次当作 3 条配对数据；有界面读数但缺 API 对应值
   时只记为 UI_OBSERVED，校准仍为 UNCALIBRATED。
   如果 API 侧一次最多执行一批、每小时仅一批，则必须跨允许的时段
   分批采集，**不允许为了凑齐3次而重复有副作用的 POST**。
4. 不要做 fallback 测试、不要改任何选择、不要动生产池。

API 侧的对应值由桥只读查询取回后对照, 不需要机主再操作 App 外的步骤。

## 执行范围约束

- 每批最多 **10** 个 identifier, 每小时最多 **1** 批
  (`check_batch_limits(identifiers, last_batch_at)`)。
- POST 超时**不得重发**: `post_timeout_policy()` 返回
  `retry_allowed=False` 与明确的“不得重发”指示。
  调用方不得自动重试, 须人工核查手机侧执行状态后,
  再由人工显式发起新批次。
- 真机 POST 只写接口与约束, 不实际发送:
  `post_test_to_phone()` 在沙盒内永远返回 `sent=False`,
  本模块不含任何 socket / HTTP 发送代码。

## 影子审计接入方式

```python
from evidence_validator import audit_shadow  # 文件名含连字符时用 importlib 加载, 见 tests/

audit = audit_shadow(
    candidate_nodes=["TEST-PINNED-01", "..."],   # 当前候选节点名列表
    evidence_records=[...],                     # 原生证据记录列表
    pinned_names=["TEST-PINNED-01", "..."],     # 21 条钉选名
    stop_status="RUNNING",                      # "STOP" 时强制 NO_SAFE_REMOVAL
    output_dir="/path/to/isolated-evidence",    # 隔离目录; 不传则不写文件
    candidate_record=candidate,                 # 冻结候选记录 (必须; 缺失即 NO_SAFE_REMOVAL)
)
```

输出十项计数:

1. 当前候选节点数 (`candidate_count`)
2. 原生证据覆盖数 (`evidence_coverage` / 总数)
3. 有效测试数 (`valid_test_count`)
4. 小于 300ms 数量 (`lt_300_count`)
5. 大于等于 300ms 数量 (`gte_300_count`)
6. 明确失败数量 (`failed_count`)
7. UNKNOWN 数量 (`unknown_count`)
8. 具有安全删除资格的非钉选数量 (`safe_removal_eligible_count`)
9. 21 条钉选完整性 (`pinned_integrity`, 如 `"21/21"`, 及 `pinned_intact`)
10. STOP 状态 (`stop_status`)

另含 `removal_candidates` 与 `decision`
(`NO_SAFE_REMOVAL`, 或 `REMOVAL_CANDIDATES:<n>`)。

当前生产态复核: 30 候选、原生证据覆盖 0/30 时,
`removal_candidates=0`、`decision=NO_SAFE_REMOVAL`, 这是正确结果,
不是缺失——没有可信失败证据就不能删节点。

## 如何运行测试与示例

```bash
cd ~/workspace/p2p3-dual/surge-d7-acceptance

# 全部测试 (unittest, 无需 pytest)
python3 -m unittest discover -s tests -v

# 只跑候选冻结测试
python3 -m unittest tests.test_native_candidate_binding -v

# 只跑证据校验测试
python3 -m unittest tests.test_native_evidence_validator -v

# 可运行的示例入口: 冻结 TEST-NET 测试候选, 生成一条完整可复核的
# 同候选证据链示例, 输出到隔离证据目录并打印十项计数
python3 native-evidence/evidence-validator.py
python3 native-evidence/evidence-validator.py --output-dir /tmp/isolated-evidence-demo
```

测试与示例夹具一律用 TEST-NET 假值 (`192.0.2.0/24` + `test123`),
代码与测试中不得出现真实节点 URI、密码、token、真实出口 IP。
