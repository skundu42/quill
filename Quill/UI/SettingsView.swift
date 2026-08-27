import AppKit
import AVFoundation
import SwiftUI

struct SettingsView: View {
    @State private var selection: QuillDestination = .home
    let controller: DictationController

    var body: some View {
        HStack(spacing: 0) {
            QuillSidebar(selection: $selection)
                .frame(width: 188)

            Divider()

            Group {
                switch selection {
                case .home:
                    HomeView(controller: controller) { selection = .privacy }
                case .dictation:
                    DictationSettingsView()
                case .vocabulary:
                    VocabularyView()
                case .privacy:
                    PrivacyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .background(QuillBrand.ink)
    }
}

private enum QuillDestination: String, CaseIterable, Identifiable {
    case home = "Home"
    case dictation = "Dictation"
    case vocabulary = "Vocabulary"
    case privacy = "Privacy & Access"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .dictation: "waveform"
        case .vocabulary: "text.book.closed.fill"
        case .privacy: "lock.shield.fill"
        }
    }
}

private struct QuillSidebar: View {
    @Binding var selection: QuillDestination

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                QuillNibMark(color: QuillBrand.ink)
                    .padding(4)
                    .frame(width: 32, height: 32)
                    .background(QuillBrand.signal, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Quill")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                    Text("Voice to text")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.52))
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.top, 22)
            .padding(.bottom, 24)

            VStack(spacing: 5) {
                ForEach(QuillDestination.allCases) { destination in
                    Button {
                        selection = destination
                    } label: {
                        Label(destination.rawValue, systemImage: destination.symbol)
                            .font(.system(size: 13, weight: .semibold))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 11)
                            .frame(height: 38)
                            .foregroundStyle(selection == destination ? QuillBrand.ink : .white.opacity(0.72))
                            .background(
                                selection == destination ? QuillBrand.signal : Color.clear,
                                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selection == destination ? .isSelected : [])
                }
            }
            .padding(.horizontal, 10)

            Spacer()

            Text("Your stats stay on this Mac")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
                .padding(18)
        }
        .background(QuillBrand.ink)
    }
}

private struct HomeView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var preferences: AppPreferences
    @EnvironmentObject private var stats: LocalStatsStore
    @EnvironmentObject private var apiKeys: LocalAPIKeyStore
    let controller: DictationController
    let onOpenPrivacy: () -> Void

    var body: some View {
        QuillPage(title: "Good to have you here", subtitle: "Quill is ready wherever your cursor is.") {
            statusCard

            VStack(alignment: .leading, spacing: 10) {
                Text("ON THIS MAC")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    LocalStatCard(value: stats.todayDictations, label: "Dictations today", symbol: "mic.fill")
                    LocalStatCard(value: stats.todayWords, label: "Words today", symbol: "text.word.spacing")
                    LocalStatCard(value: stats.totalWords, label: "Words all time", symbol: "sum")
                }
            }

            recentCard
        }
        .onAppear { stats.refreshDay() }
    }

    private var statusCard: some View {
        HStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 13) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                        .shadow(color: statusColor.opacity(0.65), radius: 5)
                    Text(apiKeys.hasKey ? state.phase.title.uppercased() : "SETUP NEEDED")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(1.3)
                        .foregroundStyle(.white.opacity(0.62))
                }

                Text(statusHeadline)
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                HStack(spacing: 8) {
                    Text(preferences.shortcut.title)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 7))
                    Text(preferences.dictationMode == .pushToTalk ? "Hold to speak" : "Press to start and stop")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.58))
                }
            }

            Spacer(minLength: 12)

            InkLine(level: state.phase == .listening ? state.audioLevel : 0)
                .frame(width: 112, height: 42)

            Button(actionTitle) {
                apiKeys.hasKey ? controller.toggle() : onOpenPrivacy()
            }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(QuillBrand.signal)
                .foregroundStyle(QuillBrand.ink)
                .disabled(state.phase == .finalizing || state.phase == .inserting)
        }
        .padding(24)
        .background(QuillBrand.ink, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(QuillBrand.signal.opacity(0.82))
                .frame(height: 2)
                .padding(.horizontal, 22)
        }
    }

    private var recentCard: some View {
        QuillCard {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "quote.opening")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(QuillBrand.ink)
                    .frame(width: 34, height: 34)
                    .background(QuillBrand.signal, in: RoundedRectangle(cornerRadius: 9))

                VStack(alignment: .leading, spacing: 7) {
                    Text("Latest dictation")
                        .font(.headline)
                    Text(state.lastTranscript.isEmpty ? "Your latest dictation will appear here until Quill quits." : state.lastTranscript)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .textSelection(.enabled)
                }

                Spacer()

                if !state.lastTranscript.isEmpty {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(state.lastTranscript, forType: .string)
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                }
            }
        }
    }

    private var statusColor: Color {
        guard apiKeys.hasKey else { return .orange }
        if case .error = state.phase { return .orange }
        return state.phase == .idle ? QuillBrand.signal : .white
    }

    private var statusHeadline: String {
        guard apiKeys.hasKey else { return "Add your API key to start dictating" }
        return switch state.phase {
        case .idle: "Speak. Quill will write."
        case .listening: "Listening to you…"
        case .finalizing: "Polishing your words…"
        case .inserting: "Putting it at your cursor…"
        case .error: "Quill needs your attention"
        }
    }

    private var actionTitle: String {
        guard apiKeys.hasKey else { return "Add API key" }
        return state.phase == .listening ? "Stop" : "Start dictating"
    }
}

private struct DictationSettingsView: View {
    @EnvironmentObject private var preferences: AppPreferences

    var body: some View {
        QuillPage(title: "Dictation", subtitle: "Make Quill work the way you speak.") {
            QuillCard(title: "How you start") {
                QuillSettingRow(title: "Keyboard shortcut", detail: "Works from any app") {
                    Picker("", selection: $preferences.shortcut) {
                        ForEach(ShortcutPreset.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 150)
                }

                QuillDivider()

                QuillSettingRow(title: "Shortcut behavior", detail: "Hold or toggle the microphone") {
                    Picker("", selection: $preferences.dictationMode) {
                        ForEach(DictationMode.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 190)
                }

                QuillDivider()

                QuillSettingRow(title: "Listening indicator", detail: "Show the live ink line while speaking") {
                    Toggle("", isOn: $preferences.showIndicator).labelsHidden()
                }
            }

            QuillCard(title: "Your words") {
                QuillSettingRow(title: "Writing style", detail: styleDetail) {
                    Picker("", selection: $preferences.transcriptionMode) {
                        ForEach(TranscriptionMode.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 150)
                }

                QuillDivider()

                QuillSettingRow(title: "Language", detail: "Automatic works well for multilingual speech") {
                    Picker("", selection: $preferences.languageCode) {
                        ForEach(LanguageChoice.supported) { Text($0.title).tag($0.code) }
                    }
                    .labelsHidden()
                    .frame(width: 190)
                }

                QuillDivider()

                QuillSettingRow(title: "When finished", detail: insertionDetail) {
                    Picker("", selection: $preferences.insertionMode) {
                        ForEach(InsertionMode.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 170)
                }
            }

            QuillCard(title: "Mac") {
                QuillSettingRow(title: "Launch at login", detail: "Keep Quill ready in the menu bar") {
                    Toggle("", isOn: Binding(
                        get: { preferences.launchAtLogin },
                        set: { preferences.setLaunchAtLogin($0) }
                    ))
                    .labelsHidden()
                }
                if let error = preferences.launchAtLoginError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .padding(.top, 4)
                }
            }
        }
    }

    private var styleDetail: String {
        preferences.transcriptionMode == .smart
            ? "Remove filler words and format punctuation"
            : "Keep repetitions, filler words, and false starts"
    }

    private var insertionDetail: String {
        preferences.insertionMode == .direct
            ? "Types at your active cursor"
            : "Leaves the text on your clipboard"
    }
}

private struct VocabularyView: View {
    @EnvironmentObject private var preferences: AppPreferences
    @State private var newPhrase = ""

    var body: some View {
        QuillPage(title: "Vocabulary", subtitle: "Teach Quill the names and terms you use.") {
            QuillCard {
                HStack(spacing: 10) {
                    TextField("Add a name or technical term", text: $newPhrase)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(addPhrase)
                    Button("Add", action: addPhrase)
                        .buttonStyle(.borderedProminent)
                        .tint(QuillBrand.ink)
                        .disabled(cleanPhrase.isEmpty || preferences.vocabulary.contains(cleanPhrase))
                }

                Text("Keep this list focused. Quill uses it only as a transcription hint.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }

            QuillCard(title: "Saved terms") {
                if preferences.vocabulary.isEmpty {
                    Text("No custom terms yet.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 90)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 9)], alignment: .leading, spacing: 9) {
                        ForEach(preferences.vocabulary, id: \.self) { phrase in
                            HStack(spacing: 7) {
                                Text(phrase)
                                    .lineLimit(1)
                                Spacer(minLength: 4)
                                Button {
                                    preferences.vocabulary.removeAll { $0 == phrase }
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 9, weight: .bold))
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                                .accessibilityLabel("Remove \(phrase)")
                            }
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 10)
                            .frame(height: 32)
                            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
        }
    }

    private var cleanPhrase: String {
        newPhrase.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func addPhrase() {
        guard !cleanPhrase.isEmpty, !preferences.vocabulary.contains(cleanPhrase) else { return }
        preferences.vocabulary.append(cleanPhrase)
        newPhrase = ""
    }
}

private struct PrivacyView: View {
    @EnvironmentObject private var stats: LocalStatsStore
    @EnvironmentObject private var apiKeys: LocalAPIKeyStore
    @State private var apiKey = ""
    @State private var keyError: String?
    @State private var microphoneGranted = Permissions.microphoneStatus == .authorized
    @State private var accessibilityGranted = Permissions.hasAccessibilityAccess
    @State private var showingResetConfirmation = false

    var body: some View {
        QuillPage(title: "Privacy & Access", subtitle: "Your key, permissions, and local data—nothing else.") {
            QuillCard(title: "Permissions") {
                PermissionAccessRow(
                    symbol: "mic.fill",
                    title: "Microphone",
                    detail: "Used only while you dictate",
                    granted: microphoneGranted,
                    action: requestMicrophone
                )

                QuillDivider()

                PermissionAccessRow(
                    symbol: "accessibility",
                    title: "Accessibility",
                    detail: "Types the result at your active cursor",
                    granted: accessibilityGranted,
                    action: requestAccessibility
                )
            }

            QuillCard(title: "Gemini API key") {
                HStack(spacing: 10) {
                    SecureField(apiKeys.hasKey ? "Paste a replacement key" : "Paste your API key", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                    Button(apiKeys.hasKey ? "Replace Key" : "Save Key", action: saveKey)
                        .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if apiKeys.hasKey {
                    Label("Saved locally. It remains until you replace it.", systemImage: "key.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
                if let keyError {
                    Text(keyError).font(.caption).foregroundStyle(.red)
                }
            }

            QuillCard(title: "Local data") {
                QuillSettingRow(title: "Usage statistics", detail: "Only word and dictation counts are saved on this Mac") {
                    Button("Reset…") { showingResetConfirmation = true }
                }
                QuillDivider()
                Label("Transcript history is not stored", systemImage: "checkmark.shield.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear(perform: refresh)
        .task {
            while !Task.isCancelled {
                refresh()
                try? await Task.sleep(for: .milliseconds(400))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
        .alert("Reset local statistics?", isPresented: $showingResetConfirmation) {
            Button("Reset", role: .destructive) { stats.reset() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This clears dictation and word counts. It does not change your settings or vocabulary.")
        }
    }

    private func requestMicrophone() {
        Task {
            microphoneGranted = await Permissions.requestMicrophoneAccess()
            if !microphoneGranted {
                openPrivacyPane("Privacy_Microphone")
            }
        }
    }

    private func requestAccessibility() {
        accessibilityGranted = Permissions.requestAccessibilityAccess()
        if !accessibilityGranted {
            openPrivacyPane("Privacy_Accessibility")
        }
    }

    private func refresh() {
        microphoneGranted = Permissions.microphoneStatus == .authorized
        accessibilityGranted = Permissions.hasAccessibilityAccess
    }

    private func saveKey() {
        do {
            try apiKeys.replace(with: apiKey)
            apiKey = ""
            keyError = nil
        } catch {
            keyError = error.localizedDescription
        }
    }

    private func openPrivacyPane(_ anchor: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else { return }
        NSWorkspace.shared.open(url)
    }
}

private struct QuillPage<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    init(title: String, subtitle: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 25, weight: .bold, design: .rounded))
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }

                content
            }
            .frame(maxWidth: 690, alignment: .leading)
            .padding(.horizontal, 30)
            .padding(.vertical, 27)
            .frame(maxWidth: .infinity, alignment: .top)
        }
    }
}

private struct QuillCard<Content: View>: View {
    let title: String?
    @ViewBuilder let content: Content

    init(title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            if let title {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
            }
            content
        }
        .padding(17)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.07), lineWidth: 1)
        }
    }
}

private struct QuillSettingRow<Control: View>: View {
    let title: String
    let detail: String
    @ViewBuilder let control: Control

    init(title: String, detail: String, @ViewBuilder control: () -> Control) {
        self.title = title
        self.detail = detail
        self.control = control()
    }

    var body: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            control
        }
    }
}

private struct QuillDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.07))
            .frame(height: 1)
    }
}

private struct LocalStatCard: View {
    let value: Int
    let label: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(QuillBrand.ink)
                .frame(width: 26, height: 26)
                .background(QuillBrand.signal, in: RoundedRectangle(cornerRadius: 7))
            Text(value.formatted())
                .font(.system(size: 25, weight: .bold, design: .rounded))
                .contentTransition(.numericText())
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(Color.primary.opacity(0.07), lineWidth: 1)
        }
    }
}

private struct PermissionAccessRow: View {
    let symbol: String
    let title: String
    let detail: String
    let granted: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 32, height: 32)
                .background(Color.secondary.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if granted {
                Label("Allowed", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.green)
            } else {
                Button("Allow", action: action)
            }
        }
    }
}

private struct InkLine: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let level: Double
    private let profile: [CGFloat] = [0.25, 0.46, 0.72, 0.38, 0.9, 0.58, 1, 0.48, 0.7, 0.34, 0.54]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 24, paused: reduceMotion || level == 0)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 4) {
                ForEach(profile.indices, id: \.self) { index in
                    let ambient = CGFloat(level > 0 && !reduceMotion
                        ? 0.74 + 0.26 * abs(sin(time * 5 + Double(index)))
                        : 1)
                    Capsule()
                        .fill(QuillBrand.signal.opacity(level > 0 ? 1 : 0.42))
                        .frame(width: 3, height: 3 + 30 * profile[index] * (0.16 + level * 0.84) * ambient)
                }
            }
        }
        .animation(.spring(response: 0.16, dampingFraction: 0.72), value: level)
        .accessibilityHidden(true)
    }
}
