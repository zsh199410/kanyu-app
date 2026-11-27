import XCTest
import UIKit
import PDFKit
import CryptoKit
@testable import Kanyu

/// A rendering bridge, not a replacement report writer or second pagination algorithm.
final class V5PublicationStyleTests: XCTestCase {
    private func normalized(_ text: String) -> String {
        text.components(separatedBy: .whitespacesAndNewlines).joined()
    }
    private func rawPDF(style: V5PublicationStyle, texts: [String]) throws -> Data {
        let data = NSMutableData()
        let consumer = try XCTUnwrap(CGDataConsumer(data: data as CFMutableData))
        var box = V5PublicationStyle.a4
        let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &box, nil))
        // Explicit pages supplied by the test: there is deliberately no test-only paginator.
        for (index, text) in texts.enumerated() {
            context.beginPDFPage(nil)
            context.translateBy(x: 0, y: box.height)
            context.scaleBy(x: 1, y: -1)
            style.drawBackground(in: context, pageRect: box)
            try style.drawHeader("三术合参 · 个人命书", in: context, pageRect: box)
            try style.drawText(text, role: .body, in: style.contentRect(in: box), context: context)
            try style.drawFooter(in: context, pageRect: box, page: index + 1, total: texts.count)
            context.endPDFPage()
        }
        context.closePDF()
        return data as Data
    }
    func testFontsSpacingAndContentGeometryPreserveExistingPaginationMetrics() throws {
        for theme in V5Theme.allCases {
            let style = V5PublicationStyle(theme: theme)
            XCTAssertEqual(style.font(for: .title).pointSize, 20)
            XCTAssertEqual(style.font(for: .heading).pointSize, 12.5)
            XCTAssertEqual(style.font(for: .body).pointSize, 11.5)
            XCTAssertEqual(style.font(for: .caption).pointSize, 9)
            XCTAssertEqual(style.contentRect(in: V5PublicationStyle.a4), CGRect(x: 48, y: 48, width: 499, height: 746))
            let paragraph = try XCTUnwrap(style.attributes(for: .body)[.paragraphStyle] as? NSParagraphStyle)
            XCTAssertEqual(paragraph.lineSpacing, 3)
            XCTAssertEqual(paragraph.lineBreakMode, .byWordWrapping)
            // The snapshot references the authority; no copied per-theme color table exists here.
            XCTAssertEqual(style.palette.heroSurface, theme.palette.heroSurface)
            XCTAssertEqual(style.palette.readingPaper, theme.palette.readingPaper)
            XCTAssertEqual(style.palette.readingInk, theme.palette.readingInk)
        }
    }
    func testChineseRealProfileTextAndPageFurnitureExtractAcrossAllFourThemes() throws {
        let person = Person(name: "中文长名验证甲乙丙丁戊己庚辛壬癸", relation: "本人", birthEpoch: 946684800)
        let lines = ReportBuilder.lines(for: person, tier: .concise)
        // Actual source strings, including birth receipt and derived chart; no sample predictions.
        let texts = [lines.prefix(4).joined(separator: "\n"),
                     lines.filter { $0.hasPrefix("年柱") || $0.hasPrefix("月柱") || $0.hasPrefix("日柱") || $0.hasPrefix("时柱") }.joined(separator: "\n"),
                     lines.suffix(3).joined(separator: "\n")]
        XCTAssertTrue(texts.allSatisfy { !$0.isEmpty })
        for theme in V5Theme.allCases {
            let pdf = try XCTUnwrap(PDFDocument(data: rawPDF(style: V5PublicationStyle(theme: theme), texts: texts)))
            XCTAssertEqual(pdf.pageCount, 3)
            for (index, text) in texts.enumerated() {
                let page = try XCTUnwrap(pdf.page(at: index))
                let extracted = normalized(try XCTUnwrap(page.string))
                XCTAssertTrue(extracted.contains(normalized(text)), "\(theme.rawValue) page \(index + 1)")
                XCTAssertTrue(extracted.contains(normalized("第 \(index + 1) 页（共 3 页）")))
                XCTAssertEqual(page.bounds(for: .mediaBox), V5PublicationStyle.a4)
            }
        }
    }
    func testOverflowRejectsRatherThanSilentlyClippingDynamicText() throws {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 595, height: 842))
        let style = V5PublicationStyle(theme: .song)
        _ = renderer.image { context in
            let longText = String(repeating: "真实中文姓名与完整说明不得截断。", count: 500)
            do {
                try style.drawText(longText, role: .body, in: style.contentRect(in: V5PublicationStyle.a4), context: context.cgContext)
                XCTFail("Oversized text must not silently clip")
            } catch V5PublicationStyle.Failure.textExceedsFrame { }
              catch { XCTFail("Unexpected error: \(error)") }
            do {
                try style.drawHeader(longText, in: context.cgContext, pageRect: V5PublicationStyle.a4)
                XCTFail("Oversized running title must be rejected")
            } catch V5PublicationStyle.Failure.textExceedsFrame { }
              catch { XCTFail("Unexpected error: \(error)") }
            do {
                try style.drawFooter(in: context.cgContext, pageRect: V5PublicationStyle.a4, page: 0, total: 1)
                XCTFail("Invalid page number must be rejected")
            } catch V5PublicationStyle.Failure.invalidPageNumber { }
              catch { XCTFail("Unexpected error: \(error)") }
        }
    }
    func testExistingProfessionalExporterKeepsCompleteRealTextAcrossPages() throws {
        // This baseline exercises the existing renderer. The production style bridge must retain the complete original report text.
        let person = Person(name: "分页验证" + String(UUID().uuidString.prefix(8)), birthEpoch: 946684800)
        let lines = ReportBuilder.lines(for: person, tier: .professional)
        let url = try XCTUnwrap(ReportBuilder.makePDF(for: person, tier: .professional))
        let bytes = try Data(contentsOf: url)
        let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let archived = try ReportExportArchive.rootDirectory().appendingPathComponent(digest).appendingPathComponent(url.lastPathComponent)
        defer {
            try? FileManager.default.removeItem(at: url)
            // Remove this test's exact export only, never other reports or the archive root.
            try? FileManager.default.removeItem(at: archived)
            let directory = archived.deletingLastPathComponent()
            if (try? FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty) == true {
                try? FileManager.default.removeItem(at: directory)
            }
        }
        let pdf = try XCTUnwrap(PDFDocument(data: bytes))
        XCTAssertGreaterThan(pdf.pageCount, 3)
        var body = ""
        for index in 2..<pdf.pageCount {
            let page = try XCTUnwrap(pdf.page(at: index))
            let text = normalized(try XCTUnwrap(page.string))
            let footer = normalized("三术合参 · 命书 — 第 \(index + 1) 页（共 \(pdf.pageCount) 页）")
            XCTAssertTrue(text.contains(footer))
            body += text.replacingOccurrences(of: footer, with: "")
        }
        for line in lines where !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            XCTAssertTrue(body.contains(normalized(line)), "Missing report text: \(line.prefix(80))")
        }
    }
}
