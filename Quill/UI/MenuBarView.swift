import AppKit
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var preferences: AppPreferences
    let controller: DictationController

    var body: some View {
        Button {
            controller.toggle()
        } label: {
            Label(primaryActionTitle, systemImage: state.phase == .listening ? "stop.fill" : "mic.fill")
        }
        .keyboardShortcut(.space, modifiers: .option)

        Divider()

        LabeledContent("Status", value: state.phase.title)
        LabeledContent("Shortcut", value: preferences.shortcut.title)
        LabeledContent("Mode", value: preferences.transcriptionMode.title)

        if !state.lastTranscript.isEmpty {
            Divider()
            Button("Copy Recent Dictation") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(state.lastTranscript, forType: .string)
            }
        }

        if let error = state.lastError {
            Divider()
            Text(error)
        }

        Divider()

        SettingsLink {
            Text("Settings…")
        }
        .keyboardShortcut(",", modifiers: .command)

        Button("Quit Quill") { NSApp.terminate(nil) }
            .keyboardShortcut("q", modifiers: .command)
    }

    private var primaryActionTitle: String {
        switch state.phase {
        case .listening: "Stop Dictation"
        case .finalizing, .inserting: "Finishing…"
        case .idle, .error: "Start Dictation"
        }
    }
}
