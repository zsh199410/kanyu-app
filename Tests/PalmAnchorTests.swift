import XCTest
@testable import Kanyu

final class PalmAnchorTests: XCTestCase {
    // 直立标准掌（Vision 归一化坐标，左下原点）
    private func uprightJoints() -> [String: CGPoint] {
        [
            "wrist": CGPoint(x: 0.50, y: 0.10),
            "middleMCP": CGPoint(x: 0.50, y: 0.75),
            "indexMCP": CGPoint(x: 0.35, y: 0.72),
            "littleMCP": CGPoint(x: 0.65, y: 0.70),
            "thumbCMC": CGPoint(x: 0.30, y: 0.35),
            "thumbTip": CGPoint(x: 0.18, y: 0.55),
            "indexTip": CGPoint(x: 0.33, y: 0.98),
            "middleTip": CGPoint(x: 0.50, y: 1.00),
            "littleTip": CGPoint(x: 0.68, y: 0.95),
        ]
    }

    func testAnchoredLinesShape() {
        guard let lines = anchoredPalmLines(joints: uprightJoints()) else {
            XCTFail("直立标准掌应能锚定出三线")
            return
        }
        XCTAssertEqual(lines.count, 3)
        for line in lines {
            XCTAssertEqual(line.count, 4)
            for pt in line {
                XCTAssertTrue(pt.x >= 0 && pt.x <= 1, "x 越界：\(pt)")
                XCTAssertTrue(pt.y >= 0 && pt.y <= 1, "y 越界：\(pt)")
            }
        }
        // 画布左上原点：感情线应在智慧线上方（y 更小）
        let heartY = lines[0].map { $0.y }.reduce(0, +) / 4
        let headY = lines[1].map { $0.y }.reduce(0, +) / 4
        XCTAssertTrue(heartY < headY, "感情线应在智慧线上方")
        // 生命线起点与智慧线起点相近（同在虎口附近）
        let d = hypot(lines[2][0].x - lines[1][0].x, lines[2][0].y - lines[1][0].y)
        XCTAssertTrue(d < 0.15, "生命线与智慧线起点应相近，实测 \(d)")
    }

    func testAnchoredLinesFollowsTilt() {
        // 手整体绕掌心顺时针转 90°：线应跟着转，感情线仍在智慧线手指侧
        let center = CGPoint(x: 0.5, y: 0.5)
        var tilted = uprightJoints()
        func rot(_ p: CGPoint) -> CGPoint {
            let dx = p.x - center.x; let dy = p.y - center.y
            return CGPoint(x: center.x + dy, y: center.y - dx)
        }
        for k in tilted.keys { tilted[k] = rot(tilted[k]!) }
        guard let lines = anchoredPalmLines(joints: tilted) else {
            XCTFail("斜手应能锚定出三线")
            return
        }
        XCTAssertEqual(lines.count, 3)
        let wrist = tilted["wrist"]!
        let mm = tilted["middleMCP"]!
        let ux = mm.x - wrist.x; let uy = mm.y - wrist.y
        let len = (ux * ux + uy * uy).squareRoot()
        func proj(_ pt: CGPoint) -> CGFloat {
            let vx = pt.x; let vy = 1 - pt.y
            return ((vx - wrist.x) * ux + (vy - wrist.y) * uy) / len
        }
        let heartA = lines[0].map(proj).reduce(0, +) / 4
        let headA = lines[1].map(proj).reduce(0, +) / 4
        XCTAssertTrue(heartA > headA, "感情线应在智慧线手指侧")
    }

    func testMissingJointsReturnsNil() {
        XCTAssertNil(anchoredPalmLines(joints: ["wrist": CGPoint(x: 0.5, y: 0.1)]))
        XCTAssertNil(palmFrame(joints: [:]))
    }

    func testSmoothLinePoints() {
        let anchors = [CGPoint(x: 0, y: 0), CGPoint(x: 0.3, y: 0.4), CGPoint(x: 0.6, y: 0.3), CGPoint(x: 1, y: 0.8)]
        let pts = smoothLinePoints(anchors)
        XCTAssertEqual(pts.first, anchors.first, "采样起点应为首个锚点")
        XCTAssertEqual(pts.last, anchors.last, "采样终点应为末个锚点")
        XCTAssertEqual(pts.count, 1 + 3 * 16, "每段 16 段采样")
        for pt in pts {
            XCTAssertTrue(pt.x >= -0.05 && pt.x <= 1.05 && pt.y >= -0.05 && pt.y <= 1.05, "采样点不应大幅越界：\(pt)")
        }
        // 锚点少于 3 个时原样返回（直线即可）
        XCTAssertEqual(smoothLinePoints([CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1)]).count, 2)
    }

    // MARK: - 边缘贴合
    func testEdgeMapSampling() {
        // 5x5，中心列亮带
        var values = [Float](repeating: 0, count: 25)
        for y in 0..<5 { values[y * 5 + 2] = 1 }
        let map = EdgeMap(width: 5, height: 5, values: values)
        XCTAssertEqual(map.strength(at: CGPoint(x: 0.5, y: 0.5)), 1, accuracy: 0.01)
        XCTAssertEqual(map.strength(at: CGPoint(x: 0, y: 0)), 0, accuracy: 0.01)
        XCTAssertEqual(map.strength(at: CGPoint(x: 1.2, y: 0.5)), 0, accuracy: 0.01)
        // 双线性：亮带与暗列之间应为中间值
        let mid = map.strength(at: CGPoint(x: 0.375, y: 0.5))
        XCTAssertTrue(mid > 0.2 && mid < 0.8, "亮带边缘应为中间值，实测 \(mid)")
    }

    func testSnapLineToEdges() {
        // 亮带竖在 x=0.5；一条竖线锚点在 x≈0.46 附近，应被吸到 0.5 上
        let w = 101, h = 101
        var values = [Float](repeating: 0, count: w * h)
        for y in 0..<h { values[y * w + 50] = 1 }
        let map = EdgeMap(width: w, height: h, values: values)
        let line = [CGPoint(x: 0.46, y: 0.3), CGPoint(x: 0.46, y: 0.5), CGPoint(x: 0.46, y: 0.7)]
        let r = snapLineToEdges(line, edge: map)
        for pt in r.line {
            XCTAssertEqual(pt.x, 0.5, accuracy: 0.01, "锚点应吸到亮带 x=0.5 上")
        }
        XCTAssertEqual(r.moved, 3)
        // 全黑图：无边缘，锚点不动
        let empty = EdgeMap(width: w, height: h, values: [Float](repeating: 0, count: w * h))
        let r2 = snapLineToEdges(line, edge: empty)
        XCTAssertEqual(r2.line, line)
        XCTAssertEqual(r2.moved, 0)
        // 弱边缘（0.1，低于阈值 0.30）：不动
        var weak = [Float](repeating: 0, count: w * h)
        for y in 0..<h { weak[y * w + 50] = 0.1 }
        let weakMap = EdgeMap(width: w, height: h, values: weak)
        let r3 = snapLineToEdges(line, edge: weakMap)
        XCTAssertEqual(r3.line, line)
        XCTAssertEqual(r3.moved, 0)
    }
}
