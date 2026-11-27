import XCTest

/// Exercises the real PDF and system share lifecycle, with no export bypass.
final class V5PublicationSharingUITests: XCTestCase {
    func testRealPublicationShareReturnsToTheSameOwner() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-onboardingDone", "YES", "-v5.theme", "song", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        app.launch()
        defer { app.terminate() }
        let selected = app.buttons["v5.person.switch"]
        XCTAssertTrue(selected.waitForExistence(timeout: 10))
        let owner = try XCTUnwrap(selected.value as? String)
        XCTAssertTrue(owner.contains("00000000-0000-4000-8000-000000005000"))
        app.tabBars.buttons["命书"].tap()
        let entry = app.buttons["v5.library.generate"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10)); entry.tap()
        let generate = app.buttons["生成命书文件"]
        for _ in 0..<10 {
            if generate.exists && generate.isHittable { break }
            app.scrollViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(generate.exists && generate.isHittable)
        generate.tap()
        let share = app.buttons["分享命书文件"]
        XCTAssertTrue(share.waitForExistence(timeout: 30))
        XCTAssertTrue(share.isHittable); share.tap()
        // iOS exposes the actual activity controller as a popover or a sheet.
        let popover = app.popovers.firstMatch
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(popover.waitForExistence(timeout: 15) || sheet.waitForExistence(timeout: 2), "Actual system PDF sharing did not present")
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "v5-real-publication-system-share"; attachment.lifetime = .keepAlways; add(attachment)
        for _ in 0..<2 {
            if !popover.exists && !sheet.exists { break }
            if app.buttons["取消"].exists { app.buttons["取消"].tap() }
            else if app.otherElements["PopoverDismissRegion"].firstMatch.exists { app.otherElements["PopoverDismissRegion"].firstMatch.tap() }
            else if popover.exists { popover.swipeDown() }
            else { sheet.swipeDown() }
        }
        XCTAssertTrue(popover.waitForNonExistence(timeout: 5))
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 5))
        XCTAssertTrue(share.exists && share.isHittable, "Share dismissal must restore the real publication page")
        app.tabBars.buttons["首页"].tap()
        XCTAssertTrue(selected.waitForExistence(timeout: 10))
        XCTAssertEqual(selected.value as? String, owner, "Sharing must not replace the selected person")
    }
}
