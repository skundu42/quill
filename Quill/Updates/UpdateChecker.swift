import Combine
import Foundation
@preconcurrency import Sparkle

@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    private let controller: SPUStandardUpdaterController
    private let feedOverride = FeedOverrideDelegate()
    private var canCheckObservation: NSKeyValueObservation?

    @Published private(set) var canCheckForUpdates = false
    @Published var automaticUpdatesEnabled = true {
        didSet {
            controller.updater.automaticallyChecksForUpdates = automaticUpdatesEnabled
            controller.updater.automaticallyDownloadsUpdates = automaticUpdatesEnabled
        }
    }

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    var lastUpdateCheck: Date? {
        controller.updater.lastUpdateCheckDate
    }

    private init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: Self.shouldStartUpdater(
                isRunningTests: ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil,
                environment: ProcessInfo.processInfo.environment
            ),
            updaterDelegate: feedOverride,
            userDriverDelegate: nil
        )
        automaticUpdatesEnabled = controller.updater.automaticallyChecksForUpdates
        canCheckObservation = controller.updater.observe(
            \.canCheckForUpdates,
            options: [.initial, .new]
        ) { [weak self] _, change in
            let canCheck = change.newValue ?? false
            Task { @MainActor in
                self?.canCheckForUpdates = canCheck
            }
        }
    }

    func checkManually() {
        guard canCheckForUpdates else { return }
        controller.checkForUpdates(nil)
    }

    nonisolated static func shouldStartUpdater(
        isRunningTests: Bool,
        environment: [String: String]
    ) -> Bool {
        guard !isRunningTests else { return false }
        #if DEBUG
        return environment["QUILL_UPDATE_FEED"] != nil
        #else
        return true
        #endif
    }
}

private final class FeedOverrideDelegate: NSObject, SPUUpdaterDelegate {
    func feedURLString(for updater: SPUUpdater) -> String? {
        ProcessInfo.processInfo.environment["QUILL_UPDATE_FEED"]
    }
}
