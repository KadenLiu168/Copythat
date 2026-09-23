import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
    let settings: AppSettings
    let sourceTracker: CopySourceTracker
    let store: ClipboardStore
    let historySaveCoordinator: ClipboardHistorySaveCoordinator

    convenience init() {
        self.init(historySaveCoordinator: ClipboardHistorySaveCoordinator())
    }

    init(historySaveCoordinator: ClipboardHistorySaveCoordinator) {
        let settings = AppSettings()
        let sourceTracker = CopySourceTracker()
        self.settings = settings
        self.sourceTracker = sourceTracker
        self.historySaveCoordinator = historySaveCoordinator
        let store = ClipboardStore(
            settings: settings,
            sourceTracker: sourceTracker,
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
}
