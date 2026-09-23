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
