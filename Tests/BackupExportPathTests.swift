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
    func testRestoreAttemptsUseIndependentDirectories() {
        let root = FileManager.default.temporaryDirectory
        let first = BackupExportPath.restoreDirectory(in: root)
        let second = BackupExportPath.restoreDirectory(in: root)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(first.deletingLastPathComponent(), root)
        XCTAssertEqual(second.deletingLastPathComponent(), root)
        XCTAssertTrue(first.lastPathComponent.hasPrefix("Kanyu-Restore-"))
    }

    func testFailedUnzipCleanupDoesNotDeleteAnotherRestoreDirectory() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("restore-isolation-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let first = BackupExportPath.restoreDirectory(in: root)
        let second = BackupExportPath.restoreDirectory(in: root)
        try fm.createDirectory(at: first, withIntermediateDirectories: true)
        try fm.createDirectory(at: second, withIntermediateDirectories: true)
        let marker = second.appendingPathComponent("marker.txt")
        try Data("preserve".utf8).write(to: marker)
        try fm.removeItem(at: first)
        XCTAssertFalse(fm.fileExists(atPath: first.path))
        XCTAssertEqual(try Data(contentsOf: marker), Data("preserve".utf8))
    }

    func testEmptyOrManifestOnlyBackupIsNotRestorable() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("restore-empty-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        XCTAssertFalse(BackupExportPath.containsRestorableData(in: root))
        try Data("{}".utf8).write(to: root.appendingPathComponent("manifest.json"))
        XCTAssertFalse(BackupExportPath.containsRestorableData(in: root))
    }

    func testDirectoryNamedLikeBackupDataIsNotRestorable() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("restore-directory-spoof-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        try fm.createDirectory(at: root.appendingPathComponent("people.json"), withIntermediateDirectories: true)
        XCTAssertFalse(BackupExportPath.containsRestorableData(in: root))
    }

    func testSymlinkNamedLikeBackupDataIsNotRestorable() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("restore-symlink-spoof-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let external = fm.temporaryDirectory.appendingPathComponent("restore-external-\(UUID().uuidString).json")
        try Data("[]".utf8).write(to: external, options: .atomic)
        defer { try? fm.removeItem(at: external) }
        try fm.createSymbolicLink(at: root.appendingPathComponent("people.json"), withDestinationURL: external)
        XCTAssertFalse(BackupExportPath.containsRestorableData(in: root))
        XCTAssertEqual(try Data(contentsOf: external), Data("[]".utf8))
    }

    func testRecognizedBackupDataCanBeRestored() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("restore-valid-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        try Data("[]".utf8).write(to: root.appendingPathComponent("people.json"))
        XCTAssertTrue(BackupExportPath.containsRestorableData(in: root))
    }

}
