import SwiftUI

@main
struct QuillApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(controller: appDelegate.dictationController)
                .environmentObject(AppPreferences.shared)
                .environmentObject(AppState.shared)
                .environmentObject(LocalStatsStore.shared)
                .environmentObject(LocalAPIKeyStore.shared)
                .frame(width: 820, height: 590)
        }
    }
}
