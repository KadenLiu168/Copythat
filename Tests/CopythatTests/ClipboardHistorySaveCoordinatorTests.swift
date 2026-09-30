@testable import Copythat
import Foundation
import Testing

private struct RecordedHistoryCommit: Equatable, Sendable {
    let generation: UInt64
    let text: String
}

private enum ControlledWorkerFailure: Error {
    case injectedSaveFailure
}

/// Captures the receipts a coordinator handler receives. Handling can be held
/// open at an explicit continuation so drain and flush ordering are observable
/// without sleeps.
@MainActor
private final class DurableCommitRecorder {
    private let blocksHandling: Bool
    private(set) var commits: [ClipboardHistoryDurableMediaCommit] = []
    private var handlingContinuations: [CheckedContinuation<Void, Never>] = []
    private var arrivalWaiters: [CheckedContinuation<Void, Never>] = []

    init(blocksHandling: Bool = false) {
        self.blocksHandling = blocksHandling
    }

    var generations: [UInt64] {
        commits.map(\.generation)
    }

    func handle(_ commit: ClipboardHistoryDurableMediaCommit) async {
        commits.append(commit)
        let waiters = arrivalWaiters
        arrivalWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
        guard blocksHandling else { return }
        await withCheckedContinuation { continuation in
            handlingContinuations.append(continuation)
        }
    }

    func waitForCommit(at index: Int) async {
        while commits.count <= index {
            await withCheckedContinuation { continuation in
                arrivalWaiters.append(continuation)
            }
        }
    }

    /// Lets every currently suspended handling call finish.
    func finishHandling() {
        let continuations = handlingContinuations
        handlingContinuations.removeAll()
        for continuation in continuations { continuation.resume() }
    }
}

private actor ControlledHistorySaveWorker: ClipboardHistorySaving {
    private(set) var attempts: [RecordedHistoryCommit] = []
    private(set) var commits: [RecordedHistoryCommit] = []
    private(set) var garbageCollectionGenerations: [UInt64] = []

    private var blockedGenerations: Set<UInt64>
    private var failedGenerations: Set<UInt64>
    private var startWaiters: [UInt64: [CheckedContinuation<Void, Never>]] = [:]
    private var releaseWaiters: [UInt64: CheckedContinuation<Void, Never>] = [:]

    init(blockedGenerations: Set<UInt64> = [], failedGenerations: Set<UInt64> = []) {
        self.blockedGenerations = blockedGenerations
        self.failedGenerations = failedGenerations
    }

    func save(_ items: [ClipboardItem], generation: UInt64) async throws {
        let text = items.first?.textValue ?? ""
        let record = RecordedHistoryCommit(generation: generation, text: text)
        attempts.append(record)
        startWaiters.removeValue(forKey: generation)?.forEach { $0.resume() }

        if blockedGenerations.contains(generation) {
            await withCheckedContinuation { continuation in
                releaseWaiters[generation] = continuation
            }
        }

        if failedGenerations.remove(generation) != nil {
            throw ControlledWorkerFailure.injectedSaveFailure
        }
        commits.append(record)
    }

    func collectGarbage() async {
        garbageCollectionGenerations.append(commits.last?.generation ?? 0)
    }

    func waitUntilStarted(_ generation: UInt64) async {
        if attempts.contains(where: { $0.generation == generation }) { return }
        await withCheckedContinuation { continuation in
            startWaiters[generation, default: []].append(continuation)
        }
    }

    func release(_ generation: UInt64) {
        blockedGenerations.remove(generation)
        releaseWaiters.removeValue(forKey: generation)?.resume()
    }
}

@MainActor
@Suite(.serialized)
struct ClipboardHistorySaveCoordinatorTests {
    @Test func workerRejectsAStaleGenerationAfterANewerCommit() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipboardHistorySaveCoordinatorTests-\(UUID().uuidString)", isDirectory: true)
        let defaultsName = "ClipboardHistorySaveCoordinatorTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsName)!
        defer {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: defaultsName)
        }

        let persistence = ClipboardHistoryPersistence(directoryURL: directory, userDefaults: defaults)
        let worker = ClipboardHistorySaveWorker(persistence: persistence)
        let newer = historyItem("generation-4")
        try await worker.save([newer], generation: 4)

        var rejected = false
        do {
            try await worker.save([historyItem("generation-3")], generation: 3)
        } catch {
            rejected = true
        }

        #expect(rejected)
        #expect(await worker.lastCommittedGeneration == 4)
        #expect(try persistence.loadItems() == [newer])
    }

    @Test func coalescesPendingGenerationsAndFlushWaitsForLatestCommit() async {
        let worker = ControlledHistorySaveWorker(blockedGenerations: [1, 4])
        let coordinator = ClipboardHistorySaveCoordinator(worker: worker)
        coordinator.requestSave([historyItem("generation-1")])
        await worker.waitUntilStarted(1)

        coordinator.requestSave([historyItem("generation-2")])
        coordinator.requestSave([historyItem("generation-3")])
        coordinator.requestSave([historyItem("generation-4")])
        var flushResolved = false
        let flushTask = Task { @MainActor in
            let result = await coordinator.flush()
            flushResolved = result
            return result
        }

        await worker.release(1)
        await worker.waitUntilStarted(4)
        try? await Task.sleep(nanoseconds: 20_000_000)
        #expect(!flushResolved)

        await worker.release(4)
        #expect(await flushTask.value)
        #expect(await worker.attempts == [
            RecordedHistoryCommit(generation: 1, text: "generation-1"),
            RecordedHistoryCommit(generation: 4, text: "generation-4")
        ])
        #expect(await worker.commits == [
            RecordedHistoryCommit(generation: 1, text: "generation-1"),
            RecordedHistoryCommit(generation: 4, text: "generation-4")
        ])
        #expect(await worker.garbageCollectionGenerations == [4])

        let committedGenerations = await worker.commits.map(\.generation)
        let collectedGenerations = await worker.garbageCollectionGenerations
        AcceptanceMetrics.record(
            scenario: "history-save-coordinator",
            metric: "committedGenerationsForRapidRequests",
            expected: "[1, 4]",
            observed: "\(committedGenerations)"
        )
        AcceptanceMetrics.record(
            scenario: "history-save-coordinator",
            metric: "garbageCollectionAfterLatestCommit",
            expected: "[4]",
            observed: "\(collectedGenerations)"
        )
    }

    @Test func latestFailedGenerationCanBeRetriedAndFlushReportsFailure() async {
        let worker = ControlledHistorySaveWorker(blockedGenerations: [1], failedGenerations: [1])
        let coordinator = ClipboardHistorySaveCoordinator(worker: worker)
        coordinator.requestSave([historyItem("latest-state")])
        await worker.waitUntilStarted(1)

        let flushTask = Task { @MainActor in await coordinator.flush() }
        await worker.release(1)
        #expect(!(await flushTask.value))

        #expect(await coordinator.retryLatest())
        #expect(await worker.attempts == [
            RecordedHistoryCommit(generation: 1, text: "latest-state"),
            RecordedHistoryCommit(generation: 2, text: "latest-state")
        ])
        #expect(await worker.commits == [RecordedHistoryCommit(generation: 2, text: "latest-state")])
        #expect(await coordinator.flush())
    }

    // MARK: - Durable media receipts (1.1)

    @Test func receiptCarriesOnlyResidentHeavyMediaRolesWithoutNewHashes() async throws {
        let counters = MediaOperationCounters()
        let worker = ControlledHistorySaveWorker()
        let coordinator = ClipboardHistorySaveCoordinator(worker: worker)
        let recorder = DurableCommitRecorder()
        coordinator.setDurableMediaHandler { commit in await recorder.handle(commit) }

        let imageID = UUID(uuidString: "00000000-0000-0000-0000-0000000000b1")!
        let previewID = UUID(uuidString: "00000000-0000-0000-0000-0000000000b2")!
        let referenceID = UUID(uuidString: "00000000-0000-0000-0000-0000000000b3")!
        let iconOnlyID = UUID(uuidString: "00000000-0000-0000-0000-0000000000b4")!
        // Fixture identities are established before the measurement window.
        let image = PreparedMedia(hashing: Data(repeating: 0x21, count: 192))
        let linkImage = PreparedMedia(hashing: Data(repeating: 0x22, count: 96))
        let restoredReference = PreparedMedia(hashing: Data(repeating: 0x23, count: 64)).id
        let icon = Data(repeating: 0x24, count: 48)

        let items = [
            mediaItem(id: imageID, icon: icon, imageData: image.data, imageBlobID: image.id),
            mediaItem(id: previewID, icon: icon, linkImageData: linkImage.data, linkImageBlobID: linkImage.id),
            mediaItem(id: referenceID, icon: icon, imageBlobID: restoredReference),
            mediaItem(id: iconOnlyID, icon: icon)
        ]

        let flushed = await counters.measure {
            coordinator.requestSave(items)
            let flushTask = Task { @MainActor in await coordinator.flush() }
            await recorder.waitForCommit(at: 0)
            return await flushTask.value
        }

        #expect(flushed)
        #expect(await worker.commits.map(\.generation) == [1])
        #expect(counters.mediaHashCount == 0, "creating a receipt must not hash media")

        let commit = try #require(recorder.commits.first)
        #expect(commit.generation == 1)
        let entries = commit.entries
        #expect(entries.map(\.itemID) == [imageID, previewID])
        #expect(entries.first?.image?.id == image.id)
        #expect(entries.first?.image?.data == image.data)
        #expect(entries.first?.linkImage == nil)
        #expect(entries.last?.linkImage?.id == linkImage.id)
        #expect(entries.last?.linkImage?.data == linkImage.data)
        #expect(entries.last?.image == nil, "an absent role must not be synthesized")
        AcceptanceMetrics.record(
            scenario: "durable-media-commit",
            metric: "receiptEntries",
            expected: "2",
            observed: "\(entries.count)"
        )
        AcceptanceMetrics.record(
            scenario: "durable-media-commit",
            metric: "mediaHashDuringReceipt",
            expected: "0",
            observed: "\(counters.mediaHashCount)"
        )
    }

    // MARK: - Retry snapshot ownership (1.2)

    @Test func latestSuccessClearsRetrySnapshotWithOrWithoutAHandler() async {
        for installsHandler in [false, true] {
            let worker = ControlledHistorySaveWorker()
            let coordinator = ClipboardHistorySaveCoordinator(worker: worker)
            let recorder = DurableCommitRecorder()
            if installsHandler {
                coordinator.setDurableMediaHandler { commit in await recorder.handle(commit) }
            }

            coordinator.requestSave([historyItem("latest")])
            #expect(await coordinator.flush())
            #expect(!coordinator.hasRetainedRetrySnapshot)
            #expect(recorder.generations == (installsHandler ? [1] : []))
        }
    }

    @Test func failedLatestGenerationRetainsSnapshotAndRetrySuccessClearsIt() async {
        let worker = ControlledHistorySaveWorker(blockedGenerations: [1], failedGenerations: [1])
        let coordinator = ClipboardHistorySaveCoordinator(worker: worker)
        coordinator.requestSave([historyItem("latest-state")])
        await worker.waitUntilStarted(1)
        #expect(coordinator.hasRetainedRetrySnapshot)

        let flushTask = Task { @MainActor in await coordinator.flush() }
        await worker.release(1)
        #expect(!(await flushTask.value))
        #expect(coordinator.hasRetainedRetrySnapshot, "a failed transaction still needs its retry snapshot")

        #expect(await coordinator.retryLatest())
        #expect(!coordinator.hasRetainedRetrySnapshot)
    }

    @Test func olderSuccessDoesNotClearNewerRetrySnapshot() async {
        let worker = ControlledHistorySaveWorker(blockedGenerations: [1, 2])
        let coordinator = ClipboardHistorySaveCoordinator(worker: worker)
        coordinator.requestSave([historyItem("generation-1")])
        await worker.waitUntilStarted(1)
        coordinator.requestSave([historyItem("generation-2")])

        await worker.release(1)
        await worker.waitUntilStarted(2)
        #expect(coordinator.hasRetainedRetrySnapshot, "an older success must keep the latest pending snapshot")

        await worker.release(2)
        #expect(await coordinator.flush())
        #expect(!coordinator.hasRetainedRetrySnapshot)
        #expect(await worker.commits.map(\.generation) == [1, 2])
    }

    // MARK: - Drain ordering across handling (1.3)

    @Test func flushWaitsForHandlingAndDrainsRequestsArrivingDuringIt() async {
        let worker = ControlledHistorySaveWorker()
        let coordinator = ClipboardHistorySaveCoordinator(worker: worker)
        let recorder = DurableCommitRecorder(blocksHandling: true)
        coordinator.setDurableMediaHandler { commit in await recorder.handle(commit) }

        var flushResolved = false
        coordinator.requestSave([historyItem("generation-1")])
        let flushTask = Task { @MainActor in
            let result = await coordinator.flush()
            flushResolved = result
            return result
        }

        await recorder.waitForCommit(at: 0)
        #expect(!flushResolved, "flush must not return while committed media is still being handled")

        coordinator.requestSave([historyItem("generation-2")])
        recorder.finishHandling()
        await recorder.waitForCommit(at: 1)
        #expect(!flushResolved)

        recorder.finishHandling()
        #expect(await flushTask.value)
        #expect(recorder.generations == [1, 2])
        #expect(await worker.attempts.map(\.generation) == [1, 2])
        #expect(await worker.garbageCollectionGenerations == [2], "GC must be reconsidered after handling")
        AcceptanceMetrics.record(
            scenario: "durable-media-commit",
            metric: "receiptGenerationsDuringHandling",
            expected: "[1, 2]",
            observed: "\(recorder.generations)"
        )
    }

    @Test func coalescedGenerationsNeverEmitReceipts() async {
        let worker = ControlledHistorySaveWorker(blockedGenerations: [1, 3])
        let coordinator = ClipboardHistorySaveCoordinator(worker: worker)
        let recorder = DurableCommitRecorder()
        coordinator.setDurableMediaHandler { commit in await recorder.handle(commit) }

        coordinator.requestSave([historyItem("generation-1")])
        await worker.waitUntilStarted(1)
        coordinator.requestSave([historyItem("generation-2")])
        coordinator.requestSave([historyItem("generation-3")])

        await worker.release(1)
        await worker.waitUntilStarted(3)
        await worker.release(3)
        #expect(await coordinator.flush())

        #expect(recorder.generations == [1, 3])
        #expect(await worker.attempts.map(\.generation) == [1, 3])
        #expect(await worker.garbageCollectionGenerations == [3])
    }

    @Test func failureKeepsRetrySemanticsWhileReportingNoReceipt() async {
        let worker = ControlledHistorySaveWorker(failedGenerations: [1])
        let coordinator = ClipboardHistorySaveCoordinator(worker: worker)
        let recorder = DurableCommitRecorder()
        coordinator.setDurableMediaHandler { commit in await recorder.handle(commit) }

        coordinator.requestSave([historyItem("latest-state")])
        #expect(!(await coordinator.flush()))
        #expect(recorder.commits.isEmpty, "only successful transactions authorize release")

        #expect(await coordinator.retryLatest())
        #expect(recorder.generations == [2])
        #expect(!coordinator.hasRetainedRetrySnapshot)
    }

    private func mediaItem(
        id: UUID,
        icon: Data? = nil,
        imageData: Data? = nil,
        imageBlobID: String? = nil,
        linkImageData: Data? = nil,
        linkImageBlobID: String? = nil
    ) -> ClipboardItem {
        ClipboardItem(
            id: id,
            kind: .image,
            title: "image",
            preview: "image",
            sourceApp: "Tests",
            sourceAppIconData: icon,
            createdAt: Date(timeIntervalSince1970: 1_700_000_062),
            isPinned: false,
            pinboardName: nil,
            textValue: nil,
            fileURLs: [],
            imageData: imageData,
            imageBlobID: imageBlobID,
            linkImageData: linkImageData,
            linkImageBlobID: linkImageBlobID
        )
    }

    private func historyItem(_ value: String) -> ClipboardItem {
        ClipboardItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000061")!,
            kind: .text,
            title: value,
            preview: value,
            sourceApp: "Tests",
            sourceAppIconData: nil,
            createdAt: Date(timeIntervalSince1970: 1_700_000_061),
            isPinned: false,
            pinboardName: nil,
            textValue: value,
            fileURLs: [],
            imageData: nil
        )
    }
}
