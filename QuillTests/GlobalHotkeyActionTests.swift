import AppKit
import Carbon
import XCTest
@testable import Quill

final class GlobalHotkeyActionTests: XCTestCase {
    func testEscapeAcceptsHeldDictationModifiersWithoutInterceptingOtherShortcuts() throws {
        let custom = KeyboardShortcut(keyCode: UInt32(kVK_Space), modifiers: [.command, .option])
        let cases: [(NSEvent.ModifierFlags, DictationMode, KeyboardShortcut?, Bool)] = [
            (.option, .pushToTalk, .defaultDictation, true),
            ([.command, .option], .pushToTalk, custom, true),
            (.option, .pushToTalk, custom, true),
            ([], .toggle, .defaultDictation, true),
            (.option, .toggle, .defaultDictation, false),
            ([.command, .option], .pushToTalk, .defaultDictation, false),
            (.option, .pushToTalk, nil, false)
        ]
        for (flags, mode, shortcut, expected) in cases {
            let event = try XCTUnwrap(NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: flags,
                timestamp: 0, windowNumber: 0, context: nil,
                characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
                isARepeat: false, keyCode: UInt16(kVK_Escape)
            ))
            XCTAssertEqual(
                GlobalHotkeyAction.isEscapeCancellation(event, mode: mode, dictationShortcut: shortcut),
                expected,
                "flags=\(flags), mode=\(mode)"
            )
        }
    }

    func testPushToTalkRoutesPressAndReleaseSeparately() {
        XCTAssertEqual(
            GlobalHotkeyAction.resolve(eventKind: UInt32(kEventHotKeyPressed), mode: .pushToTalk),
            .press
        )
        XCTAssertEqual(
            GlobalHotkeyAction.resolve(eventKind: UInt32(kEventHotKeyReleased), mode: .pushToTalk),
            .release
        )
    }

    func testToggleModeUsesEveryPressAndIgnoresRelease() {
        XCTAssertEqual(
            GlobalHotkeyAction.resolve(eventKind: UInt32(kEventHotKeyPressed), mode: .toggle),
            .toggle
        )
        XCTAssertEqual(
            GlobalHotkeyAction.resolve(eventKind: UInt32(kEventHotKeyReleased), mode: .toggle),
            .ignore
        )
    }

    func testPasteLastUsesPressAndIgnoresRelease() {
        XCTAssertEqual(
            GlobalHotkeyAction.resolve(
                eventKind: UInt32(kEventHotKeyPressed),
                shortcutAction: .pasteLast,
                mode: .pushToTalk
            ),
            .pasteLast
        )
        XCTAssertEqual(
            GlobalHotkeyAction.resolve(
                eventKind: UInt32(kEventHotKeyReleased),
                shortcutAction: .pasteLast,
                mode: .toggle
            ),
            .ignore
        )
    }
}
