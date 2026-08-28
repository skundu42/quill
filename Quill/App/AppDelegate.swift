import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let state = AppState.shared
    let preferences = AppPreferences.shared
    let stats = LocalStatsStore.shared
    let apiKeys = LocalAPIKeyStore.shared
    let updateChecker = UpdateChecker.shared
    let audioDevices = AudioInputDeviceCatalog()
    private let hotkeyManager = GlobalHotkeyManager()
    lazy var shortcutCoordinator = ShortcutCoordinator(preferences: preferences, registrar: hotkeyManager)
    lazy var dictationController = DictationController(
        state: state,
        preferences: preferences,
        stats: stats,
        apiKeys: apiKeys
    )

    private var pillController: DictationPillPanelController?
    private var onboardingWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var statusItem: NSStatusItem?
    private var primaryMenuItem: NSMenuItem?
    private var statusMenuItem: NSMenuItem?
    private var pasteLastMenuItem: NSMenuItem?
    private var updateMenuItem: NSMenuItem?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }

        NSApp.setActivationPolicy(.regular)
        setupStatusItem()

        hotkeyManager.onPress = { [weak self] in self?.dictationController.start() }
        hotkeyManager.onRelease = { [weak self] in self?.dictationController.stop() }
        hotkeyManager.onToggle = { [weak self] in self?.dictationController.toggle() }
        hotkeyManager.onPasteLast = { [weak self] in self?.dictationController.pasteLastTranscript() }
        hotkeyManager.onEscape = { [weak self] in self?.dictationController.cancel() ?? false }
        shortcutCoordinator.start()

        preferences.$dictationMode
            .sink { [weak self] mode in
                self?.hotkeyManager.setDictationMode(mode)
                guard let self else { return }
                self.updateShortcutPresentation(
                    dictation: self.shortcutCoordinator.dictationShortcut,
                    pasteLast: self.shortcutCoordinator.pasteLastShortcut
                )
            }
            .store(in: &cancellables)

        Publishers.CombineLatest(
            shortcutCoordinator.$dictationShortcut,
            shortcutCoordinator.$pasteLastShortcut
        )
        .sink { [weak self] dictation, pasteLast in
            self?.updateShortcutPresentation(dictation: dictation, pasteLast: pasteLast)
        }
        .store(in: &cancellables)

        Publishers.CombineLatest(state.$phase, state.$audioLevel)
            .throttle(for: .milliseconds(33), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] phase, level in self?.updateStatusItem(for: phase, level: level) }
            .store(in: &cancellables)

        state.$lastTranscript
            .sink { [weak self] _ in self?.updatePasteLastAvailability() }
            .store(in: &cancellables)

        preferences.$microphonePreference
            .dropFirst()
            .sink { [weak self] _ in self?.dictationController.prewarmAudio() }
            .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didActivateApplicationNotification)
            .compactMap { notification in
                notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            }
            .filter { application in
                application.processIdentifier != ProcessInfo.processInfo.processIdentifier
            }
            .sink { [weak self] _ in
                // App activation is delivered before the click that activated the app
                // has necessarily moved AX focus into the clicked text field.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    self?.dictationController.rememberInsertionTarget()
                }
            }
            .store(in: &cancellables)

        updateChecker.$canCheckForUpdates
            .sink { [weak self] canCheck in
                self?.updateMenuItem?.isEnabled = canCheck
            }
            .store(in: &cancellables)

        pillController = DictationPillPanelController(state: state, preferences: preferences) { [weak self] in
            _ = self?.dictationController.cancel()
        }

        dictationController.prewarmAudio()
        DispatchQueue.main.async { [weak self] in self?.showPrimaryWindow() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        _ = dictationController.cancel()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPrimaryWindow()
        return true
    }

    func closePrimaryWindow() {
        settingsWindow?.orderOut(nil)
        onboardingWindow?.orderOut(nil)
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

        let open = NSMenuItem(title: "Open Quill", action: #selector(showPrimaryWindow), keyEquivalent: "")
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

        let pasteLast = NSMenuItem(title: "Paste Last Transcript", action: #selector(pasteLastTranscript), keyEquivalent: "")
        pasteLast.target = self
        pasteLast.isEnabled = false
        menu.addItem(pasteLast)
        pasteLastMenuItem = pasteLast

        menu.addItem(.separator())
        let settings = NSMenuItem(title: "Settings…", action: #selector(showPrimaryWindow), keyEquivalent: ",")
        settings.keyEquivalentModifierMask = [.command]
        settings.target = self
        menu.addItem(settings)

        let updates = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        updates.target = self
        updates.isEnabled = updateChecker.canCheckForUpdates
        menu.addItem(updates)
        updateMenuItem = updates

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
        updatePasteLastAvailability()

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

    @objc private func pasteLastTranscript() {
        dictationController.pasteLastTranscript()
    }

    private func updatePasteLastAvailability() {
        pasteLastMenuItem?.isEnabled = !state.lastTranscript.isEmpty && !state.phase.isActive
    }

    private func updateShortcutPresentation(
        dictation: KeyboardShortcut,
        pasteLast: KeyboardShortcut
    ) {
        apply(dictation, to: primaryMenuItem)
        apply(pasteLast, to: pasteLastMenuItem)
        let behavior = preferences.dictationMode == .pushToTalk ? "Hold" : "Press"
        statusItem?.button?.toolTip = "Quill — \(behavior) \(dictation.title) to dictate"
    }

    private func apply(_ shortcut: KeyboardShortcut, to item: NSMenuItem?) {
        item?.keyEquivalent = shortcut.menuKeyEquivalent ?? ""
        item?.keyEquivalentModifierMask = shortcut.modifiers.eventFlags
    }

    @objc private func showPrimaryWindow() {
        dictationController.rememberInsertionTarget()
        if preferences.onboardingComplete {
            showSettings()
        } else {
            showOnboarding()
        }
    }

    private func showSettings() {
        if let settingsWindow {
            presentCentered(settingsWindow)
            return
        }

        stats.refreshDay()
        let view = SettingsView(controller: dictationController)
            .environmentObject(preferences)
            .environmentObject(state)
            .environmentObject(stats)
            .environmentObject(apiKeys)
            .environmentObject(updateChecker)
            .environmentObject(shortcutCoordinator)
            .environmentObject(audioDevices)
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
        settingsWindow = window
        presentCentered(window)
    }

    @objc private func quitQuill() {
        NSApp.terminate(nil)
    }

    @objc private func checkForUpdates() {
        updateChecker.checkManually()
    }

    private func showOnboarding() {
        if let onboardingWindow {
            presentCentered(onboardingWindow)
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
        onboardingWindow = window
        presentCentered(window)
    }

    private func finishOnboarding() {
        preferences.onboardingComplete = true

        // Hiding avoids AppKit releasing the window while its close animation is active.
        // The window is retained for the app's lifetime and released safely at termination.
        onboardingWindow?.orderOut(nil)
        showSettings()
    }

    private func presentCentered(_ window: NSWindow) {
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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
