import ApplicationServices
import XCTest
@testable import Quill

final class TextInsertionTargetTests: XCTestCase {
    func testRequiresOriginalElementAndFrontmostApplication() {
        let original = AXUIElementCreateApplication(100)
        let other = AXUIElementCreateApplication(200)
        let target = TextInsertionTarget(
            processIdentifier: 100,
            focusedElement: original,
            pasteEventClassification: nil
        )

        XCTAssertTrue(target.matches(processIdentifier: 100, focusedElement: original))
        XCTAssertFalse(target.matches(processIdentifier: 100, focusedElement: other))
        XCTAssertFalse(target.matches(processIdentifier: 200, focusedElement: original))
        XCTAssertFalse(target.matches(processIdentifier: nil, focusedElement: original))
        XCTAssertFalse(target.matches(processIdentifier: 100, focusedElement: nil))
        XCTAssertFalse(TextInsertionTarget(
            processIdentifier: 100,
            focusedElement: nil,
            pasteEventClassification: nil
        ).matches(processIdentifier: 100, focusedElement: original))
    }

    @MainActor
    func testCancelledInsertionStopsBeforeTouchingClipboardOrPermissions() async {
        let operation = Task { @MainActor in
            try await TextInsertionService().insert("Cancelled words", mode: .clipboard, target: nil)
        }
        operation.cancel()
        do {
            try await operation.value
            XCTFail("Cancelled insertion must throw before writing")
        } catch is CancellationError {
            // Cancellation is checked before clipboard and accessibility operations.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
