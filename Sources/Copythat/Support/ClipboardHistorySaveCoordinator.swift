import Foundation

protocol ClipboardHistorySaving: Sendable {
    func save(_ items: [ClipboardItem], generation: UInt64) async throws
    func collectGarbage() async
}

@MainActor
final class ClipboardHistorySaveCoordinator {
    private struct Request {
        let generation: UInt64
        let items: [ClipboardItem]
    }

    private let worker: any ClipboardHistorySaving
    private var nextGeneration: UInt64 = 0
    private var committedGeneration: UInt64 = 0
    private var latestItems: [ClipboardItem]?
    private var pendingRequest: Request?
    private var failedGeneration: UInt64?
    private var drainTask: Task<Void, Never>?

    init(worker: any ClipboardHistorySaving = ClipboardHistorySaveWorker()) {
        self.worker = worker
    }

    var hasUnsavedChanges: Bool {
        nextGeneration > committedGeneration
    }

    func requestSave(_ items: [ClipboardItem]) {
        nextGeneration += 1
        latestItems = items
        pendingRequest = Request(generation: nextGeneration, items: items)
        startDrainIfNeeded()
    }

    func flush() async -> Bool {
        while true {
            if !hasUnsavedChanges, pendingRequest == nil, drainTask == nil {
                return true
            }
            if pendingRequest == nil, drainTask == nil, failedGeneration == nextGeneration {
                return false
            }
            startDrainIfNeeded()
            guard let task = drainTask else { return !hasUnsavedChanges }
            await task.value
        }
    }

    func retryLatest() async -> Bool {
        if failedGeneration == nextGeneration,
           drainTask == nil,
           let latestItems {
            nextGeneration += 1
            failedGeneration = nil
            pendingRequest = Request(generation: nextGeneration, items: latestItems)
            startDrainIfNeeded()
        }
        return await flush()
    }

    private func startDrainIfNeeded() {
        guard drainTask == nil, pendingRequest != nil else { return }
        drainTask = Task { @MainActor [weak self] in
            await self?.drain()
        }
    }

    private func drain() async {
        while let request = pendingRequest {
            pendingRequest = nil
            do {
                try await worker.save(request.items, generation: request.generation)
                committedGeneration = max(committedGeneration, request.generation)
                failedGeneration = nil
                if pendingRequest == nil {
                    await worker.collectGarbage()
                }
            } catch {
                failedGeneration = request.generation
                if pendingRequest == nil { break }
            }
        }
        drainTask = nil
        startDrainIfNeeded()
    }
}
