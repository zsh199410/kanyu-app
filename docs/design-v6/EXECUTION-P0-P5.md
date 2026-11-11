# V6 P0～P5：可执行源码指令与交付门槛

全局阶段顺序以本文件为准。基线 `1ae6503994940414ab31afb4906cb7b32d291d82`；只做表现层。每批独立分支/提交，保留现有 API、档案 UUID/存储键、命盘/解释模型、原始输入和现有测试。`Sources` 目录由 `project.yml` 自动纳入构建；新增 Swift 即使没有调用也必须能编译。

## P0：冻结真实基线

在仓库根目录执行：

```sh
git status --short
git rev-parse HEAD
git diff --check
git diff 1ae6503994940414ab31afb4906cb7b32d291d82 -- Tests UITests Resources
python3 design/verify_v6.py
node --input-type=module --check < design/web/theme-adapter-v6.js
```

`verify_v6.py` 是本批 P1 的只读源码/静态设计合同检查（只写核查报告）。它逐字节比较所有基线受保护文件，并对两个混合文件只豁免明确的主题/按钮/卡片片段；不能把它的 PASS 写成 Xcode 或截图验收。P2 起其窄白名单会有意拒绝更多 UI 改动，应在独立评审中建立同等精度的阶段性保护范围，不删除保护、不将整个混合文件列为可任意改动。

在 macOS/Xcode 26 环境执行现有工程回归，**不改任何 Tests**：

```sh
set -e
set -o pipefail
xcodegen generate
mkdir -p build
KANYU_V6_SIM=$(xcrun simctl list devices available -j | python3 -c "import json,sys; ds=json.load(sys.stdin)['devices']; us=[x['udid'] for v in ds.values() for x in v if 'iPhone' in x.get('name','') and x.get('isAvailable',True)]; print(us[0] if us else '')")
test -n "$KANYU_V6_SIM"
xcodebuild test -project Kanyu.xcodeproj -scheme Kanyu -destination "platform=iOS Simulator,id=$KANYU_V6_SIM" -resultBundlePath "build/V6-$(git rev-parse --short HEAD)-$(date +%s).xcresult" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | tee build/v6-tests.log
```

保存浅/深主题、普通/最大辅助字号、降低动态效果/透明度的原生截图与 VoiceOver 路径。至少首页、无档案、个人中心、八字、紫微、奇门、罗盘、压盘、报告各一组；每份证据包含提交 SHA、设备、系统版本、主题和字号。没有运行的格子写「未运行」。现有 1 条 UI smoke 不足以代替这些视觉和业务路径。

## P1：先接语义层，保留旧调用点

实际代码已在本批实施：

1. `Sources/DesignSystemV6.swift`：集中 `KanyuV6.Hex/Theme/Metric/Typography/Motion`，新增 `KanyuV6Card`、`KanyuV6PrimaryButton`、`KanyuV6FloatingSurface`。所有颜色整数显式 `UInt32`，匹配既有 `Color(rgb:)` 和 `kyDyn`。
2. `Sources/KanyuApp.swift`：仅 `enum Ky` 代理到 V6；仅把原 `KyPrimaryButton` 改为 `typealias KyPrimaryButton = KanyuV6PrimaryButton`。不改 `KyMotion`、引擎、路由或首页逻辑。
3. `Sources/DesignSystemV2.swift`：只把 `kyCard()` 委托给 `KanyuV6Card { self }`。其他五行映射、解释、设置代码保持不变。
4. `design/tokens-v6.json` 是可检查 token 记录，`design/web/kanyu-v6.css` 与 `theme-adapter-v6.js` 为待接真实 Web 的参考，当前不声称线上使用。

最小使用方法（示意，接在现有 View 内，不新建业务模型）：

```swift
VStack(alignment: .leading, spacing: 8) {
    Text("本盘依据").font(KanyuV6.Typography.cardTitle)
    Text(existingExplanation).font(KanyuV6.Typography.body)
}.kyCard()
Button("查看完整解读", action: existingAction).buttonStyle(KyPrimaryButton())
```

玻璃只在已有浮动层逐个接入 `.modifier(KanyuV6FloatingSurface())`；不要全仓替换 `kyGlass`，不要改变抽屉绑定/选中值。P1 需检查浅深按钮文字、卡边界、禁用态、嵌套旧组件配色和所有旧入口，再合并。

## P2：首页、命主与个人中心

- `KanyuApp.swift/HomePageView`：先提取 `brandHeader`、`personSwitcherCard`、`todaySection`、`primaryBentoGrid`、`recentToolsSection` 的纯 View 小组件，保留现有输入/回调/绑定；按 SCREEN-SPEC 的六层顺序重排。先迁移品牌栏中的个人中心按钮，再移除重复视觉块。
- `AlmanacModule.swift/TodayFortuneCard`：不改历法和三条已有解释生成；五主题只做已有解读的导航/摘要。无数据明确空态，绝不增加随机数、硬编码「82分」或用条形长度暗示不存在的个人评分。
- `HomeTabs.swift/MyView` 与 `PeopleModule.swift` 的 View：分组档案、报告、备份、回验、显示设置；不改人物模型/增删/备份实现。`PersonQuickBar.swift` 统一 44pt 命中区和档案切换反馈。
- `AllToolsView.swift` 保留完整 registry、原 `ContextualToolDestination` 门禁和所有工具路由；可调整目录排版/分组，不能移除功能。无档案选择个人工具仍进入真实建档页，取消不生成替代盘。

回归：无档案→创建→取消/保存、两人切换、删除当前/最后一个、恢复备份、五 Tab、四旗舰、全部工具逐项可达。截图检查 320pt 等效窄宽和辅助字号单列。只在真数据下显示当前大运摘要，不在 View 计算大运。

## P3：八字、紫微、奇门及白话解读

- `BaziModule.swift` 只改 View：四柱/时间层/标签/已有 sheet 的版式；天干、地支、十神、神煞的动作绑定到现有详情数据。统一底部抽屉 detents 与读法结构。对已有 `safeDayun`、柱索引等选中状态做 UI 边界防护：先判断数组非空，再 `min(max(index,0),count-1)`；空态不创建假条目。不得触碰排盘函数/取用规则。
- `ZiweiModule.swift` 只改 `ZiweiBoardView`、宫格及其 `flyLinesOverlay`、`palaceCenter`、`replayFlyLines` 的绘制样式；飞线使用现成关系字段/现有三方四正关系，不凭视觉手写替代安宫算法。选中索引防护与数据版本同步；所有宫位有列表等价入口；角标文字保留真实四化。`PosterModule.swift/ZiweiCenterFlyLines` 是海报组件，留到 P5，不误当本阶段屏幕飞线。
- `QimenModule.swift` 只改宫格、筛选胶囊、解释容器和 zoom 交互的样式；已有层、局、时间和方位不变，不翻转盘序、不对门/星/神重新排名。
- `InterpretModule.swift`、`ChartDepthModule.swift` 中若存在渲染 View，只改 View；如果段落产生器与 UI 混杂，先抽出接收现有字符串的只读阅读器。不改原文、规则、条目顺序或生成条件。术语解释用现有词典；缺出处写「未收录原文」，不伪造五典引文。
- 五行色只替换颜色常量，保留 `KyV2.element(ofChar:)`、`elementIndex` 和占比计算原样；按元素字/图标双编码。旧 `KyMotion` 的循环高光逐个换成选中瞬时反馈，检查 Reduce Motion 与页面离开后的停止。

回归：现有金标准与 XCTest 原样运行；同一人物/时刻/设置前后原始盘与解释内容相同；选宫/选运/换人/空数组不越界；VoiceOver 能从列表读出盘面。不修改 Tests 来补救实现。

## P4：恒深仪器与压盘

- `CompassModule.swift` 只改 `CompassStandaloneView` 的 `dial(size:)`、`lockCard`、读数/质量状态布局；复用既有恒深底与 Canvas。首屏保留真磁北、校正来源和采样状态。手动刻度反馈节流不超过 8Hz；传感器刷新不得触发同频触感。
- `FloorPlanOverlayView.swift` 先调整工具栏、图例、透明度和准星热区，再在同一坐标容器对图层施加视觉变换。视图旋转/缩放/平移独立于 `sitDegree`、测量锁值、宫序与元运。
- 不动 `CompassBearingResolver`、`CompassManualDeclinationInput`、`CompassSampleReceipt`、`finishCollect`、WMM 表/系数、坐向转换、`FengshuiEngine.chart/youNian`。不放宽锁定门控以迎合新按钮。
- AR/相机相关入口先完成真实权限、图像/方向来源、采集失败的呈现；只替换现有仪表/按钮，不能把未实现的 AR 识别描述成已上线。

真机回归：拒绝/撤销权限、低水平磁场、无校正/校正变化、手动输入、旋转/锁定/重采样、前后台切换、拖拽缩放底图。保留测量收据；截图和性能记录不能代替传感器准确度验证。iPhone 16 Pro Max 用 Instruments 记录滚动/旋盘帧耗时、卡顿和内存；未达到时如实报告。

## P5：海报、PDF、Web 接入与安装包

- 新增纯度量 `Sources/PosterMetrics.swift`；在 `PosterModule.swift` 的 View/Palette 和 `PosterEditorModule.swift` 接 540pt@2、正文476pt、细盘列106.5pt。别盲目替换所有 padding。已有两样式不改 rawValue；同步新增朱砂/玄夜的 switch、palette、suffix、选择器和所有 renderer。
- `ZiweiPosterView`/`HeCanPosterView` 保留现有数据与真实飞线；宫格拥挤内容移续段。`ReportCenterView.swift` 兼容新后缀并保留所有旧前缀/旧文件。
- `ReportModule.swift` 只改 `makePDF` 的布局/绘制/分页部分：用 CoreText 可见范围拆超长段；同一布局结果产生正文和目录；目录可续页。保留 `ReportBuilder.lines`、内容/档位/哈希/引擎版本。PDF 第 2 页仍是首目录并保留现有目录文字契约。
- 保留 `ImageRenderer` 在 MainActor；导出前测内存预算，超限提供分章长图/PDF；生成/取消/错误/重试/分享/相册成功有真实反馈。逐变体保存实际 PNG/PDF，检查长姓名、多星曜、超长说明、首末字和边距，不能只看宽高。
- Web：当前只验证可移植 CSS/ESM 语法与颜色合同。找到真实源码后，记录实际主题/路由/图表/报告文件，再按 P1～P5 同序接入；不得虚构源码路径或新建一个静态壳称已完成全站。主题适配器由宿主传 `getPreference`，不新增存储键。

在 macOS 本地构建真实未签名设备包（CI 已有同等流程；PR 构建只产 artifact，不发布 release）：

```sh
set -e
set -o pipefail
KANYU_V6_BUILD_NUMBER=$(git rev-list --count HEAD)
xcodebuild -project Kanyu.xcodeproj -scheme Kanyu -sdk iphoneos -configuration Release CURRENT_PROJECT_VERSION="$KANYU_V6_BUILD_NUMBER" -derivedDataPath build/V6-DD CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build 2>&1 | tee build/v6-device-build.log
KANYU_V6_PACKAGE=$(mktemp -d "${TMPDIR:-/tmp}/kanyu-v6.XXXXXX")
mkdir -p "$KANYU_V6_PACKAGE/Payload"
cp -R build/V6-DD/Build/Products/Release-iphoneos/Kanyu.app "$KANYU_V6_PACKAGE/Payload/"
(cd "$KANYU_V6_PACKAGE" && zip -qry Kanyu-unsigned.ipa Payload && unzip -tq Kanyu-unsigned.ipa && shasum -a 256 Kanyu-unsigned.ipa > Kanyu-unsigned.ipa.sha256)
git rev-parse HEAD > "$KANYU_V6_PACKAGE/commit.txt"
printf '%s\n' "$KANYU_V6_PACKAGE"
```

本地检查用提交数量提供明确的正整数构建号，避免空 CFBundleVersion；正式发布仍用现有 CI 的 github.run_number。没有成功 `xcodebuild` 就停止打包；上面的命令在支持环境启用 `set -e`，失败即停；不能跳过失败步骤继续打包。安装需用户自行签名。正式发布优先走现有 `.github/workflows/build.yml`，测试、设备 Release、CRC、SHA 和提交对应后才给新 IPA 链接。

## 每批提交与回滚

```sh
git diff --check
git diff --stat
git diff --exit-code 1ae6503994940414ab31afb4906cb7b32d291d82 -- Tests UITests Resources
```

只 stage 本批列明的文件，不用 `git add .` 带入其他工作。提交记录写出影响范围、已运行检查与未运行项。推送后核对 PR head SHA 与 Actions 对应 SHA；PR 的旧绿色结果不代表新 head 已通过。通过实际回归并记录截图后合并。回滚单提交用 `git revert <commit-sha>`；回滚合并提交用 `git revert -m 1 <merge-sha>`，不强推、不重置用户数据。

交付清单：PR/commit、真实测试数/失败数、设备 Release 结果、截图/性能证据范围、PNG/PDF 样例、IPA 的对应提交与 SHA256/CRC。未运行写未运行，未构建写未构建。
