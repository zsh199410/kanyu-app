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
    enum Failure: Error { case imageUnavailable, invalidDimensions(Int, Int), unreadablePNG }

    static func run() async {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("V6ExportQA", isDirectory: true)
        var samples: [Sample] = []
        var errors: [String] = []
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
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
        } catch { errors.append("setup: \(error)") }
        let manifest = Manifest(status: errors.isEmpty && samples.count == 11 ? "success" : "failure",
            scope: "Debug-only native ImageRenderer samples at fixed export font/theme; not export-sheet, photo permission, sensor, or device performance tests",
            samples: samples, errors: errors)
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(manifest).write(to: directory.appendingPathComponent("manifest.json"), options: .atomic)
        } catch { print("V6 export QA manifest write failed: \(error)") }
    }

    static func render(_ view: AnyView, name: String, style: PosterStyle, directory: URL) throws -> Sample {
        try autoreleasepool {
            let scheme: ColorScheme = style == .xuanye ? .dark : .light
            let renderer = ImageRenderer(content: view.environment(\.colorScheme, scheme)
                .environment(\.dynamicTypeSize, .large))
            renderer.scale = 2
            guard let image = renderer.uiImage, let cg = image.cgImage else { throw Failure.imageUnavailable }
            guard let data = image.pngData(), UIImage(data: data)?.cgImage != nil else { throw Failure.unreadablePNG }
            let file = name + ".png"
            // Keep the actual failed image for review, without counting it as a valid sample.
            try data.write(to: directory.appendingPathComponent(file), options: .atomic)
            guard cg.width == 1080, cg.height > cg.width else {
                throw Failure.invalidDimensions(cg.width, cg.height)
            }
            return Sample(file: file, width: cg.width, height: cg.height,
                sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())
        }
    }
}
#endif
