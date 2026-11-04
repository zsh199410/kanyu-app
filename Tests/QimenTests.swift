// 奇门金标准测试（与 Python 参考实现同规则先验；CI 红了不出包）。
// 金标准 1：《遁甲演义》阳遁一局三时辰；金标准 3：阴遁九局甲子时全盘（手工推导，见注释）。
import XCTest
@testable import Kanyu

final class QimenTests: XCTestCase {
    // 金标准 1：阳遁一局——甲子时天蓬 1 宫休门 1 宫；乙丑时天蓬 9 宫休门 2 宫；丙寅时天蓬 8 宫休门 3 宫
    func testYangJu1Golden() {
        let a = QimenEngine.chart(ju: 1, yang: true, hourStem: "甲", hourBranch: "子")!
        XCTAssertEqual(a.palaces[1]?.star, "蓬")
        XCTAssertEqual(a.palaces[1]?.door, "休")
        let b = QimenEngine.chart(ju: 1, yang: true, hourStem: "乙", hourBranch: "丑")!
        XCTAssertEqual(b.palaces[9]?.star, "蓬")
        XCTAssertEqual(b.palaces[2]?.door, "休")
        let c = QimenEngine.chart(ju: 1, yang: true, hourStem: "丙", hourBranch: "寅")!
        XCTAssertEqual(c.palaces[8]?.star, "蓬")
        XCTAssertEqual(c.palaces[3]?.door, "休")
    }

    // 金标准 2：自洽——每宫一地盘干一天盘干一星；除中宫外每宫一门一神；值符值使与旬首一致
    func testSelfConsistency() {
        let cases: [(Int, Bool, String, String)] = [
            (1, true, "甲", "子"), (9, false, "甲", "子"), (5, true, "丁", "卯"),
            (3, false, "庚", "午"), (7, true, "癸", "亥"), (2, false, "辛", "巳"),
        ]
        for (ju, yang, hs, hb) in cases {
            let ch = QimenEngine.chart(ju: ju, yang: yang, hourStem: hs, hourBranch: hb)!
            XCTAssertEqual(Set(ch.palaces.values.map { $0.diStem }).count, 9, "\(ju)\(hs)\(hb) 地盘干")
            XCTAssertEqual(Set(ch.palaces.values.map { $0.tianStem }).count, 9, "\(ju)\(hs)\(hb) 天盘干")
            XCTAssertEqual(Set(ch.palaces.values.map { $0.star }).count, 9, "\(ju)\(hs)\(hb) 星")
            XCTAssertEqual(ch.palaces.values.compactMap { $0.door }.count, 8, "\(ju)\(hs)\(hb) 门")
            XCTAssertEqual(Set(ch.palaces.values.compactMap { $0.door }).count, 8, "\(ju)\(hs)\(hb) 门唯一")
            XCTAssertEqual(ch.palaces.values.compactMap { $0.god }.count, 8, "\(ju)\(hs)\(hb) 神")
            XCTAssertEqual(ch.palaces[ch.hourPalace]?.star, ch.zhiFuStar, "\(ju)\(hs)\(hb) 值符星")
            XCTAssertEqual(ch.palaces[ch.zhiShiPalace]?.door, ch.zhiShiDoor, "\(ju)\(hs)\(hb) 值使门")
            XCTAssertNil(ch.palaces[5]?.door)
            XCTAssertNil(ch.palaces[5]?.god)
        }
        // 日期版自洽（四柱/节气/局数走真实历法路径，只验结构）
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd HH:mm"
        fmt.timeZone = TimeZone(secondsFromGMT: 8 * 3600)
        for ds in ["2026-11-04 12:00", "2025-03-21 08:30", "2024-08-15 23:15", "2023-01-06 06:00"] {
            let ch = QimenEngine.chart(for: fmt.date(from: ds)!)!
            XCTAssertEqual(ch.pillars.count, 4, ds)
            XCTAssertFalse(ch.jieqi.isEmpty, ds)
            XCTAssertTrue((1...9).contains(ch.ju), ds)
            XCTAssertEqual(Set(ch.palaces.values.map { $0.star }).count, 9, ds)
        }
    }

    // 金标准 3：阴遁九局甲子时全盘（手工推导）：
    // 地盘戊起 9 宫阴逆：1乙2丙3丁4癸5壬6辛7庚8己9戊；旬首甲子遁戊在 9 宫→值符英、值使景；
    // 时干甲遁戊→时干宫 9；天盘星阴逆：英9蓬8芮7冲6辅5禽4心3柱2任1；
    // 天盘干阴逆：戊9己8庚7辛6壬5癸4丁3丙2乙1（与地盘全同＝全局伏吟）；
    // 值使景本宫 9，时支子→景 9；余门阴逆：死4惊3开2休1生6伤7杜8；
    // 神阴逆：值符9螣蛇4太阴3六合2白虎1玄武6九地7九天8；空亡戌亥；马星寅；
    // 格局：伏吟九宫、门迫震 3（惊金克木）与艮 8（杜木克土）；无三奇得使（严格版：天丙 2 宫地盘丙，非戊/庚）。
    func testYinJu9JiaZiFullChart() {
        let ch = QimenEngine.chart(ju: 9, yang: false, hourStem: "甲", hourBranch: "子")!
        XCTAssertEqual(ch.zhiFuStar, "英")
        XCTAssertEqual(ch.zhiShiDoor, "景")
        XCTAssertEqual(ch.zhiShiPalace, 9)
        XCTAssertEqual(ch.hourPalace, 9)
        XCTAssertEqual(ch.kongWang, "戌亥")
        XCTAssertEqual(ch.maXing, "寅")
        let di: [Int: String] = [1: "乙", 2: "丙", 3: "丁", 4: "癸", 5: "壬", 6: "辛", 7: "庚", 8: "己", 9: "戊"]
        let stars: [Int: String] = [1: "任", 2: "柱", 3: "心", 4: "禽", 5: "辅", 6: "冲", 7: "芮", 8: "蓬", 9: "英"]
        let doors: [Int: String] = [1: "休", 2: "开", 3: "惊", 4: "死", 6: "生", 7: "伤", 8: "杜", 9: "景"]
        let gods: [Int: String] = [1: "白虎", 2: "六合", 3: "太阴", 4: "螣蛇", 6: "玄武", 7: "九地", 8: "九天", 9: "值符"]
        for p in 1...9 {
            XCTAssertEqual(ch.palaces[p]?.diStem, di[p], "地盘干 \(p) 宫")
            XCTAssertEqual(ch.palaces[p]?.tianStem, di[p], "天盘干 \(p) 宫（伏吟）")
            XCTAssertEqual(ch.palaces[p]?.star, stars[p], "星 \(p) 宫")
            XCTAssertEqual(ch.palaces[p]?.door, doors[p], "门 \(p) 宫")
            XCTAssertEqual(ch.palaces[p]?.god, gods[p], "神 \(p) 宫")
            XCTAssertTrue(ch.palaces[p]?.patterns.contains { $0.name == "伏吟" } ?? false, "伏吟 \(p) 宫")
        }
        XCTAssertTrue(ch.palaces[3]?.patterns.contains { $0.name == "门迫" } ?? false, "门迫震宫")
        XCTAssertTrue(ch.palaces[8]?.patterns.contains { $0.name == "门迫" } ?? false, "门迫艮宫")
        XCTAssertFalse(ch.palaces.values.contains { $0.patterns.contains { $0.name == "三奇得使" } }, "阴九甲子时无三奇得使")
        XCTAssertFalse(ch.palaces[9]?.patterns.contains { $0.name == "玉女守门" } ?? true, "值使景宫地盘戊非丁，无玉女守门")
    }

    // 三奇得使严格版正例：阳遁一局庚午时（甲子旬），天盘丙落 1 宫、地盘 1 宫为戊（甲子之仪），丙奇得使；
    // 同盘 2 宫天盘乙、地盘己（甲戌之仪），乙奇得使亦成立。
    func testSanQiDeShiStrict() {
        let ch = QimenEngine.chart(ju: 1, yang: true, hourStem: "庚", hourBranch: "午")!
        XCTAssertEqual(ch.hourPalace, 3, "时干庚落地盘 3 宫")
        XCTAssertEqual(ch.palaces[1]?.tianStem, "丙")
        XCTAssertEqual(ch.palaces[1]?.diStem, "戊")
        XCTAssertTrue(ch.palaces[1]?.patterns.contains { $0.name == "三奇得使" } ?? false, "丙奇得使坎宫")
        XCTAssertEqual(ch.palaces[2]?.tianStem, "乙")
        XCTAssertEqual(ch.palaces[2]?.diStem, "己")
        XCTAssertTrue(ch.palaces[2]?.patterns.contains { $0.name == "三奇得使" } ?? false, "乙奇得使坤宫")
    }
}
