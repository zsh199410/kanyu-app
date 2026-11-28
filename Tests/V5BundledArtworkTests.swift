import XCTest
import ImageIO
import UIKit
@testable import Kanyu

/// Real bundle resources, not generated test stand-ins or design-reference screenshots.
final class V5BundledArtworkTests: XCTestCase {
    func testAllSixtyOriginalRoleFilesAreBundledAndDecodeAtTheirDisplayBudget() throws {
        var names = Set<String>()
        for theme in V5Theme.allCases {
            XCTAssertTrue(V5ArtworkRegistry.missing(theme: theme).isEmpty, theme.rawValue)
            for role in V5ArtworkRole.allCases {
                let url = try XCTUnwrap(V5ArtworkRegistry.url(role, theme: theme))
                XCTAssertTrue(names.insert(url.lastPathComponent).inserted)
                let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary))
                XCTAssertEqual(CGImageSourceGetStatus(source), .statusComplete)
                let image = try XCTUnwrap(V5ArtworkRegistry.image(role, theme: theme)?.cgImage)
                XCTAssertEqual(image.colorSpace?.model, .rgb)
                XCTAssertLessThanOrEqual(max(image.width, image.height), role.displayPixelSize)
                XCTAssertGreaterThan(image.width, 0); XCTAssertGreaterThan(image.height, 0)
                XCTAssertLessThanOrEqual(V5ArtworkStore.shared.cachedBytes, 32 * 1024 * 1024)
            }
        }
        XCTAssertEqual(names.count, 60)
    }
    func testFormalPosterArtworkUsesImmutableFamilySelection() {
        XCTAssertEqual(V5PosterArtworkTheme.theme(for: .bazi), .song)
        XCTAssertEqual(V5PosterArtworkTheme.theme(for: .ziwei), .night)
        XCTAssertEqual(V5PosterArtworkTheme.theme(for: .palm), .celadon)
        XCTAssertEqual(V5PosterArtworkTheme.theme(for: .premium), .collection)
    }
}
