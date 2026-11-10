import XCTest

final class NavigationSmokeTests: XCTestCase {
    func testCoreTabsAndLearningGuide() {
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
        for title in ["合参", "八字", "紫微", "奇门", "堪舆", "合参"] {
            let tab = app.tabBars.buttons[title]
            XCTAssertTrue(tab.waitForExistence(timeout: 30), title)
            tab.tap()
            if !tab.isSelected { tab.tap() }
            XCTAssertTrue(tab.isSelected, title)
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "tab-" + title
            shot.lifetime = .keepAlways
            add(shot)
        }
        let guide = app.buttons["home.learning"]
        for _ in 0..<5 {
            if guide.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(guide.isHittable)
        guide.tap()
        XCTAssertTrue(app.navigationBars["白话使用指南"].waitForExistence(timeout: 10))
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "learning-guide"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
