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
}
