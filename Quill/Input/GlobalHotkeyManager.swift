import AppKit
import Carbon
import Foundation

enum GlobalHotkeyAction: Equatable {
    case press
    case release
    case toggle
    case ignore

    static func resolve(eventKind: UInt32, mode: DictationMode) -> GlobalHotkeyAction {
        switch mode {
        case .pushToTalk:
            if eventKind == UInt32(kEventHotKeyPressed) { return .press }
            if eventKind == UInt32(kEventHotKeyReleased) { return .release }
            return .ignore
        case .toggle:
            return eventKind == UInt32(kEventHotKeyPressed) ? .toggle : .ignore
        }
    }
}

@MainActor
final class GlobalHotkeyManager {
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    var onToggle: (() -> Void)?
    var onEscape: (() -> Bool)?

    private var eventHandlerRef: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?
    private var globalEscapeMonitor: Any?
    private var localEscapeMonitor: Any?
    private var dictationMode: DictationMode = .pushToTalk

    init() {
        installCarbonEventHandler()
        installEscapeMonitors()
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandlerRef { RemoveEventHandler(eventHandlerRef) }
        if let globalEscapeMonitor { NSEvent.removeMonitor(globalEscapeMonitor) }
        if let localEscapeMonitor { NSEvent.removeMonitor(localEscapeMonitor) }
    }

    func register(_ shortcut: ShortcutPreset, mode: DictationMode) {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        dictationMode = mode

        let signature = OSType(0x514C4C31) // QLL1
        let hotKeyID = EventHotKeyID(signature: signature, id: 1)
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        if status != noErr {
            QuillLogger.app.error("Unable to register global hotkey: \(status)")
        }
    }

    private func installCarbonEventHandler() {
        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]

        let handler: EventHandlerUPP = { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            let manager = Unmanaged<GlobalHotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            let kind = GetEventKind(event)
            Task { @MainActor in manager.handleHotkeyEvent(kind: kind) }
            return noErr
        }

        InstallEventHandler(
            GetApplicationEventTarget(),
            handler,
            eventTypes.count,
            &eventTypes,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )
    }

    private func handleHotkeyEvent(kind: UInt32) {
        switch GlobalHotkeyAction.resolve(eventKind: kind, mode: dictationMode) {
        case .press: onPress?()
        case .release: onRelease?()
        case .toggle: onToggle?()
        case .ignore: break
        }
    }

    private func installEscapeMonitors() {
        globalEscapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == UInt16(kVK_Escape) {
                Task { @MainActor in _ = self?.onEscape?() }
            }
        }
        localEscapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == UInt16(kVK_Escape), self?.onEscape?() == true {
                return nil
            }
            return event
        }
    }
}
