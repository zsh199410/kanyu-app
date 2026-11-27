import XCTest

/// Real form input and persisted UUIDs; no launch-time seed or production bypass.
final class V5PersonLifecycleUITests: XCTestCase {
    func testSameNameSelectionChartOwnershipAndRelaunch() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-onboardingDone", "YES", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        app.tabBars.buttons["档案"].tap()
        let name = "归属回归" + UUID().uuidString.prefix(6)
        func create() {
            let button = app.buttons["v5.profile.create"]
            XCTAssertTrue(button.waitForExistence(timeout: 10))
            button.tap()
            let field = app.textFields["person.form.name"]
            XCTAssertTrue(field.waitForExistence(timeout: 10))
            field.tap(); field.typeText(name)
            app.buttons["person.form.save"].tap()
            XCTAssertTrue(button.waitForExistence(timeout: 10))
        }
        func reveal(_ element: XCUIElement) {
            let scroll = app.scrollViews.firstMatch
            for upward in [true, false] {
                for _ in 0..<12 {
                    if element.exists && element.isHittable { return }
                    if upward { scroll.swipeUp() } else { scroll.swipeDown() }
                }
            }
            XCTFail("Profile control unreachable: \(element.identifier)")
        }
        create()
        // Filter via the public search; only UUIDs belonging to this test can be selected.
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap(); search.typeText(name + "\n")
        let identities = app.staticTexts.matching(identifier: "v5.profile.uuid")
        XCTAssertTrue(identities.firstMatch.waitForExistence(timeout: 10))
        let first = try XCTUnwrap(identities.firstMatch.value as? String)
        create()
        var found: String?
        for _ in 0..<12 {
            found = identities.allElementsBoundByIndex.compactMap { $0.value as? String }.first { $0 != first }
            if found != nil { break }
            app.scrollViews.firstMatch.swipeUp()
        }
        let second = try XCTUnwrap(found, "Second same-name profile did not receive a distinct persisted UUID")
        XCTAssertNotEqual(first, second)
        for id in [second, first] {
            let select = app.buttons["v5.profile.select." + id]
            if !select.isHittable { app.scrollViews.firstMatch.swipeDown() }
            reveal(select)
            if select.isEnabled { select.tap() }
            app.tabBars.buttons["测算"].tap()
            let owner = app.staticTexts["v5.calculation.owner"]
            XCTAssertTrue(owner.waitForExistence(timeout: 10))
            XCTAssertEqual(owner.value as? String, id)
            for kind in ["bazi", "ziwei"] {
                let entry = app.buttons["v5.measure." + kind]
                reveal(entry); entry.tap()
                let resultOwner = app.staticTexts["v5." + kind + ".result.owner"]
                XCTAssertTrue(resultOwner.waitForExistence(timeout: 10), "Actual chart did not finish loading")
                XCTAssertEqual(resultOwner.value as? String, id, "Rendered chart belongs to a different profile")
                app.navigationBars.firstMatch.buttons.element(boundBy: 0).tap()
            }
            app.tabBars.buttons["档案"].tap()
        }
        app.terminate(); app.launch()
        app.tabBars.buttons["测算"].tap()
        let owner = app.staticTexts["v5.calculation.owner"]
        XCTAssertTrue(owner.waitForExistence(timeout: 10))
        XCTAssertEqual(owner.value as? String, first)
        // Delete only the two UUIDs created by this test, through the public UI.
        app.tabBars.buttons["档案"].tap()
        for id in [first, second] {
            let manage = app.buttons["v5.profile.manage." + id]
            app.scrollViews.firstMatch.swipeDown()
            reveal(manage); manage.tap()
            app.buttons["删除档案与归属记录"].tap()
            app.alerts["删除人物档案？"].buttons["确认删除"].tap()
            XCTAssertTrue(manage.waitForNonExistence(timeout: 10))
        }
    }
}
