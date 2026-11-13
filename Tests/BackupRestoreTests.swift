import XCTest
@testable import Kanyu

/// P0-4 恢复端到端：只测可达的公开接缝（解压→定位载荷→清单校验→事务回滚）。
/// 边界（诚实说明）：BackupView.restore(from:) 与 importFiles/rollbackRestore 是 private，
/// 单元测试无法直接调用；本文件证明每段接缝失败时都闭合（抛错、本地数据不动），
/// 完整 restore(from:) 路径须走 UI 测试，或把 importFiles 改为 internal（生产改动，另行授权）。
/// 失败文案不断言具体中文，只断言失败类型与数据不变。
final class BackupRestoreTests: XCTestCase {
    private var directory: URL!
    private var local: URL!
    private var store: URL!

    override func setUpWithError() throws {
        let base = FileManager.default.temporaryDirectory
        directory = base.appendingPathComponent("BackupRestoreTests-\(UUID().uuidString)", isDirectory: true)
        local = base.appendingPathComponent("BackupRestoreLocal-\(UUID().uuidString)", isDirectory: true)
        store = base.appendingPathComponent("BackupRestoreStore-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: store, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.removeItem(at: local)
        try? FileManager.default.removeItem(at: store)
        directory = nil
        local = nil
        store = nil
    }

    private func samplePerson() -> Person {
        Person(name: "QA-A", birthEpoch: 946684800.0)
    }

    private func makeValidBackup() throws -> URL {
        let people = try JSONEncoder().encode([samplePerson()])
        return try BackupExportArchive.write(in: directory, date: "2026-11-13") { staging in
            try people.write(to: staging.appendingPathComponent("people.json"))
            try Data("[]".utf8).write(to: staging.appendingPathComponent("forecasts.json"))
            try BackupIntegrity.writeManifest(in: staging)
        }
    }

    private func restoreLeftovers(in root: URL) -> [URL] {
        let items = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        return items.filter { $0.lastPathComponent.hasPrefix("Kanyu-Restore-") }
    }

    func testExtractRejectsNonZipData() throws {
        let garbage = directory.appendingPathComponent("garbage.zip")
        try Data("this is not a zip archive".utf8).write(to: garbage)

        XCTAssertThrowsError(try BackupExportArchive.extract(from: garbage, in: directory))
        XCTAssertTrue(restoreLeftovers(in: directory).isEmpty)
    }

    func testExtractRejectsTruncatedZip() throws {
        let valid = try makeValidBackup()
        let data = try Data(contentsOf: valid)
        XCTAssertGreaterThan(data.count, 32)

        let truncated = directory.appendingPathComponent("truncated.zip")
        try Data(data.prefix(data.count / 2)).write(to: truncated)

        XCTAssertThrowsError(try BackupExportArchive.extract(from: truncated, in: directory))
        XCTAssertTrue(restoreLeftovers(in: directory).isEmpty)
    }

    func testValidBackupPassesExtractValidatePipeline() throws {
        let backup = try makeValidBackup()

        let extracted = try BackupExportArchive.extract(from: backup, in: directory)
        let payload = try BackupExportArchive.payloadDirectory(in: extracted)
        let manifest = try BackupIntegrity.validate(in: payload)

        XCTAssertEqual(Set(try XCTUnwrap(manifest).files.map(\.name)), Set(["forecasts.json", "people.json"]))
    }

    func testTamperedBackupStopsAtValidationAndLeavesLocalDataUntouched() throws {
        let sentinel = local.appendingPathComponent("people.json")
        let sentinelData = try JSONEncoder().encode([samplePerson()])
        try sentinelData.write(to: sentinel)

        let backup = try makeValidBackup()
        let extracted = try BackupExportArchive.extract(from: backup, in: directory)
        // P0-4 修正：必须先经 payloadDirectory 定位真正的载荷目录再篡改。
        // 直接改 extract 返回的根目录只会在顶层新建一个 people.json，载荷里的
        // manifest.json 仍在子目录里，validate 会把无清单的目录当作旧版格式
        // 返回 nil（不抛错），测不到篡改。改载荷目录里的文件并重打该目录的包，
        // 才能让 validate 真正比对到被篡改的 people.json。
        let payload = try BackupExportArchive.payloadDirectory(in: extracted)
        try Data("tampered".utf8).write(to: payload.appendingPathComponent("people.json"))
        let tamperedZip = directory.appendingPathComponent("tampered.zip")
        try FileManager.default.zipItem(at: payload, to: tamperedZip)

        let extractedTampered = try BackupExportArchive.extract(from: tamperedZip, in: directory)
        let payloadTampered = try BackupExportArchive.payloadDirectory(in: extractedTampered)
        XCTAssertThrowsError(try BackupIntegrity.validate(in: payloadTampered)) { error in
            XCTAssertEqual(error as? BackupIntegrityError, .checksumMismatch("people.json"))
        }

        XCTAssertEqual(try Data(contentsOf: sentinel), sentinelData)
    }

    func testPayloadDirectoryRejectsAmbiguousPayload() throws {
        let root = directory.appendingPathComponent("ambiguous", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for group in ["group1", "group2"] {
            let dir = root.appendingPathComponent(group, isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data("people".utf8).write(to: dir.appendingPathComponent("people.json"))
        }

        XCTAssertThrowsError(try BackupExportArchive.payloadDirectory(in: root)) { error in
            guard case BackupExportArchive.Failure.ambiguousPayload = error else {
                return XCTFail("Expected ambiguousPayload, got \(error)")
            }
        }
    }

    func testPayloadDirectoryRejectsEmptyPayload() throws {
        let root = directory.appendingPathComponent("empty", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        XCTAssertThrowsError(try BackupExportArchive.payloadDirectory(in: root)) { error in
            guard case BackupExportArchive.Failure.noData = error else {
                return XCTFail("Expected noData, got \(error)")
            }
        }
    }

    func testRestoreTransactionRollsBackRealFilesWhenLaterDecodeFails() throws {
        let peopleURL = store.appendingPathComponent("people.json")
        let forecastsURL = store.appendingPathComponent("forecasts.json")
        let palmsURL = store.appendingPathComponent("palm_records.json")
        let oldPeople = try JSONEncoder().encode([samplePerson()])
        let oldForecasts = Data("[]".utf8)
        let oldPalms = Data("[]".utf8)
        try oldPeople.write(to: peopleURL)
        try oldForecasts.write(to: forecastsURL)
        try oldPalms.write(to: palmsURL)

        let corruptPalms = Data("not json".utf8)
        XCTAssertThrowsError(
            try BackupRestoreTransaction.perform(
                snapshot: {
                    var snapshot: [String: Data] = [:]
                    for url in [peopleURL, forecastsURL, palmsURL] {
                        snapshot[url.lastPathComponent] = try Data(contentsOf: url)
                    }
                    return snapshot
                },
                apply: {
                    try Data("new people".utf8).write(to: peopleURL)
                    try Data("new forecasts".utf8).write(to: forecastsURL)
                    guard (try? JSONDecoder().decode([PalmRecord].self, from: corruptPalms)) != nil else {
                        throw CocoaError(.fileReadCorruptFile, userInfo: [NSFilePathErrorKey: palmsURL.path])
                    }
                },
                rollback: { snapshot in
                    for (name, data) in snapshot {
                        try data.write(to: store.appendingPathComponent(name), options: .atomic)
                    }
                }
            )
        ) { error in
            guard let cocoa = error as? CocoaError, cocoa.code == .fileReadCorruptFile else {
                return XCTFail("Expected fileReadCorruptFile, got \(error)")
            }
        }

        XCTAssertEqual(try Data(contentsOf: peopleURL), oldPeople)
        XCTAssertEqual(try Data(contentsOf: forecastsURL), oldForecasts)
        XCTAssertEqual(try Data(contentsOf: palmsURL), oldPalms)
    }

    func testRestoreTransactionReportsRollbackFailureWhenFileRollbackFails() throws {
        let peopleURL = store.appendingPathComponent("people.json")
        try Data("old".utf8).write(to: peopleURL)

        XCTAssertThrowsError(
            try BackupRestoreTransaction.perform(
                snapshot: { try Data(contentsOf: peopleURL) },
                apply: {
                    try FileManager.default.removeItem(at: store)
                    throw CocoaError(.fileReadCorruptFile)
                },
                rollback: { snapshot in
                    try snapshot.write(to: peopleURL, options: [])
                }
            )
        ) { error in
            guard case BackupRestoreTransactionError.rollbackFailed = error else {
                return XCTFail("Expected rollbackFailed, got \(error)")
            }
        }
    }
}
