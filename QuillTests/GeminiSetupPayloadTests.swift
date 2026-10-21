import XCTest
@testable import Quill

final class GeminiSetupPayloadTests: XCTestCase {
    func testAutomaticLanguageUsesSmartTranscriptionAndManualActivityDetection() throws {
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

    func testLanguageHintUsesManualActivityDetection() throws {
        let configuration = GeminiLiveSession.Configuration(
            apiKey: "not-used-in-payload",
            model: "gemini-3.5-transcribe-live",
            transcriptionMode: .verbatim,
            languageCode: "hi-IN",
            vocabulary: []
        )

        let payload = GeminiLiveSession.setupPayload(for: configuration)
        let setup = try XCTUnwrap(payload["setup"] as? [String: Any])
        let transcription = try XCTUnwrap(setup["inputAudioTranscription"] as? [String: Any])
        XCTAssertEqual(transcription["languageCodes"] as? [String], ["hi-IN"])

        let realtime = try XCTUnwrap(setup["realtimeInputConfig"] as? [String: Any])
        let detection = try XCTUnwrap(realtime["automaticActivityDetection"] as? [String: Any])
        XCTAssertEqual(detection["disabled"] as? Bool, true)
    }

    func testModelResourceAcceptsBareAndFullyQualifiedIDsWithWhitespace() throws {
        for model in ["gemini-3.5-transcribe-live", "models/gemini-3.5-transcribe-live", " \nmodels/gemini-3.5-transcribe-live\t"] {
            let configuration = GeminiLiveSession.Configuration(
                apiKey: "not-used-in-payload",
                model: model,
                transcriptionMode: .smart,
                languageCode: "",
                vocabulary: []
            )
            let setup = try XCTUnwrap(GeminiLiveSession.setupPayload(for: configuration)["setup"] as? [String: Any])
            XCTAssertEqual(setup["model"] as? String, "models/gemini-3.5-transcribe-live")
        }
    }

    func testEmptyModelIsRejectedBeforeOpeningConnection() async {
        for model in ["", " \n", "models/", " models/ "] {
            let configuration = GeminiLiveSession.Configuration(
                apiKey: "not-a-real-key",
                model: model,
                transcriptionMode: .smart,
                languageCode: "",
                vocabulary: []
            )
            do {
                try await GeminiLiveSession().connect(configuration: configuration) { _ in
                    XCTFail("An invalid model must not open a connection.")
                }
                XCTFail("An invalid model must fail before connecting.")
            } catch GeminiLiveError.invalidModel {
                // Expected validation failure; no network request was made.
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }
}
