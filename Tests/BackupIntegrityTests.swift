import XCTest
@testable import Kanyu

final class BackupIntegrityTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BackupIntegrityTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        directory = nil
    }

    func testManifestRoundTripValidatesEveryFile() throws {
        try Data("people".utf8).write(to: directory.appendingPathComponent("people.json"))
        try Data("marks".utf8).write(to: directory.appendingPathComponent("verify-marks-v2.json"))

        try BackupIntegrity.writeManifest(in: directory, now: Date(timeIntervalSince1970: 1_700_000_000))
        let manifest = try XCTUnwrap(BackupIntegrity.validate(in: directory))

        XCTAssertEqual(manifest.schemaVersion, BackupIntegrity.currentSchemaVersion)
        XCTAssertEqual(manifest.files.map(\.name), ["people.json", "verify-marks-v2.json"])
    }

    func testTamperedFileStopsRestoreValidation() throws {
        let file = directory.appendingPathComponent("people.json")
        try Data("original".utf8).write(to: file)
        try BackupIntegrity.writeManifest(in: directory)
        try Data("tampered".utf8).write(to: file)

        XCTAssertThrowsError(try BackupIntegrity.validate(in: directory)) { error in
            XCTAssertEqual(error as? BackupIntegrityError, .checksumMismatch("people.json"))
        }
    }

    func testLegacyDirectoryWithoutManifestIsReportedAsUnverified() throws {
        try Data("legacy".utf8).write(to: directory.appendingPathComponent("people.json"))
        XCTAssertNil(try BackupIntegrity.validate(in: directory))
    }
    func testDuplicateManifestEntryRejected() throws {
        try Data("person".utf8).write(to: directory.appendingPathComponent("people.json"))
        try BackupIntegrity.writeManifest(in: directory)
        let url = directory.appendingPathComponent(BackupIntegrity.manifestName)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let original = try decoder.decode(BackupManifest.self, from: Data(contentsOf: url))
        let duplicate = BackupManifest(schemaVersion: original.schemaVersion, createdAt: original.createdAt,
                                       files: original.files + [original.files[0]])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(duplicate).write(to: url)
        XCTAssertThrowsError(try BackupIntegrity.validate(in: directory)) { error in
            XCTAssertEqual(error as? BackupIntegrityError, .duplicateName("people.json"))
        }
    }

    func testUnsupportedOldManifestSchemaRejected() throws {
        try Data("person".utf8).write(to: directory.appendingPathComponent("people.json"))
        try BackupIntegrity.writeManifest(in: directory)
        let url = directory.appendingPathComponent(BackupIntegrity.manifestName)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let original = try decoder.decode(BackupManifest.self, from: Data(contentsOf: url))
        let old = BackupManifest(schemaVersion: 1, createdAt: original.createdAt, files: original.files)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(old).write(to: url)
        XCTAssertThrowsError(try BackupIntegrity.validate(in: directory)) { error in
            XCTAssertEqual(error as? BackupIntegrityError, .unsupportedVersion(1))
        }
    }

    func testManifestSymlinkIsNotAccepted() throws {
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent("BackupOutside-\(UUID().uuidString)")
        try Data("outside".utf8).write(to: outside)
        defer { try? FileManager.default.removeItem(at: outside) }
        let file = directory.appendingPathComponent("people.json")
        try Data("outside".utf8).write(to: file)
        try BackupIntegrity.writeManifest(in: directory)
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: outside)
        XCTAssertThrowsError(try BackupIntegrity.validate(in: directory)) { error in
            XCTAssertEqual(error as? BackupIntegrityError, .unsafeName("people.json"))
        }
    }

}

