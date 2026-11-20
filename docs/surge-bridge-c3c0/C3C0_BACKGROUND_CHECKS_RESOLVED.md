# 待核对项核查结论（2026-11-20 11:4x CST）

两项后台待核对项均已核查，均属误认/混淆，无真实不一致。证据如下。

## 1. fc18d04 “07:47” 引用时间错位 —— 不存在

- fc18d04（PR #97 Round 8 head）实际推送时间：**2026-11-20T01:43:17Z = 09:43:17 CST**（commit API 核实：committer GitHub，author zsh199410，message “C3-C0 Round 8: absorb PR #108 signed issuer + PR #109 atomic token registry, F2/F3”）。
- 全 #73 评论（224 条，逐条 grep）中引用 fc18d04 的只有两条：
  - 7027879240（Muse Round 8 回执，2026-11-20T01:52:11Z = 09:52 CST）
  - 7028224204（GPT Round 8 审查，2026-11-20T02:14:09Z = 10:14 CST）
  - 两条均在推送之后，无任何评论在 07:47 引用 fc18d04。
- “07:47” 的真实来源：两条 **2026-11-19** 的 F 校准评论，与 fc18d04 无关：
  - 6995920135（2026-11-19T00:35:22Z，vxhvxfghv）：“[F CALIBRATION RESULT | Three Paired Samples | 2026-11-19]”，行 “UI: 57 ms, 07:47 CST (whole-pool test)”。
  - 6995956415（2026-11-19T00:37:26Z，zsh199410）：“## [GPT-6 INDEPENDENT F CALIBRATION REVIEW｜NO-GO｜2026-11-19]”，表行 “| 1 | 07:47 | 08:00:01 | 57 | 56 | 65 | tcp 相差1ms |”。
  - 07:47 CST 是 11 月 19 日 F 校准测试本身的时刻（评论发于 08:35/08:37 CST），与 11 月 20 日的 fc18d04 推送无关。
- 结论：所谓“有评论引 head fc18d04 标 07:47”是把 11 月 19 日 F 校准测试时间错当成 fc18d04 的引用时间。**无错位，无需更正任何回执。**

## 2. Round 6 回执引用的 “C3-C0 #31” —— 不存在

- Round 6 回执（评论 7024825173，2026-11-19T23:11:18Z = 07:11 CST）与 Round 6 报告（C3C0_ROUND6_REPORT.md）中引用的 C3-C0 运行是两个 workflow run ID：
  - **44631205964** = “Issue73 C3-C0 v2 full isolated regression” workflow run **#23**，created 2026-11-19T22:43:02Z = **06:43 CST**，head 44ad192（PR #104 head），success。
  - **44631915120** = 同 workflow run **#24**，created 2026-11-19T22:47:43Z = **06:47 CST**，head 09db336（PR #105 head），success。
  - 两者均在 GPT 评论 7024399594（06:49 CST）与 Round 6 回执（07:11 CST）之前完成，时间一致，无错位。
- 全 #73 评论（224 条）中没有任何一条包含 “C3-C0 #31” 或 “#31”；Round 6 回执、Round 6 报告、GPT 评论 7024399594 中均无 “#31”。
- 同 workflow 的 run **#31** 真实存在，但与 Round 6 无关：id 44636207032，created 2026-11-19T23:16:20Z = **07:16 CST**，head 1a0d7bd（= PR #107 head，Round 7 吸收范围），success。Round 6 回执发于 07:11 CST，早于 run #31 的 07:16 CST——若有人把 run #31 归到 Round 6 名下，时间自然对不上，但那是归属错误，不是回执错误。
- 结论：**Round 6 回执从未引用 “C3-C0 #31”**；实际引用的 #23/#24 时间核实无误。所谓“与 Actions 列表时间对不上”源于把属于 PR #107（Round 7）的 run #31 误归到 Round 6。**无错位，无需更正任何回执。**

## 附：核查方法
- commit API：/repos/zsh199410/kanyu-app/commits/fc18d04d2ba93348982b1eefd837279b60e73e86
- 评论单条 API：/repos/zsh199410/kanyu-app/issues/comments/{7024825173, 7025894256, 7024399594}
- 评论全量：/repos/zsh199410/kanyu-app/issues/73/comments?per_page=100&page=1..3（224 条，逐条 grep “07:47”“fc18d04”“#31”）
- Actions API：/repos/zsh199410/kanyu-app/actions/runs/{44631205964, 44631915120}；/actions/workflows/423908447/runs?per_page=50&page=2
