import CryptoKit
import SwiftUI
import XCTest
@testable import Kanyu

/// QA 导出验收正式导出自动化测试（独立 QA 分支 qa/poster-export-acceptance-20261117）。
/// 任务一：四款海报走正式导出流程（PosterRasterizer.render ＋ ReportExportArchive.save，
/// 与生产 sheet 同一条路，不是 --v6-export-qa 的 DEBUG 栅格化），以虚构人物夹具数据导出，
/// 逐份记录来源记录、像素尺寸、SHA256，写分片 manifest 供 design 收割脚本校验。
/// 任务二：缺失态 / 长文本 / 长图分段截图以 XCTAttachment 落 xcresult（进 build/screenshots）。
/// 测试人物为虚构（王小明），不用家人真实信息；手相照片为程序化确定性图片，非真机实拍。
final class PosterFormalExportTests: XCTestCase {
    private func fixturePerson() -> Person { Person(name: "王小明", birthEpoch: 946684800) }
    private func baziChart(for person: Person) -> BaziChart {
        BaziEngine.cachedPaipan(clock: person.birthDate, gender: person.gender,
                                longitude: person.useLongitude ? person.longitude : nil)
    }
    private func ziweiChart(for person: Person) -> ZiweiChart {
        ZiweiEngine.chart(clock: person.birthDate, gender: person.gender,
                          longitude: person.useLongitude ? person.longitude : nil)
    }
    private var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    private var exportsURL: URL { documentsURL.appendingPathComponent("KanyuExports", isDirectory: true) }

    /// 程序化确定性手相照片（暖纸底＋三线示意曲线）。非真机实拍，manifest 会注明。
    private func deterministicPalmPhoto() -> UIImage {
        let size = CGSize(width: 400, height: 500)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            UIColor(red: 0.93, green: 0.88, blue: 0.80, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            UIColor(red: 0.55, green: 0.25, blue: 0.15, alpha: 1).setStroke()
            let path = UIBezierPath()
            path.move(to: CGPoint(x: 40, y: 120))
            path.addCurve(to: CGPoint(x: 360, y: 100), controlPoint1: CGPoint(x: 150, y: 60), controlPoint2: CGPoint(x: 250, y: 160))
            path.move(to: CGPoint(x: 40, y: 220))
            path.addCurve(to: CGPoint(x: 360, y: 200), controlPoint1: CGPoint(x: 150, y: 170), controlPoint2: CGPoint(x: 250, y: 250))
            path.move(to: CGPoint(x: 60, y: 320))
            path.addCurve(to: CGPoint(x: 340, y: 300), controlPoint1: CGPoint(x: 160, y: 280), controlPoint2: CGPoint(x: 260, y: 340))
            path.lineWidth = 3
            path.stroke()
        }
    }

    private struct FormalExportFragment: Codable {
        var kind: String
        var fileName: String
        var sha256: String
        var bytes: Int
        var width: Int
        var height: Int
        var personUUID: String
        var sourceRecordIDs: [String]
        var sourceVersions: [String: String]
        var photoNote: String?
    }

    /// 正式导出公共路径：渲染 → 断言 → 归档 → 附件 → 分片 manifest。
    @MainActor
    private func exportPoster<Content: View>(kind: String, fileName: String, content: Content,
                                             snapshot: PosterDynamicSnapshot, person: Person,
                                             photoNote: String? = nil) throws -> FormalExportFragment {
        let output = try PosterRasterizer.render(content)
        let pngData = output.pngData
        XCTAssertFalse(pngData.isEmpty, kind)
        XCTAssertEqual(Array(pngData.prefix(8)), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A], kind)
        let cgImage = try XCTUnwrap(output.image.cgImage, kind)
        XCTAssertEqual(cgImage.width, 1080, kind)
        XCTAssertGreaterThan(cgImage.height, cgImage.width, kind)
        // 正式导出门禁：快照可归档（归属无歧义、无 blocking 缺失）。
        XCTAssertTrue(snapshot.canArchive, kind)
        let url = try ReportExportArchive.save(pngData, fileName: fileName)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), kind)
        let sha256 = SHA256.hash(data: pngData).map { String(format: "%02x", $0) }.joined()
        // 归档目录名即内容 SHA256（与 PDF 同一不变量，收割脚本复核）。
        XCTAssertEqual(url.deletingLastPathComponent().lastPathComponent, sha256, kind)
        let attachment = XCTAttachment(image: output.image)
        attachment.name = "formal-" + kind
        attachment.lifetime = .keepAlways
        add(attachment)
        let fragment = FormalExportFragment(kind: kind, fileName: fileName, sha256: sha256,
                                            bytes: pngData.count, width: cgImage.width, height: cgImage.height,
                                            personUUID: person.id.uuidString,
                                            sourceRecordIDs: snapshot.sourceRecordIDs,
                                            sourceVersions: snapshot.sourceVersions,
                                            photoNote: photoNote)
        try FileManager.default.createDirectory(at: exportsURL, withIntermediateDirectories: true)
        let fragmentURL = exportsURL.appendingPathComponent("formal-export-\(kind).json")
        try JSONEncoder().encode(fragment).write(to: fragmentURL, options: .atomic)
        return fragment
    }

    // MARK: - 任务一：四款正式导出

    @MainActor
    func testFormalExportBazi() throws {
        let person = fixturePerson()
        let chart = baziChart(for: person)
        let snapshot = PosterDynamicSnapshot.bazi(person: person, chart: chart, premium: false)
        let fragment = try exportPoster(kind: "bazi", fileName: "formal-export-bazi.png",
                                        content: PosterView(chart: chart, name: person.name, style: .songQingdai)
                                            .environment(\.colorScheme, .light)
                                            .environment(\.dynamicTypeSize, .large),
                                        snapshot: snapshot, person: person)
        XCTAssertTrue(fragment.sourceRecordIDs.contains("Person:\(person.id.uuidString)"))
        XCTAssertEqual(fragment.sourceVersions["interpret"], "30条")
    }

    @MainActor
    func testFormalExportPremium() throws {
        let person = fixturePerson()
        let chart = baziChart(for: person)
        let snapshot = PosterDynamicSnapshot.bazi(person: person, chart: chart, premium: true)
        // 尊享须有独立图：YucedanPosterLayout 经 PosterView(style: .yuceDan) 渲染。
        let fragment = try exportPoster(kind: "premium", fileName: "formal-export-premium.png",
                                        content: PosterView(chart: chart, name: person.name, style: .yuceDan)
                                            .environment(\.colorScheme, .light)
                                            .environment(\.dynamicTypeSize, .large),
                                        snapshot: snapshot, person: person)
        XCTAssertNotNil(snapshot.lucky)
        XCTAssertTrue(snapshot.lucky?.isVerified ?? false)
        XCTAssertTrue(fragment.sourceRecordIDs.contains("Person:\(person.id.uuidString)"))
    }

    @MainActor
    func testFormalExportZiwei() throws {
        let person = fixturePerson()
        let chart = ziweiChart(for: person)
        let snapshot = PosterDynamicSnapshot.ziwei(chart: chart, name: person.name, ownerIDs: [person.id])
        let fragment = try exportPoster(kind: "ziwei", fileName: "formal-export-ziwei.png",
                                        content: ZiweiPosterView(chart: chart, name: person.name, style: .songQingdai)
                                            .environment(\.colorScheme, .light)
                                            .environment(\.dynamicTypeSize, .large),
                                        snapshot: snapshot, person: person)
        XCTAssertTrue(fragment.sourceRecordIDs.contains("ZiweiChart:\(chart.stableID)"))
    }

    @MainActor
    func testFormalExportPalm() throws {
        let person = fixturePerson()
        let photo = deterministicPalmPhoto()
        // 照片落盘：PalmPhotos/<recordID>.jpg，使快照 imageAssets 的 sourcePath 真实存在。
        var record = PalmRecord(personID: person.id, personName: person.name, kind: "手相",
                                createdEpoch: 946684800, summary: "测试摘要",
                                linesFlat: [0.2, 0.3, 0.4, 0.35, 0.6, 0.3, 0.3, 0.5, 0.5, 0.55, 0.7, 0.5,
                                            0.25, 0.65, 0.45, 0.7, 0.65, 0.65, 0.35, 0.8, 0.55, 0.85, 0.75, 0.8])
        let photoDir = documentsURL.appendingPathComponent("PalmPhotos", isDirectory: true)
        try FileManager.default.createDirectory(at: photoDir, withIntermediateDirectories: true)
        let photoFile = "\(record.id.uuidString).jpg"
        guard let jpg = photo.jpegData(compressionQuality: 0.85) else {
            XCTFail("程序化照片编码失败")
            return
        }
        try jpg.write(to: photoDir.appendingPathComponent(photoFile), options: .atomic)
        record.photoFile = photoFile
        let snapshot = PosterDynamicSnapshot.palm(record: record, ownerID: person.id)
        XCTAssertEqual(snapshot.imageAssets.first?.sourcePath, "PalmPhotos/\(photoFile)")
        let fragment = try exportPoster(kind: "palm", fileName: "formal-export-palm.png",
                                        content: PalmPosterView(record: record, image: photo)
                                            .environment(\.colorScheme, .light)
                                            .environment(\.dynamicTypeSize, .large),
                                        snapshot: snapshot, person: person,
                                        photoNote: "程序化确定性照片，非真机实拍")
        XCTAssertTrue(fragment.sourceRecordIDs.contains("PalmRecord:\(record.id.uuidString)"))
        XCTAssertTrue(fragment.sourceRecordIDs.contains("Person:\(person.id.uuidString)"))
    }

    // MARK: - 任务二：缺失态 / 长文本 / 长图分段附件

    @MainActor
    func testMissingStateAttachments() throws {
        let person = fixturePerson()
        // 孤儿手相快照：缺失态横幅“缺少稳定身份：禁止正式导出”。
        let orphanRecord = PalmRecord(personID: nil, personName: person.name, kind: "手相",
                                      summary: "测试摘要", linesFlat: [])
        let orphanSnapshot = PosterDynamicSnapshot.palm(record: orphanRecord, ownerID: nil)
        XCTAssertFalse(orphanSnapshot.canArchive)
        let orphanOutput = try PosterRasterizer.render(PosterDynamicTemplateView(snapshot: orphanSnapshot))
        XCTAssertFalse(orphanOutput.pngData.isEmpty)
        let orphanShot = XCTAttachment(image: orphanOutput.image)
        orphanShot.name = "missing-orphan-palm-template"
        orphanShot.lifetime = .keepAlways
        add(orphanShot)
        // 未关联紫微快照：同样禁正式导出。
        let chart = ziweiChart(for: person)
        let unlinkedSnapshot = PosterDynamicSnapshot.ziwei(chart: chart, name: person.name, ownerIDs: [])
        XCTAssertFalse(unlinkedSnapshot.canArchive)
        XCTAssertTrue(unlinkedSnapshot.missingFields.contains { $0.id == "ownerID" && $0.blocking })
        let unlinkedOutput = try PosterRasterizer.render(PosterDynamicTemplateView(snapshot: unlinkedSnapshot))
        let unlinkedShot = XCTAttachment(image: unlinkedOutput.image)
        unlinkedShot.name = "missing-unlinked-ziwei-template"
        unlinkedShot.lifetime = .keepAlways
        add(unlinkedShot)
    }

    @MainActor
    func testLongTextAttachments() throws {
        let person = fixturePerson()
        let bazi = baziChart(for: person)
        let ziwei = ziweiChart(for: person)
        // 合参长文本：20 段重复长文本行（与 PosterLayoutTests 同口径）。
        let longLines = [String(repeating: "长文本换行样例。", count: 20)]
        let hecanOutput = try PosterRasterizer.render(
            HeCanPosterView(bazi: bazi, ziwei: ziwei, name: person.name, palmLines: longLines, style: .songQingdai)
                .environment(\.colorScheme, .light)
                .environment(\.dynamicTypeSize, .large))
        let hecanImage = try XCTUnwrap(hecanOutput.image.cgImage)
        XCTAssertEqual(hecanImage.width, 1080)
        let hecanShot = XCTAttachment(image: hecanOutput.image)
        hecanShot.name = "longtext-hecan"
        hecanShot.lifetime = .keepAlways
        add(hecanShot)
        // 尊享长文本：30 条解读全文。
        let premiumOutput = try PosterRasterizer.render(
            PosterView(chart: bazi, name: person.name, style: .yuceDan)
                .environment(\.colorScheme, .light)
                .environment(\.dynamicTypeSize, .large))
        let premiumShot = XCTAttachment(image: premiumOutput.image)
        premiumShot.name = "longtext-premium"
        premiumShot.lifetime = .keepAlways
        add(premiumShot)
    }

    @MainActor
    func testLongPosterSegments() throws {
        let person = fixturePerson()
        let chart = baziChart(for: person)
        let output = try PosterRasterizer.render(
            PosterView(chart: chart, name: person.name, style: .songQingdai)
                .environment(\.colorScheme, .light)
                .environment(\.dynamicTypeSize, .large))
        let cgImage = try XCTUnwrap(output.image.cgImage)
        XCTAssertEqual(cgImage.width, 1080)
        XCTAssertGreaterThan(cgImage.height, cgImage.width)
        let fullShot = XCTAttachment(image: output.image)
        fullShot.name = "multipage-bazi-full"
        fullShot.lifetime = .keepAlways
        add(fullShot)
        // 同一长图的上/下段（多页证据是 report-samples 里的多页 PDF，此处只分段呈现长图）。
        let half = cgImage.height / 2
        if let top = cgImage.cropping(to: CGRect(x: 0, y: 0, width: cgImage.width, height: half)) {
            let topShot = XCTAttachment(image: UIImage(cgImage: top, scale: 2, orientation: .up))
            topShot.name = "multipage-bazi-top"
            topShot.lifetime = .keepAlways
            add(topShot)
        } else {
            XCTFail("长图上段裁剪失败")
        }
        if let bottom = cgImage.cropping(to: CGRect(x: 0, y: half, width: cgImage.width, height: cgImage.height - half)) {
            let bottomShot = XCTAttachment(image: UIImage(cgImage: bottom, scale: 2, orientation: .up))
            bottomShot.name = "multipage-bazi-bottom"
            bottomShot.lifetime = .keepAlways
            add(bottomShot)
        } else {
            XCTFail("长图下段裁剪失败")
        }
    }
}
