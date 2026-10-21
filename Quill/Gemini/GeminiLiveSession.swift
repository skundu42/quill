import Foundation

enum GeminiLiveError: LocalizedError {
    case invalidURL
    case invalidModel
    case connectionTimedOut
    case invalidResponse
    case sendQueueFull
    case server(String)
    case disconnected

    var errorDescription: String? {
        switch self {
        case .invalidURL: "Quill could not construct the Gemini connection URL."
        case .invalidModel: "Enter a Gemini model ID in Models, such as gemini-3.5-transcribe-live."
        case .connectionTimedOut: "Gemini took too long to start the live session. Check your connection and try again."
        case .invalidResponse: "Gemini returned an unreadable response."
        case .sendQueueFull: "The connection is too slow to keep up with your audio. Try again on a more stable connection."
        case .server(let message): message
        case .disconnected: "The Gemini live session disconnected."
        }
    }
}

enum GeminiOutboundMessage: Sendable, Equatable {
    case activityStart
    case audio(Data)
    case activityEnd
}

final class GeminiOutboundQueue: Sendable {
    let stream: AsyncStream<GeminiOutboundMessage>
    private let continuation: AsyncStream<GeminiOutboundMessage>.Continuation

    init(capacity: Int = 320) {
        precondition(capacity > 0)
        var continuation: AsyncStream<GeminiOutboundMessage>.Continuation!
        stream = AsyncStream(bufferingPolicy: .bufferingOldest(capacity)) {
            continuation = $0
        }
        self.continuation = continuation
    }

    @discardableResult
    func enqueue(_ message: GeminiOutboundMessage) -> Bool {
        switch continuation.yield(message) {
        case .enqueued: true
        case .dropped, .terminated: false
        @unknown default: false
        }
    }

    func finish() {
        continuation.finish()
    }
}

actor GeminiLiveSession {
    struct Configuration: Sendable {
        let apiKey: String
        let model: String
        let transcriptionMode: TranscriptionMode
        let languageCode: String
        let vocabulary: [String]

        var modelResource: String {
            let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.hasPrefix("models/") ? trimmed : "models/\(trimmed)"
        }
    }

    enum Event: Sendable, Equatable {
        case interim(String)
        case final(String)
        case turnComplete
        case error(String)
    }

    private let outboundQueue: GeminiOutboundQueue
    private var socket: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var sendTask: Task<Void, Never>?
    private var eventHandler: (@Sendable (Event) -> Void)?
    private var apiKey = ""

    init(outboundQueue: GeminiOutboundQueue = GeminiOutboundQueue()) {
        self.outboundQueue = outboundQueue
    }

    nonisolated func enqueueActivityStart() -> Bool {
        outboundQueue.enqueue(.activityStart)
    }

    nonisolated func enqueueAudio(_ data: Data) -> Bool {
        outboundQueue.enqueue(.audio(data))
    }

    nonisolated func enqueueActivityEnd() -> Bool {
        outboundQueue.enqueue(.activityEnd)
    }

    func connect(configuration: Configuration, onEvent: @escaping @Sendable (Event) -> Void) async throws {
        guard socket == nil else { throw GeminiLiveError.disconnected }
        guard configuration.modelResource != "models/" else { throw GeminiLiveError.invalidModel }
        eventHandler = onEvent
        apiKey = configuration.apiKey

        var components = URLComponents(string: "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent")
        components?.queryItems = [URLQueryItem(name: "key", value: configuration.apiKey)]
        guard let url = components?.url else { throw GeminiLiveError.invalidURL }

        let task = URLSession.shared.webSocketTask(with: url)
        socket = task
        task.resume()

        let setupDeadline = ContinuousClock.now.advanced(by: .seconds(8))
        let setupTimeoutTask = Task { [task] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            task.cancel(with: .goingAway, reason: Data("setup timeout".utf8))
        }
        defer { setupTimeoutTask.cancel() }

        do {
            try await sendJSON(Self.setupPayload(for: configuration))

            while true {
                let message = try await task.receive()
                let object = try Self.decode(message)
                if object["setupComplete"] != nil || object["setup_complete"] != nil {
                    break
                }
                if let errorMessage = Self.errorMessage(in: object) {
                    throw GeminiLiveError.server(errorMessage)
                }
            }
        } catch {
            let closeReason = task.closeReason
            let failure = Self.connectionError(for: error, closeReason: closeReason, apiKey: configuration.apiKey)
            disconnect()
            if Task.isCancelled { throw CancellationError() }
            if ContinuousClock.now >= setupDeadline,
               closeReason == nil || closeReason == Data("setup timeout".utf8) {
                throw GeminiLiveError.connectionTimedOut
            }
            throw failure
        }

        sendTask = Task { [weak self] in
            await self?.sendLoop()
        }
        receiveTask = Task { [weak self] in
            await self?.receiveLoop()
        }
    }

    func disconnect() {
        outboundQueue.finish()
        sendTask?.cancel()
        sendTask = nil
        receiveTask?.cancel()
        receiveTask = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        eventHandler = nil
        apiKey = ""
    }

    static func setupPayload(for configuration: Configuration) -> [String: Any] {
        var transcription: [String: Any] = [
            "mode": configuration.transcriptionMode.rawValue,
            "languageCodes": configuration.languageCode.isEmpty ? [] : [configuration.languageCode]
        ]
        if !configuration.vocabulary.isEmpty {
            transcription["customVocabulary"] = Array(configuration.vocabulary.prefix(1_000))
        }

        let setup: [String: Any] = [
            "model": configuration.modelResource,
            "generationConfig": ["responseModalities": ["TEXT"]],
            "inputAudioTranscription": transcription,
            // Both shortcut modes have explicit start/stop boundaries. Language
            // detection is independent of who controls those boundaries.
            "realtimeInputConfig": [
                "automaticActivityDetection": ["disabled": true]
            ]
        ]
        return ["setup": setup]
    }

    static func events(in object: [String: Any], apiKey: String = "") -> [Event] {
        if let errorMessage = errorMessage(in: object) {
            return [.error(serverMessage(errorMessage, apiKey: apiKey))]
        }

        guard let serverContent = (object["serverContent"] ?? object["server_content"]) as? [String: Any] else {
            return []
        }

        let interim = (serverContent["interimInputTranscription"] ?? serverContent["interim_input_transcription"]) as? [String: Any]
        let final = (serverContent["inputTranscription"] ?? serverContent["input_transcription"]) as? [String: Any]
        var events: [Event] = []

        if let text = interim?["text"] as? String, !text.isEmpty {
            events.append(.interim(text))
        }
        // The transcription service can acknowledge a silent turn with an empty
        // finalized transcript. Preserve that event so the controller can finish
        // the session without waiting for a turnComplete message that may not come.
        if let text = final?["text"] as? String {
            events.append(.final(text))
        }
        if (serverContent["turnComplete"] ?? serverContent["turn_complete"]) as? Bool == true {
            events.append(.turnComplete)
        }
        return events
    }

    private func sendLoop() async {
        do {
            for await message in outboundQueue.stream {
                try Task.checkCancellation()
                try await sendJSON(Self.payload(for: message))
            }
        } catch is CancellationError {
            return
        } catch {
            if !Task.isCancelled {
                failConnection(error)
            }
        }
    }

    private func receiveLoop() async {
        guard let socket else { return }
        do {
            while !Task.isCancelled {
                let message = try await socket.receive()
                let object = try Self.decode(message)
                for event in Self.events(in: object, apiKey: apiKey) {
                    eventHandler?(event)
                }
            }
        } catch is CancellationError {
            return
        } catch {
            if !Task.isCancelled {
                failConnection(error)
            }
        }
    }

    private func failConnection(_ error: Error) {
        guard let eventHandler else { return }
        let failure = Self.connectionError(for: error, closeReason: socket?.closeReason, apiKey: apiKey)
        disconnect()
        eventHandler(.error(failure.localizedDescription))
    }

    static func connectionError(for error: Error, closeReason: Data?, apiKey: String) -> GeminiLiveError {
        // URLSession often reports only "Socket is not connected" when Gemini
        // rejects a session. The WebSocket close frame contains the real cause.
        if let closeReason, let reason = String(data: closeReason, encoding: .utf8),
           !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .server(serverMessage(reason, apiKey: apiKey))
        }
        if let liveError = error as? GeminiLiveError {
            if case .server(let message) = liveError {
                return .server(serverMessage(message, apiKey: apiKey))
            }
            return liveError
        }
        return .server("Gemini connection failed: \(serverMessage(error.localizedDescription, apiKey: apiKey))")
    }

    private static func serverMessage(_ message: String, apiKey: String) -> String {
        var safeMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if !apiKey.isEmpty {
            safeMessage = safeMessage.replacingOccurrences(of: apiKey, with: "[redacted]")
        }
        if safeMessage.lowercased().contains("prepayment credits are depleted") {
            return "Gemini project credits are depleted. Add credits at https://ai.studio/projects or save an API key from a funded project in Models."
        }
        return safeMessage.isEmpty ? "Gemini rejected the live session." : safeMessage
    }

    private func sendJSON(_ object: [String: Any]) async throws {
        guard let socket else { throw GeminiLiveError.disconnected }
        let data = try JSONSerialization.data(withJSONObject: object)
        guard let string = String(data: data, encoding: .utf8) else { throw GeminiLiveError.invalidResponse }
        try await socket.send(.string(string))
    }

    static func payload(for message: GeminiOutboundMessage) -> [String: Any] {
        switch message {
        case .activityStart:
            ["realtimeInput": ["activityStart": [:]]]
        case .audio(let data):
            [
                "realtimeInput": [
                    "audio": [
                        "data": data.base64EncodedString(),
                        "mimeType": "audio/pcm;rate=16000"
                    ]
                ]
            ]
        case .activityEnd:
            ["realtimeInput": ["activityEnd": [:]]]
        }
    }

    private static func decode(_ message: URLSessionWebSocketTask.Message) throws -> [String: Any] {
        let data: Data
        switch message {
        case .data(let messageData): data = messageData
        case .string(let text): data = Data(text.utf8)
        @unknown default: throw GeminiLiveError.invalidResponse
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GeminiLiveError.invalidResponse
        }
        return object
    }

    private static func errorMessage(in object: [String: Any]) -> String? {
        guard let error = object["error"] as? [String: Any] else { return nil }
        return error["message"] as? String ?? "Gemini rejected the live session."
    }
}
