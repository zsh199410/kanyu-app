# 旧发布器输入数据 schema（只读描述，不含真实值）

## 1. `pool.db`（SQLite，`/opt/free-node-program/data/pool.db`）

| 表 | 关键列 | 发布逻辑中的用途 |
|---|---|---|
| `nodes` | protocol, host, port, source, name_hint, first_seen, last_seen, last_test_at, last_result, last_reason, pass_count, test_count, country, status | `db_pass` 来源：`last_result='pass'` 且新鲜 |
| `node_tests` | protocol, host, port, result, ms, tested_at | 最新一次 pass 的 ms（须 ≤300） |
| `pinned` | protocol, host, port, name, created, by | 钉选集合（25 行；发布时 21 行在池） |
| `blocklist` | （协议/主机/端口） | 拉黑，`kept_old` 与新轮换均排除 |
| `config` | per_country_cap, publish_max_lines, publish_fresh_hours, publish_max_vps_ms, publish_min_pass_rate, vmess_tls_only, disabled_sources | 发布参数（见默认值） |
| `audit` | — | 发布审计记录 |
| `winner_reports` / `scheme_a_batches` / `scheme_a_winners` | — | Scheme A 胜者轮次 |
| `published_first` | — | 轮换节点首次发布时间（Scheme B 清洗用） |

配置默认值（`config.yaml` 未覆盖时）：`publish_fresh_hours=12`，
`publish_max_vps_ms=300`，`publish_min_pass_rate=0.5`，
`per_country_cap=40`，`publish_max_lines=150`。

## 2. 订阅文件（Surge 原生格式）

`/opt/free-node-program/publish/pool-new.txt` → `:15` 同步到
`/opt/surge-bridge/modules/pool-new.txt`（托管订阅，手机策略组
`policy-path` 指向该地址）。每行格式：

```
名称 = trojan, host, port, password=..., sni=..., ...
```

名称即 `国家/地区+序号+国旗`（如 `香港24 🇭🇰`）。指纹算法与探针服务一致：
`SHA256(proto|host|port|sorted k=v params)` 前 32 hex，排除显示名。

## 3. 探针服务 `probe.db`（发布逻辑目前不读）

`/opt/probe-service/data/probe.db`，`probe_nodes` 表：

- `fingerprint`（同上算法）、`name`、`protocol/host/port`
- `state`：pending / verified / expired / quarantined / retired
  （verified 唯一条件：手机实测 success 且 <300ms，VERIFY_TTL 24h）
- `last_phone_ts`、`last_second_ms`、`last_success`、`phone_ok` / `phone_fail`

`probe_reports`（蜂窝，224 行）与 `probe_reports_wifi`（Wi-Fi，0 行）为
手机回传明细。探针服务地址 `127.0.0.1:18081`，nginx 8443 反代。

## 4. 定时器（生产现行，未改）

- `pool-publish.timer`：每小时 :07，`pool-publish.service`（旧发布器）
- `pool-sync.timer`：每 15 分钟，`pool-sync.service`（served → bridge）
- `pool-crawl` 每小时 :12、`pool-test` 每 2 小时 :42、
  `pool-test-full` 每日 03:30
- 门禁 `pool-gate-publish.timer`：**不存在，未部署**
