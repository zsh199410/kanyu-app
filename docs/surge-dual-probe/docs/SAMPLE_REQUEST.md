> PR 包副本说明：本样本采自隔离运行，其 `CLIENT_VERSION` 值为隔离树
> 脚本的构建 ID；本包脚本的 `CLIENT_VERSION` 已按脱敏后内容重算
> （见 `DESENSITIZATION_CHECKLIST.md`）。绑定结构与字段含义不变。

# P0-1 绑定样本：一条真实请求 JSON 与入库列

以下全部来自一次隔离运行（合成夹具池，TEST-NET 主机），非手写示例。

## 两个版本概念的来源与区别

| 字段 | 值 | 来源 | 含义 |
|---|---|---|---|
| `source_version_sha` | 池文件内容 SHA256（64 hex） | 服务端：发 tasks 时锁定**任务快照**的池 SHA（`info.pool_sha`），脚本原样回填；入库时服务端按批次记录校验，不对照“当前池文件” | **被测节点池的版本**：结果绑定到哪一份池文件快照 |
| `batch_id` | `b-<16 hex>` | 服务端：发 tasks 时锁定批次记录（池 SHA＋指纹集＋有效期），脚本原样回填；入库时服务端按该记录验指纹/版本/时窗/去重键 | **任务批次绑定**：这条结果属于哪一批下发的任务 |
| `client_version` | 脚本构建 ID（`dual-v1-<sha12>`） | 构建时注入：`tools/inject_sha.py` 对脚本文件算 SHA（占位符归一化后前 12 hex） | **手机脚本自身的版本**：哪一份客户端代码发的这条结果 |

三者绝不混用：脚本构建 ID 不能当池版本；池 SHA 不能标识客户端代码；
没有批次绑定，结果不能证明属于哪一批任务。
关键更正（GPT #6938432964 门禁 1）：真实池 SHA 必须是**任务快照的 SHA**，
不是接收 POST 时的“当前池”SHA。服务端下发批次时锁定完整
`source_version_sha`＋`task_id/batch_id`＋指纹集＋有效期；接收时按绑定记录
验证指纹、版本、时窗与去重键；期间 :07 轮换不得把旧批次记录标成新池合格。
所有不匹配 fail closed。旧蜂窝客户端不发绑定字段时仍可入库（向后兼容）；
一旦发送任一绑定字段，就必须通过批次记录校验。

## 1. tasks 响应（服务端签发 pool_sha + batch_id）

```json
{
  "ok": true,
  "tasks": [
    {
      "fingerprint": "ea2a430bf8d12a13a3ebad61b8f391db",
      "name": "Fixture1",
      "protocol": "trojan"
    },
    {
      "fingerprint": "cc58216bed8bc0e89520589049bd5ee4",
      "name": "Fixture2",
      "protocol": "trojan"
    }
  ],
  "info": {
    "reason": "ok",
    "batch_size": 4,
    "tested_hour": 0,
    "tested_day": 0,
    "qualified_hour": 0,
    "pool_sha": "914558d062a58f21191abfa0a776db9df617442ec279391d62a22ed3e3282723",
    "batch_id": "b-d184ed6148ab405f"
  }
}
```

## 2. 上报请求体（脚本回填 pool_sha + batch_id 原值 + 自身 client_version）

```json
{
  "results": [
    {
      "fingerprint": "ea2a430bf8d12a13a3ebad61b8f391db",
      "name": "Fixture1",
      "ts": 1794890906,
      "state": "measured",
      "warm_ms": 120,
      "second_request_ms": 95,
      "second_status": 204,
      "success": true,
      "error": null,
      "network_type": "wifi",
      "source_version_sha": "914558d062a58f21191abfa0a776db9df617442ec279391d62a22ed3e3282723",
      "batch_id": "b-d184ed6148ab405f",
      "client_version": "dual-v1-1aa60229fd22"
    },
    {
      "fingerprint": "cc58216bed8bc0e89520589049bd5ee4",
      "name": "Fixture2",
      "ts": 1794890907,
      "state": "measured",
      "warm_ms": 120,
      "second_request_ms": 105,
      "second_status": 204,
      "success": true,
      "error": null,
      "network_type": "wifi",
      "source_version_sha": "914558d062a58f21191abfa0a776db9df617442ec279391d62a22ed3e3282723",
      "batch_id": "b-d184ed6148ab405f",
      "client_version": "dual-v1-1aa60229fd22"
    }
  ]
}
```

## 3. 入库行（probe_reports_wifi）

```json
{
  "id": 1,
  "fingerprint": "ea2a430bf8d12a13a3ebad61b8f391db",
  "name": "Fixture1",
  "ts": 1794890906,
  "state": "measured",
  "warm_ms": 120,
  "second_ms": 95,
  "second_status": 204,
  "success": 1,
  "error": null,
  "network_type": "wifi",
  "source_version_sha": "914558d062a58f21191abfa0a776db9df617442ec279391d62a22ed3e3282723",
  "client_version": "dual-v1-1aa60229fd22",
  "batch_id": "b-d184ed6148ab405f"
}
```

入库核对：`source_version_sha` == tasks 响应里的 `pool_sha`（该批次锁定
的快照 SHA）；`batch_id` == tasks 响应里的 `batch_id`；`client_version` ==
脚本构建 ID；三者不同值。`network_type` 是客户端声明的标签，
不是原生验证证据（见报告 P0-3 节）。
