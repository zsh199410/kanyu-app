// 全部工具注册表回归（AllToolsData，Sources/AllToolsView.swift）：37 项工具的 id 唯一、分组计数、
// 别名搜索、最近使用。与风险点 (f) 相关：导航入口不得空白／不可返回；
// toolDestination 返回不透明 some View、分支归属不可直测，UI 部分见 UITests/ToolsNavigationTests.swift。
// UserDefaults 隔离：recordRecent／recentEntries 读写真实 UserDefaults.standard，
// setUp 保存、tearDown 恢复，避免污染真机数据与互相干扰。
import XCTest
@testable import Kanyu

final class ToolRegistryTests: XCTestCase {
    private let recentKey = "recentTools.v1"
    private var savedRecent: [String]?

    override func setUp() {
        super.setUp()
        savedRecent = UserDefaults.standard.stringArray(forKey: recentKey)
        UserDefaults.standard.removeObject(forKey: recentKey)
    }

    override func tearDown() {
        if let saved = savedRecent {
            UserDefaults.standard.set(saved, forKey: recentKey)
        } else {
            UserDefaults.standard.removeObject(forKey: recentKey)
        }
        savedRecent = nil
        super.tearDown()
    }

    func testAllItemsCountAndUniqueIDs() {
        XCTAssertEqual(AllToolsData.allItems.count, 37)
        XCTAssertEqual(Set(AllToolsData.allItems.map(\.id)).count, 37, "工具 id 必须唯一")
    }

    func testGroupCounts() {
        XCTAssertEqual(AllToolsData.allItems.filter { $0.group == .paipan }.count, 12)
        XCTAssertEqual(AllToolsData.allItems.filter { $0.group == .calendar }.count, 6)
        XCTAssertEqual(AllToolsData.allItems.filter { $0.group == .knowledge }.count, 9)
        XCTAssertEqual(AllToolsData.allItems.filter { $0.group == .tools }.count, 10)
        XCTAssertEqual(AllToolsData.allItems.filter { $0.group == .all }.count, 0, ".all 只是筛选伪分组，不应有工具归属它")
    }

    func testItemRoundTrip() {
        for item in AllToolsData.allItems {
            XCTAssertEqual(AllToolsData.item(for: item.id)?.id, item.id)
        }
        XCTAssertNil(AllToolsData.item(for: "no-such-tool"))
    }

    func testChartConsumingIDsExist() {
        // 8 个用盘工具（从 toolDestination switch 体反推，与 PR #15 的 chartRequiredIDs 逐字一致）：
        // 锁死该集合，供 #15 合并时交叉核对；真正的无人物守门测试在 #15 合并后补（见审计报告）。
        let chartIDs = ["astro", "yearly", "interpret", "chartdepth", "poster", "chenggu", "lucky", "annual"]
        for id in chartIDs {
            XCTAssertNotNil(AllToolsData.item(for: id), "用盘工具 \(id) 必须在注册表里")
        }
    }

    func testFilteredItemsGroup() {
        XCTAssertEqual(AllToolsData.filteredItems(query: "", groupIndex: 0).count, 37)
        XCTAssertEqual(AllToolsData.filteredItems(query: "", groupIndex: 1).count, 12)
        XCTAssertEqual(AllToolsData.filteredItems(query: "", groupIndex: 2).count, 6)
        XCTAssertEqual(AllToolsData.filteredItems(query: "", groupIndex: 3).count, 9)
        XCTAssertEqual(AllToolsData.filteredItems(query: "", groupIndex: 4).count, 10)
        XCTAssertEqual(AllToolsData.filteredItems(query: "", groupIndex: 99).count, 37, "越界分组回落为全部")
        XCTAssertEqual(AllToolsData.filteredItems(query: "", groupIndex: -1).count, 37, "负分组回落为全部")
    }

    func testFilteredItemsAliasSearch() {
        let ids = { (items: [ToolItem]) in Set(items.map(\.id)) }
        XCTAssertTrue(ids(AllToolsData.filteredItems(query: "八字", groupIndex: 0)).contains("interpret"), "别名“八字”应搜到 30 维详批")
        XCTAssertTrue(ids(AllToolsData.filteredItems(query: "指南针", groupIndex: 0)).contains("compass"), "别名“指南针”应搜到罗盘实测")
        XCTAssertTrue(ids(AllToolsData.filteredItems(query: "入门", groupIndex: 0)).contains("learning"), "别名“入门”应搜到白话使用指南")
        XCTAssertTrue(AllToolsData.filteredItems(query: "zzz-no-match", groupIndex: 0).isEmpty)
    }

    func testFilteredItemsTitleSearch() {
        let ids = Set(AllToolsData.filteredItems(query: "罗盘", groupIndex: 0).map(\.id))
        XCTAssertEqual(ids, ["compass", "workbench"], "“罗盘”命中罗盘实测（标题）与风水勘察（描述）")
    }

    func testRecentEntriesCapDedupAndOrder() {
        let ids = ["astro", "compass", "almanac", "quiz", "backup", "meihua", "library"]
        for id in ids { AllToolsData.recordRecent(tool: id) }
        let entries = AllToolsData.recentEntries(people: [])
        XCTAssertEqual(entries.count, 6, "最近使用上限 6 条")
        XCTAssertEqual(entries.first?.id, "library", "最后记录的应置顶")
        XCTAssertEqual(entries.map(\.id), ["library", "meihua", "backup", "quiz", "almanac", "compass"], "超出上限时最早的 astro 应被挤出")
        AllToolsData.recordRecent(tool: "quiz")
        XCTAssertEqual(AllToolsData.recentEntries(people: []).map(\.id).first, "quiz", "重复记录去重后置顶")
        XCTAssertEqual(AllToolsData.recentEntries(people: []).count, 6)
    }

    func testRecentEntriesPersonResolvedAndSkipped() {
        // 2000-01-01 合成数据，不含家人出生数据
        let person = Person(name: "合成甲", gender: "M", birthEpoch: 946684800)
        AllToolsData.recordRecent(person: person)
        AllToolsData.recordRecent(tool: "compass")
        let resolved = AllToolsData.recentEntries(people: [person])
        XCTAssertEqual(resolved.count, 2)
        XCTAssertEqual(resolved[0].id, "compass")
        XCTAssertEqual(resolved[1].id, "person:" + person.id.uuidString)
        // 人物 id 解析不到档案时跳过
        let skipped = AllToolsData.recentEntries(people: [])
        XCTAssertEqual(skipped.count, 1)
        XCTAssertEqual(skipped[0].id, "compass")
    }
}
