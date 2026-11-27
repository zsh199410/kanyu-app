import XCTest

/// Produces an actual saved publication through the public UI in the isolated
/// visual simulator. It deliberately remains there for the following theme captures.
final class V5ArchiveCreationUITests: XCTestCase {
    func testGenerateRealPublicationAndShowSavedWorkGallery() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-onboardingDone", "YES", "-v5.theme", "song", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        app.launch()
        let selected = app.buttons["v5.person.switch"]
        XCTAssertTrue(selected.waitForExistence(timeout: 10))
        XCTAssertTrue((selected.value as? String ?? "").contains("00000000-0000-4000-8000-000000005000"))
        app.tabBars.buttons["命书"].tap()
        let generateEntry = app.buttons["v5.library.generate"]
        XCTAssertTrue(generateEntry.waitForExistence(timeout: 10));generateEntry.tap()
        func reveal(_ element: XCUIElement) {
            for _ in 0..<10 {
                if element.exists && element.isHittable { return }
                app.scrollViews.firstMatch.swipeUp()
            }
            XCTFail("Public publication control is unreachable")
        }
        let generate = app.buttons["生成命书文件"]
        reveal(generate);generate.tap()
        XCTAssertTrue(app.buttons["分享命书文件"].waitForExistence(timeout: 30), "Actual ReportBuilder export did not complete")
        app.navigationBars.firstMatch.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["命书"].waitForExistence(timeout: 10))
        app.scrollViews.firstMatch.swipeDown()
        let preview = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "v5.work.preview.")).firstMatch
        reveal(preview)
        XCTAssertTrue(preview.exists && preview.isHittable, "The generated UUID-owned file must appear as a real saved work")
        let loading = app.progressIndicators["读取作品"].firstMatch
        XCTAssertTrue(loading.waitForNonExistence(timeout: 10), "Saved work preview remained loading")
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "v5-real-saved-publication-gallery";attachment.lifetime = .keepAlways;add(attachment)
        app.terminate()
    }
}
