import Foundation

/// A finalized media payload bound to its SHA256 content address. Creating one
/// from final bytes performs that payload's single identity hash; forwarding an
/// already known address performs none.
struct PreparedMedia: Sendable, Equatable {
    let data: Data
    let id: String

    init(hashing data: Data) {
        MediaHashObservation.record(.identity)
        self.init(data: data, id: ClipboardHistoryBlobStore.sha256Hex(data))
    }

    /// Trusted forwarding: the caller already knows the address of these bytes,
    /// so no digest is taken again.
    init(data: Data, id: String) {
        self.data = data
        self.id = id
    }
}

/// Why a media SHA256 operation runs. Identity creation happens once per
/// finalized payload; integrity verification runs whenever stored bytes are
/// released, and never proves that those bytes were written or repaired.
enum MediaHashCategory: Sendable {
    case identity
    case integrity
}

/// Test-installed sink for actual media SHA256 operations. A recorder belongs to
/// one test: counting is lock-guarded so concurrent work inside that test is
/// accounted for, and tests without a recorder observe nothing.
final class MediaHashRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var counts: [MediaHashCategory: Int] = [:]
    private var identityOnMainThread = 0

    func record(_ category: MediaHashCategory) {
        lock.lock()
        counts[category, default: 0] += 1
        if category == .identity, Thread.isMainThread {
            identityOnMainThread += 1
        }
        lock.unlock()
    }

    func count(of category: MediaHashCategory) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return counts[category] ?? 0
    }

    /// Identity work that ran on the main thread. Prepared media is expected to
    /// be finalized off it, so a non-zero reading means preparation moved back
    /// onto MainActor.
    var mainThreadIdentityCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return identityOnMainThread
    }

    var totalCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return counts.values.reduce(0, +)
    }
}

/// Observation seam for the two media digest operations: identity creation and
/// integrity verification. The recorder is task-local, so parallel tests never
/// share counters and production runs without one.
enum MediaHashObservation {
    @TaskLocal static var recorder: MediaHashRecorder?

    static func record(_ category: MediaHashCategory) {
        recorder?.record(category)
    }

    /// Detached work does not inherit task-local values, so preparation that runs
    /// detached must carry the recorder across explicitly.
    static func propagating<T>(_ recorder: MediaHashRecorder?, _ body: () async -> T) async -> T {
        await $recorder.withValue(recorder) { await body() }
    }
}
