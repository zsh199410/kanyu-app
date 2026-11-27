import XCTest

/// Actual application screenshots. Fixture files are installed only into a fresh CI
/// simulator's standard sandbox; there is no application seeding flag or alternate UI.
final class V5VisualAcceptanceTests: XCTestCase {
    func testFourThemesOnFixedPersonAndNativeScreens() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let owner = "00000000-0000-4000-8000-000000005000"
        func screenshot(_ name: String) {
            let a = XCTAttachment(screenshot: app.screenshot());a.name = name;a.lifetime = .keepAlways;add(a)
        }
        func frame(_ id: String) -> [String: Double]? {
            let element = app.descendants(matching: .any).matching(identifier: id).firstMatch
            guard element.exists else { return nil }
            let f = element.frame
            return ["x": f.minX, "y": f.minY, "width": f.width, "height": f.height]
        }
        for theme in ["song", "night", "celadon", "collection"] {
            app.launchArguments = ["-onboardingDone", "YES", "-v5.theme", theme,
                "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN",
                "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
            app.launch()
            let selected = app.buttons["v5.person.switch"]
            XCTAssertTrue(selected.waitForExistence(timeout: 10))
            XCTAssertTrue((selected.value as? String ?? "").contains(owner))
            screenshot("v5-visual-" + theme + "-home")
            let layout: [String: Any] = ["theme": theme, "fixtureOwner": owner,
                "screen": ["width": app.frame.width, "height": app.frame.height],
                "person": frame("v5.person.switch") ?? [:],
                "baziEntry": frame("v5.home.entry.bazi") ?? [:],
                "surveyEntry": frame("v5.home.entry.survey") ?? [:],
                "visualApproval": false, "metricStatus": "Awaiting GPT reviewed bounds; no 98% claim"]
            let receipt = XCTAttachment(data: try JSONSerialization.data(withJSONObject: layout, options: [.prettyPrinted, .sortedKeys]), uniformTypeIdentifier: "public.json")
            receipt.name = "v5-layout-" + theme;receipt.lifetime = .keepAlways;add(receipt)
            for title in ["测算", "命书", "档案"] {
                let tab = app.tabBars.buttons[title];XCTAssertTrue(tab.exists);tab.tap()
                XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 10))
                screenshot("v5-visual-" + theme + "-" + ["测算":"measure", "命书":"library", "档案":"profiles"][title]!)
            }
            app.tabBars.buttons["测算"].tap()
            for kind in ["bazi", "ziwei"] {
                let entry = app.buttons["v5.measure." + kind]
                XCTAssertTrue(entry.waitForExistence(timeout: 10));entry.tap()
                let result = app.staticTexts["v5." + kind + ".result.owner"]
                XCTAssertTrue(result.waitForExistence(timeout: 10));XCTAssertEqual(result.value as? String, owner)
                screenshot("v5-visual-" + theme + "-" + kind)
                app.navigationBars.firstMatch.buttons.element(boundBy: 0).tap()
            }
            app.terminate()
        }
    }
}
