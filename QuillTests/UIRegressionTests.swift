import AppKit
import Carbon
import XCTest
@testable import Quill

@MainActor
final class UIRegressionTests: XCTestCase {
    func testAccessibilityPressStartsShortcutRecording() throws {
        let button = ShortcutRecorderButton()
        button.shortcut = .defaultDictation
        var recorded: KeyboardShortcut?
        button.onRecord = { recorded = $0 }

        _ = button.accessibilityPerformPress()
        XCTAssertEqual(button.title, "Type shortcut…")
        button.keyDown(with: try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [.command, .option],
            timestamp: 0, windowNumber: 0, context: nil,
            characters: "d", charactersIgnoringModifiers: "d",
            isARepeat: false, keyCode: UInt16(kVK_ANSI_D)
        )))
        XCTAssertEqual(recorded, KeyboardShortcut(keyCode: UInt32(kVK_ANSI_D), modifiers: [.command, .option]))
        XCTAssertEqual(button.title, recorded?.title)

        button.isEnabled = false
        button.performClick(nil)
        XCTAssertEqual(button.title, recorded?.title)
    }

    func testIndicatorRemainsVisibleAfterAnImmediateRestart() async throws {
        let suite = "UIRegressionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let preferences = AppPreferences(defaults: defaults)
        let state = AppState.shared
        let previousPhase = state.phase
        defer {
            state.phase = previousPhase
            defaults.removePersistentDomain(forName: suite)
        }
        state.phase = .idle
        let existingWindows = Set(NSApp.windows.map(\.windowNumber))
        let controller = DictationPillPanelController(state: state, preferences: preferences)
        let panel = try XCTUnwrap(NSApp.windows.first {
            $0 is NSPanel && !existingWindows.contains($0.windowNumber)
        })
        defer { panel.orderOut(nil) }

        state.phase = .listening
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertTrue(panel.isVisible)
        state.phase = .idle
        try await Task.sleep(for: .milliseconds(20))
        state.phase = .listening
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertTrue(panel.isVisible)
        XCTAssertEqual(state.phase, .listening)
        withExtendedLifetime(controller) {}
    }
}
