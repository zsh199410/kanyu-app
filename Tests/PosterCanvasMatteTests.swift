import SwiftUI
import ImageIO
import UIKit
import XCTest
@testable import Kanyu

/// Independent regression: the frozen formal tests did not inspect every alpha byte.
final class PosterCanvasMatteTests: XCTestCase {
    private func decoded(_ data: Data) throws -> CGImage {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        return try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }
    private func alphaMinimum(_ image: CGImage) throws -> UInt8 {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        return try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            var minimum: UInt8 = 255
            for offset in stride(from: 3, to: buffer.count, by: 4) { minimum = min(minimum, buffer[offset]) }
            return minimum
        }
    }
    @MainActor func testFractionalHeightGetsPaperAcrossEveryIntegerPixel() throws {
        let output = try PosterRasterizer.render(Color.clear.frame(width: 10, height: 10.25))
        let image = try decoded(output.pngData)
        XCTAssertEqual(image.width, 20)
        XCTAssertEqual(image.height, 21)
        XCTAssertEqual(try alphaMinimum(image), 255)
    }
    @MainActor func testNightMatteComesFromExistingStyleWithoutPaperHalo() throws {
        let output = try PosterRasterizer.render(Color.clear.frame(width: 10, height: 10.25), matte: PosterStyle.xuanye.exportMatteColor)
        let image = try decoded(output.pngData)
        XCTAssertEqual(try alphaMinimum(image), 255)
        let color = UIColor(PosterStyle.xuanye.exportMatteColor)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        XCTAssertTrue(color.getRed(&r, green: &g, blue: &b, alpha: &a))
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try pixels.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        // Encoded sRGB uses the existing dark palette, rather than the default ivory.
        XCTAssertEqual(pixels[0], UInt8((r * 255).rounded()))
        XCTAssertEqual(pixels[1], UInt8((g * 255).rounded()))
        XCTAssertEqual(pixels[2], UInt8((b * 255).rounded()))
    }
    @MainActor func testLegacyPremiumFormalPNGAndPreviewHaveCompletePaper() throws {
        let person = Person(name: "纸底回归", birthEpoch: 946684800)
        let chart = BaziEngine.cachedPaipan(clock: person.birthDate, gender: person.gender,
            longitude: person.useLongitude ? person.longitude : nil)
        let output = try PosterRasterizer.render(PosterView(chart: chart, name: person.name, style: .yuceDan)
            .environment(\.colorScheme, .light).environment(\.dynamicTypeSize, .large))
        let image = try decoded(output.pngData)
        XCTAssertEqual(image.width, 1080)
        XCTAssertGreaterThan(image.height, 5000)
        XCTAssertEqual(try alphaMinimum(image), 255, "Formal PNG has transparent paper")
        XCTAssertEqual(try alphaMinimum(XCTUnwrap(output.image.cgImage)), 255, "Share preview has transparent paper")
        let attachment = XCTAttachment(data: output.pngData, uniformTypeIdentifier: "public.png")
        attachment.name = "premium-complete-paper-raw-png"; attachment.lifetime = .keepAlways; add(attachment)
    }
}
