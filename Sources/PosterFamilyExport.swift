import SwiftUI
import UIKit
import ImageIO
import UniformTypeIdentifiers

/// Private-family export: never uses concept JPGs or placeholder example text.
/// Export is deliberately gated by the immutable owner and source snapshot.
@MainActor
enum PosterFamilyExport {
    enum Failure: LocalizedError {
        case unverifiedOwner, renderingFailed
        var errorDescription: String? {
            switch self {
            case .unverifiedOwner: return "当前报告缺少可信人物归属或数据来源，禁止导出。"
            case .renderingFailed: return "海报渲染失败，请重试。"
            }
        }
    }

    static func image(snapshot: PosterDynamicSnapshot) throws -> URL {
        guard snapshot.canArchive, snapshot.ownerID != nil else { throw Failure.unverifiedOwner }
        let width: CGFloat = 1080
        let content = PosterFamilyExportCanvas(snapshot: snapshot)
            .frame(width: width, alignment: .topLeading)
            .fixedSize(horizontal: true, vertical: true)
            .frame(minHeight: 1081, alignment: .top)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 1
        // Record the stage and dimensions before attempting PNG compression.
        // Keep all source fields intact: do not truncate report content to hide a render failure.
        guard let image = renderer.uiImage else {
            NSLog("[PosterFamilyExport] ImageRenderer returned nil: kind=%@ sections=%d", snapshot.kind.rawValue, snapshot.sections.count)
            throw Failure.renderingFailed
        }
        NSLog("[PosterFamilyExport] rasterized: kind=%@ points=%.0fx%.0f pixels=%.0fx%.0f sections=%d",
              snapshot.kind.rawValue, image.size.width, image.size.height,
              image.size.width * image.scale, image.size.height * image.scale, snapshot.sections.count)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("kanyu-\(snapshot.kind.rawValue)-\(UUID().uuidString).png")
        // ImageIO writes directly to disk, avoiding UIImage.pngData's large
        // intermediate Data allocation for tall, full-resolution reports.
        // Never downscale or omit sections: export remains a lossless PNG.
        guard let cgImage = image.cgImage,
              let destination = CGImageDestinationCreateWithURL(
                  url as CFURL, UTType.png.identifier as CFString, 1, nil
              ) else {
            NSLog("[PosterFamilyExport] PNG destination unavailable: kind=%@", snapshot.kind.rawValue)
            throw Failure.renderingFailed
        }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: url)
            NSLog("[PosterFamilyExport] ImageIO PNG encoding failed: kind=%@ pixels=%.0fx%.0f",
                  snapshot.kind.rawValue, image.size.width * image.scale, image.size.height * image.scale)
            throw Failure.renderingFailed
        }
        return url
    }
}

/// Original four styles remain unchanged in the concept gallery. This is a
/// first-stage native *data* export, not a claim of visual parity with those JPGs.
private struct PosterFamilyExportCanvas: View {
    let snapshot: PosterDynamicSnapshot
    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            VStack(alignment: .leading, spacing: 14) {
                Text("三术合参").font(.system(size: 32, design: .serif))
                Text(snapshot.kind.title)
                    .font(.system(size: 68, weight: .bold, design: .serif))
                Text(snapshot.displayName)
                    .font(.system(size: 36, weight: .medium, design: .serif))
                Text(snapshot.receipt).font(.system(size: 23))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(50)
            .background(snapshot.kind.ink)
            ForEach(snapshot.sections) { section in
                VStack(alignment: .leading, spacing: 18) {
                    Text(section.title)
                        .font(.system(size: 39, weight: .semibold, design: .serif))
                        .foregroundStyle(snapshot.kind.ink)
                    ForEach(section.fields) { field in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(field.label)
                                .font(.system(size: 27, weight: .bold))
                            Text(field.value)
                                .font(.system(size: 30))
                                .fixedSize(horizontal: false, vertical: true)
                            Text("来源：\(field.source)")
                                .font(.system(size: 20))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(24)
                        .background(.white.opacity(0.85))
                    }
                }
                .padding(32)
            }
            Text(snapshot.caution)
                .font(.system(size: 22))
                .fixedSize(horizontal: false, vertical: true)
            Text("个人与家庭使用 · 数据来自当前人物的实际记录")
                .font(.system(size: 19))
        }
        .foregroundStyle(snapshot.kind.ink)
        .padding(45)
        .frame(width: 1080, alignment: .topLeading)
        .background(snapshot.kind.paper)
    }
}

struct PosterFamilyShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
