// 奇门金标准测试（与 Python 参考实现同规则先验；CI 红了不出包）。
// 金标准 1：《遁甲演义》阳遁一局三时辰；金标准 3：阴遁九局甲子时全盘（手工推导，见注释）。
// 口径（2026-11-08 奇门大修）：值使移宫旬首起数＋数字宫序 1→9（含中五寄坤二）；
// 星／干／门／神一律沿方位环序 [1,8,3,4,9,2,7,6] 布（阴遁逆环），中宫不布星干，天禽随芮。
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

    // 金标准 2：自洽——每宫一地盘干；除中宫外每宫一天盘干一星一门一神；
    // 中宫无星无干无门无神（天禽与中宫原干随芮）；值符值使与旬首一致
    func testSelfConsistency() {
        let cases: [(Int, Bool, String, String)] = [
            (1, true, "甲", "子"), (9, false, "甲", "子"), (5, true, "丁", "卯"),
            (3, false, "庚", "午"), (7, true, "癸", "亥"), (2, false, "辛", "巳"),
        ]
        for (ju, yang, hs, hb) in cases {
            let ch = QimenEngine.chart(ju: ju, yang: yang, hourStem: hs, hourBranch: hb)!
            XCTAssertEqual(Set(ch.palaces.values.map { $0.diStem }).count, 9, "\(ju)\(hs)\(hb) 地盘干")
            XCTAssertEqual(ch.palaces.values.compactMap { $0.tianStem }.count, 8, "\(ju)\(hs)\(hb) 天盘干 8 个（中宫不布）")
            XCTAssertEqual(Set(ch.palaces.values.compactMap { $0.tianStem }).count, 8, "\(ju)\(hs)\(hb) 天盘干 8 个不重")
            XCTAssertNil(ch.palaces[5]?.tianStem, "\(ju)\(hs)\(hb) 中宫无天盘干")
            XCTAssertEqual(ch.palaces.values.compactMap { $0.star }.count, 8, "\(ju)\(hs)\(hb) 星 8 个（中宫不布）")
            XCTAssertEqual(Set(ch.palaces.values.compactMap { $0.star }).count, 8, "\(ju)\(hs)\(hb) 星 8 个不重")
            XCTAssertNil(ch.palaces[5]?.star, "\(ju)\(hs)\(hb) 中宫无星")
            XCTAssertEqual(ch.palaces[ch.tianRuiPalace]?.hostedStar, "禽", "\(ju)\(hs)\(hb) 天禽随芮")
            XCTAssertEqual(ch.palaces[ch.tianRuiPalace]?.hostedTianStem, ch.palaces[5]?.diStem, "\(ju)\(hs)\(hb) 中宫原干随芮")
            XCTAssertEqual(ch.qinPalace, ch.tianRuiPalace, "\(ju)\(hs)\(hb) 禽宫 = 芮宫")
            XCTAssertEqual(ch.palaces.values.compactMap { $0.door }.count, 8, "\(ju)\(hs)\(hb) 门")
            XCTAssertEqual(Set(ch.palaces.values.compactMap { $0.door }).count, 8, "\(ju)\(hs)\(hb) 门唯一")
            XCTAssertEqual(ch.palaces.values.compactMap { $0.god }.count, 8, "\(ju)\(hs)\(hb) 神")
            XCTAssertEqual(Set(ch.palaces.values.compactMap { $0.god }).count, 8, "\(ju)\(hs)\(hb) 神唯一")
            let effFu = ch.zhiFuStar == "禽" ? "芮" : ch.zhiFuStar
            XCTAssertEqual(ch.palaces[ch.zhiFuPalace]?.star, effFu, "\(ju)\(hs)\(hb) 值符星在值符宫")
            if ch.zhiFuStar == "禽" {
                XCTAssertEqual(ch.palaces[ch.zhiFuPalace]?.hostedStar, "禽", "\(ju)\(hs)\(hb) 禽值符随芮在值符宫")
            }
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
            XCTAssertEqual(Set(ch.palaces.values.compactMap { $0.star }).count, 8, ds)
        }
    }

    // 金标准 3：阴遁九局甲子时全盘（手工推导，2026-11-08 大修口径重算）：
    // 地盘戊起 9 宫阴逆：1乙2丙3丁4癸5壬6辛7庚8己9戊；旬首甲子遁戊在 9 宫→值符英、值使景；
    // 时干甲遁戊→时干宫 9；星沿逆环：英9辅4冲3任8蓬1心6柱7芮2（禽随芮在 2 宫，中宫无星）；
    // 天盘干沿逆环：戊9癸4丁3己8乙1辛6庚7丙2（中宫无干，中宫原干壬随芮在 2 宫）；
    // 值使景本宫 9，旬首起数 0 步→景 9；余门沿逆环：杜4伤3生8休1开6惊7死2；
    // 神沿顺时针环逆布：值符9九天2九地7玄武6白虎1六合8太阴3螣蛇4；空亡戌亥；马星寅；
    // 格局：伏吟八环宫（中宫无天盘干故无伏吟）、门迫无（门落本宫皆比和）；
    // 无三奇得使（天丙 2 宫地盘丙，非戊/庚）。
    // 依据：《遁甲演义》卷一「阴遁九局甲子在离天英为直符景门为直使」＋卷二地遁／人遁阴例逐宫对拍。
    func testYinJu9JiaZiFullChart() {
        let ch = QimenEngine.chart(ju: 9, yang: false, hourStem: "甲", hourBranch: "子")!
        XCTAssertEqual(ch.zhiFuStar, "英")
        XCTAssertEqual(ch.zhiShiDoor, "景")
        XCTAssertEqual(ch.zhiShiPalace, 9)
        XCTAssertEqual(ch.hourPalace, 9)
        XCTAssertEqual(ch.zhiFuPalace, 9)
        XCTAssertEqual(ch.kongWang, "戌亥")
        XCTAssertEqual(ch.maXing, "寅")
        let di: [Int: String] = [1: "乙", 2: "丙", 3: "丁", 4: "癸", 5: "壬", 6: "辛", 7: "庚", 8: "己", 9: "戊"]
        let stars: [Int: String] = [1: "蓬", 2: "芮", 3: "冲", 4: "辅", 6: "心", 7: "柱", 8: "任", 9: "英"]
        let tian: [Int: String] = [1: "乙", 2: "丙", 3: "丁", 4: "癸", 6: "辛", 7: "庚", 8: "己", 9: "戊"]
        let doors: [Int: String] = [1: "休", 2: "死", 3: "伤", 4: "杜", 6: "开", 7: "惊", 8: "生", 9: "景"]
        let gods: [Int: String] = [1: "白虎", 2: "九天", 3: "太阴", 4: "螣蛇", 6: "玄武", 7: "九地", 8: "六合", 9: "值符"]
        for p in 1...9 {
            XCTAssertEqual(ch.palaces[p]?.diStem, di[p], "地盘干 \(p) 宫")
            XCTAssertEqual(ch.palaces[p]?.tianStem, tian[p], "天盘干 \(p) 宫")
            XCTAssertEqual(ch.palaces[p]?.star, stars[p], "星 \(p) 宫")
            XCTAssertEqual(ch.palaces[p]?.door, doors[p], "门 \(p) 宫")
            XCTAssertEqual(ch.palaces[p]?.god, gods[p], "神 \(p) 宫")
            if p == 5 {
                XCTAssertFalse(ch.palaces[p]?.patterns.contains { $0.name == "伏吟" } ?? true, "中宫无天盘干，无伏吟")
            } else {
                XCTAssertTrue(ch.palaces[p]?.patterns.contains { $0.name == "伏吟" } ?? false, "伏吟 \(p) 宫")
            }
        }
        XCTAssertEqual(ch.palaces[2]?.hostedStar, "禽", "天禽随芮在 2 宫")
        XCTAssertEqual(ch.palaces[2]?.hostedTianStem, "壬", "中宫原干壬随芮在 2 宫")
        XCTAssertFalse(ch.palaces.values.contains { $0.patterns.contains { $0.name == "门迫" } }, "全盘无门迫（门落本宫皆比和）")
        XCTAssertFalse(ch.palaces.values.contains { $0.patterns.contains { $0.name == "三奇得使" } }, "阴九甲子时无三奇得使")
        XCTAssertFalse(ch.palaces[9]?.patterns.contains { $0.name == "玉女守门" } ?? true, "值使景宫地盘戊非丁，无玉女守门")
    }

    // 三奇得使严格版（2026-11-08 大修口径重算）：
    // 旧正例阳一局庚午时在新口径下已无三奇得使（1 宫天盘丁／地盘戊，丁需癸／壬），
    // 故改用《遁甲演义》卷二「三奇得使」三例原文逐宫核对：
    // ①阳九局庚午时，3 宫天乙／地辛（甲午之仪辛），乙奇得使；
    // ②阴三局壬辰时，9 宫天乙／地辛，乙奇得使（原文「在杜门下」一句与环序门盘
    //    对不上：环序杜门在 1 宫，存疑待查，此处不断言杜门宫，只断言乙奇得使本身）；
    // ③阳九局戊寅时，4 宫天丁／地壬（甲辰之仪壬），丁奇得使。
    func testSanQiDeShiStrict() {
        let a = QimenEngine.chart(ju: 9, yang: true, hourStem: "庚", hourBranch: "午")!
        XCTAssertEqual(a.hourPalace, 2, "阳九庚午时时干庚落地盘 2 宫")
        XCTAssertEqual(a.palaces[3]?.tianStem, "乙")
        XCTAssertEqual(a.palaces[3]?.diStem, "辛")
        XCTAssertTrue(a.palaces[3]?.patterns.contains { $0.name == "三奇得使" } ?? false, "乙奇得使震宫")
        let b = QimenEngine.chart(ju: 3, yang: false, hourStem: "壬", hourBranch: "辰")!
        XCTAssertEqual(b.hourPalace, 8, "阴三壬辰时时干壬落地盘 8 宫")
        XCTAssertEqual(b.palaces[9]?.tianStem, "乙")
        XCTAssertEqual(b.palaces[9]?.diStem, "辛")
        XCTAssertTrue(b.palaces[9]?.patterns.contains { $0.name == "三奇得使" } ?? false, "乙奇得使离宫")
        let c = QimenEngine.chart(ju: 9, yang: true, hourStem: "戊", hourBranch: "寅")!
        XCTAssertEqual(c.hourPalace, 9, "阳九戊寅时时干戊落地盘 9 宫")
        XCTAssertEqual(c.palaces[4]?.tianStem, "丁")
        XCTAssertEqual(c.palaces[4]?.diStem, "壬")
        XCTAssertTrue(c.palaces[4]?.patterns.contains { $0.name == "三奇得使" } ?? false, "丁奇得使巽宫")
    }

    // MARK: - G3 寄宫四档（与 Python test_qimen_jigong.py 同期望；2026-11-08 大修口径重算）
    func testG3Jigong() {
        // 阳 5 局甲子时（旬首与时干均在中宫）：kun2 值使死 2 宫，gen8 值使生 8 宫；
        // 星／天盘干／门全档相同，只有值使门本位与值符神起宫随档换位；中宫无星无干，禽随芮在 2 宫
        let k5 = QimenEngine.chart(ju: 5, yang: true, hourStem: "甲", hourBranch: "子", jigong: .kun2)!
        XCTAssertEqual(k5.zhiShiDoor, "死")
        XCTAssertEqual(k5.zhiShiPalace, 2)
        XCTAssertEqual(k5.zhiFuPalace, 2, "值符宫（禽在芮宫）")
        XCTAssertEqual(k5.tianRuiPalace, 2)
        XCTAssertEqual(k5.palaces[2]?.door, "死")
        XCTAssertEqual(k5.palaces[8]?.door, "生")
        XCTAssertEqual(k5.palaces[2]?.god, "值符")
        XCTAssertEqual(k5.palaces[1]?.god, "六合")
        XCTAssertEqual(k5.palaces[9]?.god, "九天")
        XCTAssertNil(k5.palaces[5]?.star, "中宫无星")
        XCTAssertNil(k5.palaces[5]?.tianStem, "中宫无天盘干")
        XCTAssertEqual(k5.palaces[2]?.hostedStar, "禽", "天禽随芮在 2 宫")
        XCTAssertEqual(k5.palaces[2]?.hostedTianStem, "戊", "中宫原干戊随芮在 2 宫")
        let g5 = QimenEngine.chart(ju: 5, yang: true, hourStem: "甲", hourBranch: "子", jigong: .gen8)!
        XCTAssertEqual(g5.zhiShiDoor, "生")
        XCTAssertEqual(g5.zhiShiPalace, 8)
        XCTAssertEqual(g5.zhiFuPalace, 2, "值符宫（禽恒随芮在 2 宫）")
        XCTAssertEqual(g5.palaces[8]?.door, "生")
        XCTAssertEqual(g5.palaces[2]?.door, "死")
        XCTAssertEqual(g5.palaces[8]?.god, "值符")
        XCTAssertEqual(g5.palaces[9]?.god, "六合")
        XCTAssertNil(g5.palaces[5]?.star)
        XCTAssertEqual(g5.palaces[2]?.hostedStar, "禽", "gen8 天禽仍随芮在 2 宫")
        // 星／天盘干在寄宫切换时不变
        for p in 1...9 {
            XCTAssertEqual(g5.palaces[p]?.star, k5.palaces[p]?.star, "星 \(p) 宫不变")
            XCTAssertEqual(g5.palaces[p]?.tianStem, k5.palaces[p]?.tianStem, "天盘干 \(p) 宫不变")
        }
        // 阴 5 局甲子时：kun2 值使死 2 宫，gen8 值使生 8 宫
        let ck = QimenEngine.chart(ju: 5, yang: false, hourStem: "甲", hourBranch: "子", jigong: .kun2)!
        XCTAssertEqual(ck.zhiShiDoor, "死")
        XCTAssertEqual(ck.zhiShiPalace, 2)
        XCTAssertEqual(ck.palaces[2]?.god, "值符")
        XCTAssertEqual(ck.palaces[7]?.god, "九天")
        let cg = QimenEngine.chart(ju: 5, yang: false, hourStem: "甲", hourBranch: "子", jigong: .gen8)!
        XCTAssertEqual(cg.zhiShiDoor, "生")
        XCTAssertEqual(cg.zhiShiPalace, 8)
        XCTAssertEqual(cg.palaces[8]?.god, "值符")
        XCTAssertEqual(cg.palaces[3]?.god, "九天")
        // 阳艮阴坤在阴遁时＝kun2，阳坤阴艮在阴遁时＝gen8
        let cyk = QimenEngine.chart(ju: 5, yang: false, hourStem: "甲", hourBranch: "子", jigong: .yanggenYinkun)!
        XCTAssertEqual(cyk.zhiShiPalace, ck.zhiShiPalace)
        XCTAssertEqual(cyk.palaces[2]?.god, "值符")
        let cyg = QimenEngine.chart(ju: 5, yang: false, hourStem: "甲", hourBranch: "子", jigong: .yangkunYingen)!
        XCTAssertEqual(cyg.zhiShiPalace, cg.zhiShiPalace)
        XCTAssertEqual(cyg.palaces[8]?.god, "值符")
        // 阳 1 局壬午时（时干宫为中宫）：值使移宫原宫 1 不在中宫，门两档同；
        // 值符星芮与值符干随寄宫换位，神盘寄宫不同
        let rk = QimenEngine.chart(ju: 1, yang: true, hourStem: "壬", hourBranch: "午", jigong: .kun2)!
        XCTAssertEqual(rk.zhiShiPalace, 1, "值使宫（数字序 2+8=1）")
        XCTAssertEqual(rk.palaces[1]?.door, "死")
        XCTAssertEqual(rk.zhiFuPalace, 2, "kun2 值符宫（芮寄坤 2）")
        XCTAssertEqual(rk.palaces[2]?.god, "值符")
        XCTAssertEqual(rk.palaces[1]?.god, "六合")
        XCTAssertEqual(rk.palaces[2]?.star, "芮", "kun2 芮在寄宫 2")
        XCTAssertEqual(rk.palaces[2]?.tianStem, "己", "kun2 值符干己在寄宫 2")
        let rg = QimenEngine.chart(ju: 1, yang: true, hourStem: "壬", hourBranch: "午", jigong: .gen8)!
        XCTAssertEqual(rg.zhiShiPalace, 1, "gen8 值使宫仍为 1")
        XCTAssertEqual(rg.palaces[1]?.door, "死")
        XCTAssertEqual(rg.zhiFuPalace, 8, "gen8 值符宫（芮寄艮 8）")
        XCTAssertEqual(rg.palaces[8]?.god, "值符")
        XCTAssertEqual(rg.palaces[9]?.god, "六合")
        XCTAssertEqual(rg.palaces[8]?.star, "芮", "gen8 芮随寄宫到 8")
        XCTAssertEqual(rg.palaces[8]?.tianStem, "己", "gen8 值符干己随寄宫到 8")
        // 旬首仪与时干宫均不在中宫时，四档盘面完全相同
        let a = QimenEngine.chart(ju: 1, yang: true, hourStem: "甲", hourBranch: "子", jigong: .kun2)!
        let b = QimenEngine.chart(ju: 1, yang: true, hourStem: "甲", hourBranch: "子", jigong: .gen8)!
        for p in 1...9 {
            XCTAssertEqual(b.palaces[p]?.door, a.palaces[p]?.door, "门 \(p) 宫同")
            XCTAssertEqual(b.palaces[p]?.god, a.palaces[p]?.god, "神 \(p) 宫同")
            XCTAssertEqual(b.palaces[p]?.star, a.palaces[p]?.star, "星 \(p) 宫同")
            XCTAssertEqual(b.palaces[p]?.tianStem, a.palaces[p]?.tianStem, "天盘干 \(p) 宫同")
        }
    }

    // MARK: - G3 四害／长生／克应／暗干（与 Python test_qimen_layers.py 同期望）
    func testG3Layers() {
        let ch = QimenEngine.chart(ju: 1, yang: true, hourStem: "庚", hourBranch: "午")!
        let p2 = ch.palaces[2]!
        let p3 = ch.palaces[3]!
        let p4 = ch.palaces[4]!
        let p5 = ch.palaces[5]!
        let p6 = ch.palaces[6]!
        // 四害（2026-11-08 环序重算）：击刑仅 3 宫（天盘戊落震三），
        // 入墓无（天盘乙在兑七、丙在巽四、丁在坎一，均非墓宫），
        // 旬空仅 6 宫（甲子旬空戌亥→乾六），门迫仅 8 宫（杜木落艮土）
        XCTAssertTrue(p3.siHaiJiXing, "天盘戊落震三为击刑")
        XCTAssertEqual((1...9).filter { ch.palaces[$0]?.siHaiJiXing ?? false }, [3], "全盘仅 3 宫击刑")
        XCTAssertFalse(p2.siHaiRuMu, "天盘辛落坤二非入墓")
        XCTAssertEqual((1...9).filter { ch.palaces[$0]?.siHaiRuMu ?? false }, [], "全盘无入墓")
        XCTAssertTrue(p6.siHaiKong, "甲子旬空戌亥→乾六宫空")
        XCTAssertEqual((1...9).filter { ch.palaces[$0]?.siHaiKong ?? false }, [6], "全盘仅 6 宫旬空")
        XCTAssertTrue(ch.palaces[8]!.siHaiMenPo, "杜门木落艮土宫为门迫")
        XCTAssertFalse(p2.siHaiMenPo, "开门金落坤土宫非门迫")
        XCTAssertFalse(p4.siHaiMenPo, "死门土落巽木宫非门迫")
        XCTAssertEqual((1...9).filter { ch.palaces[$0]?.siHaiMenPo ?? false }, [8], "全盘门迫仅 8 宫")
        // 时干入墓（盘级）
        XCTAssertTrue(QimenEngine.chart(ju: 1, yang: true, hourStem: "戊", hourBranch: "戌")!.shiGanRumu, "戊戌时干入墓")
        XCTAssertTrue(QimenEngine.chart(ju: 1, yang: true, hourStem: "壬", hourBranch: "辰")!.shiGanRumu, "壬辰时干入墓")
        XCTAssertFalse(QimenEngine.chart(ju: 1, yang: true, hourStem: "甲", hourBranch: "子")!.shiGanRumu, "甲子时干不入墓")
        // 十二长生：3 宫天戊临卯沐浴（四正单值），2 宫天辛临未衰申帝旺（四维双值），中宫 nil
        XCTAssertEqual(p3.changshengTian, ["卯": "沐浴"], "3 宫天戊临卯沐浴")
        XCTAssertEqual(p2.changshengTian, ["未": "衰", "申": "帝旺"], "2 宫天辛临未衰申帝旺")
        XCTAssertNil(p5.changshengTian, "中宫无本位地支")
        XCTAssertEqual(QimenEngine.changshengStage(stem: "乙", branch: "巳"), "沐浴", "乙巳沐浴（阴逆）")
        XCTAssertEqual(QimenEngine.changshengStage(stem: "乙", branch: "寅"), "帝旺", "乙寅帝旺（阴逆）")
        XCTAssertEqual(QimenEngine.changshengStage(stem: "辛", branch: "亥"), "沐浴", "辛亥沐浴（阴逆）")
        // 十干克应（环序重算）：3 宫戊加庚值符飞宫，2 宫辛加己入狱自刑，
        // 1 宫丁加戊青龙转光，9 宫庚加乙太白逢星
        XCTAssertEqual(p3.keYingName, "值符飞宫", "3 宫戊加庚值符飞宫")
        XCTAssertEqual(p2.keYingName, "入狱自刑", "2 宫辛加己入狱自刑")
        XCTAssertEqual(ch.palaces[1]!.keYingName, "青龙转光", "1 宫丁加戊青龙转光")
        XCTAssertEqual(ch.palaces[9]!.keYingName, "太白逢星", "9 宫庚加乙太白逢星")
        XCTAssertEqual(QimenEngine.keYing["乙辛"]?.name, "青龙逃走", "乙加辛青龙逃走")
        XCTAssertEqual(QimenEngine.keYing.count, 81, "十干克应全表 81 格")
        // 暗干：阳 1 庚午时值使休门落 7 宫，时干庚放 7 宫阳顺
        XCTAssertEqual(ch.palaces[7]!.angan, "庚", "暗干庚放值使宫")
        XCTAssertEqual(ch.palaces[1]!.angan, "癸", "暗干 1 宫癸")
        XCTAssertEqual(p5.angan, "戊", "暗干 5 宫戊")
        // 阴遁逆行：阴 5 局甲子时值使死门落 2 宫，暗干戊放 2 宫阴逆
        let cy = QimenEngine.chart(ju: 5, yang: false, hourStem: "甲", hourBranch: "子")!
        XCTAssertEqual(cy.palaces[2]!.angan, "戊", "阴遁暗干戊放值使宫")
        XCTAssertEqual(cy.palaces[1]!.angan, "乙", "阴遁暗干逆行 1 宫乙")
        XCTAssertEqual(cy.palaces[3]!.angan, "己", "阴遁暗干逆行 3 宫己")
        // 开关：不布暗干
        let off = QimenEngine.chart(ju: 1, yang: true, hourStem: "庚", hourBranch: "午", angan: false)!
        XCTAssertTrue((1...9).allSatisfy { off.palaces[$0]?.angan == nil }, "angan=false 全宫无暗干")
        XCTAssertTrue(off.receiptText().contains("暗干不布"), "收据写明暗干不布")
        // 收据行（默认口径）
        XCTAssertTrue(ch.receiptText().contains("定局：拆补法"), "收据定局拆补法")
        XCTAssertTrue(ch.receiptText().contains("寄宫恒寄坤二"), "收据寄宫恒寄坤二")
        XCTAssertTrue(ch.receiptText().contains("真太阳时未校正"), "收据真太阳时未校正")
    }

    // MARK: - G3 日家奇门（与 Python test_qimen_rijia_zhiyun.py 同期望）
    func testG3Rijia() {
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd HH:mm"
        fmt.timeZone = TimeZone(secondsFromGMT: 8 * 3600)
        // 2026-10-17 甲子日：阴遁二局，天蓬艮八宫，休门坎一宫
        let r1 = QimenEngine.rijiaChart(for: fmt.date(from: "2026-10-17 08:00")!)!
        XCTAssertEqual(r1.ju, 2)
        XCTAssertFalse(r1.yang)
        XCTAssertEqual(r1.palaces[8]?.star, "蓬", "甲子日天蓬起艮八宫")
        XCTAssertEqual(r1.palaces[1]?.door, "休", "甲子日休门起坎一宫")
        XCTAssertEqual(r1.palaces[9]?.star, "芮", "芮在离九")
        // 2026-11-07 乙酉日：阴遁八局，天蓬坤二宫，休门离九宫
        let r2 = QimenEngine.rijiaChart(for: fmt.date(from: "2026-11-07 08:00")!)!
        XCTAssertEqual(r2.ju, 8)
        XCTAssertFalse(r2.yang)
        XCTAssertEqual(r2.palaces[2]?.star, "蓬", "乙酉日天蓬坤二宫")
        XCTAssertEqual(r2.palaces[9]?.door, "休", "乙酉日休门离九宫")
        XCTAssertTrue(r2.receiptText().contains("日家奇门"), "日家收据行")
    }

    // MARK: - G3 置闰行走（纯日期算术，不依赖历法；与 Python 行走同期望）
    func testG3ZhiyunLookup() {
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = TimeZone(secondsFromGMT: 8 * 3600)
        func lookup(_ ds: String) -> (jieqi: String, yang: Bool, sanyuan: String, ju: Int, runqi: Bool)? {
            return QimenEngine.zhiyunLookup(date: fmt.date(from: ds)!)
        }
        // 1718-06-14 芒种闰奇上局阳 6（统宗康熙五十七年芒种置闰）
        let a = lookup("1718-06-14")!
        XCTAssertEqual(a.jieqi, "芒种")
        XCTAssertEqual(a.sanyuan, "上元")
        XCTAssertEqual(a.ju, 6)
        XCTAssertTrue(a.runqi)
        // 1718-06-22 分叉：置闰闰奇中局阳 3（拆补为夏至中元阴 3）
        let b = lookup("1718-06-22")!
        XCTAssertEqual(b.jieqi, "芒种")
        XCTAssertEqual(b.sanyuan, "中元")
        XCTAssertEqual(b.ju, 3)
        XCTAssertTrue(b.runqi)
        // 1718-06-29 夏至上局：两者一致阴 9
        let c = lookup("1718-06-29")!
        XCTAssertEqual(c.jieqi, "夏至")
        XCTAssertEqual(c.ju, 9)
        XCTAssertFalse(c.runqi)
        // 2024-12-11 大雪闰奇块始；2024-12-26 冬至上元（最近一次置闰）
        XCTAssertTrue(lookup("2024-12-11")!.runqi, "2024-12-11 大雪闰奇块始")
        let d = lookup("2024-12-26")!
        XCTAssertEqual(d.jieqi, "冬至")
        XCTAssertEqual(d.sanyuan, "上元")
        XCTAssertEqual(d.ju, 1)
        XCTAssertFalse(d.runqi)
        // 2026 年无闰：芒种上元 2026-06-04、夏至上元 2026-06-19
        XCTAssertFalse(lookup("2026-06-04")!.runqi, "2026 芒种无闰")
        XCTAssertEqual(lookup("2026-06-19")!.jieqi, "夏至", "2026 夏至上元")
        // 置闰 chart：2024-12-26 冬至上元阴 1 局
        let z = QimenEngine.zhiyunChart(for: fmt.date(from: "2024-12-26")!)!
        XCTAssertEqual(z.jieqi, "冬至")
        XCTAssertEqual(z.ju, 1)
        XCTAssertTrue(z.receiptText().contains("置闰法"), "置闰收据行")
    }

    // MARK: - G3 真太阳时（与 Python test_qimen_solar.py 同期望）
    func testG3Solar() {
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd HH:mm"
        fmt.timeZone = TimeZone(secondsFromGMT: 8 * 3600)
        let d = fmt.date(from: "2026-11-07 07:00")!
        // 未校正：07:00 辰时，时柱庚辰
        let plain = QimenEngine.chart(for: d)!
        XCTAssertEqual(plain.pillars[3], "庚辰", "未校正 07:00 辰时")
        XCTAssertNil(plain.solarMinutes)
        // 校正（经度 107.8 梁平）：约 -32.7 分，06:27 卯时，时柱己卯
        let corr = QimenEngine.chart(for: d, longitude: 107.8, jigong: .kun2, angan: true)!
        XCTAssertEqual(corr.pillars[3], "己卯", "校正后 06:27 卯时")
        XCTAssertNotNil(corr.solarMinutes)
        XCTAssertEqual(corr.solarMinutes ?? 0, -32.7, accuracy: 0.5, "校正分钟约 -32.7")
        XCTAssertEqual(corr.longitude, 107.8)
        XCTAssertTrue(corr.receiptText().contains("已校正"), "收据写明已校正")
        XCTAssertTrue(corr.receiptText().contains("107.8"), "收据写明经度")
    }

    // MARK: - G3 案例库
    func testG3Cases() {
        XCTAssertEqual(QimenCases.all.count, 8, "案例库 8 条")
        XCTAssertEqual(QimenCases.all[0].id, "qimen-case-01")
        XCTAssertEqual(QimenCases.all[7].id, "qimen-case-08")
        XCTAssertEqual(QimenCases.all[7].dingju, "置闰法")
        XCTAssertTrue(QimenCases.all.allSatisfy { !$0.verified.isEmpty }, "每条均有复核结论")
    }
}
