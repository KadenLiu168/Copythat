import AppKit
import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
    let settings: AppSettings
    let sourceTracker: CopySourceTracker
    let store: ClipboardStore
    let historySaveCoordinator: ClipboardHistorySaveCoordinator

    convenience init() {
        #if DEBUG
        if let root = ProcessInfo.processInfo.environment["COPYTHAT_VERIFY_ROOT"] {
            guard root.hasPrefix("/"),
                  let suite = ProcessInfo.processInfo.environment["COPYTHAT_VERIFY_DEFAULTS_SUITE"],
                  suite.hasPrefix("local.copythat.verify."),
                  let defaults = UserDefaults(suiteName: suite),
                  let name = ProcessInfo.processInfo.environment["COPYTHAT_TEST_PASTEBOARD_NAME"] else {
                fatalError("Incomplete verification isolation configuration")
            }
            // Seed every setting read by AppSettings in the verification suite,
            // avoiding inherited application-domain values in UserDefaults' search list.
            defaults.setPersistentDomain([
                "historyLimit": 500, "recordSensitiveContent": false,
                "ignoredApplications": "", "customPinboards": Data("[]".utf8),
                "pinboardsText": "", "shortcut": AppSettings.GlobalShortcut.commandShiftV.rawValue,
                "appearance": AppSettings.AppearanceMode.system.rawValue,
            ], forName: suite)
            let persistence = ClipboardHistoryPersistence(
                directoryURL: URL(fileURLWithPath: root, isDirectory: true), userDefaults: defaults
            )
            self.init(
                historySaveCoordinator: ClipboardHistorySaveCoordinator(
                    worker: ClipboardHistorySaveWorker(persistence: persistence)
                ),
                pasteboard: NSPasteboard(name: NSPasteboard.Name(name)),
                settings: AppSettings(defaults: defaults), initialItems: []
            )
            return
        }
        #endif
        self.init(
            historySaveCoordinator: ClipboardHistorySaveCoordinator(),
            pasteboard: Self.capturePasteboard
        )
    }

    init(
        historySaveCoordinator: ClipboardHistorySaveCoordinator,
        pasteboard: NSPasteboard = .general,
        settings: AppSettings? = nil,
        initialItems: [ClipboardItem]? = nil
    ) {
        let settings = settings ?? AppSettings()
        let sourceTracker = CopySourceTracker()
        self.settings = settings
        self.sourceTracker = sourceTracker
        self.historySaveCoordinator = historySaveCoordinator
        let store = ClipboardStore(
            settings: settings,
            sourceTracker: sourceTracker,
            initialItems: initialItems,
            pasteboard: pasteboard,
            persistItems: { historySaveCoordinator.requestSave($0) }
        )
        self.store = store
        // D2: the tracker reports copy intent only; the store owns polling, stability,
        // and capture. Weak capture avoids a tracker → closure → store → tracker cycle.
        sourceTracker.onCopyIntentWake = { [weak store] in
            Task { @MainActor [weak store] in
                store?.handleCopyIntentWake()
            }
        }
    }

    private static var capturePasteboard: NSPasteboard {
        #if DEBUG
        if let name = ProcessInfo.processInfo.environment["COPYTHAT_TEST_PASTEBOARD_NAME"] {
            return NSPasteboard(name: NSPasteboard.Name(name))
        }
        #endif
        return .general
    }
}
