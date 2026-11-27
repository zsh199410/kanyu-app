import Foundation

/// Presentation-only verification. Do not persist inferred ownership or rename old exports.
enum V5ReportOwnership {
    static func verified(_ entry: ReportHistoryEntry) -> ReportHistoryEntry {
        let explicitID: UUID?
        switch entry.url.pathExtension.lowercased() {
        case "pdf": explicitID = ReportHistory.pdfPersonID(for: entry.url)
        case "png": explicitID = ReportHistory.stripPersonIDSuffix(entry.url.deletingPathExtension().lastPathComponent).personID
        default: explicitID = nil
        }
        return ReportHistoryEntry(id: entry.id, url: entry.url, personID: explicitID,
            personName: entry.personName, kind: entry.kind, icon: entry.icon,
            generatedAt: entry.generatedAt, sizeKB: entry.sizeKB,
            tierName: entry.tierName, hashShort: entry.hashShort)
    }
}
