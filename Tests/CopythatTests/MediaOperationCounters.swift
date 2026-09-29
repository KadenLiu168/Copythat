@testable import Copythat
import Foundation

enum MediaOperationCountersError: Error {
    case injectedWriteFailure
}

/// One measurement window over media work: the observation seam for actual
/// SHA256 operations plus injected persistence I/O, so a scenario can assert
/// hash counts and payload access together.
///
/// A window starts with `reset()` and runs the measured work through `measure`,
/// which installs the recorder for the current task and the tasks it awaits.
/// Fixture preparation, real media access inside a scenario, and assertion-side
/// digests stay outside the window by construction.
final class MediaOperationCounters: @unchecked Sendable {
    private let lock = NSLock()
    private var recorder = MediaHashRecorder()
    private var blobReads = 0
    private var blobWrites = 0
    private var manifestReads = 0
    private var manifestWrites = 0

    var identityHashCount: Int { locked { recorder.count(of: .identity) } }
    var integrityHashCount: Int { locked { recorder.count(of: .integrity) } }
    var mediaHashCount: Int { locked { recorder.totalCount } }
    var mainThreadIdentityHashCount: Int { locked { recorder.mainThreadIdentityCount } }
    var blobReadCount: Int { locked { blobReads } }
    var blobWriteCount: Int { locked { blobWrites } }
    var manifestReadCount: Int { locked { manifestReads } }
    var manifestWriteCount: Int { locked { manifestWrites } }

    /// Starts a new window: a fresh hash recorder and zeroed I/O counts.
    func reset() {
        lock.lock()
        recorder = MediaHashRecorder()
        blobReads = 0
        blobWrites = 0
        manifestReads = 0
        manifestWrites = 0
        lock.unlock()
    }

    /// Runs work with the media hash observation installed. Detached tasks
    /// started inside still need explicit propagation by their producer.
    func measure<T>(_ body: () async throws -> T) async rethrows -> T {
        let recorder = locked { self.recorder }
        return try await MediaHashObservation.$recorder.withValue(recorder) {
            try await body()
        }
    }

    /// Persistence whose payload access is counted separately from manifest
    /// reads and commits, while behaving exactly like the production store. A
    /// write the caller rejects fails before reaching disk and is not counted.
    func makePersistence(
        directoryURL: URL,
        userDefaults: UserDefaults,
        failWrite: @escaping (URL) -> Bool = { _ in false }
    ) -> ClipboardHistoryPersistence {
        ClipboardHistoryPersistence(
            directoryURL: directoryURL,
            userDefaults: userDefaults,
            readData: { [self] url in
                record(read: url)
                return try Data(contentsOf: url)
            },
            writeData: { [self] data, url in
                if failWrite(url) {
                    throw MediaOperationCountersError.injectedWriteFailure
                }
                try data.write(to: url, options: [.atomic])
                record(write: url)
            }
        )
    }

    /// Counters are exposed so a test that injects its own persistence
    /// closures can still account for payload access.
    func record(read url: URL) {
        lock.lock()
        if url.pathExtension == "blob" {
            blobReads += 1
        } else {
            manifestReads += 1
        }
        lock.unlock()
    }

    func record(write url: URL) {
        lock.lock()
        if url.pathExtension == "blob" {
            blobWrites += 1
        } else {
            manifestWrites += 1
        }
        lock.unlock()
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
