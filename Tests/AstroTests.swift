// 星命金标准测试：与 Web astro.py 真太阳时校正后输出对拍（容差 ±0.5°；CI 红了不出包）。
// 期望值取自 Web /api/astro 实测（经度 107.8、纬度 30.5、真太阳时校正开启）；用合成日期，不含家人出生数据。
import XCTest
@testable import Kanyu

final class AstroTests: XCTestCase {
    private func date(_ s: String) -> Date {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm"
        fmt.timeZone = TimeZone(identifier: "Asia/Shanghai")
        return fmt.date(from: s)!
    }

    func testTrueSolarTimeGolden() {
        // (钟表时间, 太阳星座, 太阳度数, 月亮星座, 月亮度数, 上升星座, 上升度数)
        let cases: [(String, ZodiacSign, Double, ZodiacSign, Double, ZodiacSign, Double)] = [
            ("2000-06-15 10:30", .gemini, 24.28, .sagittarius, 3.82, .leo, 14.10),
            ("1990-03-08 18:45", .pisces, 17.57, .leo, 11.86, .virgo, 3.77),
            ("2015-11-25 06:15", .sagittarius, 2.29, .taurus, 17.71, .scorpio, 9.38),
        ]
        for (ds, sunSign, sunDeg, moonSign, moonDeg, ascSign, ascDeg) in cases {
            let ch = AstroEngine.calculate(birthDate: date(ds), longitude: 107.8, latitude: 30.5)
            XCTAssertEqual(ch.sunSign, sunSign, ds)
            XCTAssertEqual(ch.sunDegree, sunDeg, accuracy: 0.5, ds)
            XCTAssertEqual(ch.moonSign, moonSign, ds)
            XCTAssertEqual(ch.moonDegree, moonDeg, accuracy: 0.5, ds)
            XCTAssertEqual(ch.ascSign, ascSign, ds)
            XCTAssertEqual(ch.ascDegree, ascDeg, accuracy: 0.5, ds)
        }
    }
}
