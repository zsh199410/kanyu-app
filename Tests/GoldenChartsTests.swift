// 金标准盘对拍（12 例，服务端已验证引擎 paipan.py 生成）：
// 立春/惊蛰交节边界、晚子时 sect=2、真太阳时跨时辰、大经度差、闰月期、胎元命宫。
// CI 红了不出包——口径守门，与八字线「只信互校」铁规矩一致。
import XCTest
@testable import Kanyu

final class GoldenChartsTests: XCTestCase {
    struct Golden: Decodable {
        let name: String; let datetime: String; let gender: String; let lon: Double?
        let pillars: [String: String]; let rizhu: String; let taiyuan_minggong: [String: String]
        let qiyun_dir: String; let qiyun_date: String; let dayun_first4: [String]
    }
    func testGoldenCharts() throws {
        let url = Bundle(for: Self.self).url(forResource: "golden_charts", withExtension: "json")!
        let list = try JSONDecoder().decode([Golden].self, from: Data(contentsOf: url))
        XCTAssertEqual(list.count, 12)
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd HH:mm"
        fmt.timeZone = TimeZone(secondsFromGMT: 8 * 3600)
        for g in list {
            let ch = BaziEngine.paipan(clock: fmt.date(from: g.datetime)!, gender: g.gender, longitude: g.lon)
            XCTAssertEqual(ch.yearPillar, g.pillars["年柱"], g.name)
            XCTAssertEqual(ch.monthPillar, g.pillars["月柱"], g.name)
            XCTAssertEqual(ch.dayPillar, g.pillars["日柱"], g.name)
            XCTAssertEqual(ch.timePillar, g.pillars["时柱"], g.name)
            XCTAssertEqual(ch.taiYuan, g.taiyuan_minggong["胎元"], g.name)
            XCTAssertEqual(ch.mingGong, g.taiyuan_minggong["命宫"], g.name)
            XCTAssertEqual(ch.shenGong, g.taiyuan_minggong["身宫"], g.name)
            XCTAssertEqual(ch.qiyunDirection, g.qiyun_dir, g.name)
            XCTAssertEqual(ch.qiyunDate, g.qiyun_date, g.name)
            XCTAssertEqual(Array(ch.dayunGanZhi.prefix(4)), g.dayun_first4, g.name)
        }
    }
}
