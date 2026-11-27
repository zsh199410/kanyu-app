import XCTest
@testable import Kanyu

final class V5NavigationPathIsolationTests: XCTestCase {
    @MainActor func testCapturedTabBindingCannotWriteIntoNewlySelectedTab() {
        let router = V5Router()
        let home = router.path(for: 0)
        let measure = router.path(for: 1)
        router.tab = 1
        home.wrappedValue = [.settings]
        XCTAssertEqual(router.paths[0], [.settings])
        XCTAssertTrue(measure.wrappedValue.isEmpty)
        measure.wrappedValue = [.bazi, .appearance]
        router.tab = 0
        measure.wrappedValue.removeLast()
        XCTAssertEqual(home.wrappedValue, [.settings])
        XCTAssertEqual(router.paths[1], [.bazi])
    }
}
