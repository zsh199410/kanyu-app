import XCTest
import UIKit
@testable import Kanyu

final class V5ArtworkStoreTests: XCTestCase {
    private var directory: URL!
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }
    private func png(_ color: UIColor, width: Int = 400, height: Int = 200) throws -> URL {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = false; format.preferredRange = .standard
        let size = CGSize(width: width, height: height)
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            color.setFill(); context.fill(CGRect(x: 0, y: 0, width: size.width / 2, height: size.height))
        }
        let url = directory.appendingPathComponent(UUID().uuidString + ".png")
        try XCTUnwrap(image.pngData()).write(to: url)
        return url
    }
    func testDownsamplesWithoutCroppingOrLosingAlpha() throws {
        let store = V5ArtworkStore(byteLimit: 1024 * 1024)
        let image = try XCTUnwrap(store.image(at: png(.red), maximumPixelSize: 100)?.cgImage)
        XCTAssertEqual(image.width, 100); XCTAssertEqual(image.height, 50)
        XCTAssertTrue([CGImageAlphaInfo.premultipliedLast, .premultipliedFirst, .last, .first].contains(image.alphaInfo))
        // Decode into known RGBA order; the transparent half must remain transparent.
        var pixels = [UInt8](repeating: 0, count: 100 * 50 * 4)
        let context = try XCTUnwrap(CGContext(data: &pixels, width: 100, height: 50, bitsPerComponent: 8,
            bytesPerRow: 400, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: 100, height: 50))
        XCTAssertEqual(pixels[(25 * 100 + 25) * 4], 255)
        XCTAssertEqual(pixels[(25 * 100 + 25) * 4 + 3], 255)
        XCTAssertEqual(pixels[(25 * 100 + 75) * 4 + 3], 0)
    }
    func testSizeAndResourceIdentityAreSeparateCacheKeys() throws {
        let store = V5ArtworkStore(byteLimit: 1024 * 1024)
        let first = try png(.red), second = try png(.blue)
        let small = try XCTUnwrap(store.image(at: first, maximumPixelSize: 50))
        let large = try XCTUnwrap(store.image(at: first, maximumPixelSize: 100))
        let other = try XCTUnwrap(store.image(at: second, maximumPixelSize: 50))
        XCTAssertEqual(small.cgImage?.width, 50); XCTAssertEqual(large.cgImage?.width, 100)
        XCTAssertFalse(small === other)
        XCTAssertTrue(small === store.image(at: first, maximumPixelSize: 50))
    }
    func testLRUEvictsUsingDecodedBytesAndKeepsRecentlyUsedEntry() throws {
        let store = V5ArtworkStore(byteLimit: 2 * 64 * 64 * 4)
        let a = try png(.red, width: 64, height: 64)
        let b = try png(.blue, width: 64, height: 64)
        let c = try png(.green, width: 64, height: 64)
        let first = try XCTUnwrap(store.image(at: a, maximumPixelSize: 64))
        let second = try XCTUnwrap(store.image(at: b, maximumPixelSize: 64))
        XCTAssertTrue(first === store.image(at: a, maximumPixelSize: 64))
        XCTAssertNotNil(store.image(at: c, maximumPixelSize: 64))
        XCTAssertLessThanOrEqual(store.cachedBytes, 2 * 64 * 64 * 4)
        XCTAssertTrue(first === store.image(at: a, maximumPixelSize: 64))
        XCTAssertFalse(second === store.image(at: b, maximumPixelSize: 64))
        store.removeAll(); XCTAssertEqual(store.cachedBytes, 0)
    }
    func testOversizedExportDecodesButIsNotRetained() throws {
        let store = V5ArtworkStore(byteLimit: 100)
        XCTAssertNotNil(store.image(at: try png(.red), maximumPixelSize: 400))
        XCTAssertEqual(store.cachedBytes, 0)
    }
    func testInvalidOrTruncatedFilesFailWithoutPoisoningCache() throws {
        let store = V5ArtworkStore(byteLimit: 1024 * 1024)
        let url = directory.appendingPathComponent("bad.png")
        try Data([137,80,78,71,13,10,26,10]).write(to: url)
        XCTAssertNil(store.image(at: url, maximumPixelSize: 100))
        XCTAssertNil(store.image(at: url, maximumPixelSize: 0))
        XCTAssertNil(store.image(at: url, maximumPixelSize: 8193))
        XCTAssertEqual(store.cachedBytes, 0)
        let valid = try png(.red)
        try FileManager.default.removeItem(at: url)
        try FileManager.default.copyItem(at: valid, to: url)
        XCTAssertNotNil(store.image(at: url, maximumPixelSize: 100))
    }
    func testConcurrentAsyncRequestsShareDecodedImage() async throws {
        let url = try png(.red)
        let store = V5ArtworkStore(byteLimit: 1024 * 1024)
        async let first = store.load(at: url, maximumPixelSize: 100)
        async let second = store.load(at: url, maximumPixelSize: 100)
        let (a, b) = await (first, second)
        XCTAssertNotNil(a); XCTAssertTrue(a === b)
        XCTAssertTrue(a === store.image(at: url, maximumPixelSize: 100))
    }
    func testCancelledRequestDoesNotDeliverImage() async throws {
        let url = try png(.blue)
        let store = V5ArtworkStore(byteLimit: 1024 * 1024)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await store.load(at: url, maximumPixelSize: 100)
        }
        let image = await task.value
        XCTAssertNil(image); XCTAssertEqual(store.cachedBytes, 0)
    }
}
