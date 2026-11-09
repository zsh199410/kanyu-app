// 解盘／紫微展开集编解码回归（性能收尾：第 ⑥ 项）。
// 展开集原来是 @State 会话内状态，重启后丢失；现经 SceneStorage 逗号串跨启动保留。
// 本文件只测纯编解码函数（encode/decode），不测 SceneStorage 本身。
import XCTest
@testable import Kanyu

final class InterpretExpansionTests: XCTestCase {
    // MARK: - 解盘展开集（Set<Int>）
    func testDecodeDefault() {
        XCTAssertEqual(decodeExpandedItems("0,1,2,3,4"), [0, 1, 2, 3, 4])
    }

    func testEncodeDefault() {
        XCTAssertEqual(encodeExpandedItems([0, 1, 2, 3, 4]), "0,1,2,3,4")
    }

    func testRoundTrip() {
        XCTAssertEqual(decodeExpandedItems(encodeExpandedItems([2, 7, 29])), [2, 7, 29])
    }

    func testEmpty() {
        XCTAssertEqual(decodeExpandedItems(""), [])
        XCTAssertEqual(encodeExpandedItems([]), "")
    }

    func testOutOfOrderSortedOnEncode() {
        XCTAssertEqual(decodeExpandedItems("3,1"), [1, 3])
        XCTAssertEqual(encodeExpandedItems([3, 1]), "1,3")
    }

    func testIllegalSegmentSkipped() {
        XCTAssertEqual(decodeExpandedItems("2,x,5"), [2, 5])
    }

    // MARK: - 紫微 11 卡展开集（Set<String>）
    func testCardsDecodeDefault() {
        XCTAssertEqual(decodeExpandedCards("命宫定型"), ["命宫定型"])
    }

    func testCardsRoundTripAllTitles() {
        let titles: Set<String> = ["命宫定型", "三方四正", "生年四化", "大限推程",
                                    "财帛赚钱", "官禄事业", "夫妻婚恋", "疾厄体质",
                                    "田宅置业", "福德心境", "迁移外出"]
        XCTAssertEqual(decodeExpandedCards(encodeExpandedCards(titles)), titles)
    }

    func testCardsEmpty() {
        XCTAssertEqual(decodeExpandedCards(""), [])
        XCTAssertEqual(encodeExpandedCards([]), "")
    }

    func testCardsEncodeSorted() {
        XCTAssertEqual(encodeExpandedCards(["迁移外出", "命宫定型"]), "命宫定型,迁移外出")
    }
}
