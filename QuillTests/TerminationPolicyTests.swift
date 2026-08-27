import XCTest
@testable import Quill

final class TerminationPolicyTests: XCTestCase {
    func testNormalTerminationRequestKeepsMenuBarAppRunning() {
        let policy = TerminationPolicy()

        XCTAssertFalse(policy.shouldTerminate(updaterIsRelaunching: false))
    }

    func testStatusMenuQuitAllowsTermination() {
        var policy = TerminationPolicy()

        policy.requestStatusMenuQuit()

        XCTAssertTrue(policy.shouldTerminate(updaterIsRelaunching: false))
    }

    func testSparkleRelaunchAllowsTermination() {
        let policy = TerminationPolicy()

        XCTAssertTrue(policy.shouldTerminate(updaterIsRelaunching: true))
    }
}
