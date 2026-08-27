import XCTest
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
}
