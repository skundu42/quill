import SwiftUI

@main
struct QuillApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var updateChecker = UpdateChecker.shared

    var body: some Scene {
        Settings {
            // AppDelegate owns the windows; this scene hosts the app commands.
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    appDelegate.showPrimaryWindow()
                }
                .keyboardShortcut(",", modifiers: .command)
            }

            CommandGroup(replacing: .appTermination) {
                Button("Close Quill Window") {
                    appDelegate.closePrimaryWindow()
                }
                .keyboardShortcut("q", modifiers: .command)
            }

            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    updateChecker.checkManually()
                }
                .disabled(!updateChecker.canCheckForUpdates)
            }
        }
    }
}
