import XCTest

/// Fixed-person CI fixture is installed into a fresh simulator by v5-visual.yml.
/// No application seeding path or alternative UI exists.
final class V5HomeQuickCreateUITests: XCTestCase {
    func testQuickCreateRemainsReachableAfterHomeScroll() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-onboardingDone", "YES", "-v5.theme", "song",
            "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        app.launch()
        let selector = app.buttons["v5.person.switch"]
        XCTAssertTrue(selector.waitForExistence(timeout: 10))
        XCTAssertTrue((selector.value as? String ?? "").contains("00000000-0000-4000-8000-000000005000"))
        let scroll = app.scrollViews["home.scroll"]
        XCTAssertTrue(scroll.exists)
        scroll.swipeUp()
        // A partially visible card must not make its covered/offscreen controls
        // appear usable. The frequent create action must remain truly hittable.
        let create = app.buttons["快速新建档案"]
        XCTAssertTrue(create.exists && create.isHittable)
        create.tap()
        XCTAssertTrue(app.navigationBars["新建人物"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.textFields["person.form.name"].exists)
        XCTAssertFalse(app.buttons["person.form.save"].isEnabled)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "v5-quick-create-after-home-scroll";shot.lifetime = .keepAlways;add(shot)
        app.buttons["person.form.cancel"].tap()
        XCTAssertTrue(app.navigationBars["首页"].waitForExistence(timeout: 10))
        scroll.swipeDown()
        XCTAssertTrue(selector.waitForExistence(timeout: 10))
        XCTAssertTrue((selector.value as? String ?? "").contains("00000000-0000-4000-8000-000000005000"), "Cancelling creation must preserve the actual selected UUID")
    }
}
