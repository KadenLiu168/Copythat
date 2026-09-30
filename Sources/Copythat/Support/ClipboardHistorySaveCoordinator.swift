import Foundation

protocol ClipboardHistorySaving: Sendable {
    func save(_ items: [ClipboardItem], generation: UInt64) async throws
    func collectGarbage() async
}

/// Resident heavy media from one snapshot that successfully completed the
/// blob-first, atomic-manifest save transaction.
///
/// A receipt is scoped to the request that committed it and reports only the
/// roles that carried resident bytes in that request. Metadata, reference-only
/// media, and source icons never appear; identities are forwarded from the
/// existing runtime addresses, so building a receipt hashes nothing.
struct ClipboardHistoryDurableMediaCommit: Sendable {
    struct Entry: Sendable {
        let itemID: UUID
        let image: PreparedMedia?
        let linkImage: PreparedMedia?

        /// Resident roles in a stable role order, for one seeding batch.
        var preparedMedia: [PreparedMedia] {
            [image, linkImage].compactMap(\.self)
        }
    }

    let generation: UInt64
    let entries: [Entry]
}

/// Awaited, nonthrowing handling for one successful commit. Handling runs on
/// the main actor in generation order and keeps the coordinator's drain active,
/// so `flush()` cannot return before seeding and the release-or-defer decision.
typealias ClipboardHistoryDurableMediaHandler = @MainActor (ClipboardHistoryDurableMediaCommit) async -> Void

@MainActor
final class ClipboardHistorySaveCoordinator {
    private struct Request {
        let generation: UInt64
        let items: [ClipboardItem]
    }

    private let worker: any ClipboardHistorySaving
    private var durableMediaHandler: ClipboardHistoryDurableMediaHandler?
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

    /// Whether the snapshot of the latest requested generation is still held
    /// for retry. Only that generation's own success clears it.
    var hasRetainedRetrySnapshot: Bool {
        latestItems != nil
    }

    /// Installs the single durable-media handler. Requests made before a
    /// handler exists still clear their retry snapshot; only release handling
    /// is skipped.
    func setDurableMediaHandler(_ handler: @escaping ClipboardHistoryDurableMediaHandler) {
        durableMediaHandler = handler
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
                // An older success must not discard the retry snapshot a newer
                // request installed while this generation was saving.
                if request.generation == nextGeneration {
                    latestItems = nil
                }
                if let durableMediaHandler {
                    await durableMediaHandler(durableMediaCommit(for: request))
                }
                // Reconsidered after handling: a request that arrived while the
                // handler ran keeps the drain alive and defers GC to its commit.
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

    /// The committed request's own resident heavy media, in its committed order.
    private func durableMediaCommit(for request: Request) -> ClipboardHistoryDurableMediaCommit {
        ClipboardHistoryDurableMediaCommit(
            generation: request.generation,
            entries: request.items.compactMap { item -> ClipboardHistoryDurableMediaCommit.Entry? in
                let image = item.imageData.flatMap { data in
                    item.imageBlobID.map { PreparedMedia(data: data, id: $0) }
                }
                let linkImage = item.linkImageData.flatMap { data in
                    item.linkImageBlobID.map { PreparedMedia(data: data, id: $0) }
                }
                guard image != nil || linkImage != nil else { return nil }
                return ClipboardHistoryDurableMediaCommit.Entry(
                    itemID: item.id,
                    image: image,
                    linkImage: linkImage
                )
            }
        )
    }
}
