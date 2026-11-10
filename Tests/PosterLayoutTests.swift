import SwiftUI
import XCTest
@testable import Kanyu

final class PosterLayoutTests: XCTestCase {
    @MainActor
    func testPosterLayoutsRenderAtExportWidth() throws {
        let birth = Date(timeIntervalSince1970: 946684800)
        let bazi = BaziEngine.cachedPaipan(clock: birth, gender: "M", longitude: nil)
        let ziwei = ZiweiEngine.cachedChart(clock: birth, gender: "M", longitude: nil)
        let name = "海报排版回归样例"
        let posters: [(String, AnyView)] = [
            ("八字", AnyView(PosterView(chart: bazi, name: name))),
            ("预测单", AnyView(PosterView(chart: bazi, name: name, style: .yuceDan))),
            ("紫微", AnyView(ZiweiPosterView(chart: ziwei, name: name))),
            ("合参", AnyView(HeCanPosterView(bazi: bazi, ziwei: ziwei, name: name,
                palmLines: [String(repeating: "长文本换行样例。", count: 20)])))
        ]

        for (title, poster) in posters {
            let renderer = ImageRenderer(content: poster.environment(\.colorScheme, .light))
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.uiImage?.cgImage, title)
            XCTAssertEqual(image.width, 1080, title)
            XCTAssertGreaterThan(image.height, image.width, title)
        }
    }
}

