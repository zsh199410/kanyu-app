import XCTest
import UIKit
@testable import Kanyu

/// Raster bounds verify the real bundled cover illustration cannot override the
/// reserved text field's paper contrast. This does not change or snapshot report text.
final class V5PublicationArtworkOpacityTests: XCTestCase {
    @MainActor func testEveryThemeCoverArtRespectsCompositingBounds() throws {
        let width = 595, height = 842
        for theme in V5Theme.allCases {
            let style = V5PublicationStyle(theme: theme)
            let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
            let page = CGRect(x: 0, y: 0, width: width, height: height)
            style.drawBackground(in: context, pageRect: page, cover: true)
            style.drawCoverArtwork(in: context, pageRect: page)
            let pixels = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
            var low = [255, 255, 255], high = [0, 0, 0]
            // Exclude the separate opaque gold frame; examine only the illustrated field.
            for y in 60..<(height - 60) {
                for x in 50..<(width - 50) {
                    let offset = y * context.bytesPerRow + x * 4
                    for channel in 0..<3 {
                        low[channel] = min(low[channel], Int(pixels[offset + channel]))
                        high[channel] = max(high[channel], Int(pixels[offset + channel]))
                    }
                }
            }
            let paper = style.palette.heroSurface
            let background = [Int((paper >> 16) & 255), Int((paper >> 8) & 255), Int(paper & 255)]
            let alpha = style.palette.isDark ? 0.22 : 0.38
            for channel in 0..<3 {
                // Independent source-over bounds for *any* source pixel in [0,255].
                let lower = Int(floor(Double(background[channel]) * (1 - alpha))) - 3
                let upper = Int(ceil(Double(background[channel]) + alpha * Double(255 - background[channel]))) + 3
                XCTAssertGreaterThanOrEqual(low[channel], lower, theme.rawValue)
                XCTAssertLessThanOrEqual(high[channel], upper, theme.rawValue)
            }
        }
    }
}
