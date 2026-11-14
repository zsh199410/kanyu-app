# D1：共享锁 + 双门禁防 :07 覆盖（隔离实现）

针对 GPT 决策 6875033415（Issue #73，2026-11-14 17:12）第 4 点：
publish / sync 无共享 flock、21 条钉选仍享豁免，**不接受“仅原子重命名”
代替互斥和门禁**。本目录在隔离环境实现并验证了共享锁 + 双门禁，
**生产一律未动**（未改生产目录、生产订阅、生产定时器、手机配置）。

## 1. 双门禁口径（GPT 6875033415 第 1 点，已接受）

发布 allowlist 的**唯一标准** = 最新同一版本手机原生成功且 <300ms、
无后续原生失败。P0 只作初筛 / 健康信号。

- 对每条指纹，取其在**被发布版本**上的最新一次原生结果：
  无同版本原生证据 → 拒绝（fail closed）。
- 同版本最新结果必须是成功且 ms < 300。
  P0 <280 但原生失败 / 超线 → 拒绝（原生说了算，P0 救不了）。
- **无后续原生失败**：同版本通过之后，任何更新一轮原生测试里
  该指纹失败或超线 → 通过作废，拒绝。更新一轮通过不作废（只确认）。
- 同版本通过须新鲜：时间戳 0 < ts <= now（任何未来时间戳一律拒绝，
  与 D0 严格规则一致），且在 24h TTL 内。
- 原生通过但 P0 最新在 (280, 297] → **有条件候选**：放行，但打上
  conditional 标记供复核。P0 最新失败只记健康警告，不拒绝。

## 2. 共享锁（publish / sync / rollback 共用一把 flock）

- 锁文件 `lock/publish.lock`（D0 `publish_lock.py` 原样复用，SHA256
  `02e840513ff686d1ac00ba64ec4aea80136bc1faaace6c3eb924a5a51b44ab98`，
  D1 只加了：锁内原子写 `_atomic_write_inner`、快照/文件版本 sidecar）。
- publish、sync、rollback 三条路径在**同一把锁内**完成“门禁判定 +
  写文件”（无 TOCTOU）；拿不到锁超时即拒绝，不强行覆盖。
- 崩溃恢复是 flock 的固有属性：持有者 SIGKILL 后内核立即释放锁，
  下一轮直接接手（演练已验证）。
- 每次发布先把当前文件拷到 `history/`（保留最新 3 份），每个快照与
  当前文件各带 `.meta.json` sidecar，记其 `source_version_sha`——
  回滚目标据此做门禁复核，无 sidecar 的锚点一律拒绝回滚。

## 3. 三条路径的门禁

| 路径 | 门禁点 | 拒绝时 |
|---|---|---|
| publish（:07） | 候选行（含钉选，无豁免）过原生 allowlist；0 条通过则拒绝 | 旧订阅原样保留，rc=1 |
| sync（:00/:15/:30/:45） | 源文件逐行重过门禁；须**全部**通过且非零，否则拒绝 | 已服务文件原样保留，不被脏源覆盖 |
| rollback | 锚点（.prev / history）按其**自身版本**过门禁；须全部通过且非零 | 当前文件不动，拒绝回滚 |

关键防线：即使一个不认锁的旧逻辑写手把未门禁的 44 行文件直接丢进
`publish/`，sync 门禁也会拒绝服务它，已服务的干净文件保持不变
（演练 `sync-refuses-legacy-ungated-source` 已验证）。锁管住认锁的
写手，sync 门禁兜底不认锁的写手；两者缺一不可，缺的那个是部署前置
条件，不是代码能单方面保证的（见 §5）。

## 4. 目录

```
pool/
  phone_gate.py     D0 严格版（P0 门禁，ts <= now；现仅作 P0 健康信号源）
  native_gate.py    D1 双门禁（原生 allowlist + P0 健康信号）
  publish_lock.py   D0 锁 + D1 锁内写 / 版本 sidecar
  rules.py          D0 select_publish（allowed_fingerprints；钉选与轮换同过门禁）
  publish.py        D1 发布路径（:07）
  sync.py           D1 同步路径（:00/:15/:30/:45）
  rollback.py       D1 回滚路径（8 步，门禁复核锚点）
fixtures/
  build_fixtures.py 合成固件生成器（TEST-NET 主机、假密码；只镜像 13:24 的判定结构）
  pool_44_fixture.txt / clean_14_fixture.txt / native_results_fixture.json /
  native_results_supersede_fixture.json / p0_fixture.db / MAPPING.md
tests/test_d1.py    24 项单元/集成测试
drills/
  hold_lock.py      锁持有者（崩溃演练用）
  sim_timers.py     定时模拟：并发 :07 发布 + :15 同步、锁竞争、旧逻辑写手兜底、下一轮 :07
docs/
  direct-test-plan.md  手机正式组 DIRECT 证据测试方案（只给方案，等机主定时间再跑）
```

## 5. 运行

```bash
python3 fixtures/build_fixtures.py            # 生成合成固件
python3 -m unittest discover -s tests -v      # 24 项测试
python3 drills/sim_timers.py --workdir /tmp/d1-drill --cycles 3 \
  --candidates fixtures/pool_44_fixture.txt \
  --clean fixtures/clean_14_fixture.txt \
  --native-record fixtures/native_results_fixture.json \
  --source-version <fixture pool SHA> \
  --probe-db fixtures/p0_fixture.db --log /tmp/d1-drill/sim-log.json
```

## 6. 诚实边界（已验证什么、没验证什么）

已验证（隔离环境，合成固件）：
- 共享 flock 互斥：持锁时另一方 1s 超时失败；释放后正常接手。
- 崩溃恢复：SIGKILL 持锁者后，下一方立即拿到锁，文件完好（SHA 不变）。
- 双门禁：14 条原生通过放行（含 3 条有条件候选 P0 281–297）；
  4 条 P0 <280 但原生超线（320/321/983/1018）拒绝；26 条原生失败拒绝；
  异版本证据拒绝；后续原生失败作废旧通过；未来时间戳拒绝；超 24h 拒绝。
- 钉选无豁免：无原生通过的钉选行被挡下，有通过的才放行。
- 门禁贯穿三路：sync 拒绝未门禁源文件；rollback 拒绝无版本 sidecar 的锚点。
- 定时模拟：并发 :07 发布 + :15 同步多轮后，服务文件始终是干净 14 行；
  旧逻辑写手直接丢 44 行进 publish/ 后，sync 拒绝、服务文件不动；
  再下一轮 :07 后仍是干净 14 行（无 21+23 恢复）。

没验证 / 仍需的：
- **固件是合成的**：TEST-NET 主机 + 假密码，只镜像 13:24 的判定结构
  （名字、原生/P0 毫秒数、通过/超线/失败）。固件的 tested_at 取生成
  时刻，只为让演练可跑——**它不是 13:24 证据的新鲜度证明，不重置
  真实 13:24 的 TTL**（GPT 6880539782 已定：13:24 只作历史证据）。
  生产切换前后仍各需一次新的手机原生复测。
- 锁只约束认锁的写手：生产切换时必须把 :07 / :15 定时器改成调 D1
  路径，否则旧逻辑照样绕过锁写文件（sync 门禁是兜底，不是替代）。
- DIRECT 证据：VPS 侧只能证明传输无 DIRECT 回退（D0 已做）；Surge
  正式组全失败/空/单节点是否落 DIRECT，只能按 `docs/direct-test-plan.md`
  在手机上实测，尚未跑。
- 生产切换本身：须 GPT 批准 + 完整未脱敏备份 + 机主在场验收后才做。
  本目录不含任何生产切换步骤。
