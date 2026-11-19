# Issue #73 · D4 正式切换准备与验收（2026-11-19）

状态：**D3 VPS ISOLATION PASS**；**D4 LIVE PREP / D5 CUTOVER NOT YET EXECUTED**。
机主已经授权**在真实技术门禁全部通过时**完成生产单写手切换。
本文件**不是自动切换脚本**，在最终D4回执前不得关旧timer、启动新生产writer。

## 已接收的实机事实

- Muse在#73回执 `7001942664`：精确HEAD `7c7f36a3` 的 `--inspect-only`、
  `--preview`成功；当次45行、21pin、served+staging SHA一致，
  legacy`load_yaml_simple(path)`无新pip依赖；
  真systemd隔离36/36通过；只读账本计划得到24条轮换、24条历史。
- GitHub新D4快照代码/测试应在将来新HEAD的CI过后再导入VPS。
  本文不把旧45行SHA当作未来切换固定值。
- 当前 `AUTO_DELETE=OFF`、winner-clean过窗只用合成样本验证，
  当前池中的非pin节点不能自动按VPS或未经校准的手机结果删除。

## D4-A：当前只读状态 + 独立备份（不停止旧服务）

**先确认实际代码HEAD和路径，不可复制历史SHA。**
在可信VPS隔离工作目录用真实的venv执行：

```bash
cd /opt/p2p3-shadow/pr93-audit/generator/docs/surge-d7-acceptance
git rev-parse HEAD
/opt/free-node-program/venv/bin/python single-writer/production_cycle.py --inspect-only
/opt/free-node-program/venv/bin/python single-writer/production_cycle.py --preview
sh single-writer/systemd/install-disabled.sh --dry-run
```

第一行若不是本轮审定的精确HEAD，停止后核对代码差异再继续。
两项检查必须退出0、21pin、现网served与staging SHA相同；
在旧发布器约:07写staging、:15同步served的窗口中可能正常临时不一致，
此时应等稳定窗口重查，不许直接覆盖或停旧任务。
`--preview`只读取DB和远端源，不调用旧`pool.cli publish`。

准备由root持有、不可被现用旧publisher覆盖的私有备份目录，
**仅创建备份目录，不触碰生产发布器**：

```bash
install -d -o root -g root -m 0700 /opt/p2p3-cutover-backups
/opt/free-node-program/venv/bin/python single-writer/d4_snapshot.py --check \
  --served /opt/surge-bridge/modules/pool-new.txt \
  --staging /opt/free-node-program/publish/pool-new.txt
/opt/free-node-program/venv/bin/python single-writer/d4_snapshot.py --capture \
  --served /opt/surge-bridge/modules/pool-new.txt \
  --staging /opt/free-node-program/publish/pool-new.txt \
  --db /opt/free-node-program/data/pool.db \
  --backup-root /opt/p2p3-cutover-backups
```

程序保存独立served/staging原始字节、一个SQLite只读一致性备份、
7个systemd旧unit状态和manifest哈希；源端只读、快照为唯一
时间戳+随机目录，私有只读权限。**备份后立刻运行**：

```bash
/opt/free-node-program/venv/bin/python single-writer/d4_snapshot.py --verify \
  /opt/p2p3-cutover-backups/<本轮实际生成的d4-目录名>
```

`--verify`会在**临时目录**故意破坏并恢复模拟served/staging，
验证字节及DB备份SHA；**不会重启生产unit、不会覆盖生产文件**。
这并非实机生产回滚已完成，unit恢复只能依据manifest在实际回滚时进行。
不可把文件内容、代理URI、节点IP、密码、完整订阅URL贴在GitHub。
私有备份目录离线复制一份到受信位置更保险。

## D4-B：新写手安装前门禁

请Muse只读填充下列证据，不允许“推测通过”：

1. **STOP策略**：当前旧服务没有新`RUNNING`状态文件；为新发布者指定
   `P2P3_STOP_STATE_FILE`的**专用私有绝对路径**，支持精确`RUNNING`和
   `STOP`，文件缺失/未知即拒绝，且继续尊重served目录里的旧`STOP`文件。
   在隔离目录完整注入`RUNNING`/STOP/缺失三种情况，验证fail-closed。
   生产文件的显式初始化应等D4审查通过后执行。
2. **当前防DIRECT**：手机此前报告 `FINAL→漏网之鱼→美国自动`（选择代理
   非DIRECT），这是当时实际选择的证据，不等于永久fail-closed。
   在交接时以现有受信只读通路复核实际出站模式、FINAL和手动组
   选择值。若桥仍无法回读live配置，应明确列出
   `ANTI_DIRECT_LIVE=UNKNOWN`并阻断，不以11月15日副本冒充live。
   **不得修改iPhone分流规则。**
3. **新服务目录**：核对`/opt/p2p3-single-writer`中的
   `single-writer/production_cycle.py`、`single_writer.py`、
   `legacy-writer-guard.py`可从其预期位置加载，
   `/opt/free-node-program/venv/bin/python`存在且能从旧root读pure源码。
   如有路径差异，先更改/测试模板，不以软链接绕过源码证明。
4. **独立数据库与锁**：新writer DB和flock路径有root写权限；
   旧pool.db始终只读；`ProtectSystem=strict`、
   `ReadWritePaths`不允许放宽为根文件系统。
5. **源码证明**：记录旧pool包**全部**`*.py`文件集合和哈希，
   配置`P2P3_LEGACY_SOURCE_SHA256`与本轮文件逐字节相符；
   此校验在运行任何旧回调前执行。哈希文件本身不能代表已通过业务测试。
6. **周期更新能力**：新timer目标每小时:55。验证10个来源获取、
   候选产生、最多4个可信VPS新增、不删旧节点、无候选时安全HOLD。
   **只设置`SAME_BYTES_ONLY`会在需要新增时HOLD而不是继续动态更新**：
   所以D5之前必须明确安全新增开关何时启用、是否具备足够隔离证据。
   不允许以“定时器存在”冒充“节点持续更新”。
7. **发布前置保护**：新`p2p3-single-publish.timer`安装后必须维持
   `disabled/inactive`；旧5个timer完整；正式release marker不提前创建。
   `single_writer.py check`此时必须**退出1**且拒绝旧writer在运行，
   这叫**负例PASS**。不能在旧发布器仍活跃时要求正向guard=0。

## D4-C：条件性安装新unit但不启用

仅在以上只读证据审查通过之后，才可以通过`--install-disabled`
安装新service/timer定义；它**不会启动**生产新writer，也**不会停旧timer**。
这是受控的系统文件更改（非生产订阅发布），仍须做前后服务清点：
全部旧unit继续原状态，新unit确认disabled/inactive，
且指向准确venv、源码、专用环境文件。环境文件权限600，
release marker仍未创建，STOP状态仍需fail-closed。

## D5：真实切换——切换前不可“预先要求正向guard=0”

真实正向guard只有在**停止并禁用两个旧写timer、排空它们的service进程、
mask旧service之后**才可能返回0；旧timer运行时返回1是正确防护。

**必须在一次有回滚能力的受控操作窗口内顺序执行：**

1. 再次冻结**执行时**最新served/staging字节、SHA、行数、有效21pin、
   旧unit状态；若与之前D4快照不同，创建新的独立快照并再次隔离恢复验证。
2. 停/disable仅`pool-publish.timer`、`pool-sync.timer`，
   等对应service无PID/Job、无旧publish/sync进程，再mask两个service；
   其余crawl/test/test-full timers和bridge/probe完全不动。
3. 执行新版`single_writer.py check`，要求**退出0**，
   guard的`legacy_writers_drained`和masked-ban全部为真。
   若不通过，**不创建release marker、不发布**，立即按快照恢复旧unit状态。
4. 首次只允许当前最新served的**完全相同字节**发布；新release marker
   严格为`PR93_APPROVED_SAME_BYTES_ONLY`，STOP显式RUNNING，
   真实写入函数必须持同一flock且检验旧写手禁启状态，输出读回SHA。
   新timer接管前核验HTTP对外served与本地served SHA相符。
5. 正式启用新timer之前，必须确认安全新增模式的业务验收范围：
   `PR93_APPROVED_VPS_ADDITIONS`需要独立env开关和真实源码完整性，
   仅允许最多4条具有VPS有效证据的新增、不能自动删除现有成员。
   没有这一后续策略，则新timer只会重复同字节或HOLD，
   **不能宣称已经恢复长期自动更新**。
6. 新timer启用后验证真实下一轮成功或安全HOLD日志、互斥、
   21pin/served/staging/HTTP哈希、手机不DIRECT/无误路由。
   一旦服务错误、pool覆盖为空、旧writer重新进入或网络受损，
   执行快照恢复两文件以及按manifest记录的旧timer/service状态。
   禁止只依赖会被覆盖的`.prev`回滚，失败必须留脱敏审计。

### D4 回执最少字段

`HEAD`、`CI`、`snapshot ID/private path`（不含原始内容）、
`sha256(full; private only)`、`line_count`、`21pin`、
`snapshot_isolation_restore`、`db_backup_integrity`、
`old_timer_state_before_after`、`new_unit_disabled`、
`STOP_test`、`source_attestation`、
`ANTI_DIRECT_LIVE`、`guard_negative_exit=1`、
`candidate_addition_gate`、`production_mutated=false`。

**在D4-A/B/C未全绿前保持 `CUTOVER_BLOCKED`、旧5个timer均运行。**
任何工作回执必须区分“隔离测试通过”和“生产真实完成”。
