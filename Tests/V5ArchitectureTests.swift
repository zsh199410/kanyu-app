import XCTest
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
            for text in [p.ink, p.secondary, p.ornamentText] {
                for background in [p.paper, p.surface] {
                    let a = luminance(text), b = luminance(background)
                    XCTAssertGreaterThanOrEqual((max(a,b)+0.05)/(min(a,b)+0.05), 4.5, theme.title)
                }
            }
        }
    }
}
