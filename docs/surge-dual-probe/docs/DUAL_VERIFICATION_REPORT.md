> PR 包副本说明：正文 §1 的 SHA 指隔离树原始文件；本包内文件的 SHA
> 见本包 `SHA_MANIFEST.md`。`CLIENT_VERSION` 已按脱敏后脚本重算
> （见 `DESENSITIZATION_CHECKLIST.md`）。其余内容与隔离树报告一致。

# #73 双通道探针补丁（B①）隔离验证报告 v3

- 任务来源：Issue #73 评论 #6937918471（GPT 最终裁决：B①「双网络分轨」）
  与评论 #6938432964（GPT 增量复核：五条精确门禁）。
- 状态：**隔离开发与测试完成，生产未动。补丁未部署，等 GPT 最终代码裁决。**
- 隔离树：本地 `~/workspace/p2p3-dual/`、VPS `/opt/p2p3-dual/`（文件 SHA 双边一致）。
- 夹具：12 个合成节点（TEST-NET 203.0.113.11–22，假口令），从未用真实节点做测试。
- v3 相对 v2 的改动（GPT #6940445042 逐文件终审，四项 P0）：
  P0-1 单次不可变池快照（`_pool_snapshot()`，do_GET 不再覆盖批次锁定
  SHA，轮换故障注入测试）；P0-2 私有渲染生产脚本（占位符 fail-closed、
  CLIENT_VERSION 重算、按渲染产物 SHA 核验）；P0-3 部署脚本改为 stage
  参数独立执行、阶段 4 改为“旧蜂窝兼容＋隔离新脚本”，生产 Wi-Fi 回传
  改到阶段 5；P0-4 DB 备份改为 SQLite backup API 一致性快照 +
  integrity_check（单文件 cp 不再当作可靠备份）。报告 §9 详述。

## 1. 基线 SHA（完整值，另见 `docs/SHA_MANIFEST.md`）

| 文件 | SHA256 | 说明 |
|---|---|---|
| `service/probe_service_orig.py`（556 行） | `015472a839991ef5a2eb6fb155e4696d27b8a430602a4b7e9ef9e5ea3b63e3f3` | 生产接收端原样取回 |
| `service/probe_service_dual.py`（1208 行） | `188f29bbd2eb154baad768b36c8de78603b7574473332e53521dcde0baaef984` | 补丁版 v3 |
| `script/probe-task-orig.js`（7148 字节） | `1a0197db7cb8f76143eae4f4822b43466de982eacfd360129db47536e9bff837` | 生产脚本原样取回 |
| `script/probe-task-dual.js`（308 行） | `32c620fe7220335735026ea79b2250c789e8dd17c8caf6222e3481eb79012f28` | 补丁版，`CLIENT_VERSION=dual-v1-1aa60229fd22` |
| `fixtures/pool-fixture.txt` | `914558d062a58f21191abfa0a776db9df617442ec279391d62a22ed3e3282723` | 12 行合成池 |
| `tests/test_dual_probe.py`（28 项） | `a3c95007f7789d1ec270c931e76530ed2d65b4e1ac6efbec71ce10515fe04e11` | Python 套件 |
| `tests/test_deploy_matrix.py`（8 项） | `df8c0a6e6211896f8656000ab15d29e43de7561ba2ca95c514be455d04202a04` | 五阶段矩阵 + 部署脚本分阶段测试 |
| `tests/test_backup.py`（3 项） | `fd0e3d61cea664352c634b4fe869e8ccfa558e8695930bf02742fb68d0d7f4e8` | WAL 备份测试（P0-4） |
| `tests/js_detect_test.js`（43 项检查） | `13e0becd801a5ed84fd4330d386f3c8076e4a2ca9a8ddccb0d599032f482a617` | Node 套件 |
| `tools/inject_sha.py` | `540bbd1386afc9173e64ca91776c58c85dccade58bbcef48ba8ca28a53441b29` | SHA 注入工具 |
| `tools/deploy_dual.sh` | `4c3fbf759592f90bb49724855a34048545f802371124b9f82087a8bbc86c7aee` | 五阶段部署脚本（stage 1–5） |
| `tools/render_probe_script.py` | `1edaad16167d52f5cb799a2e128c6e23179032191652374204a13776a653f58a` | 私有渲染生产脚本（P0-2） |
| `tools/backup_db.py` | `4133f56df1d20ccd30f20b831be80c4607db449f435c334d2b01fe4c79e9fd89` | WAL 安全 DB 备份（P0-4） |
| `tools/make_pr_package.py` | `2b068843bc2dd04b13248c87fb0f21f6aa65355eb9650ba30c8035da3aceb0d3` | 脱敏 PR 包组装工具 |
| `tools/rollback_dual.sh` | `6c8774710420d501aaed1bf6306fdd2a4f53f2a38e004d4c5ce960db6157b626` | 逆序回滚脚本 |
| `tools/capture_sample.py` | `586b9d8a74c27f10b43e14ebe3f25417c193ef0b239e67f7f6e435a272364189` | 样本采集工具 |
| `docs/SAMPLE_REQUEST.md` | `205b555d6d62016b914b22ec9e03a20dda81e6a1c237b09862da4bba639e5891` | P0-1 绑定样本 |
| `docs/STAGED_RUNBOOK.md` | `1bca887739faa3319a0cbaa9679a88fba98a1cd33f07868d10263c710a3a7116` | 分阶段手册 v3 |

## 2. 补丁内容（逐条对 GPT 设计）

**脚本端 `probe-task-dual.js`**
1. `detectNetwork()`（取代 `isCellular()`）：按 `$network.v4.primaryInterface`
   （主承载接口）判定。cellular = `pdp_ipN`（即使有 SSID，承载就是蜂窝）；
   wifi = 主接口是 `en0` 且有 SSID；其余一律 `unknown` → fail-closed 跳过，
   不上报。utun*（VPN 隧道）永不推出承载，空值/无主接口/未识别接口名/
   en0 无 SSID 一律不猜。字段来源已核实：Surge 官方手册
   （JavaScript API Reference）`$network` = `wifi`（`ssid`、`bssid`）、
   `v4`（`primaryAddress`、`primaryInterface`、`primaryRouter`）、
   `v6`（`primaryAddress`、`primaryInterface`）、`dns`，iOS 另有
   `cellular-data`（`carrier`、`radio`）；接口名取值（en0/pdp_ipN/utunN）
   是 iOS 系统名，非 Surge 文档常量，故规则只认两个承载、其余全 unknown。
   推理写进注释：SSID 只证明 Wi-Fi 已连，不证明流量走 Wi-Fi；
   primaryInterface 才是承载。
2. 每条结果绑定 `network_type` + `source_version_sha`（服务端签发的任务
   快照池 SHA，原样回填）+ `batch_id`（服务端签发的批次绑定，原样回填）
   + `client_version`（脚本构建 ID `dual-v1-1aa60229fd22`）+ 指纹 + 时间 +
   成败 + 毫秒。**不再发送原始 interface 值**，不发送 SSID/IP/设备身份。
   无 `pool_sha` 或无 `batch_id` 时整轮中止（fail-closed），不上报无绑定结果。
3. Wi-Fi 用独立端点（`PROBE_URL + '-wifi'`）+ `X-Probe-Network` 头；蜂窝走
   原端点。未知网络不执行。
4. 每批前重检网络类型，切网即中止（`network_changed`，未上报结果丢弃）；
   上报前再检一次。无重试循环（上报失败即 `$done()`，与原行为一致）。
5. 探针仍两 HEAD + policy 钉死节点，无 DIRECT；MAX_BATCHES_PER_RUN=3、
   超时 3s 不变；Wi-Fi 与蜂窝同等轻量上限。

**服务端 `probe_service_dual.py`**
1. 新增独立表 `probe_reports_wifi`（+ `network_type`、`source_version_sha`、
   `client_version`、`batch_id` 列）与 `probe_nodes_wifi`（wifi 专属聚合：
   `wifi_verified`/`wifi_expired`/`wifi_quarantined`/`wifi_retired`、
   `phone_ok_wifi`/`phone_fail_wifi`、`last_wifi_ts`）。
   新增独立函数 `sync_pool_wifi` / `next_tasks_wifi` / `ingest_wifi` /
   `stats_wifi` / wifi 熔断（`wifi_circuit_until`）。
2. 新增任务快照绑定表 `probe_task_batches`（`batch_id` 主键 +
   `network_type` + 锁定快照 `pool_sha` + 指纹集 JSON + `issued_at` /
   `expires_at`，有效期 2 小时，时钟偏差允差 600 秒）；
   `probe_reports` 与 `probe_reports_wifi` 各加 `batch_id` 列（旧库迁移补列）；
   `probe_meta` 记入标签策略行 `channel_label_policy`。
3. **Cellular 代码字节级不变**：AST 逐函数比对，20 个共有函数中 13 个
   与原版完全一致（`Handler._auth`、`Handler._send`、
   `Handler.log_message`、`_circuit_open`、`_hour_bounds`、
   `_maybe_trip_circuit`、`_meta_get`、`_meta_set`、`fingerprint_of`、
   `load_secret`、`main`、`parse_surge_line`、`quality_score`）；
   有改动的 7 个是 `db`（追加建表/列）、`Handler.do_GET`（批次锁定
   SHA 不再被重算覆盖；无批次的 early-return 才填当前池 SHA）、
   `Handler.do_POST`（路由分发）、`ingest`（新式结果加批次校验，旧形
   状路径不变）、`next_tasks`（单次快照签发批次绑定）、`stats`（只加
   `channel_label` 字段）、`sync_pool`（接受快照行参数，默认行为不变）。
   新增函数：`_pool_snapshot`、`_issue_batch`、`_check_batch`、
   `pool_sha`、`sync_pool_wifi` / `next_tasks_wifi` / `ingest_wifi` /
   `stats_wifi` / wifi 熔断、`Handler._channel`、`_ensure_columns`。
4. 路由：`/<seg>` = cellular（原路径，老客户端无 `X-Probe-Network` 头时仍按
   cellular 处理，完全兼容）；`/<seg>-wifi` = wifi（独立端点）。头与路径
   不一致 → 400；wifi 标签记录发到 cellular 路径 → 400（纵深防御）。
5. 隔离性由构造保证：cellular 的 caps/熔断/统计只读 `probe_reports`，
   wifi 只读 `probe_reports_wifi`；`stats()`（cellular）与 `stats_wifi()`
   各自独立。
6. WinnerReport 未动：补丁服务源码中无 `winner_report`/`winner_reports`/
   `pool.db` 引用（原版注释里有一处 “(like winner-report)” 指另一服务的
   保护模型，已在测试中注明）。

## 3. GPT 五条精确门禁（#6938432964）逐条落实

**门禁 1 — P0-1 任务快照绑定（设计更正，取代 v1 的“入库时比对当前池 SHA”）**
真实池 SHA 必须是任务快照的 SHA，不是接收 POST 时的“当前池”SHA。
服务端下发批次时锁定完整 `source_version_sha`（当时池文件字节的 SHA）、
`batch_id`、指纹集及有效期（`probe_task_batches`）；接收时按绑定记录验证
指纹、版本、时窗与去重键；期间 :07 轮换不得把旧批次记录标成新池合格；
构建标识单放 `client_version`；所有不匹配 fail closed。
实测：池轮换后旧批次结果仍被接受（绑定的是快照，不是当前文件），
且入库行存的是旧快照 SHA（永不重标为新池合格）；无批次的新 SHA 结果被拒；
过期/未来批次被拒；错通道批次被拒；不在批次指纹集内的指纹被拒；
旧蜂窝客户端不发绑定字段时仍可入库（向后兼容），一旦发送任一绑定字段
就必须通过批次校验。样本见 `docs/SAMPLE_REQUEST.md`（真实隔离运行的
tasks 响应 + 上报请求体 + 入库行，含 `batch_id`）。

**门禁 2 — 主承载接口**
Wi-Fi 已连且蜂窝接口同时存在是正常环境，不因此一概 unknown；只按主路径判；
`utun`、空值或信息矛盾不猜，走 unknown。已按 Surge 官方手册核实
`$network` 实际字段（见 §2.1）；测试覆盖：en0+SSID→wifi、pdp_ip0 无
SSID→cellular、pdp_ip0+SSID→cellular（承载为蜂窝）、en0 无 SSID→unknown、
无 v4→unknown、utun0/utun1+SSID→unknown、未识别接口名 en1+SSID→unknown、
wifi 对象缺失时 pdp→cellular。不上报真实 SSID、IP 或设备身份。

**门禁 3 — 客户端标签仅为声明**
路径 + 头能防协议错误，不能证明真实无线接口。数据库与报表须标清
“客户端声明的 wifi/cellular”，不接 P0 原生整组测速放行。
已落实：服务模块 docstring、wifi 入库 docstring、`_channel` 注释、
`probe_meta` 的 `channel_label_policy` 行、`stats()` /
`stats_wifi()` 响应里的 `channel_label` 字段（分别为
`client-declared` / `client-declared wifi`）、本报告与样本文件全文。
grep 核查：全树 `gate` / `native` / `P0` 只出现在注释/docstring，
无任何把探针结果提升进 P0 gate 或 native 验收的代码路径
（测试 test_P03 剥离注释与 docstring 后断言）。

**门禁 4 — 脱敏是 P0-STOP（范围扩大）**
脚本内真实随机 URL 路径段、旧脚本快照、测试 fixture、日志、差异补丁、
报告、部署命令、凭据/私有地址全部检查，不只 grep 一个脚本。
核查结论（2026-11-17）：
- 真实随机路径段在 `~/workspace` 全仓只出现在隔离树内两个文件：
  `p2p3-dual/script/probe-task-orig.js`（生产脚本快照）与
  `p2p3-dual/script/probe-task-dual.js`（补丁脚本）。
- `~/workspace` 不是 git 仓库（`git log` 报 `not a git repository`），
  `p2p3-dual/` 也不是；真实路径段从未进过任何 git 提交历史——
  “密钥已进提交须阻断”条件未触发。
- PR 包从脱敏副本在全新目录 `~/workspace/p2p3-dual-pr/` 里组装，
  分支须从 main 新建、只含脱敏文件；绝不先提交真实路径再删除。
  脱敏清单与逐项 grep 结果见 `docs/DESENSITIZATION_CHECKLIST.md`
  （PR 包内）与 PR 正文草稿。
- 占位符不影响审查的逻辑结构：脱敏只替换 URL/主机/路径字面量，
  函数与控制流逐行保留；占位符须在部署时替换，脚本不替换无法直接运行；
  测试用 localhost/占位符。

**门禁 5 — 四阶段 HTTP/数据库验收（取代原 P0-4 的阶段划分）**
阶段：① 旧服务/旧脚本基线；② 先换服务；③ 再加 nginx；④ 新旧脚本兼容；
⑤ 最终换脚本；以及逆序回滚。每个阶段记录真实 HTTP 状态、蜂窝表/统计 SHA、
Wi-Fi 单独写入、失败关闭。日常回滚保留 Wi-Fi 表，**禁止删表**
（原任务书的“可选彻底清理”作废，`tools/rollback_dual.sh` 里的
`--drop-wifi-tables` 选项与删表逻辑已删除；矩阵测试断言回滚脚本全文
不含删表语句）。矩阵结果见 §5；分阶段手册见 `docs/STAGED_RUNBOOK.md`。

## 4. 测试结果

### JS（node v24，本地）：43/43 通过
- J01 决策表 17 项：cellular（pdp_ip0/3 无 SSID、pdp_ip0+SSID、
  pdp_ip1 空 SSID、wifi 对象缺失时 pdp）、wifi（仅 en0+SSID）、
  unknown（utun0/utun1+SSID、en1+SSID、en0 无 SSID、en0 SSID null、
  无 v4、空网络、null、v4 无主接口、主接口 null）。
- J06 整轮模拟 26 项：wifi 整轮走 `-wifi` 端点、标签 wifi+池 SHA+
  batch_id+client_version、无 interface/SSID 字段、policy 钉死；
  cellular 整轮走原端点、标签 cellular+池 SHA+batch_id；
  无 pool_sha 中止（0 次 POST）、无 batch_id 中止（0 次 POST）；
  unknown 零 HTTP 调用 fail-closed；批间切网 abort（1 次 POST、1 次 GET、
  无第 2 批）；批内切网 abort（0 次 POST，批次丢弃）。
- 阴性对照：原版脚本无 `detectNetwork`、有 `isCellular()` 门限、发送原始
  interface、无 `network_type`、无 `SOURCE_VERSION_SHA`、无 `batch_id`。

### Python（39 项 × 4 组，全绿）
| 组 | 结果 |
|---|---|
| 本地 Python 3.12.3 root | 39/39 OK |
| 本地 nobody（/tmp 副本） | 39/39 OK |
| VPS Python 3.13.5 root | 39/39 OK |
| VPS nobody | 39/39 OK |

`tests/test_dual_probe.py` 28 项：S01 wifi 只写 wifi 表（cellular 表哈希
前后一致）；S02 cellular 回归与原版逐表相同；S03 unknown/错通道/坏 SHA/
无批次/错通道批次/批次外指纹/过期批次拒绝；S06 重复 (fp,ts) 计一次；
S07 标签+SHA+batch_id 全行对齐；S08 caps 独立（wifi 20 条/小时达上限时
cellular 仍可发任务）；S09 熔断独立（wifi 8 异 host 全败只 trip wifi 熔断，
cellular 熔断未动、任务照常）；S10 stats 分离；S11 wifi_verified 永不提升
cellular verified；S12 老客户端兼容（无 network_type 的旧形状照常入库，
stats 键不变）；S13 WinnerReport 隔离；S14 回滚到原版服务（cellular 数据
完好、wifi 表保留但不再被读、老客户端照常）；P01 快照绑定（tasks info 带
pool_sha+batch_id、批次记录核对、旧蜂窝兼容/新绑定强制执行、池轮换后旧批次
仍接受且不重标、批次时窗强制、迁移补列、**轮换故障注入**：快照读取与 GET
返回之间轮换池子，返回的仍是批次锁定 SHA，旧批回传被接受且不重标为新池
合格）；P03 信任边界与 client-declared
针；HTTP 路由（S04 头与路径不一致 400、S03 错通道 400、S05 切网后批次拒绝
首批完好、E2E 双通道全程、S15  early-return 仍带 pool_sha）；J02–J05 脚本
静态检查。
`tests/test_deploy_matrix.py` 8 项：五阶段矩阵全程（见 §5）＋ HTTP 级轮换
故障注入（P0-1）＋ 部署脚本分阶段测试 6 项（stage 参数必填、阶段 1/4 独立
运行并停下、阶段 5 无渲染配置时 fail-closed、阶段 5 渲染部署按渲染产物
SHA 核验、阶段结构断言）。
`tests/test_backup.py` 3 项：WAL 未 checkpoint 行的 backup API 快照（含
integrity_check）＋ 单文件 cp 对照（丢行，含表缺失）＋ 缺失源库失败＋
干净库备份。
- HTTP 级回归对照：同夹具池（12 节点）下原版与补丁版服务 cellular 端点
  返回逐字节相同（tasks 4 条、stats total 12、verified 0）。
- 本轮失败均已定位修复（补丁或测试侧）：P0-1 池轮换用例按快照语义重写
  （旧批次仍接受是正确行为，测试原按 v1 语义误判）；矩阵三处测试侧问题
  （stats() 触发 sync_pool 改写 updated_at 致 SHA 基线漂移，改为先取
  stats 再取 SHA；REPLENISH_TARGET=3 致阶段 4 蜂窝 tasks 取空，阶段 2–4
  改报失败；wifi 行数基线取在 flood 之前，改到回滚起点重取）；
  `ingest_wifi` 曾把批次校验放在 `fp`/`ts` 赋值之前（NameError/错指纹），
  已调为先验字段再验批次；回滚脚本删表选项被矩阵门禁测试捕获并删除。

## 5. 五阶段部署矩阵结果（真实 HTTP + cellular 表 SHA）

隔离矩阵（模拟 nginx 代理层 + 同一隔离 DB + 夹具池），阶段日志：

| 阶段 | 服务 | nginx | 脚本 | cellular tasks/report | wifi tasks/report | 蜂窝表 SHA / 统计 | Wi-Fi 写入 |
|---|---|---|---|---|---|---|---|
| 1 基线 | 旧 | 旧 | 旧 | 200 / 200 | 404 / — | 基线已记 | 0 行 |
| 2 先换服务 | 新 | 旧 | 旧 | 200 / 200 | 404 / 404 | 仅因预期蜂窝回传而变 | 0 行 |
| 3 再加 nginx | 新 | 新 | 旧 | 200 / 200 | 200 / — | wifi tasks GET 后不变 | 0 行 |
| 4 新旧兼容 | 新 | 新 | 新+旧 | 200 / 200 | 200 / 200 | wifi 上报后不变 | 1 行（隔离 harness 扮演新脚本，非生产手机回传） |
| 5 最终换脚本 | 新 | 新 | 新 | 200 / 200 | 200 / 200 | wifi 上报后不变 | 2 行 |
| 6 滥用 | 新 | 新 | 新 | 200（滥用后仍可） | 畸形/超大/错通道/头不符 400，重复计 1 次，wifi 小时上限到达后 cellular 仍可发任务 | 不变 | 22 行 |
| R1 回滚脚本 | 新 | 新 | 旧 | 200 / 200 | — | — | 22 行保留 |
| R2 回滚 nginx | 新 | 旧 | 旧 | 200 / 200 | 404 / — | — | 22 行保留 |
| R3 回滚服务 | 旧 | 旧 | 旧 | 200 / 200 | 404 / 404（nginx 层与服务层均 404） | verified ≥ 1 完好 | 22 行保留 |

另：回滚脚本全文不含删表语句（矩阵断言）；回滚后 wifi 表保留、
cellular 数据完好、老客户端照常入库。

## 6. 隔离数据摘要

- 全部测试数据均为夹具指纹与合成毫秒；生产 `probe.db`（212 条）与
  `pool.db` 全程只读核查、零写入；生产脚本、生产服务、订阅、nginx、
  timer、手机配置零改动（复核：托管脚本仍 `1a0197db…ff837` 7148 字节，
  probe.db 仍 212 条，probe-service active）。
- 隔离库内 wifi/cellular 各通道的计数均来自测试种子，可复现
  （见 `tests/test_dual_probe.py` 与 `tests/test_deploy_matrix.py`）。

## 7. 生产变更评估（未执行，等 GPT 裁决）

**改动文件（共 3 处）**
1. `/opt/probe-service/probe_service.py` → 换成补丁版（先备份原文件；
   `probe.db` 用 SQLite backup API 一致性快照 + `integrity_check`，
   不用单文件 cp——服务跑在 WAL 模式，单文件复制可能丢未 checkpoint
   的提交；systemd 重启 probe-service）。
2. `/etc/nginx/conf.d/<nginx-vhost>.conf`：新增一个 exact location
   `location = /<seg>-wifi { proxy_pass http://127.0.0.1:18081; …同现有块… }`
   （现有块在 :43 行，`location = /<seg>`）；`nginx -t` 后 reload。
3. `/opt/surge-bridge/modules/probe-task.js` → 换成**私有渲染后**的
   生产脚本（先备份；渲染：真实 host/path 来自服务器本地 600 权限
   配置，占位符未替换干净即 fail-closed，`CLIENT_VERSION` 按渲染后
   内容重算；核对渲染产物 SHA，不用脱敏 GitHub SHA 当部署产物 SHA；
   手机端 `script-update-interval=0`，下次整点自动取新版）。

**顺序（五阶段，详见 `docs/STAGED_RUNBOOK.md`）**：① 基线 → ② 先换服务
（补丁版对老脚本完全兼容：cellular 路径行为逐字节相同）→ ③ 再加 nginx
（无此 location 时 wifi 端点在 nginx 层 404，脚本 fail-closed 跳过，
不丢数据）→ ④ 新旧脚本兼容验证（旧蜂窝兼容＋隔离新脚本；**不要求
生产 Wi-Fi 回传**）→ ⑤ 最终换脚本（私有渲染后上线）。部署后验证：
cellular `/stats` 与部署前一致；wifi 端点 `stats` 有计数；下一整点
两通道各有回传且标签正确。部署脚本按 stage 参数独立执行，一次一个
阶段，做完即停，无一键跑到底模式。

**回滚步骤（逆序）**
1. 恢复旧脚本文件（托管路径覆盖回原版，核对 SHA `1a0197db…ff837`），
   手机下次整点自动取回旧版。
2. 恢复原版 `probe_service.py`，重启服务；cellular 数据完好（S14、
   矩阵 R3 已验证）。
3. 删掉 nginx 的 `-wifi` location，`nginx -t` + reload（也可保留，
   服务层无该路径时返回 404，无影响）。
4. wifi 表（`probe_reports_wifi` / `probe_nodes_wifi`）留在库里保留审计；
   **常规回滚不删表**，没有清理选项。

**兼容性说明**：新脚本对旧服务：cellular 整轮正常（旧服务忽略未知头/字段）；
wifi 端点 404 → `tasks_error` → `$done()`，不回退到 cellular 路径。
旧脚本对新服务：cellular 路径行为与旧版逐字节相同。

## 8. 残余风险（诚实边界）

1. 批内切网的检测窗口：上报前重检能拦住“探测中切网”，但两次 HEAD 之间
   切网仍可能把一次探测记到旧标签下——窗口以毫秒计，残余风险极低，且
   服务端按端点+头双重校验，标签错误的记录会被拒绝。
2. `PROBE_URL_WIFI` 由 `PROBE_URL` 末段加 `-wifi` 派生，依赖随机路径为单段
   （当前路径符合）；若将来路径形态变了，派生失效时脚本会 404 fail-closed，
   不会误报。
3. Wi-Fi 探针测的是家庭宽带出口质量，不得与蜂窝证据混用；13 条新候选
   （SHA `f151f4b305c2`）仍需同 SHA 原生 13/13 证据，探针不能自动放行。
4. 接口名取值（en0/pdp_ipN/utunN）是 iOS 系统名，非 Surge 文档常量；
   若未来 iOS 或 Surge 改名，规则按 unknown fail-closed，不会误标——
   但可能导致 Wi-Fi 回传暂停，需届时复核。
5. 批次有效期 2 小时、时钟偏差允差 600 秒：手机时钟偏差超过 10 分钟时，
   新批次结果会被拒（fail-closed，可观测、可复核）。
6. 本补丁不解决原生门禁与生产切换的其余阻塞（PR #80、回滚锚点、
   钉选审批仍按原线推进）。

## 9. v3：GPT #6940445042 四项 P0 修复（逐文件终审，审阅 head 66a92adc）

**P0-1 确定性 SHA 版本竞态**（`service/probe_service_dual.py`）
- 根因：`do_GET` 在 `next_tasks[_wifi]()` 已把 batch_id + 池 SHA +
  指纹锁入 DB 后，又用 `info["pool_sha"] = pool_sha()` 重算覆盖；
  且指纹选择与 SHA 读取是两次独立的文件读取，:07 轮换可错绑。
- 修法：新增 `_pool_snapshot()`，池文件字节只读一次，SHA 与行集
  同源；`sync_pool(lines)` / `sync_pool_wifi(lines)` 接受快照行
  （默认仍读文件，独立调用行为不变）；`next_tasks()` /
  `next_tasks_wifi()` 先快照、再同步、再选候选、再以快照 SHA 签发
  批次；`do_GET` 只在无批次的 early-return（熔断/上限/目标达成）
  时填当前池 SHA，**有批次时绝不覆盖锁定 SHA**。
- 测试：新增轮换故障注入两处——`test_dual_probe.py` 函数级
  （快照后轮换，返回的仍是批次锁定 SHA）与 `test_deploy_matrix.py`
  HTTP 级（快照读取与 GET 返回之间轮换，旧批回传被接受且存旧快照
  SHA、不重标为新池合格；同批认新 SHA 被拒；轮换后新批次绑定新
  SHA）。S15（early-return 仍带 pool_sha）继续通过。

**P0-2 部署会把脱敏占位符原样发手机**（新增
`tools/render_probe_script.py`，`tools/deploy_dual.sh` 阶段 5）
- 根因：PR 脚本 `PROBE_URL` 仍是占位符，旧部署脚本只 `cp` 不渲染。
- 修法：阶段 5 先核对脱敏脚本 SHA，再由渲染工具从服务器本地 600
  权限配置（`deploy-render.conf`：`PROBE_HOST` + `NGINX_CONF`，
  永不进 PR、永不打印）与 `probe-path.txt` 取真实 host/path，替换
  占位符并校验 host/path 格式；渲染后 `PROBE_URL` 必须与配置完全
  一致（输入已带不同真实值即 fail-closed）；占位符残留即
  fail-closed；`CLIENT_VERSION` 按渲染后内容重算（与
  `tools/inject_sha.py` 同算法）；部署后按**渲染产物 SHA**核验，
  绝不用脱敏 GitHub SHA 当部署产物 SHA。nginx conf 路径与健康检查
  Host 同样来自私有渲染配置，不再硬编码。
- 测试：渲染工具正向（无占位符、URL 正确、CLIENT_VERSION 自验）
  与两个 fail-closed 负向（缺渲染配置、输入带过期真实 URL）；
  矩阵 `TestDeployScriptStages`：阶段 5 无渲染配置时拒绝部署、
  阶段 5 渲染部署后产物 SHA 即渲染 SHA 且不等于脱敏输入 SHA。

**P0-3 分阶段脚本与手册矛盾**（`tools/deploy_dual.sh`、
`docs/STAGED_RUNBOOK.md`、`tests/test_deploy_matrix.py`）
- 根因：旧脚本 service→nginx→script 一次跑到底，无 stage 参数；
  手册“第 1 步后停”做不到；阶段 4 在脚本未换时要求新脚本 Wi-Fi
  自然回传，逻辑不成立。
- 修法：部署脚本改为 `deploy_dual.sh <stage 1|2|3|4|5>`，一次一个
  阶段，做完即停（无一键跑到底模式）；每阶段自带 HTTP + SHA 门禁。
  阶段 4 改为“旧蜂窝兼容＋隔离新脚本”（HTTP 门禁 + 隔离矩阵的
  harness 扮演新脚本）；**生产 Wi-Fi 回传改到阶段 5**（脚本上线后
  下一整点）。手册按此改写，阶段编号与脚本一致；矩阵阶段 4 注释
  同步标注“隔离 harness 扮演新脚本，非生产手机回传”。
- 测试：`TestDeployScriptStages` 6 项（stage 参数必填、阶段 1/4
  对模拟服务/代理独立运行并停下、阶段 5 fail-closed、阶段 5 渲染
  部署、阶段结构断言）。

**P0-4 SQLite WAL 备份不可靠**（新增 `tools/backup_db.py`，
`tools/deploy_dual.sh` 阶段 2，手册步骤 0）
- 根因：服务 DB 跑 `PRAGMA journal_mode=WAL`，旧脚本对在线
  `probe.db` 直接 `cp`，可能遗漏 `-wal` 里未 checkpoint 的提交。
- 修法：备份改为 SQLite backup API 一致性快照（含未 checkpoint
  的 WAL 内容）+ 快照 `PRAGMA integrity_check` + 打印快照 SHA；
  快照落盘后转 `journal_mode=DELETE`，不依赖 `-wal` 边车文件。
  部署脚本阶段 2 与手册步骤 0 的预部署备份均改用该工具。
  **报告此前从未声称单文件复制足以可靠恢复**（全文核查无此说法）；
  现明确写明：单文件 cp 不是可靠备份。
- 测试：新增 `tests/test_backup.py` 3 项——未 checkpoint 行的快照
  含全部行 + integrity ok；对照：单文件 cp 丢全部行（连表结构
  都没有）；缺失源库失败；干净库备份。

**保留的正确设计（未动）**：Wi-Fi 与 cellular 独立存储、探针记录
仅为客户端声明、不能升级 P0 原生验证、回滚保留 Wi-Fi 表。
**兼容例外措辞核查**：旧版 cellular 客户端无 batch 字段仍被接受，
报告 §3 门禁 1 与 §4 S12 已写明“旧蜂窝客户端不发绑定字段时仍可
入库（向后兼容）”，手册阶段 2 亦补写“不得声称所有蜂窝记录都已强
绑定 SHA”；全文无相反说法。

**打包工具修正**：`tools/make_pr_package.py` 步骤 4b 曾把报告/样本写成
仅 4 行说明（`open(..., "w")` 先截断、后读原文的次序 bug，v2 PR 包
里的报告与样本副本因此只有说明、没有正文）；已改成先读后写并重建
PR 包，包内报告 382 行、样本 118 行已核对完整。
（核验 2026-11-17：本地 root 39/39、本地 nobody 39/39、VPS root 39/39、
VPS nobody 39/39，JS 本地 43/43；PR 包内复跑 Python 39/39、JS 43/43；
隔离树与 VPS 双边 SHA 已逐个核对一致。）
