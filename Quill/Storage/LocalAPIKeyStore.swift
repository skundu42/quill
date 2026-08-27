import Combine
import Foundation

enum LocalAPIKeyStoreError: LocalizedError {
    case couldNotSecureFile

    var errorDescription: String? {
        "Quill could not secure the local API key file."
    }
}

@MainActor
final class LocalAPIKeyStore: ObservableObject {
    static let shared = LocalAPIKeyStore()

    @Published private(set) var hasKey: Bool
    private var apiKey: String?
    private let fileURL: URL
    private let fileManager: FileManager

    init(fileURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.fileURL = fileURL ?? Self.defaultFileURL(fileManager: fileManager)
        let storedKey = try? String(contentsOf: self.fileURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if storedKey?.isEmpty == false,
           (try? Self.secureAndValidateFile(at: self.fileURL, fileManager: fileManager)) == true {
            apiKey = storedKey
        } else {
            apiKey = nil
        }
        hasKey = apiKey?.isEmpty == false
    }

    func replace(with key: String) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        do {
            try Data(trimmed.utf8).write(to: fileURL, options: .atomic)
            guard try Self.secureAndValidateFile(at: fileURL, fileManager: fileManager) else {
                throw LocalAPIKeyStoreError.couldNotSecureFile
            }
        } catch {
            try? fileManager.removeItem(at: fileURL)
            apiKey = nil
            hasKey = false
            throw error
        }

        apiKey = trimmed
        hasKey = true
    }

    func value() -> String? {
        apiKey
    }

    private static func defaultFileURL(fileManager: FileManager) -> URL {
        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return applicationSupport
            .appendingPathComponent("Quill", isDirectory: true)
            .appendingPathComponent("api-key", isDirectory: false)
    }

    private static func secureAndValidateFile(at url: URL, fileManager: FileManager) throws -> Bool {
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        return (attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600
    }
}
