import XCTest
@testable import Kanyu

/// P0-4 PeopleStore：load/save 往返、setCurrentPerson＋回落、remove 清理、import 去重、坏档处理。
/// 目录用临时目录注入，绝不碰真实 Documents；currentPersonId／recentTools 走 UserDefaults.standard
///（与生产一致），setUp 记下原值、tearDown 原样恢复，不动真实数据。
/// 边界：VerifyStore／手相／前瞻／报告的级联删除见 PersonCascadeTests；详情页「换人」菜单到
/// setCurrentPerson 的接线只能走 XCUITest（本文件只测 setCurrentPerson 本身）。
@MainActor
final class PeopleStoreTests: XCTestCase {
    private var dir: URL!
    private var origCurrentPersonId: String?
    private var origRecentTools: [String]?

    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("PeopleStoreTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        origCurrentPersonId = UserDefaults.standard.string(forKey: "currentPersonId")
        origRecentTools = UserDefaults.standard.stringArray(forKey: "recentTools.v1")
    }

    override func tearDown() {
        if let v = origCurrentPersonId { UserDefaults.standard.set(v, forKey: "currentPersonId") } else { UserDefaults.standard.removeObject(forKey: "currentPersonId") }
        if let v = origRecentTools { UserDefaults.standard.set(v, forKey: "recentTools.v1") } else { UserDefaults.standard.removeObject(forKey: "recentTools.v1") }
        try? FileManager.default.removeItem(at: dir)
        dir = nil
        super.tearDown()
    }

    private func makePerson(name: String, relation: String = "") -> Person {
        Person(name: name, relation: relation, birthEpoch: 946684800)
    }

    func testLoadSaveRoundtrip() {
        let store = PeopleStore(directory: dir)
        let p = makePerson(name: "QA-A", relation: "本人")
        store.upsert(p)
        let reloaded = PeopleStore(directory: dir)
        XCTAssertEqual(reloaded.people.count, 1)
        XCTAssertEqual(reloaded.people.first?.id, p.id)
        XCTAssertEqual(reloaded.people.first?.name, "QA-A")
        XCTAssertEqual(reloaded.people.first?.birthEpoch, 946684800)
    }

    func testSetCurrentPersonAndFallback() {
        let store = PeopleStore(directory: dir)
        let a = makePerson(name: "QA-A", relation: "本人")
        let b = makePerson(name: "QA-B", relation: "儿子")
        store.upsert(a)
        store.upsert(b)
        store.setCurrentPerson(b)
        XCTAssertEqual(store.currentPerson?.id, b.id)
        // currentPersonId 指向不存在的人 → 回落到 relation 本人
        store.currentPersonId = UUID()
        XCTAssertEqual(store.currentPerson?.id, a.id)
        // 本人也被删 → 回落到首位
        store.remove(a)
        XCTAssertEqual(store.currentPerson?.id, b.id)
        // 全删 → nil
        store.remove(b)
        XCTAssertNil(store.currentPerson)
    }

    func testRemoveClearsCurrentPersonIdAndRecentTools() {
        let store = PeopleStore(directory: dir)
        let a = makePerson(name: "QA-A", relation: "本人")
        let b = makePerson(name: "QA-B", relation: "儿子")
        store.upsert(a)
        store.upsert(b)
        store.setCurrentPerson(a)
        UserDefaults.standard.set(["person:\(a.id.uuidString)", "person:\(b.id.uuidString)"], forKey: "recentTools.v1")
        store.remove(a)
        XCTAssertNil(store.currentPersonId)
        XCTAssertEqual(store.currentPerson?.id, b.id)
        let recent = UserDefaults.standard.stringArray(forKey: "recentTools.v1") ?? []
        XCTAssertFalse(recent.contains("person:\(a.id.uuidString)"))
        XCTAssertTrue(recent.contains("person:\(b.id.uuidString)"))
    }

    func testImportDataDedupByID() {
        let store = PeopleStore(directory: dir)
        let a = makePerson(name: "QA-A")
        let b = makePerson(name: "QA-B")
        let wrapped = try! JSONEncoder().encode(PeopleExport(schemaVersion: 1, people: [a, b]))
        XCTAssertEqual(store.importData(wrapped), 2)
        XCTAssertEqual(store.people.count, 2)
        // 再导同一份：同 ID 全跳过，返回 0，条数不变
        XCTAssertEqual(store.importData(wrapped), 0)
        XCTAssertEqual(store.people.count, 2)
        // 无版本旧格式（纯数组）也按 id 去重
        let bare = try! JSONEncoder().encode([a, b])
        XCTAssertEqual(store.importData(bare), 0)
        XCTAssertEqual(store.people.count, 2)
    }

    func testLoadCorruptFileWritesCorruptJSON() {
        try! "not json".write(to: dir.appendingPathComponent("people.json"), atomically: true, encoding: .utf8)
        let store = PeopleStore(directory: dir)
        XCTAssertTrue(store.people.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("people.corrupt.json").path))
    }

    func testExpiredCurrentPersonIdFallsBack() {
        let first = PeopleStore(directory: dir)
        let a = makePerson(name: "QA-A", relation: "本人")
        first.upsert(a)
        // currentPersonId 指向一个已不存在的人（过期）
        UserDefaults.standard.set(UUID().uuidString, forKey: "currentPersonId")
        let store = PeopleStore(directory: dir)
        // 过期 id 不被采纳（currentPersonId 为 nil），currentPerson 回落到本人
        XCTAssertNil(store.currentPersonId)
        XCTAssertEqual(store.currentPerson?.id, a.id)
    }
}
