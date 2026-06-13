import SwiftUI

@main
struct CopythatApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(settings: appDelegate.model.settings, store: appDelegate.model.store)
                .frame(width: 520, height: 420)
        }
    }
}
