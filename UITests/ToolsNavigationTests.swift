// 全部工具导航 UI 回归（XCUITest，风险点 f）：工具列表可打开、独立工具可进入并可返回。
// 已有 UITests/NavigationSmokeTests 只覆盖 5 个 Tab 与白话指南；本文件补工具列表路径。
// 注意：无人物档案时用盘工具会显示伪造的当前时刻盘（Issue #14，PR #15 未合并），
// 故本文件只进独立工具（万年历，不依赖人物），用盘工具的守门测试在 #15 合并后补。
import XCTest

final class ToolsNavigationTests: XCTestCase {
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-onboardingDone", "YES", "-AppleLanguages", "(zh-Hans)"]
        addUIInterruptionMonitor(withDescription: "系统权限") { alert in
            for title in ["使用App时允许", "使用 App 时允许", "Allow While Using App", "允许一次", "Allow Once", "好", "OK"] {
                if alert.buttons[title].exists { alert.buttons[title].tap(); return true }
            }
            return false
        }
        app.launch()
        return app
    }

    private func openToolsList(_ app: XCUIApplication) {
        let homeTab = app.tabBars.buttons["合参"]
        XCTAssertTrue(homeTab.waitForExistence(timeout: 30), "合参 Tab 应存在")
        homeTab.tap()
        let link = app.staticTexts["全部工具"]
        for _ in 0..<5 {
            if link.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(link.waitForExistence(timeout: 10), "首页应有“全部工具”入口")
        link.tap()
        XCTAssertTrue(app.navigationBars["全部工具"].waitForExistence(timeout: 10), "应进入全部工具页")
    }

    func testToolsListOpensAlmanacAndReturns() {
        continueAfterFailure = false
        let app = launch()
        openToolsList(app)
        let almanac = app.staticTexts["万年历"]
        for _ in 0..<8 {
            if almanac.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(almanac.waitForExistence(timeout: 10), "工具列表应含“万年历”")
        almanac.tap()
        XCTAssertTrue(app.navigationBars["今日黄历"].waitForExistence(timeout: 10), "万年历页导航栏应为“今日黄历”")
        let back = app.navigationBars["今日黄历"].buttons.element(boundBy: 0)
        XCTAssertTrue(back.waitForExistence(timeout: 5), "万年历页应有返回按钮")
        back.tap()
        XCTAssertTrue(app.navigationBars["全部工具"].waitForExistence(timeout: 10), "返回后应回到全部工具页")
    }

    func testToolsListShowsGroupFilters() {
        continueAfterFailure = false
        let app = launch()
        openToolsList(app)
        for title in ["排盘", "历法择吉", "知识库", "工具"] {
            XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 10), "分组筛选应含“\(title)”")
        }
    }
}
