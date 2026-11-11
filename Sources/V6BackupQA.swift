#if DEBUG
import Foundation

/// Uses only a disposable temporary directory and synthetic JSON. Never opens app stores.
@MainActor enum V6BackupQA {
    enum Failure: Error { case injectedPrepare, injectedZIP, check(String) }

    static func run(output: URL) throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("V6BackupQA-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        var checks: [String] = []
        func check(_ condition: Bool, _ name: String) throws {
            guard condition else { throw Failure.check(name) }
            checks.append(name)
        }
        func prepare(_ directory: URL, name: String) throws {
            let person = Person(name: name, birthEpoch: 946684800)
            try JSONEncoder().encode([person]).write(to: directory.appendingPathComponent("people.json"), options: .atomic)
            try BackupIntegrity.writeManifest(in: directory, fileManager: fm)
        }
        var staging: [URL] = []
        let first = try BackupExportArchive.write(in: root, date: "2000-01-01") { directory in
            staging.append(directory)
            try prepare(directory, name: "QA备份人物甲")
        }
        let firstBytes = try Data(contentsOf: first)
        let second = try BackupExportArchive.write(in: root, date: "2000-01-01") { directory in
            staging.append(directory)
            try prepare(directory, name: "QA备份人物乙")
        }
        let secondBytes = try Data(contentsOf: second)
        try check(first != second && first.lastPathComponent.hasSuffix(".zip"), "same-day exports have distinct ZIP paths")
        try check(try Data(contentsOf: first) == firstBytes, "second export preserves the first ZIP byte-for-byte")
        try check(staging.count == 2 && staging.allSatisfy { !fm.fileExists(atPath: $0.path) }, "successful exports remove their staging directories")

        var extractedPaths: [URL] = []
        for (archive, name) in [(first, "QA备份人物甲"), (second, "QA备份人物乙")] {
            let extracted = try BackupExportArchive.extract(from: archive, in: root)
            extractedPaths.append(extracted)
            let directory = try BackupExportArchive.payloadDirectory(in: extracted)
            let manifest = try BackupIntegrity.validate(in: directory, fileManager: fm)
            let people = try JSONDecoder().decode([Person].self, from: Data(contentsOf: directory.appendingPathComponent("people.json")))
            try check(manifest != nil && people.map(\.name) == [name], "actual ZIP restores expected synthetic JSON and SHA256 manifest: \(name)")
            try fm.removeItem(at: extracted)
        }
        try check(Set(extractedPaths).count == 2, "restore attempts have distinct extraction paths")

        var failedStaging: URL?
        do {
            _ = try BackupExportArchive.write(in: root, date: "2000-01-01") { directory in
                failedStaging = directory
                try Data("partial".utf8).write(to: directory.appendingPathComponent("partial.json"))
                throw Failure.injectedPrepare
            }
            throw Failure.check("prepare failure was not propagated")
        } catch Failure.injectedPrepare {}
        try check(failedStaging.map { !fm.fileExists(atPath: $0.path) } == true,
                  "prepare failure removes partial staging")

        var failedArchive: URL?
        var failedZIPStaging: URL?
        do {
            _ = try BackupExportArchive.write(in: root, date: "2000-01-01", zip: { _, archive in
                failedArchive = archive
                try Data("partial ZIP".utf8).write(to: archive)
                throw Failure.injectedZIP
            }) { directory in
                failedZIPStaging = directory
                try prepare(directory, name: "QA打包失败人物")
            }
            throw Failure.check("ZIP failure was not propagated")
        } catch Failure.injectedZIP {}
        try check(failedArchive.map { !fm.fileExists(atPath: $0.path) } == true &&
                  failedZIPStaging.map { !fm.fileExists(atPath: $0.path) } == true,
                  "ZIP failure removes only its incomplete archive and staging")

        do {
            _ = try BackupExportArchive.write(in: root, date: "2000-01-01") { _ in
                throw BackupExportArchive.Failure.noData
            }
            throw Failure.check("no-data failure was not propagated")
        } catch BackupExportArchive.Failure.noData {}
        try check(try Data(contentsOf: first) == firstBytes && Data(contentsOf: second) == secondBytes,
                  "prepare, ZIP and no-data failures preserve both previous ZIPs byte-for-byte")
        try check(try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).count == 2,
                  "failed exports leave no extra staging directories or archives")

        let invalid = root.appendingPathComponent("invalid.zip")
        try Data("not a ZIP".utf8).write(to: invalid)
        let before = Set(try fm.contentsOfDirectory(atPath: root.path))
        do {
            _ = try BackupExportArchive.extract(from: invalid, in: root)
            throw Failure.check("malformed ZIP was accepted")
        } catch is Failure { throw Failure.check("malformed ZIP was accepted") }
        catch {}
        try check(try Set(fm.contentsOfDirectory(atPath: root.path)) == before,
                  "malformed ZIP extraction leaves no partial restore directory")

        let legacy = try BackupExportArchive.write(in: root, date: "2000-01-01") { directory in
            try JSONEncoder().encode([Person(name: "QA旧版人物", birthEpoch: 946684800)])
                .write(to: directory.appendingPathComponent("people.json"), options: .atomic)
        }
        let legacyExtracted = try BackupExportArchive.extract(from: legacy, in: root)
        let legacyPayload = try BackupExportArchive.payloadDirectory(in: legacyExtracted)
        let legacyPeople = try JSONDecoder().decode([Person].self, from: Data(contentsOf: legacyPayload.appendingPathComponent("people.json")))
        let legacyManifest = try BackupIntegrity.validate(in: legacyPayload)
        try check(legacyManifest == nil && legacyPeople.map(\.name) == ["QA旧版人物"],
                  "legacy wrapped ZIP without a manifest resolves its actual JSON payload")
        try fm.removeItem(at: legacyExtracted)

        let direct = root.appendingPathComponent("direct-payload", isDirectory: true)
        try fm.createDirectory(at: direct, withIntermediateDirectories: true)
        try prepare(direct, name: "QA根目录人物")
        try check(try BackupExportArchive.payloadDirectory(in: direct) == direct,
                  "root-level current payload is supported")

        let linked = root.appendingPathComponent("linked-payload", isDirectory: true)
        try fm.createDirectory(at: linked, withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: linked.appendingPathComponent("people.json"), withDestinationURL: first)
        try Data("[]".utf8).write(to: linked.appendingPathComponent("forecasts.json"))
        do {
            _ = try BackupExportArchive.payloadDirectory(in: linked)
            throw Failure.check("a valid sibling hid a linked data file")
        } catch BackupExportArchive.Failure.unsafePayload {}
        try check(true, "linked data is rejected even beside a valid recognized file")

        let directoryPayload = root.appendingPathComponent("directory-payload", isDirectory: true)
        try fm.createDirectory(at: directoryPayload.appendingPathComponent("people.json"), withIntermediateDirectories: true)
        try Data("[]".utf8).write(to: directoryPayload.appendingPathComponent("forecasts.json"))
        do {
            _ = try BackupExportArchive.payloadDirectory(in: directoryPayload)
            throw Failure.check("a valid sibling hid a data directory")
        } catch BackupExportArchive.Failure.unsafePayload {}
        try check(true, "data directories are rejected even beside a valid recognized file")

        let empty = root.appendingPathComponent("manifest-only", isDirectory: true)
        try fm.createDirectory(at: empty, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: empty.appendingPathComponent(BackupIntegrity.manifestName))
        do {
            _ = try BackupExportArchive.payloadDirectory(in: empty)
            throw Failure.check("manifest-only payload was accepted")
        } catch BackupExportArchive.Failure.noData {}
        try check(true, "manifest-only archives have no restorable data")

        let ambiguous = root.appendingPathComponent("ambiguous-payload", isDirectory: true)
        for name in ["first", "second"] {
            let directory = ambiguous.appendingPathComponent(name, isDirectory: true)
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            try prepare(directory, name: "QA歧义人物")
        }
        do {
            _ = try BackupExportArchive.payloadDirectory(in: ambiguous)
            throw Failure.check("ambiguous payload was selected arbitrarily")
        } catch BackupExportArchive.Failure.ambiguousPayload {}
        try check(true, "multiple payload groups are rejected")

        try firstBytes.write(to: output.appendingPathComponent("backup-first.zip"), options: .atomic)
        try secondBytes.write(to: output.appendingPathComponent("backup-second.zip"), options: .atomic)
        let legacyBytes = try Data(contentsOf: legacy)
        try legacyBytes.write(to: output.appendingPathComponent("backup-legacy.zip"), options: .atomic)
        let report: [String: Any] = ["status": "success", "checks": checks,
            "scope": "Native production local ZIP/extraction/payload helpers with disposable synthetic data and injected failures; not backup UI, iCloud, disk-full or live-store restore testing",
            "archives": [["file": "backup-first.zip", "sha256": BackupIntegrity.digest(firstBytes)],
                         ["file": "backup-second.zip", "sha256": BackupIntegrity.digest(secondBytes)],
                         ["file": "backup-legacy.zip", "sha256": BackupIntegrity.digest(legacyBytes)]]]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("backup-verification.json"), options: .atomic)
    }
}
#endif
