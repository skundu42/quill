import XCTest
import Carbon
@testable import Quill

@MainActor
final class AppPreferencesTests: XCTestCase {
    func testFreshInstallUsesBarkAndPersistsProvider() {
        let suiteName = "AppPreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = AppPreferences(defaults: defaults)

        XCTAssertEqual(preferences.transcriptionProvider, .bark)
        XCTAssertEqual(defaults.string(forKey: "transcriptionProvider"), "bark")
        preferences.onboardingComplete = true
        XCTAssertEqual(AppPreferences(defaults: defaults).transcriptionProvider, .bark)
    }

    func testExistingInstallationKeepsGeminiAndCustomModel() {
        let suiteName = "AppPreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: "onboardingComplete")
        defaults.set("custom-gemini-model", forKey: "model")

        let preferences = AppPreferences(defaults: defaults)

        XCTAssertEqual(preferences.transcriptionProvider, .gemini)
        XCTAssertEqual(preferences.model, "custom-gemini-model")
        XCTAssertEqual(defaults.string(forKey: "transcriptionProvider"), "gemini")
    }

    func testSwitchingProvidersPreservesGeminiConfiguration() {
        let suiteName = "AppPreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = AppPreferences(defaults: defaults)
        preferences.transcriptionProvider = .gemini
        preferences.model = "custom-gemini-model"
        preferences.languageCode = "hi-IN"
        preferences.vocabulary = ["Quill"]
        preferences.transcriptionProvider = .bark

        let reloaded = AppPreferences(defaults: defaults)

        XCTAssertEqual(reloaded.transcriptionProvider, .bark)
        XCTAssertEqual(reloaded.model, "custom-gemini-model")
        XCTAssertEqual(reloaded.languageCode, "hi-IN")
        XCTAssertEqual(reloaded.vocabulary, ["Quill"])
        reloaded.transcriptionProvider = .gemini
        XCTAssertEqual(AppPreferences(defaults: defaults).transcriptionProvider, .gemini)
    }

    func testInvalidProviderUsesInstallationDefault() {
        let suiteName = "AppPreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("unknown-provider", forKey: "transcriptionProvider")
        XCTAssertEqual(AppPreferences(defaults: defaults).transcriptionProvider, .bark)

        defaults.set(true, forKey: "onboardingComplete")
        defaults.set("unknown-provider", forKey: "transcriptionProvider")
        XCTAssertEqual(AppPreferences(defaults: defaults).transcriptionProvider, .gemini)
    }

    func testFreshInstallStartsWithEmptyVocabulary() {
        let suiteName = "AppPreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = AppPreferences(defaults: defaults)

        XCTAssertTrue(preferences.vocabulary.isEmpty)
    }

    func testSavedVocabularyIsPreserved() {
        let suiteName = "AppPreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(["Quill", "Gemini"], forKey: "vocabulary")

        let preferences = AppPreferences(defaults: defaults)

        XCTAssertEqual(preferences.vocabulary, ["Quill", "Gemini"])
    }

    func testFreshInstallUsesShortcutAndMicrophoneDefaults() {
        let suiteName = "AppPreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = AppPreferences(defaults: defaults)

        XCTAssertEqual(preferences.dictationShortcut, .defaultDictation)
        XCTAssertEqual(preferences.pasteLastShortcut, .defaultPasteLast)
        XCTAssertNil(preferences.microphonePreference)
        XCTAssertNotNil(defaults.data(forKey: "dictationShortcut"))
        XCTAssertNotNil(defaults.data(forKey: "pasteLastShortcut"))
    }

    func testLegacyShortcutMigratesOnce() {
        let suiteName = "AppPreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("commandShiftSpace", forKey: "shortcut")

        let preferences = AppPreferences(defaults: defaults)

        XCTAssertEqual(
            preferences.dictationShortcut,
            KeyboardShortcut(keyCode: UInt32(kVK_Space), modifiers: [.command, .shift])
        )
        XCTAssertNil(defaults.object(forKey: "shortcut"))
    }

    func testMalformedShortcutDataUsesSafeDefaults() {
        let suiteName = "AppPreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(Data("not-json".utf8), forKey: "dictationShortcut")
        defaults.set(Data("not-json".utf8), forKey: "pasteLastShortcut")

        let preferences = AppPreferences(defaults: defaults)

        XCTAssertEqual(preferences.dictationShortcut, .defaultDictation)
        XCTAssertEqual(preferences.pasteLastShortcut, .defaultPasteLast)
    }

    func testCustomShortcutsAndMicrophonePersist() {
        let suiteName = "AppPreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let custom = KeyboardShortcut(keyCode: UInt32(kVK_ANSI_K), modifiers: [.command, .control])

        var preferences: AppPreferences? = AppPreferences(defaults: defaults)
        preferences?.dictationShortcut = custom
        preferences?.microphonePreference = MicrophonePreference(uid: "input-1", name: "Studio Mic")
        preferences = nil

        let reloaded = AppPreferences(defaults: defaults)
        XCTAssertEqual(reloaded.dictationShortcut, custom)
        XCTAssertEqual(
            reloaded.microphonePreference,
            MicrophonePreference(uid: "input-1", name: "Studio Mic")
        )
    }
}
