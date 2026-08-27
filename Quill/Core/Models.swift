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

enum ShortcutPreset: String, CaseIterable, Identifiable {
    case optionSpace
    case controlSpace
    case commandShiftSpace

    var id: String { rawValue }

    var title: String {
        switch self {
        case .optionSpace: "⌥ Space"
        case .controlSpace: "⌃ Space"
        case .commandShiftSpace: "⇧⌘ Space"
        }
    }

    var keyCode: UInt32 { UInt32(kVK_Space) }

    var carbonModifiers: UInt32 {
        switch self {
        case .optionSpace: UInt32(optionKey)
        case .controlSpace: UInt32(controlKey)
        case .commandShiftSpace: UInt32(cmdKey | shiftKey)
        }
    }
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
