import Foundation

/// The one capability startup restoration needs: read persisted history.
///
/// Deliberately narrower than persistence. It carries no save, garbage
/// collection or blob authority, so a Store cannot reach a write path through
/// the loader it was handed.
protocol ClipboardHistoryLoading: Sendable {
    func loadItems() async throws -> [ClipboardItem]
}

/// Runs the synchronous, throwing instance persistence load on the actor's own
/// executor.
///
/// The instance load is deliberately *not* delegated to the static wrapper:
/// that wrapper converts every error into an empty baseline, which would erase
/// the corrupt-input backup the instance path performs before rethrowing. The
/// actor body calls it directly, so manifest read, JSON decoding, V2 blob
/// reference validation, deduplicated source-icon integrity verification and
/// item/search-corpus construction all happen off MainActor, and a failure
/// reaches the caller with its backup already written.
actor ClipboardHistoryRestoreWorker: ClipboardHistoryLoading {
    private let persistence: ClipboardHistoryPersistence

    init(persistence: ClipboardHistoryPersistence = .shared) {
        self.persistence = persistence
    }

    func loadItems() async throws -> [ClipboardItem] {
        try persistence.loadItems()
    }
}
