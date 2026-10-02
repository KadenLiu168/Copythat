import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var store: ClipboardStore
    @State private var accessibilityTrusted = AccessibilityService.isTrusted
    @State private var isShowingClearHistoryConfirmation = false

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
                HStack {
                    // A count read while loading would look like an
                    // authoritative zero, so it is identified as loading.
                    Text(HistoryPresentation.cardSummary(
                        isRestoring: store.isRestoringHistory,
                        cardCount: store.items.count
                    ))
                    .lineLimit(1)
                    Spacer()
                    Button("Clear Cards...") {
                        // Re-checked on activation: the window may have been
                        // open before history finished restoring.
                        guard store.canMutateHistory else { return }
                        isShowingClearHistoryConfirmation = true
                    }
                    .disabled(!HistoryPresentation.canClearCards(
                        isRestoring: store.isRestoringHistory,
                        canMutateHistory: store.canMutateHistory,
                        cardCount: store.items.count
                    ))
                }
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
        .confirmationDialog(
            "Clear cards?",
            isPresented: $isShowingClearHistoryConfirmation
        ) {
            Button("Clear Regular Cards", role: .destructive) {
                clearHistory(includePinnedAndPinboardItems: false)
            }
            Button("Clear All Cards", role: .destructive) {
                clearHistory(includePinnedAndPinboardItems: true)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Regular cards exclude pinned cards and cards in pinboards.")
        }
    }

    /// A confirmation that runs while history mutations are unavailable does
    /// nothing at all: no deletion, no pasteboard clear, no image invalidation
    /// and no save request, and it is never deferred until later.
    private func clearHistory(includePinnedAndPinboardItems: Bool) {
        guard store.canMutateHistory else { return }
        isShowingClearHistoryConfirmation = false
        store.clearHistory(includePinnedAndPinboardItems: includePinnedAndPinboardItems)
    }

    private func requestAccessibility() {
        accessibilityTrusted = AccessibilityService.requestIfNeeded()
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        if let url {
            NSWorkspace.shared.open(url)
        }
    }
}
