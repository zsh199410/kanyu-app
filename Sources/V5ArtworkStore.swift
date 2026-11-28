import Foundation
import ImageIO
import UIKit

/// Decoded pixels, not compressed file sizes, determine the cache budget.
/// All file reads/decode requests use one worker; cache access is short and thread-safe.
final class V5ArtworkStore: @unchecked Sendable {
    static let shared = V5ArtworkStore(byteLimit: 32 * 1024 * 1024)
    private struct Entry { let image: UIImage; let cost: Int; var access: UInt64 }
    private let lock = NSLock()
    private let worker = DispatchQueue(label: "com.kanyu.artwork.decode", qos: .userInitiated)
    private let byteLimit: Int
    private var entries: [String: Entry] = [:]
    private var bytes = 0
    private var clock: UInt64 = 0

    init(byteLimit: Int) { self.byteLimit = max(0, byteLimit) }
    var cachedBytes: Int { lock.lock(); defer { lock.unlock() }; return bytes }
    func removeAll() {
        lock.lock(); defer { lock.unlock() }
        entries.removeAll(); bytes = 0
    }
    private func key(_ url: URL, _ maximumPixelSize: Int) -> String {
        "\(url.standardizedFileURL.path)#\(maximumPixelSize)"
    }
    private func cached(_ key: String) -> UIImage? {
        lock.lock(); defer { lock.unlock() }
        guard var entry = entries[key] else { return nil }
        clock &+= 1; entry.access = clock; entries[key] = entry
        return entry.image
    }
    private func retain(_ image: UIImage, key: String) {
        guard let cg = image.cgImage else { return }
        let cost = cg.bytesPerRow * cg.height
        lock.lock(); defer { lock.unlock() }
        // Oversized export images belong to their caller, never to the UI cache.
        guard cost <= byteLimit else { return }
        if let previous = entries.removeValue(forKey: key) { bytes -= previous.cost }
        while bytes + cost > byteLimit, let oldest = entries.min(by: { $0.value.access < $1.value.access }) {
            bytes -= oldest.value.cost; entries.removeValue(forKey: oldest.key)
        }
        clock &+= 1; entries[key] = Entry(image: image, cost: cost, access: clock); bytes += cost
    }
    /// Synchronous path for export snapshots: no .task/onAppear is required to render art.
    /// UIImage(named:) is deliberately avoided; its process-wide decoded cache is unbounded here.
    func image(at url: URL, maximumPixelSize: Int) -> UIImage? {
        guard (1...8192).contains(maximumPixelSize) else { return nil }
        let key = key(url, maximumPixelSize)
        if let image = cached(key) { return image }
        return worker.sync { load(at: url, maximumPixelSize: maximumPixelSize, key: key) }
    }
    func load(at url: URL, maximumPixelSize: Int) async -> UIImage? {
        guard !Task.isCancelled, (1...8192).contains(maximumPixelSize) else { return nil }
        let key = key(url, maximumPixelSize)
        if let image = cached(key) { return image }
        let image: UIImage? = await withCheckedContinuation { continuation in
            worker.async { [self] in
                continuation.resume(returning: load(at: url, maximumPixelSize: maximumPixelSize, key: key))
            }
        }
        return Task.isCancelled ? nil : image
    }
    private func load(at url: URL, maximumPixelSize: Int, key: String) -> UIImage? {
        if let image = cached(key) { return image }
        return autoreleasepool {
            guard let source = CGImageSourceCreateWithURL(url as CFURL,
                [kCGImageSourceShouldCache: false] as CFDictionary),
                CGImageSourceGetStatus(source) == .statusComplete,
                CGImageSourceGetType(source) as String? == "public.png" else { return nil }
            let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
                kCGImageSourceShouldCacheImmediately: true]
            guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
            let image = UIImage(cgImage: cg, scale: 1, orientation: .up)
            retain(image, key: key)
            return image
        }
    }
}
