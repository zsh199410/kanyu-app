# 时间戳选最近报告的证明（D0，GPT 审查项 2）

> 结论先行：`load_verified` 按报告时间戳选最近一条记录，
> 不依赖插入顺序。证明分三层：代码段、行为测试（33 项）、
> 发现的一处漏洞与修复。
> 本文件脱敏：只含代码段、断言名与数字，无节点数据、密码、
> URI、token、订阅 URL。

## 1. 关键代码（`pool/phone_gate.py`，修复后版）

### 1.1 最近报告查询：按 ts 倒序取 1 条

```python
def _most_recent_report(conn, fingerprint):
    """Return the most recent probe report row for a fingerprint, or None.

    Row: (ts, success, second_ms, second_status, interface, error).
    """
    row = conn.execute(
        """SELECT ts, success, second_ms, second_status, interface, error
           FROM probe_reports WHERE fingerprint=? ORDER BY ts DESC LIMIT 1""",
        (fingerprint,),
    ).fetchone()
    return row
```

- 排序键是 `ts`（报告时间戳），不是 `id` / `rowid`。
- `LIMIT 1` 只取时间戳最大的一条；其余历史报告不参与判定。
- 同一指纹不可能出现两个相同 `ts`：`probe_reports` 表有
  `UNIQUE(fingerprint, ts)` 约束（P0 schema），`ts DESC` 的胜者唯一。

### 1.2 最近一条记录决定放行与否（`load_verified` 主循环）

```python
report = _most_recent_report(conn, fingerprint)
# ...
if state != "verified":            # probe_nodes.state 交叉核对
    ... reject "state_not_verified"
if not success:                    # 最近一条失败即拒
    ... reject "latest_failed"
if second_ms is None or second_ms > threshold_ms:
    ... reject "latest_slow_or_missing_ms"
if second_status != EXPECTED_SECOND_STATUS:   # 须为 204
    ... reject "latest_status_not_204"
if not interface or not str(interface).startswith("pdp_ip"):
    ... reject "latest_interface_not_cellular"
# --- 时间戳合理性（本次修复新增，见第 3 节）---
if ts is None or ts <= 0 or ts > now + MAX_FUTURE_SKEW_SECONDS:
    ... reject "latest_ts_invalid"
if now - ts > ttl_seconds:         # 超出 24 h TTL 即拒
    ... reject "latest_stale"
admitted.add(fingerprint)
```

顺序说明：state 交叉核对在前，最近报告的各项判定在后；
任何一项不满足即拒，不回头参考更旧的成功记录。

## 2. 行为测试：`tests/test_timestamp_priority.py`（33 项，全过）

测试自建临时 `probe.db`（P0 schema），不碰生产文件。
每场景均有“先好后坏 → 拒绝”和“先坏后好 → 放行”的对照。

| 场景 | 先好后坏 | 先坏后好 | 备注 |
|---|---|---|---|
| a. 后续失败报告（success=0） | 拒绝 | 放行 | 含 error="timeout" 的失败行 |
| b. 后续超时 | 拒绝 | 放行 | 两种子编码都拒：success=0 + warm 3000ms + error 超时；以及 success=1 但 second_ms 缺失 + error 超时（以“缺失 ms”拒） |
| c. 后续 ≥300ms | 拒绝 | 放行 | 测了 310ms、500ms、281ms（阈值 280 的边界+1）三档；280ms 本身放行（原有测试 `admit_boundary_280`） |
| d. 后续换网络 | 拒绝 | 放行 | en0、空字符串、NULL interface 均拒；`pdp_ip1`（非 pdp_ip0 的蜂窝口）放行——判定口径是“以 pdp_ip 开头”，不是“等于 pdp_ip0” |
| e. 报告时间异常 | 见下表 | — | ts=0 拒；远早于 TTL 拒；TTL 边界精确值放行、超 1 秒拒；未来时间戳见第 3 节 |
| f. 指纹更改 | 旧指纹不放行新行 | — | 同名同 host、端口 443→8443 或参数加 sni，指纹改变，`gate_lines` 丢弃新行，旧行仍放行（对照） |
| g. 插入顺序干扰 | 拒绝（旧好报告后插入、id 更大但 ts 更小，仍不胜） | 放行 | 测试内断言了 id 顺序确实是“误导性”的（新坏报告 id 更小、旧好报告 id 更大），再验证胜者仍按 ts 选 |

### 场景 e 明细（TTL = 86400 秒，阈值 280ms）

| 报告 ts | 结果 | 原因 |
|---|---|---|
| `now + 3600`（未来 1 小时） | 拒绝 | `latest_ts_invalid`（本次修复，见第 3 节） |
| `now + 300`（未来 5 分钟） | 放行 | 在 P0 ingest 允许的 +600 秒时钟偏差内，视为新鲜；与 ingest 口径一致 |
| `0` | 拒绝 | `latest_ts_invalid` |
| `now - 90000`（25 小时前） | 拒绝 | `latest_stale` |
| `now - 86400`（恰好 TTL） | 放行 | 判定条件是 `now - ts > ttl`（严格大于） |
| `now - 86401`（TTL + 1 秒） | 拒绝 | `latest_stale` |

### diag 计数核对（主库 20 个节点）

放行 7 / 拒绝 13；原因分布：`latest_failed` 2、
`latest_slow_or_missing_ms` 4、`latest_interface_not_cellular` 3、
`latest_ts_invalid` 2、`latest_stale` 2。

## 3. 发现的漏洞：未来时间戳曾被当作“最新鲜”放行

### 3.1 现象（修复前复现）

修复前跑新增测试：**29 通过 / 4 失败**。
失败的 4 项全部源于同一根因：

- `reject_future_ts_far`：ts = `now + 3600` 的成功快报告被放行；
- `diag_counts`、`diag_reason_latest_ts_invalid`、`diag_reason_latest_stale`
  随之错位（未来报告被计为放行，`ts=0` 被计为 stale 而非无效）。

根因：TTL 判定只有 `now - ts > ttl_seconds`。未来 ts 使
`now - ts` 为负，恒不大于 TTL，于是被当作“0 秒前的新鲜报告”
放行；且该状态会持续到 `now` 追上未来 ts 再加 TTL，
即最长可错误放行约 `未来偏移 + 24 h`。

### 3.2 影响评估（实事求是）

- 正常 ingest 路径写不进这种行：P0 `ingest()` 已拒
  `ts <= 0` 与 `ts > now + 600` 的报告（见
  `probe_service_reference.py` 的 `ingest`）。
  因此该漏洞需要直接写库、时钟跳变或 ingest 旁路才能触发，
  不是一条正在发生的泄漏路径。
- 但门禁是直接读库的， defense in depth 上应与 ingest 同口径，
  故仍按漏洞修复，不只写文档。

### 3.3 修复（只改隔离目录，不动生产）

文件：`pool/phone_gate.py`（隔离目录 `/opt/p2p3-d0/` 与本地副本同步），
修复 diff 见同目录 `phone_gate_future_ts_fix.diff`。改动三处：

1. 新增常量 `MAX_FUTURE_SKEW_SECONDS = 600`（与 P0 ingest 的 +600 秒
   偏差 allowance 完全一致）；
2. TTL 判定之前加时间戳合理性检查：
   `ts is None or ts <= 0 or ts > now + MAX_FUTURE_SKEW_SECONDS`
   → 以新原因 `latest_ts_invalid` 拒绝；
3. 模块 docstring 的放行条件补一句 ts 合理性说明。

修复后复跑：**81/81 全过**（原有 48 项 + 新增 33 项），
且修复前后 dry-run 候选 SHA 完全一致（见第 4 节）。

## 4. 修复不影响现行候选（A/B 对照）

修复前后各跑一次隔离 dry-run（`dry_run.py`，只读生产池与 probe.db）：

- 修复前版候选 SHA：`f389acc57542bfe67dbc26b03c44154e90ab4a958bd8d931d4fdd50f0a67a0be`
- 修复后版候选 SHA：`f389acc57542bfe67dbc26b03c44154e90ab4a958bd8d931d4fdd50f0a67a0be`
- 两版逐字节一致。

注：该 SHA 与 `D0_SUMMARY.md` 记载的 `8dba4472…`（12 条）不同，
原因是生产池本身在 D0 之后轮换了（源订阅 42 行 → 40 行，
源 SHA 已变），且 probe.db 有了新报告（放行指纹 13 → 14）。
变化来自生产轮换与新探测数据，与本次修复无关——A/B 对照已证实
同一份当前数据下修复前后候选完全一致。
本次 dry-run 候选为 14 条，**不宣称“全部 <300ms”**，仍是
dry-run 候选，须经手机原生整组测速验收。

## 5. 已审未改的说明（供 GPT 复核）

- `warm_ms` 与 `error` 字段不单独参与判定：门禁以
  `success` + `second_ms` + `second_status` + `interface` + `ts`
  为准。`warm` 只是预热请求，真正计量的第二请求由 `second_ms`
  覆盖；一次 warm 超时在 P0 语义里对应 `success=0`，
  已由 `latest_failed` 挡下。`success=1` 但 `second_ms` 缺失
  的行由 `latest_slow_or_missing_ms` 挡下（场景 b 已覆盖）。
  若 GPT 认为 warm 也应独立设限，可追加判定，不影响现有结论。
- `state` 字段取自 `probe_nodes`（P0 ingest 随每条报告更新），
  门禁只做交叉核对，不单独信任它。
