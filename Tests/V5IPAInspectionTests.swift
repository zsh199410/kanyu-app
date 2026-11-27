import XCTest
import CryptoKit
import ZIPFoundation
@testable import Kanyu

/// Real ZIP fixtures exercise the local importer without signing, UI, or user stores.
final class V5IPAInspectionTests: XCTestCase {
    private var directory: URL!
    private var inspectedCopies: [URL] = []
    private let app = "Payload/Fixture.app/"
    private let executable = Data("fixture executable bytes".utf8)

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("V5IPAInspectionTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws {
        for copy in inspectedCopies { try? FileManager.default.removeItem(at: copy.deletingLastPathComponent()) }
        try? FileManager.default.removeItem(at: directory)
        inspectedCopies = []
    }
    private func info(executable: String = "Fixture", packageType: String = "APPL") throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: [
            "CFBundleIdentifier": "org.example.fixture", "CFBundleName": "Fixture",
            "CFBundleDisplayName": "测试应用", "CFBundleExecutable": executable,
            "CFBundlePackageType": packageType, "CFBundleShortVersionString": "5.0", "CFBundleVersion": "42"
        ], format: .binary, options: 0)
    }
    private func archive(_ entries: [(String, Data)], deflate: Bool = false) throws -> URL {
        let url = directory.appendingPathComponent("Fixture-\(UUID().uuidString).ipa")
        let zip = try Archive(url: url, accessMode: .create)
        for (path, data) in entries {
            try zip.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count),
                             compressionMethod: deflate ? .deflate : .none) { position, size in
                let lower = Int(position)
                return data.subdata(in: lower..<min(data.count, lower + size))
            }
        }
        return url
    }
    private func valid(extra: [(String, Data)] = [], deflate: Bool = false) throws -> URL {
        try archive([(app + "Info.plist", info()), (app + "Fixture", executable)] + extra, deflate: deflate)
    }
    private func inspect(_ url: URL) throws -> V5LibraryIPAReceipt {
        let receipt = try V5LibraryIPAInspector.inspect(url)
        inspectedCopies.append(receipt.url)
        return receipt
    }
    private func replacePath(in url: URL, from old: String, to replacement: String) throws {
        let needle = Data(old.utf8), value = Data(replacement.utf8)
        XCTAssertEqual(needle.count, value.count)
        var bytes = try Data(contentsOf: url)
        var replacements = 0
        var cursor = bytes.startIndex
        while cursor < bytes.endIndex, let range = bytes.range(of: needle, in: cursor..<bytes.endIndex) {
            bytes.replaceSubrange(range, with: value)
            cursor = range.lowerBound + value.count
            replacements += 1
        }
        // A real ZIP contains this path in its local and central header.
        XCTAssertEqual(replacements, 2)
        try bytes.write(to: url)
    }
    private func littleEndian32(_ bytes: Data, at offset: Int) -> Int {
        (0..<4).reduce(0) { $0 | (Int(bytes[offset + $1]) << ($1 * 8)) }
    }
    private func centralHeader(in bytes: Data, named path: String) throws -> Int {
        let signature = Data([0x50, 0x4b, 0x01, 0x02])
        var cursor = 0
        while cursor < bytes.count, let range = bytes.range(of: signature, in: cursor..<bytes.count) {
            let offset = range.lowerBound
            guard offset + 46 <= bytes.count else { break }
            let length = Int(bytes[offset + 28]) | Int(bytes[offset + 29]) << 8
            if offset + 46 + length <= bytes.count,
               String(data: bytes.subdata(in: offset + 46..<offset + 46 + length), encoding: .utf8) == path {
                return offset
            }
            cursor = offset + 4
        }
        throw NSError(domain: "V5IPAInspectionTests.MissingCentralHeader", code: 1)
    }

    func testValidStoredAndDeflatedIPAsProduceIndependentReadOnlyCopyAndCorrectHash() throws {
        for deflate in [false, true] {
            let source = try valid(deflate: deflate)
            let original = try Data(contentsOf: source)
            let receipt = try inspect(source)
            XCTAssertEqual(receipt.name, "测试应用")
            XCTAssertEqual(receipt.version, "5.0")
            XCTAssertEqual(receipt.build, "42")
            XCTAssertEqual(receipt.bundleID, "org.example.fixture")
            XCTAssertEqual(receipt.bytes, Int64(original.count))
            XCTAssertEqual(receipt.sha256, SHA256.hash(data: original).map { String(format: "%02x", $0) }.joined())
            XCTAssertNotEqual(receipt.url, source)
            XCTAssertEqual(try Data(contentsOf: receipt.url), original)
            let attributes = try FileManager.default.attributesOfItem(atPath: receipt.url.path)
            XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o400)
            // Modifying the provider's file cannot change the already inspected copy.
            try Data("provider replaced source".utf8).write(to: source)
            XCTAssertEqual(try Data(contentsOf: receipt.url), original)
        }
    }
    func testMissingOrEmptyExecutableIsRejected() throws {
        for entries in [[(app + "Info.plist", try info())],
                        [(app + "Info.plist", try info()), (app + "Fixture", Data())]] {
            XCTAssertThrowsError(try inspect(archive(entries)))
        }
    }
    func testExecutableCannotEscapeMainApp() throws {
        for name in ["../Fixture", ".", "..", "Other/Fixture", "Other\\Fixture"] {
            let source = try archive([(app + "Info.plist", info(executable: name)), (app + "Fixture", executable)])
            XCTAssertThrowsError(try inspect(source), name)
        }
    }
    func testMissingMalformedOrNonApplicationInfoIsRejected() throws {
        let fixtures = [
            try archive([(app + "Fixture", executable)]),
            try archive([(app + "Info.plist", Data("not a plist".utf8)), (app + "Fixture", executable)]),
            try archive([(app + "Info.plist", info(packageType: "BNDL")), (app + "Fixture", executable)])
        ]
        for source in fixtures { XCTAssertThrowsError(try inspect(source)) }
    }
    func testMultipleMainAppsAreRejected() throws {
        let source = try valid(extra: [("Payload/Second.app/Info.plist", info()), ("Payload/Second.app/Fixture", executable)])
        XCTAssertThrowsError(try inspect(source))
    }
    func testNestedExtensionInfoDoesNotCountAsSecondMainApp() throws {
        let source = try valid(extra: [(app + "PlugIns/Widget.appex/Info.plist", info(packageType: "XPC!"))])
        XCTAssertEqual(try inspect(source).bundleID, "org.example.fixture")
    }
    func testUnsafePathsAreRejectedWithoutExtractingFiles() throws {
        let paths = ["../outside.txt", "/outside.txt", "Assets/./file", "Assets//file", "Assets\\file"]
        for path in paths {
            let placeholder = String(repeating: "x", count: path.utf8.count)
            let source = try valid(extra: [(placeholder, Data("unsafe entry".utf8))])
            try replacePath(in: source, from: placeholder, to: path)
            XCTAssertThrowsError(try inspect(source), path)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("outside.txt").path))
    }
    func testDuplicatePathIsRejected() throws {
        let source = try valid(extra: [("Assets/one.txt", Data([1])), ("Assets/two.txt", Data([2]))])
        try replacePath(in: source, from: "Assets/two.txt", to: "Assets/one.txt")
        XCTAssertThrowsError(try inspect(source))
    }
    func testCorruptedStoredContentsFailCRCAndLeaveSourceUntouched() throws {
        let source = try valid()
        var bytes = try Data(contentsOf: source)
        let central = try centralHeader(in: bytes, named: app + "Fixture")
        let local = littleEndian32(bytes, at: central + 42)
        let nameLength = Int(bytes[local + 26]) | Int(bytes[local + 27]) << 8
        let extraLength = Int(bytes[local + 28]) | Int(bytes[local + 29]) << 8
        let content = local + 30 + nameLength + extraLength
        bytes[content] ^= 0xff
        try bytes.write(to: source)
        XCTAssertThrowsError(try inspect(source))
        XCTAssertEqual(try Data(contentsOf: source), bytes)
    }
    func testUnderstatedDeflateOutputSizeIsRejected() throws {
        let source = try valid(extra: [("Assets/compressed.bin", Data(repeating: 0x61, count: 131_072))], deflate: true)
        var bytes = try Data(contentsOf: source)
        let central = try centralHeader(in: bytes, named: "Assets/compressed.bin")
        let local = littleEndian32(bytes, at: central + 42)
        // Preserve valid compressed bytes/CRC but forge advertised expanded size in both headers.
        for offset in [central + 24, local + 22] { bytes.replaceSubrange(offset..<offset + 4, with: [1, 0, 0, 0]) }
        try bytes.write(to: source)
        XCTAssertThrowsError(try inspect(source))
    }
    func testOverstatedOutputSizeIsRejected() throws {
        let source = try valid(deflate: true)
        var bytes = try Data(contentsOf: source)
        let central = try centralHeader(in: bytes, named: app + "Fixture")
        let local = littleEndian32(bytes, at: central + 42)
        let advertised = executable.count + 1
        let value = (0..<4).map { UInt8((advertised >> ($0 * 8)) & 0xff) }
        for offset in [central + 24, local + 22] { bytes.replaceSubrange(offset..<offset + 4, with: value) }
        try bytes.write(to: source)
        XCTAssertThrowsError(try inspect(source))
    }
    func testDirectoryAndSymbolicLinkCannotBeImportedAsSourceIPA() throws {
        let source = try valid()
        let symlink = directory.appendingPathComponent("linked.ipa")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: source)
        XCTAssertThrowsError(try inspect(symlink))
        let folder = directory.appendingPathComponent("folder.ipa")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        XCTAssertThrowsError(try inspect(folder))
    }
    func testEmptyGarbageTruncatedAndWrongExtensionAreRejected() throws {
        let validSource = try valid()
        let bytes = try Data(contentsOf: validSource)
        for data in [Data(), Data("not ZIP".utf8), Data(bytes.prefix(bytes.count / 2))] {
            let source = directory.appendingPathComponent(UUID().uuidString + ".ipa")
            try data.write(to: source)
            XCTAssertThrowsError(try inspect(source))
            XCTAssertEqual(try Data(contentsOf: source), data)
        }
        let wrongExtension = validSource.deletingPathExtension().appendingPathExtension("zip")
        try FileManager.default.copyItem(at: validSource, to: wrongExtension)
        XCTAssertThrowsError(try inspect(wrongExtension))
    }
    func testAlreadyCancelledTaskRejectsBeforeInspectingAndPreservesSource() async throws {
        let source = try valid()
        let original = try Data(contentsOf: source)
        let cancelled = await Task.detached { () -> Bool in
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                let receipt = try V5LibraryIPAInspector.inspect(source)
                try? FileManager.default.removeItem(at: receipt.url.deletingLastPathComponent())
                return false
            } catch is CancellationError { return true }
            catch { return false }
        }.value
        XCTAssertTrue(cancelled)
        XCTAssertEqual(try Data(contentsOf: source), original)
    }
}
