# Fail-closed 安全出口控制器（任务 A）

只控制一个 Surge 5 select 策略组「测试安全出口」，通过 Surge 官方 HTTP API。
独立测试 profile，不碰生产配置、不停生产 timer、不删节点、不动 blocklist / STOP / 21 钉选。

## 文件

| 文件 | 说明 |
|---|---|
| `safe-egress-test.conf` | 独立可运行的 Surge 5 测试 profile（A1） |
| `check_conf.py` | conf 静态检查脚本：真实解析 conf 并校验（A1） |
| `selector-controller.py` | 出口控制器，Python 3 标准库 + urllib，无外部依赖（A2） |
| `selector-state.py` | 状态持久化：原子写、状态枚举、TTL、加载即标记未验证（A3） |
| `../tests/mock_surge_api.py` | mock Surge HTTP API 服务器（仅测试用） |
| `../tests/test_selector_controller.py` | 正常路径测试（A5） |
| `../tests/test_selector_failures.py` | 负例测试（A5） |

## 设计

- 策略组 `测试安全出口 = select, REJECT, Test-Proxy-1, Test-Proxy-2, Test-Proxy-3`，
  首位固定为 REJECT；测试代理全部用 TEST-NET `192.0.2.0/24` + 密码 `test123`，
  无真实节点 URI / token / 真实出口 IP。
- 仅 `example.com` 走测试出口，其余流量 `FINAL,REJECT`。
- 选代理的前置条件（缺一不可）：候选健康检查通过（TEST-NET 内地址、
  延迟 < 300ms、证据 < 24h）、候选集合 SHA 与预期版本一致、成员名在设备
  成员列表中真实存在、无重复标识、设备已加载预期测试配置。
- 每次选择后必须 GET 回读验证，回读不一致即视为未验证。
- 无合格节点 / 证据过期 / STOP / 版本不匹配 → 尝试显式选 REJECT 并回读确认。
- POST 超时、返回不确定、GET 失败 → 状态为 `SELECTION_UNKNOWN`（API 不可达时
  为 `CONTROLLER_UNAVAILABLE`），**绝不声称已切到 REJECT**，也不放行生产。
- 状态：`REJECT_VERIFIED`、`PROXY_VERIFIED`、`EVIDENCE_EXPIRED`、
  `VERSION_MISMATCH`、`SELECTION_UNKNOWN`、`CONTROLLER_UNAVAILABLE`、`STOPPED`。
  只有新近验证过的 `PROXY_VERIFIED` 允许生产流量走测试出口。
- 状态文件原子写（同目录 tmp + fsync + rename）；加载旧状态一律标记未验证，
  必须经启动回读重新验证才可信任。
- 日志为脱敏结构化 JSON：只记策略名、SHA、状态与原因，不记密码、token、URI 与主机地址。
- 人工回滚入口：`SelectorController.rollback_to_reject(manual=True)`。

## 三个安全问题的诚实结论

### 1. 手机重启后是否保留上一次选择？
**保留。** Surge select 选择随 profile 持久化，重启后仍是上一次的选择。
因此控制器从不信任持久化选择：启动时 `startup_reverify()` 加载状态文件
（加载即标记未验证），再用 GET 回读实时选择，只有实时值与记录一致且证据
未过期时才重新标记为已验证；不一致或过期则尝试显式 REJECT。

### 2. 控制器失联后如何防止旧选择继续使用？
**无法防止。** 控制器没有远程强制设备行为的能力：代理一旦被选中，设备会
一直用它，直到设备本地有人或机制改选。失联时控制器只能记录
`CONTROLLER_UNAVAILABLE` / `SELECTION_UNKNOWN`、拒绝从自己这边继续授权
生产使用，**不能**强制设备切到 REJECT。任何“失联自动回落”的说法都是假的。

### 3. 控制器故障时能否由设备本地可靠地执行 REJECT？
**UNPROVEN（未证明）。** 本任务内没有任何已验证的设备端机制（无设备端脚本、
无 Surge 端规则、无看门狗）能在控制器失效时可靠地把策略组切到 REJECT。
首位成员是 REJECT 只意味着“从未选过时默认 REJECT”，它不会覆盖已选中的代理。
因此 **fail-closed 未完成**，不得声称已完成。残余风险：控制器故障后，已选
代理可能继续服务，直到人工介入（`rollback_to_reject()`）或未来补上可验证的
设备端机制。真机验收必须单独验证这一点。

## Mock 与真机的界限

- `tests/mock_surge_api.py` 只模拟 HTTP 层面（select / get-select / groups，
  及超时、错误、错值、配置未加载）。它证明的是**控制器逻辑**在这些故障下的
  行为，不是真机行为。
- mock **不能**证明：真机重启后选择是否保留、真机 select 语义、控制器失联后
  真机是否回落、真实延迟与真实网络切换。以上必须在真机上单独验证。
- 测试全程不联网、不调真实 Surge、不碰生产配置。

## 运行

```bash
# 1. 静态检查 conf（真实解析，非肉眼）
cd fail-closed-select
python3 check_conf.py safe-egress-test.conf

# 2. 跑全部测试（unittest，mock 服务器，无真机）
cd ../tests
python3 -m unittest test_selector_controller test_selector_failures -v
```

测试日志保存在 `tests/logs/`。

## 尚未解决 / 需真机验证

1. 控制器失联自动 REJECT：**UNPROVEN**，见上文 Q3。
2. 真机上 select 持久化与重启行为尚未实测（mock 不能代替）。
3. 真机 Surge HTTP API 的实际 base URL / 鉴权方式尚未接入——控制器接受
   可注入的 `request_fn` / `base_url`，真机联调时替换传输层即可，逻辑不变。
4. 未提供设备端自动 REJECT 机制；如需补，需另立任务并在真机上证明。
