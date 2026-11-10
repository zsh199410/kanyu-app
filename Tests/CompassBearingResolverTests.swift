import XCTest
@testable import Kanyu

final class CompassBearingResolverTests: XCTestCase {
    func testManualTextValidationDistinguishesEmptyInvalidAndValid() {
        for text in ["", "  ", "\n"] {
            XCTAssertFalse(CompassManualDeclinationInput.isInvalid(text))
        }
        for text in ["abc", "12abc", "NaN", "inf", "181", "-181", "1,5"] {
            XCTAssertTrue(CompassManualDeclinationInput.isInvalid(text), "Expected invalid: \(text)")
        }
        for text in ["0", "-3.3", " 180 ", "-180", "+5"] {
            XCTAssertFalse(CompassManualDeclinationInput.isInvalid(text), "Expected valid: \(text)")
        }
    }

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

    func testInvalidExplicitManualDoesNotSilentlyUseDeviceOrWMM() {
        for value in [Double.nan, .infinity, -.infinity, 181, -181] {
            XCTAssertNil(CompassBearingResolver.resolve(manual: value, magnetic: 10, deviceTrue: 15,
                                                       latitude: 30.654, longitude: 107.77, year: 2026),
                         "Invalid manual correction must not fall back to a different source")
        }
        let automatic = CompassBearingResolver.resolve(manual: nil, magnetic: 10, deviceTrue: 15,
                                                       latitude: 30.654, longitude: 107.77, year: 2026)
        XCTAssertEqual(automatic?.source, "device")
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

    func testReceiptRejectsSourceSwitchDuringSampling() throws {
        let initial = try XCTUnwrap(CompassBearingResolver.resolve(
            manual: 5, magnetic: 90, deviceTrue: -1,
            latitude: nil, longitude: nil, year: 2026))
        let changed = try XCTUnwrap(CompassBearingResolver.resolve(
            manual: nil, magnetic: 90, deviceTrue: 95,
            latitude: nil, longitude: nil, year: 2026))
        let receipt = (source: initial.source, correction: initial.correction)
        XCTAssertTrue(CompassSampleReceipt.matches(receipt, current: initial))
        XCTAssertFalse(CompassSampleReceipt.matches(receipt, current: changed))
        XCTAssertFalse(CompassSampleReceipt.matches(receipt, current: nil))
    }

    func testReceiptRejectsManualCorrectionChangeButAllowsSmallDrift() throws {
        let initial = try XCTUnwrap(CompassBearingResolver.resolve(
            manual: 5, magnetic: 90, deviceTrue: -1,
            latitude: nil, longitude: nil, year: 2026))
        let within = try XCTUnwrap(CompassBearingResolver.resolve(
            manual: 5.1, magnetic: 90, deviceTrue: -1,
            latitude: nil, longitude: nil, year: 2026))
        let changed = try XCTUnwrap(CompassBearingResolver.resolve(
            manual: 6, magnetic: 90, deviceTrue: -1,
            latitude: nil, longitude: nil, year: 2026))
        let receipt = (source: initial.source, correction: initial.correction)
        XCTAssertTrue(CompassSampleReceipt.matches(receipt, current: within))
        XCTAssertFalse(CompassSampleReceipt.matches(receipt, current: changed))
    }

    func testReceiptRejectsNonFiniteValuesIncludingDeviceSource() {
        let valid = CompassBearingResolver.Result(trueNorth: 95, correction: 5, source: "device")
        let invalidCorrection = CompassBearingResolver.Result(trueNorth: 95, correction: .nan, source: "device")
        let invalidBearing = CompassBearingResolver.Result(trueNorth: .infinity, correction: 5, source: "device")
        XCTAssertFalse(CompassSampleReceipt.matches((source: "device", correction: .nan), current: valid))
        XCTAssertFalse(CompassSampleReceipt.matches((source: "device", correction: 5), current: invalidCorrection))
        XCTAssertFalse(CompassSampleReceipt.matches((source: "device", correction: 5), current: invalidBearing))
        XCTAssertTrue(CompassSampleReceipt.matches((source: "device", correction: 5), current: valid))
    }

    func testDeviceReceiptAllowsHeadingNoiseWithoutChangingSource() throws {
        let initial = try XCTUnwrap(CompassBearingResolver.resolve(
            manual: nil, magnetic: 90, deviceTrue: 95,
            latitude: nil, longitude: nil, year: 2026))
        let next = try XCTUnwrap(CompassBearingResolver.resolve(
            manual: nil, magnetic: 91, deviceTrue: 97,
            latitude: nil, longitude: nil, year: 2026))
        XCTAssertTrue(CompassSampleReceipt.matches(
            (source: initial.source, correction: initial.correction), current: next))
    }
}
