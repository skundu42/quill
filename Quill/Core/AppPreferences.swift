import Foundation
import ServiceManagement

@MainActor
final class AppPreferences: ObservableObject {
    static let shared = AppPreferences()

    private enum Key {
        static let onboardingComplete = "onboardingComplete"
        static let launchAtLogin = "launchAtLogin"
        static let showIndicator = "showIndicator"
        static let dictationMode = "dictationMode"
        static let transcriptionMode = "transcriptionMode"
        static let insertionMode = "insertionMode"
        static let shortcut = "shortcut"
        static let languageCode = "languageCode"
        static let vocabulary = "vocabulary"
        static let model = "model"
    }

    private let defaults: UserDefaults

    @Published var onboardingComplete: Bool { didSet { defaults.set(onboardingComplete, forKey: Key.onboardingComplete) } }
    @Published var launchAtLogin: Bool { didSet { defaults.set(launchAtLogin, forKey: Key.launchAtLogin) } }
    @Published var showIndicator: Bool { didSet { defaults.set(showIndicator, forKey: Key.showIndicator) } }
    @Published var dictationMode: DictationMode { didSet { defaults.set(dictationMode.rawValue, forKey: Key.dictationMode) } }
    @Published var transcriptionMode: TranscriptionMode { didSet { defaults.set(transcriptionMode.rawValue, forKey: Key.transcriptionMode) } }
    @Published var insertionMode: InsertionMode { didSet { defaults.set(insertionMode.rawValue, forKey: Key.insertionMode) } }
    @Published var shortcut: ShortcutPreset { didSet { defaults.set(shortcut.rawValue, forKey: Key.shortcut) } }
    @Published var languageCode: String { didSet { defaults.set(languageCode, forKey: Key.languageCode) } }
    @Published var vocabulary: [String] { didSet { defaults.set(vocabulary, forKey: Key.vocabulary) } }
    @Published var model: String { didSet { defaults.set(model, forKey: Key.model) } }
    @Published var launchAtLoginError: String?

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        onboardingComplete = defaults.bool(forKey: Key.onboardingComplete)
        launchAtLogin = defaults.bool(forKey: Key.launchAtLogin)
        showIndicator = defaults.object(forKey: Key.showIndicator) as? Bool ?? true
        dictationMode = DictationMode(rawValue: defaults.string(forKey: Key.dictationMode) ?? "") ?? .pushToTalk
        transcriptionMode = TranscriptionMode(rawValue: defaults.string(forKey: Key.transcriptionMode) ?? "") ?? .smart
        insertionMode = InsertionMode(rawValue: defaults.string(forKey: Key.insertionMode) ?? "") ?? .direct
        shortcut = ShortcutPreset(rawValue: defaults.string(forKey: Key.shortcut) ?? "") ?? .optionSpace
        languageCode = defaults.string(forKey: Key.languageCode) ?? ""
        vocabulary = defaults.stringArray(forKey: Key.vocabulary) ?? ["Kubernetes", "PostgreSQL", "SwiftUI", "vLLM"]
        model = defaults.string(forKey: Key.model) ?? "gemini-3.5-transcribe-live"
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLogin = enabled
            launchAtLoginError = nil
        } catch {
            launchAtLogin = false
            launchAtLoginError = "Launch at login is available after Quill is moved to Applications."
        }
    }
}
