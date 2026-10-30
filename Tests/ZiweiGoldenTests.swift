// 紫微金标准盘对拍（14 例，iztro 参照引擎生成——与主流排盘软件同源）：
// 命宫/身宫/五行局/宫名/十四主星/四化/十六辅星/大限，逐项锁死。口径差异（晚子时/闰月）例不在本卷。
import XCTest
@testable import Kanyu

final class ZiweiGoldenTests: XCTestCase {
    struct Lunar: Decodable { let yearStem: String; let month: Int; let leap: Bool; let day: Int }
    struct Golden: Decodable {
        let name: String; let ti: Int; let gender: String; let lunar: Lunar; let yearBranch: String
        let soul: String; let body: String; let ju: String
        let majors: [String: String]; let mutagens: [String: String]
        let minors: [String: String]; let decadal: [String: [Int]]; let palaceNames: [String: String]
    }
    func testZiweiGolden() throws {
        let url = Bundle(for: Self.self).url(forResource: "ziwei_golden", withExtension: "json")!
        let list = try JSONDecoder().decode([Golden].self, from: Data(contentsOf: url))
        XCTAssertEqual(list.count, 14)
        let dz = Array("子丑寅卯辰巳午未申酉戌亥")
        for g in list {
            let month = g.lunar.leap ? min(g.lunar.month + 1, 12) : g.lunar.month
            let ch = ZiweiCore.compute(yearStem: g.lunar.yearStem.first!,
                                       yearBranch: dz.firstIndex(of: g.yearBranch.first!)!,
                                       month: month, day: g.lunar.day, hourBranch: g.ti,
                                       isMale: g.gender == "男")
            XCTAssertEqual(String(dz[ch.mingGong]), g.soul, g.name)
            XCTAssertEqual(String(dz[ch.shenGong]), g.body, g.name)
            XCTAssertEqual(ch.juName, g.ju, g.name)
            for p in ch.palaces {
                let b = String(dz[p.branch])
                XCTAssertEqual(p.name, g.palaceNames[b], g.name)
                XCTAssertEqual(p.decadal, g.decadal[b], g.name)
                for m in p.majors {
                    XCTAssertEqual(g.majors[m.star], b, "\(g.name) \(m.star)")
                    XCTAssertEqual(g.mutagens[m.star], m.mutagen, "\(g.name) \(m.star)四化")
                }
                for s in p.minors {
                    XCTAssertEqual(g.minors[s], b, "\(g.name) \(s)")
                }
            }
            XCTAssertEqual(ch.palaces.flatMap { $0.majors }.count, 14, g.name)
        }
    }
}
