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
