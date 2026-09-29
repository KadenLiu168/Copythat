@testable import Copythat
import AppKit
import Foundation

private actor DiscardHistorySaves: ClipboardHistorySaving {
    func save(_ items: [ClipboardItem], generation: UInt64) async throws {}
    func collectGarbage() async {}
}

@MainActor
func isolatedAppModel(coordinator: ClipboardHistorySaveCoordinator? = nil) -> AppModel {
    let mediaDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("IsolatedAppModel-\(UUID().uuidString)/history-media", isDirectory: true)
    return AppModel(
        historySaveCoordinator: coordinator ?? ClipboardHistorySaveCoordinator(worker: DiscardHistorySaves()),
        pasteboard: NSPasteboard.withUniqueName(),
        settings: isolatedAppSettings(), initialItems: [],
        mediaLoader: ClipboardHistoryMediaLoader(
            blobStore: ClipboardHistoryBlobStore(
                directoryURL: mediaDirectory,
                readData: { try Data(contentsOf: $0) }
            )
        )
    )
}

@MainActor
func isolatedAppSettings() -> AppSettings {
    let suite = "CopythatTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    let settings = AppSettings(defaults: defaults)
    defaults.removePersistentDomain(forName: suite)
    return settings
}
