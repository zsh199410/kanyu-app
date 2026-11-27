import Foundation
import PDFKit

// Diagnostic only: expose the actual PDFKit strings without rewriting PDFs or normalizing assertions.
let root = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2])
let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).filter { $0.pathExtension == "pdf" }
var reports: [[String: Any]] = []
for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
    guard let document = PDFDocument(url: file) else { fatalError("Cannot decode \(file.lastPathComponent)") }
    var pages: [String] = []
    for index in 0..<document.pageCount {
        guard let text = document.page(at: index)?.string else { fatalError("Missing text page \(index)") }
        pages.append(text)
    }
    reports.append(["file": file.lastPathComponent, "pages": pages, "pageCount": document.pageCount])
}
guard files.count == 4 else { fatalError("Expected four formal exports") }
try JSONSerialization.data(withJSONObject: reports, options: [.prettyPrinted, .sortedKeys]).write(to: output)
print("Preserved original PDFKit strings from \(files.count) PDFs; no acceptance claim")
