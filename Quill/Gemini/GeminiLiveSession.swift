import Foundation

enum GeminiLiveError: LocalizedError {
    case invalidURL
    case missingSetupAcknowledgement
    case invalidResponse
    case server(String)
    case disconnected

    var errorDescription: String? {
        switch self {
        case .invalidURL: "Quill could not construct the Gemini connection URL."
        case .missingSetupAcknowledgement: "Gemini did not acknowledge the live session."
        case .invalidResponse: "Gemini returned an unreadable response."
        case .server(let message): message
        case .disconnected: "The Gemini live session disconnected."
        }
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

    enum Event: Sendable {
        case interim(String)
        case final(String)
        case error(String)
    }

    private var socket: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var eventHandler: (@Sendable (Event) -> Void)?

    func connect(configuration: Configuration, onEvent: @escaping @Sendable (Event) -> Void) async throws {
        disconnect()
        self.eventHandler = onEvent

        var components = URLComponents(string: "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent")
        components?.queryItems = [URLQueryItem(name: "key", value: configuration.apiKey)]
        guard let url = components?.url else { throw GeminiLiveError.invalidURL }

        let task = URLSession.shared.webSocketTask(with: url)
        socket = task
        task.resume()

        try await sendJSON(Self.setupPayload(for: configuration))

        var acknowledged = false
        for _ in 0..<3 {
            let message = try await task.receive()
            let object = try Self.decode(message)
            if object["setupComplete"] != nil || object["setup_complete"] != nil {
                acknowledged = true
                break
            }
            if let errorMessage = Self.errorMessage(in: object) {
                throw GeminiLiveError.server(errorMessage)
            }
        }
        guard acknowledged else { throw GeminiLiveError.missingSetupAcknowledgement }

        receiveTask = Task { [weak self] in
            await self?.receiveLoop()
        }
    }

    func sendActivityStart() async throws {
        try await sendJSON(["realtimeInput": ["activityStart": [:]]])
    }

    func sendAudio(_ data: Data) async throws {
        try await sendJSON([
            "realtimeInput": [
                "audio": [
                    "data": data.base64EncodedString(),
                    "mimeType": "audio/pcm;rate=16000"
                ]
            ]
        ])
    }

    func sendActivityEnd() async throws {
        try await sendJSON(["realtimeInput": ["activityEnd": [:]]])
    }

    func disconnect() {
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

    private func receiveLoop() async {
        guard let socket else { return }
        do {
            while !Task.isCancelled {
                let message = try await socket.receive()
                let object = try Self.decode(message)
                handle(object)
            }
        } catch is CancellationError {
            return
        } catch {
            if !Task.isCancelled {
                eventHandler?(.error(error.localizedDescription))
            }
        }
    }

    private func handle(_ object: [String: Any]) {
        if let errorMessage = Self.errorMessage(in: object) {
            eventHandler?(.error(errorMessage))
            return
        }

        let serverContent = (object["serverContent"] ?? object["server_content"]) as? [String: Any]
        let interim = (serverContent?["interimInputTranscription"] ?? serverContent?["interim_input_transcription"]) as? [String: Any]
        let final = (serverContent?["inputTranscription"] ?? serverContent?["input_transcription"]) as? [String: Any]

        if let text = interim?["text"] as? String, !text.isEmpty {
            eventHandler?(.interim(text))
        }
        if let text = final?["text"] as? String, !text.isEmpty {
            eventHandler?(.final(text))
        }
    }

    private func sendJSON(_ object: [String: Any]) async throws {
        guard let socket else { throw GeminiLiveError.disconnected }
        let data = try JSONSerialization.data(withJSONObject: object)
        guard let string = String(data: data, encoding: .utf8) else { throw GeminiLiveError.invalidResponse }
        try await socket.send(.string(string))
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
