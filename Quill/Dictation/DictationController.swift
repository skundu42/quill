import AppKit
import Foundation

struct TranscriptionCompletionGate {
    private(set) var activityEnded = false
    private(set) var finalTranscriptReceived = false
    private(set) var turnCompleteReceived = false
    private(set) var completionStarted = false

    var isReady: Bool {
        activityEnded && (finalTranscriptReceived || turnCompleteReceived)
    }

    var canCompleteImmediately: Bool {
        isReady && turnCompleteReceived
    }

    mutating func markActivityEnded() {
        activityEnded = true
    }

    mutating func receiveFinalTranscript() {
        finalTranscriptReceived = true
    }

    mutating func receiveTurnComplete() {
        turnCompleteReceived = true
    }

    mutating func beginCompletion() -> Bool {
        guard isReady, !completionStarted else { return false }
        completionStarted = true
        return true
    }
}

@MainActor
final class DictationController {
    private static let maximumBufferedAudioBytes = 16_000 * 2 * 30

    private let state: AppState
    private let preferences: AppPreferences
    private let apiKeys: LocalAPIKeyStore
    private let audioRecorder: AudioRecorder
    private let insertionService: any TextInsertionServing
    private let stats: LocalStatsStore

    private var session: GeminiLiveSession?
    private var sessionConnected = false
    private var pendingAudio: [Data] = []
    private var pendingAudioBytes = 0
    private var shouldEndWhenConnected = false
    private var usesHybridVoiceActivityDetection = false
    private var completionGate = TranscriptionCompletionGate()
    private var finalSegments: [String] = []
    private var connectionTask: Task<Void, Never>?
    private var completionTask: Task<Void, Never>?
    private var finalizationTimeoutTask: Task<Void, Never>?
    private var errorResetTask: Task<Void, Never>?
    private var pasteTask: Task<Void, Never>?
    private var sessionGeneration = UUID()
    private var insertionTarget: TextInsertionTarget?

    init(
        state: AppState,
        preferences: AppPreferences,
        stats: LocalStatsStore,
        apiKeys: LocalAPIKeyStore,
        audioRecorder: AudioRecorder = AudioRecorder(),
        insertionService: (any TextInsertionServing)? = nil
    ) {
        self.state = state
        self.preferences = preferences
        self.apiKeys = apiKeys
        self.audioRecorder = audioRecorder
        self.insertionService = insertionService ?? TextInsertionService()
        self.stats = stats
    }

    func rememberInsertionTarget() {
        insertionService.rememberFrontmostTarget()
    }

    func prewarmAudio() {
        guard Permissions.microphoneStatus == .authorized else { return }
        let audioRecorder = audioRecorder
        let microphone = preferences.microphonePreference
        Task.detached(priority: .utility) {
            do {
                _ = try audioRecorder.prewarm(microphone: microphone)
            } catch {
                QuillLogger.audio.debug("Audio prewarm skipped: \(error.localizedDescription)")
            }
        }
    }

    func start() {
        guard state.phase == .idle || isErrorPhase else { return }
        resetSessionState()
        insertionTarget = insertionService.captureTarget()
        state.resetTranscript()
        state.phase = .listening
        let generation = sessionGeneration

        connectionTask = Task { [weak self] in
            await self?.beginSession(generation: generation)
        }
    }

    func stop() {
        guard state.phase == .listening else { return }
        state.phase = .finalizing
        state.audioLevel = 0
        let generation = sessionGeneration
        audioRecorder.stop()

        // Audio callbacks use the main queue. Enqueuing the end marker on that same
        // queue guarantees every chunk produced before stop is handled first.
        DispatchQueue.main.async { [weak self] in
            self?.finishAudioInput(generation: generation)
        }
    }

    func toggle() {
        state.phase == .listening ? stop() : start()
    }

    func pasteLastTranscript() {
        guard !state.phase.isActive else { return }
        let transcript = state.lastTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else {
            fail("No recent transcript to paste.")
            return
        }

        resetSessionState()
        let target = insertionService.captureTarget()
        state.lastError = nil
        state.phase = .inserting
        let generation = sessionGeneration
        pasteTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.insertionService.insert(transcript, mode: .direct, target: target)
                guard generation == self.sessionGeneration else { return }
                self.finishAndReturnToIdle()
            } catch TextInsertionError.targetUnavailableCopiedToClipboard {
                guard generation == self.sessionGeneration else { return }
                self.fail(TextInsertionError.targetUnavailableCopiedToClipboard.localizedDescription)
            } catch {
                guard generation == self.sessionGeneration else { return }
                self.fail(error.localizedDescription)
            }
        }
    }

    @discardableResult
    func cancel() -> Bool {
        guard state.phase.isActive else { return false }
        audioRecorder.stop()
        let activeSession = session
        resetSessionState()
        if let activeSession { Task { await activeSession.disconnect() } }
        state.phase = .idle
        state.interimTranscript = ""
        return true
    }

    private var isErrorPhase: Bool {
        if case .error = state.phase { return true }
        return false
    }

    private func beginSession(generation: UUID) async {
        do {
            guard let apiKey = apiKeys.value(), !apiKey.isEmpty else {
                throw GeminiLiveError.server("Add your Gemini API key in Privacy & Access.")
            }

            let microphoneAllowed = await Permissions.requestMicrophoneAccess()
            guard microphoneAllowed else {
                throw AudioRecorderError.unavailableInput
            }
            guard generation == sessionGeneration, state.phase == .listening else {
                if generation == sessionGeneration, state.phase == .finalizing {
                    fail("Microphone setup finished after the shortcut was released. Hold the shortcut and try again.")
                }
                return
            }

            try audioRecorder.start(
                microphone: preferences.microphonePreference,
                onChunk: { [weak self] data in
                    DispatchQueue.main.async {
                        self?.receiveAudio(data, generation: generation)
                    }
                },
                onLevel: { [weak self] level in
                    DispatchQueue.main.async {
                        self?.receiveAudioLevel(level, generation: generation)
                    }
                },
                onError: { [weak self] error in
                    DispatchQueue.main.async {
                        guard let self, generation == self.sessionGeneration else { return }
                        self.fail(error.localizedDescription)
                    }
                }
            )

            let liveSession = GeminiLiveSession()
            session = liveSession
            let configuration = GeminiLiveSession.Configuration(
                apiKey: apiKey,
                model: preferences.model,
                transcriptionMode: preferences.transcriptionMode,
                languageCode: preferences.languageCode,
                vocabulary: preferences.vocabulary
            )
            usesHybridVoiceActivityDetection = configuration.usesHybridVoiceActivityDetection

            try await liveSession.connect(configuration: configuration) { [weak self] event in
                Task { @MainActor in self?.receive(event, generation: generation) }
            }
            guard generation == sessionGeneration else {
                await liveSession.disconnect()
                return
            }

            sessionConnected = true
            if !usesHybridVoiceActivityDetection,
               !liveSession.enqueueActivityStart() {
                throw GeminiLiveError.sendQueueFull
            }
            for chunk in pendingAudio {
                guard liveSession.enqueueAudio(chunk) else { throw GeminiLiveError.sendQueueFull }
            }
            pendingAudio.removeAll(keepingCapacity: true)
            pendingAudioBytes = 0

            // finishAudioInput is queued behind every audio callback on the main
            // queue. Only end here when that ordered marker has already run.
            if shouldEndWhenConnected {
                endAudioInput(on: liveSession)
            }
        } catch is CancellationError {
            return
        } catch {
            guard generation == sessionGeneration else { return }
            fail(friendlyMessage(for: error))
        }
    }

    private func receiveAudio(_ data: Data, generation: UUID) {
        guard generation == sessionGeneration,
              !completionGate.activityEnded,
              state.phase == .listening || state.phase == .finalizing else { return }

        if sessionConnected, let session {
            guard session.enqueueAudio(data) else {
                fail(GeminiLiveError.sendQueueFull.localizedDescription)
                return
            }
        } else {
            pendingAudio.append(data)
            pendingAudioBytes += data.count
            while pendingAudioBytes > Self.maximumBufferedAudioBytes, !pendingAudio.isEmpty {
                pendingAudioBytes -= pendingAudio.removeFirst().count
            }
        }
    }

    private func receiveAudioLevel(_ level: Double, generation: UUID) {
        guard generation == sessionGeneration, state.phase == .listening else { return }
        state.audioLevel = level
    }

    private func finishAudioInput(generation: UUID) {
        guard generation == sessionGeneration,
              state.phase == .finalizing,
              !completionGate.activityEnded else { return }
        guard sessionConnected, let session else {
            shouldEndWhenConnected = true
            return
        }
        endAudioInput(on: session)
    }

    private func endAudioInput(on session: GeminiLiveSession) {
        guard !completionGate.activityEnded else { return }
        let endWasQueued = usesHybridVoiceActivityDetection
            ? session.enqueueAudioStreamEnd()
            : session.enqueueActivityEnd()
        guard endWasQueued else {
            fail(GeminiLiveError.sendQueueFull.localizedDescription)
            return
        }
        completionGate.markActivityEnded()
        startFinalizationTimeout()
        // Hybrid VAD may have finalized earlier utterances while listening. Wait
        // for a fresh finalization event after audioStreamEnd before completing,
        // so the last utterance is not cut off.
        if !usesHybridVoiceActivityDetection, completionGate.isReady {
            scheduleCompletion(immediately: completionGate.canCompleteImmediately)
        }
    }

    private func receive(_ event: GeminiLiveSession.Event, generation: UUID) {
        guard generation == sessionGeneration,
              state.phase == .listening || state.phase == .finalizing else { return }

        switch event {
        case .interim(let text):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            state.interimTranscript = (finalSegments + (trimmed.isEmpty ? [] : [trimmed])).joined(separator: " ")
        case .final(let text):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            finalSegments.append(trimmed)
            state.interimTranscript = finalSegments.joined(separator: " ")
            completionGate.receiveFinalTranscript()
            scheduleCompletion(immediately: completionGate.canCompleteImmediately)
        case .turnComplete:
            guard state.phase == .finalizing else { return }
            completionGate.receiveTurnComplete()
            if completionGate.canCompleteImmediately {
                scheduleCompletion(immediately: true)
            }
        case .error(let message):
            fail(message)
        }
    }

    private func scheduleCompletion(immediately: Bool = false) {
        guard state.phase == .finalizing, completionGate.isReady else { return }
        completionTask?.cancel()
        let generation = sessionGeneration
        completionTask = Task { [weak self] in
            if !immediately {
                do {
                    try await Task.sleep(for: .milliseconds(300))
                } catch {
                    return
                }
            }
            guard let self, generation == self.sessionGeneration else { return }
            await self.completeTranscription()
        }
    }

    private func completeTranscription() async {
        // Multiple final events can race after the debounce. Claim completion
        // synchronously before disconnecting so only one task can ever insert.
        guard state.phase == .finalizing, completionGate.beginCompletion() else { return }
        state.phase = .inserting
        finalizationTimeoutTask?.cancel()
        // This method runs inside completionTask. Clear the stored handle without
        // cancelling the task that still has to disconnect and insert the text.
        completionTask = nil
        let transcript = finalSegments.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else {
            // A completed turn without a final segment means Gemini detected no
            // speech. There is nothing to insert, so end the session normally.
            finishAndReturnToIdle()
            return
        }

        let completedSession = session
        session = nil
        if let completedSession { await completedSession.disconnect() }

        do {
            try await insertionService.insert(
                transcript,
                mode: preferences.insertionMode,
                target: insertionTarget
            )
            recordCompletedTranscript(transcript)
            finishAndReturnToIdle()
        } catch TextInsertionError.targetUnavailableCopiedToClipboard {
            recordCompletedTranscript(transcript)
            fail(TextInsertionError.targetUnavailableCopiedToClipboard.localizedDescription)
        } catch {
            fail(error.localizedDescription)
        }
    }

    private func recordCompletedTranscript(_ transcript: String) {
        state.lastTranscript = transcript
        stats.record(transcript: transcript)
        state.interimTranscript = ""
    }

    private func startFinalizationTimeout() {
        finalizationTimeoutTask?.cancel()
        let generation = sessionGeneration
        finalizationTimeoutTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(8))
            } catch {
                return
            }
            guard let self, generation == self.sessionGeneration else { return }
            self.fail("Transcription timed out. Check your connection and try again.")
        }
    }

    private func finishAndReturnToIdle() {
        let activeSession = session
        resetSessionState()
        if let activeSession { Task { await activeSession.disconnect() } }
        state.phase = .idle
    }

    private func fail(_ message: String) {
        audioRecorder.stop()
        let activeSession = session
        resetSessionState()
        if let activeSession { Task { await activeSession.disconnect() } }
        state.lastError = message
        state.audioLevel = 0
        state.phase = .error(message)

        let errorGeneration = sessionGeneration
        errorResetTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(4))
            } catch {
                return
            }
            guard let self,
                  errorGeneration == self.sessionGeneration,
                  case .error = self.state.phase else { return }
            self.state.phase = .idle
        }
    }

    private func resetSessionState() {
        connectionTask?.cancel()
        completionTask?.cancel()
        finalizationTimeoutTask?.cancel()
        errorResetTask?.cancel()
        pasteTask?.cancel()
        connectionTask = nil
        completionTask = nil
        finalizationTimeoutTask = nil
        errorResetTask = nil
        pasteTask = nil
        session = nil
        sessionConnected = false
        pendingAudio.removeAll(keepingCapacity: true)
        pendingAudioBytes = 0
        shouldEndWhenConnected = false
        usesHybridVoiceActivityDetection = false
        completionGate = TranscriptionCompletionGate()
        finalSegments.removeAll(keepingCapacity: true)
        insertionTarget = nil
        state.audioLevel = 0
        sessionGeneration = UUID()
    }

    private func friendlyMessage(for error: Error) -> String {
        if let recorderError = error as? AudioRecorderError, recorderError == .unavailableInput {
            return Permissions.microphoneStatus == .denied
                ? "Quill needs Microphone access. Open System Settings → Privacy & Security → Microphone."
                : recorderError.localizedDescription
        }
        return error.localizedDescription
    }
}
