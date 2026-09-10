import AppKit
import Foundation
import ServiceManagement

struct CustomPinboard: Codable, Equatable, Identifiable {
    let name: String
    let color: PinboardColorToken

    var id: String { name }
}

enum PinboardColorToken: String, Codable, CaseIterable, Identifiable {
    case amber
    case green
    case cyan
    case blue
    case violet
    case pink

    var id: String { rawValue }

    var color: NSColor {
        let components: (hue: CGFloat, saturation: CGFloat, brightness: CGFloat) = switch self {
        case .amber: (0.08, 0.90, 0.95)
        case .green: (0.36, 0.80, 0.78)
        case .cyan: (0.52, 0.89, 0.85)
        case .blue: (0.60, 0.85, 0.92)
        case .violet: (0.74, 0.70, 0.85)
        case .pink: (0.93, 0.72, 0.97)
        }
        return NSColor(
            calibratedHue: components.hue,
            saturation: components.saturation,
            brightness: components.brightness,
            alpha: 1
        )
    }
}

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
                defaults.set(historyLimit, forKey: Keys.historyLimit)
            }
        }
    }
    @Published var recordSensitiveContent: Bool {
        didSet { defaults.set(recordSensitiveContent, forKey: Keys.recordSensitiveContent) }
    }
    @Published var ignoredApplications: String {
        didSet { defaults.set(ignoredApplications, forKey: Keys.ignoredApplications) }
    }
    @Published private(set) var customPinboards: [CustomPinboard] {
        didSet { persistCustomPinboards() }
    }
    @Published var shortcut: String {
        didSet {
            if GlobalShortcut(rawValue: shortcut) == nil {
                shortcut = GlobalShortcut.commandShiftV.rawValue
            } else {
                defaults.set(shortcut, forKey: Keys.shortcut)
            }
        }
    }
    @Published private(set) var shortcutError: String?
    @Published var appearance: AppearanceMode {
        didSet { defaults.set(appearance.rawValue, forKey: Keys.appearance) }
    }
    private let defaults: UserDefaults
    private var isRevertingLaunchAtLogin = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        launchAtLogin = SMAppService.mainApp.status == .enabled
        launchAtLoginError = nil
        historyLimit = Self.normalizedHistoryLimit(
            defaults.object(forKey: Keys.historyLimit) as? Int ?? 500
        )
        recordSensitiveContent = defaults.object(forKey: Keys.recordSensitiveContent) as? Bool ?? false
        ignoredApplications = defaults.string(forKey: Keys.ignoredApplications) ?? ""
        customPinboards = Self.loadCustomPinboards(from: defaults)
        shortcut = defaults.string(forKey: Keys.shortcut) ?? GlobalShortcut.commandShiftV.rawValue
        shortcutError = nil
        appearance = AppearanceMode(rawValue: defaults.string(forKey: Keys.appearance) ?? "") ?? .system
        persistCustomPinboards()
    }

    func createCustomPinboard(name: String, color: PinboardColorToken) -> CustomPinboard? {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty,
              !customPinboards.contains(where: { $0.name == normalizedName }) else {
            return nil
        }

        let pinboard = CustomPinboard(name: normalizedName, color: color)
        customPinboards.append(pinboard)
        return pinboard
    }

    func canCreateCustomPinboard(named name: String) -> Bool {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !normalizedName.isEmpty &&
            !customPinboards.contains(where: { $0.name == normalizedName })
    }

    func updateCustomPinboard(named name: String, newName: String, color: PinboardColorToken) -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let index = customPinboards.firstIndex(where: { $0.name == trimmedName }) else {
            return false
        }

        let trimmedNewName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedNewName.isEmpty,
              !customPinboards.contains(where: { $0.name == trimmedNewName && $0.name != trimmedName }) else {
            return false
        }

        customPinboards[index] = CustomPinboard(name: trimmedNewName, color: color)
        return true
    }

    func canUpdateCustomPinboard(named name: String, newName: String) -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNewName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedNewName.isEmpty &&
            !customPinboards.contains(where: { $0.name == trimmedNewName && $0.name != trimmedName })
    }

    func deleteCustomPinboard(named name: String) -> Bool {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let index = customPinboards.firstIndex(where: { $0.name == normalizedName }) else {
            return false
        }

        customPinboards.remove(at: index)
        return true
    }

    /// Encoder for the persisted `customPinboards` payload. `.sortedKeys` pins
    /// JSON key order, which a default JSONEncoder derives from per-process
    /// hash seeding; without it the stored bytes differ between launches for
    /// identical content. Static so tests can assert this configuration.
    static func makeCustomPinboardsEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return encoder
    }

    private func persistCustomPinboards() {
        guard let data = try? Self.makeCustomPinboardsEncoder().encode(customPinboards) else { return }
        defaults.set(data, forKey: Keys.customPinboards)
    }

    private static func loadCustomPinboards(from defaults: UserDefaults) -> [CustomPinboard] {
        if let data = defaults.data(forKey: Keys.customPinboards),
           let pinboards = try? JSONDecoder().decode([CustomPinboard].self, from: data) {
            return pinboards
        }

        let legacyText = defaults.string(forKey: Keys.pinboardsText) ?? "Work\nIdeas"
        return normalizedNames(from: legacyText).enumerated().map { index, name in
            CustomPinboard(
                name: name,
                color: PinboardColorToken.allCases[index % PinboardColorToken.allCases.count]
            )
        }
    }

    private static func normalizedNames(from text: String) -> [String] {
        text
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
        static let customPinboards = "customPinboards"
        static let shortcut = "shortcut"
        static let appearance = "appearance"
    }
}
