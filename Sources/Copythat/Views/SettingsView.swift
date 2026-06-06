import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @State private var accessibilityTrusted = AccessibilityService.isTrusted

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
                if let launchAtLoginError = settings.launchAtLoginError {
                    Label(launchAtLoginError, systemImage: "exclamationmark.triangle.fill")
                        .font(CopythatFont.font(size: 12))
                        .foregroundStyle(.orange)
                }
                Stepper(value: $settings.historyLimit, in: 100...1_000, step: 100) {
                    Text("History limit: \(settings.historyLimit)")
                }
                Toggle("Record sensitive clipboard contents", isOn: $settings.recordSensitiveContent)
            }

            Section("Shortcut") {
                Picker("Global shortcut", selection: $settings.shortcut) {
                    ForEach(AppSettings.GlobalShortcut.allCases) { shortcut in
                        Text(shortcut.rawValue).tag(shortcut.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                if let shortcutError = settings.shortcutError {
                    Label(shortcutError, systemImage: "exclamationmark.triangle.fill")
                        .font(CopythatFont.font(size: 12))
                        .foregroundStyle(.orange)
                }
            }

            Section("Permissions") {
                HStack {
                    Label(accessibilityTrusted ? "Accessibility is enabled" : "Accessibility is disabled",
                          systemImage: accessibilityTrusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(accessibilityTrusted ? .green : .orange)
                    Spacer()
                    Button(accessibilityTrusted ? "Open Settings" : "Enable") {
                        requestAccessibility()
                    }
                }
            }

            Section("Ignore Applications") {
                TextEditor(text: $settings.ignoredApplications)
                    .font(CopythatFont.font(size: 13))
                    .frame(height: 96)
                Text("One application name per line.")
                    .font(CopythatFont.font(size: 12))
                    .foregroundStyle(.secondary)
            }

            Section("Appearance") {
                Picker("Mode", selection: $settings.appearance) {
                    ForEach(AppSettings.AppearanceMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .formStyle(.grouped)
        .font(CopythatFont.font(size: 13))
        .padding(16)
        .onAppear {
            accessibilityTrusted = AccessibilityService.isTrusted
        }
    }

    private func requestAccessibility() {
        accessibilityTrusted = AccessibilityService.requestIfNeeded()
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        if let url {
            NSWorkspace.shared.open(url)
        }
    }
}
