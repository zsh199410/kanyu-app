import XCTest

/// Real four-tab navigation, formal rasterization, Photos write and activity controller.
/// Fixture identity is installed by CI through the normal people.json format, never a launch bypass.
final class V5PosterSharingUITests: XCTestCase {
    func testFormalBaziPhotoAndSharePreserveSelectedOwner() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-onboardingDone", "YES", "-v5.theme", "song", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        app.launch(); defer { app.terminate() }
        let selected = app.buttons["v5.person.switch"]
        XCTAssertTrue(selected.waitForExistence(timeout: 10))
        let owner = try XCTUnwrap(selected.value as? String)
        XCTAssertTrue(owner.contains("00000000-0000-4000-8000-000000005000"))
        app.tabBars.buttons["命书"].tap()
        let gallery = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "海报设计")).firstMatch
        for _ in 0..<8 {
            if gallery.exists && gallery.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(gallery.exists && gallery.isHittable); gallery.tap()
        let bazi = app.buttons["poster.gallery.open.bazi"]
        for _ in 0..<8 {
            if bazi.exists && bazi.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(bazi.exists && bazi.isHittable); bazi.tap()
        let personal = app.buttons["poster.gallery.dynamic.bazi"]
        XCTAssertTrue(personal.waitForExistence(timeout: 10)); personal.tap()
        let export = app.buttons["poster.dynamic.export"]
        let ready = NSPredicate(format: "exists == true AND enabled == true")
        expectation(for: ready, evaluatedWith: export)
        waitForExpectations(timeout: 30)
        XCTAssertFalse(app.otherElements["poster.dynamic.unavailable"].exists)
        let photo = app.buttons["v5.poster.savePhoto"]
        XCTAssertTrue(photo.exists && photo.isHittable); photo.tap()
        let receipt = app.staticTexts["v5.poster.photoReceipt"]
        XCTAssertTrue(receipt.waitForExistence(timeout: 30))
        XCTAssertEqual(receipt.label, "已存入相册", "Photo permission is pre-granted by CI; a real Photos completion must succeed")
        export.tap()
        let popover = app.popovers.firstMatch, sheet = app.sheets.firstMatch
        XCTAssertTrue(popover.waitForExistence(timeout: 15) || sheet.waitForExistence(timeout: 2))
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "v5-formal-bazi-real-system-share"; shot.lifetime = .keepAlways; add(shot)
        for _ in 0..<2 {
            if !popover.exists && !sheet.exists { break }
            if app.buttons["取消"].exists { app.buttons["取消"].tap() }
            else if app.otherElements["PopoverDismissRegion"].firstMatch.exists { app.otherElements["PopoverDismissRegion"].firstMatch.tap() }
            else if popover.exists { popover.swipeDown() }
            else { sheet.swipeDown() }
        }
        XCTAssertTrue(popover.waitForNonExistence(timeout: 5))
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 5))
        XCTAssertTrue(export.exists && export.isEnabled)
        app.tabBars.buttons["首页"].tap()
        XCTAssertTrue(selected.waitForExistence(timeout: 10))
        XCTAssertEqual(selected.value as? String, owner)
    }
}
