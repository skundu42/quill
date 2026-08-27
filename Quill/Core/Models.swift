import AppKit
import Carbon
import Foundation

enum DictationPhase: Equatable {
    case idle
    case listening
    case finalizing
    case inserting
    case error(String)

    var title: String {
        switch self {
        case .idle: "Ready"
        case .listening: "Listening"
        case .finalizing: "Polishing"
        case .inserting: "Inserting"
        case .error(let message): message
        }
    }

    var menuBarSymbol: String {
        switch self {
        case .idle: "pencil.tip"
        case .listening: "waveform"
        case .finalizing, .inserting: "ellipsis"
        case .error: "exclamationmark.triangle.fill"
        }
    }

    var isActive: Bool {
        switch self {
        case .listening, .finalizing, .inserting: true
        case .idle, .error: false
        }
    }
}

enum TranscriptionMode: String, CaseIterable, Identifiable {
    case smart = "SMART"
    case verbatim = "VERBATIM"

    var id: String { rawValue }
    var title: String { self == .smart ? "Smart" : "Verbatim" }
}

enum InsertionMode: String, CaseIterable, Identifiable {
    case direct
    case clipboard

    var id: String { rawValue }
    var title: String { self == .direct ? "Type directly" : "Copy to clipboard" }
}

enum DictationMode: String, CaseIterable, Identifiable {
    case pushToTalk
    case toggle

    var id: String { rawValue }
    var title: String { self == .pushToTalk ? "Hold to speak" : "Press to start / stop" }
}

struct ShortcutModifiers: OptionSet, Codable, Hashable {
    let rawValue: UInt32

    static let command = ShortcutModifiers(rawValue: 1 << 0)
    static let option = ShortcutModifiers(rawValue: 1 << 1)
    static let control = ShortcutModifiers(rawValue: 1 << 2)
    static let shift = ShortcutModifiers(rawValue: 1 << 3)

    static let allowed: ShortcutModifiers = [.command, .option, .control, .shift]

    init(rawValue: UInt32) {
        self.rawValue = rawValue & 0x0F
    }

    init(from decoder: Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(UInt32.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    init(eventFlags: NSEvent.ModifierFlags) {
        var value: ShortcutModifiers = []
        if eventFlags.contains(.command) { value.insert(.command) }
        if eventFlags.contains(.option) { value.insert(.option) }
        if eventFlags.contains(.control) { value.insert(.control) }
        if eventFlags.contains(.shift) { value.insert(.shift) }
        self = value
    }

    var carbonValue: UInt32 {
        var value: UInt32 = 0
        if contains(.command) { value |= UInt32(cmdKey) }
        if contains(.option) { value |= UInt32(optionKey) }
        if contains(.control) { value |= UInt32(controlKey) }
        if contains(.shift) { value |= UInt32(shiftKey) }
        return value
    }

    var eventFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if contains(.command) { flags.insert(.command) }
        if contains(.option) { flags.insert(.option) }
        if contains(.control) { flags.insert(.control) }
        if contains(.shift) { flags.insert(.shift) }
        return flags
    }

    var title: String {
        var value = ""
        if contains(.control) { value += "⌃" }
        if contains(.option) { value += "⌥" }
        if contains(.shift) { value += "⇧" }
        if contains(.command) { value += "⌘" }
        return value
    }
}

struct KeyboardShortcut: Codable, Equatable, Hashable {
    let keyCode: UInt32
    let modifiers: ShortcutModifiers

    static let defaultDictation = KeyboardShortcut(
        keyCode: UInt32(kVK_Space),
        modifiers: [.option]
    )
    static let defaultPasteLast = KeyboardShortcut(
        keyCode: UInt32(kVK_ANSI_V),
        modifiers: [.control, .option]
    )

    init(keyCode: UInt32, modifiers: ShortcutModifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    init?(event: NSEvent) {
        let modifiers = ShortcutModifiers(eventFlags: event.modifierFlags)
        guard !modifiers.isEmpty,
              !Self.unassignableKeyCodes.contains(event.keyCode) else { return nil }
        self.init(keyCode: UInt32(event.keyCode), modifiers: modifiers)
    }

    var isValid: Bool {
        keyCode <= UInt32(UInt16.max)
            && !modifiers.isEmpty
            && !Self.unassignableKeyCodes.contains(UInt16(keyCode))
    }

    var title: String {
        "\(modifiers.title) \(keyTitle)"
    }

    var menuKeyEquivalent: String? {
        if let functionKeyEquivalent { return functionKeyEquivalent }
        return switch Int(keyCode) {
        case kVK_Space: " "
        case kVK_Return: "\r"
        case kVK_Tab: "\t"
        case kVK_Escape: "\u{1b}"
        case kVK_Delete: "\u{8}"
        case kVK_ForwardDelete: String(Character(UnicodeScalar(NSDeleteFunctionKey)!))
        case kVK_LeftArrow: String(Character(UnicodeScalar(NSLeftArrowFunctionKey)!))
        case kVK_RightArrow: String(Character(UnicodeScalar(NSRightArrowFunctionKey)!))
        case kVK_UpArrow: String(Character(UnicodeScalar(NSUpArrowFunctionKey)!))
        case kVK_DownArrow: String(Character(UnicodeScalar(NSDownArrowFunctionKey)!))
        default: translatedCharacter?.lowercased()
        }
    }

    private var keyTitle: String {
        if let functionKeyTitle { return functionKeyTitle }
        return switch Int(keyCode) {
        case kVK_Space: "Space"
        case kVK_Return: "↩"
        case kVK_Tab: "⇥"
        case kVK_Escape: "Esc"
        case kVK_Delete: "⌫"
        case kVK_ForwardDelete: "⌦"
        case kVK_LeftArrow: "←"
        case kVK_RightArrow: "→"
        case kVK_UpArrow: "↑"
        case kVK_DownArrow: "↓"
        case kVK_Home: "↖"
        case kVK_End: "↘"
        case kVK_PageUp: "⇞"
        case kVK_PageDown: "⇟"
        default: translatedCharacter?.uppercased() ?? "Key \(keyCode)"
        }
    }

    private var functionKeyTitle: String? {
        let functionKeys = [
            kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
            kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20
        ]
        guard let index = functionKeys.firstIndex(of: Int(keyCode)) else { return nil }
        return "F\(index + 1)"
    }

    private var functionKeyEquivalent: String? {
        let functionKeys: [Int] = [
            NSF1FunctionKey, NSF2FunctionKey, NSF3FunctionKey, NSF4FunctionKey, NSF5FunctionKey,
            NSF6FunctionKey, NSF7FunctionKey, NSF8FunctionKey, NSF9FunctionKey, NSF10FunctionKey,
            NSF11FunctionKey, NSF12FunctionKey, NSF13FunctionKey, NSF14FunctionKey, NSF15FunctionKey,
            NSF16FunctionKey, NSF17FunctionKey, NSF18FunctionKey, NSF19FunctionKey, NSF20FunctionKey
        ]
        guard let title = functionKeyTitle,
              let number = Int(title.dropFirst()),
              functionKeys.indices.contains(number - 1),
              let scalar = UnicodeScalar(functionKeys[number - 1]) else { return nil }
        return String(Character(scalar))
    }

    private var translatedCharacter: String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return fallbackCharacter
        }
        let data = unsafeBitCast(layoutData, to: CFData.self)
        guard let bytes = CFDataGetBytePtr(data) else { return fallbackCharacter }
        let layout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
        var deadKeyState: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 4)
        let status = UCKeyTranslate(
            layout,
            UInt16(keyCode),
            UInt16(kUCKeyActionDisplay),
            0,
            UInt32(LMGetKbdType()),
            OptionBits(kUCKeyTranslateNoDeadKeysBit),
            &deadKeyState,
            characters.count,
            &length,
            &characters
        )
        guard status == noErr, length > 0 else { return fallbackCharacter }
        return String(utf16CodeUnits: characters, count: length)
    }

    private var fallbackCharacter: String? {
        let ansi: [Int: String] = [
            kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D",
            kVK_ANSI_E: "E", kVK_ANSI_F: "F", kVK_ANSI_G: "G", kVK_ANSI_H: "H",
            kVK_ANSI_I: "I", kVK_ANSI_J: "J", kVK_ANSI_K: "K", kVK_ANSI_L: "L",
            kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O", kVK_ANSI_P: "P",
            kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
            kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X",
            kVK_ANSI_Y: "Y", kVK_ANSI_Z: "Z",
            kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3",
            kVK_ANSI_4: "4", kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7",
            kVK_ANSI_8: "8", kVK_ANSI_9: "9"
        ]
        return ansi[Int(keyCode)]
    }

    private static let unassignableKeyCodes: Set<UInt16> = [
        UInt16(kVK_Command), UInt16(kVK_RightCommand), UInt16(kVK_Shift), UInt16(kVK_RightShift),
        UInt16(kVK_Option), UInt16(kVK_RightOption), UInt16(kVK_Control), UInt16(kVK_RightControl),
        UInt16(kVK_Function), UInt16(kVK_CapsLock)
    ]
}

enum GlobalShortcutAction: UInt32, CaseIterable {
    case dictation = 1
    case pasteLast = 2
}

struct AudioInputDevice: Identifiable, Equatable, Hashable {
    let deviceID: UInt32
    let uid: String
    let name: String

    var id: String { uid }
}

struct MicrophonePreference: Codable, Equatable, Hashable {
    let uid: String
    let name: String
}

struct LanguageChoice: Identifiable, Hashable {
    let code: String
    let title: String
    var id: String { code }

    static let supported: [LanguageChoice] = [
        .init(code: "", title: "Detect automatically"),
        .init(code: "en-US", title: "English"),
        .init(code: "hi-IN", title: "Hindi"),
        .init(code: "bn-IN", title: "Bengali"),
        .init(code: "es-ES", title: "Spanish"),
        .init(code: "fr-FR", title: "French"),
        .init(code: "de-DE", title: "German"),
        .init(code: "ja-JP", title: "Japanese")
    ]
}
