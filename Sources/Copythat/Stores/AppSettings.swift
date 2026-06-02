import Foundation
import ServiceManagement

@MainActor
final class AppSettings: ObservableObject {
    @Published var launchAtLogin: Bool {
        didSet {
            guard !isRevertingLaunchAtLogin else { return }
            updateLaunchAtLogin(previousValue: oldValue)
        }
    }
    @Published private(set) var launchAtLoginError: String?
    @Published var historyLimit: Int {
        didSet {
            let normalized = Self.normalizedHistoryLimit(historyLimit)
            if historyLimit != normalized {
                historyLimit = normalized
            } else {
                UserDefaults.standard.set(historyLimit, forKey: Keys.historyLimit)
            }
        }
    }
    @Published var recordSensitiveContent: Bool {
        didSet { UserDefaults.standard.set(recordSensitiveContent, forKey: Keys.recordSensitiveContent) }
    }
    @Published var ignoredApplications: String {
        didSet { UserDefaults.standard.set(ignoredApplications, forKey: Keys.ignoredApplications) }
    }
    @Published var pinboardsText: String {
        didSet { UserDefaults.standard.set(pinboardsText, forKey: Keys.pinboardsText) }
    }
    @Published var shortcut: String {
        didSet {
            if GlobalShortcut(rawValue: shortcut) == nil {
                shortcut = GlobalShortcut.commandShiftV.rawValue
            } else {
                UserDefaults.standard.set(shortcut, forKey: Keys.shortcut)
            }
        }
    }
    @Published private(set) var shortcutError: String?
    @Published var appearance: AppearanceMode {
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: Keys.appearance) }
    }
    private var isRevertingLaunchAtLogin = false

    init() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
        launchAtLoginError = nil
        historyLimit = Self.normalizedHistoryLimit(
            UserDefaults.standard.object(forKey: Keys.historyLimit) as? Int ?? 500
        )
        recordSensitiveContent = UserDefaults.standard.object(forKey: Keys.recordSensitiveContent) as? Bool ?? false
        ignoredApplications = UserDefaults.standard.string(forKey: Keys.ignoredApplications) ?? ""
        pinboardsText = UserDefaults.standard.string(forKey: Keys.pinboardsText) ?? "Work\nIdeas"
        shortcut = UserDefaults.standard.string(forKey: Keys.shortcut) ?? GlobalShortcut.commandShiftV.rawValue
        shortcutError = nil
        appearance = AppearanceMode(rawValue: UserDefaults.standard.string(forKey: Keys.appearance) ?? "") ?? .system
    }

    var customPinboards: [String] {
        pinboardsText
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .uniqued()
    }

    private func updateLaunchAtLogin(previousValue: Bool) {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginError = nil
        } catch {
            isRevertingLaunchAtLogin = true
            launchAtLogin = previousValue
            isRevertingLaunchAtLogin = false
            launchAtLoginError = "Launch at login could not be changed."
        }
    }

    private static func normalizedHistoryLimit(_ value: Int) -> Int {
        min(max(value, 100), 1_000)
    }

    func setShortcutRegistrationStatus(_ status: OSStatus) {
        shortcutError = status == noErr ? nil : "Global shortcut could not be registered."
    }

    enum AppearanceMode: String, CaseIterable, Identifiable {
        case system
        case light
        case dark

        var id: String { rawValue }

        var label: String {
            switch self {
            case .system: "System"
            case .light: "Light"
            case .dark: "Dark"
            }
        }
    }

    enum GlobalShortcut: String, CaseIterable, Identifiable {
        case commandShiftV = "⌘⇧V"
        case optionSpace = "⌥Space"
        case controlSpace = "⌃Space"

        var id: String { rawValue }
    }

    private enum Keys {
        static let historyLimit = "historyLimit"
        static let recordSensitiveContent = "recordSensitiveContent"
        static let ignoredApplications = "ignoredApplications"
        static let pinboardsText = "pinboardsText"
        static let shortcut = "shortcut"
        static let appearance = "appearance"
    }
}
