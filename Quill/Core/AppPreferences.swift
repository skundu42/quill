import Carbon
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
        static let legacyShortcut = "shortcut"
        static let dictationShortcut = "dictationShortcut"
        static let pasteLastShortcut = "pasteLastShortcut"
        static let microphonePreference = "microphonePreference"
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
    @Published var dictationShortcut: KeyboardShortcut { didSet { persist(dictationShortcut, forKey: Key.dictationShortcut) } }
    @Published var pasteLastShortcut: KeyboardShortcut { didSet { persist(pasteLastShortcut, forKey: Key.pasteLastShortcut) } }
    @Published var microphonePreference: MicrophonePreference? {
        didSet {
            if let microphonePreference {
                persist(microphonePreference, forKey: Key.microphonePreference)
            } else {
                defaults.removeObject(forKey: Key.microphonePreference)
            }
        }
    }
    @Published var languageCode: String { didSet { defaults.set(languageCode, forKey: Key.languageCode) } }
    @Published var vocabulary: [String] { didSet { defaults.set(vocabulary, forKey: Key.vocabulary) } }
    @Published var model: String { didSet { defaults.set(model, forKey: Key.model) } }
    @Published var launchAtLoginError: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        onboardingComplete = defaults.bool(forKey: Key.onboardingComplete)
        launchAtLogin = defaults.bool(forKey: Key.launchAtLogin)
        showIndicator = defaults.object(forKey: Key.showIndicator) as? Bool ?? true
        dictationMode = DictationMode(rawValue: defaults.string(forKey: Key.dictationMode) ?? "") ?? .pushToTalk
        transcriptionMode = TranscriptionMode(rawValue: defaults.string(forKey: Key.transcriptionMode) ?? "") ?? .smart
        insertionMode = InsertionMode(rawValue: defaults.string(forKey: Key.insertionMode) ?? "") ?? .direct
        dictationShortcut = Self.loadShortcut(
            defaults: defaults,
            key: Key.dictationShortcut,
            fallback: Self.legacyShortcut(from: defaults.string(forKey: Key.legacyShortcut))
        )
        pasteLastShortcut = Self.loadShortcut(
            defaults: defaults,
            key: Key.pasteLastShortcut,
            fallback: .defaultPasteLast
        )
        microphonePreference = Self.decode(MicrophonePreference.self, from: defaults.data(forKey: Key.microphonePreference))
        languageCode = defaults.string(forKey: Key.languageCode) ?? ""
        vocabulary = defaults.stringArray(forKey: Key.vocabulary) ?? []
        model = defaults.string(forKey: Key.model) ?? "gemini-3.5-transcribe-live"

        defaults.set(Self.encode(dictationShortcut), forKey: Key.dictationShortcut)
        defaults.set(Self.encode(pasteLastShortcut), forKey: Key.pasteLastShortcut)
        defaults.removeObject(forKey: Key.legacyShortcut)
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

    private func persist<T: Encodable>(_ value: T, forKey key: String) {
        defaults.set(Self.encode(value), forKey: key)
    }

    private static func loadShortcut(
        defaults: UserDefaults,
        key: String,
        fallback: KeyboardShortcut
    ) -> KeyboardShortcut {
        guard let shortcut = decode(KeyboardShortcut.self, from: defaults.data(forKey: key)),
              shortcut.isValid else { return fallback }
        return shortcut
    }

    private static func legacyShortcut(from rawValue: String?) -> KeyboardShortcut {
        switch rawValue {
        case "controlSpace":
            KeyboardShortcut(keyCode: UInt32(kVK_Space), modifiers: [.control])
        case "commandShiftSpace":
            KeyboardShortcut(keyCode: UInt32(kVK_Space), modifiers: [.command, .shift])
        default:
            .defaultDictation
        }
    }

    private static func encode<T: Encodable>(_ value: T) -> Data? {
        try? JSONEncoder().encode(value)
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data?) -> T? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
