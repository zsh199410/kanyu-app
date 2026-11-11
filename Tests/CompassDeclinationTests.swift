// WMM2025 磁偏角现算回归（CompassDeclination，Sources/CompassModule.swift）＋罗盘锁定记录（CompassLock）。
// 全部为不依赖定位与传感器的纯函数；与风险点 (g) 相关：无定位伪造真北的根因在 private 的
// declinationInfo／trueDisplay（不可测，见审计报告），此处锁死其依赖的公开计算层。
// 梁平金标准：Web test_compass.py 对拍值 −3.32066°（2026 年）；此处用 ±0.5° 宽容差锁定，防系数表漂移。
// 注意：magneticField 的水平分量 < 1e-9 nT 才返回 nil，常规坐标下远高于阈值，该分支在单元测试中不可达，见报告。
import XCTest
@testable import Kanyu

final class CompassDeclinationTests: XCTestCase {
    private let liangpingLat = 30.654
    private let liangpingLon = 107.770
    private let year2026 = 2026.5

    func testLegendreSeedValues() {
        let sinPhi = 0.5
        let cosPhi = (0.75).squareRoot()
        let result = CompassDeclination.legendre(sinPhi: sinPhi, cosPhi: cosPhi)
        XCTAssertEqual(result.p[0][0], 1, accuracy: 1e-12)
        XCTAssertEqual(result.p[1][0], sinPhi, accuracy: 1e-12)
        XCTAssertEqual(result.p[1][1], cosPhi, accuracy: 1e-12)
        XCTAssertEqual(result.dp[1][0], cosPhi, accuracy: 1e-12)
        XCTAssertEqual(result.dp[1][1], -sinPhi, accuracy: 1e-12)
    }

    func testLiangpingDeclination2026() throws {
        let value = try XCTUnwrap(CompassDeclination.liangpingDeclination(year: year2026), "梁平 2026 年 WMM 磁偏角应能算出")
        XCTAssertEqual(value, -3.32, accuracy: 0.5, "梁平 2026 年磁偏角约 −3.3°（Web 金标准 −3.32066°）")
        XCTAssertLessThan(value, 0, "梁平为西偏（负值）")
    }

    func testLiangpingDeclinationMatchesDirectCall() throws {
        let viaHelper = try XCTUnwrap(CompassDeclination.liangpingDeclination(year: year2026))
        let direct = try XCTUnwrap(CompassDeclination.declination(latitude: liangpingLat, longitude: liangpingLon, year: year2026))
        XCTAssertEqual(viaHelper, direct, accuracy: 1e-9)
    }

    func testMagneticFieldLiangpingComponents() throws {
        let field = try XCTUnwrap(CompassDeclination.magneticField(latitude: liangpingLat, longitude: liangpingLon, year: year2026))
        XCTAssertEqual(field.declination, -3.32, accuracy: 0.5)
        XCTAssertGreaterThan(field.horizontal, 1000, "梁平水平分量应为数万 nT 量级")
        XCTAssertLessThan(field.horizontal, 60000)
        XCTAssertGreaterThan(field.total, field.horizontal)
        XCTAssertGreaterThan(field.inclination, 0, "北半球磁倾角为正")
        XCTAssertLessThan(field.inclination, 90)
    }

    func testFieldComponentsSign() throws {
        let field = try XCTUnwrap(CompassDeclination.field(latitude: liangpingLat, longitude: liangpingLon, year: year2026))
        XCTAssertGreaterThan(field.x, 10000, "北向分量 X 应为正且上万 nT")
        XCTAssertLessThan(field.y, 0, "西偏时东向分量 Y 为负")
        XCTAssertGreaterThan(field.z, 10000, "北半球向下分量 Z 为正")
    }

    func testYearOutOfModelReturnsNil() {
        XCTAssertNil(CompassDeclination.declination(latitude: liangpingLat, longitude: liangpingLon, year: 2024.9))
        XCTAssertNil(CompassDeclination.declination(latitude: liangpingLat, longitude: liangpingLon, year: 2030.1))
        XCTAssertNil(CompassDeclination.magneticField(latitude: liangpingLat, longitude: liangpingLon, year: 2024.0))
        XCTAssertNotNil(CompassDeclination.declination(latitude: liangpingLat, longitude: liangpingLon, year: 2025.0))
        XCTAssertNotNil(CompassDeclination.declination(latitude: liangpingLat, longitude: liangpingLon, year: 2030.0))
    }

    func testInvalidCoordinatesReturnNil() {
        XCTAssertNil(CompassDeclination.field(latitude: 91, longitude: 107.77, year: year2026))
        XCTAssertNil(CompassDeclination.field(latitude: -91, longitude: 107.77, year: year2026))
        XCTAssertNil(CompassDeclination.field(latitude: 30.654, longitude: 181, year: year2026))
        XCTAssertNil(CompassDeclination.field(latitude: .nan, longitude: 107.77, year: year2026))
        XCTAssertNil(CompassDeclination.field(latitude: 30.654, longitude: .nan, year: year2026))
        XCTAssertNil(CompassDeclination.field(latitude: 30.654, longitude: 107.77, year: .nan))
        XCTAssertNil(CompassDeclination.declination(latitude: 91, longitude: 0, year: year2026))
    }

    func testFieldAtPolesReturnsNil() {
        XCTAssertNil(CompassDeclination.field(latitude: 90, longitude: 0, year: year2026), "北极点地心纬余弦≈0，不编造场量")
        XCTAssertNil(CompassDeclination.field(latitude: -90, longitude: 0, year: year2026))
    }

    // MARK: - CompassLock（锁定记录纯换算）

    private func lock(mountain: String = "午", trueNorth: Double = 180) -> CompassLock {
        CompassLock(magnetic: 183.3, trueNorth: trueNorth, declination: -3.3, declinationSource: "wmm2025",
                    mountain: mountain, palace: "离", accuracy: 2.5, tilt: 1.0,
                    latitude: 30.654, longitude: 107.77, timestamp: Date(timeIntervalSince1970: 1_700_000_000),
                    samples: 12, spread: 1.2)
    }

    func testSitFace() {
        let sitFace = lock().sitFace()
        XCTAssertEqual(sitFace.sit, "午")
        XCTAssertEqual(sitFace.face, "子")
        XCTAssertEqual(sitFace.sitPalace, "离")
        XCTAssertEqual(sitFace.facePalace, "坎")
    }

    func testSitFaceText() {
        XCTAssertEqual(lock().sitFaceText, "午山子向 · 坐离宫向坎宫")
    }

    func testSitDegreeIsTrueNorth() {
        XCTAssertEqual(lock(trueNorth: 182.5).sitDegree, 182.5, accuracy: 1e-9)
    }

    func testDeclinationSourceText() {
        XCTAssertEqual(lock().declinationSourceText, "WMM2025 现算")
        var device = lock()
        device.declinationSource = "device"
        XCTAssertEqual(device.declinationSourceText, "设备真北（系统内建校正）")
        var manual = lock()
        manual.declinationSource = "manual"
        XCTAssertEqual(manual.declinationSourceText, "手动填入")
    }

    func testHeadingReadingPassthrough() {
        let reading = lock().headingReading()
        XCTAssertEqual(reading.pointName, "大门外朝内")
        XCTAssertEqual(reading.trueNorth, 180, accuracy: 1e-9)
        XCTAssertEqual(reading.magnetic, 183.3, accuracy: 1e-9)
        XCTAssertEqual(reading.mountain, "午")
    }

    func testLockCodableRoundTrip() throws {
        let original = lock()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CompassLock.self, from: data)
        XCTAssertEqual(decoded, original)
    }
}
