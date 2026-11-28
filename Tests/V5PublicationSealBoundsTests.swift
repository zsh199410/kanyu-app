import XCTest
import PDFKit
import CryptoKit
@testable import Kanyu

/// Inspect actual PDFKit raster output, including font fallback and the original
/// ReportBuilder cover. Text extraction alone cannot detect glyphs clipped by a box.
final class V5PublicationSealBoundsTests: XCTestCase {
    @MainActor func testFourFormalCoversKeepWhiteSealGlyphsInsideCinnabar() throws {
        let store = V5ThemeStore.shared, original = store.theme
        let saved = UserDefaults.standard.object(forKey: "v5.theme")
        defer {
            store.select(original)
            if let saved { UserDefaults.standard.set(saved, forKey: "v5.theme") }
            else { UserDefaults.standard.removeObject(forKey: "v5.theme") }
        }
        for theme in V5Theme.allCases {
            store.select(theme)
            var person = Person(name: "印章边界验证", relation: "本人", birthEpoch: 946684800, useLongitude: false)
            person.id = UUID(uuidString: "00000000-0000-4000-8000-000000005002")!
            let url = try XCTUnwrap(ReportBuilder.makePDF(for: person, tier: .professional))
            let bytes = try Data(contentsOf: url)
            let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
            let archived = try ReportExportArchive.rootDirectory().appendingPathComponent(digest).appendingPathComponent(url.lastPathComponent)
            defer {
                try? FileManager.default.removeItem(at: url)
                try? FileManager.default.removeItem(at: archived)
                if (try? FileManager.default.contentsOfDirectory(atPath: archived.deletingLastPathComponent().path).isEmpty) == true {
                    try? FileManager.default.removeItem(at: archived.deletingLastPathComponent())
                }
            }
            let document = try XCTUnwrap(PDFDocument(data: bytes))
            let page = try XCTUnwrap(document.page(at: 0))
            XCTAssertTrue((page.string ?? "").contains("三术"))
            XCTAssertTrue((page.string ?? "").contains("合参"))
            let width = 595, height = 842
            let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
            page.draw(with: .mediaBox, to: context)
            let pixels = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
            var minX = width, minY = height, maxX = -1, maxY = -1
            for y in 0..<height {
                for x in 0..<width {
                    let offset = y * context.bytesPerRow + x * 4
                    if abs(Int(pixels[offset]) - 154) <= 3 && abs(Int(pixels[offset + 1]) - 42) <= 3 && abs(Int(pixels[offset + 2]) - 34) <= 3 {
                        minX = min(minX, x); maxX = max(maxX, x)
                        minY = min(minY, y); maxY = max(maxY, y)
                    }
                }
            }
            XCTAssertTrue((62...65).contains(maxX - minX + 1), theme.rawValue)
            XCTAssertTrue((62...65).contains(maxY - minY + 1), theme.rawValue)
            guard minX <= maxX && minY <= maxY else { continue }
            var inkCount = 0, inkMinY = height, inkMaxY = -1
            for y in minY...maxY {
                for x in minX...maxX {
                    let offset = y * context.bytesPerRow + x * 4
                    if pixels[offset] > 225 && pixels[offset + 1] > 225 && pixels[offset + 2] > 225 {
                        inkCount += 1; inkMinY = min(inkMinY, y); inkMaxY = max(inkMaxY, y)
                    }
                }
            }
            XCTAssertGreaterThan(inkCount, 50, "The real embedded white glyphs must be visible: \(theme.rawValue)")
            XCTAssertGreaterThanOrEqual(inkMinY - minY, 8, "White glyphs touch the lower seal edge: \(theme.rawValue)")
            XCTAssertGreaterThanOrEqual(maxY - inkMaxY, 8, "White glyphs touch the upper seal edge: \(theme.rawValue)")
            let image = try XCTUnwrap(context.makeImage())
            let proof = XCTAttachment(image: UIImage(cgImage: image))
            proof.name = "v5-native-pdf-cover-\(theme.rawValue)";proof.lifetime = .keepAlways;add(proof)
        }
    }
}
