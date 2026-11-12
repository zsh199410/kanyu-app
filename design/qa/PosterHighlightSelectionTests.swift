import XCTest
@testable import Kanyu

/// Opt-in CI test for the editorial poster. No original golden JSON is changed.
final class PosterHighlightSelectionTests: XCTestCase {
    private func sample(premium: Bool) -> (PosterDynamicSnapshot, [InterpretItem]) {
        let person = Person(name: "重点摘要样例", birthEpoch: 946684800)
        let chart = BaziEngine.cachedPaipan(clock: person.birthDate, gender: person.gender,
                                             longitude: person.useLongitude ? person.longitude : nil)
        return (PosterDynamicSnapshot.bazi(person: person, chart: chart, premium: premium),
                InterpretEngine.interpret(chart: chart))
    }

    func testPosterOnlyHasImportantSectionsNotFullEvidenceOrAdvice() {
        for premium in [false, true] {
            let (poster, _) = sample(premium: premium)
            let ids = poster.sections.map(\.id)
            XCTAssertTrue(ids.contains("pillars"))
            XCTAssertTrue(ids.contains("elements"))
            XCTAssertFalse(ids.contains("reading"))
            XCTAssertFalse(ids.contains("evidence"))
            XCTAssertFalse(poster.sections.flatMap(\.fields).contains { field in
                field.id.contains(".mechanism") || field.id.contains(".advice")
                    || field.id.contains(".link.")
            })
            XCTAssertTrue(poster.canArchive)
        }
    }

    func testHighlightTextIsShortTraceableExcerptNotFabricatedPrediction() {
        let (snapshot, originals) = sample(premium: true)
        let highlighted = snapshot.sections.flatMap(\.fields)
            .filter { $0.id.hasPrefix("highlight.") }
        XCTAssertGreaterThan(highlighted.count, 4)
        for field in highlighted {
            XCTAssertLessThanOrEqual(field.value.count, 89) // 88 + optional ellipsis
            XCTAssertFalse(field.source.isEmpty)
            let original = originals.first(where: { $0.title == field.label })
            XCTAssertNotNil(original)
            let sourceText = original!.conclusion.split(whereSeparator: { $0.isWhitespace })
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let excerpt = field.value.hasSuffix("…") ? String(field.value.dropLast()) : field.value
            XCTAssertTrue(sourceText.hasPrefix(excerpt), "Excerpt must come from real result for \(field.label)")
        }
    }

    func testMissingTopicsAreNotInvented() {
        let person = Person(name: "空主题", birthEpoch: 946684800)
        let chart = BaziEngine.cachedPaipan(clock: person.birthDate, gender: person.gender, longitude: nil)
        let sections = PosterHighlightSelection.baziSections(chart: chart, items: [],
                                                               pillars: [], elements: [], premium: true)
        XCTAssertFalse(sections.contains { $0.id.hasPrefix("highlight.") })
    }

    func testExcerptDoesNotClaimToBeTheFullSource() {
        XCTAssertEqual(PosterHighlightSelection.excerpt("结论短句。"), "结论短句。")
        let long = String(repeating: "来源中的真实文字，后续内容继续展开。", count: 20)
        let short = PosterHighlightSelection.excerpt(long)
        XCTAssertTrue(short.hasSuffix("…"))
        XCTAssertLessThanOrEqual(short.count, 89)
        XCTAssertTrue(long.hasPrefix(String(short.dropLast())))
    }
}
