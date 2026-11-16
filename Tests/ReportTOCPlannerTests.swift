import XCTest
import UIKit
import PDFKit
@testable import Kanyu

/// New tests only: the existing Tests and golden JSON stay unchanged.
/// Exercises measured TOC rows and the real ReportBuilder PDF, never mock labels.
final class ReportTOCPlannerTests: XCTestCase {
    private let a4 = CGRect(x: 0, y: 0, width: 595, height: 842)
    private var heading: UIFont {
        UIFont(name: "STSongti-SC-Semibold", size: 18) ?? .boldSystemFont(ofSize: 18)
    }
    private var body: UIFont {
        UIFont(name: "STSongti-SC-Regular", size: 11) ?? .systemFont(ofSize: 11)
    }
    private var item: UIFont {
        UIFont(name: "STSongti-SC-Regular", size: 10) ?? .systemFont(ofSize: 10)
    }

    private func measured(_ value: String, font: UIFont, width: CGFloat) -> CGFloat {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        let style: [NSAttributedString.Key: Any] = [.font: font, .paragraphStyle: paragraph]
        return ceil((value as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin], attributes: style, context: nil).height)
    }

    private func rows(_ pages: [ReportTOCPlanner.Page]) -> [ReportTOCPlanner.PlacedRow] {
        pages.flatMap { $0.rows }
    }

    func testLongDoubleColumnTOCUsesMeasuredHeightInsteadOfFixed16Points() {
        let title = String(repeating: "超长目录标题需要完整显示与自动换行。", count: 9)
        let entries = (0..<14).map { (title: "\($0 + 1) · " + title, page: 10 + $0) }
        let pages = ReportTOCPlanner.pages(
            personName: "目录长标题测试", chapters: [("第一章 · 总览", 3)],
            items: entries, pageRect: a4, headFont: heading, bodyFont: body)
        let col = (a4.width - 96 - 16) / 2
        let pairs = rows(pages).compactMap { placed -> (CGFloat, String, String?)? in
            guard case let .itemPair(left, right) = placed.kind else { return nil }
            return (placed.y, left.title, right?.title)
        }
        XCTAssertEqual(pairs.count, 7)
        XCTAssertTrue(pairs.contains { measured($0.1, font: item, width: col - 40) > 16 })
        for page in pages {
            for (previous, next) in zip(page.rows, page.rows.dropFirst()) {
                guard case let .itemPair(left, right) = previous.kind else { continue }
                let leftH = measured(left.title, font: item, width: col - 40)
                let rightH = right.map { measured($0.title, font: item, width: col - 40) } ?? 0
                XCTAssertGreaterThanOrEqual(next.y - previous.y,
                                            max(16, max(leftH, rightH)),
                                            "Variable-height TOC rows must not overlap")
            }
        }
    }

    func testLongTOCContinuesAndNeverCrossesFooter() {
        let chapters = (1...14).map { i in
            (title: "第\(i)章 · " + String(repeating: "完整章节说明与来源回溯。", count: 6),
             page: i * 4 + 3)
        }
        let entries = (1...90).map { i in
            (title: "第\(i)条 · " + String(repeating: "双栏条目长标题与依据核对。", count: 5),
             page: i + 20)
        }
        let pages = ReportTOCPlanner.pages(personName: "复杂姓名目录分页",
                                            chapters: chapters, items: entries,
                                            pageRect: a4, headFont: heading, bodyFont: body)
        XCTAssertGreaterThan(pages.count, 2, "Long indexes require real TOC continuation pages")
        XCTAssertEqual(rows(pages).filter {
            if case .itemPair = $0.kind { return true }; return false
        }.count, (entries.count + 1) / 2)
        XCTAssertEqual(rows(pages).filter {
            if case .chapter = $0.kind { return true }; return false
        }.count, chapters.count)
        let col = (a4.width - 96 - 16) / 2
        for (index, page) in pages.enumerated() {
            XCTAssertFalse(page.rows.isEmpty)
            XCTAssertEqual(page.rows.first?.y, 48)
            if index > 0 {
                guard case .continued = page.rows.first!.kind else {
                    XCTFail("Every continuation page must begin with 目录（续）")
                    continue
                }
            }
            for row in page.rows {
                let height: CGFloat
                switch row.kind {
                case .title: height = measured("目录", font: heading, width: a4.width - 96)
                case .continued: height = measured("目录（续）", font: heading, width: a4.width - 96)
                case .summary: height = measured("命书 · 复杂姓名目录分页　共 9999 页", font: body, width: a4.width - 96)
                case .chapter(let entry):
                    height = measured(entry.title, font: body, width: a4.width - 96 - 60)
                case .indexHeader(let count):
                    height = measured("详批条目（\(count) 条）", font: heading, width: a4.width - 96)
                case .itemPair(let left, let right):
                    let lh = measured(left.title, font: item, width: col - 40)
                    let rh = right.map { measured($0.title, font: item, width: col - 40) } ?? 0
                    height = max(lh, rh)
                case .note:
                    height = measured("页码与正文实际分页一致；正文每页页脚亦标页码，可逐页核对。",
                                      font: body, width: a4.width - 96)
                }
                XCTAssertLessThanOrEqual(row.y + height, a4.height - 68 + 1,
                                         "TOC row enters footer region on page \(index + 2)")
            }
        }
    }

    func testRealReportKeepsLegacy4_14_26PageBaselines() throws {
        let fixtures: [(ReportTier, String, Int)] = [
            (.concise, "张/三\\测试:报告", 4),
            (.professional, "目录回归", 14),
            (.complete, "目录回归", 26)
        ]
        for (tier, name, expectedPages) in fixtures {
            let person = Person(name: name, birthEpoch: 946684800)
            let url = try XCTUnwrap(ReportBuilder.makePDF(for: person, tier: tier))
            defer { try? FileManager.default.removeItem(at: url) }
            let pdf = try XCTUnwrap(PDFDocument(url: url))
            XCTAssertEqual(pdf.pageCount, expectedPages, "Legacy \(tier.rawValue) page count changed")
            XCTAssertTrue((pdf.page(at: 1)?.string ?? "").contains("目录"), tier.rawValue)
            XCTAssertNotNil(pdf.page(at: 2)?.string, tier.rawValue)
            let lines = ReportBuilder.lines(for: person, tier: tier)
            let contentHash = ReportBuilder.contentHash(lines: lines, tier: tier)
            XCTAssertEqual(contentHash.count, 64)
            XCTAssertTrue(url.lastPathComponent.contains(String(contentHash.prefix(12))))
        }
    }
}
