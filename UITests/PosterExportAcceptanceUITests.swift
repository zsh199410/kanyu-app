import XCTest

/// QA 导出验收 UI 截图测试（独立 QA 分支 qa/poster-export-acceptance-20261117）。
/// 任务二：真实 App 内的业务入口（八字/紫微/合参 tab）＋八字海报页＋分享流程截图。
/// 附件经现有 xcresulttool 导出步进 build/screenshots（注明模拟器，xcresult 自带设备信息）。
/// 依据：八字 tab 有 TextField“命主姓名（可留空）”与“立即排盘”按钮；海报入口 hub 卡
/// “命盘海报导出”与速览链接“出预测单海报 ›”；PosterSheetView 的 ShareLink 在 fileURL
/// 非空时显示，八字 sheet 无归属门禁（render 无条件归档），故无人物档案也能走到分享。
final class PosterExportAcceptanceUITests: XCTestCase {
    private func shot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// 等待海报渲染完成再断言分享按钮：分享按钮出现即成功；失败卡片出现即按渲染失败报错；
    /// 保存按钮出现而分享按钮不出现，说明渲染已完成但 ShareLink 标签查不到（另类失败，需修标签）。
    /// 渲染是主线程同步 1080px 光栅化（PosterSheetView.render 经 PosterRasterizer.render＋
    /// 等海报渲染完成并滚到底部，等到分享按钮出现。
    /// 根因（Build #467 失败时刻证据已核实，run 44020882050）：
    /// 渲染本身不慢——失败时刻录屏三帧（t=105/135/148s）完全相同，海报已完整渲染
    /// （王小明四柱＋五行条＋解盘文字全在屏上），且失败时刻 UI 层级里预览图在、无进度条、无失败卡，
    /// 就是没有分享按钮。原因是分享／保存按钮在 7 页长图底部、LazyVStack 里，不滚到底根本不会实例化，
    /// 光等多久都没用。所以每轮查不到就长拖拽滚向底部再查；120 秒是上限，不是“渲染要 120 秒”。
    /// 这不是放宽断言——分享按钮仍必须出现。失败卡片（“重新生成海报”按钮）
    /// 与保存按钮（“保存到相册”，与分享按钮同属 fileURL != nil 分支）用于区分“渲染失败”与“标签问题”。
    /// Build #491 失败定论：5 次短 swipeUp 只滚到 90%（滚动条 6 页 90%），第 5 次后 App 60 秒以上
    /// 不进入 idle，第 6 次 waitForExistence 快照评估逐次超时（:34 报错），重进修法从未执行；
    /// 改为一次长拖拽（0.85→0.15）、最多 4 次，断言不变。
    private func waitForPosterRender(_ app: XCUIApplication, timeout: TimeInterval = 120) {
        let shareButton = app.buttons["分享海报"]
        let retryButton = app.buttons["重新生成海报"]
        let saveButton = app.buttons["保存到相册"]
        let deadline = Date().addingTimeInterval(timeout)
        var drags = 0
        while Date() < deadline && drags < 4 {
            if shareButton.waitForExistence(timeout: 2) { return }
            if retryButton.exists {
                XCTFail("海报渲染失败（已显示重新生成卡片），不是超时")
                return
            }
            if saveButton.exists {
                XCTFail("海报已渲染完成（保存到相册已出现）但「分享海报」按钮无法按标签查到，疑似 ShareLink 无障碍标签问题")
                return
            }
            // 分享按钮在 6 页长图的 LazyVStack 底部，未滚到底不会实例化：长拖拽滚向底部再查。
            // 短 swipeUp 每次只挪约 1 个版面、多次手势增加 App 失活风险（Build #491：5 次只到 90%，
            // 随后 App 不 idle、快照评估超时）；一次长拖拽（0.85→0.15）挪得更多，最多 4 次。
            // 渲染未完成时内容只有进度条，滑动无影响；渲染失败时内容短，滑动无影响。
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15))
            start.press(forDuration: 0.1, thenDragTo: end)
            drags += 1
        }
        XCTFail("海报渲染超时（120 秒内分享按钮与失败卡片均未出现）")
    }

    func testPosterBusinessEntriesAndShareFlow() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-onboardingDone", "YES", "-AppleLanguages", "(zh-Hans)"]
        addUIInterruptionMonitor(withDescription: "系统权限") { alert in
            for title in ["使用App时允许", "使用 App 时允许", "Allow While Using App", "允许一次", "Allow Once", "好", "OK"] {
                if alert.buttons[title].exists { alert.buttons[title].tap(); return true }
            }
            return false
        }
        app.launch()

        // 业务入口：八字 tab → 输入虚构人名 → 立即排盘。
        let baziTab = app.tabBars.buttons["八字"]
        XCTAssertTrue(baziTab.waitForExistence(timeout: 30), "八字 tab 未出现")
        baziTab.tap()
        let nameField = app.textFields["命主姓名（可留空）"]
        for _ in 0..<5 {
            if nameField.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(nameField.waitForExistence(timeout: 10), "姓名输入框未出现")
        nameField.tap()
        nameField.typeText("王小明")
        let calcButton = app.buttons["立即排盘"]
        XCTAssertTrue(calcButton.waitForExistence(timeout: 10), "立即排盘按钮未出现")
        calcButton.tap()
        let baziWorkspace = app.descendants(matching: .any).matching(identifier: "workspace.bazi").firstMatch
        XCTAssertTrue(baziWorkspace.waitForExistence(timeout: 30), "八字排盘结果未出现")
        shot(app, name: "entry-bazi-result")

        // 海报页：hub 卡“命盘海报导出”（找不到时回落速览链接“出预测单海报 ›”）。
        let posterEntry = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "命盘海报导出")).firstMatch
        if posterEntry.waitForExistence(timeout: 30) {
            posterEntry.tap()
        } else {
            let altEntry = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "出预测单海报")).firstMatch
            XCTAssertTrue(altEntry.waitForExistence(timeout: 10), "海报入口未出现")
            altEntry.tap()
        }
        XCTAssertTrue(app.navigationBars["命盘海报"].waitForExistence(timeout: 30), "命盘海报页未出现")
        waitForPosterRender(app)
        let shareButton = app.buttons["分享海报"]
        XCTAssertTrue(shareButton.exists, "分享海报按钮未出现（渲染未完成）")
        shot(app, name: "sheet-bazi-song")

        // 分享流程：点分享 → 系统分享 sheet 截图 → 关闭。
        // 失败定论（Build #471 取证）：系统分享 sheet 在 iOS 27 以 Popover 呈现，非 Sheet；
        // 失败时刻层级与录屏均显示分享 sheet 已完整出现（Reminders/Preview/More、Copy/Save Image），
        // 只是 app.sheets 永远匹配不到 Popover。先等 Popover，再回落 Sheet，断言强度不变。
        shareButton.tap()
        let popoverAppeared = app.popovers.firstMatch.waitForExistence(timeout: 15)
        let sheetAppeared = popoverAppeared || app.sheets.firstMatch.waitForExistence(timeout: 2)
        XCTAssertTrue(sheetAppeared, "系统分享 sheet 未出现")
        shot(app, name: "share-bazi")
        // 关闭分享 sheet：iOS 27 的分享 sheet 是 Popover，无「取消」按钮（Build #471 失败时刻层级已证实）；
        // 先点系统 dismiss 区域，再回落 swipeDown；关闭后确认 Popover 已消失再继续。
        let cancelButton = app.buttons["取消"]
        if cancelButton.waitForExistence(timeout: 3) {
            cancelButton.tap()
        } else if app.otherElements["PopoverDismissRegion"].firstMatch.waitForExistence(timeout: 3) {
            app.otherElements["PopoverDismissRegion"].firstMatch.tap()
        } else {
            app.swipeDown()
        }
        let sheetGone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.popovers.firstMatch, handler: nil)
        wait(for: [sheetGone], timeout: 5)

        // 尊享款式：切款式 Picker 到“尊享预测单”，等重渲染后截图。
        // 回到页顶：Picker("海报款式") 在 LazyVStack 第一项（页顶，PosterModule.swift:1411），分享 sheet 关闭后
        // 页面仍停在底部，屏外项不会实例化（Build #474 失败定论，与 #467 同类）。
        // Build #488 失败定论：swipeDown 滚回顶部后 App 60 秒以上不进入 idle，后续 waitForExistence 的快照评估
        // 逐次超时（重试 257.56s、288.62s，:125 报错），循环走不到第二次滑动；一次滑动只挪约 1 个版面，
        // 6 页海报靠滑动回顶不可靠。改为返回重进：页顶初载时选择器在树内（#474 t≈149s 已证 y=136 可见），断言不变。
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(baziWorkspace.waitForExistence(timeout: 30), "返回后八字排盘结果未出现")
        if posterEntry.waitForExistence(timeout: 30) {
            posterEntry.tap()
        } else {
            let altEntry = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "出预测单海报")).firstMatch
            XCTAssertTrue(altEntry.waitForExistence(timeout: 10), "海报入口未出现")
            altEntry.tap()
        }
        XCTAssertTrue(app.navigationBars["命盘海报"].waitForExistence(timeout: 30), "命盘海报页未出现")
        waitForPosterRender(app)
        let stylePicker = app.buttons["海报款式"]
        XCTAssertTrue(stylePicker.waitForExistence(timeout: 10), "海报款式选择器未出现")
        stylePicker.tap()
        let premiumOption = app.buttons["尊享预测单"]
        XCTAssertTrue(premiumOption.waitForExistence(timeout: 10), "尊享预测单选项未出现")
        premiumOption.tap()
        // 先等旧分享按钮消失（重渲染已开始），再等新渲染完成，避免误认旧图。
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: shareButton, handler: nil)
        wait(for: [gone], timeout: 10)
        waitForPosterRender(app)
        XCTAssertTrue(shareButton.exists, "尊享款式重渲染后分享按钮未出现")
        shot(app, name: "sheet-premium-yucedan")

        // 返回后依次截图紫微、合参业务入口（不深入填表流程）。
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let ziweiTab = app.tabBars.buttons["紫微"]
        XCTAssertTrue(ziweiTab.waitForExistence(timeout: 30), "紫微 tab 未出现")
        ziweiTab.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "workspace.ziwei").firstMatch.waitForExistence(timeout: 10), "紫微页未出现")
        shot(app, name: "entry-ziwei")
        let hecanTab = app.tabBars.buttons["合参"]
        XCTAssertTrue(hecanTab.waitForExistence(timeout: 30), "合参 tab 未出现")
        hecanTab.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "workspace.workbench").firstMatch.waitForExistence(timeout: 10), "合参页未出现")
        shot(app, name: "entry-hecan")
    }
}
