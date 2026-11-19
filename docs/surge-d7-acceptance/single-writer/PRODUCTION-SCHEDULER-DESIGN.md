# Issue #73 — 新节点池生成器与单写手定时发布器设计定稿（2026-11-19）

状态：**DESIGN APPROVED; IMPLEMENTATION PENDING VERIFIED LEGACY SOURCE**。本文件不是生产安装凭证。

## 0. 为什么当前禁止切换

现有 `single_writer.py` 保证双文件写入的锁/门禁/回滚，但不计算下一轮节点池；
`vps_publish_driver.py` 是隔离演练驱动，默认使用 `p2p3-gate-*` 假系统单元，
也不生成候选。VPS 尚无定时替代者。若现在禁用 `pool-publish.timer`、
`pool-sync.timer`，即使一个同字节发布成功，后续也只会冻结节点池。
**必须证明独立生成器 + 新定时服务的真实运行链才允许切生产。**

## 1. 权威数据源、职责分离

```text
pool-crawl.timer ────┐
pool-test.timer ─────┼─> 现有 pool.db [SQLite只读一致性快照]
pool-test-full.timer ┘                  │
                                         v
现有served + 21 pin + blocklist ──> 纯候选生成器 (无生产写入)
                                         │
                           验证候选+证据/版本/保护
                                         │
                           隔离候选文件+冻结manifest
                                         │
             单写手 publish() 取得 flock + 再查guard/STOP/旧写手
                                         │
                         原子写 staging + served 并读回
                                         │
                          独立快照/审计/可恢复
```

- 数据来自现用VPS `pool.db` 内 `nodes/sources/node_tests/pinned/blocklist` 的真实字段；
  在获得 `PRAGMA table_info` 与 `publish.py` 原版只读/筛选函数之前，
  **不得凭推断编写SQLite字段映射**。具体映射留待交付后接入。
- **唯一选择逻辑来源**：旧 `pool.cli publish` 中已有的候选算法（取针、保留、
  去重、补位）；必须迁移为不写DB、不写 `publish/pool-new.txt`、不改
  `.prev` 的 `build_candidate(snapshot, current, pins, blocked) -> bytes`。
  不允许在新进程里直接跑旧 `pool.cli publish` 再去读其文件。
- `pool-crawl.timer`、`pool-test.timer`、`pool-test-full.timer` 保留，
  因为三者只写数据库；新发布者独占双文件写入，**不再需要第二个sync写手**。
- `vps_publish_driver.py` 保持隔离测试用途；生产不得默认使用其模拟
  `p2p3-gate-*` 门禁或 `stop_check=lambda: False`。

## 2. 候选策略的硬约束

1. **21条 canonical pinned**，必须从数据库 pinned 减 blocklist 计算，
   去重得到21个名称、13条美国+8条香港。旧 snapshot `pinned-nodes.txt`
   25个物理行中另4个是 blocklisted，不能认成25个保护目标。
   21条钉选必须仍存在且其代理定义字节不被无证替换。
2. **失败 vs 慢**：只有与手机已加载字节、原生事件、网络类型一致的可信
   测速失败才可`exclude_from_active_selection`；连接成功 >=300ms
   仅`retest_high_latency`。不可用VPS数据冒充iPhone原生测速。
3. **F仍为UNCALIBRATED**：不能用shadow 0 verified当作0可用节点，
   不能自动删除或过滤目前池内现存非pin成员。真实可信新增判据未完成前，
   **保留现用候选字节并记录HOLD，不冒充已刷新**。
4. 21 pins缺一、来源字段/冻结SHA无效、STOP不明、候选重复、
   不可信缩池、完全空池、超出限定变化范围、未经审查的脚本出现时
   **必须拒绝写入，保持旧文件不变**。
5. 可信新增补位必须校验源数据库快照+唯一指纹+去重+阻止blocklist回流；
   限制单轮新增（初定最多4条，仅试运行阶段；正式阈值以真实数据证据确认），
   没有验证便不得把4条硬凑进生产。
6. 规则中不得发明DIRECT兜底；VPS不改变iPhone profile，
   用户当前FINAL选择`漏网之鱼→美国自动`仅证明当时在走代理，
   并非永久fail-closed保证。

## 3. 新发布定时与服务契约

建议**仅一组** `p2p3-single-publish.service` /
`p2p3-single-publish.timer`；`OnCalendar=*-*-* *:55:00`，
`Persistent=false`（重启不补一轮突发写入），
`RandomizedDelaySec=0`，`AccuracySec=1min`，任务超时后失败告警。
选择 :55 是为了等 crawl(:12) 和 incremental test(:42)，
并避开旧publish(:07)；正式启用前仍要确认真实测试任务结果时效。

单次运行应：
1. 读STOP状态（异常视为STOP），核对该次来源版本、21pin、blocklist、
   正在使用的served+staging完整SHA与一致性；
2. 用只读SQLite snapshot+经过单测的纯函数生成候选到**受限隔离临时目录**；
3. 对候选做`candidate-freeze`+结构/数量/钉选/证据/变化审查；
   如没有安全有效新候选，输出`HOLD_NO_TRUSTED_CHANGES`，不得以空数据
   覆盖生产；
4. 持锁调用`single_writer.publish`，其内核flock、STOP、
   旧写手guard、masked-ban、当前served SHA二次检查、
   双文件原子写与失败恢复必须保持开启；
5. 写后核对双SHA/行数/钉选完整性、对外HTTP读回SHA（若可访问）、
   调度状态、日志去敏回执；错误时从独立快照恢复双文件及units，
   不能依赖只有一版的`.prev`。

旧两条写单元必须先停止/disable并排空，其service mask后，
新生产门禁`single_writer.py check`必须返回**0**才允许切换；
三个DB-only timer、surge-bridge、probe-service均不动。
**不是先关旧定时器再慢慢写新生成器。**

## 4. 发布阶段与硬门禁

| 阶段 | 条件 | 可执行 |
| --- | --- | --- |
| D1 源映射 | 真实旧候选算法及DB schema已审查，不含生产URI和凭据 | 可编写纯生成器 |
| D2 单测 | pin/blocklist/空池/版本竞态/过期证据/新旧输出一致性 PASS | 可进隔离集成 |
| D3 VPS隔离 | 真SQLite只读快照，临时双文件，真实systemd计时和并发/恢复验证 | 可申请实际切换 |
| D4 现网只读预检 | 新发布定时单元**已安装但未启用**、来源生成可定时完成、独立新鲜备份、21pin、STOP、防DIRECT观察 | 可开始停旧写手 |
| D5 单写手生产 | 旧写服务禁启证明、正向guard=0、首次同字节发布、HTTP SHA与双文件一致、下一轮真实生产候选机制正常 | 正式切换完成 |

机主已经授权**满足全部门禁后的受控切换**。未达D4，不许碰旧写手。
即使达到D5，自动**永久删除节点仍为OFF**，F不可伪标CALIBRATED。

## 5. Muse只读依赖

- 精确旧Python源：`pool.cli publish` 中只读访问、选择、排序、保存候选的
  函数及调用边界；涉及节点凭据的实际数据不可公开。
- `PRAGMA table_info`：只交结构与索引，不交节点记录本身；
  pin/blocklist如何判定，以及冻结源版本（SQLite snapshot/时间/sha）。
- 系统Python版本，实际运行账户、DB路径、旧发布配置数值，
  `single_writer._db_connect`和真实表名是否存在碰撞。
- 完整源的去敏校验、再现46行旧算法结果的本地只读/隔离样例，
  便于把迁移后算法与原算法作字节/成员对照。

**现阶段真实状态**：`CUTOVER_BLOCKED`，现网旧5个timer保持原状。
