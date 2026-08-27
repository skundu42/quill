import Carbon
import XCTest
@testable import Quill

final class KeyboardShortcutTests: XCTestCase {
    func testDefaultShortcutTitlesAndCarbonModifiers() {
        XCTAssertEqual(KeyboardShortcut.defaultDictation.title, "⌥ Space")
        XCTAssertEqual(KeyboardShortcut.defaultPasteLast.title, "⌃⌥ V")
        XCTAssertEqual(KeyboardShortcut.defaultDictation.modifiers.carbonValue, UInt32(optionKey))
        XCTAssertEqual(
            KeyboardShortcut.defaultPasteLast.modifiers.carbonValue,
            UInt32(controlKey | optionKey)
        )
    }

    func testShortcutRoundTripsThroughJSON() throws {
        let shortcut = KeyboardShortcut(
            keyCode: UInt32(kVK_ANSI_P),
            modifiers: [.command, .option, .shift]
        )

        let data = try JSONEncoder().encode(shortcut)
        let decoded = try JSONDecoder().decode(KeyboardShortcut.self, from: data)

        XCTAssertEqual(decoded, shortcut)
    }

    func testShortcutRequiresModifierAndNonModifierKey() {
        XCTAssertFalse(KeyboardShortcut(keyCode: UInt32(kVK_ANSI_A), modifiers: []).isValid)
        XCTAssertFalse(KeyboardShortcut(keyCode: UInt32(kVK_Command), modifiers: [.command]).isValid)
        XCTAssertTrue(KeyboardShortcut(keyCode: UInt32(kVK_Escape), modifiers: [.option]).isValid)
        XCTAssertTrue(KeyboardShortcut(keyCode: UInt32(kVK_F8), modifiers: [.control]).isValid)
    }
}
