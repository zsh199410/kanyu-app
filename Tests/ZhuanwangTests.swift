// C10 专旺格定量判定 · App 侧测试（口径 v1.0，2026-11-09）。
// 与 tools/tests/test_c10_zhuanwang.py 同集：6 则公开命例（千里命稿 4 则＋朱祖夏 2 则）
// ＋边界合成例（已标注合成）。只用四柱干支串，不含任何真实人物出生信息。
import XCTest
@testable import Kanyu

final class ZhuanwangTests: XCTestCase {
    func pillars(_ s: String) -> [String] {
        stride(from: 0, to: 8, by: 2).map { i in
            String([s[s.index(s.startIndex, offsetBy: i)], s[s.index(s.startIndex, offsetBy: i + 1)]])
        }
    }

    // 公开例 1：曲直格真成（千里命稿）— 木 46.9% 未达 55%，条件 1 用 (a)
    func testQuzhiTrue() {
        let r = Zhuanwang.check(pillars: pillars("壬寅癸卯甲辰甲子"), dayStem: "甲")
        XCTAssertEqual(r.verdict, "真成")
        XCTAssertEqual(r.wangPct, 46.9, accuracy: 0.15)
        XCTAssertEqual(r.cond1Via, "三会/三合")
        XCTAssertEqual(r.cond3, "无逆")
    }

    // 公开例 2：稼穑格真成（千里命稿）— 财癸透时干不破格
    func testJiaseTrue() {
        let r = Zhuanwang.check(pillars: pillars("戊戌己未戊辰癸丑"), dayStem: "戊")
        XCTAssertEqual(r.verdict, "真成")
        XCTAssertEqual(r.wangPct, 62.5, accuracy: 0.15)
        XCTAssertEqual(r.cond3, "无逆")
        XCTAssertTrue(r.notes.contains { $0.contains("逢财") })
    }

    // 公开例 3：从革格真成（千里命稿）
    func testConggeTrue() {
        let r = Zhuanwang.check(pillars: pillars("戊申辛酉庚戌乙酉"), dayStem: "庚")
        XCTAssertEqual(r.verdict, "真成")
        XCTAssertEqual(r.wangPct, 57.3, accuracy: 0.15)
        XCTAssertEqual(r.cond3, "无逆")
    }

    // 公开例 4：润下格真成（千里命稿）
    func testRunxiaTrue() {
        let r = Zhuanwang.check(pillars: pillars("壬申壬子壬辰庚子"), dayStem: "壬")
        XCTAssertEqual(r.verdict, "真成")
        XCTAssertEqual(r.wangPct, 60.4, accuracy: 0.15)
        XCTAssertEqual(r.cond3, "无逆")
    }

    // 公开例 5：朱祖夏失败例（破格）— 壬透干＋辰水库有效库根
    func testZhuFail() {
        let r = Zhuanwang.check(pillars: pillars("甲戌丙寅丙午壬辰"), dayStem: "丙")
        XCTAssertEqual(r.verdict, "不成")
        XCTAssertEqual(r.cond3, "强逆")
        XCTAssertTrue(r.cond3KuRoot)
    }

    // 公开例 6：朱祖夏不真例（假成）— 丁透干，戌火库在金局内化掉
    func testZhuNotTrue() {
        let r = Zhuanwang.check(pillars: pillars("戊申辛酉庚戌丁丑"), dayStem: "庚")
        XCTAssertEqual(r.verdict, "假成")
        XCTAssertEqual(r.cond3, "弱逆")
        XCTAssertTrue(r.cond3Tou)
        XCTAssertFalse(r.cond3BenRoot)
        XCTAssertFalse(r.cond3KuRoot)
    }

    // 公开例 7：炎上格真成（千里命稿·外格篇）— 丁巳 丙午 丙寅 乙未，巳午未三会火局；克星水全无
    func testYanshangPublic() {
        let r = Zhuanwang.check(pillars: pillars("丁巳丙午丙寅乙未"), dayStem: "丙")
        XCTAssertEqual(r.verdict, "真成")
        XCTAssertEqual(r.wangPct, 55.0, accuracy: 0.15)
        XCTAssertEqual(r.cond1Via, "三会/三合")
        XCTAssertEqual(r.cond3, "无逆")
    }

    // 合成例 8：条件 1 不成立（日主丙火，火 37.6% 无局；月令午得令、通根 1 处）
    func testCond1Fail() {
        let r = Zhuanwang.check(pillars: pillars("戊子丁午丙寅乙卯"), dayStem: "丙")
        XCTAssertEqual(r.verdict, "非专旺候选")
        XCTAssertFalse(r.cond1)
        XCTAssertTrue(r.cond2)
    }

    // 合成例 9：条件 2 得令不成立（日主甲木，木 62.5% 达标；月令丑土不得令）
    func testCond2Fail() {
        let r = Zhuanwang.check(pillars: pillars("甲子乙丑甲寅乙卯"), dayStem: "甲")
        XCTAssertEqual(r.verdict, "非专旺候选")
        XCTAssertTrue(r.cond1)
        XCTAssertFalse(r.cond2)
    }

    // 合成例 10：从势候选（旺行木≠日主土）
    func testCongshiCandidate() {
        let r = Zhuanwang.check(pillars: pillars("壬寅癸卯戊辰甲子"), dayStem: "戊")
        XCTAssertEqual(r.verdict, "非专旺（从势候选）")
        XCTAssertNil(r.cond3)
    }

    // 合成例 11：食伤泄秀不破格（曲直格例藏干寅中气丙为食伤）
    func testShishangNotPo() {
        let r = Zhuanwang.check(pillars: pillars("壬寅癸卯甲辰甲子"), dayStem: "甲")
        XCTAssertTrue(r.notes.contains { $0.contains("食伤泄秀为喜") })
    }

    // 升格断语行（C10 §七，2026-11-09 主代理批准接线）：7 则公开例逐字断言＋2 则空行
    func testVerdictLines() {
        XCTAssertEqual(Zhuanwang.verdictLine(pillars: pillars("壬寅癸卯甲辰甲子"), dayStem: "甲"),
            "专旺格真成：木独旺成势（寅卯辰东方），不见克星。用神取木，喜水相助、食伤泄秀，忌金克伐。逢财藏干须有食伤通关。")
        XCTAssertEqual(Zhuanwang.verdictLine(pillars: pillars("戊戌己未戊辰癸丑"), dayStem: "戊"),
            "专旺格真成：土独旺成势（辰戌丑未），不见克星。用神取土，喜火相助、食伤泄秀，忌木克伐。逢财透干须有食伤通关。")
        XCTAssertEqual(Zhuanwang.verdictLine(pillars: pillars("戊申辛酉庚戌乙酉"), dayStem: "庚"),
            "专旺格真成：金独旺成势（申酉戌西方），不见克星。用神取金，喜土相助、食伤泄秀，忌火克伐。逢财透干须有食伤通关。")
        XCTAssertEqual(Zhuanwang.verdictLine(pillars: pillars("壬申壬子壬辰庚子"), dayStem: "壬"),
            "专旺格真成：水独旺成势（申子辰水局），不见克星。用神取水，喜金相助、食伤泄秀，忌土克伐。")
        XCTAssertEqual(Zhuanwang.verdictLine(pillars: pillars("丁巳丙午丙寅乙未"), dayStem: "丙"),
            "专旺格真成：火独旺成势（巳午未南方），不见克星。用神取火，喜木相助、食伤泄秀，忌水克伐。逢财藏干须有食伤通关。")
        XCTAssertEqual(Zhuanwang.verdictLine(pillars: pillars("甲戌丙寅丙午壬辰"), dayStem: "丙"),
            "专旺格不成：火虽成势，时干壬水通根坐辰库，克伐旺神，专旺破格。改按身旺论，不取专旺用神。")
        XCTAssertEqual(Zhuanwang.verdictLine(pillars: pillars("戊申辛酉庚戌丁丑"), dayStem: "庚"),
            "专旺格假成：金虽独旺成势，但时干丁火虚浮无根，格不纯粹。用神仍取金，须防火介入。")
        XCTAssertEqual(Zhuanwang.verdictLine(pillars: pillars("戊子丁午丙寅乙卯"), dayStem: "丙"), "")
        XCTAssertEqual(Zhuanwang.verdictLine(pillars: pillars("壬寅癸卯戊辰甲子"), dayStem: "戊"), "")
    }
}
