// G14 多流派对照 · App 侧测试（预注册协议 v1.1）。
// 只断言结构与功链判定（主功链种、3 条判断、item 07 分流），不含答案键；
// 答案键只存 Web 测试数据（tools/tests/g14_preregistered.json），不进 App 包。
// 12 例四柱＋大运与 Web 测试数据逐字一致（paipan 复核）；出生月日时一律不进测试。
import XCTest
@testable import Kanyu

final class ZuogongTests: XCTestCase {
    // 预注册 12 例（id、四柱、日主、起运年、大运、目标年）
    private static let cases: [(id: String, pillars: [String], dayMaster: String,
                                qiyunYear: Int, dayun: [String], year: Int)] = [
        ("G14-01", ["己卯", "丙子", "庚寅", "辛巳"], "庚", 1888,
         ["乙亥", "甲戌", "癸酉", "壬申", "辛未", "庚午", "己巳", "戊辰", "丁卯"], 1934),
        ("G14-02", ["己卯", "丁丑", "癸丑", "乙卯"], "癸", 1886,
         ["丙子", "乙亥", "甲戌", "癸酉", "壬申", "辛未", "庚午", "己巳", "戊辰"], 1930),
        ("G14-03", ["癸巳", "丙辰", "壬申", "癸卯"], "壬", 1893,
         ["乙卯", "甲寅", "癸丑", "壬子", "辛亥", "庚戌", "己酉", "戊申", "丁未"], 1933),
        ("G14-04", ["己卯", "丁卯", "丙申", "甲午"], "丙", 1881,
         ["丙寅", "乙丑", "甲子", "癸亥", "壬戌", "辛酉", "庚申", "己未", "戊午"], 1903),
        ("G14-05", ["癸巳", "甲子", "丁酉", "甲辰"], "丁", 1900,
         ["癸亥", "壬戌", "辛酉", "庚申", "己未", "戊午", "丁巳", "丙辰", "乙卯"], 1920),
        ("G14-06", ["癸巳", "甲子", "丁酉", "甲辰"], "丁", 1900,
         ["癸亥", "壬戌", "辛酉", "庚申", "己未", "戊午", "丁巳", "丙辰", "乙卯"], 1922),
        ("G14-07", ["己卯", "丁卯", "丙申", "甲午"], "丙", 1881,
         ["丙寅", "乙丑", "甲子", "癸亥", "壬戌", "辛酉", "庚申", "己未", "戊午"], 1905),
        ("G14-08", ["己卯", "丁卯", "丙申", "甲午"], "丙", 1881,
         ["丙寅", "乙丑", "甲子", "癸亥", "壬戌", "辛酉", "庚申", "己未", "戊午"], 1921),
        ("G14-09", ["癸巳", "甲子", "丁酉", "甲辰"], "丁", 1900,
         ["癸亥", "壬戌", "辛酉", "庚申", "己未", "戊午", "丁巳", "丙辰", "乙卯"], 1909),
        ("G14-10", ["己卯", "丁卯", "丙申", "甲午"], "丙", 1881,
         ["丙寅", "乙丑", "甲子", "癸亥", "壬戌", "辛酉", "庚申", "己未", "戊午"], 1897),
        ("G14-11", ["丁亥", "庚戌", "己巳", "庚午"], "己", 1895,
         ["己酉", "戊申", "丁未", "丙午", "乙巳", "甲辰", "癸卯", "壬寅", "辛丑"], 1961),
        ("G14-12", ["甲辰", "丙子", "己未", "辛未"], "己", 2029,
         ["丁丑", "戊寅", "己卯", "庚辰", "辛巳", "壬午", "癸未", "甲申", "乙酉"], 2026),
    ]

    private func chart(pillars: [String], dayMaster: String, qiyunYear: Int, dayun: [String]) -> BaziChart {
        let dayStem = dayMaster.first!
        let stemSS = pillars.enumerated().map { i, p in
            i == 2 ? "日主" : BaziTables.shiShen(day: dayStem, stem: p.first!)
        }
        let hideSS = pillars.map { p in
            BaziTables.cangGan[p.last!]!.map { BaziTables.shiShen(day: dayStem, stem: $0) }
        }
        let hideGan = pillars.map { p in BaziTables.cangGan[p.last!]!.map { String($0) } }
        return BaziChart(yearPillar: pillars[0], monthPillar: pillars[1], dayPillar: pillars[2], timePillar: pillars[3],
                         rizhu: dayMaster,
                         taiYuan: "", taiXi: "", mingGong: "", shenGong: "",
                         qiyunDirection: "", qiyunDate: "\(qiyunYear)-01-01",
                         dayunGanZhi: dayun,
                         stemShiShen: stemSS,
                         hideGan: hideGan,
                         hideShiShen: hideSS,
                         diShi: ["", "", "", ""],
                         naYin: ["", "", "", ""],
                         xunKong: "",
                         wuxingPercents: [20, 20, 20, 20, 20])
    }

    private func chartFor(_ id: String) -> BaziChart {
        let c = Self.cases.first { $0.id == id }!
        return chart(pillars: c.pillars, dayMaster: c.dayMaster, qiyunYear: c.qiyunYear, dayun: c.dayun)
    }

    // 主功链：7 张盘（手算＋spike 交叉核对，与 Web 端一致）
    func testMainChains() {
        let expected: [(String, String)] = [
            ("G14-01", "食伤制杀"), ("G14-02", "食伤制杀"), ("G14-03", "食伤生财"),
            ("G14-05", "化用"), ("G14-11", "印制食伤"), ("G14-04", "印制食伤"),
            ("G14-12", "食伤制杀"),
        ]
        for (id, kind) in expected {
            let (main, _, _) = Zuogong.mainChain(chartFor(id))
            XCTAssertEqual(main?.kind, kind, "\(id) 主功链应为 \(kind)")
        }
    }

    // 冲突核对（协议 §五）：史量才/谭延闿的 item 07 分流与做功层不一致
    func testItem07Conflicts() {
        XCTAssertEqual(Zuogong.item07Branch(chartFor("G14-01")), "官印相生", "史量才 item 07 应为官印相生")
        XCTAssertEqual(Zuogong.item07Branch(chartFor("G14-02")), "食伤生财", "谭延闿 item 07 应为食伤生财")
    }

    // 每例做功组与对照组各出 3 条判断，字段齐全，年份＝目标年
    func testJudgmentsShape() {
        for c in Self.cases {
            let ch = chart(pillars: c.pillars, dayMaster: c.dayMaster, qiyunYear: c.qiyunYear, dayun: c.dayun)
            for (group, js) in [("zuogong", Zuogong.judgments(ch, year: c.year)),
                                 ("control", Zuogong.controlJudgments(ch, year: c.year))] {
                XCTAssertEqual(js.count, 3, "\(c.id) \(group) 应出 3 条判断")
                for j in js {
                    XCTAssertEqual(j.year, c.year, "\(c.id) \(group) 判断年份应为目标年")
                    XCTAssertTrue(["落实", "半落实", "不落实"].contains(j.luoshi), "\(c.id) \(group) 落实度取值")
                    XCTAssertEqual(j.source, group, "\(c.id) \(group) 来源标记")
                    XCTAssertFalse(j.eventClass.isEmpty, "\(c.id) \(group) 事件类非空")
                    XCTAssertFalse(j.basis.isEmpty, "\(c.id) \(group) 依据非空")
                }
            }
        }
    }

    // 规则版本 v1.1（与 app/zuogong.py RULES_VERSION 同步）
    func testRulesVersion() {
        XCTAssertEqual(Zuogong.rulesVersion, "1.1")
    }

    // v1.1 修正①：12 例逐年扫描的穿破信号无重复（关系，来源，目标）键
    func testPoDedup() {
        for c in Self.cases {
            let ch = chart(pillars: c.pillars, dayMaster: c.dayMaster, qiyunYear: c.qiyunYear, dayun: c.dayun)
            let (main, _, _) = Zuogong.mainChain(ch)
            guard let main else { continue }
            let scan = Zuogong.yearScan(ch, year: c.year, chain: main)
            let keys = scan.po.map { "\($0.kind)|\($0.src)|\($0.tgt)" }
            XCTAssertEqual(keys.count, Set(keys).count, "\(c.id) 穿破信号应去重")
        }
    }

    // v1.1 修正②：J3 按穿破强度分级（合成信号）
    func testJ3Classify() {
        func po(_ kind: String, _ target: String) -> ZuogongPoSignal {
            ZuogongPoSignal(kind: kind, target: target, description: "合成", src: "午", tgt: "子")
        }
        XCTAssertEqual(Zuogong.j3Classify([]), "守年/平年")
        XCTAssertEqual(Zuogong.j3Classify([po("冲", "用神")]), "破耗")
        XCTAssertEqual(Zuogong.j3Classify([po("冲", "日支")]), "破耗")
        XCTAssertEqual(Zuogong.j3Classify([po("冲", "日支"), po("刑", "用神")]), "人身")
        XCTAssertEqual(Zuogong.j3Classify([po("穿", "功神"), po("财党杀", "用神")]), "人身")
        XCTAssertEqual(Zuogong.j3Classify([po("财党杀", "用神"), po("劫争财", "用神")]), "破耗")
    }

    // v1.2 修正⑤⑥⑦：J2 门槛 helper（合成主功链；修正③作废）
    func testGateHelpers() {
        let chain = ZuogongChain(kind: "化用", gongShen: "正官", yongShen: "七杀",
                                 gongStem: "甲", yongStem: "癸", gongPos: 1, yongPos: 0, weak: false)
        XCTAssertTrue(Zuogong.j2GateA("庚", starSS: "正官", chain: chain))  // 流年干十神==功神十神
        XCTAssertTrue(Zuogong.j2GateA("壬", starSS: "正财", chain: chain))  // 壬水生甲木功神干
        XCTAssertTrue(Zuogong.j2GateA("戊", starSS: "正财", chain: chain))  // 戊土克癸水用神干
        XCTAssertFalse(Zuogong.j2GateA("乙", starSS: "比肩", chain: chain))  // 无匹配
        let pillars = ["甲子", "乙子", "丙子", "丁子"]  // 日支/时支全为子（合成）
        XCTAssertEqual(Zuogong.j2GateB("午", pillars: pillars).map { "\($0.role)\($0.rel)" },
                       ["日支冲", "时支冲"])  // 午冲子
        XCTAssertTrue(Zuogong.j2GateB("辰", pillars: pillars).isEmpty)  // 辰与子无合/冲/刑/穿
        XCTAssertEqual(Zuogong.palaceEvent("食神", fromLiunianStem: true, gateBHits: [("时支", "冲")]),
                       ("子女", "子女"))
        XCTAssertEqual(Zuogong.palaceEvent("正官", fromLiunianStem: true, gateBHits: [("日支", "冲")]),
                       ("婚", "配偶"))
        XCTAssertEqual(Zuogong.palaceEvent("正财", fromLiunianStem: true, gateBHits: [("日支", "穿")]),
                       ("婚", "配偶"))
        XCTAssertNil(Zuogong.palaceEvent("食神", fromLiunianStem: false, gateBHits: [("时支", "冲")]))
        XCTAssertNil(Zuogong.palaceEvent("正印", fromLiunianStem: true, gateBHits: [("时支", "穿")]))
    }

    // 童限（未起运）不崩：G14-12 目标年 2026 在起运 2029 之前，大运为空
    func testChildLimitNoCrash() {
        let ch = chartFor("G14-12")
        XCTAssertNil(Zuogong.dayunOfYear(ch, year: 2026))
        let js = Zuogong.judgments(ch, year: 2026)
        XCTAssertEqual(js.count, 3)
    }
}
