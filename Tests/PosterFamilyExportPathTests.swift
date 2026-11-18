import Foundation
import UIKit
import XCTest
@testable import Kanyu

/// Exercises the new in-app ImageRenderer export path, not PosterRasterizer.
final class PosterFamilyExportPathTests: XCTestCase {
    @MainActor
    func testOwnedBaziExportsRealPNGAt1080Pixels() throws {
        let person = Person(name: "导出路径测试", birthEpoch: 946684800)
        let chart = BaziEngine.cachedPaipan(clock: person.birthDate, gender: person.gender,
                                            longitude: person.useLongitude ? person.longitude : nil)
        let snapshot = PosterDynamicSnapshot.bazi(person: person, chart: chart, premium: false)
        XCTAssertTrue(snapshot.canArchive)
        let url = try PosterFamilyExport.image(snapshot: snapshot)
        defer { try? FileManager.default.removeItem(at: url) }
        let data = try Data(contentsOf: url)
        XCTAssertEqual(Array(data.prefix(8)), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let image = try XCTUnwrap(UIImage(data: data)?.cgImage)
        XCTAssertEqual(image.width, 1080)
        XCTAssertGreaterThan(image.height, 1080)
        XCTAssertTrue(url.lastPathComponent.hasPrefix("kanyu-bazi-"))
    }

    @MainActor
    func testOrphanZiweiCannotCreateExportFile() throws {
        let person = Person(name: "无归属测试", birthEpoch: 946684800)
        let chart = ZiweiEngine.chart(clock: person.birthDate, gender: person.gender,
                                     longitude: person.useLongitude ? person.longitude : nil)
        let snapshot = PosterDynamicSnapshot.ziwei(chart: chart, name: person.name, ownerIDs: [])
        XCTAssertFalse(snapshot.canArchive)
        XCTAssertThrowsError(try PosterFamilyExport.image(snapshot: snapshot)) { error in
            guard case PosterFamilyExport.Failure.unverifiedOwner = error else {
                return XCTFail("Expected unverifiedOwner, got \(error)")
            }
        }
    }

    @MainActor
    func testConflictingPalmOwnerCannotCreateExportFile() throws {
        let actualOwner = UUID()
        let selectedOwner = UUID()
        let record = PalmRecord(personID: actualOwner, personName: "同名测试", kind: "手相",
                                summary: "测试摘要", linesFlat: [])
        let snapshot = PosterDynamicSnapshot.palm(record: record, ownerID: selectedOwner)
        XCTAssertFalse(snapshot.canArchive)
        XCTAssertTrue(snapshot.missingFields.contains { $0.id == "ownerID-conflict" && $0.blocking })
        XCTAssertThrowsError(try PosterFamilyExport.image(snapshot: snapshot)) { error in
            guard case PosterFamilyExport.Failure.unverifiedOwner = error else {
                return XCTFail("Expected unverifiedOwner, got \(error)")
            }
        }
    }
}
