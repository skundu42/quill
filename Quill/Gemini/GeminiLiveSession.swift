import Foundation

enum GeminiLiveError: LocalizedError {
    case invalidURL
    case connectionTimedOut
    case invalidResponse
    case sendQueueFull
    case server(String)
    case disconnected

    var errorDescription: String? {
        switch self {
        case .invalidURL: "Quill could not construct the Gemini connection URL."
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
        eventHandler = onEvent

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
            if ContinuousClock.now >= setupDeadline {
                throw GeminiLiveError.connectionTimedOut
            }
            throw error
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
    }

    static func setupPayload(for configuration: Configuration) -> [String: Any] {
        var transcription: [String: Any] = [
            "mode": configuration.transcriptionMode.rawValue,
            "languageCodes": configuration.languageCode.isEmpty ? [] : [configuration.languageCode]
        ]
        if !configuration.vocabulary.isEmpty {
            transcription["customVocabulary"] = Array(configuration.vocabulary.prefix(1_000))
        }

        return [
            "setup": [
                "model": "models/\(configuration.model)",
                "generationConfig": ["responseModalities": ["TEXT"]],
                "inputAudioTranscription": transcription,
                "realtimeInputConfig": [
                    "automaticActivityDetection": ["disabled": true]
                ]
            ]
        ]
    }

    static func events(in object: [String: Any]) -> [Event] {
        if let errorMessage = errorMessage(in: object) {
            return [.error(errorMessage)]
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
        if let text = final?["text"] as? String, !text.isEmpty {
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
            failConnection(error.localizedDescription)
        }
    }

    private func receiveLoop() async {
        guard let socket else { return }
        do {
            while !Task.isCancelled {
                let message = try await socket.receive()
                let object = try Self.decode(message)
                for event in Self.events(in: object) {
                    eventHandler?(event)
                }
            }
        } catch is CancellationError {
            return
        } catch {
            if !Task.isCancelled {
                failConnection(error.localizedDescription)
            }
        }
    }

    private func failConnection(_ message: String) {
        guard let eventHandler else { return }
        self.eventHandler = nil
        outboundQueue.finish()
        receiveTask?.cancel()
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        eventHandler(.error(message))
    }

    private func sendJSON(_ object: [String: Any]) async throws {
        guard let socket else { throw GeminiLiveError.disconnected }
        let data = try JSONSerialization.data(withJSONObject: object)
        guard let string = String(data: data, encoding: .utf8) else { throw GeminiLiveError.invalidResponse }
        try await socket.send(.string(string))
    }

    private static func payload(for message: GeminiOutboundMessage) -> [String: Any] {
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
