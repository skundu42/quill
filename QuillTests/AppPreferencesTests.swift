import XCTest
import Carbon
@testable import Quill

@MainActor
final class AppPreferencesTests: XCTestCase {
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
