import XCTest
import UIKit
import PDFKit
@testable import Kanyu

final class ReadableExperienceTests: XCTestCase {
    func testToolSearchHandlesRestoredInvalidGroupAndMultipleWords() {
        XCTAssertEqual(AllToolsData.filteredItems(query: "  ", groupIndex: 999).count, AllToolsData.allItems.count)
        XCTAssertEqual(AllToolsData.filteredItems(query: "指南针", groupIndex: -1).map { $0.id }, ["compass"])
        XCTAssertTrue(AllToolsData.filteredItems(query: "ｐｄｆ 报告", groupIndex: 0).contains { $0.id == "reportcenter" })
        XCTAssertTrue(AllToolsData.filteredItems(query: "入门", groupIndex: 0).contains { $0.id == "learning" })
        XCTAssertFalse(AllToolsData.filteredItems(query: "不存在的工具", groupIndex: 0).contains { _ in true })
    }

    func testGuideCanFindTermsAndHasNoDuplicateEntries() {
        XCTAssertEqual(Set(LearningContent.topics.map { $0.id }).count, LearningContent.topics.count)
        XCTAssertEqual(Set(LearningContent.terms.map { $0.id }).count, LearningContent.terms.count)
        XCTAssertEqual(Set(AllToolsData.allItems.map { $0.id }).count, AllToolsData.allItems.count)
        XCTAssertEqual(Set(ToolHelpContent.entries.keys), Set(AllToolsData.allItems.map { $0.id }))
        XCTAssertTrue(ToolHelpContent.entries.values.allSatisfy { $0.count == 3 && $0.allSatisfy { !$0.isEmpty } })
        XCTAssertEqual(LearningContent.search("真北 校正").map { $0.id }, ["compass"])
        XCTAssertTrue(LearningContent.topics.allSatisfy { $0.steps.count >= 4 && !$0.terms.isEmpty })
    }

    func testProfessionalReportPreservesEveryFullConclusion() {
        let person = Person(name: "回归样例", birthEpoch: 946684800)
        let chart = BaziEngine.cachedPaipan(clock: person.birthDate, gender: person.gender,
                                           longitude: person.useLongitude ? person.longitude : nil)
        let items = InterpretEngine.interpret(chart: chart)
        let report = ReportBuilder.lines(for: person, tier: .professional).joined(separator: "\n")
        for item in items { XCTAssertTrue(report.contains(item.conclusion), item.title) }
        let complete = ReportBuilder.lines(for: person, tier: .complete)
        XCTAssertTrue(complete.contains("【白话阅读指南】"))
    }

    func testDetailedReportKeepsInterpretationItemsInPDFContents() throws {
        let person = Person(name: "目录回归", birthEpoch: 946684800)
        let chart = BaziEngine.cachedPaipan(clock: person.birthDate, gender: person.gender,
                                           longitude: person.useLongitude ? person.longitude : nil)
        let firstTitle = try XCTUnwrap(InterpretEngine.interpret(chart: chart).first?.title)
        for tier in [ReportTier.professional, .complete] {
            let url = try XCTUnwrap(ReportBuilder.makePDF(for: person, tier: tier))
            defer { try? FileManager.default.removeItem(at: url) }
            let pdf = try XCTUnwrap(PDFDocument(url: url))
            let contents = try XCTUnwrap(pdf.page(at: 1)?.string)
                .components(separatedBy: .whitespacesAndNewlines).joined()
            XCTAssertTrue(contents.contains("详批条目"), tier.rawValue)
            XCTAssertTrue(contents.contains(firstTitle), tier.rawValue)
        }
    }

    @MainActor
    func testPhotoWriteFailureDoesNotReturnSuccessRecord() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: root)
            AppErrorCenter.shared.dismiss()
        }
        let store = SurveyStore(baseDirectory: root)
        let id = UUID()
        // A file occupies the directory path: deterministic write failure, even on privileged runners.
        try Data("occupied".utf8).write(to: root.appendingPathComponent(id.uuidString))
        let image = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32)).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
        }
        let task = SurveyTask(id: "regression", title: "回归照片", instruction: "", kind: .photo)
        let result = store.savePhoto(caseId: id, task: task, imageData: try XCTUnwrap(image.pngData()), loc: LocationManager())
        XCTAssertNil(result)
        XCTAssertNotNil(AppErrorCenter.shared.message)
    }

    @MainActor
    func testTwoRapidPhotosProduceDistinctReadableFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SurveyStore(baseDirectory: root)
        let id = UUID()
        let image = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32)).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
        }
        let task = SurveyTask(id: "regression", title: "回归照片", instruction: "", kind: .photo)
        let location = LocationManager()
        let data = try XCTUnwrap(image.pngData())
        let first = try XCTUnwrap(store.savePhoto(caseId: id, task: task, imageData: data, loc: location))
        let second = try XCTUnwrap(store.savePhoto(caseId: id, task: task, imageData: data, loc: location))
        XCTAssertNotEqual(first.fileName, second.fileName)
        for item in [first, second] {
            XCTAssertNotNil(UIImage(contentsOfFile: store.caseDir(id).appendingPathComponent(item.fileName).path))
            XCTAssertNotNil(UIImage(contentsOfFile: store.caseDir(id).appendingPathComponent(try XCTUnwrap(item.stampedFileName)).path))
        }
    }
}
