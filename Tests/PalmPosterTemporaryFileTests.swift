import XCTest
@testable import Kanyu

final class PalmPosterTemporaryFileTests: XCTestCase {
    func testEachRenderGetsUniquePathForSameRecord() {
        let id = UUID()
        let directory = URL(fileURLWithPath: "/tmp/palm-poster-test", isDirectory: true)
        let first = PalmPosterTemporaryFile.url(for: id, directory: directory)
        let second = PalmPosterTemporaryFile.url(for: id, directory: directory)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(first.deletingLastPathComponent(), directory)
        XCTAssertEqual(second.deletingLastPathComponent(), directory)
        XCTAssertTrue(first.lastPathComponent.hasPrefix("palm-poster-\(id.uuidString)-"))
        XCTAssertEqual(first.pathExtension, "png")
    }

    func testDifferentRecordsNeverReuseSameTemporaryName() {
        let first = PalmPosterTemporaryFile.url(for: UUID())
        let second = PalmPosterTemporaryFile.url(for: UUID())
        XCTAssertNotEqual(first.lastPathComponent, second.lastPathComponent)
    }
}
