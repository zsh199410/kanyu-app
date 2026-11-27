import XCTest
import UIKit
@testable import Kanyu

final class V5WorkThumbnailTests: XCTestCase {
    private var directory: URL!
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("V5WorkThumbnailTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }
    private func png(size: CGSize, upper: UIColor, lower: UIColor? = nil) throws -> URL {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1; format.opaque = true; format.preferredRange = .standard
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            upper.setFill(); context.fill(CGRect(origin: .zero, size: size))
            if let lower {
                lower.setFill()
                context.fill(CGRect(x: 0, y: size.height / 3, width: size.width, height: size.height * 2 / 3))
            }
        }
        let url = directory.appendingPathComponent(UUID().uuidString + ".png")
        try XCTUnwrap(image.pngData()).write(to: url)
        return url
    }
    private func pixel(_ image: UIImage, verticalFraction: CGFloat = 0.5) throws -> (red: UInt8, green: UInt8, blue: UInt8) {
        let cg = try XCTUnwrap(image.cgImage)
        let x = cg.width / 2
        let y = min(cg.height - 1, max(0, Int(CGFloat(cg.height) * verticalFraction)))
        let sample = try XCTUnwrap(cg.cropping(to: CGRect(x: CGFloat(x), y: CGFloat(y), width: 1, height: 1)))
        var rgba = Data(count: 4)
        try rgba.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
            context.draw(sample, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return (rgba[0], rgba[1], rgba[2])
    }
    func testLongPNGShowsRealUpperRegionAtReadableBoundedResolution() async throws {
        // Same long-poster proportions as 1080×9520. Lower two thirds are deliberately blue.
        let source = try png(size: CGSize(width: 720, height: 6_350), upper: .red, lower: .blue)
        let bytes = try Data(contentsOf: source)
        let result = try await V5WorkThumbnailStore().image(for: source)
        let cg = try XCTUnwrap(result.image.cgImage)
        XCTAssertTrue(result.showsUpperRegion)
        XCTAssertGreaterThanOrEqual(cg.width, 320)
        XCTAssertLessThanOrEqual(cg.width, 400)
        XCTAssertLessThanOrEqual(max(cg.width, cg.height), 4_096)
        XCTAssertEqual(Double(cg.width) / Double(cg.height), 0.707, accuracy: 0.005)
        // Both ends of the returned cover remain in the original red upper band, not the blue lower strip.
        for position in [CGFloat(0.1), CGFloat(0.9)] {
            let color = try pixel(result.image, verticalFraction: position)
            XCTAssertGreaterThan(color.red, 220)
            XCTAssertLessThan(color.blue, 30)
        }
        XCTAssertEqual(try Data(contentsOf: source), bytes)
    }
    func testTwoPagePDFRendersActualFirstPageOnly() async throws {
        let url = directory.appendingPathComponent("two-pages.pdf")
        let bounds = CGRect(x: 0, y: 0, width: 240, height: 340)
        let bytes = UIGraphicsPDFRenderer(bounds: bounds).pdfData { renderer in
            for color in [UIColor.red, UIColor.blue] {
                renderer.beginPage()
                color.setFill(); renderer.cgContext.fill(bounds)
            }
        }
        try bytes.write(to: url)
        XCTAssertEqual(try XCTUnwrap(CGPDFDocument(url as CFURL)).numberOfPages, 2)
        let result = try await V5WorkThumbnailStore().image(for: url)
        XCTAssertFalse(result.showsUpperRegion)
        let cg = try XCTUnwrap(result.image.cgImage)
        XCTAssertLessThanOrEqual(max(cg.width, cg.height), 640)
        let color = try pixel(result.image)
        XCTAssertGreaterThan(color.red, 220)
        XCTAssertLessThan(color.blue, 30)
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }
    func testCorruptedReplacementAtSameURLDoesNotReturnCachedOldImage() async throws {
        let store = V5WorkThumbnailStore()
        let source = try png(size: CGSize(width: 80, height: 100), upper: .green)
        let first = try await store.image(for: source)
        XCTAssertGreaterThan(try pixel(first.image).green, 220)
        let corrupt = Data("This file replaced a previously valid PNG.".utf8)
        try corrupt.write(to: source)
        do {
            _ = try await store.image(for: source)
            XCTFail("A damaged source must not return the previous cached preview")
        } catch { XCTAssertFalse(error is CancellationError) }
        XCTAssertEqual(try Data(contentsOf: source), corrupt)
    }
    func testCancelledRequestDoesNotReturnPreviouslyCachedImage() async throws {
        let store = V5WorkThumbnailStore()
        let source = try png(size: CGSize(width: 80, height: 100), upper: .blue)
        let cached = try await store.image(for: source)
        XCTAssertGreaterThan(try pixel(cached.image).blue, 220)
        let cancelled = await Task.detached { () -> Bool in
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try await store.image(for: source)
                return false
            } catch is CancellationError { return true }
            catch { return false }
        }.value
        XCTAssertTrue(cancelled)
    }
}
