// 人物档案前置条件回归（PeopleStore／Person／StoreSchema，Sources/PeopleModule.swift）。
// 与风险点 (a) 相关：PeopleStore.currentPerson 本身是诚实的（空档案回 nil）；
// 伪造发生在 AllToolsView 的 private 层（currentPerson／currentChart，不可测），
// 真正的无人物守门测试须等 PR #15 的可测 API（见审计报告）。
// 注意：PeopleStore() 会读测试宿主的 Documents／UserDefaults；本组只读不写
// （不调 save／upsert／remove），UserDefaults 键在 tearDown 清理。
// PeopleStore 为 @MainActor：涉及其实例的两个测试用 async＋MainActor.run 调用，避免给测试类加 @MainActor
// 后与 XCTestCase.setUp／tearDown 的隔离标注冲突。
import XCTest
@testable import Kanyu

final class PeopleStoreBasicsTests: XCTestCase {
    private let currentPersonKey = "currentPersonId"

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: currentPersonKey)
        super.tearDown()
    }

    func testCurrentPersonNilWhenEmpty() async {
        let current = await MainActor.run { PeopleStore().currentPerson }
        XCTAssertNil(current, "全新模拟器上无人物档案时 currentPerson 应为 nil，不伪造")
    }

    func testSetCurrentPersonNilClearsKey() async {
        await MainActor.run {
            let store = PeopleStore()
            store.setCurrentPerson(nil)
        }
        XCTAssertNil(UserDefaults.standard.object(forKey: currentPersonKey))
    }

    func testPersonBirthDateFromEpoch() {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm"
        fmt.timeZone = TimeZone(secondsFromGMT: 8 * 3600)
        let date = fmt.date(from: "2000-06-15 10:30")!
        let person = Person(name: "合成甲", gender: "M", birthEpoch: date.timeIntervalSince1970)
        XCTAssertEqual(person.birthDate, date)
        XCTAssertEqual(person.useLongitude, true)
        XCTAssertEqual(person.longitude, 107.8, accuracy: 1e-9)
    }

    func testStoreSchemaReadVersionMissingIsZero() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("no-such-people-\(UUID().uuidString).json")
        XCTAssertEqual(StoreSchema.readVersion(for: url), 0, "无 meta 文件的旧档按 v0 计")
    }

    func testStoreSchemaWriteThenReadVersion() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("StoreSchemaTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let fileURL = dir.appendingPathComponent("people.json")
        StoreSchema.writeMeta(for: fileURL, count: 3)
        XCTAssertEqual(StoreSchema.readVersion(for: fileURL), StoreSchema.current)
        let meta = try JSONDecoder().decode(StoreSchema.Meta.self, from: Data(contentsOf: StoreSchema.metaURL(for: fileURL)))
        XCTAssertEqual(meta.count, 3)
        XCTAssertEqual(StoreSchema.metaURL(for: fileURL).lastPathComponent, "people.meta.json")
    }

    func testPeopleExportCodableRoundTrip() throws {
        // 2000-01-01 合成数据，不含家人出生数据
        let person = Person(name: "合成甲", gender: "M", birthEpoch: 946684800)
        let data = try JSONEncoder().encode(PeopleExport(schemaVersion: 1, people: [person]))
        let decoded = try JSONDecoder().decode(PeopleExport.self, from: data)
        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertEqual(decoded.people, [person])
    }
}
