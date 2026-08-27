import AppKit
import Carbon
import SwiftUI

struct ShortcutRecorderControl: NSViewRepresentable {
    let shortcut: KeyboardShortcut
    let isEnabled: Bool
    let onRecord: (KeyboardShortcut) -> Void

    func makeNSView(context: Context) -> ShortcutRecorderButton {
        let button = ShortcutRecorderButton()
        button.onRecord = onRecord
        button.bezelStyle = .rounded
        button.setButtonType(.momentaryPushIn)
        button.alignment = .center
        button.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
        return button
    }

    func updateNSView(_ button: ShortcutRecorderButton, context: Context) {
        button.shortcut = shortcut
        button.onRecord = onRecord
        button.isEnabled = isEnabled
        if !isEnabled { button.cancelRecording() }
    }
}

final class ShortcutRecorderButton: NSButton {
    var shortcut: KeyboardShortcut = .defaultDictation {
        didSet { updateTitle() }
    }
    var onRecord: ((KeyboardShortcut) -> Void)?
    private var isRecording = false

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        beginRecording()
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        guard !event.isARepeat else { return }
        if event.keyCode == UInt16(kVK_Escape),
           ShortcutModifiers(eventFlags: event.modifierFlags).isEmpty {
            cancelRecording()
            return
        }
        guard let recorded = KeyboardShortcut(event: event) else {
            NSSound.beep()
            return
        }
        shortcut = recorded
        isRecording = false
        window?.makeFirstResponder(nil)
        onRecord?(recorded)
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        updateTitle()
        return super.resignFirstResponder()
    }

    func cancelRecording() {
        isRecording = false
        updateTitle()
        if window?.firstResponder === self {
            window?.makeFirstResponder(nil)
        }
    }

    private func beginRecording() {
        isRecording = true
        title = "Type shortcut…"
        window?.makeFirstResponder(self)
    }

    private func updateTitle() {
        title = isRecording ? "Type shortcut…" : shortcut.title
    }
}
