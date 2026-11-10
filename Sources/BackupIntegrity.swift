import Foundation
import CryptoKit

struct BackupManifest: Codable, Equatable {
    struct Entry: Codable, Equatable {
        let name: String
        let byteCount: Int
        let sha256: String
    }

    let schemaVersion: Int
    let createdAt: Date
    let files: [Entry]
}

enum BackupIntegrity {
    static let currentSchemaVersion = 2
    static let manifestName = "manifest.json"

    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func writeManifest(in directory: URL, fileManager: FileManager = .default, now: Date = Date()) throws {
        let urls = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
            .filter { $0.lastPathComponent != manifestName }
        var entries: [BackupManifest.Entry] = []
        for url in urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            let data = try Data(contentsOf: url)
            entries.append(.init(name: url.lastPathComponent, byteCount: data.count, sha256: digest(data)))
        }
        guard !entries.isEmpty else { throw CocoaError(.fileNoSuchFile) }
        let manifest = BackupManifest(schemaVersion: currentSchemaVersion, createdAt: now, files: entries)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: directory.appendingPathComponent(manifestName), options: .atomic)
    }

    @discardableResult
    static func validate(in directory: URL, fileManager: FileManager = .default) throws -> BackupManifest? {
        let url = directory.appendingPathComponent(manifestName)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(BackupManifest.self, from: Data(contentsOf: url))
        guard manifest.schemaVersion == currentSchemaVersion else { throw BackupIntegrityError.unsupportedVersion(manifest.schemaVersion) }
        guard !manifest.files.isEmpty else { throw BackupIntegrityError.emptyManifest }
        var seenNames = Set<String>()
        for entry in manifest.files {
            guard entry.name == URL(fileURLWithPath: entry.name).lastPathComponent,
                  !entry.name.contains("..") else { throw BackupIntegrityError.unsafeName(entry.name) }
            guard seenNames.insert(entry.name).inserted else { throw BackupIntegrityError.duplicateName(entry.name) }
            let fileURL = directory.appendingPathComponent(entry.name)
            let attributes = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard attributes?.isSymbolicLink != true else { throw BackupIntegrityError.unsafeName(entry.name) }
            guard attributes?.isRegularFile == true else { throw BackupIntegrityError.missingFile(entry.name) }
            let data = try Data(contentsOf: fileURL)
            guard data.count == entry.byteCount, digest(data) == entry.sha256 else {
                throw BackupIntegrityError.checksumMismatch(entry.name)
            }
        }
        return manifest
    }
}

enum BackupIntegrityError: LocalizedError, Equatable {
    case unsupportedVersion(Int)
    case emptyManifest
    case unsafeName(String)
    case duplicateName(String)
    case missingFile(String)
    case checksumMismatch(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version): return "备份版本 \(version) 高于当前 App 支持范围"
        case .emptyManifest: return "备份清单为空"
        case .unsafeName(let name): return "备份清单包含不安全文件名：\(name)"
        case .duplicateName(let name): return "备份清单重复列出文件：\(name)"
        case .missingFile(let name): return "备份缺少清单文件：\(name)"
        case .checksumMismatch(let name): return "备份文件校验失败：\(name)"
        }
    }
}



enum BackupRestoreTransactionError: LocalizedError {
    case rollbackFailed(original: Error, rollback: Error)

    var errorDescription: String? {
        switch self {
        case .rollbackFailed(let original, let rollback):
            return "恢复失败（\(original.localizedDescription)），且回滚失败（\(rollback.localizedDescription)）"
        }
    }
}

/// Runs restore mutations as one logical transaction. A snapshot is captured before
/// the first mutation and is restored if any later mutation fails.
enum BackupRestoreTransaction {
    static func perform<Snapshot, Result>(
        snapshot: () throws -> Snapshot,
        apply: () throws -> Result,
        rollback: (Snapshot) throws -> Void
    ) throws -> Result {
        let captured = try snapshot()
        do {
            return try apply()
        } catch {
            let original = error
            do {
                try rollback(captured)
            } catch {
                throw BackupRestoreTransactionError.rollbackFailed(original: original, rollback: error)
            }
            throw original
        }
    }
}
