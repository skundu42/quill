import XCTest
@testable import Quill

final class GeminiSetupPayloadTests: XCTestCase {
    func testPushToTalkSetupUsesSmartTranscriptionAndManualActivityDetection() throws {
        let configuration = GeminiLiveSession.Configuration(
            apiKey: "not-used-in-payload",
            model: "gemini-3.5-transcribe-live",
            transcriptionMode: .smart,
            languageCode: "",
            vocabulary: ["SwiftUI", "Kubernetes"]
        )

        let payload = GeminiLiveSession.setupPayload(for: configuration)
        let setup = try XCTUnwrap(payload["setup"] as? [String: Any])
        XCTAssertEqual(setup["model"] as? String, "models/gemini-3.5-transcribe-live")

        let transcription = try XCTUnwrap(setup["inputAudioTranscription"] as? [String: Any])
        XCTAssertEqual(transcription["mode"] as? String, "SMART")
        XCTAssertEqual(transcription["languageCodes"] as? [String], [])
        XCTAssertEqual(transcription["customVocabulary"] as? [String], ["SwiftUI", "Kubernetes"])

        let realtime = try XCTUnwrap(setup["realtimeInputConfig"] as? [String: Any])
        let detection = try XCTUnwrap(realtime["automaticActivityDetection"] as? [String: Any])
        XCTAssertEqual(detection["disabled"] as? Bool, true)
    }
}
