@testable import Copythat
import Foundation

// MARK: - Loader script primitives

/// Metadata loader outcome scripts.
indirect enum LinkPreviewMetadataScript {
    case titleOnly(String)
    case empty
    case image(Data)
    case failure
    /// Waits for the gate; on cancel throws CancellationError, on release runs `then`.
    case gated(LinkPreviewGate, then: LinkPreviewMetadataScript)
    /// Ignores task cancellation; waits for release and then returns `then`,
    /// exercising deliberately late completions.
    case lateAfterCancel(LinkPreviewGate, then: LinkPreviewMetadataScript)

    func evaluate(counter: LinkPreviewCounter, key: String) async throws -> LinkPreviewMetadata {
        switch self {
        case .titleOnly(let title):
            return LinkPreviewMetadata(title: title, imageData: nil)
        case .empty:
            return LinkPreviewMetadata(title: nil, imageData: nil)
        case .image(let data):
            return LinkPreviewMetadata(title: nil, imageData: data)
        case .failure:
            throw URLError(.badServerResponse)
        case .gated(let gate, let then):
            await gate.waitOrCancelled()
            if Task.isCancelled {
                counter.mark("cancelled:\(key)")
                throw CancellationError()
            }
            return try await then.evaluate(counter: counter, key: key)
        case .lateAfterCancel(let gate, let then):
            await gate.waitUntilReleased()
            return try await then.evaluate(counter: counter, key: key)
        }
    }
}

extension LinkPreviewMetadataScript {
    /// Wraps the script into a counted metadata loader.
    func loader(counter: LinkPreviewCounter, key: String) -> ClipboardStore.LinkMetadataLoader {
        let script = self
        return { _ in
            counter.begin("metadata:\(key)")
            defer { counter.end("metadata:\(key)") }
            return try await script.evaluate(counter: counter, key: key)
        }
    }
}

/// Snapshot loader outcome scripts.
indirect enum LinkPreviewSnapshotScript {
    case image(Data)
    case failure
    case gated(LinkPreviewGate, then: LinkPreviewSnapshotScript)
    case lateAfterCancel(LinkPreviewGate, then: LinkPreviewSnapshotScript)
    /// Observes cancellation, then blocks cleanup until the second gate opens,
    /// modeling slow resource release after cancellation.
    case cleanupAfterCancel(LinkPreviewGate, LinkPreviewGate, then: LinkPreviewSnapshotScript)

    func evaluate(counter: LinkPreviewCounter, key: String) async throws -> Data {
        switch self {
        case .image(let data):
            return data
        case .failure:
            throw URLError(.badServerResponse)
        case .gated(let gate, let then):
            await gate.waitOrCancelled()
            if Task.isCancelled {
                counter.mark("cancelled:\(key)")
                throw CancellationError()
            }
            return try await then.evaluate(counter: counter, key: key)
        case .lateAfterCancel(let gate, let then):
            await gate.waitUntilReleased()
            return try await then.evaluate(counter: counter, key: key)
        case .cleanupAfterCancel(let cancelGate, let cleanupGate, let then):
            await cancelGate.waitOrCancelled()
            if Task.isCancelled {
                await cleanupGate.waitUntilReleased()
                counter.mark("cleanupDone:\(key)")
                throw CancellationError()
            }
            return try await then.evaluate(counter: counter, key: key)
        }
    }
}

extension LinkPreviewSnapshotScript {
    /// Wraps the script into a counted snapshot loader.
    func loader(counter: LinkPreviewCounter, key: String) -> ClipboardStore.LinkSnapshotLoader {
        let script = self
        return { _ in
            counter.begin("snapshot:\(key)")
            defer { counter.end("snapshot:\(key)") }
            return try await script.evaluate(counter: counter, key: key)
        }
    }
}
