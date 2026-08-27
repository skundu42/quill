import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let state = AppState.shared
    let preferences = AppPreferences.shared
    let stats = LocalStatsStore.shared
    let apiKeys = LocalAPIKeyStore.shared
    lazy var dictationController = DictationController(
        state: state,
        preferences: preferences,
        stats: stats,
        apiKeys: apiKeys
    )

    private let hotkeyManager = GlobalHotkeyManager()
    private var pillController: DictationPillPanelController?
    private var onboardingWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var statusItem: NSStatusItem?
    private var primaryMenuItem: NSMenuItem?
    private var statusMenuItem: NSMenuItem?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }

        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()

        hotkeyManager.onPress = { [weak self] in self?.dictationController.start() }
        hotkeyManager.onRelease = { [weak self] in self?.dictationController.stop() }
        hotkeyManager.onEscape = { [weak self] in self?.dictationController.cancel() }

        Publishers.CombineLatest(preferences.$shortcut, preferences.$dictationMode)
            .sink { [weak self] shortcut, mode in
                self?.hotkeyManager.register(shortcut, mode: mode)
            }
            .store(in: &cancellables)

        Publishers.CombineLatest(state.$phase, state.$audioLevel)
            .throttle(for: .milliseconds(33), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] phase, level in self?.updateStatusItem(for: phase, level: level) }
            .store(in: &cancellables)

        pillController = DictationPillPanelController(state: state, preferences: preferences) { [weak self] in
            self?.dictationController.cancel()
        }

        if !preferences.onboardingComplete {
            DispatchQueue.main.async { [weak self] in self?.showOnboarding() }
        } else if !apiKeys.hasKey {
            DispatchQueue.main.async { [weak self] in self?.showSettings() }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = QuillStatusIcon.make()
        item.button?.imagePosition = .imageOnly
        item.button?.toolTip = "Quill — Hold ⌥ Space to dictate"
        item.button?.setAccessibilityLabel("Quill")

        let menu = NSMenu()
        let heading = NSMenuItem(title: "Quill", action: nil, keyEquivalent: "")
        heading.isEnabled = false
        menu.addItem(heading)

        let open = NSMenuItem(title: "Open Quill", action: #selector(showSettings), keyEquivalent: "")
        open.target = self
        menu.addItem(open)

        menu.addItem(.separator())

        let primary = NSMenuItem(title: "Start Dictation", action: #selector(toggleDictation), keyEquivalent: " ")
        primary.keyEquivalentModifierMask = [.option]
        primary.target = self
        menu.addItem(primary)
        primaryMenuItem = primary

        let status = NSMenuItem(title: "Status: Ready", action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        statusMenuItem = status

        menu.addItem(.separator())
        let settings = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settings.keyEquivalentModifierMask = [.command]
        settings.target = self
        menu.addItem(settings)

        let quit = NSMenuItem(title: "Quit Quill", action: #selector(quitQuill), keyEquivalent: "q")
        quit.keyEquivalentModifierMask = [.command]
        quit.target = self
        menu.addItem(quit)

        item.menu = menu
        statusItem = item
    }

    private func updateStatusItem(for phase: DictationPhase, level: Double) {
        primaryMenuItem?.title = phase == .listening ? "Stop Dictation" : "Start Dictation"
        primaryMenuItem?.isEnabled = phase != .finalizing && phase != .inserting
        statusMenuItem?.title = "Status: \(phase.title)"

        let image: NSImage?
        switch phase {
        case .idle:
            image = QuillStatusIcon.make()
        case .listening:
            image = QuillStatusIcon.waveform(level: level)
        case .finalizing, .inserting:
            image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "Quill is finishing")
        case .error:
            image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "Quill encountered an error")
        }
        image?.isTemplate = true
        statusItem?.button?.image = image
    }

    @objc private func toggleDictation() {
        dictationController.toggle()
    }

    @objc func showSettings() {
        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        stats.refreshDay()
        let view = SettingsView(controller: dictationController)
            .environmentObject(preferences)
            .environmentObject(state)
            .environmentObject(stats)
            .environmentObject(apiKeys)
            .frame(width: 820, height: 590)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 590),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Quill"
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: view)
        window.contentMinSize = NSSize(width: 760, height: 540)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = window
    }

    @objc private func quitQuill() {
        NSApp.terminate(nil)
    }

    private func showOnboarding() {
        if let onboardingWindow {
            onboardingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = OnboardingView { [weak self] in self?.finishOnboarding() }
        .environmentObject(preferences)
        .environmentObject(apiKeys)
        .frame(width: 640, height: 520)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 520),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to Quill"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.contentViewController = NSHostingController(rootView: view)
        window.contentMinSize = NSSize(width: 640, height: 520)
        window.contentMaxSize = NSSize(width: 640, height: 520)
        window.setContentSize(NSSize(width: 640, height: 520))
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow = window
    }

    private func finishOnboarding() {
        preferences.onboardingComplete = true

        // Hiding avoids AppKit releasing the window while its close animation is active.
        // The window is retained for the app's lifetime and released safely at termination.
        onboardingWindow?.orderOut(nil)
        showSettings()
    }
}

private enum QuillStatusIcon {
    static func make() -> NSImage {
        let image = NSImage(size: NSSize(width: 20, height: 20), flipped: false) { _ in
            let scale: CGFloat = 0.95
            func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
                NSPoint(
                    x: 10 + (x - 18.7) * scale,
                    y: 10 - (y - 17.7) * scale
                )
            }

            let path = NSBezierPath()
            path.move(to: point(26.8, 8.5))
            path.curve(
                to: point(13.2, 17.6),
                controlPoint1: point(20.6, 9.9),
                controlPoint2: point(16.0, 12.9)
            )
            path.curve(
                to: point(10.9, 26.9),
                controlPoint1: point(11.4, 20.6),
                controlPoint2: point(10.6, 23.7)
            )
            path.line(to: point(15.5, 22.1))
            path.line(to: point(18.7, 21.9))
            path.line(to: point(16.3, 20.6))
            path.line(to: point(19.7, 17.0))
            path.line(to: point(23.0, 16.9))
            path.line(to: point(20.6, 15.5))
            path.curve(
                to: point(26.8, 8.5),
                controlPoint1: point(22.7, 13.3),
                controlPoint2: point(25.0, 10.9)
            )
            path.close()
            NSColor.black.setFill()
            path.fill()
            return true
        }
        image.isTemplate = true
        return image
    }

    static func waveform(level: Double) -> NSImage {
        let image = NSImage(size: NSSize(width: 20, height: 20), flipped: false) { _ in
            let profiles: [CGFloat] = [0.48, 0.76, 1, 0.68, 0.42]
            let amplitude = 0.22 + CGFloat(level) * 0.78
            for (index, profile) in profiles.enumerated() {
                let height = 4 + 13 * profile * amplitude
                let rect = NSRect(
                    x: 2.2 + CGFloat(index) * 3.8,
                    y: 10 - height / 2,
                    width: 2.3,
                    height: height
                )
                NSBezierPath(roundedRect: rect, xRadius: 1.15, yRadius: 1.15).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
