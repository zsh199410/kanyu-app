# Issue #73 · C轮受控桥接部署门禁（GPT-6裁决，2026-11-19）

状态：**A/B isolation verified / C code & mocks implemented / C live deployment NOT STARTED**。

依据：Issue #73 [#7004322797](https://github.com/zsh199410/kanyu-app/issues/73#issuecomment-7004322797)
真实VPS摘要，A轮29/29、B轮独立私服32/32。
本仓库Draft PR #96不是私有server.py或手机bridge.js的可直接覆盖文件。

## 0. 问题判定与权限边界

- 旧bridge.js存last_id早于发/result，单次网络中断可导致永久忽略待处理命令。
- **ID已持久化≠操作完成，连接超时≠没有保存。**
- 当前单槽cmd id **1795063030**、手机动作结果**OUTCOME_UNKNOWN**。
- 不重置last_id、不重放1795063030、不清/覆盖cmd、
  不更新手机代理策略、STOP或Surge节点池；旧5timer继续运行。
- VPS近期state.json、server.py、bridge.js、bridge.sgmodule备份
  0700，Muse报告线上与备份SHA相同。部署前**再次**冻结执行时字节和元数据。
- 原切换授权不被用来跳过此次桥接更新的额外回归与回滚门禁。
  C轮在私有环境完成后，只有通过以下条件才可执行最小增量部署；
  未通过必须保留旧服务并报告 BLOCKED，不用重复要求机主手工测速。

## 1. F2修复：明确5xx，不能伪报ACK

新增 `server_http_commit.py` 仅是**经过鉴权、全局锁之内的HTTP
handler适配代码**。它在调用原子保存`persist(next_state)`
成功之前绝不返回200；保存例外时返回：

```json
{"ok":false,"accepted":false,"error":"durable_commit_failed","commit_state":"unknown"}
```

HTTP应为 **503**、`Content-Type: application/json`、
`Cache-Control: no-store`，不在响应里回显私有文件路径或异常内容。

**503不证明写盘没有发生。** 原子替换可能已完成但异常或网络故障
发生在持久化确认之后；客户端一律不重新执行action。
若先前已缓存`result_ready`，只能同字节重复发送结果并要求
`accepted:true + acked_id=<id>`，或调用已鉴权的只读`/receipt`。
旧`/result`匹配则200；不匹配409，不能篡改cmd/result；
旧格式`{id,at,outputs}`仍必须兼容。

若 `persist`在成功返回之前没有真正fsync/原子提交保证，
不要将同步函数返回当成durable，须审计原版写盘实现。
**实际write失败仍可能触发TCP reset而无法交付503**；
只要连接可用，明确5xx优于静默断开，但不能保证客户端一定收到。

## 2. C0 · 先审核私有真实集成，不动生产

Muse在受信VPS**隔离副本**把PR96三个server模块接入真实server.py，
逐路由检查：
- 原 X-Dev-Token 用于`/poll`、`/result`、`/diagnostic`、
  `/receipt`；X-Admin-Token用于`/issue`和`/status`。
  任意未授权请求必须是403，严禁私有令牌进GitHub或明文日志。
- 原处理线程全局锁保持覆盖**读取state→纯转移→持久化→HTTP响应**
  全过程。不得在持锁外计算出待保存状态后与另一个请求竞争。
- `/result`匹配200/持久化、错ID409/不写，重复同payload200且
  无新写，保存失败可收503；`/diagnostic`只记录有界last_id与
  枚举代码而**绝不改cmd/result**，持久化失败503；
  `/receipt` 只读且返回是否收到**指定ID**，不泄露输出正文。
- `/issue`有未确认cmd时409，拒绝覆盖当前单槽；
  私有旧CLI/admin写命令的副作用必须经过验证。
- 20并发重复result与10并发issue完整重跑，断网/丢ACK/重启/存储
  故障全部重跑。所有测试仅使用隔离状态与模拟令牌，
  不连接现网端口或真实手机。
- 同时验证**当前线上旧脚本仍可使用新服务器**，它在原来收到
  200 {ok:true}的路径上仍正常工作。当前旧命令不能借兼容测试重新执行。
- 此轮提交脱敏状态码/数量/SHA/差异，严禁贴真实state.json或脚本原文。

C0全绿后，进入C1。若C0任何失败，**不改生产服务/手机**。

## 3. C1 · 最小可回滚服务器部署（不变手机）

只允许对已测试的私有server.py做小范围路由更新；
**不得整体换成PR96的纯模块**，不得替换state.json。
正确流程：
1. 再次备份当前server.py、state.json、bridge.js、sgmodule及权限，
   记录确切pending ID、旧result时间与SHA；旧服务保持运行。
2. 使用测试通过的私有集成文件做语法检查、权限校验；
   准备经测试的服务进程滚动重启/恢复脚本和**当前状态文件只读副本**。
3. 在一次受控窗口替换server.py并重启**仅**surge-bridge服务，
   监测端口、GET /poll既有行为、/s/脚本字节SHA完全不变。
   不删除、清空或自动恢复旧state。回退**程序代码**时优先保留
   最新有效state文件，防止“恢复旧state”令已完成命令再次待执行。
4. 验证未授权403、合法旧GET /poll200且**仍返回原cmd**，
   /diagnostic在受信隔离ID测试或客户端诊断时不会清cmd，
   /receipt只读，**不通过生产/result去模拟匹配旧cmd**
   （会把OUTCOME_UNKNOWN清掉！）。
5. 写入故障5xx测试只允许隔离环境注入；禁止在生产state.json
   上用chmod/删除/模拟磁盘故障。生产回执提供PID、服务状态、
   pending ID、last result ID、脚本SHA及旧node pool SHA不变。

**C1部署不是“桥已修复”**：尚未拿到真实phone last_id，也未证明新脚本加载。
若服务异常，恢复备份server.py及服务状态，保存**最新**state快照供
取证；不得盲目把旧state.json覆盖回去。

## 4. C2 · 首次手机诊断-only（不能执行任何待处理动作）

新增`surge_diagnostic_canary.template.js` 是**单独脚本模板**：
它只读已有 `$persistentStore.read(existing_key)`，
`GET /poll`，再`POST /diagnostic`，不使用`$httpAPI`、
不访问`/result`、不调用任何cmd.actions，
不读写新的持久ledger、不改旧last_id。
脚本遵循Surge官方`$httpClient.get/post`、`$done()`用法。
**不能直接部署公开占位符**；Muse必须从现有私有脚本中
核对精确store key、真实受信HTTPS入口、X-Dev-Token后，
只在其可信私有副本填入配置。不在公开Issue贴凭据/URL。
若key不存在、数据不是安全数字，报告INVALID，不伪称已执行。

**强制顺序**：
1. C1的服务器已支持有鉴权`/diagnostic`且隔离测试通过。
2. 仅在受信独立脚本路径放置诊断-only脚本，
   **不要覆盖已有PR85 bridge.js、不要替换其cron脚本路径**。
3. 验证iPhone实际已**下载此诊断脚本的精确SHA和字节长度**；
   原旧脚本的`/poll`200不能冒充新版脚本生效。
   若没有可用的远程脚本调度/下载触发通道，
   标记`C2_WAITING_FOR_DEVICE_TRIGGER`，不得凭猜测宣布执行。
4. 单次触发后在服务器看`/diagnostic`的200/脱敏
   `legacy_last_id`与当前cmd id，记录服务端前后cmd/result字节摘要一致、
   旧手机存储没有写入、`/result`没有新的POST、没有任何Surge
   API/策略/测速变更；失败时立即停止诊断脚本，但不清队列。
5. 若`last_id >=1795063030`：标为
   `LEGACY_CHECKPOINTED_OUTCOME_UNKNOWN`，
   **不可擅自判定已经执行成功**。
   若`last_id <1795063030`：标为
   `CLIENT_EXECUTION_PATH_UNCONFIRMED`，
   **不可擅自判定抛错**。如果INVALID则持续UNKNOWN。
   三种结果都保留原命令，不重试。
6. 后续必须以受信人工或服务端可核验记录**对账并归档旧命令**，
   单独获得清理单槽的审计方案后，才能发更大、唯一ID的新
   GET-only金丝雀。不能把旧命令“结果未知”直接当成删除许可。

## 5. C2成功 ≠ D5开闸

桥恢复后再用**新命令ID、真实当前时间的GET-only**
取回`/v1/outbound`、规则、当前profile和手动选择值，
并核实当前代理组无静默DIRECT路径。
不得仅凭历史“漏网之鱼→美国自动”就声称永不DIRECT。

然后按PR#93原门禁：最新现场备份、21pins、旧timer
负例→停旧两写service→正向guard=0→首次同字节发布→
新的安全新增链路与真实定时触发→读回/回滚。
**桥修复与节点池切换是两个不同变更，不得捆绑上线**。

### C轮验收字段（只贴脱敏摘要）

`PR96_HEAD` / `C0_SIM=PASS|FAIL` / `F2_503=PASS|FAIL` /
`C1_BACKUP_SHA` / `C1_SERVER_ROUTES=PASS|FAIL` /
`C1_STATUS` / `PHONE_DIAGNOSTIC_SCRIPT_SHA` /
`C2_DOWNLOAD_SEEN` / `DEVICE_LAST_ID_RELATION` /
`ORIGINAL_PENDING_CMD_UNCHANGED` / `RESULT_SLOT_UNCHANGED` /
`LEGACY_SCRIPT_SHA_UNCHANGED` / `LIVE_SURGE_RULES_UNCHANGED` /
`LEGACY_5_TIMER_STATE_UNCHANGED` / `ROLLBACK_PATH_VALIDATED`.

**GO范围：C0实际代码整合与C1准备可以启动；只有真实C0和
安全备份/回滚/鉴权门禁通过后，才可进行受控C1最小部署。
C2仅诊断-only；任何不满足立即C_BLOCKED。**
