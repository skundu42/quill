import AppKit
import Carbon
import Foundation

enum GlobalHotkeyAction: Equatable {
    case press
    case release
    case toggle
    case pasteLast
    case ignore

    static func resolve(
        eventKind: UInt32,
        shortcutAction: GlobalShortcutAction = .dictation,
        mode: DictationMode
    ) -> GlobalHotkeyAction {
        if shortcutAction == .pasteLast {
            return eventKind == UInt32(kEventHotKeyPressed) ? .pasteLast : .ignore
        }

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

enum GlobalHotkeyRegistrationError: LocalizedError, Equatable {
    case duplicate
    case unavailable(OSStatus)

    var errorDescription: String? {
        switch self {
        case .duplicate:
            "That shortcut is already assigned to another Quill action."
        case .unavailable:
            "That shortcut is already in use by macOS or another app."
        }
    }
}

@MainActor
protocol GlobalShortcutRegistering: AnyObject {
    func register(_ shortcut: KeyboardShortcut, for action: GlobalShortcutAction) throws
}

@MainActor
final class GlobalHotkeyManager: GlobalShortcutRegistering {
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    var onToggle: (() -> Void)?
    var onPasteLast: (() -> Void)?
    var onEscape: (() -> Bool)?

    private struct Registration {
        let shortcut: KeyboardShortcut
        let reference: EventHotKeyRef
    }

    private var eventHandlerRef: EventHandlerRef?
    private var registrations: [GlobalShortcutAction: Registration] = [:]
    private var globalEscapeMonitor: Any?
    private var localEscapeMonitor: Any?
    private var dictationMode: DictationMode = .pushToTalk

    init() {
        installCarbonEventHandler()
        installEscapeMonitors()
    }

    deinit {
        for registration in registrations.values {
            UnregisterEventHotKey(registration.reference)
        }
        if let eventHandlerRef { RemoveEventHandler(eventHandlerRef) }
        if let globalEscapeMonitor { NSEvent.removeMonitor(globalEscapeMonitor) }
        if let localEscapeMonitor { NSEvent.removeMonitor(localEscapeMonitor) }
    }

    func setDictationMode(_ mode: DictationMode) {
        dictationMode = mode
    }

    func register(_ shortcut: KeyboardShortcut, for action: GlobalShortcutAction) throws {
        guard shortcut.isValid else {
            throw GlobalHotkeyRegistrationError.unavailable(OSStatus(paramErr))
        }
        if registrations.contains(where: { $0.key != action && $0.value.shortcut == shortcut }) {
            throw GlobalHotkeyRegistrationError.duplicate
        }
        if registrations[action]?.shortcut == shortcut { return }

        let previous = registrations.removeValue(forKey: action)
        if let previous { UnregisterEventHotKey(previous.reference) }

        do {
            registrations[action] = try makeRegistration(shortcut, for: action)
        } catch {
            if let previous {
                do {
                    registrations[action] = try makeRegistration(previous.shortcut, for: action)
                } catch {
                    QuillLogger.app.error("Unable to restore previous global hotkey: \(error.localizedDescription)")
                }
            }
            throw error
        }
    }

    private func makeRegistration(
        _ shortcut: KeyboardShortcut,
        for action: GlobalShortcutAction
    ) throws -> Registration {
        let signature = OSType(0x514C4C31) // QLL1
        let hotKeyID = EventHotKeyID(signature: signature, id: action.rawValue)
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers.carbonValue,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &reference
        )
        guard status == noErr, let reference else {
            QuillLogger.app.error("Unable to register global hotkey: \(status)")
            throw GlobalHotkeyRegistrationError.unavailable(status)
        }
        return Registration(shortcut: shortcut, reference: reference)
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
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard status == noErr, let action = GlobalShortcutAction(rawValue: hotKeyID.id) else {
                return OSStatus(eventNotHandledErr)
            }
            Task { @MainActor in manager.handleHotkeyEvent(kind: kind, action: action) }
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

    private func handleHotkeyEvent(kind: UInt32, action: GlobalShortcutAction) {
        switch GlobalHotkeyAction.resolve(eventKind: kind, shortcutAction: action, mode: dictationMode) {
        case .press: onPress?()
        case .release: onRelease?()
        case .toggle: onToggle?()
        case .pasteLast: onPasteLast?()
        case .ignore: break
        }
    }

    private func installEscapeMonitors() {
        globalEscapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == UInt16(kVK_Escape),
               ShortcutModifiers(eventFlags: event.modifierFlags).isEmpty {
                Task { @MainActor in _ = self?.onEscape?() }
            }
        }
        localEscapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == UInt16(kVK_Escape),
               ShortcutModifiers(eventFlags: event.modifierFlags).isEmpty,
               self?.onEscape?() == true {
                return nil
            }
            return event
        }
    }
}

@MainActor
final class ShortcutCoordinator: ObservableObject {
    @Published private(set) var dictationShortcut: KeyboardShortcut
    @Published private(set) var pasteLastShortcut: KeyboardShortcut
    @Published private(set) var dictationError: String?
    @Published private(set) var pasteLastError: String?

    private let preferences: AppPreferences
    private let registrar: any GlobalShortcutRegistering

    init(preferences: AppPreferences, registrar: any GlobalShortcutRegistering) {
        self.preferences = preferences
        self.registrar = registrar
        dictationShortcut = preferences.dictationShortcut
        pasteLastShortcut = preferences.pasteLastShortcut
    }

    func start() {
        registerStored(dictationShortcut, for: .dictation)
        registerStored(pasteLastShortcut, for: .pasteLast)
    }

    func update(_ shortcut: KeyboardShortcut, for action: GlobalShortcutAction) {
        guard shortcut.isValid else {
            setError("Use a key together with Command, Option, Control, or Shift.", for: action)
            return
        }
        let otherShortcut = action == .dictation ? pasteLastShortcut : dictationShortcut
        guard shortcut != otherShortcut else {
            setError(GlobalHotkeyRegistrationError.duplicate.localizedDescription, for: action)
            return
        }

        do {
            try registrar.register(shortcut, for: action)
            switch action {
            case .dictation:
                dictationShortcut = shortcut
                preferences.dictationShortcut = shortcut
                dictationError = nil
            case .pasteLast:
                pasteLastShortcut = shortcut
                preferences.pasteLastShortcut = shortcut
                pasteLastError = nil
            }
        } catch {
            setError(error.localizedDescription, for: action)
        }
    }

    func error(for action: GlobalShortcutAction) -> String? {
        action == .dictation ? dictationError : pasteLastError
    }

    private func registerStored(_ shortcut: KeyboardShortcut, for action: GlobalShortcutAction) {
        do {
            try registrar.register(shortcut, for: action)
            setError(nil, for: action)
        } catch {
            setError(error.localizedDescription, for: action)
        }
    }

    private func setError(_ message: String?, for action: GlobalShortcutAction) {
        switch action {
        case .dictation: dictationError = message
        case .pasteLast: pasteLastError = message
        }
    }
}
