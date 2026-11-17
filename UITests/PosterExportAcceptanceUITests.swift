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
        let shareButton = app.buttons["分享海报"]
        XCTAssertTrue(shareButton.waitForExistence(timeout: 30), "分享海报按钮未出现（渲染未完成）")
        shot(app, name: "sheet-bazi-song")

        // 分享流程：点分享 → 系统分享 sheet 截图 → 关闭。
        shareButton.tap()
        XCTAssertTrue(app.sheets.firstMatch.waitForExistence(timeout: 15), "系统分享 sheet 未出现")
        shot(app, name: "share-bazi")
        let cancelButton = app.buttons["取消"]
        if cancelButton.waitForExistence(timeout: 5) {
            cancelButton.tap()
        } else {
            app.swipeDown()
        }

        // 尊享款式：切款式 Picker 到“尊享预测单”，等重渲染后截图。
        let stylePicker = app.buttons["海报款式"]
        XCTAssertTrue(stylePicker.waitForExistence(timeout: 10), "海报款式选择器未出现")
        stylePicker.tap()
        let premiumOption = app.buttons["尊享预测单"]
        XCTAssertTrue(premiumOption.waitForExistence(timeout: 10), "尊享预测单选项未出现")
        premiumOption.tap()
        XCTAssertTrue(shareButton.waitForExistence(timeout: 30), "尊享款式重渲染后分享按钮未出现")
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
