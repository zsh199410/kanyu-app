// 罗盘纯数学回归（CompassMath，Sources/KanyuApp.swift）：二十四山／八宫换算、圆周平均、最短角差。
// 全部为不依赖定位、传感器与业务状态的纯函数；main 行为已稳定，锁死防漂移。
// 与风险点 (g) 相关：真北读数、坐山换算都经这组函数；偏角解析本身（declinationInfo）为 private，见审计报告缺口。
import XCTest
@testable import Kanyu

final class CompassMathTests: XCTestCase {
    func testNormalize() {
        XCTAssertEqual(CompassMath.normalize(370), 10, accuracy: 1e-9)
        XCTAssertEqual(CompassMath.normalize(-10), 350, accuracy: 1e-9)
        XCTAssertEqual(CompassMath.normalize(360), 0, accuracy: 1e-9)
        XCTAssertEqual(CompassMath.normalize(720), 0, accuracy: 1e-9)
        XCTAssertEqual(CompassMath.normalize(-360), 0, accuracy: 1e-9)
        XCTAssertEqual(CompassMath.normalize(0), 0, accuracy: 1e-9)
        XCTAssertEqual(CompassMath.normalize(359.9), 359.9, accuracy: 1e-9)
    }

    func testMountain() {
        XCTAssertEqual(CompassMath.mountain(for: 0), "子")
        XCTAssertEqual(CompassMath.mountain(for: 7.5), "癸")
        XCTAssertEqual(CompassMath.mountain(for: 180), "午")
        XCTAssertEqual(CompassMath.mountain(for: 90), "卯")
        XCTAssertEqual(CompassMath.mountain(for: 352.5), "子")
        XCTAssertEqual(CompassMath.mountain(for: 360), "子")
        XCTAssertEqual(CompassMath.mountain(for: -7.5), "子")
    }

    func testPalace() {
        XCTAssertEqual(CompassMath.palace(for: 0), "坎")
        XCTAssertEqual(CompassMath.palace(for: 22.5), "艮")
        XCTAssertEqual(CompassMath.palace(for: 180), "离")
        XCTAssertEqual(CompassMath.palace(for: 90), "震")
        XCTAssertEqual(CompassMath.palace(for: 360), "坎")
    }

    func testFormat() {
        XCTAssertEqual(CompassMath.format(-1), "—")
        XCTAssertEqual(CompassMath.format(-0.5), "—")
        XCTAssertEqual(CompassMath.format(0), "0.0°")
        XCTAssertEqual(CompassMath.format(10.5), "10.5°")
        XCTAssertEqual(CompassMath.format(370), "10.0°")
    }

    func testCircularMeanEmpty() {
        let result = CompassMath.circularMean([])
        XCTAssertEqual(result.mean, -1, accuracy: 1e-9)
        XCTAssertEqual(result.r, 0, accuracy: 1e-9)
    }

    func testCircularMeanWrapsAroundNorth() {
        let result = CompassMath.circularMean([359, 1])
        XCTAssertEqual(result.mean, 0, accuracy: 0.5, "359° 与 1° 的圆周均值应为 0° 而非 180°")
        XCTAssertGreaterThan(result.r, 0.99)
    }

    func testCircularMeanSingle() {
        let result = CompassMath.circularMean([90])
        XCTAssertEqual(result.mean, 90, accuracy: 1e-9)
        XCTAssertEqual(result.r, 1, accuracy: 1e-9)
    }

    func testCircularMeanOppositeCancels() {
        let result = CompassMath.circularMean([0, 180])
        XCTAssertLessThan(result.r, 0.01, "正对的两个读数集中度应接近 0")
    }

    func testShortestDiff() {
        XCTAssertEqual(CompassMath.shortestDiff(from: 350, to: 10), 20, accuracy: 1e-9)
        XCTAssertEqual(CompassMath.shortestDiff(from: 10, to: 350), -20, accuracy: 1e-9)
        XCTAssertEqual(CompassMath.shortestDiff(from: 0, to: 90), 90, accuracy: 1e-9)
        XCTAssertEqual(CompassMath.shortestDiff(from: 0, to: 180), -180, accuracy: 1e-9)
        XCTAssertEqual(CompassMath.shortestDiff(from: 45, to: 45), 0, accuracy: 1e-9)
    }

    func testKindLabel() {
        XCTAssertEqual(CompassMath.kindLabel("photo"), "照片")
        XCTAssertEqual(CompassMath.kindLabel("video"), "视频")
        XCTAssertEqual(CompassMath.kindLabel("scan3d"), "三维扫描")
        XCTAssertEqual(CompassMath.kindLabel("artrack"), "实景轨迹")
        XCTAssertEqual(CompassMath.kindLabel("unknown-kind"), "unknown-kind")
    }

    func testMountainsAndPalacesTables() {
        XCTAssertEqual(CompassMath.mountains.count, 24)
        XCTAssertEqual(CompassMath.palaces.count, 8)
        XCTAssertEqual(CompassMath.mountains[0], "子")
        XCTAssertEqual(CompassMath.mountains[12], "午")
        XCTAssertEqual(CompassMath.mountains[23], "壬")
        XCTAssertEqual(CompassMath.palaces[0], "坎")
        XCTAssertEqual(CompassMath.palaces[4], "离")
    }
}
