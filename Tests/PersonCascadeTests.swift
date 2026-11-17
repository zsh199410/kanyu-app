import XCTest
@testable import Kanyu

/// P0-4 级联删除：建一个人＋标记＋手相＋前瞻＋报告，删人后断言四处全清；另一个人的数据原样不动。
/// 全部文件落在注入的临时目录；VerifyStore 标记走 UserDefaults.standard（与生产一致），
/// 只对本测试的 UUID 设标、tearDown 只清这些 UUID 的标记，不动其他数据。
/// 边界：报告的 temp 副本（makePDF 的临时 URL）与归档副本同名时扫描会隐藏 temp 副本，
/// 本文件用不同文件名覆盖两路；手相海报的 -pid 文件名与命书的姓名迁移各测一路。
@MainActor
final class PersonCascadeTests: XCTestCase {
    private var dir: URL!
    private var tempFiles: [URL] = []
    private var testOwnerIDs: [String] = []

    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("PersonCascadeTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        for ownerID in testOwnerIDs { VerifyStore.clearAll(ownerID: ownerID) }
        testOwnerIDs = []
        for url in tempFiles { try? FileManager.default.removeItem(at: url) }
        tempFiles = []
        try? FileManager.default.removeItem(at: dir)
        dir = nil
        super.tearDown()
    }

    private func makePerson(name: String, relation: String = "") -> Person {
        Person(name: name, relation: relation, birthEpoch: 946684800)
    }

    private func uuid32(_ id: UUID) -> String {
        id.uuidString.replacingOccurrences(of: "-", with: "")
    }

    private func writeFile(_ url: URL, content: String = "fake") {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? content.write(to: url, atomically: true, encoding: .utf8)
    }

    func testCascadeDeletesAllFourStores() {
        // 人物 A（删）与 B（留）
        let people = PeopleStore(directory: dir)
        let a = makePerson(name: "QA-A", relation: "本人")
        let b = makePerson(name: "QA-B", relation: "儿子")
        people.upsert(a)
        people.upsert(b)
        let ownerA = "person:\(a.id.uuidString)"
        let ownerB = "person:\(b.id.uuidString)"
        testOwnerIDs = [ownerA, ownerB]

        // ① 回验标记
        VerifyStore.set("item-1", ownerID: ownerA, true)
        VerifyStore.set("item-2", ownerID: ownerA, false)
        VerifyStore.set("item-1", ownerID: ownerB, true)

        // ② 手相记录（含照片文件）
        let palm = PalmRecordStore(directory: dir)
        let recA = PalmRecord(personID: a.id, personName: a.name, kind: "手相", summary: "QA-A 手相")
        let recB = PalmRecord(personID: b.id, personName: b.name, kind: "手相", summary: "QA-B 手相")
        let photoA = dir.appendingPathComponent("PalmPhotos/\(recA.id.uuidString).jpg")
        writeFile(photoA, content: "fake-jpg")
        var recAWithPhoto = recA
        recAWithPhoto.photoFile = "\(recA.id.uuidString).jpg"
        palm.add(recAWithPhoto, image: nil)
        palm.add(recB, image: nil)
        XCTAssertTrue(FileManager.default.fileExists(atPath: photoA.path))

        // ③ 前瞻登记
        let fc = ForecastStore(directory: dir)
        fc.add(ForecastEntry(personID: a.id, personName: a.name, text: "QA-A 断语", targetYear: 2027))
        fc.add(ForecastEntry(personID: b.id, personName: b.name, text: "QA-B 断语", targetYear: 2027))

        // ④ 报告文件：归档手相海报（-pid 归属）＋归档命书（姓名迁移归属）＋临时目录手相海报（-pid 归属）
        let archive = dir.appendingPathComponent("KanyuExports/testdigest", isDirectory: true)
        let posterA = archive.appendingPathComponent("palm-poster-QA-A-pid\(uuid32(a.id)).png")
        let bookA = archive.appendingPathComponent("命书-QA-A-专业-20261113-120000-abcdef123456.pdf")
        let posterB = archive.appendingPathComponent("palm-poster-QA-B-pid\(uuid32(b.id)).png")
        writeFile(posterA)
        writeFile(bookA)
        writeFile(posterB)
        let tempPosterA = FileManager.default.temporaryDirectory.appendingPathComponent("palm-poster-QA-TEMP-\(UUID().uuidString.prefix(8))-pid\(uuid32(a.id)).png")
        writeFile(tempPosterA)
        tempFiles.append(tempPosterA)

        // 删 A
        people.remove(a)

        // 断言：A 的四处全清（用全新实例重读，避开旧实例的内存残留）
        XCTAssertNil(VerifyStore.mark(for: "item-1", ownerID: ownerA))
        XCTAssertNil(VerifyStore.mark(for: "item-2", ownerID: ownerA))
        XCTAssertFalse(FileManager.default.fileExists(atPath: photoA.path))
        let palmAfter = PalmRecordStore(directory: dir)
        XCTAssertTrue(palmAfter.records(for: a).isEmpty)
        let fcAfter = ForecastStore(directory: dir)
        XCTAssertTrue(fcAfter.entries(for: a).isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: posterA.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: bookA.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempPosterA.path))
        XCTAssertFalse(people.people.contains(where: { $0.id == a.id }))

        // 断言：B 的数据原样不动
        XCTAssertEqual(VerifyStore.mark(for: "item-1", ownerID: ownerB), true)
        XCTAssertEqual(palmAfter.records(for: b).count, 1)
        XCTAssertEqual(fcAfter.entries(for: b).count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: posterB.path))
        XCTAssertTrue(people.people.contains(where: { $0.id == b.id }))
    }

    func testCascadeSharedNameKeepsOrphanRecords() {
        let people = PeopleStore(directory: dir)
        let c = makePerson(name: "QA-同名", relation: "本人")
        let d = makePerson(name: "QA-同名", relation: "儿子")
        people.upsert(c)
        people.upsert(d)
        let palm = PalmRecordStore(directory: dir)
        // C 与 D 各一条 UUID 归属记录；另有一条旧姓名键记录（personID 为空，同名歧义 → 孤儿）
        palm.add(PalmRecord(personID: c.id, personName: c.name, kind: "手相", summary: "C 的记录"), image: nil)
        palm.add(PalmRecord(personID: d.id, personName: d.name, kind: "手相", summary: "D 的记录"), image: nil)
        palm.add(PalmRecord(personName: "QA-同名", kind: "手相", summary: "旧姓名键记录"), image: nil)
        let fc = ForecastStore(directory: dir)
        fc.add(ForecastEntry(personID: c.id, personName: c.name, text: "C 的断语", targetYear: 2027))
        fc.add(ForecastEntry(personID: d.id, personName: d.name, text: "D 的断语", targetYear: 2027))
        fc.add(ForecastEntry(personName: "QA-同名", text: "旧姓名键登记", targetYear: 2027))

        people.remove(c)

        // ① 直接读盘（不走 store 初始化，避免迁移干扰）：旧姓名键记录仍在且 personID 仍为空。
        let palmData = try! Data(contentsOf: dir.appendingPathComponent("palm_records.json"))
        let palmOnDisk = try! JSONDecoder().decode([PalmRecord].self, from: palmData)
        XCTAssertEqual(palmOnDisk.count, 2)
        XCTAssertTrue(palmOnDisk.contains { $0.personID == d.id && $0.summary == "D 的记录" })
        XCTAssertTrue(palmOnDisk.contains { $0.personID == nil && $0.summary == "旧姓名键记录" })
        XCTAssertFalse(palmOnDisk.contains { $0.personID == c.id })
        let fcData = try! Data(contentsOf: dir.appendingPathComponent("forecasts.json"))
        let fcOnDisk = try! JSONDecoder().decode([ForecastEntry].self, from: fcData)
        XCTAssertEqual(fcOnDisk.count, 2)
        XCTAssertTrue(fcOnDisk.contains { $0.personID == nil && $0.text == "旧姓名键登记" })
        XCTAssertFalse(fcOnDisk.contains { $0.personID == c.id })

        // ② 再走一次正常读档：删 C 后姓名只剩 D 唯一，迁移会把旧记录挂到 D 名下
        // （姓名迁移的已知局限：删人前歧义的孤儿，删人后可能归到同名幸存者；本测试只记录该行为）。
        let palmAfter = PalmRecordStore(directory: dir)
        XCTAssertEqual(palmAfter.records(for: d).count, 2)
        XCTAssertTrue(palmAfter.records(for: c).isEmpty)
    }
}
