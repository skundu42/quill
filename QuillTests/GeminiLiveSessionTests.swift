import XCTest
@testable import Quill

final class GeminiLiveSessionTests: XCTestCase {
    func testOutboundQueuePreservesActivityAndAudioOrder() async {
        let queue = GeminiOutboundQueue(capacity: 3)
        let audio = Data([1, 2, 3])

        XCTAssertTrue(queue.enqueue(.activityStart))
        XCTAssertTrue(queue.enqueue(.audio(audio)))
        XCTAssertTrue(queue.enqueue(.activityEnd))
        queue.finish()

        var iterator = queue.stream.makeAsyncIterator()
        let first = await iterator.next()
        let second = await iterator.next()
        let third = await iterator.next()
        let end = await iterator.next()

        XCTAssertEqual(first, .activityStart)
        XCTAssertEqual(second, .audio(audio))
        XCTAssertEqual(third, .activityEnd)
        XCTAssertNil(end)
    }

    func testManualEndUsesActivityEndSignal() throws {
        let payload = GeminiLiveSession.payload(for: .activityEnd)
        let realtimeInput = try XCTUnwrap(payload["realtimeInput"] as? [String: Any])

        XCTAssertNotNil(realtimeInput["activityEnd"] as? [String: Any])
        XCTAssertNil(realtimeInput["audioStreamEnd"])
    }

    func testOutboundQueueRejectsMessagesBeyondItsBound() async {
        let queue = GeminiOutboundQueue(capacity: 1)

        XCTAssertTrue(queue.enqueue(.activityStart))
        XCTAssertFalse(queue.enqueue(.activityEnd))
        queue.finish()

        var iterator = queue.stream.makeAsyncIterator()
        let first = await iterator.next()
        let end = await iterator.next()
        XCTAssertEqual(first, .activityStart)
        XCTAssertNil(end)
    }

    func testFinalTranscriptIsEmittedBeforeTurnCompletionFromSameMessage() {
        let object: [String: Any] = [
            "serverContent": [
                "inputTranscription": ["text": "Final words"],
                "turnComplete": true
            ]
        ]

        XCTAssertEqual(
            GeminiLiveSession.events(in: object),
            [.final("Final words"), .turnComplete]
        )
    }

    func testFinalTranscriptDoesNotRequireTurnCompletion() {
        let object: [String: Any] = [
            "serverContent": [
                "inputTranscription": ["text": "Final words"]
            ]
        ]

        XCTAssertEqual(GeminiLiveSession.events(in: object), [.final("Final words")])
    }

    func testEmptyFinalTranscriptIsPreservedWithoutTurnCompletion() {
        let object: [String: Any] = [
            "serverContent": [
                "inputTranscription": ["text": ""]
            ]
        ]

        XCTAssertEqual(GeminiLiveSession.events(in: object), [.final("")])
    }

    func testSnakeCaseTurnCompletionIsRecognized() {
        let object: [String: Any] = [
            "server_content": ["turn_complete": true]
        ]

        XCTAssertEqual(GeminiLiveSession.events(in: object), [.turnComplete])
    }

    func testWebSocketCloseReasonTakesPrecedenceOverGenericTransportFailure() {
        let reason = "The configured model is not supported for live transcription."
        let error = GeminiLiveSession.connectionError(
            for: URLError(.networkConnectionLost),
            closeReason: Data(reason.utf8),
            apiKey: "secret"
        )

        XCTAssertEqual(error.localizedDescription, reason)
    }

    func testDepletedCreditsExplainHowToRestoreService() {
        // A WebSocket close reason is length-limited, so Google's URL/message
        // may be truncated even though its leading cause is intact.
        let reason = "Your prepayment credits are depleted. Please go to AI Studio at https://ai.studio/projects to manage your project and billi"
        let error = GeminiLiveSession.connectionError(
            for: URLError(.networkConnectionLost),
            closeReason: Data(reason.utf8),
            apiKey: "secret"
        )

        XCTAssertTrue(error.localizedDescription.contains("credits are depleted"))
        XCTAssertTrue(error.localizedDescription.contains("https://ai.studio/projects"))
        XCTAssertTrue(error.localizedDescription.contains("funded project"))
        XCTAssertEqual(GeminiLiveSession.events(in: ["error": ["message": reason]]), [.error(error.localizedDescription)])
    }

    func testErrorMessagesNeverExposeTheConfiguredAPIKey() {
        let key = "fake-api-key"
        let message = "Connection failed for wss://example.test?key=\(key)"
        let errors = [
            GeminiLiveSession.connectionError(for: URLError(.badServerResponse), closeReason: Data(message.utf8), apiKey: key),
            GeminiLiveSession.connectionError(for: GeminiLiveError.server(message), closeReason: nil, apiKey: key),
            GeminiLiveSession.connectionError(for: NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: message]), closeReason: nil, apiKey: key)
        ]
        for error in errors {
            XCTAssertFalse(error.localizedDescription.contains(key))
            XCTAssertTrue(error.localizedDescription.contains("[redacted]"))
        }
        XCTAssertEqual(GeminiLiveSession.events(in: ["error": ["message": message]], apiKey: key), [.error("Connection failed for wss://example.test?key=[redacted]")])
    }

    func testMissingOrUnreadableCloseReasonRetainsUsefulFallback() {
        for closeReason in [nil, Data(), Data(" \n".utf8), Data([0xFF])] as [Data?] {
            let error = GeminiLiveSession.connectionError(for: GeminiLiveError.invalidResponse, closeReason: closeReason, apiKey: "")
            XCTAssertEqual(error.localizedDescription, GeminiLiveError.invalidResponse.localizedDescription)
        }
    }
}
