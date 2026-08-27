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

    func testSnakeCaseTurnCompletionIsRecognized() {
        let object: [String: Any] = [
            "server_content": ["turn_complete": true]
        ]

        XCTAssertEqual(GeminiLiveSession.events(in: object), [.turnComplete])
    }
}
