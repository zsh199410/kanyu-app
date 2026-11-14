import XCTest
@testable import Kanyu

/// P0-4 同名隔离：只测已按 UUID 隔离的 VerifyStore（ownerID 为 "person:<uuid>"）。
/// 边界：PalmRecord／Forecast／报告中心目前按姓名归属（同名会串），是否改 UUID 键等产品裁决，
/// 本文件不测、不改。
final class PersonIsolationTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "PersonIsolationTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    private func sameNamePair() -> (Person, Person) {
        let first = Person(id: UUID(), name: "QA-同名", birthEpoch: 946684800.0)
        let second = Person(id: UUID(), name: "QA-同名", birthEpoch: 978307200.0)
        return (first, second)
    }

    private func ownerID(for person: Person) -> String {
        "person:\(person.id.uuidString)"
    }

    func testSameNamePersonsHaveDistinctOwnerIDs() {
        let (first, second) = sameNamePair()

        XCTAssertEqual(first.name, second.name)
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertNotEqual(ownerID(for: first), ownerID(for: second))
    }

    func testSameNameDifferentIDsHaveIsolatedMarks() {
        let (first, second) = sameNamePair()

        VerifyStore.set("事业方向", ownerID: ownerID(for: first), true, defaults: defaults)
        XCTAssertEqual(VerifyStore.mark(for: "事业方向", ownerID: ownerID(for: first), defaults: defaults), true)
        XCTAssertNil(VerifyStore.mark(for: "事业方向", ownerID: ownerID(for: second), defaults: defaults))
        XCTAssertEqual(VerifyStore.verifiedCount(itemIDs: ["事业方向"], ownerID: ownerID(for: first), defaults: defaults), 1)
        XCTAssertEqual(VerifyStore.verifiedCount(itemIDs: ["事业方向"], ownerID: ownerID(for: second), defaults: defaults), 0)

        VerifyStore.set("事业方向", ownerID: ownerID(for: second), false, defaults: defaults)
        XCTAssertEqual(VerifyStore.mark(for: "事业方向", ownerID: ownerID(for: first), defaults: defaults), true)
        XCTAssertEqual(VerifyStore.mark(for: "事业方向", ownerID: ownerID(for: second), defaults: defaults), false)
        XCTAssertEqual(VerifyStore.pendingCount(itemIDs: ["事业方向"], ownerID: ownerID(for: second), defaults: defaults), 1)
        XCTAssertEqual(VerifyStore.pendingCount(itemIDs: ["事业方向"], ownerID: ownerID(for: first), defaults: defaults), 0)
    }

    func testSameTitlePersistsForSamePersonAcrossWrites() {
        let (first, second) = sameNamePair()

        VerifyStore.set("事业方向", ownerID: ownerID(for: first), true, defaults: defaults)
        VerifyStore.set("财运走势", ownerID: ownerID(for: first), false, defaults: defaults)
        VerifyStore.set("财运走势", ownerID: ownerID(for: second), true, defaults: defaults)

        XCTAssertEqual(VerifyStore.mark(for: "事业方向", ownerID: ownerID(for: first), defaults: defaults), true)
        XCTAssertEqual(VerifyStore.mark(for: "财运走势", ownerID: ownerID(for: first), defaults: defaults), false)
        XCTAssertEqual(VerifyStore.mark(for: "财运走势", ownerID: ownerID(for: second), defaults: defaults), true)
        XCTAssertNil(VerifyStore.mark(for: "事业方向", ownerID: ownerID(for: second), defaults: defaults))
    }

    func testAccuracyIsComputedPerPerson() throws {
        let (first, second) = sameNamePair()

        VerifyStore.set("事业方向", ownerID: ownerID(for: first), true, defaults: defaults)
        VerifyStore.set("财运走势", ownerID: ownerID(for: first), false, defaults: defaults)

        let accuracy = try XCTUnwrap(VerifyStore.accuracy(itemIDs: ["事业方向", "财运走势"], ownerID: ownerID(for: first), defaults: defaults))
        XCTAssertEqual(accuracy, 0.5, accuracy: 0.001)
        XCTAssertNil(VerifyStore.accuracy(itemIDs: ["事业方向", "财运走势"], ownerID: ownerID(for: second), defaults: defaults))
    }
}
