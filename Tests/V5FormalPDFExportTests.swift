import XCTest
import PDFKit
import CryptoKit
@testable import Kanyu

/// Actual production ReportBuilder output, not screenshot text or a substitute renderer.
final class V5FormalPDFExportTests: XCTestCase {
    private func normalized(_ text: String) -> String { text.components(separatedBy: .whitespacesAndNewlines).joined() }
    @MainActor private func export(_ theme: V5Theme) throws {
        let store = V5ThemeStore.shared, original = V5ThemeStore.shared.theme
        let saved = UserDefaults.standard.object(forKey: "v5.theme")
        defer {
            store.select(original)
            if let saved { UserDefaults.standard.set(saved, forKey: "v5.theme") }
            else { UserDefaults.standard.removeObject(forKey: "v5.theme") }
        }
        store.select(theme)
        var person = Person(name: "视觉出版验证", relation: "本人", birthEpoch: 946684800, useLongitude: false)
        person.id = UUID(uuidString: "00000000-0000-4000-8000-000000005001")!
        let lines = ReportBuilder.lines(for: person, tier: .professional)
        let url = try XCTUnwrap(ReportBuilder.makePDF(for: person, tier: .professional))
        let bytes = try Data(contentsOf: url)
        let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let archived = try ReportExportArchive.rootDirectory().appendingPathComponent(digest).appendingPathComponent(url.lastPathComponent)
        defer {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: archived)
            if (try? FileManager.default.contentsOfDirectory(atPath: archived.deletingLastPathComponent().path).isEmpty) == true {
                try? FileManager.default.removeItem(at: archived.deletingLastPathComponent())
            }
        }
        XCTAssertEqual(ReportHistory.pdfPersonID(for: url), person.id)
        let document = try XCTUnwrap(PDFDocument(data: bytes))
        XCTAssertGreaterThan(document.pageCount, 3)
        var body = ""
        for pageNumber in 0..<document.pageCount {
            let page = try XCTUnwrap(document.page(at: pageNumber))
            XCTAssertEqual(page.bounds(for: .mediaBox), V5PublicationStyle.a4)
            let text = normalized(try XCTUnwrap(page.string))
            let footer = normalized("三术合参 · 命书 — 第 \(pageNumber+1) 页（共 \(document.pageCount) 页）")
            XCTAssertTrue(text.contains(footer), "Missing page furniture")
            if pageNumber >= 2 { body += text.replacingOccurrences(of: footer, with: "") }
        }
        for line in lines where !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            XCTAssertTrue(body.contains(normalized(line)), "Missing actual report text: \(line.prefix(100))")
        }
        XCTAssertTrue(normalized(document.page(at: 0)?.string ?? "").contains(person.name))
        let pdf = XCTAttachment(data: bytes, uniformTypeIdentifier: "com.adobe.pdf")
        pdf.name = "v5-formal-\(theme.rawValue)-professional";pdf.lifetime = .keepAlways;add(pdf)
        let receipt: [String: Any] = ["theme": theme.rawValue,"personID": person.id.uuidString,
            "pages": document.pageCount,"bytes": bytes.count,"sha256": digest,"sourceLineCount": lines.count,
            "textExtraction": "PASS","visualApproval": false,"renderer": "ReportBuilder.makePDF"]
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: receipt, options: [.sortedKeys, .prettyPrinted]), uniformTypeIdentifier: "public.json")
        attachment.name = "v5-formal-\(theme.rawValue)-receipt";attachment.lifetime = .keepAlways;add(attachment)
    }
    @MainActor func testSongFormalPDF() throws { try export(.song) }
    @MainActor func testNightFormalPDF() throws { try export(.night) }
    @MainActor func testCeladonFormalPDF() throws { try export(.celadon) }
    @MainActor func testCollectionFormalPDF() throws { try export(.collection) }
}
