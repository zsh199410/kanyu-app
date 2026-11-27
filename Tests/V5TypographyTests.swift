import XCTest
import UIKit
import CoreText
@testable import Kanyu

final class V5TypographyTests: XCTestCase {
    func testBundledTypefaceRegistersBothFacesAndContainsChineseGlyphs() throws {
        for name in [V5Typeface.regularName, V5Typeface.emphasizedName] {
            let font = try XCTUnwrap(UIFont(name: name, size: 20), "Bundled Chinese serif is not registered")
            XCTAssertEqual(font.fontName, name)
            let face = CTFontCreateWithName(name as CFString, 20, nil)
            let characters = Array("三术合参甲乙丙丁紫微命书风水林王".utf16)
            var glyphs = [CGGlyph](repeating: 0, count: characters.count)
            XCTAssertTrue(CTFontGetGlyphsForCharacters(face, characters, &glyphs, characters.count))
            XCTAssertTrue(glyphs.allSatisfy { $0 != 0 }, "Chinese text would silently fall back")
        }
        let license = try XCTUnwrap(Bundle.main.url(forResource: "LICENSE-NotoSerifCJK", withExtension: "txt"))
        XCTAssertTrue(try String(contentsOf: license).contains("SIL OPEN FONT LICENSE Version 1.1"))
    }
}
