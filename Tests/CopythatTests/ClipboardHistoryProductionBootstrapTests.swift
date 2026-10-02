@testable import Copythat
import AppKit
import Foundation
import Testing

/// Production bootstrap contracts: real V2 persistence, the real restore worker
/// actor, and the real SaveCoordinator, over media-heavy history.
@MainActor
@Suite(.serialized)
struct ClipboardHistoryProductionBootstrapTests {

    // MARK: - 7.1 V2 media stays lazy through production bootstrap

    @Test func productionWorkerBootstrapOfMediaHeavyHistoryReadsOnlyTheManifestAndIcons() async throws {
        let fixture = try ProductionBootstrapFixture()
        defer { fixture.cleanUp() }

        let (persisted, heavyBlobIDs) = ProductionBootstrapFixture.mediaHeavyHistory()
        try fixture.persistence.save(persisted)
        fixture.counters.reset()

        // The production path: an empty in-memory Store, the real restore worker
        // actor, and the real save coordinator over one shared persistence root.
        let model = await fixture.counters.measure {
            let model = productionStyleAppModel(
                persistence: fixture.persistence,
                settings: fixture.settings
            )
            #expect(model.store.isRestoringHistory, "construction already returned in the loading state")
            await model.store.finishHistoryRestore()
            return model
        }

        // Read accounting is measured over the restore window only.
        #expect(fixture.counters.manifestReadCount == 1, "exactly one manifest read")
        #expect(fixture.counters.blobReadCount == 4, "each shared source icon is read once")
        #expect(fixture.counters.integrityHashCount == 4, "each source icon is verified once")
        #expect(fixture.counters.identityHashCount == 0, "known media identities are never recomputed")
        #expect(fixture.counters.manifestWriteCount == 0, "restore writes nothing")
        #expect(fixture.counters.blobWriteCount == 0, "restore writes no blobs")
        #expect(fixture.heavyBlobReadCount(in: heavyBlobIDs) == 0, "zero heavy reads")

        #expect(model.store.restoreState == .ready)
        #expect(model.store.isRestoringHistory == false)
        #expect(model.store.items.allSatisfy { $0.imageData == nil && $0.linkImageData == nil },
                "heavy Data is absent after restore")
        #expect(model.store.items.allSatisfy { $0.sourceAppIconData != nil },
                "eager deduplicated source icons are resident")

        // Retention is the ordinary policy's. The restored copy deliberately
        // differs from the in-memory fixture by absent heavy bytes, so identity
        // is compared rather than full value equality.
        let retained = try #require(ClipboardHistoryPolicy.enforcingLimits(
            on: persisted,
            limit: fixture.settings.historyLimit
        ).items)
        #expect(model.store.items.count == retained.count)
        #expect(Set(model.store.items.map(\.id)) == Set(retained.map(\.id)))
        #expect(model.store.items.map(\.contentKey) == retained.map(\.contentKey))
        #expect(model.store.items.map(\.createdAt) == retained.map(\.createdAt))
        #expect(model.store.items.map(\.title) == retained.map(\.title))

        #expect(await model.historySaveCoordinator.flush())

        // The manifest stays V2 and never carries a runtime corpus. Pinned
        // images leave only 100 ordinary images, so this is a clean restore.
        let manifest = try #require(String(data: Data(contentsOf: fixture.persistence.historyURL), encoding: .utf8))
        let object = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: fixture.persistence.historyURL)) as? [String: Any]
        )
        #expect(object["version"] as? Int == 2, "schema version 2 is unchanged")
        #expect(manifest.contains("searchText") == false, "no search corpus is persisted")

        // Retained metadata is searchable without any media access.
        model.store.searchText = "Item 499"
        #expect(model.store.filteredItems.count == 1)
        model.store.searchText = ""
    }

    @Test func restoredHistoryRemainsReadableThroughTheSharedMediaLoader() async throws {
        let fixture = try ProductionBootstrapFixture()
        defer { fixture.cleanUp() }
        let (persisted, _) = ProductionBootstrapFixture.mediaHeavyHistory()
        try fixture.persistence.save(persisted)

        let model = productionStyleAppModel(
            persistence: fixture.persistence,
            settings: fixture.settings
        )
        await model.store.finishHistoryRestore()

        let item = try #require(model.store.items.first { $0.imageBlobID != nil })
        let blobID = try #require(item.imageBlobID)
        #expect(await model.historySaveCoordinator.flush())
        fixture.counters.reset()

        let loaded = try await fixture.counters.measure {
            try await model.store.mediaLoader.load(blobID: blobID)
        }

        #expect(loaded.count > 0)
        #expect(fixture.counters.integrityHashCount == 1, "the blob is verified once on demand")
    }

    // MARK: - 7.2 Corpus and identity accounting across the actor boundary

    @Test func restoreBuildsOneCorpusPerItemWithoutRebuildingDuringApplication() async throws {
        let fixture = try ProductionBootstrapFixture()
        defer { fixture.cleanUp() }
        let (persisted, _) = ProductionBootstrapFixture.mediaHeavyHistory()
        try fixture.persistence.save(persisted)
        fixture.counters.reset()

        let recorder = SearchCorpusRecorder()
        await fixture.counters.measure {
            await SearchCorpusObservation.$recorder.withValue(recorder) {
                let model = productionStyleAppModel(
                    persistence: fixture.persistence,
                    settings: fixture.settings
                )
                await model.store.finishHistoryRestore()

                #expect(model.store.items.count > 0)
                #expect(recorder.count == persisted.count, "one corpus per decoded item, before retention")
                #expect(fixture.counters.identityHashCount == 0)
                let afterRestore = recorder.count
                model.store.searchText = "Item 10"
                model.store.searchText = "Item 20"
                model.store.selectedBoardID = Pinboard.pinned.id
                model.store.selectedBoardID = Pinboard.all.id
                #expect(recorder.count == afterRestore, "search rebuilds no corpus within the observation scope")
                #expect(fixture.counters.identityHashCount == 0)
                #expect(await model.historySaveCoordinator.flush())
            }
        }
    }
}

// MARK: - Fixture

/// One persistence root shared by the restore worker, the save worker and the
/// media loader, with I/O and hash accounting separated per window.
@MainActor
final class ProductionBootstrapFixture {
    let directory: URL
    let defaultsName: String
    let defaults: UserDefaults
    let counters = MediaOperationCounters()
    let persistence: ClipboardHistoryPersistence
    let settings: AppSettings
    private let readNames = RestoreReadNameBox()

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProductionBootstrap-\(UUID().uuidString)", isDirectory: true)
        defaultsName = "ProductionBootstrap.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsName)!
        defaults.removePersistentDomain(forName: defaultsName)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let counters = self.counters
        let readNames = self.readNames
        persistence = ClipboardHistoryPersistence(
            directoryURL: directory,
            userDefaults: defaults,
            readData: { url in
                counters.record(read: url)
                readNames.record(url.lastPathComponent)
                return try Data(contentsOf: url)
            },
            writeData: { data, url in
                try data.write(to: url, options: [.atomic])
                counters.record(write: url)
            }
        )
        settings = AppSettings(defaults: defaults)
    }

    /// Blobs read inside the current window whose address is a heavy payload
    /// rather than a deduplicated source icon.
    func heavyBlobReadCount(in heavyBlobIDs: Set<String>) -> Int {
        readNames.names.filter { name in
            guard name.hasSuffix(".blob") else { return false }
            return heavyBlobIDs.contains(String(name.dropLast(5)))
        }.count
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: directory)
        defaults.removePersistentDomain(forName: defaultsName)
    }

    /// 500 media-heavy V2 items sharing four source icons: 250 images and 250
    /// URL items, half of which also carry a link-preview image blob.
    static func mediaHeavyHistory() -> ([ClipboardItem], Set<String>) {
        let icons = (0..<4).map { PreparedMedia(hashing: Data(repeating: 0x10 + $0, count: 512)) }
        var heavyBlobIDs = Set<String>()
        var items: [ClipboardItem] = []
        for index in 0..<500 {
            let heavy = PreparedMedia(hashing: Data(repeating: UInt8(index % 251), count: 4_096))
            heavyBlobIDs.insert(heavy.id)
            let link = index % 2 == 0 ? PreparedMedia(hashing: Data(repeating: 0x70 + UInt8(index % 97), count: 1_024)) : nil
            if let link {
                heavyBlobIDs.insert(link.id)
            }
            items.append(
                ClipboardItem(
                    id: UUID(),
                    kind: index % 2 == 0 ? .image : .url,
                    title: "Item \(index)",
                    preview: "Preview \(index)",
                    sourceApp: "App \(index % 4)",
                    sourceAppIconData: icons[index % 4].data,
                    sourceAppIconBlobID: icons[index % 4].id,
                    createdAt: Date(timeIntervalSince1970: 1_700_000_000 + TimeInterval(500 - index)),
                    // Keep all 500 items within the existing image bound.
                    isPinned: index.isMultiple(of: 2) && index < 300,
                    pinboardName: nil,
                    textValue: index % 2 == 0 ? nil : "https://example.com/item/\(index)",
                    fileURLs: [],
                    imageData: index % 2 == 0 ? heavy.data : nil,
                    imageBlobID: index % 2 == 0 ? heavy.id : nil,
                    linkImageData: link?.data,
                    linkImageBlobID: link?.id
                )
            )
        }
        return (items, heavyBlobIDs)
    }
}

/// Records the file names a persistence read touched inside one window, so a
/// scenario can tell a deduplicated icon read from a heavy payload read.
final class RestoreReadNameBox: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [String] = []

    func record(_ name: String) {
        lock.lock()
        recorded.append(name)
        lock.unlock()
    }

    var names: [String] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }
}
