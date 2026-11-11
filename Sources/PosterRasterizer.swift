import SwiftUI
import UIKit
import ImageIO
import UniformTypeIdentifiers

/// A shared, bounded 8-bit sRGB export path for production sheets and native QA.
/// Core Graphics owns the bitmap; PNG encoding does not depend on UIImage's renderer backing.
@MainActor enum PosterRasterizer {
    struct Output {
        let image: UIImage
        let pngData: Data
    }
    enum Failure: LocalizedError {
        case invalidSize
        case tooLarge(Int, Int)
        case contextUnavailable(Int, Int)
        case encodingFailed(Int, Int)
        case noOutput
        var errorDescription: String? {
            switch self {
            case .tooLarge:
                return "海报过长，暂时无法生成单张图片。请从人物档案生成命书 PDF。"
            case .encodingFailed:
                return "海报图片编码失败，请重试。"
            default:
                return "海报生成失败，请稍后重试。"
            }
        }
    }

    static func render<Content: View>(_ content: Content, scale: CGFloat = 2) throws -> Output {
        guard scale.isFinite, scale > 0 else { throw Failure.invalidSize }
        let renderer = ImageRenderer(content: content)
        var result: Result<Output, Error>?
        renderer.render(rasterizationScale: scale) { size, draw in
            let scaledWidth = ceil(size.width * scale)
            let scaledHeight = ceil(size.height * scale)
            guard scaledWidth.isFinite, scaledHeight.isFinite,
                  scaledWidth > 0, scaledHeight > 0 else {
                result = .failure(Failure.invalidSize); return
            }
            guard scaledWidth <= 32_768, scaledHeight <= 32_768 else {
                result = .failure(Failure.tooLarge(Int(min(scaledWidth, 32_769)), Int(min(scaledHeight, 32_769)))); return
            }
            let width = Int(scaledWidth), height = Int(scaledHeight)
            guard width * height <= 40_000_000 else {
                result = .failure(Failure.tooLarge(width, height)); return
            }
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(data: nil, width: width, height: height,
                      bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else {
                result = .failure(Failure.contextUnavailable(width, height)); return
            }
            context.scaleBy(x: scale, y: scale)
            draw(context)
            guard let cgImage = context.makeImage() else {
                result = .failure(Failure.contextUnavailable(width, height)); return
            }
            result = Result {
                Output(image: UIImage(cgImage: cgImage, scale: scale, orientation: .up),
                       pngData: try encode(cgImage))
            }
        }
        guard let result else { throw Failure.noOutput }
        return try result.get()
    }

    private static func encode(_ image: CGImage) throws -> Data {
        guard let buffer = CFDataCreateMutable(kCFAllocatorDefault, 0),
              let destination = CGImageDestinationCreateWithData(buffer, UTType.png.identifier as CFString, 1, nil) else {
            throw Failure.encodingFailed(image.width, image.height)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination), CFDataGetLength(buffer) > 0,
              let bytes = CFDataGetBytePtr(buffer) else {
            throw Failure.encodingFailed(image.width, image.height)
        }
        return Data(bytes: bytes, count: CFDataGetLength(buffer))
    }
}
