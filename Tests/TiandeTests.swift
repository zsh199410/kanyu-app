// 天德子／丑两值订正回归（2026-11-08，三项全做 track1）。
// 订正：《三命通会》卷三〈论天月德〉——子月（十一月）值巳、丑月（十二月）值庚。
// 巳为地支、庚为天干，故子入支表、丑入干表（旧表两值错放于对方的干／支表）。
// 柱列均为合成干支，与家人盘无关；shenSha 只读四柱与日主，其余字段填空串占位。
import XCTest
@testable import Kanyu

final class TiandeTests: XCTestCase {
    private func chart(pillars: [String], rizhu: String) -> BaziChart {
        BaziChart(yearPillar: pillars[0], monthPillar: pillars[1], dayPillar: pillars[2], timePillar: pillars[3],
                  rizhu: rizhu,
                  taiYuan: "", taiXi: "", mingGong: "", shenGong: "",
                  qiyunDirection: "", qiyunDate: "",
                  dayunGanZhi: [],
                  stemShiShen: ["", "", "", ""],
                  hideGan: [[], [], [], []],
                  hideShiShen: [[], [], [], []],
                  diShi: ["", "", "", ""],
                  naYin: ["", "", "", ""],
                  xunKong: "",
                  wuxingPercents: [0, 0, 0, 0, 0])
    }

    private func tiande(_ pillars: [String], rizhu: String) -> [Bool] {
        BaziTables.shenSha(chart(pillars: pillars, rizhu: rizhu)).map { $0.contains("天德贵人") }
    }

    // 子月值巳：支查——巳支所在柱带天德；有庚干无巳支时不再出天德（旧值已废）
    func testTiandeZiMonth() {
        XCTAssertEqual(tiande(["乙巳", "甲子", "戊辰", "壬戌"], rizhu: "戊"), [true, false, false, false])
        XCTAssertEqual(tiande(["甲辰", "丙子", "戊午", "乙巳"], rizhu: "戊"), [false, false, false, true])
        XCTAssertEqual(tiande(["庚午", "丙子", "戊辰", "壬戌"], rizhu: "戊"), [false, false, false, false])
    }

    // 丑月值庚：干查——庚干所在柱带天德；有巳支无庚干时不再出天德（旧值已废）
    func testTiandeChouMonth() {
        XCTAssertEqual(tiande(["庚午", "乙丑", "甲子", "丙寅"], rizhu: "甲"), [true, false, false, false])
        XCTAssertEqual(tiande(["甲辰", "乙丑", "丙午", "庚辰"], rizhu: "丙"), [false, false, false, true])
        XCTAssertEqual(tiande(["乙巳", "丁丑", "戊辰", "壬戌"], rizhu: "戊"), [false, false, false, false])
    }

    // 其余月份抽查：值未动（寅月丁干查、卯月申支查、午月亥支查）
    func testTiandeOtherMonthsUnchanged() {
        XCTAssertEqual(tiande(["丁卯", "丙寅", "戊辰", "壬戌"], rizhu: "戊"), [true, false, false, false])
        XCTAssertEqual(tiande(["甲申", "丁卯", "戊辰", "壬戌"], rizhu: "戊"), [true, false, false, false])
        XCTAssertEqual(tiande(["乙亥", "丙午", "戊辰", "壬戌"], rizhu: "戊"), [true, false, false, false])
    }
}
