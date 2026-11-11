import Foundation
import CryptoKit

/// Persistent export files only. Does not migrate or change profile/forecast storage.
enum ReportExportArchive {
    enum Failure: Error { case documentsUnavailable, invalidFileName, emptyData }
    static func rootDirectory() throws -> URL {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw Failure.documentsUnavailable
        }
        return documents.appendingPathComponent("KanyuExports", isDirectory: true)
    }
    static func save(_ data: Data, fileName: String) throws -> URL {
        guard !data.isEmpty else { throw Failure.emptyData }
        guard !fileName.isEmpty, fileName != ".", fileName != "..",
              !fileName.contains("/"), !fileName.contains("\0") else { throw Failure.invalidFileName }
        // Different content never overwrites another render. Identical content can be reused.
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let directory = try rootDirectory().appendingPathComponent(digest, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(fileName)
        try data.write(to: url, options: .atomic)
        return url
    }
}
