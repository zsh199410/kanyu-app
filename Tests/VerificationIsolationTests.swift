import XCTest
@testable import Kanyu

final class VerificationIsolationTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "VerificationIsolationTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testSameTitleIsIsolatedAcrossPeopleAndPersistsForSamePerson() {
        VerifyStore.set("事业方向", ownerID: "person:A", true, defaults: defaults)

        XCTAssertEqual(VerifyStore.mark(for: "事业方向", ownerID: "person:A", defaults: defaults), true)
        XCTAssertNil(VerifyStore.mark(for: "事业方向", ownerID: "person:B", defaults: defaults))
        XCTAssertEqual(VerifyStore.verifiedCount(itemIDs: ["事业方向"], ownerID: "person:A", defaults: defaults), 1)
        XCTAssertEqual(VerifyStore.verifiedCount(itemIDs: ["事业方向"], ownerID: "person:B", defaults: defaults), 0)
    }

    func testLegacyMarksRemainUnassignedAndAreNotReadAsCurrentPerson() {
        defaults.set(["事业方向": true], forKey: VerifyStore.legacyKey)

        XCTAssertEqual(VerifyStore.legacyMarkCount(defaults: defaults), 1)
        XCTAssertNil(VerifyStore.mark(for: "事业方向", ownerID: "person:A", defaults: defaults))
    }

    func testUnboundChartCannotWriteGlobalMark() {
        VerifyStore.set("事业方向", ownerID: nil, true, defaults: defaults)

        XCTAssertNil(defaults.dictionary(forKey: VerifyStore.key))
    }
}

