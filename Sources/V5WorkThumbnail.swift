import SwiftUI
import ImageIO
import UIKit

/// Reads the saved work itself. No template, generated cover, or icon is presented as a preview.
struct V5WorkThumbnail: View {
    let url: URL
    let modifiedAt: Date
    @State private var phase: Phase = .loading
    @State private var attempt = 0
    private enum Phase { case loading, ready(UIImage), unavailable(String) }
    private struct Request: Hashable { let url: URL; let modifiedAt: Date; let attempt: Int }
    var body: some View {
        ZStack {
            V5Palette.color(V5Palette.current.surface)
            switch phase {
            case .loading:
                ProgressView("读取作品").font(.caption)
            case .ready(let image):
                Image(uiImage: image).resizable().scaledToFit().accessibilityHidden(true)
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
private actor V5WorkThumbnailStore {
    static let shared = V5WorkThumbnailStore()
    private struct Cached { let image: UIImage; let bytes: Int }
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
    func image(for url: URL) throws -> UIImage {
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
            return hit.image
        }
        let image: UIImage = try autoreleasepool {
            switch url.pathExtension.lowercased() {
            case "pdf": return try pdfThumbnail(url)
            case "png": return try imageThumbnail(url)
            default: throw Failure(message: "此格式暂不支持缩略图")
            }
        }
        try Task.checkCancellation()
        let bytes = (image.cgImage?.bytesPerRow ?? 0) * (image.cgImage?.height ?? 0)
        if bytes > 0, bytes <= byteLimit {
            while retainedBytes + bytes > byteLimit || order.count >= countLimit {
                guard let oldest = order.first else { break }
                order.removeFirst()
                if let evicted = cache.removeValue(forKey: oldest) { retainedBytes -= evicted.bytes }
            }
            cache[key] = Cached(image: image, bytes: bytes)
            order.append(key); retainedBytes += bytes
        }
        return image
    }
    private func imageThumbnail(_ url: URL) throws -> UIImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maximumPixels,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { throw Failure(message: "图片损坏或暂时无法解码") }
        return UIImage(cgImage: thumbnail)
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
