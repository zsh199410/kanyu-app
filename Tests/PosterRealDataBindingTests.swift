import SwiftUI
import XCTest
@testable import Kanyu

/// 条件 #5：海报文件名人物 UUID 绑定＋手相真实照片渲染＋八字海报数据绑定。
/// 补 PosterLayoutTests 的缺口：只有固定样例尺寸断言，无手相测试、无真实 Person 绑定测试。
/// 注意：parsePosterName 返回元组（Swift 元组不遵循 Equatable），一律逐字段断言，禁止 XCTAssertEqual 直接比元组。
final class PosterRealDataBindingTests: XCTestCase {

    // MARK: - 1. pidSuffix：姓名 → UUID 解析

    func testPidSuffixResolvesUniquePerson() {
        let person = Person(name: "王小明", birthEpoch: 946684800)
        XCTAssertEqual(Person.uniqueID(forName: "王小明", in: [person]), person.id)
        let suffix = PosterExportNaming.pidSuffix(personID: person.id)
        XCTAssertEqual(suffix, "-pid" + person.id.uuidString.replacingOccurrences(of: "-", with: ""))
        XCTAssertEqual(suffix.count, 36)
    }

    func testPidSuffixEmptyForAmbiguousOrMissingName() {
        let a = Person(name: "王小明", birthEpoch: 946684800)
        let b = Person(name: "王小明", birthEpoch: 978307200)
        XCTAssertNil(Person.uniqueID(forName: "王小明", in: [a, b]))
        XCTAssertNil(Person.uniqueID(forName: "李四", in: [a]))
        XCTAssertNil(Person.uniqueID(forName: "", in: [a]))
        XCTAssertEqual(PosterExportNaming.pidSuffix(personID: nil), "")
    }

    // MARK: - 2. 三款海报文件名往返（姓名＋UUID）

    /// 按生产 Sheet 同款公式构造文件名（前缀＋exportName＋款式＋pid＋.png）。
    private func posterFileName(prefix: String, name: String, style: PosterStyle, personID: UUID?) -> String {
        let pid = PosterExportNaming.pidSuffix(personID: personID)
        return "\(prefix)\(ReportBuilder.exportName(name.isEmpty ? "chart" : name))\(style.fileSuffix)\(pid).png"
    }

    /// 按报告中心同款口径剥前缀与扩展名，再走 ReportHistory.parsePosterName 解析。
    private func parsedPosterName(_ file: String, prefix: String) -> (name: String, personID: UUID?) {
        let noExt = file.hasSuffix(".png") ? String(file.dropLast(4)) : file
        return ReportHistory.parsePosterName(String(noExt.dropFirst(prefix.count)))
    }

    func testPosterFilenamesRoundTripWithPersonID() {
        let person = Person(name: "李四", birthEpoch: 946684800)
        let resolved = Person.uniqueID(forName: "李四", in: [person])
        XCTAssertEqual(resolved, person.id)
        for prefix in ["poster-", "ziwei-poster-", "hecan-poster-"] {
            let file = posterFileName(prefix: prefix, name: person.name, style: .songQingdai, personID: resolved)
            let parsed = parsedPosterName(file, prefix: prefix)
            XCTAssertEqual(parsed.name, "李四", prefix)
            XCTAssertEqual(parsed.personID, person.id, prefix)
        }
    }

    func testSameNameTwoPersonsGetDifferentFilenames() {
        let a = Person(name: "王小明", birthEpoch: 946684800)
        let b = Person(name: "王小明", birthEpoch: 978307200)
        XCTAssertNotEqual(a.id, b.id)
        // 同名歧义时姓名解析返回 nil（宁可孤儿不串人）；画廊等显式入口传 p.id 直挂。
        XCTAssertNil(Person.uniqueID(forName: "王小明", in: [a, b]))
        let fileA = posterFileName(prefix: "poster-", name: a.name, style: .songQingdai, personID: a.id)
        let fileB = posterFileName(prefix: "poster-", name: b.name, style: .songQingdai, personID: b.id)
        XCTAssertNotEqual(fileA, fileB)
        let parsedA = parsedPosterName(fileA, prefix: "poster-")
        XCTAssertEqual(parsedA.name, "王小明")
        XCTAssertEqual(parsedA.personID, a.id)
        let parsedB = parsedPosterName(fileB, prefix: "poster-")
        XCTAssertEqual(parsedB.name, "王小明")
        XCTAssertEqual(parsedB.personID, b.id)
    }

    func testPosterFilenameWithoutPIDParsesAsOrphan() {
        let file = posterFileName(prefix: "poster-", name: "旧档张三", style: .songQingdai, personID: nil)
        XCTAssertFalse(file.contains("-pid"))
        let parsed = parsedPosterName(file, prefix: "poster-")
        XCTAssertEqual(parsed.name, "旧档张三")
        XCTAssertNil(parsed.personID)
    }

    // MARK: - 3. 手相真实照片渲染（走生产 PosterRasterizer 路径）

    /// 确定性程序化掌纹照片（暖底＋三线示意；不是真机实拍，仅走通 image != nil 分支）。
    private func deterministicPalmPhoto() -> UIImage {
        let size = CGSize(width: 400, height: 500)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            UIColor(red: 0.85, green: 0.72, blue: 0.58, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            UIColor(red: 0.6, green: 0.35, blue: 0.25, alpha: 1).setStroke()
            ctx.cgContext.setLineWidth(3)
            // 感情线／智慧线／生命线三条示意弧线
            ctx.cgContext.move(to: CGPoint(x: 40, y: 150))
            ctx.cgContext.addQuadCurve(to: CGPoint(x: 360, y: 130), control: CGPoint(x: 200, y: 100))
            ctx.cgContext.move(to: CGPoint(x: 50, y: 250))
            ctx.cgContext.addQuadCurve(to: CGPoint(x: 350, y: 220), control: CGPoint(x: 200, y: 180))
            ctx.cgContext.move(to: CGPoint(x: 90, y: 120))
            ctx.cgContext.addQuadCurve(to: CGPoint(x: 200, y: 420), control: CGPoint(x: 60, y: 300))
            ctx.cgContext.strokePath()
        }
    }

    @MainActor
    func testPalmPosterRendersWithRealPhoto() throws {
        let person = Person(name: "王小明", birthEpoch: 946684800)
        let record = PalmRecord(personID: person.id, personName: person.name, kind: "手相",
            summary: "掌型测试", linesFlat: [
                0.1, 0.3, 0.5, 0.26, 0.9, 0.26,
                0.12, 0.5, 0.5, 0.44, 0.88, 0.44,
                0.22, 0.24, 0.5, 0.84, 0.15, 0.6
            ])
        let view = PalmPosterView(record: record, image: deterministicPalmPhoto())
            .environment(\.colorScheme, .light).environment(\.dynamicTypeSize, .large)
        let output = try PosterRasterizer.render(view)
        guard let cg = output.image.cgImage else {
            XCTFail("手相海报渲染无 cgImage")
            return
        }
        XCTAssertEqual(cg.width, 1080)
        XCTAssertGreaterThan(cg.height, cg.width)
        XCTAssertFalse(output.pngData.isEmpty)
    }

    // MARK: - 4. 八字海报确系数据绑定（不同生辰 → 不同 PNG）

    @MainActor
    func testBaziPosterPNGDiffersForDifferentBirthDates() throws {
        let chart1 = BaziEngine.cachedPaipan(clock: Date(timeIntervalSince1970: 946684800), gender: "M", longitude: nil)
        let chart2 = BaziEngine.cachedPaipan(clock: Date(timeIntervalSince1970: 631152000), gender: "M", longitude: nil)
        let out1 = try PosterRasterizer.render(PosterView(chart: chart1, name: "张三").environment(\.colorScheme, .light))
        let out2 = try PosterRasterizer.render(PosterView(chart: chart2, name: "张三").environment(\.colorScheme, .light))
        XCTAssertNotEqual(out1.pngData, out2.pngData)
    }
}
