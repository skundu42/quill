import XCTest
@testable import Quill

@MainActor
final class PasteLastTranscriptTests: XCTestCase {
    override func setUp() {
        super.setUp()
        AppState.shared.phase = .idle
        AppState.shared.lastTranscript = ""
        AppState.shared.lastError = nil
    }

    override func tearDown() {
        AppState.shared.phase = .idle
        AppState.shared.lastTranscript = ""
        AppState.shared.lastError = nil
        super.tearDown()
    }

    func testPasteLastUsesDirectInsertionWithoutRecordingStats() async throws {
        let context = try makeContext()
        defer { context.cleanup() }
        AppState.shared.lastTranscript = "Latest words"
        let totalBefore = context.stats.totalDictations

        context.controller.pasteLastTranscript()
        await waitForInsertion(context.insertion)

        XCTAssertEqual(context.insertion.insertedText, "Latest words")
        XCTAssertEqual(context.insertion.insertedMode, .direct)
        XCTAssertEqual(AppState.shared.lastTranscript, "Latest words")
        XCTAssertEqual(context.stats.totalDictations, totalBefore)
        XCTAssertEqual(AppState.shared.phase, .idle)
    }

    func testPasteLastWithoutTranscriptShowsError() throws {
        let context = try makeContext()
        defer { context.cleanup() }

        context.controller.pasteLastTranscript()

        XCTAssertEqual(AppState.shared.phase, .error("No recent transcript to paste."))
        XCTAssertEqual(AppState.shared.lastError, "No recent transcript to paste.")
        XCTAssertNil(context.insertion.insertedText)
    }

    func testPasteLastIsIgnoredWhileDictationIsActive() throws {
        let context = try makeContext()
        defer { context.cleanup() }
        AppState.shared.lastTranscript = "Do not paste yet"
        AppState.shared.phase = .listening

        context.controller.pasteLastTranscript()

        XCTAssertNil(context.insertion.insertedText)
        XCTAssertEqual(AppState.shared.phase, .listening)
    }

    func testUnavailableTargetKeepsTranscriptAndStatisticsUnchanged() async throws {
        let context = try makeContext()
        defer { context.cleanup() }
        AppState.shared.lastTranscript = "Keep this transcript"
        context.insertion.errorToThrow = TextInsertionError.targetUnavailableCopiedToClipboard
        let totalBefore = context.stats.totalDictations

        context.controller.pasteLastTranscript()
        for _ in 0..<20 where AppState.shared.phase == .inserting {
            await Task.yield()
        }

        XCTAssertEqual(
            AppState.shared.lastError,
            TextInsertionError.targetUnavailableCopiedToClipboard.localizedDescription
        )
        XCTAssertEqual(AppState.shared.lastTranscript, "Keep this transcript")
        XCTAssertEqual(context.stats.totalDictations, totalBefore)
    }

    private func waitForInsertion(_ insertion: FakeTextInsertionService) async {
        for _ in 0..<20 where insertion.insertedText == nil {
            await Task.yield()
        }
    }

    private func makeContext() throws -> TestContext {
        let suiteName = "PasteLastTranscriptTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PasteLastTranscriptTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        let preferences = AppPreferences(defaults: defaults)
        let stats = LocalStatsStore(defaults: defaults)
        let keys = LocalAPIKeyStore(fileURL: temporaryDirectory.appendingPathComponent("api-key"))
        let insertion = FakeTextInsertionService()
        let controller = DictationController(
            state: .shared,
            preferences: preferences,
            stats: stats,
            apiKeys: keys,
            insertionService: insertion
        )
        return TestContext(
            suiteName: suiteName,
            defaults: defaults,
            temporaryDirectory: temporaryDirectory,
            stats: stats,
            insertion: insertion,
            controller: controller
        )
    }
}

@MainActor
private final class FakeTextInsertionService: TextInsertionServing {
    var insertedText: String?
    var insertedMode: InsertionMode?
    var errorToThrow: Error?

    func rememberFrontmostTarget() {}
    func captureTarget() -> TextInsertionTarget? { nil }

    func insert(_ text: String, mode: InsertionMode, target: TextInsertionTarget?) async throws {
        insertedText = text
        insertedMode = mode
        if let errorToThrow { throw errorToThrow }
    }
}

@MainActor
private struct TestContext {
    let suiteName: String
    let defaults: UserDefaults
    let temporaryDirectory: URL
    let stats: LocalStatsStore
    let insertion: FakeTextInsertionService
    let controller: DictationController

    func cleanup() {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }
}
