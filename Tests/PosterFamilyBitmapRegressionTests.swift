import CryptoKit
import ImageIO
import UIKit
import XCTest
@testable import Kanyu

/// Real Family Export entry point, independent of the frozen acceptance tests.
/// Synthetic people use real engines; raw PNGs are preserved in xcresult.
final class PosterFamilyBitmapRegressionTests: XCTestCase {
    @MainActor
    private func export(_ kind: PosterDynamicKind) throws {
        let person = Person(name: "位图回归人物", birthEpoch: 946684800)
        let snapshot: PosterDynamicSnapshot
        switch kind {
        case .bazi, .premium:
            let chart = BaziEngine.cachedPaipan(clock: person.birthDate, gender: person.gender,
                longitude: person.useLongitude ? person.longitude : nil)
            snapshot = .bazi(person: person, chart: chart, premium: kind == .premium)
        case .ziwei:
            let chart = ZiweiEngine.chart(clock: person.birthDate, gender: person.gender,
                longitude: person.useLongitude ? person.longitude : nil)
            snapshot = .ziwei(chart: chart, name: person.name, ownerIDs: [person.id])
        case .palm:
            let record = PalmRecord(personID: person.id, personName: person.name, kind: "手相",
                summary: "独立导出回归摘要", linesFlat: [0.2, 0.3, 0.4, 0.5])
            snapshot = .palm(record: record, ownerID: person.id)
        }
        XCTAssertEqual(snapshot.ownerID, person.id)
        let url = try PosterFamilyExport.image(snapshot: snapshot)
        defer { try? FileManager.default.removeItem(at: url) }
        let bytes = try Data(contentsOf: url)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(bytes as CFData, nil))
        let decoded = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0,
            [kCGImageSourceShouldCacheImmediately: true] as CFDictionary))
        XCTAssertEqual(decoded.width, 1080)
        XCTAssertGreaterThan(decoded.height, 1080)
        XCTAssertEqual(decoded.bitsPerComponent, 8)
        XCTAssertEqual(decoded.colorSpace?.model, .rgb)
        XCTAssertEqual(CGImageSourceGetStatus(source), .statusComplete)
        if kind == .premium { XCTAssertGreaterThan(decoded.height, 8192) }
        let attachment = XCTAttachment(data: bytes, uniformTypeIdentifier: "public.png")
        attachment.name = "family-business-\(kind.rawValue)"
        attachment.lifetime = .keepAlways
        add(attachment)
        let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let receipt = XCTAttachment(string: "kind=\(kind.rawValue) owner=\(person.id) pixels=\(decoded.width)x\(decoded.height) sha256=\(digest) sources=\(snapshot.sourceRecordIDs) versions=\(snapshot.sourceVersions)")
        receipt.name = "family-business-\(kind.rawValue)-receipt"
        receipt.lifetime = .keepAlways
        add(receipt)
    }

    @MainActor func testBaziBitmap() throws { try export(.bazi) }
    @MainActor func testPremiumBitmapBeyond8192Rows() throws { try export(.premium) }
    @MainActor func testZiweiBitmap() throws { try export(.ziwei) }
    @MainActor func testPalmBitmap() throws { try export(.palm) }
}
