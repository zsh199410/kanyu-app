import XCTest
@testable import Kanyu

final class AskConfidenceTests: XCTestCase {
    private func response(confidence: String? = nil, degraded: Bool = false, refused: Bool = false) throws -> AskResponse {
        var json: [String: Any] = ["answer": "这是一条尚未校验的回答", "degraded": degraded,
                                   "refused": refused, "model": "test", "facts": [], "caveats": []]
        if let confidence { json["confidence"] = confidence }
        return try JSONDecoder().decode(AskResponse.self, from: JSONSerialization.data(withJSONObject: json))
    }

    func testMissingOrUnknownConfidenceIsNotInventedAsHigh() throws {
        for value: String? in [nil, "", "百分之百"] {
            let result = try response(confidence: value)
            XCTAssertEqual(result.confidenceLabel, "未标注")
            XCTAssertFalse(result.confidenceDetail.contains("后校验通过"))
        }
    }

    func testFailureFlagsTakePrecedenceOverConflictingServerHighLabel() throws {
        XCTAssertEqual(try response(confidence: "高", degraded: true).confidenceLabel, "降级")
        XCTAssertEqual(try response(confidence: "高", refused: true).confidenceLabel, "拒绝")
        XCTAssertEqual(try response(confidence: "中").confidenceLabel, "中")
    }
}
