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
                settings: AppSettings(defaults: defaults), initialItems: [],
                mediaLoader: ClipboardHistoryMediaLoader(blobStore: persistence.blobStore)
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
        initialItems: [ClipboardItem]? = nil,
        mediaLoader: ClipboardHistoryMediaLoader = .shared,
        historyLoader: (any ClipboardHistoryLoading)? = nil,
        encodeImage: @escaping ClipboardStore.ImageCaptureEncoder = ClipboardStore.defaultImageEncoder
    ) {
        let settings = settings ?? AppSettings()
        let sourceTracker = CopySourceTracker()
        self.settings = settings
        self.sourceTracker = sourceTracker
        self.historySaveCoordinator = historySaveCoordinator
        let store = ClipboardStore(
            settings: settings,
            sourceTracker: sourceTracker,
            // Explicit startup items are purely in-memory and immediately
            // usable. Nil means production: an empty Store that restores.
            initialItems: initialItems ?? [],
            pasteboard: pasteboard,
            mediaLoader: mediaLoader,
            persistItems: { historySaveCoordinator.requestSave($0) },
            encodeImage: encodeImage
        )
        self.store = store
        // The store's loader is the same blob store this persistence writes to,
        // so committed bytes it seeds are the bytes display, paste, and drag
        // read back. A weak capture keeps the callback from retaining the store.
        historySaveCoordinator.setDurableMediaHandler { [weak store] commit in
            await store?.handleDurableMediaCommit(commit)
        }
        // D2: the tracker reports copy intent only; the store owns polling, stability,
        // and capture. Weak capture avoids a tracker → closure → store → tracker cycle.
        sourceTracker.onCopyIntentWake = { [weak store] in
            Task { @MainActor [weak store] in
                store?.handleCopyIntentWake()
            }
        }
        // Restoration starts only after both handlers exist, so a capture that
        // finalizes during the load already has its durable-media and
        // copy-intent owners. The loader is created here rather than in a
        // default argument so nothing loads eagerly, and only for the
        // production path: explicit items never invoke it.
        guard initialItems == nil else { return }
        store.beginHistoryRestore(with: historyLoader ?? ClipboardHistoryRestoreWorker())
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
