// 羊刃格／月劫格格局层回归（2026-11-08，三项全做 track3）。
// 阳刃惟五阳有之（《渊海子平·论阳刃》《三命通会》卷六·论阳刃《子平真诠·论阳刃》）；
// 阴干月令逢劫为月劫（《子平真诠·论建禄月劫》徐注：阳干为刃，阴干为劫）。
// 日期均为合成日期，与家人盘无关；用 BaziEngine.paipan 现算真盘，再走 InterpretEngine.interpret。
// 断言只看「月令格局（候选）」条结论里的格名；神煞层（禄前一位）不在此测。
import XCTest
@testable import Kanyu

final class YangrenPatternTests: XCTestCase {
    private func patternConclusion(clock: String) -> String {
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd HH:mm"
        fmt.timeZone = TimeZone(secondsFromGMT: 8 * 3600)
        let ch = BaziEngine.paipan(clock: fmt.date(from: clock)!, gender: "M", longitude: 107.8)
        let items = InterpretEngine.interpret(chart: ch)
        return items.first(where: { $0.title == "月令格局（候选）" })!.conclusion
    }

    // 阴干劫财应得月劫格，且结论里不得出现羊刃格（成败也不得走刃格分支）
    func testYinDayJieCaiIsYueJie() {
        for clock in ["2010-02-04 12:00", "2010-05-07 12:00", "2010-04-09 12:00",
                      "2010-10-16 12:00", "2010-08-09 12:00", "2010-11-09 12:00"] {
            let c = patternConclusion(clock: clock)
            XCTAssertTrue(c.contains("先按月劫格候选看"), clock + " -> " + c)
            XCTAssertFalse(c.contains("羊刃格"), clock + " -> " + c)
        }
        // 乙／寅一例加查成败：不得走「刃格无官煞」，应走建禄月劫口径
        let c = patternConclusion(clock: "2010-02-04 12:00")
        XCTAssertFalse(c.contains("刃格无官煞"), c)
    }

    // 阳干劫财仍为羊刃格（对照）
    func testYangDayJieCaiIsYangRen() {
        for clock in ["2010-03-15 12:00", "2010-06-15 12:00", "2010-07-17 12:00",
                      "2010-09-17 12:00", "2010-01-02 12:00"] {
            XCTAssertTrue(patternConclusion(clock: clock).contains("先按羊刃格候选看"), clock)
        }
    }

    // 比肩建禄不变（对照）
    func testBiJianIsJianLu() {
        for clock in ["2010-02-13 12:00", "2010-03-06 12:00"] {
            XCTAssertTrue(patternConclusion(clock: clock).contains("先按建禄格候选看"), clock)
        }
    }
}
