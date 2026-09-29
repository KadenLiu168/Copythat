// Link preview seam
import AppKit
import Foundation
@preconcurrency import LinkPresentation
import UniformTypeIdentifiers

struct LinkPreviewMetadata: Sendable {
    let title: String?
    /// Final bounded preview payload with its content address, so applying or
    /// storing it never re-encodes or re-hashes it.
    let image: PreparedMedia?
}

enum LinkPreviewFetchError: Error {
    case metadataUnavailable
    case snapshotUnavailable
}

/// Thread-safe bridge between one Apple callback API and a Swift continuation.
///
/// Guarantees:
/// - The terminal/cancelled state is observable by `register`, so callers never
///   start a request into an already-cancelled bridge.
/// - `cancel` ends the local waiter exactly once without waiting for Apple's
///   callback, and cancels adopted Progress handles outside the state lock.
/// - Callbacks arriving after a terminal state are ignored; resumes stay outside
///   the state lock so no cancel/callback path re-enters it.
final class LinkPreviewCallbackBridge<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var isTerminal = false
    private var continuation: CheckedContinuation<Value, Error>?
    private var cancellableLoads: [Progress] = []

    /// Registers the continuation. Returns false when the bridge is already
    /// terminal (cancelled); the caller must not start the request then.
    func register(_ continuation: CheckedContinuation<Value, Error>) -> Bool {
        lock.lock()
        let startAllowed = !isTerminal
        if startAllowed {
            self.continuation = continuation
        }
        lock.unlock()

        if !startAllowed {
            continuation.resume(throwing: CancellationError())
        }
        return startAllowed
    }

    /// Delivers a callback result. Ignored when the request was already terminal.
    func finish(_ result: Result<Value, Error>) {
        lock.lock()
        guard !isTerminal else {
            lock.unlock()
            return
        }
        isTerminal = true
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()

        continuation?.resume(with: result)
    }

    /// Cancels the request: ends the local waiter exactly once with
    /// `CancellationError`, then cancels adopted load Progress handles outside
    /// the state lock.
    func cancel() {
        lock.lock()
        guard !isTerminal else {
            lock.unlock()
            return
        }
        isTerminal = true
        let continuation = self.continuation
        self.continuation = nil
        let adopted = cancellableLoads
        cancellableLoads = []
        lock.unlock()

        continuation?.resume(throwing: CancellationError())
        for progress in adopted {
            progress.cancel()
        }
    }

    /// Hands a load Progress handle over after the load call returned. A bridge
    /// that became terminal before adoption cancels the handle immediately,
    /// covering the race where cancellation happened before the Progress was
    /// available.
    func adopt(progress: Progress?) {
        guard let progress else { return }
        lock.lock()
        let cancelImmediately = isTerminal
        if !cancelImmediately {
            cancellableLoads.append(progress)
        }
        lock.unlock()

        if cancelImmediately {
            progress.cancel()
        }
    }
}

enum LinkPreviewFetcher {
    /// Completes LPMetadataProvider enrichment plus image/icon extraction for a
    /// URL. Throws `CancellationError` when the wrapping task is cancelled and
    /// other errors when metadata cannot be fetched. Success may carry neither
    /// title nor image (the no-image success state). This stage never creates a
    /// browser web view: the browser snapshot is the separate
    /// `fetchWebSnapshot` stage that only the Store schedules.
    static func fetchMetadata(url: URL) async throws -> LinkPreviewMetadata {
        let metadata = try await fetchLPMetadata(url: url)
        try Task.checkCancellation()
        return try await extractPreview(from: metadata)
    }

    /// Runs Copythat's browser snapshot stage for a URL and returns its final
    /// bounded PNG with its content address. Throws `CancellationError` when
    /// cancelled and other errors when no usable snapshot could be produced. The
    /// WebKit lifecycle itself lives in the focused snapshot controller file;
    /// this is only the store-facing seam.
    static func fetchWebSnapshot(url: URL) async throws -> PreparedMedia {
        let media = await LinkPreviewSnapshotController.snapshotData(url: url)
        if let media {
            return media
        }
        if Task.isCancelled {
            throw CancellationError()
        }
        throw LinkPreviewFetchError.snapshotUnavailable
    }

    /// Extraction from an already fetched `LPLinkMetadata`: image is preferred
    /// over icon, and images are re-encoded bounded to 640px.
    static func extractPreview(from metadata: LPLinkMetadata) async throws -> LinkPreviewMetadata {
        try Task.checkCancellation()
        let title = metadata.title?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
        var image = try await providerImageData(metadata.imageProvider)
        try Task.checkCancellation()
        if image == nil {
            image = try await providerImageData(metadata.iconProvider)
        }
        try Task.checkCancellation()
        return LinkPreviewMetadata(title: title, image: image)
    }

    // MARK: - LPMetadataProvider bridge

    @MainActor
    private static func fetchLPMetadata(url: URL) async throws -> LPLinkMetadata {
        try Task.checkCancellation()
        let provider = LPMetadataProvider()
        provider.timeout = 8
        let bridge = LinkPreviewCallbackBridge<LPLinkMetadata>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let startAllowed = bridge.register(continuation)
                guard startAllowed else { return }
                // Start and cancel share the main actor. The cancellation task
                // retains the provider through cancel without a callback cycle
                // when Apple never delivers a terminal callback.
                provider.startFetchingMetadata(for: url) { metadata, error in
                    if let metadata {
                        bridge.finish(.success(metadata))
                    } else {
                        bridge.finish(.failure(error ?? LinkPreviewFetchError.metadataUnavailable))
                    }
                }
            }
        } onCancel: {
            bridge.cancel()
            // LPMetadataProvider's internal teardown races with its own fetch
            // queues when cancelled from a background thread; serializing the
            // cancel on the main queue keeps the Apple-side state machine sane.
            // The local waiter already ended above, so this only stops the
            // underlying fetch.
            Task { @MainActor in
                provider.cancel()
            }
        }
    }

    // MARK: - NSItemProvider bridges

    private static func providerImageData(_ provider: NSItemProvider?) async throws -> PreparedMedia? {
        guard let provider else { return nil }

        if provider.canLoadObject(ofClass: NSImage.self) {
            let image = try await loadProviderObject(provider)
            try Task.checkCancellation()
            return image?.pngData(maxPixel: 640).map { PreparedMedia(hashing: $0) }
        }

        guard provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) else {
            return nil
        }

        let data = try await loadProviderData(provider)
        try Task.checkCancellation()
        guard let data, let image = NSImage(data: data) else { return nil }
        return image.pngData(maxPixel: 640).map { PreparedMedia(hashing: $0) }
    }

    private static func loadProviderObject(_ provider: NSItemProvider) async throws -> NSImage? {
        let bridge = LinkPreviewCallbackBridge<NSImage?>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let startAllowed = bridge.register(continuation)
                guard startAllowed else { return }
                let progress = provider.loadObject(ofClass: NSImage.self) { object, _ in
                    bridge.finish(.success(object as? NSImage))
                }
                bridge.adopt(progress: progress)
            }
        } onCancel: {
            bridge.cancel()
        }
    }

    private static func loadProviderData(_ provider: NSItemProvider) async throws -> Data? {
        let bridge = LinkPreviewCallbackBridge<Data?>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let startAllowed = bridge.register(continuation)
                guard startAllowed else { return }
                let progress = provider.loadDataRepresentation(
                    forTypeIdentifier: UTType.image.identifier
                ) { data, _ in
                    bridge.finish(.success(data))
                }
                bridge.adopt(progress: progress)
            }
        } onCancel: {
            bridge.cancel()
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
