import AppKit
import ApplicationServices
import Foundation

enum TextInsertionError: LocalizedError {
    case accessibilityPermissionMissing
    case noFocusedElement
    case clipboardWriteFailed
    case targetUnavailableCopiedToClipboard

    var errorDescription: String? {
        switch self {
        case .accessibilityPermissionMissing: "Quill needs Accessibility access to type into other apps."
        case .noFocusedElement: "Quill could not find an editable text field."
        case .clipboardWriteFailed: "Quill could not write the transcript to the clipboard."
        case .targetUnavailableCopiedToClipboard: "The original text field is no longer available. Your transcript was copied to the clipboard."
        }
    }
}

struct TextInsertionTarget {
    let processIdentifier: pid_t
    let focusedElement: AXUIElement?
}

@MainActor
protocol TextInsertionServing: AnyObject {
    func rememberFrontmostTarget()
    func captureTarget() -> TextInsertionTarget?
    func insert(_ text: String, mode: InsertionMode, target: TextInsertionTarget?) async throws
}

@MainActor
final class TextInsertionService: TextInsertionServing {
    private var lastExternalTarget: TextInsertionTarget?

    func rememberFrontmostTarget() {
        _ = captureTarget()
    }

    func captureTarget() -> TextInsertionTarget? {
        guard let application = NSWorkspace.shared.frontmostApplication else { return nil }
        guard application.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return lastExternalTarget
        }

        let applicationElement = AXUIElementCreateApplication(application.processIdentifier)
        var focusedValue: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(
            applicationElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        )

        let focusedElement: AXUIElement?
        if status == .success,
           let focusedValue,
           CFGetTypeID(focusedValue) == AXUIElementGetTypeID() {
            focusedElement = unsafeBitCast(focusedValue, to: AXUIElement.self)
        } else {
            focusedElement = nil
        }
        let target = TextInsertionTarget(
            processIdentifier: application.processIdentifier,
            focusedElement: focusedElement
        )
        lastExternalTarget = target
        return target
    }

    func insert(_ text: String, mode: InsertionMode, target: TextInsertionTarget?) async throws {
        guard !text.isEmpty else { return }

        if mode == .clipboard {
            try copyToClipboard(text)
            return
        }

        guard AXIsProcessTrusted() || CGPreflightPostEventAccess() else {
            throw TextInsertionError.accessibilityPermissionMissing
        }

        guard let target,
              target.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let application = NSRunningApplication(processIdentifier: target.processIdentifier),
              !application.isTerminated else {
            try copyToClipboard(text)
            throw TextInsertionError.targetUnavailableCopiedToClipboard
        }

        if !application.isActive {
            guard application.activate(options: []) else {
                try copyToClipboard(text)
                throw TextInsertionError.targetUnavailableCopiedToClipboard
            }
            try await Task.sleep(for: .milliseconds(150))
        }

        let originalFocusStatus = target.focusedElement.map {
            AXUIElementSetAttributeValue(
                $0,
                kAXFocusedAttribute as CFString,
                kCFBooleanTrue
            )
        }
        let focusedElement = currentFocusedElement(for: target.processIdentifier)
            ?? (originalFocusStatus == .success ? target.focusedElement : nil)

        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier,
              let focusedElement else {
            try copyToClipboard(text)
            throw TextInsertionError.targetUnavailableCopiedToClipboard
        }

        try await Task.sleep(for: .milliseconds(50))
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier else {
            try copyToClipboard(text)
            throw TextInsertionError.targetUnavailableCopiedToClipboard
        }

        // Native controls reliably support replacing the selected text through
        // Accessibility. Web editors need a real paste event so their input model
        // receives the corresponding DOM event. Choose by the focused element's
        // accessibility hierarchy rather than by application identity.
        let usesPasteEvent = isInsideWebArea(focusedElement)
        QuillLogger.insertion.info(
            "Insertion path: \(usesPasteEvent ? "paste event" : "accessibility", privacy: .public)"
        )
        if !usesPasteEvent,
           AXUIElementSetAttributeValue(
               focusedElement,
               kAXSelectedTextAttribute as CFString,
               text as CFString
           ) == .success {
            return
        }
        try await pasteWithClipboardPreservation(text)
    }

    private func currentFocusedElement(for processIdentifier: pid_t) -> AXUIElement? {
        let applicationElement = AXUIElementCreateApplication(processIdentifier)
        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            applicationElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        ) == .success,
        let focusedValue,
        CFGetTypeID(focusedValue) == AXUIElementGetTypeID() else {
            return nil
        }
        return unsafeBitCast(focusedValue, to: AXUIElement.self)
    }

    private func isInsideWebArea(_ element: AXUIElement) -> Bool {
        var current: AXUIElement? = element
        // Bound the walk in case an application exposes a malformed hierarchy.
        for _ in 0..<24 {
            guard let node = current else { return false }
            if stringAttribute(kAXRoleAttribute as CFString, from: node) == "AXWebArea" {
                return true
            }

            var parentValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(
                node,
                kAXParentAttribute as CFString,
                &parentValue
            ) == .success,
            let parentValue,
            CFGetTypeID(parentValue) == AXUIElementGetTypeID() else {
                return false
            }
            current = unsafeBitCast(parentValue, to: AXUIElement.self)
        }
        return false
    }

    private func stringAttribute(_ attribute: CFString, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let value,
              CFGetTypeID(value) == CFStringGetTypeID() else {
            return nil
        }
        return value as? String
    }

    private func copyToClipboard(_ text: String) throws {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            throw TextInsertionError.clipboardWriteFailed
        }
    }

    private func pasteWithClipboardPreservation(_ text: String) async throws {
        let pasteboard = NSPasteboard.general
        let snapshot = snapshotPasteboard(pasteboard)

        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            restorePasteboard(snapshot, to: pasteboard)
            throw TextInsertionError.clipboardWriteFailed
        }

        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false) else {
            restorePasteboard(snapshot, to: pasteboard)
            try copyToClipboard(text)
            throw TextInsertionError.targetUnavailableCopiedToClipboard
        }
        keyDown.flags = .maskCommand
        // A command modifier on key-up makes some web editors treat both
        // events as paste commands. Clear it after the single command key-down.
        keyUp.flags = []
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
