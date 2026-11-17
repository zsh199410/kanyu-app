import XCTest
@testable import Kanyu

/// QA 导出验收 P0 门禁测试（独立 QA 分支 qa/poster-export-acceptance-20261117）。
/// 任务三：旧人物自动迁移只跑一次（一次性标记），新孤儿记录永不被同名自动认领。
/// 任务四：紫微 stableID 多归属（v2 索引），同盘面两人各归其人、歧义禁导出。
/// 测试人物为虚构（王小明），不用家人真实信息；不改既有测试与断言。
final class PosterOwnershipGatesTests: XCTestCase {
    // 固定测试人物：同名两人，生辰不同（2000-01-01 与 2001-01-01）。
    private func personA() -> Person { Person(name: "王小明", birthEpoch: 946684800) }
    private func personB() -> Person { Person(name: "王小明", birthEpoch: 978307200) }
    private func ziweiChart(for person: Person) -> ZiweiChart {
        ZiweiEngine.chart(clock: person.birthDate, gender: person.gender,
                          longitude: person.useLongitude ? person.longitude : nil)
    }
    private func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    private func writeJSON<T: Encodable>(_ value: T, name: String, in dir: URL) {
        guard let data = try? JSONEncoder().encode(value) else {
            XCTFail("测试夹具写入失败：\(name)")
            return
        }
        try? data.write(to: dir.appendingPathComponent(name), options: .atomic)
    }
    private func markerExists(in dir: URL) -> Bool {
        FileManager.default.fileExists(atPath: dir.appendingPathComponent("palm_legacy_migration_done.json").path)
    }
    private func migrateEvents(in dir: URL) -> [PalmOwnershipEvent] {
        PalmOwnershipLog.load(directory: dir).filter { $0.action == "migrate" }
    }

    // MARK: - 任务三：一次性历史迁移

    @MainActor
    func testNewOrphanWithUniqueNameMatchIsNotAutoClaimed() {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let person = personA()
        writeJSON([person], name: "people.json", in: dir)
        // 空库首次加载即立标记；此后新增的孤儿记录永不参与自动迁移。
        let store = PalmRecordStore(directory: dir)
        XCTAssertTrue(markerExists(in: dir))
        let record = PalmRecord(personID: nil, personName: person.name, kind: "手相",
                                summary: "测试摘要", linesFlat: [])
        store.add(record, image: nil)
        // 模拟重启：重建 store 重新加载，孤儿仍为孤儿。
        let reloaded = PalmRecordStore(directory: dir)
        XCTAssertNil(reloaded.records.first?.personID)
        XCTAssertTrue(reloaded.records.first?.isOrphan ?? false)
        XCTAssertTrue(migrateEvents(in: dir).isEmpty)
    }

    @MainActor
    func testLegacyOrphanWithUniqueNameMatchIsMigratedOnce() {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let person = personA()
        writeJSON([person], name: "people.json", in: dir)
        let record = PalmRecord(personID: nil, personName: person.name, kind: "手相",
                                summary: "测试摘要", linesFlat: [])
        // 直接写档模拟更新前旧档（无标记文件）。
        writeJSON([record], name: "palm_records.json", in: dir)
        XCTAssertFalse(markerExists(in: dir))
        let store = PalmRecordStore(directory: dir)
        XCTAssertEqual(store.records.first?.personID, person.id)
        XCTAssertTrue(markerExists(in: dir))
        let events = migrateEvents(in: dir)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.recordID, record.id)
        XCTAssertEqual(events.first?.personID, person.id)
        // 第二次加载不再迁移：migrate 事件仍恰好一条。
        _ = PalmRecordStore(directory: dir)
        XCTAssertEqual(migrateEvents(in: dir).count, 1)
    }

    @MainActor
    func testAmbiguousNameStaysOrphanOnLegacyMigration() {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = personA()
        let b = personB()
        XCTAssertEqual(a.name, b.name)
        writeJSON([a, b], name: "people.json", in: dir)
        let record = PalmRecord(personID: nil, personName: a.name, kind: "手相",
                                summary: "测试摘要", linesFlat: [])
        writeJSON([record], name: "palm_records.json", in: dir)
        let store = PalmRecordStore(directory: dir)
        // 同名多人：唯一匹配失败，留孤儿；标记仍立（下次不再尝试）。
        XCTAssertNil(store.records.first?.personID)
        XCTAssertTrue(store.records.first?.isOrphan ?? false)
        XCTAssertTrue(markerExists(in: dir))
        XCTAssertTrue(migrateEvents(in: dir).isEmpty)
    }

    @MainActor
    func testLegacyMigrationSkipsAlreadyLinkedRecords() {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = personA()
        let b = personB()
        writeJSON([a, b], name: "people.json", in: dir)
        let linked = PalmRecord(personID: a.id, personName: a.name, kind: "手相",
                                summary: "测试摘要", linesFlat: [])
        let orphan = PalmRecord(personID: nil, personName: "无人匹配", kind: "手相",
                                summary: "测试摘要", linesFlat: [])
        writeJSON([linked, orphan], name: "palm_records.json", in: dir)
        let store = PalmRecordStore(directory: dir)
        XCTAssertEqual(store.records.first(where: { $0.id == linked.id })?.personID, a.id)
        XCTAssertNil(store.records.first(where: { $0.id == orphan.id })?.personID)
        XCTAssertTrue(migrateEvents(in: dir).isEmpty)
    }

    // MARK: - 任务四：紫微 stableID 多归属（v2）

    func testZiweiSameChartTwoPeopleBothLinked() {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        // 同生辰同性别两人：同一盘面、同一 stableID。
        let a = personA()
        let b = personA()
        XCTAssertNotEqual(a.id, b.id)
        let chartA = ziweiChart(for: a)
        let chartB = ziweiChart(for: b)
        XCTAssertEqual(chartA.stableID, chartB.stableID)
        var index = ZiweiOwnershipIndex.load(directory: dir)
        index.link(stableID: chartA.stableID, to: a.id)
        index.link(stableID: chartA.stableID, to: b.id)
        // 两人都在归属列表里（保序）；唯一归属解析返回 nil（歧义）。
        XCTAssertEqual(index.ownerIDs(for: chartA.stableID), [a.id, b.id])
        XCTAssertNil(index.ownerID(for: chartA.stableID))
        // 同一人重复 link 不追加（不制造假歧义）。
        index.link(stableID: chartA.stableID, to: a.id)
        XCTAssertEqual(index.ownerIDs(for: chartA.stableID), [a.id, b.id])
        // 持久化往返后仍为两人。
        index.save(directory: dir)
        XCTAssertEqual(ZiweiOwnershipIndex.load(directory: dir).ownerIDs(for: chartA.stableID), [a.id, b.id])
    }

    func testZiweiSnapshotsDoNotCrossForSameChart() {
        let a = personA()
        let b = personA()
        let chart = ziweiChart(for: a)
        XCTAssertEqual(chart.stableID, ziweiChart(for: b).stableID)
        let snapA = PosterDynamicSnapshot.ziwei(chart: chart, name: a.name, ownerIDs: [a.id])
        let snapB = PosterDynamicSnapshot.ziwei(chart: chart, name: b.name, ownerIDs: [b.id])
        // 同盘面两人快照各归其人，不串。
        XCTAssertEqual(snapA.ownerID, a.id)
        XCTAssertEqual(snapB.ownerID, b.id)
        XCTAssertNotEqual(snapA.ownerID, snapB.ownerID)
        XCTAssertTrue(snapA.canArchive)
        XCTAssertTrue(snapB.canArchive)
        XCTAssertTrue(snapA.missingFields.isEmpty)
        XCTAssertTrue(snapB.missingFields.isEmpty)
    }

    func testZiweiAmbiguousSnapshotCannotArchive() {
        let a = personA()
        let b = personA()
        let chart = ziweiChart(for: a)
        let snapshot = PosterDynamicSnapshot.ziwei(chart: chart, name: a.name, ownerIDs: [a.id, b.id])
        // 歧义盘面无显式选人：ownerID 为 nil、blocking 缺失、禁正式导出。
        XCTAssertNil(snapshot.ownerID)
        XCTAssertFalse(snapshot.canArchive)
        XCTAssertTrue(snapshot.missingFields.contains { $0.id == "ownerID-ambiguous" && $0.blocking })
        // 快照仍含盘面内容（非正式预览可用），只是禁正式导出。
        XCTAssertFalse(snapshot.sections.isEmpty)
    }

    func testZiweiRemoveOnePersonKeepsOther() {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = personA()
        let b = personA()
        let chart = ziweiChart(for: a)
        var index = ZiweiOwnershipIndex.load(directory: dir)
        index.link(stableID: chart.stableID, to: a.id)
        index.link(stableID: chart.stableID, to: b.id)
        // 删一人后另一人归属不受影响，且恢复为唯一归属。
        index.removeAll(for: a.id)
        XCTAssertEqual(index.ownerIDs(for: chart.stableID), [b.id])
        XCTAssertEqual(index.ownerID(for: chart.stableID), b.id)
        // 删单人 unlink 亦同。
        index.link(stableID: chart.stableID, to: a.id)
        index.unlink(stableID: chart.stableID, personID: a.id)
        XCTAssertEqual(index.ownerIDs(for: chart.stableID), [b.id])
    }

    func testZiweiV1IndexMigratesToV2() {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = personA()
        let chart = ziweiChart(for: a)
        // 直接写 v1 形状文件（entries 单值、schemaVersion 1）。
        let v1JSON = "{\"schemaVersion\":1,\"entries\":{\"\(chart.stableID)\":\"\(a.id.uuidString)\"},\"updatedEpoch\":1700000000}"
        _ = try? v1JSON.data(using: .utf8)?.write(to: dir.appendingPathComponent("ziwei_ownership.json"), options: .atomic)
        let loaded = ZiweiOwnershipIndex.load(directory: dir)
        XCTAssertEqual(loaded.schemaVersion, 2)
        XCTAssertEqual(loaded.ownerIDs(for: chart.stableID), [a.id])
        XCTAssertEqual(loaded.ownerID(for: chart.stableID), a.id)
        // 磁盘文件已迁移为 v2 数组形状。
        guard let raw = try? Data(contentsOf: dir.appendingPathComponent("ziwei_ownership.json")),
              let obj = try? JSONSerialization.jsonObject(with: raw) as? [String: Any],
              let entries = obj["entries"] as? [String: Any] else {
            XCTFail("迁移后索引文件不可读")
            return
        }
        XCTAssertTrue(entries[chart.stableID] is [Any])
        XCTAssertEqual(obj["schemaVersion"] as? Int, 2)
    }
}
