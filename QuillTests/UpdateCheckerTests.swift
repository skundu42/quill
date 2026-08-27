import XCTest
@testable import Quill

final class UpdateCheckerTests: XCTestCase {
    private let feedOverride = ["QUILL_UPDATE_FEED": "http://localhost:8000/appcast.xml"]
    private let releaseCandidateFeedURL = "https://example.com/rc/appcast.xml"

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

    func testDebugBuildCanUseReleaseCandidateChannelOverride() {
        XCTAssertTrue(UpdateChecker.shouldStartUpdater(
            isRunningTests: false,
            environment: ["QUILL_UPDATE_CHANNEL": "rc"]
        ))
    }
    #endif

    func testStableChannelIsTheDefault() {
        let defaults = makeDefaults()

        let configuration = UpdateConfiguration.resolve(
            environment: [:],
            defaults: defaults,
            releaseCandidateFeedURL: releaseCandidateFeedURL
        )

        XCTAssertEqual(configuration.channel, .stable)
        XCTAssertNil(configuration.feedURL)
        XCTAssertEqual(configuration.allowedChannels, [])
    }

    func testReleaseCandidateChannelCanBeEnabledPersistently() {
        let defaults = makeDefaults()
        defaults.set("rc", forKey: UpdateConfiguration.userDefaultsKey)

        let configuration = UpdateConfiguration.resolve(
            environment: [:],
            defaults: defaults,
            releaseCandidateFeedURL: releaseCandidateFeedURL
        )

        XCTAssertEqual(configuration.channel, .releaseCandidate)
        XCTAssertEqual(configuration.feedURL, releaseCandidateFeedURL)
        XCTAssertEqual(configuration.allowedChannels, ["rc"])
    }

    func testReleaseCandidateChannelCanBeEnabledForOneLaunch() {
        let defaults = makeDefaults()

        let configuration = UpdateConfiguration.resolve(
            environment: ["QUILL_UPDATE_CHANNEL": "RC"],
            defaults: defaults,
            releaseCandidateFeedURL: releaseCandidateFeedURL
        )

        XCTAssertEqual(configuration.channel, .releaseCandidate)
        XCTAssertEqual(configuration.feedURL, releaseCandidateFeedURL)
        XCTAssertEqual(configuration.allowedChannels, ["rc"])
    }

    func testUnknownChannelFallsBackToStable() {
        let defaults = makeDefaults()
        defaults.set("nightly", forKey: UpdateConfiguration.userDefaultsKey)

        let configuration = UpdateConfiguration.resolve(
            environment: [:],
            defaults: defaults,
            releaseCandidateFeedURL: releaseCandidateFeedURL
        )

        XCTAssertEqual(configuration.channel, .stable)
        XCTAssertNil(configuration.feedURL)
        XCTAssertEqual(configuration.allowedChannels, [])
    }

    func testExplicitFeedTakesPrecedenceOverChannelFeed() {
        let defaults = makeDefaults()
        defaults.set("rc", forKey: UpdateConfiguration.userDefaultsKey)

        let configuration = UpdateConfiguration.resolve(
            environment: feedOverride,
            defaults: defaults,
            releaseCandidateFeedURL: releaseCandidateFeedURL
        )

        XCTAssertEqual(configuration.feedURL, feedOverride["QUILL_UPDATE_FEED"])
        XCTAssertEqual(configuration.allowedChannels, ["rc"])
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "UpdateCheckerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }
}
