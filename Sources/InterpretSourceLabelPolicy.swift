import Foundation

/// Explicitly separate source provenance from the user's subjective verification.
enum InterpretSourceLabelPolicy {
    static func label(userMark: Bool?, mechanism: String?) -> String {
        let mark: String
        switch userMark {
        case true: mark = "用户标记：已应验"
        case false: mark = "用户标记：待回验"
        case nil: mark = "用户未标记"
        }
        return mark + " · " + evidenceLevel(for: mechanism)
    }

    static func evidenceLevel(for mechanism: String?) -> String {
        let text = (mechanism ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "盘面事实（规则口径）" }

        // System-internal policies are not independently validated evidence.
        if text.contains("纪律") || text.contains("回测") {
            return "系统规则／回测口径（未经独立核验）"
        }
        if text.contains("民俗") || text.contains("民间") || text.contains("象征") {
            return "民俗象征（非实证结论）"
        }
        // A book title or the word "original" is never proof of a checked quotation.
        // Structured work, location and original text must be verified separately.
        if (text.contains("《") && text.contains("》")) || text.contains("古籍") || text.contains("典籍") {
            return "古籍相关观点（未核逐字原文）"
        }
        return "传统流派解释（来源待核）"
    }
}
