# 设备端独立安全门禁（P0-E）

控制器失联后，设备上的受保护新请求不得继续通过旧代理授权——
这个保证不能由控制器实现（第一轮已证：控制器没有远程强制设备
行为的能力），只能由设备本地的逐请求门禁实现。本目录就是该门禁。

## 一句话设计

```
请求 → SCRIPT 规则（gate-script.js，逐请求查本地租约）
        租约全项通过 → 放行到已验证的具体代理（测试安全出口组当前选中项）
        任何一项不通过 → 不匹配 → 落到 FINAL,REJECT
```

门禁不依赖控制器在线、不依赖定时任务准时触发、不依赖
select 组首位 REJECT（那只是“从未选过”的默认值）。控制器只负责
签发／续租／吊销租约（`gate-controller.py`），租约过期后设备本地
即拒绝，与控制器是否失联无关。

## 文件

| 文件 | 说明 |
|---|---|
| `gate-script.js` | RULE 脚本：逐请求租约判断＋过期检查＋默认 REJECT（ES5，JavaScriptCore） |
| `gate-events.js` | EVENT 脚本：engine-started／network-changed／profile-reloaded 时吊销租约并强制 REJECT |
| `gate-sweep.js` | CRON 脚本（每 10 分钟）：过期租约清理＋无租约时代理选中时强制 REJECT，仅作备份 |
| `device-gate-test.conf` | 纯隔离测试 profile：SCRIPT 门禁＋测试节点＋FINAL,REJECT，无真实节点／生产订阅 |
| `gate-controller.py` | 租约签发／续租／吊销＋状态机（新增 LEASE_EXPIRED、GATE_SCRIPT_MISSING 等） |
| `check_gate_conf.py` | conf 静态审计：SCRIPT 首位、FINAL,REJECT、无 DIRECT、无旁路规则 |
| `README.md` | 本文件 |

测试在 `../tests/`：`mock_surge_runtime.js`（Node vm 模拟 Surge 脚本
运行时，跑**真实** gate JS）、`mock_gate_api.py`（模拟 Surge HTTP API，
evaluate 端点真实执行控制器下发的脚本）、`test_device_gate.py`、
`test_device_gate_failures.py`。

## 租约（lease）

`$persistentStore` 中 `device-gate-lease-v1` 键下一段 JSON 字符串：

```json
{"v":1, "proxy":"Test-Proxy-1", "candidate_sha":"0543b83d…",
 "issued_at":1700000000, "expires_at":1700000600, "ttl_seconds":600,
 "net_fp":"fnv1a-…", "boot_id":"boot-1700000000-…", "stopped":false}
```

- `ttl_seconds` 默认 600（10 分钟）；控制器健康时每 ~300 秒续租一次。
- `net_fp`：设备端签发脚本实时计算的 `$network` 指纹（SSID/BSSID、
  v4 地址／接口／路由、DNS、蜂窝运营商／制式）；网络变化即失效。
- `boot_id`：每次 `engine-started` 由事件脚本新铸并写入
  `device-gate-boot-v1`；租约必须绑定当前 boot，重启后旧租约不被信任。
- 租约不含任何密码／token／URI／真实 IP。

## 逐请求判定（gate-script.js `decide()`）

以下任一成立即 `matched:false` → `FINAL,REJECT`：

1. 无租约／租约 JSON 损坏／版本号不是 1；
2. 代理不在允许名单（Test-Proxy-1/2/3）；
3. `candidate_sha` 与预期 SHA（`0543b83d…`，三测试节点名排序后 SHA-256）不符；
4. `stopped === true`；
5. 时间字段缺失／`ttl_seconds` 超出 (0, 3600]／`expires_at - issued_at !== ttl_seconds`；
6. 时钟异常：`now < issued_at - 60s`（时钟被拨回至签发前），或
   `now < last_seen - 60s`（时钟被拨回至上次放行之前；`last_seen` 由脚本
   每次放行时尽力写入 `$persistentStore`）；
7. 已过期：`now > expires_at`（时钟被拨快也只会导向过期，同样拒绝）；
8. 网络指纹与当前 `$network` 不符；
9. `boot_id` 与当前存储的 boot 不符（或缺失）；
10. select 组**当前选中项**不是租约代理（未知选中项也拒绝）；
11. 脚本内任何异常（显式 `try/catch` 后仍答 `matched:false`）。

放行时只做一件事：把 `now` 写入 last-seen 守卫（尽力而为，写失败
不改变本次 verdict）。热路径无 `$httpClient`／`$httpAPI` 调用，
控制器或网络死亡不影响 verdict；也不调用
`$surge.setSelectGroupPolicy()`（换组是事件／cron 脚本的事）。

## 事件与扫除

- `engine-started`：铸新 boot id、删租约、删 last-seen、强制组选 REJECT。
  重启后流量保持 REJECT，直到控制器重新签发绑定新 boot 的租约。
- `network-changed`／`profile-reloaded`：删租约、删 last-seen、强制 REJECT。
  （boot 不变；新租约须重签。）
- `manually` 或未知事件：只记 logbook，不动状态。
- cron sweep（`*/10 * * * *`，每小时 6 次，低于手册 10 次／小时的
  电池警告阈值）：租约损坏／STOP／过期／TTL 异常 → 删租约并强制 REJECT；
  无租约但组当前选了代理 → 强制 REJECT；租约未过期 → 不动。
  sweep 只是备份：即使某次触发被系统挂起而错过，下一条请求的规则
  脚本仍会拒绝过期租约。

## 控制器（gate-controller.py）

签发流程（任一步失败即拒绝签发，不报 active）：

1. STOP 标志存在 → 拒绝并尝试吊销，记 `STOPPED`；
2. `GET /v1/features/scripting` 确认脚本功能开启，否则 `SCRIPTING_DISABLED`；
3. `GET /v1/scripting` 确认 5 个门禁脚本都在设备上，否则 `GATE_SCRIPT_MISSING`；
4. `GET /v1/policy_groups` 确认测试组已加载且成员恰为 REJECT＋三测试节点；
5. 候选校验（重名／未映射／SHA／TEST-NET 内地址／延迟 <300ms／证据 <24h），
   与第一轮同一规则；
6. `POST /v1/policy_groups/select` 选最优健康代理＋`GET` 回读验证；
7. `POST /v1/scripting/evaluate` 下发签发脚本（设备端绑定 `net_fp`＋`boot_id`
   后写入 `$persistentStore`）；
8. 再次 `POST /v1/scripting/evaluate` 读回租约，逐字段比对（代理／SHA／
   时间／TTL／指纹非空／boot 非空／未过期）＋重读当前选中项——
   **全部吻合才记 `LEASE_ACTIVE`（verified）**；evaluate 只回 200 而无
   回显时记 `LEASE_ISSUED_UNVERIFIED`，绝不记 active。

状态机：`NO_LEASE`、`LEASE_ISSUED`、`LEASE_ISSUED_UNVERIFIED`、
`LEASE_ACTIVE`、`LEASE_EXPIRED`、`LEASE_REVOKED`、`GATE_SCRIPT_MISSING`、
`SCRIPTING_DISABLED`、`GATE_UNKNOWN`、`CONTROLLER_UNAVAILABLE`、`STOPPED`。
状态文件原子写（tmp＋fsync＋rename）；加载即标记未验证，任何生命周期
入口都重新读设备，不信任历史记录。吊销（`revoke_lease`）同样只认
REJECT 回读，否则记 `GATE_UNKNOWN`。

## 官方文档依据（2026-11-18 实读 manual.nssurge.com）

| 行为 | 官方原文（意译，见下链接） | 本设计的使用 |
|---|---|---|
| SCRIPT 规则只返回 matched | “The script must finish by calling `$done()` with an object containing a `matched` boolean.” | 门禁只答放行／不放行 |
| 脚本缺失／禁用即不匹配 | “If the script is missing or scripting is disabled, the rule is treated as not matched.” | 缺失／禁用 → 落到 FINAL,REJECT |
| 引用不存在的脚本则校验失败 | “Profile verification fails if a SCRIPT rule references a script name that does not exist.” | conf 审计要求脚本齐全 |
| 未捕获异常即无效果 | “An uncaught exception aborts the session and the script has no effect.” | 脚本内显式 catch 后答 false，不依赖该行为 |
| `$persistentStore` 永久字符串存储 | “Simple persistent key-value storage… Saves data permanently. Only a string is allowed… Passing `null` as the data deletes the entry.” | 租约／boot／last-seen 的存取与吊销删除 |
| `$surge.selectGroupDetails()` | “Returns an object describing all select groups: `{groups: …, decisions: {groupName: selectedPolicy}}`.” | 规则脚本核对当前选中项 |
| `$surge.setSelectGroupPolicy()` | “Changes the selected policy of a select policy group. … All setters return a Boolean indicating success.” | 事件／cron 脚本强制 REJECT |
| `$network` 字段 | “`wifi` (`ssid`, `bssid`), `v4` (`primaryAddress`, `primaryInterface`, `primaryRouter`), `v6` …, `dns` …, on iOS `cellular-data` (`carrier`, `radio`)” | 租约网络指纹 |
| `$script.startTime` | “The time when the current run started, as UNIX epoch seconds.” | 租约过期判断的 `now` |
| `engine-started` | “Triggered once after the Surge engine finishes starting, when the Network Extension and the active profile are fully initialized, so `$network` is ready to read. … iOS 5.22.0+ Mac 6.9.0+” | 重启吊销＋铸新 boot |
| `profile-reloaded` | “Triggered after the active profile is reloaded at runtime. The initial profile load at engine startup does not count as a reload; hook `engine-started` for that. … iOS 5.22.0+ Mac 6.9.0+” | 配置重载吊销 |
| `network-changed` | “Triggered when the system network changes.” | 网络变化吊销 |
| cron 与电池阈值 | “A cron script that fires more than 10 times per hour triggers a battery consumption warning.”；cron 可调组：“`$surge.setSelectGroupPolicy('Group', 'Proxy');`” | sweep 每 10 分钟 |
| cron 可能错过触发 | “Without [wake-system], a fire time may be missed while the app is suspended by the system.” | sweep 只作备份，不作保证 |
| `POST /v1/scripting/evaluate` | “Evaluate a script with a mock environment. `script_text` is required; `mock_type` is a script type string such as `http-request` or `cron` (default: cron). The `$trigger` global is set to `http-api` during evaluation.” | 控制器下发签发／读回／吊销脚本 |
| 规则按序匹配、FINAL 兜底 | “Rules are evaluated strictly from top to bottom. The first rule that matches decides the policy… The rule list must end with an enabled FINAL rule.” | SCRIPT 首位＋FINAL,REJECT |

来源（实读页面）：

- https://manual.nssurge.com/scripting/rule.html
- https://manual.nssurge.com/scripting/api.html
- https://manual.nssurge.com/scripting/event.html
- https://manual.nssurge.com/scripting/cron.html
- https://manual.nssurge.com/tools/http-api.html
- https://manual.nssurge.com/rules/overview.html

## 已知界限（诚实结论）

### 回执：[DEVICE_LOCAL_FAIL_CLOSED] = UNPROVEN

逻辑层（mock 中真实 JS＋真实控制器流程）全部通过，但以下真机行为
**未实测**，因此不能声称设备端 fail-closed 已完成，生产继续 NO-GO：

1. **规则热路径能否调用 `$surge.selectGroupDetails()`**：手册称 `$surge`
   是“注入每个脚本”的全局量，但未写明规则脚本热路径可同步调用。
   若真机上该调用抛错／不可用，本脚本会拒绝一切（安全但不可用），
   须真机验证后才知。
2. **`POST /v1/scripting/evaluate` 的“mock environment”是否写得进真实
   `$persistentStore`**：手册明言 evaluate 是 mock 环境。签发脚本在真机
   上可能写不进真实 store，或写进一份隔离的 mock store——那样租约
   永远发不下去（拒绝一切，安全但不可用）。控制器对此的检测是：
   无回显即记 `LEASE_ISSUED_UNVERIFIED`，不报 active。
3. **evaluate 响应是否回显 `$done()` 值**：手册未写响应体结构。若真机
   不回显，控制器永远只能记 `LEASE_ISSUED_UNVERIFIED`（同样安全，
   但 active 永远得不到控制器侧确认；设备侧门禁本身不受影响）。
4. **`engine-started` 与首条请求的竞态**：手册未规定事件脚本与引擎启动后
   首条规则求值之间的顺序。重启后、事件脚本执行前到达的请求，仍可能
   看到旧租约＋旧 boot（两者都持久化）。残余窗口以租约 TTL（600 秒）
   为上限；`engine-started` 要求 Surge iOS 5.22.0+，更老的版本上该事件
   根本不触发，只剩 TTL 兜底。
5. **时钟拨回的残余窗口**：时钟拨回至 `[issued_at, last_seen]` 区间内、
   且拨回前没有任何一次放行写入过 `last_seen` 时，租约可被多用至多
   一个 TTL（已用 `issued_at` 下限＋`last_seen` 单调守卫双重收窄，
   无法彻底消除——设备没有单调时钟源暴露给脚本）。
6. **全局模式旁路**：出站模式切到 `global-proxy` 时规则不被求值，门禁
   不适用。这是 Surge 的产品语义，profile 无法强制模式；真机验收须
   确认模式保持 `rule`。
7. **用户／其他配置旁路**：门禁只在 `device-gate-test.conf` 结构内成立
   （SCRIPT 首位、唯一非 FINAL 规则、FINAL,REJECT、无 DIRECT、无其他
   策略组）。任何在 SCRIPT 之前匹配受保护流量的规则、任何新增的
   DIRECT／其他出口，都会绕过门禁。`check_gate_conf.py` 只审计本测试
   profile，不审计日用配置。
8. **选中代理本身失效**：规则脚本只核对“选中项＝租约代理”，不测速。
   代理失效时请求仍会尝试走该代理（失败即连接失败），绝不会转为 DIRECT；
   但“失效即拒绝”需要该代理先被控制器移出候选并吊销租约，控制器失联
   期间做不到——残余风险与第一轮相同，只是范围被租约 TTL 封顶。

### 已由 mock 证明的（非真机证明）

- 租约 17 种失效组合全部拒绝（无租约／过期／STOP／SHA 不符／网络变化／
  boot 不符／选中项不符／时钟拨回两类／损坏 JSON／TTL 不一致／版本错／
  代理不在名单／选中项未知），有效租约放行且更新 last-seen。
- 三事件均吊销租约并强制 REJECT；`engine-started` 铸新 boot，旧租约
  在新 boot 下拒绝；手动触发不动状态。
- cron sweep：过期／损坏租约删除并强制 REJECT；无租约时代理选中时强制
  REJECT；有效租约不动。
- 控制器：无回显不报 active；脚本缺失／脚本功能关闭／SHA 不符／STOP
  时不签发、不选代理；超时／500／POST 被忽略／GET 撒谎时不报 active；
  吊销只认 REJECT 回读；伪造的 LEASE_ACTIVE 状态文件在重启核验时坍缩；
  4 线程并发签发串行化且全部 active；全程无 DIRECT 被选中。
- conf 审计：9 类变异（DIRECT、FINAL 被改、旁路规则、SCRIPT 非首位、
  缺事件、cron 过频、非 TEST-NET 地址、错误密码、组首位非 REJECT）
  全部被拦截。

## 运行测试

```bash
# 静态审计测试 profile（真实解析）
python3 device-gate/check_gate_conf.py device-gate/device-gate-test.conf

# 全部自动化测试（unittest；Node mock 跑真实 JS；无真机、无联网）
cd tests
python3 -m unittest test_device_gate test_device_gate_failures -v
```

测试日志见 `tests/logs/device-gate-run-20261118.log`。

## 仅测试用，不可直接用于生产（P1，GPT 复核 2026-11-18）

本 profile 与控制器是隔离测试工具，以下两点决定了它们不能直接
用于生产；生产化须先解决这两项。

1. **脚本 URL 是临时的，会过期。** `device-gate-test.conf` 的
   `[Script]` 五条 `script-path` 目前是 remote-storage 公共直链
   （`https://muse.ai/files/...`），**2026-11-20T14:03 UTC 过期**。
   过期后若需重新导入 profile，须先重新托管脚本再更新链接。
   永久托管路径：极空间桥 `/m/`（`/opt/surge-bridge/modules/`，
   经 `sgcmd.vip668.xin` 访问）——该路径在 2026-11-18 因 VPS SSH
   密钥登录失败未能实施，待 SSH 恢复后把三个 JS 传到桥上并把
   conf 里的 URL 改为桥地址；在此之前，重新导入一律先重传换链，
   不得把过期链接当作可用状态。
2. **测试 HTTP API 用公开密钥监听局域网。** conf 里
   `http-api = test123@0.0.0.0:6171`：密钥 `test123` 是公开的测试
   值，且监听全部接口（0.0.0.0）以便局域网内的台式控制器访问。
   这是测试专用设计，**绝不能出现在生产配置里**：生产配置不得
   开启 `http-api`，不得用已知密钥监听局域网；控制器与签发流程
   仅用于本隔离测试 profile，不得用于日用配置。

## 真机验证（下一步，须机主操作的最短指令）

在隔离测试 profile 上逐项验证（不要动日用配置与生产池）：

1. 手机 Surge 导入 `device-gate-test.conf`（`[Script]` 五条
   `script-path` 为 remote-storage 直链，见上一节；相对路径放
   profile 同目录的方式已证实加载不到——2026-11-18 引擎日志
   `Failed to load external resource: gate-events.js 资源不存在`），
   确认出站模式为 **rule**，加载该 profile。
2. 不签发租约时打开 `example.com`：应失败／被拒绝（FINAL,REJECT 生效）。
3. 在电脑上对手机 HTTP API（`http://127.0.0.1:6171`，key `test123`，
   须与手机同一网络／USB 映射，见控制器用法）跑一次
   `gate-controller.py` 签发，确认 `LEASE_ACTIVE`；再打开 `example.com`，
   应经测试代理出去。
4. 关掉控制器／断开电脑，等 10 分钟（租约过期）后再打开 `example.com`：
   应再次被拒绝——这是“失联后自动拒绝”的关键证据。
5. 重启手机（不重签租约）后打开 `example.com`：应被拒绝（重启不信任
   历史授权）；查看 Surge Logbook 应有 `gate: engine-started` 与
   `revoke lease` 记录。
6. 切换 Wi-Fi／蜂窝后打开 `example.com`：应被拒绝（网络变化吊销），
   直至重签租约。
7. 在 Surge 里停用 `gate-rule` 脚本后打开 `example.com`：应被拒绝
   （脚本缺失／禁用即不匹配 → FINAL,REJECT）。
8. 把以上每步的实际结果（成功／失败＋截图／Logbook 行）回传，
   只有 2–7 步全部符合预期，才能把回执从 UNPROVEN 改为 PASS。

## 安全约束遵守情况

- 未改生产 Surge 配置、未停生产 timer、未删节点、未动 blocklist／STOP／
  21 钉选（本任务只写本仓库内新文件；生产池路径在本沙盒内不存在，
  无法从本机复核生产池 SHA——见“生产池 SHA”一节）。
- 代码与测试夹具只用 `192.0.2.0/24`＋`test123`，无真实节点 URI／密码／
  token／真实出口 IP；控制器日志经脱敏（密码／token／URI 键一律打码）。

## 生产池 SHA

本沙盒内 `/opt/surge-bridge/modules/pool-new.txt` 与
`/opt/free-node-program/publish/pool-new.txt` 均不存在（上一轮记录的
生产池 SHA 为 `606dcfca229e26c0ac83882085f957be40e43cc0b0904d8388cb34398c51247a`，
30 行），本任务未对生产做任何写操作（无 SSH、无订阅写入、无 timer 操作），
仅在仓库内新增文件。生产池 SHA 的“开发后复核”须在能访问上述路径的
环境重做，本报告不代为声称。
