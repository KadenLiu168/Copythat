@testable import Copythat
import AppKit
import Foundation
import Testing

// MARK: - Controllable loader

enum ClipboardHistoryLoadingResult: Sendable {
    case success([ClipboardItem])
    case failure
}

/// Loader that reports when a load actually started, parks until the test
/// releases it, and only then produces its prepared outcome.
///
/// Every wait is a handled-transition gate, so a scenario observes real
/// transitions instead of sleeping or polling a clock: releasing before the
/// load parks is held as a credit, exactly like the controlled image encoder.
actor GatedClipboardHistoryLoader: ClipboardHistoryLoading {
    private var outcomes: [ClipboardHistoryLoadingResult]
    private var gate: CheckedContinuation<Void, Never>?
    private var unclaimedReleases = 0
    private var startedWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var loadCount = 0

    init(_ outcomes: [ClipboardHistoryLoadingResult] = [.success([])]) {
        self.outcomes = outcomes
    }

    func loadItems() async throws -> [ClipboardItem] {
        loadCount += 1
        let outcome = outcomes.isEmpty ? .success([]) : outcomes.removeFirst()
        let waiters = startedWaiters
        startedWaiters = []
        waiters.forEach { $0.resume() }
        await withCheckedContinuation { continuation in
            if unclaimedReleases > 0 {
                unclaimedReleases -= 1
                continuation.resume()
            } else {
                gate = continuation
            }
        }
        switch outcome {
        case .success(let items):
            return items
        case .failure:
            throw ClipboardHistoryRestoreError.injectedLoadFailure
        }
    }

    /// Resumes once a load has begun. Never blocks when one already did.
    func waitUntilStarted() async {
        guard loadCount == 0 else { return }
        await withCheckedContinuation { continuation in
            startedWaiters.append(continuation)
        }
    }

    func release() {
        if let gate {
            self.gate = nil
            gate.resume()
        } else {
            unclaimedReleases += 1
        }
    }
}

enum ClipboardHistoryRestoreError: Error {
    case injectedLoadFailure
}

// MARK: - Snapshot and save recorder

/// Records the exact snapshots the Store hands to its persistence entry point,
/// in order, so a scenario can assert not only how many saves were requested
/// but what each one contained.
final class HistorySaveRecorder: @unchecked Sendable {    private let lock = NSLock()
    private var recorded: [[ClipboardItem]] = []
    private let events = LinkPreviewCounter()

    func record(_ items: [ClipboardItem]) {
        lock.lock()
        recorded.append(items)
        lock.unlock()
        events.mark("save")
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return recorded.count
    }

    var snapshots: [[ClipboardItem]] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    var latestTextValues: [String?] {
        snapshots.last?.map(\.textValue) ?? []
    }

    func waitForSave(_ threshold: Int) async {
        await events.waitFor("save", reaching: threshold)
    }
}

// MARK: - Restore harness

/// One Store wired for deterministic restoration observation: a gated loader,
/// settings the scenario can change mid-flight, and a recorder for every
/// requested history snapshot.
@MainActor
final class HistoryRestoreHarness {
    let store: ClipboardStore
    let loader: GatedClipboardHistoryLoader
    let saves: HistorySaveRecorder
    let settings: AppSettings
    let pasteboard: NSPasteboard
    let metadataRequests: HistoryURLObserver
    let metadataEvents: LinkPreviewCounter
    let enforcementEvents: LinkPreviewCounter
    let encoder: ControlledImageEncoder
    let imageHandledEvents: LinkPreviewCounter
    let clock: MutableClock
    let defaultsName: String

    init(
        outcomes: [ClipboardHistoryLoadingResult] = [.success([])],
        limit: Int? = nil,
        sourceApp: String = "Tests",
        sourceIcon: Data? = nil
    ) {
        let label = "HistoryRestore.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: label)!
        defaults.removePersistentDomain(forName: label)
        defaultsName = label
        // The limit must exist before AppSettings reads it.
        if let limit {
            defaults.set(limit, forKey: "historyLimit")
        }
        let settings = AppSettings(defaults: defaults)
        self.settings = settings
        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.clearContents()
        self.pasteboard = pasteboard
        let saves = HistorySaveRecorder()
        self.saves = saves
        let loader = GatedClipboardHistoryLoader(outcomes)
        self.loader = loader
        let metadataRequests = HistoryURLObserver()
        self.metadataRequests = metadataRequests
        let metadataEvents = LinkPreviewCounter()
        self.metadataEvents = metadataEvents
        let enforcementEvents = LinkPreviewCounter()
        self.enforcementEvents = enforcementEvents
        let encoder = ControlledImageEncoder()
        self.encoder = encoder
        let imageHandledEvents = LinkPreviewCounter()
        self.imageHandledEvents = imageHandledEvents
        let clock = MutableClock()
        self.clock = clock
        // A deterministic frontmost source, so admission-time attribution is
        // observable rather than dependent on the real foreground app.
        let source = ClipboardSource(appName: sourceApp, iconData: sourceIcon, capturedAt: Date())
        self.store = ClipboardStore(
            settings: settings,
            sourceTracker: CopySourceTracker(frontmostSourceProvider: { source }),
            initialItems: [],
            pasteboard: pasteboard,
            persistItems: { saves.record($0) },
            uptimeProvider: { clock.now },
            fetchLinkMetadata: { url in
                metadataRequests.record(url)
                metadataEvents.mark("metadata")
                throw URLError(.unsupportedURL)
            },
            fetchLinkSnapshot: { _ in throw URLError(.unsupportedURL) },
            encodeImage: { cgImage, recorder in
                await encoder.encode(cgImage, recorder: recorder)
            }
        )
        store.historyBoundsEnforcedObserver = { enforcementEvents.mark("enforced") }
        store.linkPreviewHandledObserver = { metadataEvents.mark("metadataHandled") }
        store.imageCompletionHandledObserver = { imageHandledEvents.mark("imageHandled") }
    }

    /// Awaits the Nth admitted image completion being applied or rejected.
    func awaitImageCompletion(_ count: Int) async {
        await imageHandledEvents.waitFor("imageHandled", reaching: count)
    }

    /// Drives one image through the real pasteboard admission path: an external
    /// write, a first observation, then a poll past the stability interval.
    func capture(_ image: NSImage) {
        pasteboard.clearContents()
        #expect(pasteboard.writeObjects([image]))
        store.pollPasteboard()
        clock.advance(by: 1)
        store.pollPasteboard()
    }

    /// Awaits the Nth eager metadata request actually reaching the loader. The
    /// loader runs inside a spawned task, so a scenario must gate on it rather
    /// than assume it has run by the time insertion returned.
    func awaitMetadataRequest(_ count: Int) async {
        await metadataEvents.waitFor("metadata", reaching: count)
    }

    /// Awaits the Nth processed link preview completion.
    func awaitMetadataCompletion(_ count: Int) async {
        await metadataEvents.waitFor("metadataHandled", reaching: count)
    }

    /// Enters the restoring state and waits until the loader is genuinely in
    /// flight, so the scenario never races the load it is about to suspend.
    func beginRestoring() async {
        store.beginHistoryRestore(with: loader)
        await loader.waitUntilStarted()
    }

    /// Releases the gated load and awaits the Store's own completion handle.
    func finishRestoring() async {
        await loader.release()
        await store.finishHistoryRestore()
    }

    /// Evaluated settings-driven history-limit enforcements so far. Capture
    /// this *before* changing the limit, so the await below is a real gate
    /// rather than a race against an already-completed turn.
    var historyEnforcementCount: Int { enforcementEvents.value("enforced") }

    /// Awaits the next settings-driven limit enforcement after `baseline`.
    func awaitHistoryEnforcement(after baseline: Int) async {
        await enforcementEvents.waitFor("enforced", reaching: baseline + 1)
    }

    func cleanUp() {
        UserDefaults.standard.removePersistentDomain(forName: defaultsName)
    }
}

/// Records URLs whose eager metadata enrichment actually started.
final class HistoryURLObserver: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [URL] = []

    func record(_ url: URL) {
        lock.lock()
        recorded.append(url)
        lock.unlock()
    }

    var urls: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    var absoluteStrings: [String] {
        urls.map(\.absoluteString)
    }
}

// MARK: - Items

enum HistoryRestoreFixture {
    static func textItem(
        _ text: String,
        id: UUID = UUID(),
        createdAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
        isPinned: Bool = false,
        pinboardName: String? = nil,
        sourceApp: String = "Tests",
        sourceIcon: Data? = nil
    ) -> ClipboardItem {
        ClipboardItem(
            id: id,
            kind: .text,
            title: text,
            preview: text,
            sourceApp: sourceApp,
            sourceAppIconData: sourceIcon,
            createdAt: createdAt,
            isPinned: isPinned,
            pinboardName: pinboardName,
            textValue: text,
            fileURLs: [],
            imageData: nil
        )
    }

    static func urlItem(
        _ url: String,
        id: UUID = UUID(),
        createdAt: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> ClipboardItem {
        ClipboardItem(
            id: id,
            kind: .url,
            title: url,
            preview: url,
            sourceApp: "Tests",
            sourceAppIconData: nil,
            createdAt: createdAt,
            isPinned: false,
            pinboardName: nil,
            textValue: url,
            fileURLs: [],
            imageData: nil
        )
    }

    static func imageItem(
        id: UUID = UUID(),
        media: PreparedMedia,
        createdAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
        isPinned: Bool = false
    ) -> ClipboardItem {
        ClipboardItem(
            id: id,
            kind: .image,
            title: "Image",
            preview: "Image",
            sourceApp: "Tests",
            sourceAppIconData: nil,
            createdAt: createdAt,
            isPinned: isPinned,
            pinboardName: nil,
            textValue: nil,
            fileURLs: [],
            imageData: media.data,
            imageBlobID: media.id
        )
    }
}

// MARK: - Production restore worker

@MainActor
@Suite(.serialized)
struct ClipboardHistoryRestoreWorkerTests {
    @Test func workerReadsTheRealPersistenceHookOffTheMainThread() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("HistoryRestoreWorker-\(UUID().uuidString)", isDirectory: true)
        let defaultsName = "HistoryRestoreWorker.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsName)!
        defer {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: defaultsName)
        }

        let persistence = ClipboardHistoryPersistence(directoryURL: directory, userDefaults: defaults)
        let item = HistoryRestoreFixture.textItem("worker loaded")
        try persistence.save([item])

        let probe = RestoreReadThreadProbe()
        let observed = ClipboardHistoryPersistence(
            directoryURL: directory,
            userDefaults: defaults,
            readData: { url in
                probe.record(threadIsMain: Thread.isMainThread)
                return try Data(contentsOf: url)
            }
        )
        let worker = ClipboardHistoryRestoreWorker(persistence: observed)

        let loaded = try await worker.loadItems()

        #expect(loaded == [item])
        #expect(probe.threadFlags == [false], "manifest reads must not run on the main thread")
        #expect(Thread.isMainThread, "the caller stays on MainActor across the await")
    }

    @Test func workerPreservesThrownErrorAndCorruptInputBackup() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("HistoryRestoreWorker-\(UUID().uuidString)", isDirectory: true)
        let defaultsName = "HistoryRestoreWorker.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsName)!
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: defaultsName)
        }

        let persistence = ClipboardHistoryPersistence(directoryURL: directory, userDefaults: defaults)
        let corrupt = Data(#"{"version":2,"items":[{"id":"not-a-uuid"}]}"#.utf8)
        try corrupt.write(to: persistence.historyURL, options: [.atomic])

        let worker = ClipboardHistoryRestoreWorker(persistence: persistence)

        var didThrow = false
        do {
            _ = try await worker.loadItems()
        } catch {
            didThrow = true
        }
        #expect(didThrow, "the instance failure must reach the caller instead of degrading to an empty baseline")
        #expect(try Data(contentsOf: persistence.historyURL) == corrupt, "the corrupt input itself stays untouched")

        let backups = try FileManager.default
            .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("clipboard-history-decode-failed-") }
        #expect(backups.count == 1, "the existing corrupt-input backup must still be written")
        #expect(try Data(contentsOf: try #require(backups.first)) == corrupt)
    }
}

/// Records whether each persistence read happened on the main thread. The probe
/// is written from the worker's executor, so counting is lock-guarded.
private final class RestoreReadThreadProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var flags: [Bool] = []

    func record(threadIsMain: Bool) {
        lock.lock()
        flags.append(threadIsMain)
        lock.unlock()
    }

    var threadFlags: [Bool] {
        lock.lock()
        defer { lock.unlock() }
        return flags
    }
}
