import Carbon
import XCTest
@testable import Quill

final class GlobalHotkeyActionTests: XCTestCase {
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
