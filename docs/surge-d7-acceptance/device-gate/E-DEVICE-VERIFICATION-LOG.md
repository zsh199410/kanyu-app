
## 2026-11-18 22:09 — 第 3 步 PASS（真机）
- 租约：proxy=Test-Proxy-1，issued_at=1795010868，expires_at=1795011468（TTL 600s），boot_id=boot-1795010788.015655-312c31ba9717d509（引擎 engine-started 现铸，证实 URL 脚本已加载）。
- 根因已定：gate-script.js / gate-events.js 相对路径加载失败（引擎日志 `Failed to load external resource: gate-events.js 资源不存在` / `Failed to load script: gate-script.js`）。修法：device-gate-test.conf 的 [Script] 改为 remote-storage 公共 URL（2026-11-20 14:03 过期），重导后加载成功。
- 证据：请求 #99/#84（HTTPS）策略=Test-Proxy-1；#117 事件 `Policy decision path: 测试安全出口 -> Test-Proxy-1`，`Rule matched: SCRIPT gate-rule`；#75 `Attempt to connect to host timed out` 属预期（假代理）。QUIC 条目为 QUIC-BLOCK（Surge 传输层拦 QUIC，非门禁拒绝）。
- 第 2 步早先“通过”是脚本未加载时的假阳性（无脚本→SCRIPT 不匹配→落 FINAL,REJECT），第 4 步（租约过期后应拒绝）将用已加载脚本重新验证 fail-closed。
- 22:10 用户关台式机。剩余：第 4 步（租约约 22:17–22:18 过期，手机单机可测）、第 5 步（重启手机）、第 6 步（切网）、第 7 步（停用脚本）。VPS SSH 当时 Permission denied（authorized_keys 疑似又被清空），未根治，待查。

## 2026-11-18 22:19 — 第 4 步 PASS（真机）
- 租约已过期（expires_at=1795011468，即 22:17:48）。22:19:24–25 的请求 #656–#670 全部 阻止、策略 REJECT、规则 FINAL（#670：HTTPS，Rejected by rule，16 ms，`Rule matched: FINAL`，`Disconnect: Rejected by rule`）。
- 这是脚本已加载状态下的真 fail-closed 证据（与第 2 步早先脚本未加载的假阳性不同）：第 3 步有租约时走 Test-Proxy-1，第 4 步租约过期后落 FINAL,REJECT。
- 结论：DEVICE_LOCAL_FAIL_CLOSED 的核心行为已双向证实（有效租约放行 / 过期租约拒绝）。
- 剩余第 5 步（重启手机）、第 6 步（切网）、第 7 步（停用脚本）均须先有新租约，台式机已关，须等电脑开机后重签再测。

## 2026-11-18 22:23 — 切回生产配置
- 用户已切回「个人最新配置.conf」，手机恢复正常上网。今晚真机验证到此为止。
- 待办（须台式机开机后）：第 5 步（重启手机）、第 6 步（切网）、第 7 步（停用 gate-rule 脚本），每步均须先重发新租约；F 原生测速校准另行安排。

## 2026-11-18 22:33 — 第 5 步 PASS（真机）
- 新租约 22:28 签发（issued_at=1795012136，expires_at=1795012736，约 22:38 过期；boot_id=boot-1795011919.972506-8623fc3e49406586，引擎现铸）。重启手机后 22:33:19 的请求 #996–#1003 全部 阻止、策略 REJECT、规则 FINAL（#1003：HTTPS，Rejected by rule，12 ms，`Rule matched: FINAL`）。
- 关键：测试时租约仍在 10 分钟有效期内（未到 22:38），拒绝不是自然过期，而是重启吊销了租约（engine-started 新铸 boot-id / profile-reloaded 删租约）。此前“engine-started 未被观察到触发”的疑虑至此解除——重启吊销机制真实生效。
- 剩余：第 6 步（切网）、第 7 步（停用 gate-rule 脚本），每步均须先重发新租约（当前租约已被重启吊销）。

## 2026-11-18 22:36 — 第 6 步 PASS（真机）
- 新租约 22:35 签发（issued_at=1795012517，expires_at=1795013117，约 22:45 过期；boot_id=boot-1795012328.0595589-cb0dcce7591aa3ae，重启后新值）。关 Wi-Fi 切到 5G 蜂窝后 22:36:20–21 的请求 #1530–#1540 全部 阻止、策略 REJECT、规则 FINAL（#1540：HTTPS，Rejected by rule，13 ms，`Rule matched: FINAL`；状态栏已显示 5G）。
- 关键：测试时租约仍在 10 分钟有效期内（未到 22:45），拒绝不是自然过期，而是切网触发 network-changed 删租约。切网吊销机制真实生效。
- 剩余：第 7 步（停用 gate-rule 脚本），须先开回 Wi-Fi、重发新租约（当前租约已被切网吊销，且手机现为 5G、台式机无法经局域网 192.168.5.19 触达）。

## 2026-11-18 22:39 — 第 7 步 PASS（真机）→ E 全过
- 新租约 22:38 签发（issued_at=1795012679，expires_at=1795013279，约 22:48 过期；boot_id 与上一租约相同，引擎未重启）。用户在 Surge 脚本列表中停用 gate-rule（列表中 gate-rule 呈灰色禁用态，其余 gate-events-boot/net/profile 与 gate-sweep 均为启用态）。
- 停用后 22:39:32–38 的请求 #1860–#1910 全部 阻止、策略 REJECT。测试时租约仍在 10 分钟有效期内，拒绝是因为 gate-rule 被停用、SCRIPT 规则不匹配、请求落 FINAL,REJECT——脚本缺失时系统 fail-closed，不 fail-open。
- 结论：E 真机验证 2–7 步全部通过。DEVICE_LOCAL_FAIL_CLOSED 由 UNPROVEN 改判 PASS（第 2 步以第 4 步过期租约的真 fail-closed 证据为准，早先脚本未加载的假阳性作废）。
- 待办：用户把 gate-rule 重新启用、切回「个人最新配置.conf」；Muse 把 E 真机证据回帖 #73、提交本轮改动并更新 PR #92。
