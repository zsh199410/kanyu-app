import Foundation
import PDFKit

// The unchanged XCTest PDF fixtures all use epoch 946684800 (Beijing 2000-01-01 08:00).
// Verify the actual saved PDF, including cover and body, rather than a formatter mock.
let directory = URL(fileURLWithPath: CommandLine.arguments[1])
let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
    .filter { $0.pathExtension == "pdf" }
precondition(files.count >= 3, "Missing actual XCTest report PDFs")
var results: [[String: Any]] = []
for file in files {
    guard let pdf = PDFDocument(url: file), let cover = pdf.page(at: 0)?.string else {
        fatalError("Unreadable PDF: \(file.lastPathComponent)")
    }
    let normalized = cover.components(separatedBy: .whitespacesAndNewlines).joined()
    precondition(normalized.contains("2000-01-0108:00（北京时间UTC+8）"),
                 "PDF cover birth clock differs from the known fixture's Beijing clock: \(file.lastPathComponent)")
    precondition((pdf.string ?? "").contains("北京时间 UTC+8"), "Missing time-zone receipt")
    results.append(["file": file.lastPathComponent, "pages": pdf.pageCount, "beijingBirthReceipt": "pass"])
}
let data = try JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys])
try data.write(to: directory.deletingLastPathComponent().appendingPathComponent("report-receipts.json"))
print("PASS: \(files.count) real XCTest PDFs show the fixture's exact Beijing birth clock")
