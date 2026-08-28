import XCTest
@testable import Quill

final class TranscriptionCompletionGateTests: XCTestCase {
    func testDoesNotCompleteFromActivityEndAlone() {
        var gate = TranscriptionCompletionGate()

        gate.markActivityEnded()

        XCTAssertFalse(gate.isReady)
    }

    func testDoesNotCompleteFromFinalTranscriptAlone() {
        var gate = TranscriptionCompletionGate()

        gate.receiveFinalTranscript()

        XCTAssertFalse(gate.isReady)
    }

    func testCompletesWhenFinalTranscriptArrivesBeforeActivityEnd() {
        var gate = TranscriptionCompletionGate()

        gate.receiveFinalTranscript()
        gate.markActivityEnded()

        XCTAssertTrue(gate.isReady)
    }

    func testCompletesWhenActivityEndArrivesBeforeFinalTranscript() {
        var gate = TranscriptionCompletionGate()

        gate.markActivityEnded()
        gate.receiveFinalTranscript()

        XCTAssertTrue(gate.isReady)
    }

    func testCompletionCanOnlyBeginOnce() {
        var gate = TranscriptionCompletionGate()
        gate.markActivityEnded()
        gate.receiveFinalTranscript()

        XCTAssertTrue(gate.beginCompletion())
        XCTAssertFalse(gate.beginCompletion())
    }

    func testTurnCompleteEnablesImmediateCompletionWhenTranscriptIsReady() {
        var gate = TranscriptionCompletionGate()
        gate.markActivityEnded()
        gate.receiveFinalTranscript()

        XCTAssertFalse(gate.canCompleteImmediately)

        gate.receiveTurnComplete()

        XCTAssertTrue(gate.canCompleteImmediately)
    }

    func testTurnCompleteAloneCannotComplete() {
        var gate = TranscriptionCompletionGate()

        gate.receiveTurnComplete()

        XCTAssertFalse(gate.isReady)
        XCTAssertFalse(gate.canCompleteImmediately)
    }

    func testEmptyTurnCompletesAfterActivityEnds() {
        var gate = TranscriptionCompletionGate()
        gate.markActivityEnded()

        gate.receiveTurnComplete()

        XCTAssertTrue(gate.isReady)
        XCTAssertTrue(gate.canCompleteImmediately)
        XCTAssertTrue(gate.beginCompletion())
    }
}
