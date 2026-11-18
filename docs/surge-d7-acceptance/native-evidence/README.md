# 可信 Surge 原生测速采集链路 (native-evidence)

任务 B 交付: 候选冻结 / 原生测速采集 / 证据校验 / 影子审计。
全部 Python 3 标准库, 不联网, 不读 / 不写生产路径,
不改生产 Surge 配置、不停生产 timer、不删节点。

## 文件

| 文件 | 作用 |
| --- | --- |
| `candidate-freeze.py` | B1 候选冻结: `freeze_candidate()` / `verify_candidate()` |
| `native-collector.py` | B2 原生测速采集: `build_evidence_chain()` / `judge_evidence()` / `check_batch_limits()` / `post_timeout_policy()` |
| `evidence-validator.py` | B3 证据校验 + 影子审计: `validate_evidence()` / `audit_shadow()` / `run_example()` |
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

## 判定标准 (judge_evidence / validate_evidence)

| 情形 | verdict |
| --- | --- |
| schema 缺字段 / 类型错误 | `UNVERIFIED` |
| policy_identifier 与当前策略不一致 (版本不一致) | `UNVERIFIED` |
| 已过期 (TTL 24h) | `UNVERIFIED` |
| 原生语义未校准 (`measurement_verified` 为 False) | `UNVERIFIED` |
| 延迟 <300ms, 且语义已校准、手机加载已验证、未过期 | `PASS` (合格候选条件之一, 不是生产准入) |
| 延迟 <300ms 但 phone_loaded_sha 为 UNKNOWN | `UNVERIFIED` |
| 延迟 >=300ms | `FAIL_LATENCY` (测速不达标, 原始延迟如实保留) |
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
  (延迟 >=300ms, 或延迟为 null 且有明确失败信号) + 非钉选。
  任一不满足即不计入 `removal_candidates`。
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
    candidate_record=candidate,                 # 冻结候选记录 (可选, 用于绑定校验)
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
