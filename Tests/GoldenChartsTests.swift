// 金标准盘对拍（12 例，服务端已验证引擎 paipan.py 生成）：
// 立春/惊蛰交节边界、晚子时 sect=2、真太阳时跨时辰、大经度差、闰月期、胎元命宫。
// 细盘层（藏干/十神/长生/纳音/旬空）为查表自算移植，2026-10-30 原型已与库输出对拍 12/12，
// 此处以金标准盘 detail 字段锁死，防移植漂移。CI 红了不出包——口径守门。
import XCTest
@testable import Kanyu

final class GoldenChartsTests: XCTestCase {
    struct Detail: Decodable {
        let stem_shishen: [String]; let hide_gan: [[String]]
        let dishi: [String]; let nayin: [String]; let xunkong: String
    }
    struct Golden: Decodable {
        let name: String; let datetime: String; let gender: String; let lon: Double?
        let pillars: [String: String]; let rizhu: String; let taiyuan_minggong: [String: String]
        let qiyun_dir: String; let qiyun_date: String; let dayun_first4: [String]
        let detail: Detail
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
            // 细盘层对拍
            XCTAssertEqual(ch.stemShiShen, g.detail.stem_shishen, g.name)
            XCTAssertEqual(ch.hideGan, g.detail.hide_gan, g.name)
            XCTAssertEqual(ch.diShi, g.detail.dishi, g.name)
            XCTAssertEqual(ch.naYin, g.detail.nayin, g.name)
            XCTAssertEqual(ch.xunKong, g.detail.xunkong, g.name)
            XCTAssertEqual(ch.wuxingPercents.reduce(0, +), 100, accuracy: 0.5, g.name)
        }
    }
}
