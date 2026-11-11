import Foundation
import PDFKit

struct ExpectedReport: Decodable {
    let tier: String
    let contentHash: String
    let lines: [String]
}

// Compare actual XCTest PDFs with the existing engine's complete drawing input.
// Whitespace/typographic forms and repeated page footers are layout, not missing content.
func normalized(_ value: String) -> String {
    value.precomposedStringWithCompatibilityMapping
        .components(separatedBy: .whitespacesAndNewlines).joined()
}

precondition(CommandLine.arguments.count == 3, "Expected PDF directory and native expected-text JSON")
let directory = URL(fileURLWithPath: CommandLine.arguments[1])
let expectedURL = URL(fileURLWithPath: CommandLine.arguments[2])
let expected = try JSONDecoder().decode([ExpectedReport].self, from: Data(contentsOf: expectedURL))
precondition(Set(expected.map(\.tier)) == Set(["简洁", "专业", "完整"]))
let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
    .filter { $0.pathExtension == "pdf" }
let footer = try NSRegularExpression(pattern: "三术合参·命书[—–-]第[0-9]+页\\(共[0-9]+页\\)")
var results: [[String: Any]] = []
var failures: [String] = []
for report in expected {
    let matches = files.filter { $0.lastPathComponent.contains("-\(report.tier)-") }
    precondition(matches.count == 1, "Need one real XCTest PDF for tier \(report.tier)")
    let file = matches[0]
    precondition(file.lastPathComponent.hasSuffix("-\(report.contentHash.prefix(12)).pdf"),
                 "Native drawing inputs differ from the PDF fixture's content hash: \(report.tier)")
    guard let pdf = PDFDocument(url: file), let extracted = pdf.string else {
        fatalError("Unreadable PDF: \(file.lastPathComponent)")
    }
    let raw = normalized(extracted)
    let text = footer.stringByReplacingMatches(in: raw, range: NSRange(raw.startIndex..<raw.endIndex, in: raw), withTemplate: "")
    let rows = report.lines.enumerated().filter { !normalized($0.element).isEmpty }
    let missing = rows.filter { !text.contains(normalized($0.element)) }
    let summary = missing.map { "row \($0.offset): \($0.element.prefix(90))" }
    if !missing.isEmpty { failures.append("\(report.tier): \(missing.count) missing lines; \(summary.prefix(5))") }
    results.append(["file": file.lastPathComponent, "tier": report.tier, "pages": pdf.pageCount,
                    "sourceLines": rows.count, "missingLines": summary,
                    "contentHash": report.contentHash])
}
let result: [String: Any] = ["scope": "Full source-line text preservation in the three actual XCTest PDFs; not a visual or physical-device acceptance test",
                             "reports": results, "status": failures.isEmpty ? "success" : "failure"]
let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
try data.write(to: directory.deletingLastPathComponent().appendingPathComponent("report-text-verification.json"))
precondition(failures.isEmpty, failures.joined(separator: "\n"))
print("PASS: complete native drawing text preserved in all three actual XCTest PDFs")
