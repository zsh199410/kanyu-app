# D0 脱敏源码隔离 PR 方案（供 GPT 审阅 Issue #73 评论 6868864259）

> 目标：让 GPT 在不接触任何生产秘密的前提下，审阅 D0 手机门禁的
> 全部改动与测试证据。
> 铁律：不推生产仓库、不合 main、不改生产文件、不改手机配置、
> 不宣称“全部 <300ms”。

## 1. 放哪里

- **仓库**：`zsh199410/kanyu-app`（已有仓库，GPT 已在审 Issue #73 的
  同一仓库语境下；D0 代码与《三术合参》App 源码无交叉）。
- **分支**：新建独立分支，例如 `issue73-surge-d0-review`，
  从 `main` 切出，只含本方案所列文件。
- **PR 标题建议**：`[D0-review-only] Surge phone gate (Issue #73): desensitized source + timestamp-priority proof`。
- **明确标注**：本 PR 为**审阅专用隔离材料**，不是部署 PR；
  合并与否不触发任何生产变更；生产目录
  `/opt/free-node-program/` 与手机配置不在本 PR 的影响范围内。
- **不得做的事**：不得把本分支合入 `main` 后当作“已上线”；
  不得把本 PR 的文件直接覆盖到 `/opt/free-node-program/`；
  不得在 PR 描述或评论里贴节点密码、完整 URI、token、订阅 URL、私钥。

## 2. PR 含哪些文件（全部已脱敏，见第 3 节）

| PR 路径（建议） | 来源（本机 `~/workspace/p2p3-d0/gpt-review/`） | 说明 |
|---|---|---|
| `docs/surge-d0-review/phone_gate.py` | `phone_gate.py` | 门禁核心，全文（修复后版，245 行） |
| `docs/surge-d0-review/diff_cli.txt` | `diff_cli.txt` | `cli.py` 的 D0 diff（88 行，统一 diff） |
| `docs/surge-d0-review/diff_rules.txt` | `diff_rules.txt` | `rules.py` 的 D0 diff（78 行，统一 diff） |
| `docs/surge-d0-review/phone_gate_future_ts_fix.diff` | `phone_gate_future_ts_fix.diff` | 本次未来时间戳修复 diff（44 行） |
| `docs/surge-d0-review/tests/test_phone_gate.py` | `test_phone_gate.py` | 门禁单测 fixture（23 项） |
| `docs/surge-d0-review/tests/test_select_publish.py` | `test_select_publish.py` | 发布选择 fixture（14 项） |
| `docs/surge-d0-review/tests/test_cmd_publish_gate.py` | `test_cmd_publish_gate.py` | 发布命令集成 fixture（11 项） |
| `docs/surge-d0-review/tests/test_timestamp_priority.py` | `test_timestamp_priority.py` | 时间戳优先级 fixture（33 项，新增） |
| `docs/surge-d0-review/tests/probe_service_reference.py` | `probe_service_reference.py` | P0 对照实现（只读参照，供指纹一致性断言用） |
| `docs/surge-d0-review/timestamp-proof.md` | `timestamp-proof.md` | 时间戳选最近报告的证明 |
| `docs/surge-d0-review/aggregate-logs.md` | `aggregate-logs.md` | 81 项单测聚合输出 |
| `docs/surge-d0-review/test-output-timestamp.txt` | `test-output-timestamp.txt` | 四套测试完整原始输出 |
| `docs/surge-d0-review/isolation-pr-plan.md` | 本文件 | 本方案 |

不含：生产 `cli.py` / `rules.py` 全文（只给 D0 diff）、
生产 `pool.db` / `probe.db`、任何订阅文件、任何节点 URI、
`config.yaml`（含 probe.db 路径以外的生产路径信息不进 PR）。

## 3. 每个文件的脱敏说明（已逐行核对）

核对方法：对全部 12 个文件跑关键字扫描
（`https?://`、`token`、`secret`、`api key`、`BEGIN … PRIVATE`、
`subscribe`、`password = "值"`），并人工复核命中行。

| 文件 | 扫描结果 | 说明 |
|---|---|---|
| `phone_gate.py` | 0 处秘密 | 仅有的 `password` 字样在 docstring 一句话里：“No passwords, URIs, tokens, or subscription URLs are ever output.”（陈述句，非值）。`fingerprint_of` 与 `parse_surge_line` 是从 P0 复制的纯算法，只做哈希与解析，不含秘密；诊断只输出指纹前 12 位与计数。唯一出现的路径是默认 probe.db 本地路径（非秘密）。 |
| `diff_cli.txt` | 0 处秘密 | 只有 D0 新增的门禁卡点代码与注释；出现的路径 `/opt/probe-service/data/probe.db` 是默认值占位，非订阅 URL。 |
| `diff_rules.txt` | 0 处秘密 | 只有新增的 `allowed_fingerprints` 参数与门禁分支；无 URL、无密钥。 |
| `phone_gate_future_ts_fix.diff` | 0 处秘密 | 只有常量与时间戳判定改动。 |
| 4 个测试 fixture | 0 处秘密 | 全部 host 为 `*.invalid`（RFC 保留域名，不可解析）；密码类参数全部为单字母占位值（`p` / `x`）或 `pw1`–`pw4` 这类明显占位；无真实 host、无真实密码、无 URI。 |
| `probe_service_reference.py` | 0 处秘密值 | 556 行。仅有 `load_secret()` 按文件名读本地配置文件（只含文件名 `probe-path.txt`，不含值）；另有一处注释明确说明“不使用 Bearer token”（因 token 须进手机脚本、经公开 URL 下发，故不算秘密）。无 URL、无 token 值、无密码值。 |
| `timestamp-proof.md` / `aggregate-logs.md` / `test-output-timestamp.txt` / 本方案 | 0 处秘密 | 只含代码段、断言名、计数与 SHA256；候选 SHA 是文件哈希，不是节点数据。 |

复核结论：12 个文件均可公开进审阅 PR；其中 `phone_gate.py` 的
SHA256 为 `b17718d4cb3dca02cab89cfffe4d21ec56f77dc1f82104bdf90398a3e26c578f`
（修复后版，与 VPS `/opt/p2p3-d0/pool/phone_gate.py` 一致）。

## 4. GPT 如何审（建议顺序）

1. **先读 `phone_gate.py`**：确认放行条件（最近报告 success=1、
   second_ms ≤280、status 204、pdp_ip、24 h TTL、state verified
   交叉核对）与 fail-closed 语义；确认 `_most_recent_report`
   用 `ORDER BY ts DESC LIMIT 1`。
2. **再读 `timestamp-proof.md`**：核对 7 类场景（a–g）的行为
   表与 TTL 边界表；重点看第 3 节的未来时间戳漏洞与修复。
3. **再读两个 diff**：`diff_cli.txt`（门禁卡点与零合格拒绝发布）、
   `diff_rules.txt`（`allowed_fingerprints` 可选参数，未提供时
   行为不变）；确认 D0 改动只集中在门禁卡点，无其他生产逻辑改动。
4. **跑 fixture**：在隔离目录复现（见第 5 节），确认 81/81；
   重点跑 `test_timestamp_priority.py`，并可自行把
   `MAX_FUTURE_SKEW_SECONDS` 改回“无检查”复现 4 项失败，
   验证测试确实能抓住该漏洞。
5. **最后看 `phone_gate_future_ts_fix.diff`**：确认修复只加了
   时间戳合理性检查与常量，未动放行阈值与判定顺序。

## 5. 本地复现命令（隔离目录，不碰生产）

```bash
cd /opt/p2p3-d0
python3 tests/test_phone_gate.py        # 23 项
python3 tests/test_select_publish.py    # 14 项
python3 tests/test_cmd_publish_gate.py  # 11 项
python3 tests/test_timestamp_priority.py  # 33 项（新增）
```

- 依赖：Python 3 标准库 + `probe_service_reference.py`
  （仅 `test_phone_gate.py` 的指纹一致性断言需要它；
  其余三套不依赖）。
- 不联网、不读生产 `pool.db`、不写生产订阅；测试自建临时库。
- 若要在 PR 检出物里跑：把 `docs/surge-d0-review/` 的内容
  平铺回隔离目录结构（`phone_gate.py` → `pool/phone_gate.py`，
  四个测试 → `tests/`，`probe_service_reference.py` → 目录根），
  再执行以上命令。

## 6. 审阅后仍需 GPT 再确认的事项（D0 不擅自定）

- 280ms 校准余量是否可接受（不是官方标准，不保证原生 <300ms）。
- `warm_ms` / `error` 不独立判定是否可接受
  （见 `timestamp-proof.md` 第 5 节）。
- 未来时间戳的 +600 秒偏差 allowance 是否合适
  （与 P0 ingest 同口径）。
- 12→14 条候选 dry-run 变化的定性（生产池轮换所致，非修复所致，
  A/B 对照已证）。
- 零合格安全态与定时锁方案仍在 `safe_state_and_lock_plan.md`
  （不在本次 PR 内，另行审）。
