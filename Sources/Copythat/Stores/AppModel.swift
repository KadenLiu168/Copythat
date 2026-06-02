import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
    let settings: AppSettings
    let sourceTracker: CopySourceTracker
    let store: ClipboardStore

    init() {
        let settings = AppSettings()
        let sourceTracker = CopySourceTracker()
        self.settings = settings
        self.sourceTracker = sourceTracker
        store = ClipboardStore(settings: settings, sourceTracker: sourceTracker)
    }
}
