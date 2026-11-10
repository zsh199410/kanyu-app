import XCTest
@testable import Kanyu

final class CompassBearingResolverTests: XCTestCase {
    func testMagneticAloneDoesNotInventTrueNorth() {
        XCTAssertNil(CompassBearingResolver.resolve(manual: nil, magnetic: 90, deviceTrue: -1,
                                                   latitude: nil, longitude: nil, year: 2026))
    }

    func testManualOverrideUsesMatchingBearingAndReceipt() throws {
        let result = try XCTUnwrap(CompassBearingResolver.resolve(manual: 5, magnetic: 358, deviceTrue: 350,
                                                                latitude: nil, longitude: nil, year: 2026))
        XCTAssertEqual(result.trueNorth, 3, accuracy: 0.001)
        XCTAssertEqual(result.correction, 5)
        XCTAssertEqual(result.source, "manual")
    }

    func testDeviceTrueNorthWorksWithoutLocationAndWrapsCorrection() throws {
        let result = try XCTUnwrap(CompassBearingResolver.resolve(manual: nil, magnetic: 359, deviceTrue: 1,
                                                                latitude: nil, longitude: nil, year: 2026))
        XCTAssertEqual(result.trueNorth, 1)
        XCTAssertEqual(result.correction, 2, accuracy: 0.001)
        XCTAssertEqual(result.source, "device")
    }

    func testInvalidManualDoesNotBecomeCorrection() {
        for value in [Double.nan, .infinity, -.infinity, 181, -181] {
            XCTAssertNil(CompassBearingResolver.resolve(manual: value, magnetic: 10, deviceTrue: -1,
                                                       latitude: nil, longitude: nil, year: 2026))
        }
    }

    func testModelNeedsValidCoordinatesAndValidEpoch() throws {
        XCTAssertNil(CompassBearingResolver.resolve(manual: nil, magnetic: 10, deviceTrue: -1,
                                                   latitude: 30, longitude: nil, year: 2026))
        XCTAssertNil(CompassBearingResolver.resolve(manual: nil, magnetic: 10, deviceTrue: -1,
                                                   latitude: 91, longitude: 100, year: 2026))
        XCTAssertNil(CompassBearingResolver.resolve(manual: nil, magnetic: 10, deviceTrue: -1,
                                                   latitude: 30, longitude: 107, year: 2031))
        let result = try XCTUnwrap(CompassBearingResolver.resolve(manual: nil, magnetic: 10, deviceTrue: -1,
                                                                latitude: 30.654, longitude: 107.77, year: 2026))
        XCTAssertEqual(result.source, "wmm2025")
        XCTAssertTrue(result.trueNorth.isFinite)
        XCTAssertEqual(result.trueNorth, CompassMath.normalize(10 + result.correction), accuracy: 0.001)
    }

    func testInvalidSensorHeadingIsRejected() {
        for magnetic in [Double.nan, .infinity, -1, 360] {
            XCTAssertNil(CompassBearingResolver.resolve(manual: 5, magnetic: magnetic, deviceTrue: 10,
                                                       latitude: nil, longitude: nil, year: 2026))
        }
    }
}
