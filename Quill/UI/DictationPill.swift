import AppKit
import Combine
import SwiftUI

struct DictationPillView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 11) {
            phaseIcon

            if state.phase == .listening {
                LiveWaveformView(level: state.audioLevel)
                    .frame(width: 78, height: 26)
                    .transition(.scale(scale: 0.82).combined(with: .opacity))
            }

            Text(pillText)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)

            if state.phase.isActive {
                Text("esc")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 5))
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .foregroundStyle(.white)
        .background(QuillBrand.ink.opacity(0.96), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        }
        .shadow(color: listeningGlow, radius: 22, y: 7)
        .shadow(color: .black.opacity(0.28), radius: 18, y: 9)
        .animation(.snappy(duration: 0.22), value: state.phase)
        .animation(.linear(duration: reduceMotion ? 0 : 0.08), value: state.audioLevel)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Quill \(pillText). Press Escape to cancel.")
    }

    @ViewBuilder
    private var phaseIcon: some View {
        switch state.phase {
        case .listening:
            ListeningOrb(level: state.audioLevel)
                .frame(width: 26, height: 26)
        case .finalizing, .inserting:
            QuillNibMark(color: QuillBrand.signal)
                .frame(width: 18, height: 18)
                .rotationEffect(.degrees(state.phase == .finalizing && !reduceMotion ? 8 : 0))
                .symbolEffect(.pulse, options: reduceMotion ? .nonRepeating : .repeating)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
        case .idle:
            QuillNibMark(color: .white).frame(width: 18, height: 18)
        }
    }

    private var pillText: String {
        switch state.phase {
        case .listening: state.interimTranscript.isEmpty ? "Listening" : state.interimTranscript
        case .finalizing: "Polishing…"
        case .inserting: "Inserting…"
        case .error(let message): message
        case .idle: "Ready"
        }
    }

    private var borderColor: Color {
        guard state.phase == .listening else { return .white.opacity(0.14) }
        return QuillBrand.signal.opacity(0.18 + state.audioLevel * 0.28)
    }

    private var listeningGlow: Color {
        guard state.phase == .listening else { return .clear }
        return QuillBrand.signal.opacity(0.05 + state.audioLevel * 0.12)
    }
}

private struct ListeningOrb: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let level: Double

    var body: some View {
        ZStack {
            Circle()
                .fill(QuillBrand.signal.opacity(0.10))
                .frame(width: 24, height: 24)
                .scaleEffect(reduceMotion ? 1 : 0.76 + level * 0.44)
            Circle()
                .fill(QuillBrand.signal.opacity(0.24))
                .frame(width: 14, height: 14)
                .scaleEffect(0.86 + level * 0.28)
            Circle()
                .fill(QuillBrand.signal)
                .frame(width: 7, height: 7)
                .shadow(color: QuillBrand.signal.opacity(0.65), radius: 5)
        }
        .animation(.spring(response: 0.14, dampingFraction: 0.68), value: level)
    }
}

private struct LiveWaveformView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let level: Double
    private let profiles: [CGFloat] = [0.38, 0.62, 0.82, 1, 0.72, 0.92, 0.58, 0.76, 0.44]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 3.5) {
                ForEach(profiles.indices, id: \.self) { index in
                    let motion = reduceMotion
                        ? 1.0
                        : 0.68 + 0.32 * abs(sin(time * (5.2 + Double(index % 3)) + Double(index) * 0.72))
                    let amplitude = 0.14 + CGFloat(level) * 0.86
                    let height = 4 + 20 * profiles[index] * amplitude * motion
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [QuillBrand.signal, QuillBrand.signal.opacity(0.62)],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .frame(width: 3.5, height: height)
                }
            }
        }
    }
}

@MainActor
final class DictationPillPanelController {
    private let panel: NSPanel
    private let state: AppState
    private let preferences: AppPreferences
    private var cancellables = Set<AnyCancellable>()

    init(state: AppState, preferences: AppPreferences, onCancel: @escaping () -> Void) {
        self.state = state
        self.preferences = preferences
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 58),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.ignoresMouseEvents = true
        let hostingView = NSHostingView(rootView: DictationPillView(onCancel: onCancel).environmentObject(state))
        hostingView.sizingOptions = []
        hostingView.frame = NSRect(x: 0, y: 0, width: 360, height: 58)
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView

        Publishers.CombineLatest3(state.$phase, preferences.$showIndicator, state.$interimTranscript)
            .receive(on: RunLoop.main)
            .sink { [weak self] phase, showIndicator, _ in
                self?.update(phase: phase, showIndicator: showIndicator)
            }
            .store(in: &cancellables)
    }

    private func update(phase: DictationPhase, showIndicator: Bool) {
        let shouldShow: Bool
        switch phase {
        case .idle: shouldShow = false
        case .listening, .finalizing, .inserting, .error: shouldShow = showIndicator
        }

        guard shouldShow else {
            hidePanel()
            return
        }

        let width: CGFloat = {
            if case .error = phase { return 420 }
            if case .listening = phase, !state.interimTranscript.isEmpty { return 420 }
            return 250
        }()
        positionOnActiveScreen(width: width, animated: panel.isVisible)
        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
            }
        }
    }

    private func hidePanel() {
        guard panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak panel] in
            panel?.orderOut(nil)
            panel?.alphaValue = 1
        }
    }

    private func positionOnActiveScreen(width: CGFloat, animated: Bool) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else { return }
        let targetFrame = NSRect(
            x: visibleFrame.midX - width / 2,
            y: visibleFrame.minY + 24,
            width: width,
            height: 58
        )
        panel.setFrame(targetFrame, display: true, animate: animated)
    }
}
