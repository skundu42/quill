import SwiftUI

@main
struct QuillApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var updateChecker = UpdateChecker.shared

    var body: some Scene {
        Settings {
            SettingsView(controller: appDelegate.dictationController)
                .environmentObject(AppPreferences.shared)
                .environmentObject(AppState.shared)
                .environmentObject(LocalStatsStore.shared)
                .environmentObject(LocalAPIKeyStore.shared)
                .environmentObject(updateChecker)
                .frame(width: 820, height: 590)
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    updateChecker.checkManually()
                }
                .disabled(!updateChecker.canCheckForUpdates)
            }
        }
    }
}
