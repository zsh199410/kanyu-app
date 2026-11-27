import XCTest
import UIKit
@testable import Kanyu

final class V5ReportOwnershipTests: XCTestCase {
    private func entry(_ url: URL, inferred: UUID?) -> ReportHistoryEntry {
        ReportHistoryEntry(id: url, url: url, personID: inferred, personName: "同名测试",
            kind: "归档", icon: "doc", generatedAt: Date(timeIntervalSince1970: 0),
            sizeKB: 12, tierName: "专业", hashShort: "abcdef")
    }
    func testLegacyFilenameCannotInheritInferredNameOwnership() {
        for name in ["poster-同名测试-song.png", "ziwei-poster-同名测试.png", "命书-同名测试.pdf"] {
            let input = entry(URL(fileURLWithPath: "/missing/" + name), inferred: UUID())
            let output = V5ReportOwnership.verified(input)
            XCTAssertNil(output.personID)
            XCTAssertEqual(output.url, input.url)
            XCTAssertEqual(output.personName, input.personName)
            XCTAssertEqual(output.hashShort, input.hashShort)
        }
    }
    func testExplicitPosterUUIDWinsOverInferredNameAndPreservesFile() throws {
        let owner = UUID()
        let name = "palm-poster-同名测试-song-pid" + owner.uuidString.replacingOccurrences(of: "-", with: "").lowercased() + ".png"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        let bytes = Data([1, 2, 3])
        try bytes.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(V5ReportOwnership.verified(entry(url, inferred: UUID())).personID, owner)
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }
    @MainActor func testPDFRequiresItsOwnMetadataAndIgnoresFilenameUUID() throws {
        let owner = UUID(), filenameOwner = UUID()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("命书-同名-pid" + filenameOwner.uuidString.replacingOccurrences(of: "-", with: "") + ".pdf")
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [kCGPDFContextKeywords as String: "personID=\(owner.uuidString)"]
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 200, height: 200), format: format)
        try renderer.writePDF(to: url) { context in context.beginPage() }
        let original = try Data(contentsOf: url)
        XCTAssertEqual(V5ReportOwnership.verified(entry(url, inferred: UUID())).personID, owner)
        XCTAssertEqual(try Data(contentsOf: url), original)
    }
}
