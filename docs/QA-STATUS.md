# QA 与缺陷跟踪

基线：87a551a；回滚本轮：git revert 本轮提交，不改写主分支历史。

## 已有证据

- Actions 42656228190：macOS 模拟器实际运行 67 个 XCTest，0 失败；设备 Release 编译及打包成功。
- 发布 build-190：Kanyu-unsigned.ipa，26,923,634 字节。未签名，尚无本轮真机安装证据。

## 本轮缺陷

| 编号 | 问题 | 处理 | 验证 |
| --- | --- | --- | --- |
| QA-001 | 姓名含斜线使 PDF 路径变成子目录，导出失败 | 文件名去除路径/控制字符，限制 UTF-8 长度，原子写入 | 新增实际生成及 PDFKit 读取测试，待 CI |
| QA-002 | WMM 接收 NaN/无穷/越界坐标，可能传播非有限数 | 输入边界拦截 | 新增无效输入与有效场量测试，待 CI |
| QA-003 | 测试结果包和构建日志未长期留存 | always 上传 xcresult/日志，发布 SHA256，PR 门禁 | 待 CI |

## 回归范围与未完成项

- 已有测试：八字金标准、紫微金标准、奇门金标准、命理解读等（Tests/）。通过基线不等于全面算法正确。
- 本轮新增：报告真实 PDF 导出及罗盘模型边界。
- 仍待执行：冷启动、各功能导航、堪舆完整采集/ZIP 导出、罗盘真机权限与传感器、报告长文本视觉分页、签名后安装。
- Linux 无 Xcode，不能在此直接执行 XCTest；以对应 SHA 的 macOS Actions 结果为准。
- 现有每日 UTC 22:00 构建继续保留。聊天关闭后的持续开发/定时进度报告不由此工作流提供。

## 流程

每次改动执行 git diff --check；Actions 必须先通过全部 XCTest 才执行设备构建及发布。
失败时下载 verification-<SHA>，查看 tests.log、device-build.log 和 TestResults.xcresult。
下载 IPA 后先核验同版本 .sha256；自行签名安装后记录设备型号/iOS 版本/操作与结果。

## 2026-11-10 下一轮：可读性与完整性

详见 UPGRADE-RESEARCH-2026-11-10.md。新增 37 项工具说明、七主题指南、完整专业报告、搜索与分类恢复边界、照片故障处理与连拍唯一文件名、海报 MainActor 修复，以及单元/原生导航 UI 回归。提交时新增测试均待 macOS CI；不提前标记通过。UI 颜色及排版为源码修改，未完成视觉截图验收。

## 2026-11-10 数据可靠性分支验收更新

> 本节覆盖上方较早的 `87a551a` / 67 XCTest / build-190 记录；旧记录仅保留为历史证据，不能证明当前分支通过。

- main 基线：`27b1478ffec8be6d911e82c5be5e904090df8768`。
- PR #18 head `89ebd7612eadcdeb262949e5dac577b8b031e536`：Actions Run #223 执行 87 XCTest、1 XCUITest，0 失败；设备 Release、未签名 IPA 打包和 ZIP 完整性检查通过。
- PR #28：严格拒绝重复清单条目、不支持的清单版本及符号链接；本节提交后的精确 head 必须重新取得 CI 证据。
- PR #29 head `4c21a315b03f4956962542314f3cb22fbc94f55b`：Actions Run #222 执行 92 XCTest、1 XCUITest，0 失败；设备 Release 和未签名 IPA 打包通过。
- 未验证：真机人物切换/重启/删除重建、磁盘耗尽或中断恢复、iCloud 真机恢复、签名与安装。任何未签名 IPA 均不得称为可直接安装版本。

## 2026-11-10 集成后验收状态（main 2812afb）

> 本节更新当前集成状态；上方 87a551a、27b1478 与各堆叠 PR 的测试数字均为历史记录，不得当作最新 main 的独立验收。

- 当前 main：`2812afb0de41c2db55d1f630ecfe2ea44c6ef948`，由 PR #30 合并。集成测试对象为 PR #30 head `8fdab61af2a20937577bc3d8523a325136b4a413`，不是合并提交本身。
- 集成 CI：https://github.com/zsh199410/kanyu-app/actions/runs/42845467650 。GitHub job 步骤确认单元/UI 测试、设备 Release 编译、IPA 打包、验证证据上传均为 success；PR 记录称 94 XCTest＋1 XCUITest，零失败。测试数量尚需以原始 tests.log 复核。
- 本次读取到的 artifact：`verification-8fdab61af2a20937577bc3d8523a325136b4a413`（ID 13779097315）和 `Kanyu-unsigned-ipa`（ID 13778663015），均未过期；artifact 存在不等于本次已独立下载核对其内部 IPA 的 SHA256，也不等于已签名安装。
- PR #18 已合并；PR #28/#29 关闭未直接合并，变更由 PR #30 整合，不再重复合并。Issue #10/#11 已关闭，但真机人物切换、iCloud、磁盘耗尽、恢复中断和回滚失败仍需故障注入。
- PR #31 head `be65a9893593e6e17ee152e010e9287ef2d1209f` 仍开放；本次查询该 head 的 PR 触发 workflow runs 返回空列表。合并前必须取得该精确 SHA 的 XCTest、XCUITest、设备 Release 与产物证据；不得用 #30 的 CI 代替。
- PR #9 已合并，PR #8 被替代且关闭未合并，照片修复不重复整合。
- 本节仅更新可追溯验收状态，不修改算法、业务代码、用户数据或 CI 门禁。后续每次集成须追加新 SHA 与日志证据，不覆盖历史。

## 2026-11-11 罗盘集成 PR #31 独立核查

- PR #31 head `be65a9893593e6e17ee152e010e9287ef2d1209f` 对应 [Actions Run #233](https://github.com/zsh199410/kanyu-app/actions/runs/42849773711)，状态 success。job 步骤确认 Unit and UI regression tests、Build (unsigned)、Package IPA、Upload artifact、Preserve verification evidence 均 success；Publish release 为 skipped。之前「未找到此 SHA 工作流」记录已过时。
- artifact `verification-2b0b758a2c87e7a851e998439179468f37bc8e52`（ID 13782340401）和 `Kanyu-unsigned-ipa`（ID 13781497305）均存在且未过期，工作流记录 head SHA 为 `be65a989...`；验证证据命名为合成 merge SHA `2b0b758...`，两者必须在验收记录中区分。未下载校验 IPA 内部文件、未验证真机安装；不能提供已安装验证的 IPA。
- 新发现待验风险：`Sources/CompassModule.swift` 的 `finishCollect()` 使用 `trueSamples` / `magSamples` 的圆周均值保存真北与磁北，但 `declination` 和 `declinationSource` 取结束时的 `resolvedBearing`。采样期间手动磁偏角、定位或设备真北来源改变时，保存的校正收据可能与已采样本不一致。应冻结采样期间的校正来源/值，变化时重启采样或拒绝锁定，并增加跨采样状态变化 XCTest、采样 UI 回归。此项为源码审查风险，尚未真机复现，不能直接宣称测量错误。
- 仍需检查原始 tests.log 数量及失败数、合成 merge SHA 与 head 的代码差异、真机磁场/定位权限、无定位、模式切换、采样中状态变化和锁定记录重启读取。此文档更新不代表上述验证通过，也不批准 PR #31 合并。
