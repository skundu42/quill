import AppKit
import Foundation

@MainActor
final class DictationController {
    private let state: AppState
    private let preferences: AppPreferences
    private let apiKeys: LocalAPIKeyStore
    private let audioRecorder: AudioRecorder
    private let insertionService: TextInsertionService
    private let stats: LocalStatsStore

    private var session: GeminiLiveSession?
    private var sessionConnected = false
    private var pendingAudio: [Data] = []
    private var shouldEndWhenConnected = false
    private var finalSegments: [String] = []
    private var connectionTask: Task<Void, Never>?
    private var completionTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var sessionGeneration = UUID()
    private var insertionTarget: TextInsertionTarget?

    init(
        state: AppState,
        preferences: AppPreferences,
        stats: LocalStatsStore,
        apiKeys: LocalAPIKeyStore,
        audioRecorder: AudioRecorder = AudioRecorder(),
        insertionService: TextInsertionService? = nil
    ) {
        self.state = state
        self.preferences = preferences
        self.apiKeys = apiKeys
        self.audioRecorder = audioRecorder
        self.insertionService = insertionService ?? TextInsertionService()
        self.stats = stats
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
        audioRecorder.stop()

        if sessionConnected, let session {
            Task { [weak self] in
                do {
                    try await session.sendActivityEnd()
                    await MainActor.run {
                        self?.startFinalizationTimeout()
                        if self?.finalSegments.isEmpty == false { self?.scheduleCompletion() }
                    }
                } catch {
                    await MainActor.run { self?.fail(error.localizedDescription) }
                }
            }
        } else {
            shouldEndWhenConnected = true
        }
    }

    func toggle() {
        state.phase == .listening ? stop() : start()
    }

    func cancel() {
        guard state.phase.isActive else { return }
        audioRecorder.stop()
        connectionTask?.cancel()
        completionTask?.cancel()
        timeoutTask?.cancel()
        if let session { Task { await session.disconnect() } }
        resetSessionState()
        state.phase = .idle
        state.interimTranscript = ""
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
                if state.phase == .finalizing {
                    fail("Microphone setup finished after the shortcut was released. Hold the shortcut and try again.")
                }
                return
            }

            try audioRecorder.start(
                onChunk: { [weak self] data in
                    Task { @MainActor in self?.receiveAudio(data, generation: generation) }
                },
                onLevel: { [weak self] level in
                    Task { @MainActor in self?.receiveAudioLevel(level, generation: generation) }
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

            try await liveSession.connect(configuration: configuration) { [weak self] event in
                Task { @MainActor in self?.receive(event, generation: generation) }
            }
            guard generation == sessionGeneration else {
                await liveSession.disconnect()
                return
            }

            sessionConnected = true
            try await liveSession.sendActivityStart()
            for chunk in pendingAudio {
                try await liveSession.sendAudio(chunk)
            }
            pendingAudio.removeAll(keepingCapacity: true)

            if shouldEndWhenConnected || state.phase == .finalizing {
                try await liveSession.sendActivityEnd()
                startFinalizationTimeout()
                if !finalSegments.isEmpty { scheduleCompletion() }
            }
        } catch is CancellationError {
            return
        } catch {
            fail(friendlyMessage(for: error))
        }
    }

    private func receiveAudio(_ data: Data, generation: UUID) {
        guard generation == sessionGeneration, state.phase == .listening || state.phase == .finalizing else { return }
        if sessionConnected, let session {
            Task { [weak self] in
                do {
                    try await session.sendAudio(data)
                } catch {
                    await MainActor.run { self?.fail(error.localizedDescription) }
                }
            }
        } else {
            pendingAudio.append(data)
            let maximumBufferedBytes = 16_000 * 2 * 30
            while pendingAudio.reduce(0, { $0 + $1.count }) > maximumBufferedBytes {
                pendingAudio.removeFirst()
            }
        }
    }

    private func receiveAudioLevel(_ level: Double, generation: UUID) {
        guard generation == sessionGeneration, state.phase == .listening else { return }
        state.audioLevel = level
    }

    private func receive(_ event: GeminiLiveSession.Event, generation: UUID) {
        guard generation == sessionGeneration else { return }
        switch event {
        case .interim(let text):
            state.interimTranscript = text
        case .final(let text):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            finalSegments.append(trimmed)
            state.interimTranscript = finalSegments.joined(separator: " ")
            scheduleCompletion()
        case .error(let message):
            fail(message)
        }
    }

    private func scheduleCompletion() {
        guard state.phase == .finalizing else { return }
        completionTask?.cancel()
        completionTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await self?.completeTranscription()
        }
    }

    private func completeTranscription() async {
        timeoutTask?.cancel()
        let transcript = finalSegments.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else {
            fail("Gemini did not return a transcript. Try speaking again.")
            return
        }

        state.phase = .inserting
        do {
            try await insertionService.insert(
                transcript,
                mode: preferences.insertionMode,
                target: insertionTarget
            )
            state.lastTranscript = transcript
            stats.record(transcript: transcript)
            state.interimTranscript = ""
            finishAndReturnToIdle()
        } catch {
            fail(error.localizedDescription)
        }
    }

    private func startFinalizationTimeout() {
        timeoutTask?.cancel()
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            self?.fail("Transcription timed out. Check your connection and try again.")
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
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard let self, case .error = self.state.phase else { return }
            self.state.phase = .idle
        }
    }

    private func resetSessionState() {
        connectionTask?.cancel()
        completionTask?.cancel()
        timeoutTask?.cancel()
        connectionTask = nil
        completionTask = nil
        timeoutTask = nil
        session = nil
        sessionConnected = false
        pendingAudio.removeAll(keepingCapacity: true)
        shouldEndWhenConnected = false
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
