import XCTest
import PDFKit
@testable import Kanyu

final class ExportCompassRegressionTests: XCTestCase {
    func testReportWithPathCharactersExportsReadablePDF() throws {
        let person = Person(name: "张/三\\测试:报告", birthEpoch: 946684800)
        let url = try XCTUnwrap(ReportBuilder.makePDF(for: person, tier: .concise))
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(url.deletingLastPathComponent().standardizedFileURL,
                       FileManager.default.temporaryDirectory.standardizedFileURL)
        let pdf = try XCTUnwrap(PDFDocument(url: url))
        XCTAssertGreaterThanOrEqual(pdf.pageCount, 3)
    }

    func testExportNameBoundsUTF8AndPreservesOrdinaryNames() {
        XCTAssertEqual(ReportBuilder.exportName("张三"), "张三")
        XCTAssertEqual(ReportBuilder.exportName("  "), "未命名")
        XCTAssertLessThanOrEqual(ReportBuilder.exportName(String(repeating: "张", count: 200)).utf8.count, 80)
        XCTAssertFalse(ReportBuilder.exportName("a\u{0}/b").contains("/"))
    }

    func testCompassRejectsInvalidInputs() {
        for latitude in [Double.nan, .infinity, -.infinity, -91, 91] {
            XCTAssertNil(CompassDeclination.declination(latitude: latitude, longitude: 107.77, year: 2026))
        }
        for longitude in [Double.nan, .infinity, -181, 181] {
            XCTAssertNil(CompassDeclination.declination(latitude: 30.654, longitude: longitude, year: 2026))
        }
        for year in [Double.nan, .infinity, 2024, 2031] {
            XCTAssertNil(CompassDeclination.declination(latitude: 30.654, longitude: 107.77, year: year))
        }
        XCTAssertNil(CompassDeclination.field(latitude: 0, longitude: 0, year: 2026, height: .nan))
    }

    func testCompassValidLocationStillProducesFiniteField() throws {
        let field = try XCTUnwrap(CompassDeclination.magneticField(latitude: 30.654, longitude: 107.77, year: 2026))
        XCTAssertTrue(field.declination.isFinite)
        XCTAssertGreaterThan(field.total, 20000)
        XCTAssertLessThan(field.total, 70000)
        XCTAssertNil(CompassDeclination.declination(latitude: 90, longitude: 0, year: 2026))
    }
}
