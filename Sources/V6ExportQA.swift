import SwiftUI

/// Normal launches and device Release builds keep the existing root view.
struct V6ExportQAHost: ViewModifier {
    func body(content: Content) -> some View {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--v6-export-qa") {
            V6ExportQARunnerView()
        } else {
            content
        }
#else
        content
#endif
    }
}

#if DEBUG
import UIKit
import CryptoKit

private struct V6ExportQARunnerView: View {
    @State private var started = false
    var body: some View {
        Text("海报渲染 QA · 独立样例，不写入人物档案")
            .task {
                guard !started else { return }
                started = true
                await V6ExportQA.run()
            }
    }
}

@MainActor private enum V6ExportQA {
    struct Sample: Codable {
        let file: String
        let width: Int
        let height: Int
        let sha256: String
    }
    struct Manifest: Codable {
        let status: String
        let scope: String
        let samples: [Sample]
        let errors: [String]
    }
    struct ExpectedReport: Codable {
        let tier: String
        let contentHash: String
        let lines: [String]
    }
    enum Failure: Error { case imageUnavailable, invalidDimensions(Int, Int), unreadablePNG(Int, Int, Int), orientationMismatch(Int, Int, Int, Int) }

    static func run() async {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("V6ExportQA", isDirectory: true)
        var samples: [Sample] = []
        var errors: [String] = []
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            await Task.yield()
            try validateOrientation(in: directory)
            let birth = Date(timeIntervalSince1970: 946684800)
            let bazi = BaziEngine.cachedPaipan(clock: birth, gender: "M", longitude: nil)
            let ziwei = ZiweiEngine.cachedChart(clock: birth, gender: "M", longitude: nil)
            let name = "QA样例·长姓名排版复核·不是用户档案"
            for style in PosterStyle.allCases {
                await Task.yield()
                do {
                    samples.append(try render(AnyView(PosterView(chart: bazi, name: name, style: style)),
                        name: "bazi\(style.fileSuffix)", style: style, directory: directory))
                } catch { errors.append("bazi\(style.fileSuffix): \(error)") }
                if style != .yuceDan {
                    await Task.yield()
                    do {
                        samples.append(try render(AnyView(ZiweiPosterView(chart: ziwei, name: name, style: style)),
                            name: "ziwei\(style.fileSuffix)", style: style, directory: directory))
                    } catch { errors.append("ziwei\(style.fileSuffix): \(error)") }
                    await Task.yield()
                    do {
                        samples.append(try render(AnyView(HeCanPosterView(bazi: bazi, ziwei: ziwei,
                            name: name, palmLines: [String(repeating: "QA长文换行样例。", count: 30), "QA第二条测量记录：用于核验多条摘要完整保留。", "QA第三条测量记录：不能因为条目数量而被省略。"], style: style)),
                            name: "hecan\(style.fileSuffix)", style: style, directory: directory))
                    } catch { errors.append("hecan\(style.fileSuffix): \(error)") }
                }
            }
            await Task.yield()
            let record = PalmRecord(personName: name, kind: "手相", createdEpoch: 946684800,
                summary: "QA渲染样例，无真人照片，不代表测量结论。")
            do {
                samples.append(try render(AnyView(PalmPosterView(record: record, image: nil)),
                    name: "palm-empty-photo", style: .songQingdai, directory: directory))
            } catch { errors.append("palm: \(error)") }
            try saveExpectedReportText(to: directory)
        } catch { errors.append("setup: \(error)") }
        let manifest = Manifest(status: errors.isEmpty && samples.count == 11 ? "success" : "failure",
            scope: "Debug-only production rasterizer samples and full report drawing inputs for existing XCTest fixtures; not export-sheet, photo permission, sensor, or physical-device performance tests",
            samples: samples, errors: errors)
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(manifest).write(to: directory.appendingPathComponent("manifest.json"), options: .atomic)
        } catch { print("V6 export QA manifest write failed: \(error)") }
    }

    static func validateOrientation(in directory: URL) throws {
        let marker = VStack(spacing: 0) {
            Color(red: 1, green: 0, blue: 0).frame(width: 8, height: 8)
            Color(red: 0, green: 0, blue: 1).frame(width: 8, height: 8)
        }.fixedSize()
        let output = try PosterRasterizer.render(marker, scale: 1)
        guard let cg = output.image.cgImage, cg.width == 8, cg.height == 16,
              let data = cg.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else {
            throw Failure.imageUnavailable
        }
        let bottom = (cg.height - 1) * cg.bytesPerRow
        guard bytes[0] > 240, bytes[2] < 16, bytes[bottom] < 16, bytes[bottom + 2] > 240 else {
            try output.pngData.write(to: directory.appendingPathComponent("orientation-probe-failure.png"), options: .atomic)
            throw Failure.orientationMismatch(Int(bytes[0]), Int(bytes[2]), Int(bytes[bottom]), Int(bytes[bottom + 2]))
        }
    }

    static func saveExpectedReportText(to directory: URL) throws {
        let fixtures: [(ReportTier, String)] = [(.concise, "张/三\\测试:报告"),
            (.professional, "目录回归"), (.complete, "目录回归")]
        let reports = fixtures.map { fixture in
            let (tier, name) = fixture
            let person = Person(name: name, birthEpoch: 946684800)
            let lines = ReportBuilder.lines(for: person, tier: tier)
            return ExpectedReport(tier: tier.rawValue,
                contentHash: ReportBuilder.contentHash(lines: lines, tier: tier), lines: lines)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(reports).write(to: directory.appendingPathComponent("report-expected-text.json"), options: .atomic)
    }

    static func render(_ view: AnyView, name: String, style: PosterStyle, directory: URL) throws -> Sample {
        try autoreleasepool {
            let scheme: ColorScheme = style == .xuanye ? .dark : .light
            let output = try PosterRasterizer.render(view.environment(\.colorScheme, scheme)
                .environment(\.dynamicTypeSize, .large))
            guard let cg = output.image.cgImage else { throw Failure.imageUnavailable }
            let data = output.pngData
            let file = name + ".png"
            // Keep the actual failed image for review, without counting it as a valid sample.
            try data.write(to: directory.appendingPathComponent(file), options: .atomic)
            guard UIImage(data: data)?.cgImage != nil else {
                throw Failure.unreadablePNG(cg.width, cg.height, data.count)
            }
            guard cg.width == 1080, cg.height > cg.width else {
                throw Failure.invalidDimensions(cg.width, cg.height)
            }
            return Sample(file: file, width: cg.width, height: cg.height,
                sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())
        }
    }
}
#endif
