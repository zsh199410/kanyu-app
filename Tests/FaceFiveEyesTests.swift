import XCTest
@testable import Kanyu

final class FaceFiveEyesTests: XCTestCase {
    private func points() -> [CGPoint] {
        var pts = [CGPoint](repeating: CGPoint(x: 0.5, y: 0.5), count: 478)
        pts[33] = CGPoint(x: 0.30, y: 0.40)
        pts[133] = CGPoint(x: 0.40, y: 0.40)
        pts[263] = CGPoint(x: 0.60, y: 0.40)
        pts[362] = CGPoint(x: 0.70, y: 0.40)
        pts[234] = CGPoint(x: 0.20, y: 0.45)
        pts[454] = CGPoint(x: 0.80, y: 0.45)
        return pts
    }

    func testFiveEyesRatios() {
        guard let r = fiveEyesRatios(points: points()) else {
            XCTFail("应能算出五眼比例")
            return
        }
        XCTAssertEqual(r.gapRatio, 3.0, accuracy: 0.01)
        XCTAssertEqual(r.faceRatio, 6.0, accuracy: 0.01)
    }

    func testFiveEyesNeedsEnoughPoints() {
        XCTAssertNil(fiveEyesRatios(points: [CGPoint](repeating: .zero, count: 100)))
        XCTAssertNil(fiveEyesRatios(points: [CGPoint](repeating: CGPoint(x: 0.5, y: 0.5), count: 478)))
    }
}

final class FaceHeadPoseTests: XCTestCase {
    // 旋转矩阵构造：R = Rz(roll)·Ry(yaw)·Rx(pitch)，与 headPoseAngles 同约定
    private func rotationRows(roll: Double, yaw: Double, pitch: Double) -> [[Double]] {
        let cr = cos(roll); let sr = sin(roll)
        let cy = cos(yaw); let sy = sin(yaw)
        let cp = cos(pitch); let sp = sin(pitch)
        return [
            [cr * cy, cr * sy * sp - sr * cp, cr * sy * cp + sr * sp],
            [sr * cy, sr * sy * sp + cr * cp, sr * sy * cp - cr * sp],
            [-sy, cy * sp, cy * cp],
        ]
    }

    func testHeadPoseAnglesIdentity() {
        guard let p = headPoseAngles(rotationRows: [[1, 0, 0], [0, 1, 0], [0, 0, 1]]) else {
            XCTFail("单位矩阵应能分解"); return
        }
        XCTAssertEqual(p.roll, 0, accuracy: 0.001)
        XCTAssertEqual(p.pitch, 0, accuracy: 0.001)
        XCTAssertEqual(p.yaw, 0, accuracy: 0.001)
    }

    func testHeadPoseAnglesPureRoll() {
        guard let p = headPoseAngles(rotationRows: rotationRows(roll: 0.2, yaw: 0, pitch: 0)) else {
            XCTFail("纯 roll 矩阵应能分解"); return
        }
        XCTAssertEqual(p.roll, 0.2, accuracy: 0.001)
        XCTAssertEqual(p.pitch, 0, accuracy: 0.001)
        XCTAssertEqual(p.yaw, 0, accuracy: 0.001)
    }

    func testHeadPoseAnglesCombinedRoundTrip() {
        guard let p = headPoseAngles(rotationRows: rotationRows(roll: 0.1, yaw: 0.3, pitch: -0.2)) else {
            XCTFail("组合矩阵应能分解"); return
        }
        XCTAssertEqual(p.roll, 0.1, accuracy: 0.001)
        XCTAssertEqual(p.yaw, 0.3, accuracy: 0.001)
        XCTAssertEqual(p.pitch, -0.2, accuracy: 0.001)
    }

    func testHeadPoseAnglesRejectsBadInput() {
        XCTAssertNil(headPoseAngles(rotationRows: [[0, 0, 0], [0, 0, 0], [0, 0, 0]]))
        XCTAssertNil(headPoseAngles(rotationRows: [[1, 0], [0, 1]]))
        XCTAssertNil(headPoseAngles(rotationRows: [[1, 0, 0], [0, 1, 0]]))
    }

    private func tiltedEyePoints() -> [CGPoint] {
        var pts = [CGPoint](repeating: CGPoint(x: 0.5, y: 0.5), count: 478)
        pts[33] = CGPoint(x: 0.30, y: 0.40)
        pts[263] = CGPoint(x: 0.60, y: 0.46)
        return pts
    }

    func testEyeLineRollSign() {
        // 眼线向右下方倾斜 θ ≈ 0.197 rad（顺时针），矩阵约定 roll 应为 -θ
        guard let roll = eyeLineRoll(points: tiltedEyePoints()) else {
            XCTFail("应能算出眼线 roll"); return
        }
        XCTAssertEqual(roll, -atan2(0.06, 0.30), accuracy: 0.001)
    }

    func testDerotateLevelsEyeLine() {
        let pts = tiltedEyePoints()
        guard let roll = eyeLineRoll(points: pts) else {
            XCTFail("应能算出眼线 roll"); return
        }
        let fixed = derotatePoints(pts, angle: roll, center: CGPoint(x: 0.45, y: 0.43))
        XCTAssertEqual(fixed[33].y, fixed[263].y, accuracy: 0.001)
    }

    // 正脸 Vision 四区（左下原点）：眉 0.40、鼻底 0.63、下颌 0.93（相对图高，左上原点分数）
    private func uprightRegions() -> VisionFaceRegions {
        VisionFaceRegions(
            leftEyebrow: [CGPoint(x: 0.25, y: 0.60), CGPoint(x: 0.375, y: 0.62), CGPoint(x: 0.50, y: 0.60)],
            rightEyebrow: [CGPoint(x: 0.55, y: 0.60), CGPoint(x: 0.675, y: 0.62), CGPoint(x: 0.80, y: 0.60)],
            nose: [CGPoint(x: 0.48, y: 0.37), CGPoint(x: 0.52, y: 0.37), CGPoint(x: 0.50, y: 0.42)],
            faceContour: [CGPoint(x: 0.25, y: 0.45), CGPoint(x: 0.50, y: 0.07), CGPoint(x: 0.80, y: 0.45),
                          CGPoint(x: 0.35, y: 0.20), CGPoint(x: 0.65, y: 0.20)])
    }

    // 把 Vision 四区整体倾斜 tilt（画面上顺时针，绕鼻区中心）
    private func tiltedRegions(_ regions: VisionFaceRegions, tilt: Double) -> VisionFaceRegions {
        func flip(_ pts: [CGPoint]) -> [CGPoint] { pts.map { CGPoint(x: $0.x, y: 1 - $0.y) } }
        func unflip(_ pts: [CGPoint]) -> [CGPoint] { pts.map { CGPoint(x: $0.x, y: 1 - $0.y) } }
        let noseImg = flip(regions.nose)
        let cx = noseImg.map { $0.x }.reduce(CGFloat(0), +) / CGFloat(noseImg.count)
        let cy = noseImg.map { $0.y }.reduce(CGFloat(0), +) / CGFloat(noseImg.count)
        let center = CGPoint(x: cx, y: cy)
        func tiltRegion(_ pts: [CGPoint]) -> [CGPoint] {
            unflip(derotatePoints(flip(pts), angle: tilt, center: center))
        }
        return VisionFaceRegions(
            leftEyebrow: tiltRegion(regions.leftEyebrow),
            rightEyebrow: tiltRegion(regions.rightEyebrow),
            nose: tiltRegion(regions.nose),
            faceContour: tiltRegion(regions.faceContour))
    }

    private func naiveMarks(regions: VisionFaceRegions) -> (brow: Double, nose: Double, chin: Double) {
        func lowestY(_ pts: [CGPoint]) -> CGFloat { pts.map { $0.y }.min() ?? 0 }
        let brow = 1 - Double((lowestY(regions.leftEyebrow) + lowestY(regions.rightEyebrow)) / 2)
        return (brow: brow, nose: 1 - Double(lowestY(regions.nose)), chin: 1 - Double(lowestY(regions.faceContour)))
    }

    func testPoseCorrectedFaceMarks() {
        let tilt = 0.2618  // 15°，头顶向画面右偏；矩阵 roll = -tilt
        let tilted = tiltedRegions(uprightRegions(), tilt: tilt)
        // 未校正的三线会被倾斜带偏（眉偏 0.046、下颌偏 0.011）：测试本身须对缺失校正敏感
        let naive = naiveMarks(regions: tilted)
        XCTAssertGreaterThan(abs(naive.brow - 0.40), 0.02)
        XCTAssertGreaterThan(abs(naive.chin - 0.93), 0.005)
        // 校正后应恢复正脸水平
        guard let fixed = poseCorrectedFaceMarks(regions: tilted, roll: -tilt) else {
            XCTFail("应能算出校正后三线"); return
        }
        XCTAssertEqual(fixed.brow, 0.40, accuracy: 0.002)
        XCTAssertEqual(fixed.nose, 0.63, accuracy: 0.002)
        XCTAssertEqual(fixed.chin, 0.93, accuracy: 0.002)
    }

    func testPoseCorrectedFaceMarksNeedsRegions() {
        let empty = VisionFaceRegions(leftEyebrow: [], rightEyebrow: [], nose: [], faceContour: [])
        XCTAssertNil(poseCorrectedFaceMarks(regions: empty, roll: 0.2))
    }

    func testFiveEyesDerotationPreservesRatios() {
        var pts = [CGPoint](repeating: CGPoint(x: 0.5, y: 0.5), count: 478)
        pts[33] = CGPoint(x: 0.30, y: 0.40)
        pts[133] = CGPoint(x: 0.40, y: 0.40)
        pts[263] = CGPoint(x: 0.60, y: 0.40)
        pts[362] = CGPoint(x: 0.70, y: 0.40)
        pts[234] = CGPoint(x: 0.20, y: 0.45)
        pts[454] = CGPoint(x: 0.80, y: 0.45)
        guard let upright = fiveEyesRatios(points: pts) else {
            XCTFail("正脸应能算出五眼"); return
        }
        let tilted = derotatePoints(pts, angle: 0.2, center: CGPoint(x: 0.5, y: 0.42))
        guard let tiltedRatios = fiveEyesRatios(points: tilted) else {
            XCTFail("倾斜后仍应能算出五眼"); return
        }
        XCTAssertEqual(tiltedRatios.gapRatio, upright.gapRatio, accuracy: 0.001)
        XCTAssertEqual(tiltedRatios.faceRatio, upright.faceRatio, accuracy: 0.001)
        guard let roll = eyeLineRoll(points: tilted) else {
            XCTFail("应能算出倾斜后的眼线 roll"); return
        }
        let fixed = derotatePoints(tilted, angle: roll, center: CGPoint(x: 0.5, y: 0.42))
        guard let fixedRatios = fiveEyesRatios(points: fixed) else {
            XCTFail("转正后仍应能算出五眼"); return
        }
        XCTAssertEqual(fixedRatios.gapRatio, upright.gapRatio, accuracy: 0.001)
        XCTAssertEqual(fixedRatios.faceRatio, upright.faceRatio, accuracy: 0.001)
    }

    func testPoseSummaryText() {
        let pose = HeadPose(roll: 0.21, pitch: 0.05, yaw: 0.30)
        let text = poseSummaryText(pose: pose, appliedRoll: 0.21, rollSource: "矩阵")
        XCTAssertTrue(text.contains("侧倾 12°"))
        XCTAssertTrue(text.contains("矩阵校正"))
        XCTAssertTrue(text.contains("侧转较大"))
        let calm = poseSummaryText(pose: HeadPose(roll: 0.05, pitch: 0.05, yaw: 0.05),
                                   appliedRoll: 0.05, rollSource: "眼线")
        XCTAssertFalse(calm.contains("侧转较大"))
        XCTAssertFalse(calm.contains("低头"))
    }
}
