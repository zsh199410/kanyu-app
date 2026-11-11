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
    func testRepeatedExportsPreserveEarlierFileContents() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("palm-poster-regression-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let recordID = UUID()
        let first = PalmPosterTemporaryFile.url(for: recordID, directory: directory)
        let second = PalmPosterTemporaryFile.url(for: recordID, directory: directory)
        let firstPNG = Data([0x89, 0x50, 0x4e, 0x47, 0x01])
        let secondPNG = Data([0x89, 0x50, 0x4e, 0x47, 0x02])
        try firstPNG.write(to: first, options: .atomic)
        try secondPNG.write(to: second, options: .atomic)

        XCTAssertNotEqual(first, second)
        XCTAssertEqual(try Data(contentsOf: first), firstPNG)
        XCTAssertEqual(try Data(contentsOf: second), secondPNG)
    }

    func testWriteToMissingDirectoryFailsWithoutCreatingPoster() {
        let missingDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("palm-poster-missing-\(UUID().uuidString)", isDirectory: true)
        let target = PalmPosterTemporaryFile.url(for: UUID(), directory: missingDirectory)
        XCTAssertThrowsError(try Data([0x01, 0x02]).write(to: target, options: .atomic))
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: missingDirectory.path))
    }

    func testGeneratedNameContainsNoPathSeparatorsFromRecordID() {
        let url = PalmPosterTemporaryFile.url(for: UUID())
        XCTAssertFalse(url.lastPathComponent.contains("/"))
        XCTAssertFalse(url.lastPathComponent.contains("\\"))
        XCTAssertEqual(url.pathExtension, "png")
    }

}
