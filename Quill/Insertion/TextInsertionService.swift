import AppKit
import ApplicationServices
import Foundation

enum TextInsertionError: LocalizedError {
    case accessibilityPermissionMissing
    case noFocusedElement
    case clipboardWriteFailed

    var errorDescription: String? {
        switch self {
        case .accessibilityPermissionMissing: "Quill needs Accessibility access to type into other apps."
        case .noFocusedElement: "Quill could not find an editable text field."
        case .clipboardWriteFailed: "Quill could not write the transcript to the clipboard."
        }
    }
}

struct TextInsertionTarget {
    let processIdentifier: pid_t
    let focusedElement: AXUIElement?
}

@MainActor
final class TextInsertionService {
    func captureTarget() -> TextInsertionTarget? {
        guard let application = NSWorkspace.shared.frontmostApplication else { return nil }

        let applicationElement = AXUIElementCreateApplication(application.processIdentifier)
        var focusedValue: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(
            applicationElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        )

        return TextInsertionTarget(
            processIdentifier: application.processIdentifier,
            focusedElement: status == .success ? focusedValue as! AXUIElement? : nil
        )
    }

    func insert(_ text: String, mode: InsertionMode, target: TextInsertionTarget?) async throws {
        guard !text.isEmpty else { return }

        if mode == .clipboard {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            guard pasteboard.setString(text, forType: .string) else {
                throw TextInsertionError.clipboardWriteFailed
            }
            return
        }

        guard AXIsProcessTrusted() || CGPreflightPostEventAccess() else {
            throw TextInsertionError.accessibilityPermissionMissing
        }

        var restoredApplication = false
        if let target,
           let application = NSRunningApplication(processIdentifier: target.processIdentifier),
           !application.isTerminated,
           !application.isActive {
            application.activate(options: [])
            restoredApplication = true
            try await Task.sleep(for: .milliseconds(150))
        }

        if let focusedElement = target?.focusedElement {
            AXUIElementSetAttributeValue(
                focusedElement,
                kAXFocusedAttribute as CFString,
                kCFBooleanTrue
            )
            if restoredApplication {
                try await Task.sleep(for: .milliseconds(50))
            }
        }
        try await pasteWithClipboardPreservation(text)
    }

    private func pasteWithClipboardPreservation(_ text: String) async throws {
        let pasteboard = NSPasteboard.general
        let snapshot = snapshotPasteboard(pasteboard)

        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            restorePasteboard(snapshot, to: pasteboard)
            throw TextInsertionError.clipboardWriteFailed
        }

        guard let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false) else {
            restorePasteboard(snapshot, to: pasteboard)
            throw TextInsertionError.noFocusedElement
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)

        let transcriptChangeCount = pasteboard.changeCount
        try await Task.sleep(for: .milliseconds(350))
        if pasteboard.changeCount == transcriptChangeCount {
            restorePasteboard(snapshot, to: pasteboard)
        }
    }

    private func snapshotPasteboard(_ pasteboard: NSPasteboard) -> [[NSPasteboard.PasteboardType: Data]] {
        (pasteboard.pasteboardItems ?? []).map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in
                item.data(forType: type).map { (type, $0) }
            })
        }
    }

    private func restorePasteboard(_ snapshot: [[NSPasteboard.PasteboardType: Data]], to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let items = snapshot.map { values -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in values { item.setData(data, forType: type) }
            return item
        }
        if !items.isEmpty { pasteboard.writeObjects(items) }
    }
}
