import XCTest
@testable import Kanyu

final class V5ThemePreferenceTests: XCTestCase {
    func testExistingDarkPreferenceIsReadWithoutWritingMigration() throws {
        let name = "V5ThemePreferenceTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("dark", forKey: "uiStyle")
        XCTAssertEqual(V5Theme.initialTheme(in: defaults), .night)
        XCTAssertNil(defaults.object(forKey: "v5.theme"))
        XCTAssertEqual(defaults.string(forKey: "uiStyle"), "dark")
        defaults.set("light", forKey: "uiStyle")
        XCTAssertEqual(V5Theme.initialTheme(in: defaults), .song)
    }
    func testExplicitProThemeWinsAndUnknownValueFallsBackSafely() throws {
        let name = "V5ThemePreferenceTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("dark", forKey: "uiStyle")
        for theme in V5Theme.allCases {
            defaults.set(theme.rawValue, forKey: "v5.theme")
            XCTAssertEqual(V5Theme.initialTheme(in: defaults), theme)
        }
        defaults.set("unsupported", forKey: "v5.theme")
        XCTAssertEqual(V5Theme.initialTheme(in: defaults), .night)
        XCTAssertEqual(defaults.string(forKey: "v5.theme"), "unsupported")
    }
}
