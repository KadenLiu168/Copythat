@testable import Copythat
import AppKit
import Foundation

/// Production-style application wiring: one persistence instance is the
/// restore worker's, the save worker's and the media loader's, so bootstrap
/// reads, commits and blob reads all name one directory and one blob store.
///
/// `initialItems` is deliberately omitted, so this takes the production path:
/// an empty in-memory Store plus an async restore.
@MainActor
func productionStyleAppModel(
    persistence: ClipboardHistoryPersistence,
    settings: AppSettings,
    pasteboard: NSPasteboard = NSPasteboard.withUniqueName(),
    historyLoader: (any ClipboardHistoryLoading)? = nil
) -> AppModel {
    AppModel(
        historySaveCoordinator: ClipboardHistorySaveCoordinator(
            worker: ClipboardHistorySaveWorker(persistence: persistence)
        ),
        pasteboard: pasteboard,
        settings: settings,
        mediaLoader: ClipboardHistoryMediaLoader(blobStore: persistence.blobStore),
        historyLoader: historyLoader ?? ClipboardHistoryRestoreWorker(persistence: persistence)
    )
}
