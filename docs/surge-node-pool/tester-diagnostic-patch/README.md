# Tester 最小诊断增量（Draft PR 材料 · v3）

> 状态：Draft，仅供评审。生产 tester.py 与 node_tests 均未动。
> 本目录含脱敏补丁（tester.patch / db.patch / cli.patch）、可执行迁移脚本
> （migrate_diag_columns.py）与回归测试（test_migration.py / test_security.py /
> test_compat.py / test_functional.py / test_negative.py）。
> 不含节点密码、完整代理URI、token、热修配置。
> 用于现网功能对照的若干 `test_*.py` 脚本保留了 **公开节点IP字面量** 与 VPS 目录路径，
> 这些是 Muse 报告的公开源测试定位信息，不是脱敏假数据；不可对整个 PR 宣称“零IP”。
> 真实数据对照仅在可信VPS隔离环境运行，不要公开包含凭据/节点URI的测试日志。
>
> v2 说明：针对 GPT 在 PR #124 上的审查（review 6030476985，
> 2026-11-23T22:23:47Z，基于 commit 1af4ed2）提出的 3 项阻塞做了最小修正，
> 见“v2 修复了哪 3 项”。v1 的隔离测试结论（测试器本身没坏、2400 次失败
> 主因是节点真死 + 中继 403）不受影响。

## v3.1 · VPS 9/9 回归后收尾

Muse在 Issue #73 回执 #7117250147 报告：VPS 真实库副本回归 **9/9 通过**（含无fuzz补丁适配、WAL、迁移、安全、兼容、功能与阴性对照），正式服务未修改。

针对其发现的CLI缺口，GPT-6 直接修复：
- `migrate_diag_columns.py` 执行 `--rollback` 时，JSON `ok=false` 将 **退出状态码1**，`ok=true` 为0。生产编排依然必须同时校验退出码和JSON；任何异常都拒绝继续部署。
- `test_rollback_wal.py` 增加坏快照/好快照的**实际子进程CLI退出码与JSON一致性测试**。这两处改动需要Muse在**最新HEAD**的VPS隔离环境再次运行该测试，完成后方可阶段3切换。
- 公开节点IP仅为旧的功能/阴性测试定位；保留诊断价值但不表示凭据可公开，若出现非公开地址须移到受限环境参数，勿写入仓库。

## v3 · GPT-6 直接修复（PR #124 第二轮复审的两项 P0）

本版由 GPT-6 直接写入本 Draft 分支；**仅修改评审材料，没有部署或修改 VPS 的生产 tester.py / SQLite / timer**。

1. **拒绝危险的临时日志路径**：`tester.patch::_create_log_file` 改用
   `O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW（支持时）`，保留 `0600`；
   已存在文件、预置 symlink 一律报错并保持目标原样，不用 `O_TRUNC`。
   `test_security.py` 增加真实文件与 symlink 的阴性用例。
2. **WAL 安全回滚**：`migrate_diag_columns.py::rollback` 不再使用
   `shutil.copyfile` 直接覆盖数据库主文件；使用 SQLite backup API
   恢复一致快照，检测当前写锁，复开连接后逐表计算内容摘要、
   检查 schema / 行数 / integrity，任何不一致返回 `ok=false`。
   原始迁移的完整性、行数、判活 SQL 门禁也改为失败即抛错。
3. **独立回归**：`python3 test_rollback_wal.py` 无需生产环境；用保持
   未 checkpoint WAL 的数据库实际验证：恢复后旧列与记录不会复活、
   保持打开的旧连接关闭后仍一致；活动写事务、损坏快照、同文件恢复
   均拒绝。日志 0600 / symlink / 现有文件防覆盖也已在本地隔离演练。

**生产回滚仍要求先停止所有测试器 service/timer 及其他 SQLite 写入者，
并由操作者核实；代码的 `BEGIN IMMEDIATE` 只检测当前写锁，
不能代替业务停机或跨进程维护锁。** 绝不能在仍有写进程运行时使用
`--rollback`。恢复期间保留原始备份，不能用滚动写入的生产库覆盖快照。

本次PR只是隔离补丁文件：进入阶段3前必须确认补丁能应用到**当前** VPS
原文件（context/hash 检查），在离线备份上实际运行全套测试，
并避开 03:30 全量和每小时 :42 增量；部署后连续2个正常调度周期验收。
未获得运行证据前不得标记 `DEPLOYED`。

## 背景

生产测试器 `pool/tester.py` 的失败只记 `curl-failed`，丢失 curl 退出码与
失败阶段诊断。P0 排障（2026-11-23）证实：2400 次失败主要是节点真死与
中继 403，不是测试器误杀；但历史记录无法事后拆解阶段，因为阶段信息
从未存过。本补丁只加诊断，不改判定。

## v2 修复了哪 3 项（GPT 审查意见逐条对照）

### 阻塞 1（P0 安全）：不再强制 debug，日志 0600、有界、异常清理，DB 不存原始错误原文
GPT 意见原文摘要：`tester.patch` 将 `cfg["log"] = {"level": "debug"}` 强制用于
每条生产测试，`errf = open(tmp + ".log", "w")` 在 umask 022 下是 0644；
`_sanitize_sb_err` 只抹当前 host 和 IP，原始 debug 日志已落盘，不能以
“用完即删”作为安全保证；DB 不应默认写未经穷尽脱敏的自由文本 `sb_err`。
- **去掉 debug 强制**：删除 `cfg["log"] = {"level": "debug"}` 与 `DEBUG`
  环境变量，日志级别沿用生产 `build_config` 的默认 `error`——只采集最小
  必要的 ERROR 行，不产生 debug 内容。
- **日志文件显式 0600**：`os.open(path, O_CREAT|O_WRONLY|O_TRUNC, 0o600)`，
  mode 不受 umask 影响；回归测试覆盖 umask 022/027/077，实测均为 0600。
- **有界读取**：`_read_error_lines()` 只读文件末尾 32 KiB、只保留 ERROR 行、
  最多 20 行，用 `with open` 读取；回归测试用超大日志验证（1025 字节、
  20 行、尾部 ERROR 保留、非 ERROR 行不混入）。
- **明确关闭/终止时序**：curl 结束后先关 errf、停子进程（terminate 等 2 秒
  再 kill），再有界读日志，最后返回；finally 兜底关闭 errf、终止子进程、
  删除临时文件（含异常路径）。回归测试验证 pass/fail/timeout 三路径后
  均无残留文件、端口已关闭。
- **DB 不存原始错误原文**：删除 `sb_err` 列（schema 从 9 列新列改为 8 列），
  `diag` 不再含 `sb_err`；`record_test` 只取白名单字段（curl_exit、
  http_code、stage、detail 与 4 个耗时），即使调用方传入 `sb_err` 等自由
  文本也不写入。`stage`/`detail` 均为枚举化白名单值。
- **敏感信息注入回归测试**（test_security.py）：构造含 token、SNI、IPv6、
  密码的 sing-box 错误行，验证分类结果与写入 DB 的行均不含任何注入值；
  另验证注入的 `sb_err` 自由文本字段不进 DB。

### 阻塞 2（P0 迁移）：可重复的显式 schema 迁移与回滚门禁
GPT 意见原文摘要：`db.patch` 只更新 `CREATE TABLE` 与 16 列 INSERT，不会为
现有 7 列库自动加 9 列；README 虽列 ALTER SQL，但 PR 里没有可执行、幂等的
迁移脚本/自动验证；部署顺序或版本错配会导致 `record_test` 因缺列失败。
- **新增可执行迁移脚本** `migrate_diag_columns.py`（本 PR 内，幂等）：
  `PRAGMA table_info` 后仅补缺失的列；迁移前用 sqlite3 backup API 做 WAL
  一致备份；迁移前后跑 `integrity_check`、行数、关键判活 SQL（50 个节点
  抽样），结果必须相同；`--check` 为 dry-run（只报告缺失列，不改库）；
  `--rollback` 用迁移前快照恢复 DB。
- **兼容性实测结论（--compat-check）**：旧版代码的位置 INSERT（7 值）在已
  迁移的 15 列库上实测失败（`table node_tests has 15 columns but 7 values
  were supplied`）。因此部署必须是停机原子进行：停测试器 → 备份 → 迁移
  schema → 部署补丁代码 → 验证 → 启动；绝不能“先迁 schema、旧代码继续跑”。
  回滚 = 恢复备份的 tester.py/db.py/cli.py + 用 `--rollback` 恢复迁移前
  DB 快照（新列可留空或删除，删列需重建表，建议恢复快照）。
- **迁移测试证据**（test_migration.py，隔离 DB 副本 247,365 行）：
  `--check` 报告缺 8 列且不改库；迁移跑两次，第一次加 8 列、第二次全部
  跳过；行数不变、新列全部 NULL；判活 SQL 前后一致；`integrity_check`
  前后均为 ok；`sb_err` 列不存在；`record_test` 带 diag / 不带 diag /
  注入 diag 三种情况均正确（注入值不进 DB）；nodes 健康字段逻辑不变；
  回滚后列数回到 7、行数回到 247,365、判活 SQL 不变。

### 阻塞 3（P1 兼容与性能）：全部调用方已核查，有界读取与子进程生命周期回归
GPT 意见原文摘要：`test_one` 返回 3→4 元组、`test_many` 返回 4→5 元组；
`cli.patch` 修了已知调用点，但生产仓库/VPS 中所有导入者必须实际搜索并
复测；日志文件在子进程仍存活时读全文，建议改为有界读取与明确关闭/终止
时序；新增回归测试应含 curl 不同退出码、HTTP 非 000 但 curl 失败、
stderr 抹密、进程异常中断、SQLite 旧库迁移与一批完整 worker 记录。
- **调用方审计**（test_compat.py，实测 grep）：生产仓库内只有
  `pool/cli.py` 导入 `tester`（`test_many`、`test_one`）；调用点只有
  cli.py 的 4 处（3 处 `test_many` 循环 + `retest-one`）与 tester.py 内部
  的 2 处（`test_many` 重试逻辑），已全部适配 4/5 元组；其余模块
  （serve.py、winner_clean.py、scheme_a.py、publish.py 等）均不导入 tester。
  `backup-p1p3-20261113-190706/pool-code/` 是 2026-11-13 的旧备份，非 live
  代码，不执行。
- **有界读取与明确时序**：见阻塞 1 的 `_read_error_lines()` 与
  test_one 重构（关 errf → 停子进程 → 有界读日志 → 返回）。
- **回归测试**（test_security.py、test_compat.py）：curl 退出码矩阵 14 例
  全过（含 HTTP 非 000 但 curl 失败按 HTTP 判定、exit 6/7/28/97 与其他
  退出码）；stderr 注入回归；进程异常中断清理（生命周期测试）；SQLite
  旧库迁移（test_migration.py）；完整 worker 批次 5 节点 / 5.3 秒 / 5 行
  写入，stage 均为枚举值（pass、timeout、tls-verify、relay-http-404）。

## 改了什么

### tester.py（tester.patch，294 行差异）
- curl `-w` 改为命名字段：`http_code`、`exitcode`、`time_total`、
  `time_namelookup`、`time_connect`、`time_appconnect`、`time_starttransfer`。
- sing-box 日志级别沿用生产默认 `error`（不强制 debug）；stderr 只写
  0600 临时文件（os.open 显式 0600），仅读 ERROR 行（有界 32 KiB、
  最多 20 行），用后即删；关闭/终止/读取时序明确。
- 新增 `classify_stage()`：失败按阶段分类
  （dns/tcp/tls/http/timeout/socks/infra/other），含 TLS 优先于 DNS 的
  修正（TLS 证书失败曾被误判为 DNS，隔离验证中已抓到并修掉）。
  `stage`/`detail` 为枚举化白名单值，可直接持久化。
- `test_one` 返回 `(result, ms, reason, diag)`，`diag` 为诊断字典；
  `test_many` 返回 5 元组。`result/ms/reason` 与原版完全一致。
- 删除 `DEBUG` 环境变量与 `_sanitize_sb_err`（DB 不再存原始错误原文，
  脱敏函数无保留必要）；删除 `sb_err`。

### db.py（db.patch，47 行差异）
- `node_tests` 增加 8 个可空列：`curl_exit`、`http_code`、`stage`、
  `stage_detail`、`t_lookup_ms`、`t_connect_ms`、`t_appconnect_ms`、
  `t_total_ms`（v1 的 `sb_err` 已删除）。
- `record_test()` 增加可选 `diag=None` 参数；INSERT 改显式列名（15 列）；
  未提供 diag 时新列写 NULL，旧行为不变；不写入任何自由文本错误原文。

### cli.py（cli.patch，62 行差异，与 v1 相同）
- 3 处 `test_many` 循环与 `retest-one` 解包改为 5 元组/4 元组，
  把 `diag` 传给 `record_test`；`retest-one` 的 JSON 输出增加
  `stage`/`detail`。

### migrate_diag_columns.py（新增，可执行迁移脚本）
- 见阻塞 2。用法：`python3 migrate_diag_columns.py <db> [--backup-dir DIR]`
  迁移；`--check` dry-run；`--compat-check` 旧代码兼容性实测；
  `--rollback <快照>` 恢复 DB。

## 没改什么

- 并发（8）、超时（8 秒）、发布规则、健康判定（pass/fail/infra/filtered）、
  判活 SQL（`SELECT ms ... WHERE result='pass'`）均未动。
- `nodes` 表的 `last_result/pass_count/test_count` 更新逻辑未动。
- 不启动第二个生产 worker，不改任何定时器与开关。
- 不改 sing-box 二进制版本，不改订阅与发布流程。

## 隔离验证结果 v2（均在独立副本上，未碰生产）

### 迁移测试（test_migration.py，隔离 DB 副本 247,365 行）
- `--check` 报告缺 8 列，不改库；迁移幂等（跑两次，第二次全部跳过）；
  旧记录原样保留（行数不变，新列全部 NULL）；判活 SQL 前后一致；
  `integrity_check` 前后均为 ok；`sb_err` 列不存在；
  `record_test` 带 diag / 不带 diag / 注入 diag 均正确；
  nodes 健康字段逻辑不变；回滚后列数 7、行数 247,365、判活 SQL 不变。
- 兼容性实测：旧版位置 INSERT 在 15 列库上失败，证明必须停机原子部署。

### 安全回归（test_security.py）
- umask 022/027/077 下日志文件均为 0600。
- 注入回归：token/SNI/IPv6/密码均未进入分类结果与 DB 行。
- 有界读取：1025 字节、20 行 ERROR、尾部保留、非 ERROR 行不混入。
- 生命周期：pass/fail/timeout 三路径后均无残留文件、端口已关闭。
- 分类矩阵：14 例全过。

### 兼容性测试（test_compat.py）
- 调用方审计：只有 cli.py 导入 tester，调用点全在 cli.py/tester.py。
- filtered 路径返回 4 元组；完整 worker 批次 5 节点 / 5.3 秒 / 5 行，
  stage 正确区分 pass、timeout、tls-verify、relay-http-404。

### 功能对照（生产 tester vs v2 补丁 tester，同一批节点）
- 4 个可比节点：`result` 与 `reason` 4/4 一致；`ms` 在失败时一致为 0.0，
  通过时因网络波动略有差异（172.0ms vs 72.3ms，均为 pass）。
- 补丁版正确分类 4 个不同失败阶段：超时（singbox-timeout，5.0s）、
  中继 HTTP 404（relay-http-404）、TLS 证书校验失败（tls-verify）、超时。
- 附带发现：38.68.135.131 在 P0 验证时 3/3 通过（157–163ms），现已失败
  （超时），两版测试器判定一致，属节点本身变化，非补丁问题；
  加拿大与 152.70.105.42 已不在新鲜抓取中，两版均为 MISSING，无分歧。

### 阴性对照（3 条 trojan，生产 vs v2 补丁）
- 3/3 的 `result`/`reason` 一致（均为 fail/curl-failed）；补丁版 stage
  分别为 timeout、relay-http-404、tls-verify。

## 迁移与部署（生产部署阶段 3 时执行，需 GPT 重新审查通过后另行批准）

部署顺序（停机原子进行，缺一不可）：
1. 停测试器（pool-test / pool-test-full 两个 timer 与 service）。
2. 备份：生产 tester.py/db.py/cli.py、WAL 一致 SQLite 快照、schema、
   配置、定时任务（备份目录见下）。
3. `python3 migrate_diag_columns.py <db> --backup-dir <备份目录>`，
   核对报告（added 8 列、integrity ok、行数与判活 SQL 不变）。
4. 部署补丁代码（tester.py/db.py/cli.py），核对 SHA。
5. 验证：`--check` 报告无需迁移；`retest-one` 一次；观察两个正常
   调度周期，统计 exit/stage/HTTP/latency 分布。
6. 异常、锁冲突、数据库破坏或判定变化则停止并回滚：恢复备份的代码文件
   + `migrate_diag_columns.py <db> --rollback <迁移前快照>`，保留审计。

回滚证据（隔离已验证）：回滚后列数 7、行数 247,365、判活 SQL 不变、
integrity ok。

## 备份

- v2 备份目录：`/opt/p2p3-cutover-backups/tester-patch-v2-20261124T001500Z/`
  （生产 tester.py SHA e012ff36…、SQLite 一致快照 247,365 行、schema、
  配置、定时任务、v2 补丁与测试脚本、隔离验证结果 JSON）。
- v1 备份目录：`/opt/p2p3-cutover-backups/tester-patch-20261123T220636Z/`。
- 隔离验证的增强版与生产原件：
  `/opt/p2p3-cutover-backups/tester-p0-20261123T0630Z/`

## 进入生产部署（阶段 3）之前还缺什么

- GPT 对本 v3 HEAD 的复审及全部回归测试通过。
- 非冲突时间窗口（避开 03:30 全量与每小时 :42 增量测试）。
- 部署后至少观察两次正常调度周期，统计 exit/stage/HTTP/latency 分布。
- 异常、锁冲突、数据库破坏或判定变化则停止并按备份回滚，保留审计。
- 隔离测试通过 ≠ 生产部署完成。
