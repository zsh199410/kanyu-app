import XCTest
import CoreGraphics

/// Additional acceptance target; existing Tests/UITests and golden fixtures remain unchanged.
/// The runner installs this build under a separate bundle ID with an empty simulator sandbox.
final class ProfileContextTests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "com.kanyu.survey.contextqa")
    private let required = ["astro", "yearly", "interpret", "chartdepth", "poster", "chenggu", "lucky", "annual"]
    private var caseName = ""

    override func setUpWithError() throws {
        continueAfterFailure = false
        addUIInterruptionMonitor(withDescription: "系统权限") { alert in
            for title in ["使用App时允许", "使用 App 时允许", "Allow While Using App", "允许一次", "Allow Once", "好", "OK"] {
                if alert.buttons[title].exists { alert.buttons[title].tap(); return true }
            }
            return false
        }
    }

    func testLightStandard() { lifecycle(theme: "light", size: "large") }
    func testDarkStandard() { lifecycle(theme: "dark", size: "large") }
    func testLightAccessibility() { lifecycle(theme: "light", size: "accessibility5") }
    func testDarkAccessibility() { lifecycle(theme: "dark", size: "accessibility5") }

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
        let bottom = app.keyboards.firstMatch.exists
            ? app.keyboards.firstMatch.frame.minY - 30 : frame.maxY - 125
        XCTAssertGreaterThan(bottom, top + 40)
        // Overlap the visible region on each scroll: large full-screen flicks can
        // skip short tool rows (e.g. 称骨) between two XCUITest snapshots.
        let travel = min(CGFloat(330), bottom - top)
        let x = frame.midX
        let startY = up ? bottom : top
        let endY = up ? bottom - travel : top + travel
        let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: x, dy: startY))
        let end = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: x, dy: endY))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    private func reveal(_ target: XCUIElement, up: Bool = true) {
        // Tool groups are not always visited in their on-screen order.
        // Sweep both directions; a forward-only scan can pass an earlier row
        // and never find it again, especially at accessibility text sizes.
        for direction in [up, !up] {
            for _ in 0..<28 {
                if target.exists && target.isHittable { return }
                drag(up: direction)
            }
        }
        if !(target.exists && target.isHittable) {
            snapshot("unreachable-" + target.identifier)
        }
        XCTAssertTrue(target.exists && target.isHittable, "Unreachable element: \(target)")
    }

    private func tap(_ identifier: String, up: Bool = true) {
        let target = element(identifier)
        reveal(target, up: up)
        target.tap()
    }

    private func back() {
        let button = app.navigationBars.firstMatch.buttons.element(boundBy: 0)
        XCTAssertTrue(button.waitForExistence(timeout: 10) && button.isHittable)
        button.tap()
    }

    private func homeTop() { reveal(element("workspace.workbench"), up: false) }

    private func allTools() {
        tap("home.alltools")
        XCTAssertTrue(app.navigationBars["全部工具"].waitForExistence(timeout: 10))
    }

    private func openTool(_ id: String) { tap("tools.open." + id) }

    private func assertMissing(_ id: String) {
        XCTAssertTrue(element("tool.missing." + id).waitForExistence(timeout: 10), id)
        XCTAssertTrue(app.staticTexts["请先选择人物档案"].exists, id)
        XCTAssertFalse(element("tool.context." + id).exists, id)
    }

    private func assertContext(_ name: String, birth: String) {
        let context = element("tool.context.astro")
        XCTAssertTrue(context.waitForExistence(timeout: 15))
        let receipt = context.value as? String ?? ""
        XCTAssertTrue(receipt.contains(name) && receipt.contains(birth), receipt)
        XCTAssertTrue(app.staticTexts[name + " · 星命合参"].waitForExistence(timeout: 10))
        XCTAssertFalse(element("tool.missing.astro").exists)
    }

    private func replace(_ field: XCUIElement, with text: String) {
        reveal(field)
        field.tap()
        let value = field.value as? String ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count))
        field.typeText(text)
    }

    @discardableResult
    private func fillPerson(_ name: String, year: String) -> String {
        XCTAssertTrue(app.navigationBars["新建人物"].waitForExistence(timeout: 10))
        let save = app.buttons["person.form.save"]
        let saveExists = save.waitForExistence(timeout: 10)
        if !saveExists || save.isEnabled { print(app.debugDescription) }
        XCTAssertTrue(saveExists)
        XCTAssertFalse(save.isEnabled)
        replace(app.textFields["person.form.name"], with: name)
        let dismissKeyboard = app.buttons["person.form.dismissKeyboard"]
        XCTAssertTrue(dismissKeyboard.waitForExistence(timeout: 10))
        dismissKeyboard.tap()
        let keyboardHidden = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.keyboards.firstMatch)
        XCTAssertEqual(XCTWaiter.wait(for: [keyboardHidden], timeout: 10), .completed)
        tap("birth.edit")
        XCTAssertTrue(app.navigationBars["选择出生时间"].waitForExistence(timeout: 10))
        replace(app.textFields["birth.year"], with: year)
        tap("birth.confirm")
        XCTAssertTrue(app.navigationBars["新建人物"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["person.form.save"].isEnabled)
        let label = app.buttons["birth.edit"].label
        let pattern = try! NSRegularExpression(pattern: "([0-9]{4})年([0-9]{1,2})月([0-9]{1,2})日 ([0-9]{2}):([0-9]{2})")
        let range = NSRange(label.startIndex..<label.endIndex, in: label)
        guard let match = pattern.firstMatch(in: label, range: range) else {
            XCTFail("Missing visible birth receipt: " + label); return ""
        }
        let values = (1...5).map { Int((label as NSString).substring(with: match.range(at: $0)))! }
        return String(format: "%04d-%02d-%02d %02d:%02d", values[0], values[1], values[2], values[3], values[4])
    }

    private func selectedHome(_ name: String) {
        homeTop()
        XCTAssertTrue(element("workspace.workbench").staticTexts[name].waitForExistence(timeout: 10))
    }

    private func openAstroFromHome() { tap("home.astro") }

    private func selectHome(_ name: String) {
        homeTop()
        app.buttons["切换命主"].tap()
        let picker = app.navigationBars["切换命主"]
        XCTAssertTrue(picker.waitForExistence(timeout: 10))
        let choice = app.buttons["选择命主：" + name]
        XCTAssertTrue(choice.waitForExistence(timeout: 10))
        // The row can exist while the medium sheet is still animating. Only tap
        // once it is hittable, then assert that the actual selection dismissed it.
        let hittable = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hittable == true"), object: choice)
        XCTAssertEqual(XCTWaiter.wait(for: [hittable], timeout: 10), .completed)
        snapshot("picker-before-" + name)
        choice.tap()
        let dismissed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: picker)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 10), .completed)
        selectedHome(name)
    }

    private func profileManager() {
        homeTop()
        app.buttons["个人中心与全局设置"].tap()
        XCTAssertTrue(app.navigationBars["档案与设置"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["全本机离线演算 · 零云端追踪"].exists)
        tap("profile.people")
        XCTAssertTrue(app.navigationBars["人物档案"].waitForExistence(timeout: 10))
    }

    private func deletePerson(_ name: String) {
        let row = app.buttons["人物档案：" + name]
        reveal(row)
        row.swipeLeft()
        let deletion = app.buttons.matching(identifier: "删除").allElementsBoundByIndex.first { $0.isHittable }
        XCTAssertNotNil(deletion)
        deletion?.tap()
        let confirmation = app.buttons.matching(identifier: "删除").allElementsBoundByIndex.first { $0.isHittable }
        XCTAssertNotNil(confirmation)
        confirmation?.tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: row)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 10), .completed)
    }

    private func lifecycle(theme: String, size: String) {
        caseName = theme + "-" + size
        app.launchArguments = ["-onboardingDone", "YES", "-uiStyle", theme,
                               "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN", "--context-acceptance"]
        app.launch()
        let environment = element("qa.context.environment")
        XCTAssertTrue(environment.waitForExistence(timeout: 30))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "QA环境 " + theme + " " + size), object: environment)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 15), .completed)
        let clock = element("qa.context.clock")
        XCTAssertTrue(clock.waitForExistence(timeout: 10))
        XCTAssertTrue(clock.label.hasPrefix("QA时钟 2000-1-1 8:0|946684800|"), clock.label)
        let clockAttachment = XCTAttachment(string: clock.label)
        clockAttachment.name = caseName + "-clock-receipt"
        clockAttachment.lifetime = .keepAlways
        add(clockAttachment)
        homeTop()
        snapshot("empty-home")
        openAstroFromHome()
        assertMissing("astro")
        tap("tool.createPerson")
        fillPerson("QA-CANCEL", year: "2002")
        snapshot("cancel-form")
        tap("person.form.cancel")
        assertMissing("astro")
        back()
        allTools()
        for id in required {
            openTool(id)
            assertMissing(id)
            snapshot("missing-" + id)
            back()
        }
        reveal(element("tools.open.learning"), up: false)
        for id in ["learning", "almanac", "compass"] {
            openTool(id)
            XCTAssertTrue(element("tool.independent." + id).waitForExistence(timeout: 15))
            XCTAssertFalse(app.staticTexts["请先选择人物档案"].exists)
            snapshot("independent-" + id)
            back()
        }
        back()
        homeTop()
        openAstroFromHome()
        tap("tool.createPerson")
        let birthA = fillPerson("QA-A", year: "2000")
        tap("person.form.save")
        assertContext("QA-A", birth: birthA)
        snapshot("saved-2000")
        back()
        homeTop()
        app.buttons["快速新建档案"].tap()
        let birthB = fillPerson("QA-B", year: "2001")
        tap("person.form.save")
        selectedHome("QA-A")
        app.terminate()
        app.launch()
        selectedHome("QA-A")
        selectHome("QA-B")
        app.terminate()
        app.launch()
        selectedHome("QA-B")
        openAstroFromHome()
        assertContext("QA-B", birth: birthB)
        let quick = app.buttons["调取命主：QA-A"]
        reveal(quick)
        quick.tap()
        assertContext("QA-A", birth: birthA)
        snapshot("quick-switch-2000")
        back()
        selectedHome("QA-A")
        profileManager()
        deletePerson("QA-A")
        back()
        XCTAssertTrue(app.staticTexts["QA-B"].waitForExistence(timeout: 10))
        back()
        selectedHome("QA-B")
        openAstroFromHome()
        assertContext("QA-B", birth: birthB)
        back()
        profileManager()
        deletePerson("QA-B")
        back()
        XCTAssertTrue(app.staticTexts["尚未建档"].waitForExistence(timeout: 10))
        snapshot("profile-empty-after-delete")
        back()
        homeTop()
        openAstroFromHome()
        assertMissing("astro")
        back()
        tap("home.recent.astro")
        assertMissing("astro")
        snapshot("recent-missing-after-delete")
        back()
        allTools()
        for id in required {
            openTool(id)
            assertMissing(id)
            back()
        }
    }
}
