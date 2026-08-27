import AppKit
import AVFoundation
import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var preferences: AppPreferences
    @EnvironmentObject private var apiKeys: LocalAPIKeyStore
    @State private var step = 0
    @State private var apiKey = ""
    @State private var microphoneGranted = Permissions.microphoneStatus == .authorized
    @State private var accessibilityGranted = Permissions.hasAccessibilityAccess
    @State private var errorMessage: String?

    let onComplete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                ForEach(0..<3, id: \.self) { index in
                    Capsule()
                        .fill(index <= step ? QuillBrand.signal : Color.secondary.opacity(0.2))
                        .frame(width: index == step ? 28 : 7, height: 7)
                }
            }
            .padding(.top, 24)

            Group {
                switch step {
                case 0: welcomeStep
                case 1: permissionsStep
                default: apiKeyStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(42)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .task(id: step) {
            guard step == 1 else { return }
            while !Task.isCancelled {
                refreshPermissionStatuses()
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshPermissionStatuses()
        }
    }

    private var welcomeStep: some View {
        VStack(spacing: 22) {
            QuillLogoView(size: 86)
            VStack(spacing: 10) {
                Text("Quill").font(.system(size: 38, weight: .bold, design: .rounded))
                Text("Speak instead of typing.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            Text("Hold ⌥ Space, speak naturally, then release. Quill inserts polished text wherever your cursor is.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 390)
            Button("Continue") { step = 1 }
                .buttonStyle(.borderedProminent)
                .tint(QuillBrand.signal)
                .foregroundStyle(QuillBrand.ink)
                .controlSize(.large)
        }
    }

    private var permissionsStep: some View {
        VStack(spacing: 28) {
            VStack(spacing: 8) {
                Text("Two permissions. One simple job.").font(.system(size: 28, weight: .bold))
                Text("Quill listens only while you hold the shortcut, then types into the app you were already using.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 440)
            }

            VStack(spacing: 12) {
                permissionRow(
                    icon: "mic.fill",
                    title: "Microphone",
                    detail: "Capture your voice while dictating",
                    granted: microphoneGranted,
                    action: requestMicrophone
                )
                permissionRow(
                    icon: "accessibility",
                    title: "Accessibility",
                    detail: "Insert text at the active cursor",
                    granted: accessibilityGranted,
                    action: requestAccessibility
                )
            }
            .frame(maxWidth: 460)

            HStack {
                Button("Back") { step = 0 }
                Spacer()
                Button("Continue") { step = 2 }
                    .buttonStyle(.borderedProminent)
                    .tint(QuillBrand.signal)
                    .foregroundStyle(QuillBrand.ink)
            }
            .frame(maxWidth: 460)
        }
    }

    private var apiKeyStep: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Text("Connect Gemini").font(.system(size: 28, weight: .bold))
                Text("Quill is bring-your-own-key. Your API key is saved locally by Quill—not in Keychain—and remains until you replace it.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 440)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Gemini API key").font(.headline)
                SecureField("AIza…", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                Text("Audio streams directly to Google for transcription and is not stored by Quill.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 460)

            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.red)
            }

            HStack {
                Button("Back") { step = 1 }
                Spacer()
                Button("Save and Finish") { saveAndFinish() }
                    .buttonStyle(.borderedProminent)
                    .tint(QuillBrand.signal)
                    .foregroundStyle(QuillBrand.ink)
                    .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .frame(maxWidth: 460)
        }
    }

    private func permissionRow(
        icon: String,
        title: String,
        detail: String,
        granted: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .frame(width: 34, height: 34)
                .background(.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.semibold)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if granted {
                Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(QuillBrand.signal)
            } else {
                Button("Enable", action: action)
            }
        }
        .padding(12)
        .background(.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }

    private func requestMicrophone() {
        Task {
            microphoneGranted = await Permissions.requestMicrophoneAccess()
        }
    }

    private func requestAccessibility() {
        accessibilityGranted = Permissions.requestAccessibilityAccess()
    }

    private func refreshPermissionStatuses() {
        microphoneGranted = Permissions.microphoneStatus == .authorized
        accessibilityGranted = Permissions.hasAccessibilityAccess
    }

    private func saveAndFinish() {
        do {
            try apiKeys.replace(with: apiKey)
            apiKey = ""
            errorMessage = nil
            onComplete()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
