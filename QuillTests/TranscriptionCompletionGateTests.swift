import XCTest
@testable import Quill

final class TranscriptionCompletionGateTests: XCTestCase {
    func testDoesNotCompleteFromActivityEndAlone() {
        var gate = TranscriptionCompletionGate()

        gate.markActivityEnded()

        XCTAssertFalse(gate.isReady)
    }

    func testDoesNotCompleteFromTurnCompletionAlone() {
        var gate = TranscriptionCompletionGate()

        gate.receiveTurnComplete()

        XCTAssertFalse(gate.isReady)
    }

    func testCompletesOnlyAfterBothSignalsArrive() {
        var gate = TranscriptionCompletionGate()

        gate.receiveTurnComplete()
        gate.markActivityEnded()

        XCTAssertTrue(gate.isReady)
    }
}
