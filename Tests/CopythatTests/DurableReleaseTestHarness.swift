@testable import Copythat
import AppKit
import Foundation

/// Injects persistence write failures while a scenario runs. Rejections happen
/// before a write reaches disk, so a rejected commit leaves the previous
/// manifest and blob set exactly as they were.
final class WriteFailureSwitch: @unchecked Sendable {
    private let lock = NSLock()
    private var predicate: (URL) -> Bool = { _ in false }

    /// Blob payloads are written before the manifest, so failing them leaves the
    /// manifest untouched; failing the manifest exercises the commit step itself.
    func failBlobWrites() {
        failWrites { $0.pathExtension == "blob" }
    }

    func failManifestWrites() {
        failWrites { $0.pathExtension != "blob" }
    }

    func allowWrites() {
        failWrites { _ in false }
    }

    private func failWrites(_ predicate: @escaping (URL) -> Bool) {
        lock.lock()
        self.predicate = predicate
        lock.unlock()
    }

    func shouldFail(_ url: URL) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return predicate(url)
    }
}

/// Real persistence with explicit per-generation blocking, so a commit can be
/// held open while the store advances to a newer media identity.
actor BlockableHistorySaveWorker: ClipboardHistorySaving {
    private let persistence: ClipboardHistoryPersistence
    private var blockedGenerations: Set<UInt64>
    private var failingGenerations: Set<UInt64>
    private var startedGenerations: Set<UInt64> = []
    private var startWaiters: [UInt64: [CheckedContinuation<Void, Never>]] = [:]
    private var releaseWaiters: [UInt64: CheckedContinuation<Void, Never>] = [:]

    init(
        persistence: ClipboardHistoryPersistence,
        blockedGenerations: Set<UInt64> = [],
        failingGenerations: Set<UInt64> = []
    ) {
        self.persistence = persistence
        self.blockedGenerations = blockedGenerations
        self.failingGenerations = failingGenerations
    }

    func save(_ items: [ClipboardItem], generation: UInt64) async throws {
        startedGenerations.insert(generation)
        startWaiters.removeValue(forKey: generation)?.forEach { $0.resume() }

        if blockedGenerations.contains(generation) {
            await withCheckedContinuation { continuation in
                releaseWaiters[generation] = continuation
            }
        }
        // A failing generation throws before touching disk, so the previous
        // manifest and blob set stay exactly as the last successful commit left
        // them, matching a rejected blob write.
        guard !failingGenerations.contains(generation) else {
            throw MediaOperationCountersError.injectedWriteFailure
        }
        try persistence.save(items, garbageCollect: false)
    }

    func collectGarbage() async {
        persistence.collectGarbage()
    }

    /// Returns once `save` has been entered for the generation, so a later
    /// `release` cannot race the continuation it resumes.
    func waitUntilStarted(_ generation: UInt64) async {
        if startedGenerations.contains(generation) { return }
        await withCheckedContinuation { continuation in
            startWaiters[generation, default: []].append(continuation)
        }
    }

    func release(_ generation: UInt64) {
        blockedGenerations.remove(generation)
        releaseWaiters.removeValue(forKey: generation)?.resume()
    }
}

/// Blocks the first blob read until released. Because the media loader is an
/// actor and `seedCommitted` performs no I/O, holding its single entry point
/// busy suspends committed-media handling exactly at the seeding boundary.
final class GatedBlobReader: @unchecked Sendable {
    let readStarted = DispatchSemaphore(value: 0)
    let releaseRead = DispatchSemaphore(value: 0)

    private let lock = NSLock()
    private var isGateArmed = true

    func read(_ url: URL) throws -> Data {
        lock.lock()
        let shouldBlock = isGateArmed
        isGateArmed = false
        lock.unlock()
        if shouldBlock {
            readStarted.signal()
            _ = releaseRead.wait(timeout: .now() + 10)
        }
        return try Data(contentsOf: url)
    }
}

/// Isolated history root, defaults, real persistence with counted and gated
/// I/O, shared media loader, and production-shaped coordinator wiring. Fixture
/// identities are created before any measurement window.
@MainActor
final class DurableReleaseHarness {    let counters = MediaOperationCounters()
    let persistence: ClipboardHistoryPersistence
    let loader: ClipboardHistoryMediaLoader
    let settings: AppSettings
    let writeFailures = WriteFailureSwitch()
    /// The named pasteboard every store built by this harness writes through.
    let pasteboard: NSPasteboard

    private(set) var coordinator: ClipboardHistorySaveCoordinator

    private let directory: URL
    private let defaultsName: String
    private let defaults: UserDefaults
    private let gatedReader: GatedBlobReader?

    init(byteBudget: Int = 1_000_000, gatedReader: GatedBlobReader? = nil) {
        self.gatedReader = gatedReader
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DurableRelease-\(UUID().uuidString)", isDirectory: true)
        defaultsName = "DurableRelease.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsName)!
        defaults.removePersistentDomain(forName: defaultsName)

        let counters = self.counters
        let writeFailures = self.writeFailures
        persistence = ClipboardHistoryPersistence(
            directoryURL: directory,
            userDefaults: defaults,
            readData: { url in
                counters.record(read: url)
                if let gatedReader {
                    return try gatedReader.read(url)
                }
                return try Data(contentsOf: url)
            },
            writeData: { data, url in
                if writeFailures.shouldFail(url) {
                    throw MediaOperationCountersError.injectedWriteFailure
                }
                try data.write(to: url, options: [.atomic])
                counters.record(write: url)
            }
        )
        settings = AppSettings(defaults: defaults)
        pasteboard = NSPasteboard.withUniqueName()
        pasteboard.clearContents()
        loader = ClipboardHistoryMediaLoader(blobStore: persistence.blobStore, byteBudget: byteBudget)
        coordinator = ClipboardHistorySaveCoordinator(
            worker: ClipboardHistorySaveWorker(persistence: persistence)
        )
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: directory)
        defaults.removePersistentDomain(forName: defaultsName)
    }

    /// Mirrors production wiring: the store saves through the coordinator and
    /// the coordinator installs the store's durable-media handler. A scenario
    /// that needs held-open generations passes its own worker.
    @discardableResult
    func makeStore(
        initialItems: [ClipboardItem],
        worker: (any ClipboardHistorySaving)? = nil
    ) -> ClipboardStore {
        if let worker {
            coordinator = ClipboardHistorySaveCoordinator(worker: worker)
        }
        let coordinator = self.coordinator
        let pasteboard = self.pasteboard
        let store = ClipboardStore(
            settings: settings,
            sourceTracker: CopySourceTracker(),
            initialItems: initialItems,
            pasteboard: pasteboard,
            mediaLoader: loader,
            persistItems: { coordinator.requestSave($0) },
            fetchLinkMetadata: { _ in throw URLError(.unsupportedURL) },
            fetchLinkSnapshot: { _ in throw URLError(.unsupportedURL) }
        )
        coordinator.setDurableMediaHandler { [weak store] commit in
            await store?.handleDurableMediaCommit(commit)
        }
        return store
    }

    func flush() async -> Bool {
        await coordinator.flush()
    }

    /// Persists and flushes the store's current history, as a metadata or
    /// capture mutation would through `saveItems()`.
    func saveAndFlush(_ store: ClipboardStore) async -> Bool {
        coordinator.requestSave(store.items)
        return await coordinator.flush()
    }

    func manifestData() throws -> Data {
        try Data(contentsOf: persistence.historyURL)
    }

    static func commit(
        generation: UInt64,
        itemID: UUID,
        image: PreparedMedia? = nil,
        linkImage: PreparedMedia? = nil
    ) -> ClipboardHistoryDurableMediaCommit {
        ClipboardHistoryDurableMediaCommit(
            generation: generation,
            entries: [.init(itemID: itemID, image: image, linkImage: linkImage)]
        )
    }

    /// Writes a blob directly, outside the measured I/O, and returns its ID so a
    /// scenario can hold the loader's single entry point busy.
    func stageBlockerBlob(_ bytes: Data) throws -> String {
        let blobStore = persistence.blobStore
        try FileManager.default.createDirectory(at: blobStore.directoryURL, withIntermediateDirectories: true)
        let blobID = ClipboardHistoryBlobStore.sha256Hex(bytes)
        try bytes.write(to: blobStore.directoryURL.appendingPathComponent("\(blobID).blob"))
        return blobID
    }

    /// Resident heavy-media bytes per role, so ownership can be asserted
    /// separately for each history array.
    static func residentBytes(_ items: [ClipboardItem]) -> (image: Int, linkImage: Int) {
        (
            items.reduce(0) { $0 + ($1.imageData?.count ?? 0) },
            items.reduce(0) { $0 + ($1.linkImageData?.count ?? 0) }
        )
    }

    // MARK: - Gated seeding

    /// Occupies the loader's single entry point, then starts committed-media
    /// handling so it suspends exactly at its seeding await. The loader is
    /// provably blocked and the main actor is serial: the entry continuation
    /// resumes its waiter only after handling suspends, without relying on
    /// yields or sleeps for ordering. The returned
    /// task completes once the scenario releases the gate.
    func holdSeeding(
        gate: GatedBlobReader,
        store: ClipboardStore,
        commit: ClipboardHistoryDurableMediaCommit
    ) async throws -> Task<Void, Never> {
        let blockerID = try stageBlockerBlob(Data(repeating: 0x7f, count: 64))
        let holder = Task { _ = try? await loader.load(blobID: blockerID) }
        guard await DurableReleaseHarness.waitOffMainActor(gate.readStarted, timeout: .now() + 5) == .success else {
            throw GatedScenarioError.loaderDidNotStart
        }
        var handle: Task<Void, Never>!
        await withCheckedContinuation { entered in
            handle = Task { @MainActor in
                entered.resume()
                await store.handleDurableMediaCommit(commit)
            }
        }
        return Task {
            await handle.value
            await holder.value
        }
    }

    /// Waits on a semaphore without blocking the main actor. The gated read runs
    /// on the loader's executor, so blocking the main actor here would prevent
    /// the very task that signals it from ever starting.
    static func waitOffMainActor(
        _ semaphore: DispatchSemaphore,
        timeout: DispatchTime
    ) async -> DispatchTimeoutResult {
        await Task.detached { semaphore.wait(timeout: timeout) }.value
    }

    // MARK: - Fixtures

    static func imageItem(id: UUID, media: PreparedMedia) -> ClipboardItem {
        ClipboardItem(
            id: id,
            kind: .image,
            title: "Image \(id.uuidString.prefix(4))",
            preview: "Preview",
            sourceApp: "Tests",
            sourceAppIconData: nil,
            createdAt: Date(timeIntervalSince1970: 1_700_000_700),
            isPinned: false,
            pinboardName: nil,
            textValue: nil,
            fileURLs: [],
            imageData: media.data,
            imageBlobID: media.id
        )
    }

    static func bothRolesItem(id: UUID, image: PreparedMedia, linkImage: PreparedMedia) -> ClipboardItem {
        ClipboardItem(
            id: id,
            kind: .image,
            title: "Both roles",
            preview: "Both roles",
            sourceApp: "Tests",
            sourceAppIconData: nil,
            createdAt: Date(timeIntervalSince1970: 1_700_000_710),
            isPinned: false,
            pinboardName: nil,
            textValue: nil,
            fileURLs: [],
            imageData: image.data,
            imageBlobID: image.id,
            linkImageData: linkImage.data,
            linkImageBlobID: linkImage.id
        )
    }

    static func urlItem(id: UUID, linkTitle: String, linkImage: PreparedMedia) -> ClipboardItem {
        ClipboardItem(
            id: id,
            kind: .url,
            title: "example.com",
            preview: "https://example.com/\(id.uuidString)",
            sourceApp: "Tests",
            sourceAppIconData: nil,
            createdAt: Date(timeIntervalSince1970: 1_700_000_720),
            isPinned: false,
            pinboardName: nil,
            textValue: "https://example.com/\(id.uuidString)",
            fileURLs: [],
            imageData: nil,
            linkTitle: linkTitle,
            linkImageData: linkImage.data,
            linkImageBlobID: linkImage.id
        )
    }

    /// A small real PNG so paste delivery and drag can decode what they get.
    static func pngBytes(size: Int) -> Data {
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: size,
            pixelsHigh: size,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        for column in 0..<size {
            for row in 0..<size {
                bitmap.setColor(.systemRed, atX: column, y: row)
            }
        }
        return bitmap.representation(using: .png, properties: [:]) ?? Data()
    }

    static func textItem() -> ClipboardItem {
        ClipboardItem(
            id: UUID(),
            kind: .text,
            title: "Baseline",
            preview: "Baseline",
            sourceApp: "Tests",
            sourceAppIconData: nil,
            createdAt: Date(timeIntervalSince1970: 1_700_000_730),
            isPinned: false,
            pinboardName: nil,
            textValue: "Baseline",
            fileURLs: [],
            imageData: nil
        )
    }
}

enum GatedScenarioError: Error {
    case loaderDidNotStart
}
