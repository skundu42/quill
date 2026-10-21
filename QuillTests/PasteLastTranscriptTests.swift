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

    func testTurnCompleteBeforeFinalDoesNotDiscardTranscript() async throws {
        let context = try makeContext()
        defer { context.cleanup() }
        beginFinalizing(context.controller)
        let generation = context.controller.sessionGeneration

        context.controller.receive(.turnComplete, generation: generation)
        XCTAssertNil(context.controller.completionTask)
        XCTAssertEqual(AppState.shared.phase, .finalizing)

        context.controller.receive(.final("Delayed final words"), generation: generation)
        await context.controller.completionTask?.value

        XCTAssertEqual(context.insertion.insertedText, "Delayed final words")
        XCTAssertEqual(AppState.shared.lastTranscript, "Delayed final words")
        XCTAssertEqual(context.stats.totalDictations, 1)
        XCTAssertEqual(AppState.shared.phase, .idle)
    }

    func testFinalTranscriptBeforeStopIsInsertedOnlyAfterAudioEnd() async throws {
        let context = try makeContext()
        defer { context.cleanup() }
        AppState.shared.phase = .listening
        let generation = context.controller.sessionGeneration

        context.controller.receive(.final("Already finalized words"), generation: generation)
        context.controller.receive(.turnComplete, generation: generation)

        XCTAssertNil(context.controller.completionTask)
        XCTAssertNil(context.insertion.insertedText)
        XCTAssertEqual(AppState.shared.phase, .listening)

        context.controller.stop()
        XCTAssertNil(context.controller.completionTask)
        let queue = GeminiOutboundQueue(capacity: 1)
        context.controller.endAudioInput(on: GeminiLiveSession(outboundQueue: queue))
        queue.finish()
        var iterator = queue.stream.makeAsyncIterator()
        let endMarker = await iterator.next()
        XCTAssertEqual(endMarker, .activityEnd)
        await context.controller.completionTask?.value

        XCTAssertEqual(context.insertion.insertedText, "Already finalized words")
        XCTAssertEqual(AppState.shared.lastTranscript, "Already finalized words")
        XCTAssertEqual(context.stats.totalDictations, 1)
        XCTAssertEqual(AppState.shared.phase, .idle)
    }

    func testFinalArrivingBetweenStopAndAudioEndIsPreserved() async throws {
        let context = try makeContext()
        defer { context.cleanup() }
        AppState.shared.phase = .listening
        let generation = context.controller.sessionGeneration

        context.controller.stop()
        context.controller.receive(.final("Words received during stop"), generation: generation)
        XCTAssertNil(context.controller.completionTask)
        XCTAssertNil(context.insertion.insertedText)

        context.controller.endAudioInput(on: GeminiLiveSession())
        await context.controller.completionTask?.value

        XCTAssertEqual(context.insertion.insertedText, "Words received during stop")
        XCTAssertEqual(context.stats.totalDictations, 1)
        XCTAssertEqual(AppState.shared.phase, .idle)
    }

    func testExplicitEmptyFinalCompletesWithoutInsertion() async throws {
        let context = try makeContext()
        defer { context.cleanup() }
        beginFinalizing(context.controller)

        context.controller.receive(.final(""), generation: context.controller.sessionGeneration)
        await context.controller.completionTask?.value

        XCTAssertNil(context.insertion.insertedText)
        XCTAssertEqual(context.stats.totalDictations, 0)
        XCTAssertEqual(AppState.shared.phase, .idle)
    }

    func testCancelDuringCompletedDictationCancelsInsertion() async throws {
        let context = try makeContext()
        defer { context.cleanup() }
        let enteredInsertion = expectation(description: "insertion suspended")
        var resume: CheckedContinuation<Void, Never>?
        context.insertion.beforeInsert = {
            await withCheckedContinuation {
                resume = $0
                enteredInsertion.fulfill()
            }
            try Task.checkCancellation()
        }
        beginFinalizing(context.controller)
        context.controller.receive(.final("Cancelled words"), generation: context.controller.sessionGeneration)
        let completion = try XCTUnwrap(context.controller.completionTask)
        await fulfillment(of: [enteredInsertion], timeout: 2)

        XCTAssertTrue(context.controller.cancel())
        resume?.resume()
        await completion.value

        XCTAssertTrue(completion.isCancelled)
        XCTAssertNil(context.insertion.insertedText)
        XCTAssertEqual(context.stats.totalDictations, 0)
        XCTAssertEqual(AppState.shared.phase, .idle)
    }

    func testLateInsertionResultCannotOverwriteANewerSession() async throws {
        for insertionError in [nil, TextInsertionError.targetUnavailableCopiedToClipboard] {
            let context = try makeContext()
            defer { context.cleanup() }
            let enteredInsertion = expectation(description: "insertion suspended")
            var resume: CheckedContinuation<Void, Never>?
            context.insertion.beforeInsert = {
                await withCheckedContinuation {
                    resume = $0
                    enteredInsertion.fulfill()
                }
                // Simulate an external operation that finishes despite cancellation.
            }
            context.insertion.errorToThrow = insertionError
            beginFinalizing(context.controller)
            context.controller.receive(.final("Old words"), generation: context.controller.sessionGeneration)
            let completion = try XCTUnwrap(context.controller.completionTask)
            await fulfillment(of: [enteredInsertion], timeout: 2)

            XCTAssertTrue(context.controller.cancel())
            AppState.shared.phase = .listening
            AppState.shared.lastTranscript = "Newer words"
            resume?.resume()
            await completion.value

            XCTAssertEqual(AppState.shared.phase, .listening)
            XCTAssertEqual(AppState.shared.lastTranscript, "Newer words")
            XCTAssertNil(AppState.shared.lastError)
            XCTAssertEqual(context.stats.totalDictations, 0)
        }
    }

    func testLocalDictationCompletesWithoutGeminiCredentials() async throws {
        let context = try makeContext(barkTranscriber: StubBarkTranscriber(text: "Local words"))
        defer { context.cleanup() }
        AppState.shared.phase = .finalizing

        context.controller.finishBarkAudio(generation: context.controller.sessionGeneration)
        await context.controller.barkTranscriptionTask?.value
        await context.controller.completionTask?.value

        XCTAssertEqual(context.insertion.insertedText, "Local words")
        XCTAssertEqual(AppState.shared.lastTranscript, "Local words")
        XCTAssertEqual(context.stats.totalDictations, 1)
        XCTAssertEqual(AppState.shared.phase, .idle)
    }

    func testCancelledLocalResultCannotInsertIntoANewerSession() async throws {
        let started = expectation(description: "local transcription started")
        let transcriber = SuspendedBarkTranscriber(onStart: { started.fulfill() })
        let context = try makeContext(barkTranscriber: transcriber)
        defer { context.cleanup() }
        AppState.shared.phase = .finalizing
        context.controller.finishBarkAudio(generation: context.controller.sessionGeneration)
        let transcription = try XCTUnwrap(context.controller.barkTranscriptionTask)
        await fulfillment(of: [started], timeout: 2)

        XCTAssertTrue(context.controller.cancel())
        AppState.shared.phase = .listening
        AppState.shared.lastTranscript = "Newer words"
        await transcriber.finish()
        await transcription.value

        XCTAssertNil(context.insertion.insertedText)
        XCTAssertEqual(context.stats.totalDictations, 0)
        XCTAssertEqual(AppState.shared.lastTranscript, "Newer words")
        XCTAssertEqual(AppState.shared.phase, .listening)
    }

    private func beginFinalizing(_ controller: DictationController) {
        AppState.shared.phase = .listening
        controller.stop()
        controller.endAudioInput(on: GeminiLiveSession())
    }

    private func waitForInsertion(_ insertion: FakeTextInsertionService) async {
        for _ in 0..<20 where insertion.insertedText == nil {
            await Task.yield()
        }
    }

    private func makeContext(barkTranscriber: any BarkTranscribing = BarkTranscriber.shared) throws -> TestContext {
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
            insertionService: insertion,
            barkTranscriber: barkTranscriber
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
    var beforeInsert: (() async throws -> Void)?

    func rememberFrontmostTarget() {}
    func captureTarget() -> TextInsertionTarget? { nil }

    func insert(_ text: String, mode: InsertionMode, target: TextInsertionTarget?) async throws {
        try await beforeInsert?()
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
        controller.cancel()
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }
}

private struct StubBarkTranscriber: BarkTranscribing {
    let text: String
    func transcribe(pcm: Data) async throws -> String { text }
}

private actor SuspendedBarkTranscriber: BarkTranscribing {
    private var continuation: CheckedContinuation<String, Never>?
    let onStart: @Sendable () -> Void

    init(onStart: @escaping @Sendable () -> Void) { self.onStart = onStart }

    func transcribe(pcm: Data) async throws -> String {
        await withCheckedContinuation {
            continuation = $0
            onStart()
        }
    }

    func finish() {
        continuation?.resume(returning: "Cancelled local words")
        continuation = nil
    }
}
