import XCTest
import UIKit
@testable import Kanyu

@MainActor final class V5BottomNavigationTests: XCTestCase {
    func testVisibleNativeControlsDeliverSelectionAndExposeSelectedState() throws {
        let bar = V5BottomNavigationBar()
        bar.frame = CGRect(x: 0, y: 0, width: 390, height: 60)
        var delivered: Int?
        bar.update(selection: 0, theme: .song) { delivered = $0 }
        bar.layoutIfNeeded()
        let controls = try XCTUnwrap(bar.accessibilityElements as? [UIButton])
        XCTAssertEqual(controls.count, 4)
        XCTAssertFalse(bar.isAccessibilityElement, "Navigation must expose actual controls, not an opaque accessibility stand-in")
        for control in controls {
            XCTAssertFalse(control.isHidden)
            XCTAssertGreaterThanOrEqual(control.frame.width, 48)
            XCTAssertGreaterThanOrEqual(control.frame.height, 48)
            XCTAssertTrue(control.accessibilityTraits.contains(.button))
        }
        controls[2].sendActions(for: .touchUpInside)
        XCTAssertEqual(delivered, 2)
        bar.update(selection: 2, theme: .song) { delivered = $0 }
        XCTAssertTrue(controls[2].isSelected)
        XCTAssertTrue(controls[2].accessibilityTraits.contains(.selected))
        XCTAssertFalse(controls[0].isSelected)
    }
    func testThemeRefreshPreservesRealButtonActionsAtAccessibilityHeight() throws {
        let bar = V5BottomNavigationBar()
        bar.frame = CGRect(x: 0, y: 0, width: 320, height: 94)
        var delivered: Int?
        for theme in V5Theme.allCases {
            bar.update(selection: 3, theme: theme) { delivered = $0 }
            bar.layoutIfNeeded()
            let controls = try XCTUnwrap(bar.accessibilityElements as? [UIButton])
            XCTAssertEqual(controls.filter(\.isSelected).count, 1)
            XCTAssertTrue(controls[3].isSelected)
            XCTAssertGreaterThanOrEqual(controls[3].frame.height, 90)
            controls[1].sendActions(for: .touchUpInside)
            XCTAssertEqual(delivered, 1)
            delivered = nil
        }
    }
}
