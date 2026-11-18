import XCTest
@testable import Kanyu

/// Batch 2 P0：四款海报归属与快照隔离测试（PR #61 第二批 DTO 合同验收第 2 条）。
/// 覆盖 A/B/同名/孤儿/删除/备份恢复/快速切换/并发导出；不删改原 43 条人物断言与既有测试。
/// 注意：测试人物为虚构（王小明），不用家人真实信息。
final class PosterBatch2OwnershipTests: XCTestCase {
    // 固定测试人物：同名两人，生辰不同（2000-01-01 与 2001-01-01）。
    private func personA() -> Person { Person(name: "王小明", birthEpoch: 946684800) }
    private func personB() -> Person { Person(name: "王小明", birthEpoch: 978307200) }
    private func baziChart(for person: Person) -> BaziChart {
        BaziEngine.cachedPaipan(clock: person.birthDate, gender: person.gender,
                                longitude: person.useLongitude ? person.longitude : nil)
    }
    private func ziweiChart(for person: Person) -> ZiweiChart {
        ZiweiEngine.chart(clock: person.birthDate, gender: person.gender,
                          longitude: person.useLongitude ? person.longitude : nil)
    }
    private func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - 孤儿（无归属）禁正式导出

    func testPalmOrphanSnapshotCannotArchive() {
        let record = PalmRecord(personID: nil, personName: "王小明", kind: "手相",
                                summary: "测试摘要", linesFlat: [])
        let snapshot = PosterDynamicSnapshot.palm(record: record, ownerID: nil)
        XCTAssertNil(snapshot.ownerID)
        XCTAssertFalse(snapshot.canArchive)
        XCTAssertTrue(snapshot.missingFields.contains { $0.id == "ownerID" && $0.blocking })
    }

    func testZiweiOrphanSnapshotCannotArchive() {
        let person = personA()
        let chart = ziweiChart(for: person)
        let snapshot = PosterDynamicSnapshot.ziwei(chart: chart, name: person.name, ownerID: nil)
        XCTAssertNil(snapshot.ownerID)
        XCTAssertFalse(snapshot.canArchive)
        XCTAssertTrue(snapshot.missingFields.contains { $0.id == "ownerID" && $0.blocking })
        // 快照仍含盘面内容（非正式预览可用），只是禁正式导出。
        XCTAssertFalse(snapshot.sections.isEmpty)
    }

    // MARK: - 同名两人不串人

    func testSameNameTwoPeopleSnapshotsDoNotCross() {
        let a = personA()
        let b = personB()
        XCTAssertEqual(a.name, b.name)
        XCTAssertNotEqual(a.id, b.id)
        let snapA = PosterDynamicSnapshot.bazi(person: a, chart: baziChart(for: a), premium: false)
        let snapB = PosterDynamicSnapshot.bazi(person: b, chart: baziChart(for: b), premium: false)
        XCTAssertNotEqual(snapA.ownerID, snapB.ownerID)
        XCTAssertNotEqual(snapA.receipt, snapB.receipt)
        XCTAssertTrue(snapA.sourceRecordIDs.contains("Person:\(a.id.uuidString)"))
        XCTAssertTrue(snapB.sourceRecordIDs.contains("Person:\(b.id.uuidString)"))
        XCTAssertFalse(snapA.sourceRecordIDs.contains("Person:\(b.id.uuidString)"))
        XCTAssertFalse(snapB.sourceRecordIDs.contains("Person:\(a.id.uuidString)"))
    }

    // MARK: - 手相显式关联 / 解除关联（迁移证据）

    @MainActor
    func testPalmAssociateAndDisassociate() {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = PalmRecordStore(directory: dir)
        let person = personA()
        let record = PalmRecord(personID: nil, personName: person.name, kind: "手相",
                                summary: "测试摘要", linesFlat: [])
        store.add(record, image: nil)
        XCTAssertTrue(store.records.first?.isOrphan ?? false)
        store.associate(recordID: record.id, to: person.id)
        XCTAssertEqual(store.records.first?.personID, person.id)
        XCTAssertEqual(store.owner(of: store.records[0], in: [person])?.id, person.id)
        let events = PalmOwnershipLog.load(directory: dir)
        XCTAssertTrue(events.contains { $0.action == "associate" && $0.recordID == record.id && $0.personID == person.id })
        store.disassociate(recordID: record.id)
        XCTAssertNil(store.records.first?.personID)
        XCTAssertTrue(store.records.first?.isOrphan ?? false)
        let events2 = PalmOwnershipLog.load(directory: dir)
        XCTAssertTrue(events2.contains { $0.action == "disassociate" && $0.recordID == record.id })
    }

    @MainActor
    func testPalmOwnerReturnsNilForDeletedPerson() {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = PalmRecordStore(directory: dir)
        let person = personA()
        let record = PalmRecord(personID: person.id, personName: person.name, kind: "手相",
                                summary: "测试摘要", linesFlat: [])
        store.add(record, image: nil)
        // 人物已从档案删除：owner 解析为 nil（归属失效，正式导出禁用）。
        XCTAssertNil(store.owner(of: store.records[0], in: []))
        XCTAssertNil(store.owner(of: store.records[0], in: [personB()]))
    }

    // MARK: - 紫微归属索引 link / unlink / 删除 / 备份恢复

    func testZiweiOwnershipIndexLinkUnlinkRoundTrip() {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let person = personA()
        let chart = ziweiChart(for: person)
        var index = ZiweiOwnershipIndex.load(directory: dir)
        XCTAssertNil(index.ownerID(for: chart.stableID))
        index.link(stableID: chart.stableID, to: person.id)
        index.save(directory: dir)
        let loaded = ZiweiOwnershipIndex.load(directory: dir)
        XCTAssertEqual(loaded.ownerID(for: chart.stableID), person.id)
        var index2 = loaded
        index2.unlink(stableID: chart.stableID)
        index2.save(directory: dir)
        XCTAssertNil(ZiweiOwnershipIndex.load(directory: dir).ownerID(for: chart.stableID))
    }

    func testZiweiOwnershipIndexRemoveAllForPerson() {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = personA()
        let b = personB()
        let chartA1 = ziweiChart(for: a)
        let chartA2 = ZiweiEngine.chart(clock: Date(timeIntervalSince1970: 946684800 + 86400),
                                        gender: "M", longitude: 107.8)
        let chartB = ziweiChart(for: b)
        XCTAssertNotEqual(chartA1.stableID, chartA2.stableID)
        var index = ZiweiOwnershipIndex.load(directory: dir)
        index.link(stableID: chartA1.stableID, to: a.id)
        index.link(stableID: chartA2.stableID, to: a.id)
        index.link(stableID: chartB.stableID, to: b.id)
        // 删人物 A：A 的两条关联全清，B 的不受影响。
        index.removeAll(for: a.id)
        XCTAssertNil(index.ownerID(for: chartA1.stableID))
        XCTAssertNil(index.ownerID(for: chartA2.stableID))
        XCTAssertEqual(index.ownerID(for: chartB.stableID), b.id)
        // 备份/恢复 round-trip：导出后导入，内容一致。
        let data = index.exportData()
        let restored = ZiweiOwnershipIndex.importData(data)
        XCTAssertEqual(restored?.ownerID(for: chartB.stableID), b.id)
        XCTAssertNil(restored?.ownerID(for: chartA1.stableID))
    }

    func testZiweiStableIDDeterministic() {
        let a = personA()
        let b = personB()
        let chartA1 = ziweiChart(for: a)
        let chartA2 = ziweiChart(for: a)
        XCTAssertEqual(chartA1.stableID, chartA2.stableID)
        let chartB = ziweiChart(for: b)
        XCTAssertNotEqual(chartA1.stableID, chartB.stableID)
    }

    // MARK: - 尊享幸运数字/颜色单一权威

    func testLuckySingleAuthority() {
        let person = personA()
        let chart = baziChart(for: person)
        let items = InterpretEngine.interpret(chart: chart)
        let conclusion = items.first(where: { $0.title == "幸运颜色与数字" })?.conclusion ?? ""
        XCTAssertFalse(conclusion.isEmpty)
        let lucky = InterpretEngine.luckyNumbersColors(items: items, chart: chart)
        XCTAssertTrue(lucky.isVerified)
        XCTAssertEqual(lucky.text, conclusion)
        XCTAssertFalse(lucky.numbers.isEmpty)
        XCTAssertFalse(lucky.colors.isEmpty)
        XCTAssertFalse(lucky.numbersList.isEmpty)
        // 模板链（快照）与原生链（同一函数）同值。
        let snapshot = PosterDynamicSnapshot.bazi(person: person, chart: chart, premium: true)
        XCTAssertEqual(snapshot.lucky?.text, lucky.text)
        XCTAssertEqual(snapshot.lucky?.numbers, lucky.numbers)
        XCTAssertEqual(snapshot.lucky?.colors, lucky.colors)
        XCTAssertEqual(snapshot.lucky?.numbersList, lucky.numbersList)
        XCTAssertEqual(snapshot.lucky?.sourceKind, lucky.sourceKind)
        // 快照深读段的幸运字段与权威同值。
        let deep = snapshot.sections.first(where: { $0.id == "deep" })
        let luckyField = deep?.fields.first(where: { $0.id == "interpret.lucky" })
        XCTAssertEqual(luckyField?.value, lucky.text)
    }

    func testLuckyUnverifiedReturnsEmpty() {
        // 空 items（无“幸运颜色与数字”条）时解析失败，isVerified 为 false；
        // 调用方须省略模块并提示“来源待核对”，不得静默回落静态映射。
        let person = personA()
        let chart = baziChart(for: person)
        let lucky = InterpretEngine.luckyNumbersColors(items: [], chart: chart)
        XCTAssertFalse(lucky.isVerified)
        XCTAssertTrue(lucky.numbers.isEmpty)
        XCTAssertTrue(lucky.numbersList.isEmpty)
    }

    // MARK: - 异步导出隔离（快速切换 / 并发导出）

    func testExportTaskIsolation() {
        let a = personA()
        let b = personB()
        let recordIDs = ["PalmRecord:11111111-1111-1111-1111-111111111111"]
        let versions = ["storeSchema": "1"]
        let task = PosterExportTask(personID: a.id, recordIDs: recordIDs, versions: versions, createdAt: Date())
        XCTAssertTrue(task.matches(personID: a.id, recordIDs: recordIDs, versions: versions))
        // 换人：不匹配，回调须丢弃。
        XCTAssertFalse(task.matches(personID: b.id, recordIDs: recordIDs, versions: versions))
        // 换记录：不匹配。
        XCTAssertFalse(task.matches(personID: a.id, recordIDs: ["PalmRecord:22222222-2222-2222-2222-222222222222"], versions: versions))
        // 版本变了：不匹配。
        XCTAssertFalse(task.matches(personID: a.id, recordIDs: recordIDs, versions: ["storeSchema": "2"]))
        // 人物变空：不匹配。
        XCTAssertFalse(task.matches(personID: nil, recordIDs: recordIDs, versions: versions))
    }

    // MARK: - 八字快照 3 个新段与 5 字段

    func testBaziSnapshotHasThreeNewSections() {
        let person = personA()
        let chart = baziChart(for: person)
        let snapshot = PosterDynamicSnapshot.bazi(person: person, chart: chart, premium: false)
        let sectionIDs = snapshot.sections.map { $0.id }
        // 十神看点（interpret 第 4 条总纲）已进原局解释段。
        let reading = snapshot.sections.first(where: { $0.id == "reading" })
        XCTAssertNotNil(reading?.fields.first(where: { $0.id == "interpret.shishen" }))
        // 排盘收据段（lunarText/节气/旬空）。
        XCTAssertTrue(sectionIDs.contains("receipt"))
        let receipt = snapshot.sections.first(where: { $0.id == "receipt" })
        XCTAssertNotNil(receipt?.fields.first(where: { $0.id == "receipt.lunar" }))
        XCTAssertNotNil(receipt?.fields.first(where: { $0.id == "receipt.prevJieQi" }))
        XCTAssertNotNil(receipt?.fields.first(where: { $0.id == "receipt.nextJieQi" }))
        XCTAssertNotNil(receipt?.fields.first(where: { $0.id == "receipt.xunKong" }))
        // 细盘段（日主/命宫/身宫/纳音/四干十神）。
        XCTAssertTrue(sectionIDs.contains("detail"))
        let detail = snapshot.sections.first(where: { $0.id == "detail" })
        XCTAssertNotNil(detail?.fields.first(where: { $0.id == "detail.rizhu" }))
        XCTAssertNotNil(detail?.fields.first(where: { $0.id == "detail.mingGong" }))
        XCTAssertNotNil(detail?.fields.first(where: { $0.id == "detail.shenGong" }))
        XCTAssertNotNil(detail?.fields.first(where: { $0.id == "detail.naYin" }))
        XCTAssertNotNil(detail?.fields.first(where: { $0.id == "detail.stemShiShen" }))
    }

    func testSnapshotFiveFieldsPresent() {
        let person = personA()
        let chart = baziChart(for: person)
        let before = Date()
        let snapshot = PosterDynamicSnapshot.bazi(person: person, chart: chart, premium: false)
        let after = Date()
        XCTAssertTrue(snapshot.generatedAt >= before && snapshot.generatedAt <= after)
        XCTAssertTrue(snapshot.sourceRecordIDs.contains("Person:\(person.id.uuidString)"))
        XCTAssertFalse(snapshot.sourceRecordIDs.isEmpty)
        XCTAssertEqual(snapshot.sourceVersions["interpret"], "30条")
        XCTAssertFalse(snapshot.sourceVersions["baziSect"]?.isEmpty ?? true)
        // 八字为矢量渲染，无图片资产；归属完整，无缺失字段。
        XCTAssertTrue(snapshot.imageAssets.isEmpty)
        XCTAssertTrue(snapshot.missingFields.isEmpty)
        XCTAssertTrue(snapshot.canArchive)
    }

    // MARK: - 手相快照图片资产

    func testPalmSnapshotImageAsset() {
        let person = personA()
        var record = PalmRecord(personID: person.id, personName: person.name, kind: "手相",
                                summary: "测试摘要", linesFlat: [])
        record.photoFile = "test-photo.jpg"
        let snapshot = PosterDynamicSnapshot.palm(record: record, ownerID: person.id)
        XCTAssertEqual(snapshot.ownerID, person.id)
        XCTAssertTrue(snapshot.canArchive)
        XCTAssertEqual(snapshot.imageAssets.count, 1)
        XCTAssertEqual(snapshot.imageAssets.first?.sourcePath, "PalmPhotos/test-photo.jpg")
        // checksum 导出时算，快照里只记来源与许可，不只存易失路径。
        XCTAssertNil(snapshot.imageAssets.first?.checksum)
        XCTAssertTrue(snapshot.missingFields.isEmpty)
        // 无照片时记 optional 缺失，但不禁导出。
        let noPhoto = PalmRecord(personID: person.id, personName: person.name, kind: "手相",
                                 summary: "测试摘要", linesFlat: [])
        let snap2 = PosterDynamicSnapshot.palm(record: noPhoto, ownerID: person.id)
        XCTAssertTrue(snap2.imageAssets.isEmpty)
        XCTAssertTrue(snap2.missingFields.contains { $0.id == "photo" && !$0.blocking })
        XCTAssertTrue(snap2.canArchive)
    }
}
