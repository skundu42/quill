import CoreML
import CryptoKit
import Foundation

enum BarkError: LocalizedError {
    case unsupported
    case modelNotInstalled
    case invalidDownload(String)
    case invalidAudio
    case recordingTooLong
    case invalidEncoderOutput

    var errorDescription: String? {
        switch self {
        case .unsupported: "Bark 3.0 requires Apple silicon and macOS 15 or later. Select Gemini in Models on this Mac."
        case .modelNotInstalled: "Download Bark 3.0 in Models before dictating."
        case .invalidDownload(let file): "Bark model verification failed for \(file). Please retry the download."
        case .invalidAudio: "Bark could not read the recorded audio. Please try again."
        case .recordingTooLong: "Bark supports up to five minutes per dictation. Please use shorter recordings."
        case .invalidEncoderOutput: "Bark returned invalid audio features. Please try again."
        }
    }
}

@MainActor
final class BarkModelManager: ObservableObject {
    static let shared = BarkModelManager()

    static var isSupported: Bool {
        #if arch(arm64)
        if #available(macOS 15, *) { return true }
        #endif
        return false
    }

    @Published private(set) var isReady: Bool
    @Published private(set) var isDownloading = false
    @Published private(set) var progress = 0.0
    @Published private(set) var status = "Download once to transcribe English on this Mac."
    @Published private(set) var error: String?

    init() {
        isReady = BarkModelFiles.isInstalled
        if isReady { status = "Ready for offline dictation." }
    }

    func prepare(reinstall: Bool = false) async {
        guard !isDownloading, !isReady || reinstall else { return }
        guard Self.isSupported else {
            error = BarkError.unsupported.localizedDescription
            return
        }
        isDownloading = true
        isReady = false
        error = nil
        progress = 0
        // Installation belongs to the app, so navigating away does not cancel it.
        let task = Task.detached(priority: .utility) {
            try await BarkModelFiles.install(reinstall: reinstall) { progress, status in
                await MainActor.run {
                    self.progress = progress
                    self.status = status
                }
            }
        }
        do {
            try await task.value
            isReady = true
            progress = 1
            status = "Ready for offline dictation."
        } catch {
            self.error = error.localizedDescription
            isReady = BarkModelFiles.isInstalled
            status = "Download could not finish. Retry when you are ready."
        }
        isDownloading = false
    }
}

/// The published Core ML variant of the standard (verbatim) Bark 3.0 model.
/// Files are pinned to a revision and checked before compilation or extraction.
enum BarkModelFiles {
    static let revision = "85db2ad18ab41e534a222ee253c29191d77ed919"
    static let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Quill/Models/Bark-3.0-\(revision)", isDirectory: true)

    struct Artifact {
        let path: String
        let size: Int64
        let sha256: String

        var localPath: String {
            path.replacingOccurrences(of: "coreml/ane/", with: "")
                .replacingOccurrences(of: "coreml/", with: "")
        }
    }

    static let artifacts = [
        Artifact(path: "coreml/ane/BarkEncoder.mlpackage/Manifest.json", size: 617,
                 sha256: "d37c121561b99da49b9bf1e28c00152c14c56a943815fa83008ee0691b8f1149"),
        Artifact(path: "coreml/ane/BarkEncoder.mlpackage/Data/com.apple.CoreML/model.mlmodel", size: 1_784_701,
                 sha256: "7c3f1c1612ba21bcc4d8efff1b32154b39cb3e1e2f10020117793acc5c96fcdf"),
        Artifact(path: "coreml/ane/BarkEncoder.mlpackage/Data/com.apple.CoreML/weights/weight.bin", size: 189_133_632,
                 sha256: "98979e5dd731486ddfb2c312f80a3038205c058aac9fe0f403ba26e1a158d385"),
        Artifact(path: "coreml/ane/decoder.npz", size: 11_168_286,
                 sha256: "1ce79071f54c3dcec9aa9bb1d488486766f1fdbb3fd988b776da3f4da8024665"),
        Artifact(path: "coreml/ane/vocab.json", size: 115_878,
                 sha256: "eee86951e9f74921342fdc60ba26711eb70f7188e8784d98d2aecfc525b72270"),
        Artifact(path: "coreml/LICENSE", size: 18_657,
                 sha256: "9ba9550ad48438d0836ddab3da480b3b69ffa0aac7b7878b5a0039e7ab429411"),
        Artifact(path: "coreml/NOTICE", size: 603,
                 sha256: "7760825e72004ccf97f7a8b63a75e2890105a7cae8ca875b70d4df78cff9abcd")
    ]

    static var isInstalled: Bool { isInstalled(at: directory) }

    static func isInstalled(at folder: URL) -> Bool {
        let manager = FileManager.default
        guard (try? String(contentsOf: folder.appendingPathComponent("ready"), encoding: .utf8)) == revision else { return false }
        return ["BarkEncoder.mlmodelc", "decoder/mel_filters.npy", "vocab.json"].allSatisfy {
            manager.fileExists(atPath: folder.appendingPathComponent($0).path)
        }
    }

    static func install(reinstall: Bool = false, onProgress: @escaping @Sendable (Double, String) async -> Void) async throws {
        if isInstalled && !reinstall { return }
        let manager = FileManager.default
        removeAbandonedStagingDirectories()
        let staging = directory.deletingLastPathComponent().appendingPathComponent(".bark-\(UUID().uuidString)")
        try manager.createDirectory(at: staging, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? manager.removeItem(at: staging) }
        let total = Double(artifacts.reduce(Int64(0)) { $0 + $1.size })
        var received: Int64 = 0
        for artifact in artifacts {
            try Task.checkCancellation()
            await onProgress(Double(received) / total * 0.9, "Downloading Bark 3.0 (202 MB)…")
            let url = URL(string: "https://huggingface.co/ConwayResearch/Underdog-Bark-3.0/resolve/\(revision)/\(artifact.path)")!
            var request = URLRequest(url: url)
            request.timeoutInterval = 300
            let (temporary, response) = try await URLSession.shared.download(for: request)
            defer { try? manager.removeItem(at: temporary) }
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw BarkError.invalidDownload(artifact.localPath)
            }
            try verify(temporary, artifact: artifact)
            let destination = staging.appendingPathComponent(artifact.localPath)
            try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try manager.moveItem(at: temporary, to: destination)
            received += artifact.size
        }
        await onProgress(0.9, "Preparing Bark for this Mac. First setup may take several minutes…")
        let decoderDirectory = staging.appendingPathComponent("decoder", isDirectory: true)
        // Only a size- and SHA-256-verified archive is passed to the system extractor.
        let extraction = Process()
        extraction.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        extraction.arguments = ["-x", "-k", staging.appendingPathComponent("decoder.npz").path, decoderDirectory.path]
        extraction.standardOutput = FileHandle.nullDevice
        extraction.standardError = FileHandle.nullDevice
        try extraction.run()
        extraction.waitUntilExit()
        guard extraction.terminationStatus == 0 else { throw BarkError.invalidDownload("decoder.npz") }
        _ = try BarkDecoder(directory: decoderDirectory, vocabularyURL: staging.appendingPathComponent("vocab.json"))
        try Task.checkCancellation()
        let compiled = try await MLModel.compileModel(at: staging.appendingPathComponent("BarkEncoder.mlpackage"))
        defer { try? manager.removeItem(at: compiled) }
        try manager.moveItem(at: compiled, to: staging.appendingPathComponent("BarkEncoder.mlmodelc"))
        try manager.removeItem(at: staging.appendingPathComponent("BarkEncoder.mlpackage"))
        try manager.removeItem(at: staging.appendingPathComponent("decoder.npz"))
        try Task.checkCancellation()
        let backup = directory.deletingLastPathComponent().appendingPathComponent(".bark-\(UUID().uuidString)")
        let hadPreviousModel = manager.fileExists(atPath: directory.path)
        if hadPreviousModel { try manager.moveItem(at: directory, to: backup) }
        do {
            try manager.moveItem(at: staging, to: directory)
            // Core ML specialization can depend on the compiled model's path. Warm
            // at the permanent path, and publish readiness only after it succeeds.
            await BarkTranscriber.shared.unload()
            try await BarkTranscriber.shared.prepare()
            try Task.checkCancellation()
            try Data(revision.utf8).write(to: directory.appendingPathComponent("ready"), options: .atomic)
            if hadPreviousModel { try? manager.removeItem(at: backup) }
        } catch {
            await BarkTranscriber.shared.unload()
            try? manager.removeItem(at: directory)
            if hadPreviousModel { try? manager.moveItem(at: backup, to: directory) }
            throw error
        }
    }

    private static func removeAbandonedStagingDirectories() {
        let manager = FileManager.default
        let parent = directory.deletingLastPathComponent()
        guard let folders = try? manager.contentsOfDirectory(at: parent, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        for folder in folders {
            let name = folder.lastPathComponent
            guard name.hasPrefix(".bark-"), UUID(uuidString: String(name.dropFirst(6))) != nil,
                  let modified = try? folder.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                  modified < Date().addingTimeInterval(-86_400) else { continue }
            try? manager.removeItem(at: folder)
        }
    }

    static func verify(_ url: URL, artifact: Artifact) throws {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize
        guard size == Int(artifact.size) else { throw BarkError.invalidDownload(artifact.localPath) }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            try Task.checkCancellation()
            hash.update(data: data)
        }
        let digest = hash.finalize().map { String(format: "%02x", $0) }.joined()
        guard digest == artifact.sha256 else { throw BarkError.invalidDownload(artifact.localPath) }
    }
}
