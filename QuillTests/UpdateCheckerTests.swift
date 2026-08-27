import XCTest
@testable import Quill

final class UpdateCheckerTests: XCTestCase {
    private let feedOverride = ["QUILL_UPDATE_FEED": "http://localhost:8000/appcast.xml"]

    func testUpdaterNeverStartsWhileHostingTests() {
        XCTAssertFalse(UpdateChecker.shouldStartUpdater(
            isRunningTests: true,
            environment: feedOverride
        ))
        XCTAssertFalse(UpdateChecker.shouldStartUpdater(
            isRunningTests: true,
            environment: [:]
        ))
    }

    #if DEBUG
    func testDebugBuildStaysInactiveWithoutFeedOverride() {
        XCTAssertFalse(UpdateChecker.shouldStartUpdater(
            isRunningTests: false,
            environment: [:]
        ))
    }

    func testDebugBuildCanUseExplicitFeedOverride() {
        XCTAssertTrue(UpdateChecker.shouldStartUpdater(
            isRunningTests: false,
            environment: feedOverride
        ))
    }
    #endif
}
