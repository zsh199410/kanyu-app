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
}
