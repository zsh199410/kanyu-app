import XCTest
import SwiftUI
import UIKit
@testable import Kanyu

final class V5ArchitectureTests: XCTestCase {
    @MainActor func testLegacyToolSelectionCannotSelectNonexistentV5Tab() {
        let router = V5Router()
        router.tab = 1
        router.legacySelection.wrappedValue = 4
        XCTAssertEqual(router.tab, 1)
        XCTAssertEqual(router.path.wrappedValue, [.survey])
        router.legacySelection.wrappedValue = 2
        XCTAssertEqual(router.path.wrappedValue, [.survey, .ziwei])
    }
    @MainActor func testEachPrimaryTabKeepsItsOwnNavigationPath() {
        let router = V5Router()
        router.open(.bazi)
        router.tab = 2
        XCTAssertTrue(router.path.wrappedValue.isEmpty)
        router.open(.tool("poster"))
        router.tab = 0
        XCTAssertEqual(router.path.wrappedValue, [.bazi])
        router.tab = 2
        XCTAssertEqual(router.path.wrappedValue, [.tool("poster")])
    }
    @MainActor func testCatalogRefreshesThemeWithoutChangingToolIdentity() throws {
        let store = V5ThemeStore.shared
        let original = store.theme
        let saved = UserDefaults.standard.object(forKey: "v5.theme")
        defer {
            store.select(original)
            if let saved { UserDefaults.standard.set(saved, forKey: "v5.theme") }
            else { UserDefaults.standard.removeObject(forKey: "v5.theme") }
        }
        store.select(.song)
        let first = AllToolsData.allItems
        store.select(.celadon)
        let second = AllToolsData.allItems
        XCTAssertEqual(first.map(\.id), second.map(\.id))
        let light = try XCTUnwrap(first.first(where: { $0.id == "learning" }))
        let dark = try XCTUnwrap(second.first(where: { $0.id == "learning" }))
        let traits = UITraitCollection(userInterfaceStyle: .light)
        XCTAssertNotEqual(UIColor(light.color).resolvedColor(with: traits), UIColor(dark.color).resolvedColor(with: traits), "Catalog cached the old theme colors")
    }
    func testAllThemesHaveReadableSemanticText() {
        func luminance(_ hex: UInt32) -> Double {
            let values = [16, 8, 0].map { shift -> Double in
                let v = Double((hex >> shift) & 255) / 255
                return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
            }
            return values[0] * 0.2126 + values[1] * 0.7152 + values[2] * 0.0722
        }
        for theme in V5Theme.allCases {
            let p = theme.palette
            for text in [p.ink, p.secondary, p.ornamentText, p.success, p.failure] {
                for background in [p.paper, p.surface] {
                    let a = luminance(text), b = luminance(background)
                    XCTAssertGreaterThanOrEqual((max(a,b)+0.05)/(min(a,b)+0.05), 4.5, theme.title)
                }
            }
        }
    }
}
