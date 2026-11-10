// 命书报告生成回归（ReportBuilder，Sources/ReportModule.swift）：内容哈希、导出文件名、档位取舍、长文本不崩。
// 与风险点 (e) 相关：报告长文本不得导致崩溃或内容意外丢失。paginate() 为 private（单行溢出、行数守恒不可直测，见审计报告缺口）。
// 人物均为合成数据（2000-06-15 10:30，梁平经度 107.8），不含家人出生数据。
import XCTest
@testable import Kanyu

final class ReportBuilderTests: XCTestCase {
    private func person(name: String = "测试甲") -> Person {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm"
        fmt.timeZone = TimeZone(secondsFromGMT: 8 * 3600)
        let epoch = fmt.date(from: "2000-06-15 10:30")!.timeIntervalSince1970
        return Person(name: name, gender: "M", birthEpoch: epoch, useLongitude: true, longitude: 107.8)
    }

    func testContentHashDeterministicAndHex() {
        let lines = ["命书 · 测试甲", "四柱：甲子 乙丑 丙寅 丁卯", ""]
        let first = ReportBuilder.contentHash(lines: lines, tier: .professional)
        let second = ReportBuilder.contentHash(lines: lines, tier: .professional)
        XCTAssertEqual(first, second, "同一输入两次哈希必相同")
        XCTAssertEqual(first.count, 64, "SHA256 应为 64 位 hex")
        XCTAssertEqual(first, first.lowercased(), "哈希应为小写 hex")
    }

    func testContentHashTierSensitive() {
        let lines = ["命书 · 测试甲"]
        XCTAssertNotEqual(ReportBuilder.contentHash(lines: lines, tier: .concise),
        ReportBuilder.contentHash(lines: lines, tier: .professional))
        XCTAssertNotEqual(ReportBuilder.contentHash(lines: lines, tier: .professional),
        ReportBuilder.contentHash(lines: lines, tier: .complete))
    }

    func testContentHashChangesWithContent() {
        XCTAssertNotEqual(ReportBuilder.contentHash(lines: ["甲"], tier: .professional),
        ReportBuilder.contentHash(lines: ["乙"], tier: .professional))
        XCTAssertNotEqual(ReportBuilder.contentHash(lines: [], tier: .professional),
        ReportBuilder.contentHash(lines: ["甲"], tier: .professional))
    }

    func testExportNameEmpty() {
        XCTAssertEqual(ReportBuilder.exportName(""), "未命名")
        XCTAssertEqual(ReportBuilder.exportName(" "), "未命名")
    }

    func testExportNameStripsForbiddenCharacters() {
        XCTAssertEqual(ReportBuilder.exportName("甲/乙:丙\\丁"), "甲_乙_丙_丁")
        XCTAssertEqual(ReportBuilder.exportName("a/b"), "a_b")
    }

    func testExportNameByteCap() {
        let longChinese = String(repeating: "甲", count: 100)
        let capped = ReportBuilder.exportName(longChinese)
        XCTAssertEqual(capped.utf8.count, 78, "80 字节上限：26 个汉字＝78 字节，第 27 个放不下")
        XCTAssertEqual(capped.count, 26)
        let longASCII = String(repeating: "a", count: 100)
        XCTAssertEqual(ReportBuilder.exportName(longASCII).count, 80)
    }

    func testLinesProfessionalSections() {
        let lines = ReportBuilder.lines(for: person())
        XCTAssertEqual(lines.first, "命书 · 测试甲")
        XCTAssertTrue(lines.contains("【四柱细盘】"))
        XCTAssertTrue(lines.contains(where: { $0.hasPrefix("【大运】")}))
        XCTAssertTrue(lines.contains("【双术合参 · 交叉印证】"))
        XCTAssertTrue(lines.contains(where: { $0.hasPrefix("【逐项解盘详解")}))
        XCTAssertTrue(lines.contains("【紫微摘要】"))
        XCTAssertTrue(lines.contains("【逐年直断（当前大运十年）】"))
        XCTAssertTrue(lines.last?.hasPrefix("口径：") == true)
    }

    func testLinesConciseOmitsSections() {
        let concise = ReportBuilder.lines(for: person(), tier: .concise)
        let professional = ReportBuilder.lines(for: person(), tier: .professional)
        XCTAssertFalse(concise.contains(where: { $0.hasPrefix("【大运】")}), "简洁档不含大运")
        XCTAssertFalse(concise.contains("【双术合参 · 交叉印证】"), "简洁档不含合参")
        XCTAssertFalse(concise.contains("【紫微摘要】"), "简洁档不含紫微摘要")
        XCTAssertTrue(concise.contains(where: { $0.hasPrefix("【解盘维度摘要")}), "简洁档只列总纲摘要")
        XCTAssertLessThan(concise.count, professional.count)
    }

    func testLinesCompleteAddsAppendix() {
        let complete = ReportBuilder.lines(for: person(), tier: .complete)
        let professional = ReportBuilder.lines(for: person(), tier: .professional)
        XCTAssertTrue(complete.contains("【白话阅读指南】"))
        XCTAssertTrue(complete.contains("【逐项依据（附录）】"))
        XCTAssertTrue(complete.contains("【附录 · 版本与口径】"))
        XCTAssertTrue(complete.contains("报告档位：完整"))
        XCTAssertTrue(complete.contains("引擎口径版本：\(ReportBuilder.engineVersion)"))
        XCTAssertGreaterThan(complete.count, professional.count)
    }

    func testLinesLongNameDoesNotCrash() {
        let longName = String(repeating: "甲", count: 500)
        let lines = ReportBuilder.lines(for: person(name: longName))
        XCTAssertFalse(lines.isEmpty)
        XCTAssertEqual(lines.first, "命书 · " + longName, "超长姓名不截断、不崩溃")
        XCTAssertLessThanOrEqual(ReportBuilder.exportName(longName).utf8.count, 80, "导出文件名仍受 80 字节上限保护")
    }

    func testLinesEmptyNameDoesNotCrash() {
        let lines = ReportBuilder.lines(for: person(name: ""))
        XCTAssertEqual(lines.first, "命书 · ")
    }

    func testMakePDFWritesFile() throws {
        let url = try XCTUnwrap(ReportBuilder.makePDF(for: person(), tier: .concise), "简洁档命书 PDF 应能生成")
        defer { try? FileManager.default.removeItem(at: url)}
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "PDF 文件应真实落盘")
        let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int ?? 0
        XCTAssertGreaterThan(size, 0, "PDF 不应为空文件")
        XCTAssertEqual(url.pathExtension, "pdf")
    }
}
