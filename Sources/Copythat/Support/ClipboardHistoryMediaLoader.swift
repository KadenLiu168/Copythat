import Foundation

/// Reads and verifies persisted heavy media outside MainActor, reusing
/// successful loads through a byte-cost LRU cache bounded by `byteBudget`.
/// Loading never mutates history: callers receive bytes and decide what to do
/// with them.
actor ClipboardHistoryMediaLoader {
    static let defaultByteBudget = 32 * 1024 * 1024

    /// The loader production consumers share, reading the same persisted blob
    /// store history saves to so card display, paste and drag cannot diverge.
    static let shared = ClipboardHistoryMediaLoader(
        blobStore: ClipboardHistoryPersistence.shared.blobStore
    )

    private let blobStore: ClipboardHistoryBlobStore
    private let byteBudget: Int
    private var cache: [String: Data] = [:]
    private var recency: [String] = []
    private var cachedByteCost = 0

    init(blobStore: ClipboardHistoryBlobStore, byteBudget: Int = ClipboardHistoryMediaLoader.defaultByteBudget) {
        self.blobStore = blobStore
        self.byteBudget = byteBudget
    }

    /// Returns verified bytes for a blob ID. A hit refreshes recency; a miss
    /// reads disk once and caches the result unless it alone exceeds the
    /// budget. Failures are never cached.
    func load(blobID: String) async throws -> Data {
        // A request cancelled while queued for the actor must not start a read.
        try Task.checkCancellation()
        if let cached = cache[blobID] {
            touch(blobID)
            return cached
        }
        let data = try blobStore.read(blobID: blobID)
        if data.count <= byteBudget {
            insert(blobID, data)
        }
        return data
    }

    private func touch(_ blobID: String) {
        recency.removeAll { $0 == blobID }
        recency.append(blobID)
    }

    private func insert(_ blobID: String, _ data: Data) {
        if let existing = cache.removeValue(forKey: blobID) {
            cachedByteCost -= existing.count
            recency.removeAll { $0 == blobID }
        }
        cache[blobID] = data
        recency.append(blobID)
        cachedByteCost += data.count

        while cachedByteCost > byteBudget, let oldest = recency.first {
            recency.removeFirst()
            if let evicted = cache.removeValue(forKey: oldest) {
                cachedByteCost -= evicted.count
            }
        }
    }
}
