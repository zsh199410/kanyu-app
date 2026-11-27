import SwiftUI
import ImageIO
import UIKit

/// Reads the saved work itself. No template, generated cover, or icon is presented as a preview.
struct V5WorkThumbnailBitmap {
    let image: UIImage
    let showsUpperRegion: Bool
}

struct V5WorkThumbnail: View {
    let url: URL
    let modifiedAt: Date
    @State private var phase: Phase = .loading
    @State private var attempt = 0
    private enum Phase { case loading, ready(V5WorkThumbnailBitmap), unavailable(String) }
    private struct Request: Hashable { let url: URL; let modifiedAt: Date; let attempt: Int }
    var body: some View {
        ZStack {
            V5Palette.color(V5Palette.current.surface)
            switch phase {
            case .loading:
                ProgressView("读取作品").font(.caption)
            case .ready(let bitmap):
                ZStack(alignment: .bottomLeading) {
                    Image(uiImage: bitmap.image).resizable().scaledToFit().accessibilityHidden(true)
                    if bitmap.showsUpperRegion {
                        Text("长图上部")
                            .font(.caption.weight(.medium)).padding(.horizontal, 8).padding(.vertical, 5)
                            .background(V5Palette.color(V5Palette.current.surface).opacity(0.96), in: Capsule())
                            .padding(8)
                            .accessibilityLabel("长图仅显示上部，打开预览可查看完整作品")
                    }
                }
            case .unavailable(let message):
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.document").font(.title3).accessibilityHidden(true)
                    Text(message).font(.caption).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    Button("重新读取") { attempt += 1 }.font(.caption).frame(minHeight: V5Metric.target)
                }.padding(10)
            }
        }
        .aspectRatio(0.707, contentMode: .fit)
        .overlay(Rectangle().stroke(V5Palette.color(V5Palette.current.ornament).opacity(0.24), lineWidth: 0.6).allowsHitTesting(false))
        .accessibilityElement(children: .contain)
        .task(id: Request(url: url, modifiedAt: modifiedAt, attempt: attempt)) {
            phase = .loading
            do {
                let image = try await V5WorkThumbnailStore.shared.image(for: url)
                try Task.checkCancellation()
                phase = .ready(image)
            } catch is CancellationError {
                // A disappeared cell releases its image and never publishes stale completion.
            } catch {
                guard !Task.isCancelled else { return }
                phase = .unavailable(error.localizedDescription)
            }
        }
        .onDisappear { phase = .loading }
    }
}

/// Serial off-main rendering bounds concurrent decode work; a strict LRU bounds retained bitmap bytes.
actor V5WorkThumbnailStore {
    static let shared = V5WorkThumbnailStore()
    private struct Cached { let bitmap: V5WorkThumbnailBitmap; let bytes: Int }
    private var cache: [String: Cached] = [:]
    private var order: [String] = []
    private var retainedBytes = 0
    private let byteLimit = 16 * 1_024 * 1_024
    private let countLimit = 16
    private let maximumPixels = 640
    private struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
    func image(for url: URL) throws -> V5WorkThumbnailBitmap {
        try Task.checkCancellation()
        let attributes: [FileAttributeKey: Any]
        do { attributes = try FileManager.default.attributesOfItem(atPath: url.path) }
        catch { throw Failure(message: "文件已不存在或暂时无法访问") }
        guard attributes[.type] as? FileAttributeType == .typeRegular else { throw Failure(message: "无法读取此文件的缩略图") }
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        guard size > 0 else { throw Failure(message: "文件为空，无法生成缩略图") }
        guard size <= 536_870_912 else { throw Failure(message: "文件较大，请使用预览查看原件") }
        let modified = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let key = "\(url.standardizedFileURL.path)|\(size)|\(modified)"
        if let hit = cache[key] {
            order.removeAll { $0 == key }; order.append(key)
            return hit.bitmap
        }
        let bitmap: V5WorkThumbnailBitmap = try autoreleasepool {
            switch url.pathExtension.lowercased() {
            case "pdf": return V5WorkThumbnailBitmap(image: try pdfThumbnail(url), showsUpperRegion: false)
            case "png": return try imageThumbnail(url)
            default: throw Failure(message: "此格式暂不支持缩略图")
            }
        }
        try Task.checkCancellation()
        let bytes = (bitmap.image.cgImage?.bytesPerRow ?? 0) * (bitmap.image.cgImage?.height ?? 0)
        if bytes > 0, bytes <= byteLimit {
            while retainedBytes + bytes > byteLimit || order.count >= countLimit {
                guard let oldest = order.first else { break }
                order.removeFirst()
                if let evicted = cache.removeValue(forKey: oldest) { retainedBytes -= evicted.bytes }
            }
            cache[key] = Cached(bitmap: bitmap, bytes: bytes)
            order.append(key); retainedBytes += bytes
        }
        return bitmap
    }
    private func imageThumbnail(_ url: URL) throws -> V5WorkThumbnailBitmap {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let rawWidth = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let rawHeight = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
              rawWidth.isFinite, rawHeight.isFinite, rawWidth > 0, rawHeight > 0 else {
            throw Failure(message: "图片损坏或暂时无法读取尺寸")
        }
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        let rotated = (5...8).contains(orientation)
        let width = rotated ? rawHeight : rawWidth
        let height = rotated ? rawWidth : rawHeight
        let longImage = height / width > 2
        // Preserve a readable ~360px width for long posters instead of shrinking the entire strip to 640px high.
        // ImageIO downsamples directly; reject extreme aspect ratios before any bitmap decode.
        let reduction = min(1, 360 / width)
        let requestedEdge = ceil(max(width, height) * reduction)
        guard requestedEdge.isFinite, requestedEdge > 0, requestedEdge <= 4_096 else {
            throw Failure(message: "长图尺寸过大，请使用预览查看完整原件")
        }
        try Task.checkCancellation()
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(requestedEdge),
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary) else { throw Failure(message: "图片损坏或暂时无法解码") }
        try Task.checkCancellation()
        guard max(thumbnail.width, thumbnail.height) <= 4_096, thumbnail.width <= 400 else {
            throw Failure(message: "图片尺寸信息不一致，请使用预览查看原件")
        }
        guard longImage else { return V5WorkThumbnailBitmap(image: UIImage(cgImage: thumbnail), showsUpperRegion: false) }
        let cropHeight = min(thumbnail.height, Int(ceil(Double(thumbnail.width) / 0.707)))
        guard let upper = thumbnail.cropping(to: CGRect(x: 0, y: 0, width: CGFloat(thumbnail.width), height: CGFloat(cropHeight))) else {
            throw Failure(message: "无法读取长图上部，请预览完整原件")
        }
        // Materialize the crop into its own small bitmap: CGImage.cropping alone may retain the entire decoded strip.
        let size = CGSize(width: CGFloat(upper.width), height: CGFloat(upper.height))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1; format.opaque = false
        let compact = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            UIImage(cgImage: upper).draw(in: CGRect(origin: .zero, size: size))
        }
        return V5WorkThumbnailBitmap(image: compact, showsUpperRegion: true)
    }
    private func pdfThumbnail(_ url: URL) throws -> UIImage {
        guard let document = CGPDFDocument(url as CFURL), !document.isEncrypted, let page = document.page(at: 1) else {
            throw Failure(message: "文档损坏、受保护或没有可读取页面")
        }
        let box = page.getBoxRect(.cropBox)
        guard box.width.isFinite, box.height.isFinite, box.width > 0, box.height > 0 else { throw Failure(message: "文档页面尺寸无效") }
        let rotated = abs(page.rotationAngle % 180) == 90
        let width = rotated ? box.height : box.width
        let height = rotated ? box.width : box.height
        let scale = CGFloat(maximumPixels) / max(width, height)
        let size = CGSize(width: max(1, ceil(width * scale)), height: max(1, ceil(height * scale)))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1; format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { renderer in
            UIColor.white.setFill(); renderer.fill(CGRect(origin: .zero, size: size))
            let context = renderer.cgContext
            context.translateBy(x: 0, y: size.height); context.scaleBy(x: 1, y: -1)
            context.concatenate(page.getDrawingTransform(.cropBox, rect: CGRect(origin: .zero, size: size), rotate: 0, preserveAspectRatio: true))
            context.drawPDFPage(page)
        }
    }
}
