import XCTest
import UIKit
import UniformTypeIdentifiers
@testable import Kanyu

final class V5PosterShareItemTests: XCTestCase {
    @MainActor func testLongPNGProvidesBoundedMetadataButSharesOriginalBytes() throws {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.preferredRange = .standard
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1080, height: 6000), format: format).image { context in
            UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 1080, height: 3000))
            UIColor.blue.setFill(); context.fill(CGRect(x: 0, y: 3000, width: 1080, height: 3000))
        }
        let data = try XCTUnwrap(image.pngData())
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        try data.write(to: file); defer { try? FileManager.default.removeItem(at: file) }
        let item = V5PosterShareItem(url: file, title: "八字古风长卷")
        let controller = UIActivityViewController(activityItems: [item], applicationActivities: nil)
        XCTAssertEqual(item.activityViewControllerPlaceholderItem(controller) as? URL, file)
        XCTAssertEqual(item.activityViewController(controller, itemForActivityType: .saveToCameraRoll) as? URL, file)
        XCTAssertEqual(item.activityViewController(controller, dataTypeIdentifierForActivityType: .saveToCameraRoll), UTType.png.identifier)
        let preview = try XCTUnwrap(item.thumbnail?.cgImage)
        XCTAssertLessThanOrEqual(max(preview.width, preview.height), 320)
        XCTAssertEqual(Double(preview.width)/Double(preview.height), 1080.0/6000.0, accuracy: 0.01)
        let metadata = try XCTUnwrap(item.activityViewControllerLinkMetadata(controller))
        XCTAssertEqual(metadata.title, "八字古风长卷")
        XCTAssertNotNil(metadata.imageProvider); XCTAssertNotNil(metadata.iconProvider)
        XCTAssertEqual(try Data(contentsOf: file), data, "A share preview must not resize or rewrite the actual export")
    }
    func testEveryPresentationHasIndependentIdentityEvenForSameURL() {
        let file = URL(fileURLWithPath: "/tmp/real-poster.png")
        let a = V5PosterSharePayload(url: file), b = V5PosterSharePayload(url: file)
        XCTAssertEqual(a.url, b.url); XCTAssertNotEqual(a.id, b.id)
    }
}
