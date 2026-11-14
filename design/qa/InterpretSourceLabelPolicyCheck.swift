import Foundation

@main
struct InterpretSourceLabelPolicyCheck {
    struct Case {
        let name: String
        let mark: Bool?
        let mechanism: String?
        let expected: String
    }

    static func main() {
        let cases: [Case] = [
            .init(name: "book name only", mark: nil, mechanism: "《子平真诠》", expected: "用户未标记 · 古籍相关观点（未核逐字原文）"),
            .init(name: "unverified traditional commentary", mark: true, mechanism: "《滴天髓》通说", expected: "用户标记：已应验 · 古籍相关观点（未核逐字原文）"),
            .init(name: "modern commentary", mark: false, mechanism: "现代博客展开，非典籍原文：《穷通宝鉴》", expected: "用户标记：待回验 · 古籍相关观点（未核逐字原文）"),
            .init(name: "quotation without provenance", mark: nil, mechanism: "古籍原文据称：某章", expected: "用户未标记 · 古籍相关观点（未核逐字原文）"),
            .init(name: "folk source", mark: nil, mechanism: "民俗象征《三命通会》", expected: "用户未标记 · 民俗象征（非实证结论）"),
            .init(name: "internal testing", mark: true, mechanism: "工作室回测纪律：样例", expected: "用户标记：已应验 · 系统规则／回测口径（未经独立核验）"),
            .init(name: "nil mechanism", mark: false, mechanism: nil, expected: "用户标记：待回验 · 盘面事实（规则口径）"),
            .init(name: "empty mechanism", mark: nil, mechanism: " \n\t ", expected: "用户未标记 · 盘面事实（规则口径）"),
            .init(name: "traditional application", mark: nil, mechanism: "命局按生克关系取象", expected: "用户未标记 · 传统流派解释（来源待核）"),
            .init(name: "unfinished book brackets", mark: nil, mechanism: "只有《书名", expected: "用户未标记 · 传统流派解释（来源待核）")
        ]
        for item in cases {
            let got = InterpretSourceLabelPolicy.label(userMark: item.mark, mechanism: item.mechanism)
            precondition(got == item.expected, "\(item.name): got \(got), expected \(item.expected)")
            precondition(!got.contains("五典原文") && !got.contains("已验真"), item.name)
        }
        print("PASS: \(cases.count) source-provenance and subjective-mark cases")
    }
}

// Reproduce (macOS or Linux Swift):
// swiftc Sources/InterpretSourceLabelPolicy.swift design/qa/InterpretSourceLabelPolicyCheck.swift -o /tmp/kanyu-label-check
// /tmp/kanyu-label-check
