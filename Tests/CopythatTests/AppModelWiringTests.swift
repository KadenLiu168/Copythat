@testable import Copythat
import AppKit
import Foundation
import Testing

private actor AppModelSaveRecorder: ClipboardHistorySaving {
    private var snapshots: [[String?]] = []

    func save(_ items: [ClipboardItem], generation: UInt64) async throws {
        snapshots.append(items.map(\.textValue))
    }

    func collectGarbage() async {}

    func recordedSnapshots() -> [[String?]] {
        snapshots
    }
}

@MainActor
@Suite(.serialized)
struct AppModelWiringTests {
    @Test func storeMutationsReachTheInjectedHistorySaveCoordinator() async {
        let worker = AppModelSaveRecorder()
        let coordinator = ClipboardHistorySaveCoordinator(worker: worker)
        let model = isolatedAppModel(coordinator: coordinator)
        let sentinel = "AppModel persistence wiring \(UUID().uuidString)"
        let item = ClipboardItem(
            id: UUID(),
            kind: .text,
            title: sentinel,
            preview: sentinel,
            sourceApp: "Tests",
            sourceAppIconData: nil,
            createdAt: Date(timeIntervalSince1970: 1_700_000_081),
            isPinned: false,
            pinboardName: nil,
            textValue: sentinel,
            fileURLs: [],
            imageData: nil
        )

        model.store.add(item)

        #expect(await coordinator.flush())
        #expect(await worker.recordedSnapshots().last?.contains(sentinel) == true)
        let snapshotContainsMutation = await worker.recordedSnapshots().last?.contains(sentinel) == true
        AcceptanceMetrics.record(
            scenario: "app-model-wiring",
            metric: "coordinatorSnapshotContainsStoreMutation",
            expected: "true",
            observed: "\(snapshotContainsMutation)"
        )
    }

    @Test func trackerWakeReachesStoreAndStartsOrExtendsTheStoreBurst() async {
        let model = isolatedAppModel()
        defer { model.store.stopMonitoring() }
        model.store.startMonitoring()

        // Same closure the tracker fires for a recognized copy/cut/screenshot intent.
        model.sourceTracker.onCopyIntentWake?()
        #expect(
            await waitUntil(timeout: 2.0) { model.store.isBurstPollingActive },
            "tracker wake must hop to the main actor and start the store-owned burst"
        )

        model.sourceTracker.onCopyIntentWake?()
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(model.store.isBurstPollingActive, "repeated wake must extend the single burst")
    }

    @Test func storeDeallocatesAfterModelIsReleased() {
        var model: AppModel? = isolatedAppModel()
        weak var weakStore = model?.store
        weak var weakTracker = model?.sourceTracker
        #expect(weakStore != nil)
        #expect(weakTracker != nil)

        model = nil

        #expect(weakStore == nil, "the wake wiring must capture the store weakly")
        #expect(weakTracker == nil)
    }

    @Test func durableMediaCallbackKeepsTheStoreWeakly() {
        var model: AppModel? = isolatedAppModel()
        weak var weakStore = model?.store
        weak var weakCoordinator = model?.historySaveCoordinator
        #expect(weakStore != nil)
        #expect(weakCoordinator != nil)

        model = nil

        // The store's save closure holds the coordinator, so only a weak capture
        // inside the durable-media handler keeps this pair from cycling.
        #expect(weakCoordinator == nil)
        #expect(weakStore == nil, "the durable-media handler must not retain the store")
    }

    @Test func modelWiringReleasesCommittedImageAndServesItFromTheSharedLoader() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppModelDurableRelease-\(UUID().uuidString)", isDirectory: true)
        let defaultsName = "AppModelDurableRelease.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsName)!
        defaults.removePersistentDomain(forName: defaultsName)
        defer {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: defaultsName)
        }

        let counters = MediaOperationCounters()
        let persistence = counters.makePersistence(directoryURL: directory, userDefaults: defaults)
        let loader = ClipboardHistoryMediaLoader(blobStore: persistence.blobStore)
        let model = AppModel(
            historySaveCoordinator: ClipboardHistorySaveCoordinator(
                worker: ClipboardHistorySaveWorker(persistence: persistence)
            ),
            pasteboard: NSPasteboard.withUniqueName(),
            settings: AppSettings(defaults: defaults),
            initialItems: [],
            mediaLoader: loader
        )
        let media = PreparedMedia(hashing: Data(repeating: 0xf1, count: 192))
        let item = ClipboardItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000f1")!,
            kind: .image,
            title: "Wired image",
            preview: "Wired image",
            sourceApp: "Tests",
            sourceAppIconData: nil,
            createdAt: Date(timeIntervalSince1970: 1_700_000_600),
            isPinned: false,
            pinboardName: nil,
            textValue: nil,
            fileURLs: [],
            imageData: media.data,
            imageBlobID: media.id
        )

        model.store.add(item)
        #expect(await model.historySaveCoordinator.flush())

        #expect(model.store.items.first?.imageData == nil)
        #expect(model.store.items.first?.imageBlobID == media.id)
        #expect(model.store.filteredItems.first?.imageData == nil)

        counters.reset()
        #expect(try await loader.load(blobID: media.id) == media.data)
        #expect(counters.blobReadCount == 0, "the store's loader must be the persistence's own blob store")
        AcceptanceMetrics.record(
            scenario: "app-model-wiring",
            metric: "blobReadsAfterCommitThroughModelWiring",
            expected: "0",
            observed: "\(counters.blobReadCount)"
        )
    }

    private func waitUntil(
        timeout seconds: TimeInterval,
        _ condition: () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        return condition()
    }
}
