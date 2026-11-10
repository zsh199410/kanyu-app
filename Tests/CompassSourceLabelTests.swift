import XCTest
@testable import Kanyu

/// Regression: an absent or unknown declination source must never be described as WMM2025.
final class CompassSourceLabelTests: XCTestCase {
    private func lock(source: String) -> CompassLock {
        CompassLock(magnetic: 10, trueNorth: 11, declination: 1,
                    declinationSource: source, mountain: "子", palace: "坎",
                    accuracy: 2, tilt: 0, latitude: nil, longitude: nil,
                    timestamp: Date(timeIntervalSince1970: 0), samples: 3, spread: 1)
    }

    func testKnownSourcesRetainAccurateLabels() {
        XCTAssertEqual(lock(source: "device").declinationSourceText, "设备真北（系统内建校正）")
        XCTAssertEqual(lock(source: "manual").declinationSourceText, "手动填入")
        XCTAssertEqual(lock(source: "wmm2025").declinationSourceText, "WMM2025 现算")
    }

    func testMissingOrUnexpectedSourceDoesNotClaimWMM() {
        XCTAssertEqual(lock(source: "none").declinationSourceText, "磁偏角来源未知")
        XCTAssertEqual(lock(source: "").declinationSourceText, "磁偏角来源未知")
        XCTAssertEqual(lock(source: "future-model").declinationSourceText, "磁偏角来源未知")
    }
}
