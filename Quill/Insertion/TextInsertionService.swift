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
    let pasteEventClassification: Task<Bool, Never>?

    func usesPasteEvent() async -> Bool {
        await pasteEventClassification?.value ?? false
    }
}

@MainActor
protocol TextInsertionServing: AnyObject {
    func rememberFrontmostTarget()
    func captureTarget() -> TextInsertionTarget?
    func insert(_ text: String, mode: InsertionMode, target: TextInsertionTarget?) async throws
}

@MainActor
final class TextInsertionService: TextInsertionServing {
    private typealias PasteboardSnapshot = [[NSPasteboard.PasteboardType: Data]]

    private struct PendingClipboardRestoration {
        let generation: UUID
        let snapshot: PasteboardSnapshot
        let transcriptChangeCount: Int
    }

    private var lastExternalTarget: TextInsertionTarget?
    private var pendingClipboardRestoration: PendingClipboardRestoration?
    private var clipboardRestorationTask: Task<Void, Never>?

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
        if let lastExternalTarget,
           lastExternalTarget.processIdentifier == application.processIdentifier,
           elementsAreEqual(lastExternalTarget.focusedElement, focusedElement) {
            return lastExternalTarget
        }

        let target = TextInsertionTarget(
            processIdentifier: application.processIdentifier,
            focusedElement: focusedElement,
            pasteEventClassification: focusedElement.map { element in
                Task.detached(priority: .userInitiated) {
                    Self.isInsideWebArea(element)
                }
            }
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

        var focusedElement = currentFocusedElement(for: target.processIdentifier)
        var restoredFocus = false
        if let originalElement = target.focusedElement,
           !elementsAreEqual(focusedElement, originalElement),
           AXUIElementSetAttributeValue(
               originalElement,
               kAXFocusedAttribute as CFString,
               kCFBooleanTrue
           ) == .success {
            focusedElement = originalElement
            restoredFocus = true
        }

        if restoredFocus {
            try await Task.sleep(for: .milliseconds(50))
            focusedElement = currentFocusedElement(for: target.processIdentifier) ?? focusedElement
        }

        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier,
              let focusedElement else {
            try copyToClipboard(text)
            throw TextInsertionError.targetUnavailableCopiedToClipboard
        }

        // Native controls reliably support replacing the selected text through
        // Accessibility. Web editors need a real paste event so their input model
        // receives the corresponding DOM event. The target's path is classified
        // when dictation starts so insertion does not synchronously walk the AX tree.
        let usesPasteEvent = await target.usesPasteEvent()
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
        try pasteWithClipboardPreservation(text)
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

    nonisolated private static func isInsideWebArea(_ element: AXUIElement) -> Bool {
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

    nonisolated private static func stringAttribute(_ attribute: CFString, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let value,
              CFGetTypeID(value) == CFStringGetTypeID() else {
            return nil
        }
        return value as? String
    }

    private func elementsAreEqual(_ lhs: AXUIElement?, _ rhs: AXUIElement?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): true
        case let (lhs?, rhs?): CFEqual(lhs, rhs)
        default: false
        }
    }

    private func copyToClipboard(_ text: String) throws {
        cancelPendingClipboardRestoration()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            throw TextInsertionError.clipboardWriteFailed
        }
    }

    private func pasteWithClipboardPreservation(_ text: String) throws {
        let pasteboard = NSPasteboard.general
        let snapshot: PasteboardSnapshot
        if let pendingClipboardRestoration,
           pasteboard.changeCount == pendingClipboardRestoration.transcriptChangeCount {
            snapshot = pendingClipboardRestoration.snapshot
        } else {
            snapshot = snapshotPasteboard(pasteboard)
        }
        cancelPendingClipboardRestoration()

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
        let generation = UUID()
        pendingClipboardRestoration = PendingClipboardRestoration(
            generation: generation,
            snapshot: snapshot,
            transcriptChangeCount: transcriptChangeCount
        )
        clipboardRestorationTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(350))
            } catch {
                return
            }
            self?.restoreClipboardIfUnchanged(generation: generation)
        }
    }

    private func restoreClipboardIfUnchanged(generation: UUID) {
        guard let pendingClipboardRestoration,
              pendingClipboardRestoration.generation == generation else { return }

        let pasteboard = NSPasteboard.general
        if pasteboard.changeCount == pendingClipboardRestoration.transcriptChangeCount {
            restorePasteboard(pendingClipboardRestoration.snapshot, to: pasteboard)
        }
        self.pendingClipboardRestoration = nil
        clipboardRestorationTask = nil
    }

    private func cancelPendingClipboardRestoration() {
        clipboardRestorationTask?.cancel()
        clipboardRestorationTask = nil
        pendingClipboardRestoration = nil
    }

    private func snapshotPasteboard(_ pasteboard: NSPasteboard) -> PasteboardSnapshot {
        (pasteboard.pasteboardItems ?? []).map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in
                item.data(forType: type).map { (type, $0) }
            })
        }
    }

    private func restorePasteboard(_ snapshot: PasteboardSnapshot, to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let items = snapshot.map { values -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in values { item.setData(data, forType: type) }
            return item
        }
        if !items.isEmpty { pasteboard.writeObjects(items) }
    }
}
