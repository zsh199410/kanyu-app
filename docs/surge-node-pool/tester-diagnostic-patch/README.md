# Tester 最小诊断增量（Draft PR 材料）

> 状态：Draft，仅供评审。生产 tester.py 与 node_tests 均未动。
> 本目录含脱敏补丁（tester.patch / db.patch / cli.patch）与测试证据。
> 不含任何节点凭据、URI、token、热修配置。

## 背景

生产测试器 `pool/tester.py` 的失败只记 `curl-failed`，丢失 curl 退出码与
失败阶段诊断。P0 排障（2026-11-23）证实：2400 次失败主要是节点真死与
中继 403，不是测试器误杀；但历史记录无法事后拆解阶段，因为阶段信息
从未存过。本补丁只加诊断，不改判定。

## 改了什么

### tester.py（tester.patch，159 行差异）
- curl `-w` 改为命名字段：`http_code`、`exitcode`、`time_total`、
  `time_namelookup`、`time_connect`、`time_appconnect`、`time_starttransfer`。
- sing-box stderr 捕获到临时文件，仅提取 ERROR 行并脱敏
  （抹节点 host 与 IP 字面量、截断 200 字符），用完即删，不落盘。
- 新增 `classify_stage()`：失败按阶段分类
  （dns/tcp/tls/http/timeout/socks/infra/other），含 TLS 优先于 DNS 的
  修正（TLS 证书失败曾被误判为 DNS，隔离验证中已抓到并修掉）。
- `test_one` 返回 `(result, ms, reason, diag)`，`diag` 为诊断字典；
  `test_many` 返回 5 元组。`result/ms/reason` 与原版完全一致。

### db.py（db.patch，30 行差异）
- `node_tests` 增加 9 个可空列：`curl_exit`、`http_code`、`stage`、
  `stage_detail`、`t_lookup_ms`、`t_connect_ms`、`t_appconnect_ms`、
  `t_total_ms`、`sb_err`。
- `record_test()` 增加可选 `diag=None` 参数；INSERT 改显式列名；
  未提供 diag 时新列写 NULL，旧行为不变。

### cli.py（cli.patch，30 行差异）
- 3 处 `test_many` 循环与 `retest-one` 解包改为 5 元组/4 元组，
  把 `diag` 传给 `record_test`；`retest-one` 的 JSON 输出增加
  `stage`/`detail`。

## 没改什么

- 并发（8）、超时（8 秒）、发布规则、健康判定（pass/fail/infra/filtered）、
  判活 SQL（`SELECT ms ... WHERE result='pass'`）均未动。
- `nodes` 表的 `last_result/pass_count/test_count` 更新逻辑未动。
- 不启动第二个生产 worker，不改任何定时器与开关。

## 隔离验证结果（均在独立副本上，未碰生产）

### 迁移测试（test_migration.py，隔离 DB 副本 246,564 行）
- 迁移幂等：跑两次，第一次加 9 列，第二次全部跳过。
- 旧记录原样保留：行数不变，新列全部 NULL。
- 判活 SQL 结果不变（50 个节点抽样，迁移前后一致）。
- 新列全部可空；`record_test` 带 diag 写入诊断值，不带 diag 写 NULL；
  `nodes` 健康字段逻辑与旧版一致。

### 功能对照（生产 tester vs 补丁 tester，同一批节点）
- 4 个可比节点：`result` 与 `reason` 4/4 一致；`ms` 在失败时一致为 0.0，
  通过时因网络波动略有差异（75.1ms vs 151.5ms，均为 pass）。
- 补丁版正确分类 4 个不同失败阶段：
  超时（singbox-timeout，5.0s）、中继 HTTP 404（relay-http-404）、
  TLS 证书校验失败（tls-verify）、超时。
- `sb_err` 脱敏生效：节点 host 被抹为 `[host]`，无 IP 字面量。

## 迁移（生产部署阶段 3 时执行，需另行批准）

```sql
ALTER TABLE node_tests ADD COLUMN curl_exit INTEGER;
ALTER TABLE node_tests ADD COLUMN http_code TEXT;
ALTER TABLE node_tests ADD COLUMN stage TEXT;
ALTER TABLE node_tests ADD COLUMN stage_detail TEXT;
ALTER TABLE node_tests ADD COLUMN t_lookup_ms REAL;
ALTER TABLE node_tests ADD COLUMN t_connect_ms REAL;
ALTER TABLE node_tests ADD COLUMN t_appconnect_ms REAL;
ALTER TABLE node_tests ADD COLUMN t_total_ms REAL;
ALTER TABLE node_tests ADD COLUMN sb_err TEXT;
```

全部可空；旧记录新列为 NULL；不补造旧 curl exit/stage。
部署顺序：先迁移 schema，再部署补丁代码；回滚：恢复备份的
tester.py/db.py/cli.py（备份见下），新列可留空或删除（删列需
SQLite 重建表，建议保留空列）。

## 备份

- 生产 tester.py（SHA e012ff36…）、SQLite 一致快照（WAL 安全备份，
  行数与生产一致）、schema、config.yaml、sources.yaml、测试器
  systemd 单元与定时器：
  `/opt/p2p3-cutover-backups/tester-patch-20261123T220636Z/`
- 隔离验证的增强版与生产原件：
  `/opt/p2p3-cutover-backups/tester-p0-20261123T0630Z/`

## 进入生产部署（阶段 3）之前还缺什么

- 非冲突时间窗口（避开 03:30 全量与每小时 :42 增量测试）。
- 备份/隔离回放/健康与失败正负对照/完整性检查通过。
- 部署后至少观察两次正常调度周期，统计 exit/stage/HTTP/latency 分布。
- 异常、锁冲突、数据库破坏或判定变化则停止并按备份回滚，保留审计。
- 隔离 3 轮通过 ≠ 生产部署完成。
