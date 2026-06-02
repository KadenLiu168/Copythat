import SwiftUI

@main
struct CopythatApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(settings: appDelegate.model.settings)
                .frame(width: 520, height: 420)
        }
    }
}
