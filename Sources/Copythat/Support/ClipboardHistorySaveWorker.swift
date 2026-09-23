import Foundation

actor ClipboardHistorySaveWorker: ClipboardHistorySaving {
    private let persistence: ClipboardHistoryPersistence
    private var lastAcceptedGeneration: UInt64 = 0
    private(set) var lastCommittedGeneration: UInt64 = 0

    init(persistence: ClipboardHistoryPersistence = .shared) {
        self.persistence = persistence
    }

    func save(_ items: [ClipboardItem], generation: UInt64) async throws {
        guard generation > lastAcceptedGeneration else {
            throw ClipboardHistorySaveWorkerError.staleGeneration(generation)
        }
        lastAcceptedGeneration = generation
        try persistence.save(items, garbageCollect: false)
        lastCommittedGeneration = generation
    }

    func collectGarbage() async {
        persistence.collectGarbage()
    }
}

enum ClipboardHistorySaveWorkerError: Error {
    case staleGeneration(UInt64)
}
