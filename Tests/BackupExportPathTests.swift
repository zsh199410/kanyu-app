import XCTest
@testable import Kanyu

final class BackupExportPathTests: XCTestCase {
    func testSameDayExportsHaveDistinctZipPaths() {
        let root = FileManager.default.temporaryDirectory
        let first = BackupExportPath.zipURL(in: root, date: "2026-11-11")
        let second = BackupExportPath.zipURL(in: root, date: "2026-11-11")
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(first.pathExtension, "zip")
        XCTAssertEqual(second.pathExtension, "zip")
        XCTAssertEqual(first.deletingLastPathComponent(), root)
    }

    func testStagingDirectoriesAreUniqueAndSeparateFromZip() {
        let root = FileManager.default.temporaryDirectory
        let first = BackupExportPath.stagingDirectory(in: root)
        let second = BackupExportPath.stagingDirectory(in: root)
        let archive = BackupExportPath.zipURL(in: root, date: "2026-11-11")
        XCTAssertNotEqual(first, second)
        XCTAssertNotEqual(first, archive)
        XCTAssertNotEqual(second, archive)
    }

    func testCreatingNewArchiveDoesNotOverwritePreviousArchive() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("backup-export-regression-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let first = BackupExportPath.zipURL(in: root, date: "2026-11-11")
        let second = BackupExportPath.zipURL(in: root, date: "2026-11-11")
        let firstData = Data([0x50, 0x4b, 0x03, 0x04, 0x01])
        let secondData = Data([0x50, 0x4b, 0x03, 0x04, 0x02])
        try firstData.write(to: first, options: .atomic)
        try secondData.write(to: second, options: .atomic)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(try Data(contentsOf: first), firstData)
        XCTAssertEqual(try Data(contentsOf: second), secondData)
    }
}
