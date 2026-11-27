import XCTest

/// Independent V5 contract. Original five-tab UI suites stay frozen and are not
/// silently adapted or treated as successful on this incompatible navigation.
final class V5NavigationUITests: XCTestCase {
    func testFourPrimaryEntriesAndThemeSurviveRelaunch() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-onboardingDone", "YES", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        let entries = [("首页", "v5.home"), ("测算", "v5.measure"), ("命书", "v5.reports"), ("档案", "v5.people")]
        for (title, identity) in entries {
            let tab = app.tabBars.buttons[title]
            XCTAssertTrue(tab.waitForExistence(timeout: 15), title)
            tab.tap()
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: identity).firstMatch.waitForExistence(timeout: 10), identity)
        }
        app.tabBars.buttons["首页"].tap()
        func appearance() {
            let menu = app.buttons["全局设置与功能"]
            XCTAssertTrue(menu.waitForExistence(timeout: 10))
            menu.tap()
            app.buttons["外观"].tap()
            XCTAssertTrue(app.navigationBars["四时外观"].waitForExistence(timeout: 10))
        }
        appearance()
        let night = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "玄夜星河 Pro")).firstMatch
        XCTAssertTrue(night.waitForExistence(timeout: 10))
        night.tap()
        XCTAssertTrue(app.navigationBars["四时外观"].exists, "Theme selection reset the current route")
        XCTAssertTrue(night.isSelected)
        app.terminate()
        app.launch()
        appearance()
        XCTAssertTrue(app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "玄夜星河 Pro")).firstMatch.isSelected)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "v5-night-theme-persistence-simulator"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
