# D7 流向证明（GPT D6 复核三项，证据链）

- 日期：2026-11-16（CST）
- 范围：隔离环境。本地 `~/workspace/p2p3-d7/` 与 VPS `/opt/p2p3-d7/`。
- 合成固件：TEST-NET 192.0.2.0/24 与 198.51.100.0/24、假密码
  `TEST-ONLY-NOT-A-REAL-NODE`。无真实节点 URI、订阅 URL、密码、私钥、
  原始 IP、令牌。live 探针证据已脱敏（路径 token 化，SHA 只留 12 位前缀）。
- 生产状态：**生产订阅、生产定时器、手机配置一律未动**。PR #77 仍为
  Draft，不合并。无手机原生测试在本轮执行。

固定 SHA（fixture 行固定，各处一致）：v1 source `f6083ad90eac`（44 行）、
v2 source `314c25b75017`（43 行，未测）、clean14 `6074082847c3`（14 行）、
污染版 `7737d85e5d1e`（15 行）。注：演练里的“旧版”行集合即 v2 source
（44 行去 1 条失败行），故旧版 SHA 与 v2 source SHA 相同（`314c25b75017`），
是 fixture 设计，不是笔误。

---

## 1. HTTP 暴露面：served / .quarantine 不可从订阅入口直读

### 1.1 真实 nginx 审计（2026-11-16 16:37，只读）

| 检查 | 结果 |
|---|---|
| live `.conf` 文件 | 4 个（`nginx.conf` 只 `include conf.d/*.conf`，`.bak*` 不加载） |
| server 块 | 3 个：订阅宿主（静态 alias 唯一）、应用宿主（纯 proxy）、sing-box 宿主（静态 root `<NGINX_HTML>` + 1 个 proxy location） |
| 静态映射总数 | **1 个**：订阅入口 `location <STATIC_PREFIX>` → `alias <BRIDGE_DIR>` |
| 指向 served / publish 目录的 root/alias | **0 个** |
| `autoindex` 开启处 | **0 处** |
| `nginx -t` | 语法 OK |
| gate 状态目录 `/opt/pool-gate` | **不存在**（切换前，served 路径本身尚无部署） |

### 1.2 Live 探针 8 条（GET，只记状态码 + 响应 SHA 前缀 + 字节数）

| # | 路径（token 化） | HTTP | 响应 SHA 前缀 | 结论 |
|---|---|---|---|---|
| P1 | `<STATIC_PREFIX>pool-new.txt`（入口） | 200 | `cdaa94605875`（29 行） | = 磁盘 bridge 文件 SHA = 生产发布文件 SHA（2026-11-16 16:07 版） |
| P2 | `<STATIC_PREFIX>../pool-new.txt` | 404 | `edc3eb965bbb`（22 字节） | 拒绝，非订阅字节 |
| P3 | `<STATIC_PREFIX>%2e%2e/pool-new.txt` | 404 | `edc3eb965bbb` | 拒绝 |
| P4 | `<STATIC_PREFIX>.quarantine/pool-new-<ts>-<sha12>.txt` | 404 | `9f6d0b634cab`（153 字节） | 隔离区不可读 |
| P5 | `<STATIC_PREFIX>../../<PUBLISH_DIR>/pool-new.txt` | 404 | `edc3eb965bbb` | 拒绝 |
| P6 | `<STATIC_PREFIX>..%2f..%2f..%2f<SERVED_DIR>/pool-new.txt` | 400 | `1425ed57b9c4`（157 字节） | nginx 拒绝编码穿越 |
| P7 | `/<SERVED_DIR>/pool-new.txt` | 404 | `edc3eb965bbb` | 拒绝 |
| P8 | `<STATIC_PREFIX>..;/pool-new.txt` | 404 | `9f6d0b634cab` | 拒绝 |

结论：除 P1 入口外无一返回订阅字节；P1 响应字节与磁盘 bridge 文件
字节一致（SHA 全等，前缀 `cdaa94605875`）。完整证据表：
`docs/d7-live-probes.json`。

### 1.3 沙箱演练（`drills/d7_item1_http_exposure.py`，13/13 双环境）

- 同映射沙箱服务：入口 200 + SHA == clean14；6 条穿越路径全拒绝；
  `.quarantine` 猜测 404。
- 引擎：VPS 为**真实 nginx**（沙箱配置，两 server 块），本地为
  Python `http.server` 仿真（同路由语义）；两引擎 verdict 一致。
- 负对照（**守卫盲区实证**）：独立 alias 指向 served 目录时，
  `gate-sync.sh` realpath 守卫返回 `ok`（盲区），探针却返回 200 且
  SHA == served SHA。因此防暴露的控制是“切换前审计 + 探针”，不是守卫；
  切换窗口须重跑审计 + 探针（`docs/D7_CHECKLIST.md` §2 第 2 行）。

---

## 2. 双目标回滚故障注入：两 rename 之间不是真正原子事务

D7 更正：`bridge_sync` 是**同一锁内连续两次原子 rename，不是跨两个
文件的真正原子事务**（D6 文档“ONE atomic unit”措辞作废）。
新增只读检测 `verify_targets()`（+ CLI `--verify-targets`），
新增三个 TEST-ONLY hook（生产调用一律传 None）。

| 注入 | 结果 | 下一轮 |
|---|---|---|
| A legacy rename 后写后 SHA 失败（hook 破坏刚 rename 的文件） | rc=1 `legacy_copy_failed`；bridge 回滚到写前字节；legacy 持污染字节（SHA `7737d85e5d1e`，可检测）；`verify_targets` rc=1（首个分歧为 bridge，因 bridge 已回滚） | 再跑一次 rc=0，两目标 clean14，`verify_targets` consistent |
| B bridge rename 后写后 SHA 失败 | rc=1 `bridge_sha_mismatch`；bridge 恢复写前字节；legacy 未动；无假成功 | 再跑一次 rc=0，两目标 clean14 |
| C 两 rename 间进程崩溃（子进程 hook 抛错，模拟 crash） | 子进程 rc!=0；bridge=新快照 clean14，legacy=写前旧版；`verify_targets` rc=1 `legacy_sha_mismatch`；锁未堵（下一轮正常获取，flock 由内核释放） | 再跑一次 rc=0，两目标 clean14，`verify_targets` consistent |
| D legacy 写 fsync 失败（mock `os.fsync` 在 legacy tmp 写时抛错） | rc=1 `legacy_copy_failed`；bridge 回滚；legacy 未动 | 再跑一次 rc=0 |

演练 `drills/d7_item2_legacy_postwrite.py` 15/15 双环境；
单元测试 `tests/test_d7.py` 第 2 组 10 项（全套 141 项内）；
红→绿 `drills/d7_redgreen.py` 4/4（D6 树：`verify_targets` ImportError；
D7 树：15/15）。

---

## 3. :07/:15 周期与 stop→restore→start（程序层）

- 周期演练 `drills/d7_cycles_0715.py` 21/21 双环境：N 周期 :07 发布 v1
  → :15 服务 clean14；N+1 周期 :07 发布 v2（源 v1→v2）→ :15 重服务
  clean14；N+2 周期 :07 未测 v3 被拒 → :15 继续服务 v2 clean14；
  :15 篡改 → 同步拒绝 + served 恢复 + bridge 保持上一好 SHA + STOP。
- stop→restore→start 演练 `drills/d7_stop_restore_start.py` 12/12 双环境：
  快照（5 文件 + manifest，目录 700 / 文件 600）→ 服务起（GET clean14）
  → 丢文件 + 坏库 → 停服务（端口拒绝）→ 恢复（SHA 全等 manifest，
  DB 计数一致）→ 重起服务（GET clean14）；第二轮重复通过。
  **生产执行未验—待切换窗口**（见清单 §2 第 7 行）。
