import XCTest
import CoreGraphics

/// Run with the dedicated context acceptance runner: a separately installed bundle and empty sandbox.
/// The runner sets the simulator content size; the receipt below verifies the actual environment.
final class PhysiognomyGuideTests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "com.kanyu.survey.contextqa")
    private var caseName = ""

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLightStandard() { guides(theme: "light", size: "large") }
    func testDarkStandard() { guides(theme: "dark", size: "large") }
    func testLightAccessibility() { guides(theme: "light", size: "accessibility5") }
    func testDarkAccessibility() { guides(theme: "dark", size: "accessibility5") }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func snapshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = caseName + "-" + name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func drag(up: Bool) {
        let frame = app.frame
        let top = max(frame.minY + 125, app.navigationBars.firstMatch.frame.maxY + 35)
        let bottom = frame.maxY - 125
        XCTAssertGreaterThan(bottom, top + 40)
        let start = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: frame.midX, dy: up ? bottom : top))
        let end = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: frame.midX, dy: up ? top : bottom))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    private func reveal(_ target: XCUIElement, up: Bool = true) {
        for _ in 0..<32 {
            if target.exists && target.isHittable { return }
            drag(up: up)
        }
        XCTFail("Unreachable element: \(target)")
    }

    private func tap(_ identifier: String, up: Bool = true) {
        let target = element(identifier)
        reveal(target, up: up)
        XCTAssertTrue(target.exists && target.isHittable)
        target.tap()
    }

    private func assertExplanation(_ title: String) {
        let heading = element("physiognomy.explanation.title")
        XCTAssertTrue(heading.waitForExistence(timeout: 10))
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", title), object: heading)
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 10), .completed)
        reveal(heading)
        XCTAssertEqual(heading.label, title)
    }

    private func selectChapter(_ title: String) {
        tap("physiognomy.guide.group", up: false)
        let option = app.buttons.matching(identifier: title).firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 10) && option.isHittable)
        option.tap()
    }

    private func back() {
        let button = app.navigationBars.firstMatch.buttons.element(boundBy: 0)
        XCTAssertTrue(button.waitForExistence(timeout: 10) && button.isHittable)
        button.tap()
    }

    private func exerciseGuide(kind: String, title: String,
                               firstID: String, firstTitle: String,
                               secondID: String, secondTitle: String,
                               chapter: String, chapterID: String, chapterTitle: String) {
        tap("physiognomy.open." + kind)
        XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["请先选择人物档案"].exists)
        // Use the real illustration marker's accessible label, rather than a coordinate tap.
        let marker = app.buttons["图中第2处，" + secondTitle]
        reveal(marker)
        XCTAssertTrue(marker.isHittable)
        snapshot(kind + "-illustration")
        marker.tap()
        assertExplanation(secondTitle)
        snapshot(kind + "-marker-selected")
        tap("physiognomy.legend." + firstID)
        assertExplanation(firstTitle)
        tap("physiognomy.legend." + secondID)
        assertExplanation(secondTitle)
        snapshot(kind + "-legend-selected")
        selectChapter(chapter)
        tap("physiognomy.legend." + chapterID)
        assertExplanation(chapterTitle)
        snapshot(kind + "-chapter-selected")
        back()
        XCTAssertTrue(app.navigationBars["手相面相"].waitForExistence(timeout: 10))
    }

    private func guides(theme: String, size: String) {
        caseName = theme + "-" + size
        app.launchArguments = ["-onboardingDone", "YES", "-uiStyle", theme,
                               "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN", "--context-acceptance"]
        app.launch()
        let environment = element("qa.context.environment")
        XCTAssertTrue(environment.waitForExistence(timeout: 30))
        let ready = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", "QA环境 " + theme + " " + size), object: environment)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 15), .completed)
        reveal(element("workspace.workbench"), up: false)
        XCTAssertTrue(app.staticTexts["添加第一位家人或命主档案"].waitForExistence(timeout: 10),
                      "The guide suite requires the actual empty-profile home state.")
        XCTAssertFalse(app.buttons["切换命主"].exists, "No person switcher may appear before creating a profile.")
        snapshot("empty-home")
        // PalmHomeView is a real home bento link; AllToolsData has no palm tool entry.
        let palm = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "手相面相")).firstMatch
        reveal(palm)
        palm.tap()
        XCTAssertTrue(app.navigationBars["手相面相"].waitForExistence(timeout: 10))
        exerciseGuide(kind: "hand", title: "道家手相图解",
                      firstID: "hand.line.life", firstTitle: "生命线（传统名称）",
                      secondID: "hand.line.head", secondTitle: "智慧线（头线，传统名称）",
                      chapter: "其他传统线名", chapterID: "hand.line.career", chapterTitle: "事业线（命运线，传统名称）")
        exerciseGuide(kind: "face", title: "面相十二宫图解",
                      firstID: "face.palace.life", firstTitle: "命宫（印堂附近）",
                      secondID: "face.palace.wealth", secondTitle: "财帛宫",
                      chapter: "三停", chapterID: "face.section.upper", chapterTitle: "上停")
        back()
        reveal(element("workspace.workbench"), up: false)
        XCTAssertTrue(app.staticTexts["添加第一位家人或命主档案"].exists)
        XCTAssertFalse(app.buttons["切换命主"].exists)
        snapshot("empty-home-after-guides")
        app.terminate()
    }
}
