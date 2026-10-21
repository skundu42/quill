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
                    HomeView(controller: controller) { selection = .models }
                case .models:
                    ModelsView()
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
    case models = "Models"
    case dictation = "Dictation"
    case vocabulary = "Vocabulary"
    case privacy = "Privacy & Access"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .models: "cpu"
        case .dictation: "waveform"
        case .vocabulary: "text.book.closed.fill"
        case .privacy: "lock.shield.fill"
        }
    }
}

private struct QuillSidebar: View {
    @EnvironmentObject private var updateChecker: UpdateChecker
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

            VStack(alignment: .leading, spacing: 8) {
                Button {
                    updateChecker.checkManually()
                } label: {
                    Label("Check for updates", systemImage: "arrow.triangle.2.circlepath")
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.68))
                .disabled(!updateChecker.canCheckForUpdates)

                Text("Version \(updateChecker.currentVersion)")
            }
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
    @ObservedObject private var barkModel = BarkModelManager.shared
    let controller: DictationController
    let onOpenModels: () -> Void

    var body: some View {
        QuillPage(title: "Good to have you here", subtitle: "Quill is ready wherever your cursor is.") {
            statusCard
            LastDictationErrorCard()

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
                    Text(isModelReady ? phaseTitle.uppercased() : "SETUP NEEDED")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(1.3)
                        .foregroundStyle(.white.opacity(0.62))
                }

                Text(statusHeadline)
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                HStack(spacing: 8) {
                    Text(preferences.dictationShortcut.title)
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
                isModelReady ? controller.toggle() : onOpenModels()
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
        guard isModelReady else { return .orange }
        if case .error = state.phase { return .orange }
        return state.phase == .idle ? QuillBrand.signal : .white
    }

    private var statusHeadline: String {
        guard isModelReady else {
            return preferences.transcriptionProvider == .bark
                ? "Set up Bark to start dictating"
                : "Connect Gemini to start dictating"
        }
        return switch state.phase {
        case .idle: "Speak. Quill will write."
        case .listening: "Listening to you…"
        case .finalizing: preferences.transcriptionProvider == .bark ? "Transcribing your words…" : "Polishing your words…"
        case .inserting: "Putting it at your cursor…"
        case .error: "Quill needs your attention"
        }
    }

    private var actionTitle: String {
        guard isModelReady else { return "Set up model" }
        return state.phase == .listening ? "Stop" : "Start dictating"
    }

    private var isModelReady: Bool {
        switch preferences.transcriptionProvider {
        case .bark: BarkModelManager.isSupported && barkModel.isReady
        case .gemini: apiKeys.hasKey && !preferences.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private var phaseTitle: String {
        if case .error = state.phase { return "Needs attention" }
        return state.phase == .finalizing && preferences.transcriptionProvider == .bark
            ? "Transcribing"
            : state.phase.title
    }
}

private struct DictationSettingsView: View {
    @EnvironmentObject private var preferences: AppPreferences
    @EnvironmentObject private var updateChecker: UpdateChecker
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var shortcuts: ShortcutCoordinator
    @EnvironmentObject private var audioDevices: AudioInputDeviceCatalog

    var body: some View {
        QuillPage(title: "Dictation", subtitle: "Make Quill work the way you speak.") {
            QuillCard(title: "Shortcuts") {
                shortcutRow(
                    title: "Dictate",
                    detail: "Starts or stops dictation from any app",
                    action: .dictation,
                    shortcut: shortcuts.dictationShortcut
                )

                QuillDivider()

                shortcutRow(
                    title: "Paste last transcript",
                    detail: "Pastes the latest completed dictation at the cursor",
                    action: .pasteLast,
                    shortcut: shortcuts.pasteLastShortcut
                )

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

                Text("Click a shortcut, then type a key with Command, Option, Control, or Shift. Press Escape to cancel.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }

            QuillCard(title: "Microphone") {
                QuillSettingRow(title: "Audio input", detail: microphoneDetail) {
                    Picker("", selection: microphoneSelection) {
                        Text(systemDefaultTitle).tag("")
                        if let preference = preferences.microphonePreference,
                           audioDevices.device(withUID: preference.uid) == nil {
                            Text("\(preference.name) — Unavailable").tag(preference.uid)
                        }
                        ForEach(audioDevices.devices) { device in
                            Text(device.name).tag(device.uid)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 220)
                }

                if let error = audioDevices.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            QuillCard(title: "Your words") {
                if preferences.transcriptionProvider == .bark {
                    Text("Bark transcribes English verbatim. Writing style and language settings apply only to Gemini.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                QuillSettingRow(title: "Writing style", detail: styleDetail) {
                    Picker("", selection: $preferences.transcriptionMode) {
                        ForEach(TranscriptionMode.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 150)
                    .disabled(preferences.transcriptionProvider != .gemini)
                }

                QuillDivider()

                QuillSettingRow(title: "Language", detail: "Automatic works well for multilingual speech") {
                    Picker("", selection: $preferences.languageCode) {
                        ForEach(LanguageChoice.supported) { Text($0.title).tag($0.code) }
                    }
                    .labelsHidden()
                    .frame(width: 190)
                    .disabled(preferences.transcriptionProvider != .gemini)
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
                QuillDivider()
                QuillSettingRow(
                    title: "Automatic updates",
                    detail: "Download signed releases and install them when Quill quits"
                ) {
                    Toggle("", isOn: $updateChecker.automaticUpdatesEnabled)
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
        .onAppear { audioDevices.refresh() }
    }

    @ViewBuilder
    private func shortcutRow(
        title: String,
        detail: String,
        action: GlobalShortcutAction,
        shortcut: KeyboardShortcut
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            QuillSettingRow(title: title, detail: detail) {
                ShortcutRecorderControl(
                    shortcut: shortcut,
                    isEnabled: !state.phase.isActive,
                    onRecord: { shortcuts.update($0, for: action) }
                )
                .frame(width: 150, height: 28)
            }
            if let error = shortcuts.error(for: action) {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var microphoneSelection: Binding<String> {
        Binding(
            get: { preferences.microphonePreference?.uid ?? "" },
            set: { uid in
                guard !uid.isEmpty else {
                    preferences.microphonePreference = nil
                    return
                }
                if let device = audioDevices.device(withUID: uid) {
                    preferences.microphonePreference = MicrophonePreference(uid: device.uid, name: device.name)
                }
            }
        )
    }

    private var systemDefaultTitle: String {
        if let name = audioDevices.defaultDevice?.name {
            return "System Default (\(name))"
        }
        return "System Default"
    }

    private var microphoneDetail: String {
        guard let preference = preferences.microphonePreference else {
            return "Follows the macOS default input"
        }
        if audioDevices.device(withUID: preference.uid) == nil {
            let fallback = audioDevices.defaultDevice?.name ?? "the system default"
            return "\(preference.name) is unavailable; using \(fallback)"
        }
        return "Used for the next dictation"
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
        QuillPage(title: "Vocabulary", subtitle: "Teach Gemini the names and terms you use.") {
            if preferences.transcriptionProvider == .bark {
                Text("Custom vocabulary is available with Gemini. Your saved terms will be used when you switch to Gemini in Models.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
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
            .disabled(preferences.transcriptionProvider != .gemini)

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
            .disabled(preferences.transcriptionProvider != .gemini)
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

private struct ModelsView: View {
    var body: some View {
        QuillPage(title: "Models", subtitle: "Use Bark on this Mac or connect your own Gemini model.") {
            LastDictationErrorCard()
            ModelSetupView()
        }
    }
}

private struct LastDictationErrorCard: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        if let error = state.lastError {
            QuillCard {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.orange)

                    VStack(alignment: .leading, spacing: 7) {
                        Text("Last dictation error")
                            .font(.system(size: 14, weight: .bold))
                        Text(error)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button("Dismiss") { state.lastError = nil }
                        .controlSize(.small)
                        .fixedSize()
                        .accessibilityLabel("Dismiss last dictation error")
                }
            }
        }
    }
}

struct ModelSetupView: View {
    @EnvironmentObject private var preferences: AppPreferences
    @EnvironmentObject private var apiKeys: LocalAPIKeyStore
    @ObservedObject private var state = AppState.shared
    @ObservedObject private var barkModel = BarkModelManager.shared
    @State private var apiKey = ""
    @State private var keyError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Transcription model", selection: $preferences.transcriptionProvider) {
                ForEach(TranscriptionProvider.allCases) { provider in
                    Text(provider.title).tag(provider)
                }
            }
            .disabled(state.phase.isActive)

            switch preferences.transcriptionProvider {
            case .bark: barkSetup
            case .gemini: geminiSetup
            }
        }
        .onChange(of: preferences.transcriptionProvider) { _, _ in
            apiKey = ""
            keyError = nil
        }
    }

    private var barkSetup: some View {
        QuillCard(title: "Underdog Bark 3.0") {
            Text("English transcription on your Mac. Bark keeps your words as spoken, without Smart cleanup, and works offline after setup.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Text("Up to five minutes per dictation. Text appears after you stop speaking. The first transcription after launching can take several minutes while the model loads.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if !BarkModelManager.isSupported {
                Label("Bark requires Apple Silicon and macOS 15 or later. Choose Gemini on this Mac.", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else if barkModel.isReady {
                Label("Ready on this Mac", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.secondary)
                Button("Reinstall model") {
                    Task { await barkModel.prepare(reinstall: true) }
                }
                .disabled(state.phase.isActive)
            } else if barkModel.isDownloading {
                ProgressView(value: barkModel.progress)
                Text(barkModel.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Button("Download Bark · about 202 MB") {
                    Task { await barkModel.prepare() }
                }
                .buttonStyle(.borderedProminent)
                .tint(QuillBrand.ink)
                Text("One-time model download. No API key or Python installation needed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let error = barkModel.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 12) {
                Link("Model by ConwayResearch", destination: URL(string: "https://huggingface.co/ConwayResearch/Underdog-Bark-3.0")!)
                Link("CC BY 4.0 license", destination: URL(string: "https://huggingface.co/ConwayResearch/Underdog-Bark-3.0/blob/\(BarkModelFiles.revision)/coreml/LICENSE")!)
            }
            .font(.caption)
        }
    }

    private var geminiSetup: some View {
        QuillCard(title: "Gemini") {
            Text("Audio streams to Google for transcription. Smart cleanup, language selection, and custom vocabulary are available with Gemini.")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                SecureField(apiKeys.hasKey ? "Paste a replacement API key" : "Paste your Gemini API key", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                Button(apiKeys.hasKey ? "Replace Key" : "Save Key", action: saveKey)
                    .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .fixedSize()
            }
            .disabled(state.phase.isActive)

            if apiKeys.hasKey {
                Label("API key saved locally until you replace it.", systemImage: "key.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("Gemini model ID").font(.caption.weight(.semibold))
                TextField("gemini-3.5-transcribe-live", text: $preferences.model)
                    .textFieldStyle(.roundedBorder)
                    .disabled(state.phase.isActive)
                Text("Use a Gemini Live model that supports input transcription.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let keyError {
                Text(keyError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Link(destination: URL(string: "https://aistudio.google.com/app/apikey")!) {
                Label("Get a key in Google AI Studio", systemImage: "arrow.up.right.square")
            }
            .font(.caption)
        }
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
}

private struct PrivacyView: View {
    @EnvironmentObject private var stats: LocalStatsStore
    @State private var microphoneGranted = Permissions.microphoneStatus == .authorized
    @State private var accessibilityGranted = Permissions.hasAccessibilityAccess
    @State private var showingResetConfirmation = false

    var body: some View {
        QuillPage(title: "Privacy & Access", subtitle: "Permissions and local data controls.") {
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
