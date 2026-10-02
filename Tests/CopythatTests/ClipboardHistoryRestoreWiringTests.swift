@testable import Copythat
import AppKit
import Foundation
import Testing

/// Startup wiring and the disk-level lost-update guarantee: a capture that
/// arrives while the manifest read is still in flight must neither see a
/// replaced manifest nor commit a partial one.
@MainActor
@Suite(.serialized)
struct ClipboardHistoryRestoreWiringTests {

    // MARK: - 2.3 AppModel bootstrap ownership

    @Test func productionStyleConstructionReturnsWhileTheLoaderIsGated() async throws {
        let fixture = try HistoryRestoreDiskFixture()
        defer { fixture.cleanUp() }
        let loader = GatedClipboardHistoryLoader([.success([HistoryRestoreFixture.textItem("A")])])

        let model = productionStyleAppModel(
            persistence: fixture.persistence,
            settings: fixture.settings,
            historyLoader: loader
        )

        // Construction already returned, and the Store is in its loading state.
        #expect(model.store.isRestoringHistory)
        #expect(model.store.items.isEmpty)
        #expect(model.store.canMutateHistory == false)
        await loader.waitUntilStarted()

        // Ordinary launch monitoring can start while the load is suspended.
        model.store.startMonitoring()
        defer { model.store.stopMonitoring() }
        #expect(model.store.isRestoringHistory, "monitoring does not release the loader")
        #expect(model.store.items.isEmpty)

        await loader.release()
        await model.store.finishHistoryRestore()

        #expect(model.store.isRestoringHistory == false)
        #expect(model.store.canMutateHistory)
        #expect(model.store.items.map(\.textValue) == ["A"])
        #expect(await loader.loadCount == 1)
    }

    @Test func explicitInitialItemsInvokeTheLoaderZeroTimes() async throws {
        // The isolated verification configuration passes an explicit empty
        // list, and ordinary tests pass explicit items. Both must stay purely
        // in memory and must never touch a persisted-history loader.
        let supplied = [HistoryRestoreFixture.textItem("A"), HistoryRestoreFixture.textItem("B")]
        for initialItems in [supplied, []] {
            let fixture = try HistoryRestoreDiskFixture()
            defer { fixture.cleanUp() }
            let loader = GatedClipboardHistoryLoader([.success([])])

            let model = AppModel(
                historySaveCoordinator: ClipboardHistorySaveCoordinator(
                    worker: ClipboardHistorySaveWorker(persistence: fixture.persistence)
                ),
                pasteboard: NSPasteboard.withUniqueName(),
                settings: fixture.settings,
                initialItems: initialItems,
                mediaLoader: ClipboardHistoryMediaLoader(blobStore: fixture.persistence.blobStore),
                historyLoader: loader
            )

            #expect(model.store.isRestoringHistory == false, "explicit startup never enters restoring")
            #expect(model.store.restoreState == .ready)
            #expect(model.store.items.map(\.id) == initialItems.map(\.id))

            await model.store.finishHistoryRestore()
            #expect(await loader.loadCount == 0, "explicit items never invoke a loader")
            #expect(fixture.counters.manifestReadCount == 0, "explicit startup never reads production history")
            #expect(fixture.counters.blobReadCount == 0)
        }
    }

    // MARK: - 3.5 Disk-level lost update

    @Test func captureDuringBlockedRestoreNeverReplacesOrPartiallyRewritesTheManifest() async throws {
        let fixture = try HistoryRestoreDiskFixture()
        defer { fixture.cleanUp() }
        let saved = HistoryRestoreFixture.textItem("A", sourceApp: "Safari", sourceIcon: Data(repeating: 0xa1, count: 256))
        let alsoSaved = HistoryRestoreFixture.textItem("C", sourceApp: "Safari", sourceIcon: Data(repeating: 0xa1, count: 256))
        try fixture.persistence.save([saved, alsoSaved])
        let manifestBefore = try Data(contentsOf: fixture.persistence.historyURL)
        let blobsBefore = try fixture.blobSnapshot()
        fixture.counters.reset()

        let loader = GatedClipboardHistoryLoader([.success([saved, alsoSaved])])
        let model = productionStyleAppModel(
            persistence: fixture.persistence,
            settings: fixture.settings,
            historyLoader: loader
        )
        await loader.waitUntilStarted()

        let arriving = HistoryRestoreFixture.textItem("B")
        model.store.add(arriving)

        // Nothing reaches disk while the baseline is still loading.
        #expect(fixture.counters.manifestWriteCount == 0, "no history-save write while loading")
        #expect(fixture.counters.blobWriteCount == 0, "no capture blob write while loading")
        #expect(try Data(contentsOf: fixture.persistence.historyURL) == manifestBefore, "the old manifest is intact")
        #expect(try fixture.blobSnapshot() == blobsBefore, "referenced blobs are intact")

        await loader.release()
        await model.store.finishHistoryRestore()
        #expect(await model.historySaveCoordinator.flush())

        // The commit is the policy-derived baseline plus the arrival, not a
        // B-only intermediate and not the old baseline alone.
        let committed = try fixture.persistence.loadItems()
        #expect(committed.map(\.textValue) == ["B", "A", "C"])
        #expect(committed.map(\.id) == [arriving.id, saved.id, alsoSaved.id])
        #expect(committed.map(\.sourceApp) == ["Tests", "Safari", "Safari"])
    }
}

// MARK: - Fixture

/// One isolated persistence root shared by the restore worker, the save worker
/// and the media loader, plus the counters that account for its I/O.
@MainActor
final class HistoryRestoreDiskFixture {
    let directory: URL
    let defaultsName: String
    let defaults: UserDefaults
    let counters = MediaOperationCounters()
    let persistence: ClipboardHistoryPersistence
    let settings: AppSettings

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("HistoryRestoreDisk-\(UUID().uuidString)", isDirectory: true)
        defaultsName = "HistoryRestoreDisk.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsName)!
        defaults.removePersistentDomain(forName: defaultsName)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        persistence = counters.makePersistence(directoryURL: directory, userDefaults: defaults)
        settings = AppSettings(defaults: defaults)
    }

    func blobSnapshot() throws -> [String: Data] {
        let mediaDirectory = directory.appendingPathComponent("history-media", isDirectory: true)
        guard FileManager.default.fileExists(atPath: mediaDirectory.path) else { return [:] }
        return try FileManager.default.contentsOfDirectory(at: mediaDirectory, includingPropertiesForKeys: nil)
            .reduce(into: [:]) { snapshot, url in
                snapshot[url.lastPathComponent] = try Data(contentsOf: url)
            }
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: directory)
        defaults.removePersistentDomain(forName: defaultsName)
    }
}
