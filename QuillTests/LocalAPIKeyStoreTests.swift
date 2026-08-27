import XCTest
@testable import Quill

@MainActor
final class LocalAPIKeyStoreTests: XCTestCase {
    func testKeyPersistsAcrossStoreInstances() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("api-key")

        try LocalAPIKeyStore(fileURL: fileURL).replace(with: "  first-key  ")
        let reloaded = LocalAPIKeyStore(fileURL: fileURL)

        XCTAssertTrue(reloaded.hasKey)
        XCTAssertEqual(reloaded.value(), "first-key")
    }

    func testNewKeyReplacesPreviousKey() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("api-key")
        let store = LocalAPIKeyStore(fileURL: fileURL)

        try store.replace(with: "first-key")
        try store.replace(with: "second-key")

        XCTAssertEqual(LocalAPIKeyStore(fileURL: fileURL).value(), "second-key")
    }

    func testKeyFileIsOwnerReadWriteOnly() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("api-key")

        try LocalAPIKeyStore(fileURL: fileURL).replace(with: "test-key")

        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }
}
