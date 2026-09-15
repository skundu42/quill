import XCTest
@preconcurrency import Sparkle
@testable import Quill

final class UpdateCheckerTests: XCTestCase {
    private let feedOverride = ["QUILL_UPDATE_FEED": "http://localhost:8000/appcast.xml"]
    private let releaseCandidateFeedURL = "https://example.com/rc/appcast.xml"

    @MainActor
    func testAutomaticUpdatesReflectSparkleChangesWithoutOverwritingThem() async {
        let updater = TestUpdateSettings()
        let checker = UpdateChecker(controller: TestUpdaterController(settings: updater))
        XCTAssertTrue(checker.automaticUpdatesEnabled)
        await Task.yield() // Drain the initial canCheckForUpdates observation.

        let changed = expectation(description: "Sparkle preference change reaches SwiftUI")
        let observation = checker.objectWillChange.sink { changed.fulfill() }
        updater.automaticallyDownloadsUpdates = false
        await fulfillment(of: [changed], timeout: 1)
        observation.cancel()

        XCTAssertFalse(checker.automaticUpdatesEnabled)
        XCTAssertTrue(updater.automaticallyChecksForUpdates)
        XCTAssertFalse(updater.automaticallyDownloadsUpdates)

        checker.automaticUpdatesEnabled = true
        XCTAssertTrue(updater.automaticallyChecksForUpdates)
        XCTAssertTrue(updater.automaticallyDownloadsUpdates)
        updater.automaticallyChecksForUpdates = false
        XCTAssertFalse(checker.automaticUpdatesEnabled)
        XCTAssertTrue(updater.automaticallyDownloadsUpdates)
        checker.automaticUpdatesEnabled = false
        XCTAssertFalse(updater.automaticallyChecksForUpdates)
        XCTAssertFalse(updater.automaticallyDownloadsUpdates)
    }

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

@MainActor
private final class TestUpdaterController: SPUStandardUpdaterController {
    private let settings: SPUUpdater

    init(settings: SPUUpdater) {
        self.settings = settings
        super.init(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
    }

    override var updater: SPUUpdater { settings }
}

// Keep preference writes in memory so this check cannot change the user's defaults.
@MainActor
private final class TestUpdateSettings: SPUUpdater {
    private var checks = true
    private var downloads = true

    init() {
        super.init(
            hostBundle: .main,
            applicationBundle: .main,
            userDriver: SPUStandardUserDriver(hostBundle: .main, delegate: nil),
            delegate: nil
        )
    }

    override var automaticallyChecksForUpdates: Bool {
        get { checks }
        set {
            willChangeValue(forKey: "automaticallyChecksForUpdates")
            checks = newValue
            didChangeValue(forKey: "automaticallyChecksForUpdates")
        }
    }

    override var automaticallyDownloadsUpdates: Bool {
        get { downloads }
        set {
            willChangeValue(forKey: "automaticallyDownloadsUpdates")
            downloads = newValue
            didChangeValue(forKey: "automaticallyDownloadsUpdates")
        }
    }
}
