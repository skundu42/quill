import Combine
import Foundation
@preconcurrency import Sparkle

enum UpdateChannel: String, Equatable {
    case stable
    case releaseCandidate = "rc"
}

struct UpdateConfiguration: Equatable {
    static let userDefaultsKey = "updateChannel"

    let channel: UpdateChannel
    let feedURL: String?

    var allowedChannels: Set<String> {
        channel == .releaseCandidate ? [UpdateChannel.releaseCandidate.rawValue] : []
    }

    static func resolve(
        environment: [String: String],
        defaults: UserDefaults,
        releaseCandidateFeedURL: String?
    ) -> UpdateConfiguration {
        let requestedChannel = environment["QUILL_UPDATE_CHANNEL"]
            ?? defaults.string(forKey: userDefaultsKey)
        let channel: UpdateChannel = requestedChannel?.lowercased() == UpdateChannel.releaseCandidate.rawValue
            ? .releaseCandidate
            : .stable
        let explicitFeedURL = environment["QUILL_UPDATE_FEED"]?.nilIfEmpty

        return UpdateConfiguration(
            channel: channel,
            feedURL: explicitFeedURL ?? (channel == .releaseCandidate ? releaseCandidateFeedURL : nil)
        )
    }
}

@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    private let controller: SPUStandardUpdaterController
    private let feedDelegate: UpdateFeedDelegate
    private var canCheckObservation: NSKeyValueObservation?

    @Published private(set) var canCheckForUpdates = false
    @Published var automaticUpdatesEnabled = true {
        didSet {
            controller.updater.automaticallyChecksForUpdates = automaticUpdatesEnabled
            controller.updater.automaticallyDownloadsUpdates = automaticUpdatesEnabled
        }
    }

    var currentVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        guard let label = Bundle.main.object(forInfoDictionaryKey: "QuillReleaseLabel") as? String,
              !label.isEmpty else { return version }
        return "\(version) \(label)"
    }

    var lastUpdateCheck: Date? {
        controller.updater.lastUpdateCheckDate
    }

    private init() {
        let configuration = UpdateConfiguration.resolve(
            environment: ProcessInfo.processInfo.environment,
            defaults: .standard,
            releaseCandidateFeedURL: Bundle.main.object(forInfoDictionaryKey: "QuillRCFeedURL") as? String
        )
        feedDelegate = UpdateFeedDelegate(configuration: configuration)
        controller = SPUStandardUpdaterController(
            startingUpdater: Self.shouldStartUpdater(
                isRunningTests: ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil,
                environment: ProcessInfo.processInfo.environment
            ),
            updaterDelegate: feedDelegate,
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
            || environment["QUILL_UPDATE_CHANNEL"]?.lowercased() == UpdateChannel.releaseCandidate.rawValue
        #else
        return true
        #endif
    }
}

private final class UpdateFeedDelegate: NSObject, SPUUpdaterDelegate {
    private let configuration: UpdateConfiguration

    init(configuration: UpdateConfiguration) {
        self.configuration = configuration
    }

    func feedURLString(for updater: SPUUpdater) -> String? {
        configuration.feedURL
    }

    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        configuration.allowedChannels
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
