import Carbon
import XCTest
@testable import Quill

@MainActor
final class ShortcutCoordinatorTests: XCTestCase {
    func testSuccessfulUpdateRegistersAndPersistsShortcut() {
        let context = makeContext()
        defer { context.defaults.removePersistentDomain(forName: context.suiteName) }
        let updated = KeyboardShortcut(keyCode: UInt32(kVK_ANSI_D), modifiers: [.command, .option])

        context.coordinator.start()
        context.coordinator.update(updated, for: .dictation)

        XCTAssertEqual(context.registrar.registrations[.dictation], updated)
        XCTAssertEqual(context.preferences.dictationShortcut, updated)
        XCTAssertNil(context.coordinator.dictationError)
    }

    func testDuplicateShortcutIsRejectedWithoutChangingStoredValue() {
        let context = makeContext()
        defer { context.defaults.removePersistentDomain(forName: context.suiteName) }
        let original = context.preferences.dictationShortcut

        context.coordinator.start()
        context.coordinator.update(context.preferences.pasteLastShortcut, for: .dictation)

        XCTAssertEqual(context.preferences.dictationShortcut, original)
        XCTAssertEqual(context.registrar.registrations[.dictation], original)
        XCTAssertNotNil(context.coordinator.dictationError)
    }

    func testRegistrationFailureKeepsPreviousShortcut() {
        let context = makeContext()
        defer { context.defaults.removePersistentDomain(forName: context.suiteName) }
        context.coordinator.start()
        let original = context.preferences.dictationShortcut
        let rejected = KeyboardShortcut(keyCode: UInt32(kVK_ANSI_R), modifiers: [.control, .shift])
        context.registrar.rejectedShortcut = rejected

        context.coordinator.update(rejected, for: .dictation)

        XCTAssertEqual(context.preferences.dictationShortcut, original)
        XCTAssertEqual(context.registrar.registrations[.dictation], original)
        XCTAssertEqual(
            context.coordinator.dictationError,
            GlobalHotkeyRegistrationError.unavailable(OSStatus(eventHotKeyExistsErr)).localizedDescription
        )
    }

    private func makeContext() -> (
        suiteName: String,
        defaults: UserDefaults,
        preferences: AppPreferences,
        registrar: FakeShortcutRegistrar,
        coordinator: ShortcutCoordinator
    ) {
        let suiteName = "ShortcutCoordinatorTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let preferences = AppPreferences(defaults: defaults)
        let registrar = FakeShortcutRegistrar()
        let coordinator = ShortcutCoordinator(preferences: preferences, registrar: registrar)
        return (suiteName, defaults, preferences, registrar, coordinator)
    }
}

@MainActor
private final class FakeShortcutRegistrar: GlobalShortcutRegistering {
    var registrations: [GlobalShortcutAction: KeyboardShortcut] = [:]
    var rejectedShortcut: KeyboardShortcut?

    func register(_ shortcut: KeyboardShortcut, for action: GlobalShortcutAction) throws {
        if shortcut == rejectedShortcut {
            throw GlobalHotkeyRegistrationError.unavailable(OSStatus(eventHotKeyExistsErr))
        }
        registrations[action] = shortcut
    }
}
