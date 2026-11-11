import Foundation
import ZIPFoundation

/// Each operation owns its temporary paths. A failed attempt cannot remove an older export.
enum BackupExportArchive {
    enum Failure: LocalizedError {
        case noData, emptyArchive, unsafePayload, ambiguousPayload
        var errorDescription: String? {
            switch self {
            case .noData: return "备份包没有可恢复的数据文件"
            case .emptyArchive: return "未生成有效的备份文件"
            case .unsafePayload: return "备份数据必须是非空的普通文件，不能是目录或链接"
            case .ambiguousPayload: return "备份包包含多组数据，请选择单个备份包"
            }
        }
    }

    static func write(in root: URL, date: String, fileManager fm: FileManager = .default,
                      zip: ((URL, URL) throws -> Void)? = nil,
                      prepare: (URL) throws -> Void) throws -> URL {
        let identifier = UUID().uuidString
        let staging = root.appendingPathComponent("Kanyu-Backup-stage-\(identifier)", isDirectory: true)
        let archive = root.appendingPathComponent("Kanyu-Backup-\(date)-\(identifier).zip")
        defer { try? fm.removeItem(at: staging) }
        do {
            try fm.createDirectory(at: staging, withIntermediateDirectories: true)
            try prepare(staging)
            if let zip { try zip(staging, archive) }
            else { try fm.zipItem(at: staging, to: archive) }
            let attributes = try fm.attributesOfItem(atPath: archive.path)
            guard (attributes[.type] as? FileAttributeType) == .typeRegular,
                  ((attributes[.size] as? NSNumber)?.intValue ?? 0) > 0 else {
                throw Failure.emptyArchive
            }
            return archive
        } catch {
            // Only this attempt's incomplete destination is eligible for removal.
            try? fm.removeItem(at: archive)
            throw error
        }
    }

    static func extract(from archive: URL, in root: URL, fileManager fm: FileManager = .default) throws -> URL {
        let destination = root.appendingPathComponent("Kanyu-Restore-\(UUID().uuidString)", isDirectory: true)
        do {
            try fm.unzipItem(at: archive, to: destination)
            return destination
        } catch {
            try? fm.removeItem(at: destination)
            throw error
        }
    }

    /// Both current manifest archives and older wrapped JSON archives are supported.
    static func payloadDirectory(in root: URL, fileManager fm: FileManager = .default) throws -> URL {
        let rootAttributes = try fm.attributesOfItem(atPath: root.path)
        guard (rootAttributes[.type] as? FileAttributeType) == .typeDirectory else { throw Failure.unsafePayload }
        let children = try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).filter { url in
            guard let attributes = try? fm.attributesOfItem(atPath: url.path) else { return false }
            return (attributes[.type] as? FileAttributeType) == .typeDirectory
        }
        let candidates = try ([root] + children).filter { try hasRestorablePayload(in: $0, fileManager: fm) }
        guard !candidates.isEmpty else { throw Failure.noData }
        guard candidates.count == 1 else { throw Failure.ambiguousPayload }
        return candidates[0]
    }

    /// Check every recognized file, so a valid file cannot hide an invalid sibling.
    static func hasRestorablePayload(in directory: URL, fileManager fm: FileManager = .default) throws -> Bool {
        let directoryAttributes = try fm.attributesOfItem(atPath: directory.path)
        guard (directoryAttributes[.type] as? FileAttributeType) == .typeDirectory else { throw Failure.unsafePayload }
        let names = ["people.json", "forecasts.json", "palm_records.json", "index.json",
                     "verify-marks-v2.json", "verify-marks-v1-unassigned.json", "verify-marks.json"]
        var found = false
        for name in names + [BackupIntegrity.manifestName] {
            let attributes: [FileAttributeKey: Any]
            do { attributes = try fm.attributesOfItem(atPath: directory.appendingPathComponent(name).path) }
            catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile { continue }
            guard (attributes[.type] as? FileAttributeType) == .typeRegular,
                  ((attributes[.size] as? NSNumber)?.intValue ?? 0) > 0 else { throw Failure.unsafePayload }
            if name != BackupIntegrity.manifestName { found = true }
        }
        return found
    }
}
