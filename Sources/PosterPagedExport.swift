import Foundation
import SwiftUI
import UIKit
import ImageIO
import ZIPFoundation
import CryptoKit

/// Read-only pagination of existing result fields. No value, evidence or date is recalculated.
enum PosterPageLayout {
    struct Cell: Identifiable {
        let id: String
        let sectionTitle: String
        let title: String
        let text: String
        let source: String
        let explanation: String?
    }
    struct Page: Identifiable {
        let id: Int
        let cells: [Cell]
    }
    enum Failure: LocalizedError {
        case noOwner, noContent, tooManyPages
        var errorDescription: String? {
            switch self {
            case .noOwner: return "人物身份没有可靠关联，不能生成私人海报。"
            case .noContent: return "没有可导出的解盘内容。"
            case .tooManyPages: return "报告太长，超出本机安全导出限额，请先使用完整版 PDF。"
            }
        }
    }

    /// Splits on Chinese sentence boundaries where possible. Every character,
    /// punctuation mark and newline is preserved exactly, including whitespace.
    static func exactChunks(_ text: String, limit: Int = 200) -> [String] {
        guard !text.isEmpty else { return [""] }
        let limit = max(32, limit)
        var tail = Array(text)
        var result: [String] = []
        while !tail.isEmpty {
            if tail.count <= limit {
                result.append(String(tail))
                break
            }
            let window = tail.prefix(limit)
            let stops: Set<Character> = ["。", "！", "？", "；", "\n"]
            let preferred = window.enumerated().compactMap { offset, ch -> Int? in
                offset >= limit / 2 && stops.contains(ch) ? offset + 1 : nil
            }.last
            let n = preferred ?? limit
            result.append(String(tail.prefix(n)))
            tail.removeFirst(n)
        }
        return result
    }

    static func paginate(_ snapshot: PosterDynamicSnapshot) throws -> [Page] {
        guard snapshot.ownerID != nil, snapshot.canArchive else { throw Failure.noOwner }
        guard snapshot.sections.contains(where: { !$0.fields.isEmpty }) else { throw Failure.noContent }
        let maxContentHeight: CGFloat = 665
        var pages: [Page] = []
        var current: [Cell] = []
        var used: CGFloat = 0

        func flush() {
            guard !current.isEmpty else { return }
            pages.append(Page(id: pages.count + 1, cells: current))
            current = []
            used = 0
        }

        for section in snapshot.sections {
            for field in section.fields {
                let pieces = exactChunks(field.value)
                // Never silently lose or paraphrase the engine's actual conclusion.
                guard pieces.joined() == field.value else { throw Failure.noContent }
                for (index, text) in pieces.enumerated() {
                    let firstPart = index == 0
                    let headerHeight: CGFloat = current.last?.sectionTitle == section.title ? 0 : 36
                    let estimate = CGFloat(138 + Int(ceil(Double(max(1, text.count)) / 24.0)) * 24)
                        + (firstPart ? 72 : 0) + headerHeight
                    if !current.isEmpty && used + estimate > maxContentHeight {
                        flush()
                    }
                    let cell = Cell(
                        id: field.id + ".part." + String(index + 1),
                        sectionTitle: section.title,
                        title: field.label + (pieces.count > 1 ? "（第 \(index + 1)/\(pieces.count) 段）" : ""),
                        text: text,
                        source: field.source,
                        explanation: firstPart ? PosterPlainGuide.explanation(for: field) : nil
                    )
                    current.append(cell)
                    used += estimate
                }
            }
        }
        flush()
        guard !pages.isEmpty else { throw Failure.noContent }
        guard pages.count <= 120 else { throw Failure.tooManyPages }
        return pages
    }
}

/// 540pt x 1050pt at scale 2 gives a 1080x2100 PNG with legible fixed-size text.
/// Background artwork is decoration only; no generated sample data is ever embedded.
struct PosterPrintedPage: View {
    let snapshot: PosterDynamicSnapshot
    let page: PosterPageLayout.Page
    let total: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            VStack(alignment: .leading, spacing: 6) {
                Text("三术合参  /  传统命理阅读报告")
                    .font(.system(size: 12, weight: .semibold, design: .serif))
                Text(snapshot.kind.title)
                    .font(.system(size: 31, weight: .bold, design: .serif))
                Text(snapshot.displayName.isEmpty ? "未命名人物" : snapshot.displayName)
                    .font(.system(size: 16, weight: .medium))
                Text("第 \(page.id) / \(total) 张")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(snapshot.kind.ink)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 12) {
                ForEach(page.cells) { cell in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(cell.sectionTitle)
                            .font(.system(size: 15, weight: .bold, design: .serif))
                            .foregroundStyle(snapshot.kind.ink)
                        Text(cell.title)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(snapshot.kind.ink)
                        if let explanation = cell.explanation {
                            Text("先看懂：" + explanation)
                                .font(.system(size: 14))
                                .foregroundStyle(Color(red: 0.23, green: 0.25, blue: 0.25))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Text(cell.text)
                            .font(.system(size: 15))
                            .foregroundStyle(Color(red: 0.14, green: 0.16, blue: 0.17))
                            .fixedSize(horizontal: false, vertical: true)
                        Text("来源：" + cell.source)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(13)
                    .background(.white.opacity(0.93))
                    .clipShape(RoundedRectangle(cornerRadius: 11))
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 4) {
                Text(snapshot.receipt)
                    .font(.system(size: 10, design: .monospaced))
                    .lineLimit(3)
                Text("传统文化解释不等于现实预测 · 本页只使用已有计算结果")
                    .font(.system(size: 11))
            }
            .foregroundStyle(snapshot.kind.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
        .frame(width: 540, height: 1050, alignment: .top)
        .background(snapshot.kind.paper)
    }
}

/// Builds a locally saved ZIP with numbered PNGs and hash receipts.
/// A failed attempt cleans up only its own new paths and never deletes an older export.
@MainActor enum PosterPagedArchive {
    static func export(_ snapshot: PosterDynamicSnapshot) async throws -> URL {
        let pages = try PosterPageLayout.paginate(snapshot)
        guard let owner = snapshot.ownerID else { throw PosterPageLayout.Failure.noOwner }
        let root = try ReportExportArchive.rootDirectory()
            .appendingPathComponent("PosterBatches", isDirectory: true)
        let batchID = UUID().uuidString
        let folder = root.appendingPathComponent(batchID, isDirectory: true)
        let archive = root.appendingPathComponent("KanyuPoster-\(snapshot.kind.rawValue)-\(batchID).zip")
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            var manifestPages: [[String: Any]] = []
            for page in pages {
                try Task.checkCancellation()
                let view = PosterPrintedPage(snapshot: snapshot, page: page, total: pages.count)
                let image = try PosterRasterizer.render(view, scale: 2)
                let png = image.pngData
                guard let src = CGImageSourceCreateWithData(png as CFData, nil),
                      let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
                      let width = props[kCGImagePropertyPixelWidth] as? Int,
                      let height = props[kCGImagePropertyPixelHeight] as? Int,
                      width == 1080, height == 2100 else {
                    throw PosterRasterizer.Failure.encodingFailed(1080, 2100)
                }
                let name = String(format: "Poster-%03d-of-%03d.png", page.id, pages.count)
                try png.write(to: folder.appendingPathComponent(name), options: .atomic)
                let digest = SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined()
                manifestPages.append(["file": name, "sha256": digest, "bytes": png.count])
                await Task.yield()
            }
            let manifest: [String: Any] = [
                "schema": "ios.poster.batch.v1",
                "kind": snapshot.kind.rawValue,
                "ownerID": owner.uuidString,
                "pageCount": pages.count,
                "receipt": snapshot.receipt,
                "pages": manifestPages
            ]
            let receipt = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
            try receipt.write(to: folder.appendingPathComponent("manifest.json"), options: .atomic)
            try fm.zipItem(at: folder, to: archive)
            let size = try fm.attributesOfItem(atPath: archive.path)[.size] as? NSNumber
            guard (size?.intValue ?? 0) > 0 else { throw PosterPageLayout.Failure.noContent }
            return archive
        } catch {
            try? fm.removeItem(at: archive)
            try? fm.removeItem(at: folder)
            throw error
        }
    }
}
