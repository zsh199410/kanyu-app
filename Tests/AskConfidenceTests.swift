import XCTest
@testable import Kanyu

final class AskConfidenceTests: XCTestCase {
    private func response(confidence: String? = nil, degraded: Bool = false, refused: Bool = false, answer: String = "这是一条尚未校验的回答") throws -> AskResponse {
        var json: [String: Any] = ["answer": answer, "degraded": degraded,
                                   "refused": refused, "model": "test", "facts": [], "caveats": []]
        if let confidence { json["confidence"] = confidence }
        return try JSONDecoder().decode(AskResponse.self, from: JSONSerialization.data(withJSONObject: json))
    }

    func testMissingOrUnknownConfidenceIsNotInventedAsHigh() throws {
        let values: [String?] = [nil, "", "百分之百"]
        for value in values {
            let result = try response(confidence: value)
            XCTAssertEqual(result.confidenceLabel, "未标注")
            XCTAssertFalse(result.confidenceDetail.contains("后校验通过"))
        }
    }

    func testAnswerWordingDoesNotInventServerVerification() throws {
        let result = try response(answer: "盘上无据")
        XCTAssertEqual(result.confidenceLabel, "未标注")
        XCTAssertFalse(result.confidenceDetail.contains("后校验通过"))
    }

    func testFailureFlagsTakePrecedenceOverConflictingServerHighLabel() throws {
        XCTAssertEqual(try response(confidence: "高", degraded: true).confidenceLabel, "降级")
        XCTAssertEqual(try response(confidence: "高", refused: true).confidenceLabel, "拒绝")
        XCTAssertEqual(try response(confidence: "中").confidenceLabel, "中")
    }
}
