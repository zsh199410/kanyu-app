// 回验打标现行 API 回归（VerifyStore，Sources/InterpretModule.swift，main 标题键 v1）。
// 与风险点 (b) 相关：main 的键只有解读标题一维，不同人物同名条目共享标记——这是已知缺陷（Issue #10）。
// 本文件只锁死现行 v1 API 的同标题读写与统计口径；PR #18 将其替换为按人物隔离的 v2 API
// （VerifyStore.set／mark 带 ownerID，Tests/VerificationIsolationTests.swift），
// #18 合并后本文件须随 API 迁移或删除，不得与 #18 的测试重复。
// UserDefaults 隔离：VerifyStore 读写真实 UserDefaults.standard，setUp 保存、tearDown 恢复
// 私有键 "kanyu.verifyMarks.v1"（此处仅作清理用字面量）。
import XCTest
@testable import Kanyu

final class VerifyStoreCurrentTests: XCTestCase {
    private let key = "kanyu.verifyMarks.v1"
    private var saved: [String: Bool]?

    override func setUp() {
        super.setUp()
        saved = UserDefaults.standard.dictionary(forKey: key) as? [String: Bool]
        UserDefaults.standard.removeObject(forKey: key)
    }

    override func tearDown() {
        if let saved = saved {
            UserDefaults.standard.set(saved, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
        saved = nil
        super.tearDown()
    }

    func testSetMarkRoundTrip() {
        XCTAssertNil(VerifyStore.mark(for: "事业方向"))
        VerifyStore.set("事业方向", true)
        XCTAssertEqual(VerifyStore.mark(for: "事业方向"), true)
        VerifyStore.set("事业方向", false)
        XCTAssertEqual(VerifyStore.mark(for: "事业方向"), false)
    }

    func testVerifiedAndPendingCounts() {
        VerifyStore.set("事业方向", true)
        VerifyStore.set("财运走势", false)
        let titles = ["事业方向", "财运走势", "婚恋感情"]
        XCTAssertEqual(VerifyStore.verifiedCount(titles: titles), 1)
        XCTAssertEqual(VerifyStore.pendingCount(titles: titles), 1)
    }

    func testAccuracy() {
        XCTAssertNil(VerifyStore.accuracy(titles: ["事业方向"]), "未打标时准确率为 nil")
        VerifyStore.set("事业方向", true)
        VerifyStore.set("财运走势", false)
        XCTAssertEqual(VerifyStore.accuracy(titles: ["事业方向", "财运走势"]) ?? -1, 0.5, accuracy: 1e-9)
        XCTAssertEqual(VerifyStore.accuracy(titles: ["事业方向"]) ?? -1, 1.0, accuracy: 1e-9)
        XCTAssertEqual(VerifyStore.accuracy(titles: ["财运走势"]) ?? -1, 0.0, accuracy: 1e-9)
    }

    func testConfidenceLabelStates() {
        XCTAssertEqual(InterpretEngine.confidenceLabel(title: "事业方向", mechanism: nil), "未打标 · 盘面事实")
        VerifyStore.set("事业方向", true)
        XCTAssertEqual(InterpretEngine.confidenceLabel(title: "事业方向", mechanism: nil), "已验真 · 盘面事实")
        VerifyStore.set("事业方向", false)
        XCTAssertEqual(InterpretEngine.confidenceLabel(title: "事业方向", mechanism: nil), "待回验 · 盘面事实")
        XCTAssertEqual(InterpretEngine.confidenceLabel(title: "事业方向", mechanism: "《滴天髓》有云"), "待回验 · 五典原文")
        XCTAssertEqual(InterpretEngine.confidenceLabel(title: "事业方向", mechanism: "本系统回测纪律"), "待回验 · 本系统回测纪律")
        XCTAssertEqual(InterpretEngine.confidenceLabel(title: "事业方向", mechanism: "民间象征说法"), "待回验 · 民间象征")
    }
}
