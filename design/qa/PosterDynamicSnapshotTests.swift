import XCTest
@testable import Kanyu

/// Newly-added regression only. Keeps the existing Bazi engine and golden charts unchanged.
final class PosterDynamicSnapshotTests: XCTestCase {
    func testElementPercentagesUseBaziChartPercentUnitsOnce() {
        let person = Person(name: "五行单位校验", birthEpoch: 946684800)
        let chart = BaziEngine.cachedPaipan(clock: person.birthDate, gender: person.gender,
                                            longitude: person.useLongitude ? person.longitude : nil)
        let snapshot = PosterDynamicSnapshot.bazi(person: person, chart: chart, premium: false)
        let fields = snapshot.sections.first(where: { $0.id == "elements" })?.fields ?? []
        XCTAssertEqual(fields.count, 5)
        XCTAssertEqual(snapshot.ownerID, person.id)
        XCTAssertTrue(snapshot.canArchive)
        XCTAssertEqual(chart.wuxingPercents.reduce(0, +), 100, accuracy: 0.01)

        for (index, field) in fields.enumerated() {
            let percent = chart.wuxingPercents[index]
            XCTAssertGreaterThanOrEqual(percent, 0)
            XCTAssertLessThanOrEqual(percent, 100)
            XCTAssertEqual(field.value, String(format: "%.1f%%", percent),
                           "Engine values are already percentages; multiplying by 100 would show 1600% instead of 16%")
            XCTAssertEqual(field.source, "BaziChart.wuxingPercents")
        }
    }

    func testSameNamePeopleRetainDistinctPosterIdentity() {
        let a = Person(name: "同名人物", birthEpoch: 946684800)
        let b = Person(name: "同名人物", birthEpoch: 978307200)
        let chartA = BaziEngine.cachedPaipan(clock: a.birthDate, gender: a.gender,
                                             longitude: a.useLongitude ? a.longitude : nil)
        let chartB = BaziEngine.cachedPaipan(clock: b.birthDate, gender: b.gender,
                                             longitude: b.useLongitude ? b.longitude : nil)
        let left = PosterDynamicSnapshot.bazi(person: a, chart: chartA, premium: false)
        let right = PosterDynamicSnapshot.bazi(person: b, chart: chartB, premium: true)
        XCTAssertNotEqual(a.id, b.id)
        XCTAssertEqual(left.ownerID, a.id)
        XCTAssertEqual(right.ownerID, b.id)
        XCTAssertNotEqual(left.receipt, right.receipt)
        XCTAssertTrue(left.canArchive)
        XCTAssertTrue(right.canArchive)
    }

    func testZiweiPreviewWithNoOwnerIDCannotBeArchived() {
        let time = Date(timeIntervalSince1970: 946684800)
        let chart = ZiweiEngine.cachedChart(clock: time, gender: "M", longitude: nil)
        let preview = PosterDynamicSnapshot.ziwei(chart: chart, name: "同名人物", ownerID: nil)
        XCTAssertEqual(preview.kind, .ziwei)
        XCTAssertNil(preview.ownerID)
        XCTAssertFalse(preview.canArchive)
        XCTAssertEqual(preview.sections.first?.fields.count, chart.palaces.count)
    }
}
