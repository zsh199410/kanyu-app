import XCTest
import Combine
@testable import Kanyu

final class V5NativeStackOwnershipTests: XCTestCase {
    @MainActor func testNativePathChangesPublishOnlyToTheirOwningStack() {
        let router = V5Router()
        let home = router.stack(for: 0)
        let measure = router.stack(for: 1)
        XCTAssertTrue(measure === router.stack(for: 1))
        var homeUpdates = 0, measureUpdates = 0, routerUpdates = 0
        let observations = [home.objectWillChange.sink { homeUpdates += 1 },
                            measure.objectWillChange.sink { measureUpdates += 1 },
                            router.objectWillChange.sink { routerUpdates += 1 }]
        withExtendedLifetime(observations) {
            measure.routes.append(.bazi)
            measure.routes.removeLast() // The exact native system-pop write.
            XCTAssertEqual(measureUpdates, 2)
            XCTAssertEqual(homeUpdates, 0)
            XCTAssertEqual(routerUpdates, 0)
            XCTAssertTrue(measure.routes.isEmpty)
        }
    }
    @MainActor func testRetainedBindingAndRouterUseTheSameStackAfterSwitchingTabs() {
        let router = V5Router()
        router.tab = 1
        router.open(.bazi)
        let nativePath = router.path(for: 1)
        router.tab = 0
        router.open(.settings)
        nativePath.wrappedValue.removeLast()
        XCTAssertTrue(router.stack(for: 1).routes.isEmpty)
        XCTAssertEqual(router.stack(for: 0).routes, [.settings])
        router.tab = 1
        router.open(.ziwei)
        XCTAssertEqual(nativePath.wrappedValue, [.ziwei])
    }
}
