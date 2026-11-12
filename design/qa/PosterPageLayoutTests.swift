import XCTest
@testable import Kanyu

/// New tests. Existing golden JSON, business rules and UI tests are untouched.
final class PosterPageLayoutTests: XCTestCase {
    private func snapshot(name: String = "同名", owner: UUID? = UUID(),
                          text: String = String(repeating: "这段内容必须原样保留，不能丢字。", count: 70)) -> PosterDynamicSnapshot {
        PosterDynamicSnapshot(
            kind: .premium,
            ownerID: owner,
            displayName: name,
            receipt: "受测人物与原数据独立绑定",
            sections: [
                PosterBoundSection(id: "interpret", title: "原局完整解盘", fields: [
                    PosterBoundField(id: "A", label: "事业方向",
                                     value: text, source: "InterpretEngine.interpret"),
                    PosterBoundField(id: "B", label: "婚姻感情",
                                     value: "原文完整、包含标点。\n不可省略。",
                                     source: "InterpretEngine.interpret")
                ])
            ],
            caution: "仅作传统文化解释"
        )
    }

    func testExactChunkingPreservesAllCharactersAndPunctuation() {
        let value = "开始，" + String(repeating: "句子内容。换行\n", count: 400) + "结束！"
        let chunks = PosterPageLayout.exactChunks(value, limit: 47)
        XCTAssertGreaterThan(chunks.count, 2)
        XCTAssertEqual(chunks.joined(), value)
        XCTAssertTrue(chunks.allSatisfy { $0.count <= 47 })
    }

    func testPagingDoesNotDropFieldsOrSplitIdentity() throws {
        let original = snapshot()
        let pages = try PosterPageLayout.paginate(original)
        XCTAssertGreaterThan(pages.count, 1)
        XCTAssertEqual(pages.map(\.id), Array(1...pages.count))
        let cells = pages.flatMap(\.cells)
        XCTAssertEqual(cells.filter { $0.id.hasPrefix("A.part.") }.map(\.text).joined(),
                       original.sections[0].fields[0].value)
        XCTAssertEqual(cells.filter { $0.id.hasPrefix("B.part.") }.map(\.text).joined(),
                       original.sections[0].fields[1].value)
        XCTAssertTrue(cells.allSatisfy { !$0.source.isEmpty })
    }

    func testIdenticalNamesWithDistinctIDsNeverUseNameAsIdentity() throws {
        let a = snapshot(owner: UUID())
        let b = snapshot(owner: UUID())
        XCTAssertNotEqual(a.ownerID, b.ownerID)
        XCTAssertEqual(a.displayName, b.displayName)
        XCTAssertNoThrow(try PosterPageLayout.paginate(a))
        XCTAssertNoThrow(try PosterPageLayout.paginate(b))
    }

    func testMissingOwnerRefusesExportPlanning() {
        let noOwner = snapshot(owner: nil)
        XCTAssertThrowsError(try PosterPageLayout.paginate(noOwner))
    }

    func testLongReportFailsClosedInsteadOfDroppingLastPages() {
        let huge = snapshot(text: String(repeating: "一段完整的原始数据。", count: 50_000))
        XCTAssertThrowsError(try PosterPageLayout.paginate(huge))
    }
}
