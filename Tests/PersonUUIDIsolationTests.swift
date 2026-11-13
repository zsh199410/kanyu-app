import XCTest
import UIKit
@testable import Kanyu

/// P0-4 UUID 隔离与旧姓名键迁移：同名不同 ID 的人物，手相／前瞻／报告按 UUID 互不可见；
/// 旧姓名键记录读档时尽力迁移（唯一匹配挂 UUID，歧义／无匹配留孤儿）。
/// 全部文件落在注入的临时目录；报告扫描只断言本测试目录下的文件（忽略系统 temp 里的其他文件）。
/// 边界：详情页「换人」菜单到 setCurrentPerson 的接线只能走 XCUITest，本文件不测。
@MainActor
final class PersonUUIDIsolationTests: XCTestCase {
    private var dir: URL!
    private var tempFiles: [URL] = []

    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("PersonUUIDIsolationTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() {
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

    private func savePeople(_ people: [Person]) {
        let store = PeopleStore(directory: dir)
        for p in people { store.upsert(p) }
    }

    func testSameNameDifferentUUIDIsolation() {
        let c = makePerson(name: "QA-同名", relation: "本人")
        let d = makePerson(name: "QA-同名", relation: "儿子")
        savePeople([c, d])
        let palm = PalmRecordStore(directory: dir)
        palm.add(PalmRecord(personID: c.id, personName: c.name, kind: "手相", summary: "C"), image: nil)
        palm.add(PalmRecord(personID: d.id, personName: d.name, kind: "手相", summary: "D"), image: nil)
        XCTAssertEqual(palm.records(for: c).count, 1)
        XCTAssertEqual(palm.records(for: c).first?.summary, "C")
        XCTAssertEqual(palm.records(for: d).count, 1)
        XCTAssertEqual(palm.records(for: d).first?.summary, "D")
        let fc = ForecastStore(directory: dir)
        fc.add(ForecastEntry(personID: c.id, personName: c.name, text: "C 的断语", targetYear: 2027))
        fc.add(ForecastEntry(personID: d.id, personName: d.name, text: "D 的断语", targetYear: 2027))
        XCTAssertEqual(fc.entries(for: c).count, 1)
        XCTAssertEqual(fc.entries(for: d).count, 1)
        // 旧版按姓名取（records(for: String)）仍会把两人混在一起——这正是改 UUID 键的原因，仅作记录。
        XCTAssertEqual(palm.records(for: "QA-同名").count, 2)
    }

    func testMigrationAttachesUniqueName() {
        let a = makePerson(name: "QA-唯一", relation: "本人")
        savePeople([a])
        // 直接写旧档（personID 为空），模拟 P0-4 之前的姓名键记录。
        let oldPalm = [PalmRecord(personName: "QA-唯一", kind: "手相", summary: "旧手相")]
        let palmData = try! JSONEncoder().encode(oldPalm)
        try! palmData.write(to: dir.appendingPathComponent("palm_records.json"))
        let oldFc = [ForecastEntry(personName: "QA-唯一", text: "旧断语", targetYear: 2027)]
        let fcData = try! JSONEncoder().encode(oldFc)
        try! fcData.write(to: dir.appendingPathComponent("forecasts.json"))
        // 读档即迁移
        let palm = PalmRecordStore(directory: dir)
        XCTAssertEqual(palm.records.count, 1)
        XCTAssertEqual(palm.records.first?.personID, a.id)
        XCTAssertEqual(palm.records(for: a).count, 1)
        let fc = ForecastStore(directory: dir)
        XCTAssertEqual(fc.entries.count, 1)
        XCTAssertEqual(fc.entries.first?.personID, a.id)
        XCTAssertEqual(fc.entries(for: a).count, 1)
        // 迁移已回写到盘上（再读一次仍是挂好的 UUID，幂等）
        let palmData2 = try! Data(contentsOf: dir.appendingPathComponent("palm_records.json"))
        let palmOnDisk = try! JSONDecoder().decode([PalmRecord].self, from: palmData2)
        XCTAssertEqual(palmOnDisk.first?.personID, a.id)
    }

    func testMigrationLeavesAmbiguousOrphan() {
        let c = makePerson(name: "QA-同名", relation: "本人")
        let d = makePerson(name: "QA-同名", relation: "儿子")
        savePeople([c, d])
        let oldPalm = [
            PalmRecord(personName: "QA-同名", kind: "手相", summary: "同名歧义"),
            PalmRecord(personName: "QA-无人", kind: "手相", summary: "查无此人"),
        ]
        let palmData = try! JSONEncoder().encode(oldPalm)
        try! palmData.write(to: dir.appendingPathComponent("palm_records.json"))
        let palm = PalmRecordStore(directory: dir)
        XCTAssertEqual(palm.records.count, 2)
        // 同名两人 → 孤儿（personID 仍为空），不属于任何人
        XCTAssertNil(palm.records.first { $0.summary == "同名歧义" }?.personID)
        XCTAssertTrue(palm.records(for: c).isEmpty)
        XCTAssertTrue(palm.records(for: d).isEmpty)
        // 查无此人 → 孤儿
        XCTAssertNil(palm.records.first { $0.summary == "查无此人" }?.personID)
    }

    func testUniqueIDHelper() {
        let a = makePerson(name: "QA-唯一")
        let c = makePerson(name: "QA-同名")
        let d = makePerson(name: "QA-同名")
        let people = [a, c, d]
        XCTAssertEqual(Person.uniqueID(forName: "QA-唯一", in: people), a.id)
        XCTAssertNil(Person.uniqueID(forName: "QA-同名", in: people))
        XCTAssertNil(Person.uniqueID(forName: "QA-无人", in: people))
        // 该测试未存 people.json，读档返回空
        XCTAssertTrue(Person.loadPeopleForMigration(directory: dir).isEmpty)
    }

    func testPosterNameParsing() {
        let id = UUID()
        let hex = uuid32(id)
        let parsed = ReportHistory.parsePosterName("QA-报告-song-pid\(hex)")
        XCTAssertEqual(parsed.name, "QA-报告")
        XCTAssertEqual(parsed.personID, id)
        let plain = ReportHistory.parsePosterName("QA-报告-song")
        XCTAssertEqual(plain.name, "QA-报告")
        XCTAssertNil(plain.personID)
        // 非法 hex 不认 pid（整段仍当姓名）
        let bad = ReportHistory.parsePosterName("QA-报告-pidzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz")
        XCTAssertEqual(bad.name, "QA-报告-pidzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz")
        XCTAssertNil(bad.personID)
        // stripPersonIDSuffix 直接测
        let stripped = ReportHistory.stripPersonIDSuffix("QA-报告-pid\(hex)")
        XCTAssertEqual(stripped.name, "QA-报告")
        XCTAssertEqual(stripped.personID, id)
    }

    func testReportScanResolution() {
        let a = makePerson(name: "QA-报告", relation: "本人")
        let c = makePerson(name: "QA-同名", relation: "本人")
        let d = makePerson(name: "QA-同名", relation: "儿子")
        savePeople([a, c, d])
        let archive = dir.appendingPathComponent("KanyuExports/testdigest", isDirectory: true)
        let posterPID = archive.appendingPathComponent("palm-poster-QA-报告-pid\(uuid32(a.id)).png")
        let bookName = archive.appendingPathComponent("命书-QA-报告-专业-20261113-120000-abcdef123456.pdf")
        let posterAmbiguous = archive.appendingPathComponent("palm-poster-QA-同名.png")
        let posterNobody = archive.appendingPathComponent("palm-poster-QA-无人.png")
        writeFile(posterPID)
        writeFile(bookName)
        writeFile(posterAmbiguous)
        writeFile(posterNobody)
        let entries = ReportHistory.scan(documents: dir).filter { $0.url.path.hasPrefix(dir.path) }
        XCTAssertEqual(entries.count, 4)
        XCTAssertEqual(entries.first { $0.url == posterPID }?.personID, a.id)
        XCTAssertEqual(entries.first { $0.url == bookName }?.personID, a.id)
        XCTAssertNil(entries.first { $0.url == posterAmbiguous }?.personID)
        XCTAssertNil(entries.first { $0.url == posterNobody }?.personID)
    }

    func testPDFPersonIDMetadata() {
        let id = UUID()
        let format = UIGraphicsPDFRendererFormat()
        // P0-4 修正：Keywords 必须与生产 makePDF 的格式一致（全 ASCII，tier 用 fileCode）。
        // 旧版写了 tier=专业（中文），与生产格式不符，CGPDFStringCopyTextString 读回为 nil。
        format.documentInfo = ["Keywords": "contentHash=abcdef1234567890;tier=professional;engine=v1;personID=\(id.uuidString)"]
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 595, height: 842), format: format)
        let data = renderer.pdfData { ctx in ctx.beginPage() }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("p04-pdf-\(UUID().uuidString).pdf")
        try! data.write(to: url)
        tempFiles.append(url)
        XCTAssertEqual(ReportHistory.pdfPersonID(for: url), id)
        // 无 personID 键的 PDF 返回 nil
        let format2 = UIGraphicsPDFRendererFormat()
        format2.documentInfo = ["Keywords": "contentHash=abcdef1234567890"]
        let data2 = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 595, height: 842), format: format2).pdfData { ctx in ctx.beginPage() }
        let url2 = FileManager.default.temporaryDirectory.appendingPathComponent("p04-pdf-\(UUID().uuidString).pdf")
        try! data2.write(to: url2)
        tempFiles.append(url2)
        XCTAssertNil(ReportHistory.pdfPersonID(for: url2))
    }

    /// P0-4 诊断 v3：v2 已证实原始 PDF 字节里根本没有 /Keywords（写侧问题，非读侧）。
    /// 本轮一次查清渲染器到底写了哪些 documentInfo 键：Title、Author、Subject、Keywords
    /// 各写一个可区分的值，搜原始字节，一条断言同时报四键的有无。
    /// 若仅 Keywords 缺失→该键被单独丢弃；若四键全缺→documentInfo 整段被忽略，须换写法。
    /// 找到根因并修好后，本测试可删。
    func testPDFReaderDiagnostics() {
        let id = UUID()
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            "Title": "diag-title-\(id.uuidString)",
            "Author": "diag-author",
            "Subject": "diag-subject",
            "Keywords": "contentHash=abcdef1234567890;tier=professional;engine=v1;personID=\(id.uuidString)"
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 595, height: 842), format: format)
        let data = renderer.pdfData { ctx in ctx.beginPage() }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("p04-diag-\(UUID().uuidString).pdf")
        try! data.write(to: url)
        tempFiles.append(url)
        let hasTitle = data.range(of: "/Title".data(using: .ascii)!) != nil
        let hasAuthor = data.range(of: "/Author".data(using: .ascii)!) != nil
        let hasSubject = data.range(of: "/Subject".data(using: .ascii)!) != nil
        let hasKW = data.range(of: "/Keywords".data(using: .ascii)!) != nil
        XCTAssertTrue(hasTitle && hasAuthor && hasSubject && hasKW,
                      "diag: info keys in raw bytes: title=\(hasTitle) author=\(hasAuthor) subject=\(hasSubject) keywords=\(hasKW)")
        guard hasKW else { return }
        guard let doc = CGPDFDocument(url as CFURL), let info = doc.info else {
            XCTFail("diag: doc/info nil")
            return
        }
        var value: CGPDFStringRef?
        XCTAssertTrue(CGPDFDictionaryGetString(info, "Keywords", &value), "diag: GetString Keywords false")
        guard let value = value, let text = CGPDFStringCopyTextString(value) as String? else {
            XCTFail("diag: CopyTextString nil")
            return
        }
        XCTAssertTrue(text.contains("personID="), "diag: text missing personID")
        XCTAssertEqual(ReportHistory.pdfPersonID(for: url), id, "diag: pdfPersonID nil but text ok")
    }
}
