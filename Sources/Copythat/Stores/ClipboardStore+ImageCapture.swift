import AppKit
import Foundation

/// One admitted image capture carrying every value its eventual card needs.
/// All of it is snapshotted at admission, so neither a queue delay nor a changed
/// foreground application can alter the resulting card.
struct PendingImageCapture {
    /// Monotonic across generations; identifies both deletion authority and
    /// physical slot ownership.
    let sequence: Int
    let generation: Int
    let changeCount: Int
    let capturedAt: Date
    let displaySize: NSSize
    let cgImage: CGImage
    let source: ClipboardSource
    /// Hash observation installed for this admission. A detached task does not
    /// inherit task-local values, so each request carries its own across.
    let recorder: MediaHashRecorder?
}

// Image pipeline state stays on ClipboardStore; these same-module transitions
// share its MainActor ownership, just like the existing preview extension.
extension ClipboardStore {
    /// Bounded PNG finalization for one admitted capture, run off MainActor.
    /// The recorder travels with the request rather than being read at launch,
    /// so a later capture never reuses an earlier one's observation context.
    typealias ImageCaptureEncoder = @Sendable (CGImage, MediaHashRecorder?) async -> PreparedMedia?

    /// Production finalization: the 1200px PNG algorithm and its single content
    /// address, together and outside MainActor. Tests wrap this exact pipeline
    /// so a controlled encoder controls only *when* work happens, never *how*.
    nonisolated static let defaultImageEncoder: ImageCaptureEncoder = { cgImage, recorder in
        await MediaHashObservation.propagating(recorder) {
            ClipboardStore.pngData(cgImage: cgImage, maxPixel: 1_200).map { PreparedMedia(hashing: $0) }
        }
    }

    /// Whether suppression authority for a content key is currently retained.
    /// Automatic retention eviction never records one, and a recorded cutoff is
    /// released once no buffered capture can still be rejected by it.
    func hasDeletedContentKey(_ key: String) -> Bool {
        deletedContentCutoffs[key] != nil
    }

    /// Completion authority for an image admitted at `sequence`. Suppression is
    /// limited to matching content admitted no later than the deletion, so an
    /// unrelated deletion never blocks a capture and an intentional recopy of
    /// the same bytes stays eligible.
    func shouldInsertEncodedItem(_ item: ClipboardItem, admittedAt sequence: Int) -> Bool {
        guard let cutoff = deletedContentCutoffs[item.contentKey] else { return true }
        return sequence > cutoff
    }

    /// Buffered captures the Store owns, including invalidated active work that
    /// has not actually finished.
    var pendingImageCaptureCount: Int {
        waitingImageCaptures.count + (activeImageCapture == nil ? 0 : 1)
    }

    var hasPendingImageCapture: Bool {
        pendingImageCaptureCount > 0
    }

    /// Deletion-authority records currently retained. Suppression is transient
    /// bookkeeping over the outstanding admission window, so this must fall
    /// back to zero once no buffered capture can still be rejected.
    var retainedDeletionAuthorityCount: Int {
        deletedContentCutoffs.count
    }

    /// Admits one stably observed image. Everything the eventual card needs is
    /// snapshotted now; at capacity the oldest *waiting* capture is evicted
    /// before the new one is appended, so buffered raw captures never exceed
    /// the bound and the physical active slot is never reclaimed to make room.
    func admitImageCapture(
        cgImage: CGImage,
        displaySize: NSSize,
        source: ClipboardSource,
        currentChangeCount: Int
    ) {
        let capture = PendingImageCapture(
            sequence: nextImageAdmissionSequence,
            generation: imageCaptureGeneration,
            changeCount: currentChangeCount,
            capturedAt: Date(),
            displaySize: displaySize,
            cgImage: cgImage,
            source: source,
            recorder: MediaHashObservation.recorder
        )
        nextImageAdmissionSequence += 1

        var evicted: PendingImageCapture?
        if pendingImageCaptureCount >= imageCaptureCapacity, !waitingImageCaptures.isEmpty {
            evicted = waitingImageCaptures.removeFirst()
            pruneDeletionCutoffs()
        }
        waitingImageCaptures.append(capture)
        if let evicted {
            diagnostics.logImageEncodingOverflow(
                sequence: evicted.sequence,
                changeCount: evicted.changeCount,
                sourceApp: evicted.source.appName,
                queueDepth: pendingImageCaptureCount,
                uptime: uptimeProvider()
            )
        }
        startNextImageCaptureIfIdle()
    }

    /// The only transition that launches encoding work, so the pipeline never
    /// holds more than one physical capture encoder.
    private func startNextImageCaptureIfIdle() {
        guard activeImageCapture == nil, !waitingImageCaptures.isEmpty else { return }
        let capture = waitingImageCaptures.removeFirst()
        activeImageCapture = capture

        let encodeImage = self.encodeImage
        let encodingTask = Task.detached(priority: .utility) {
            await encodeImage(capture.cgImage, capture.recorder)
        }
        // Only this task resolves the Store, and only after the background work
        // has returned, so no strong reference crosses the await. No handle is
        // retained: cancellation is not the authorization mechanism, and the
        // active slot — not a task reference — owns the physical work.
        Task { @MainActor [weak self] in
            let prepared = await encodingTask.value
            self?.handleImageCaptureCompletion(capture, prepared: prepared)
        }
    }

    /// Terminal handling for one request, reached for success, nil encoding and
    /// invalidation alike. Physical ownership is released before result
    /// authorization, so a stale request frees only its own slot and can never
    /// clear the state of a request that started after it.
    private func handleImageCaptureCompletion(
        _ capture: PendingImageCapture,
        prepared: PreparedMedia?
    ) {
        guard activeImageCapture?.sequence == capture.sequence else { return }
        activeImageCapture = nil

        if let prepared, capture.generation == imageCaptureGeneration {
            let item = makeImageItem(for: capture, prepared: prepared)
            if shouldInsertEncodedItem(item, admittedAt: capture.sequence) {
                add(item)
            }
        }

        pruneDeletionCutoffs()
        imageCompletionHandledObserver?()
        startNextImageCaptureIfIdle()
    }

    private func makeImageItem(for capture: PendingImageCapture, prepared: PreparedMedia) -> ClipboardItem {
        ClipboardItem(
            id: UUID(),
            kind: .image,
            title: "Image",
            preview: "\(Int(capture.displaySize.width)) x \(Int(capture.displaySize.height))",
            sourceApp: capture.source.appName,
            sourceAppIconData: capture.source.iconData,
            sourceAppIconBlobID: capture.source.iconBlobID,
            createdAt: capture.capturedAt,
            isPinned: false,
            pinboardName: nil,
            textValue: nil,
            fileURLs: [],
            imageData: prepared.data,
            imageBlobID: prepared.id
        )
    }

    /// Revokes insertion eligibility for everything admitted so far and drops
    /// waiting captures. A started encoder keeps the physical slot until it
    /// actually returns, so a newly admitted capture waits instead of running a
    /// second encoder alongside it.
    func invalidateImageCaptures() {
        imageCaptureGeneration += 1
        waitingImageCaptures.removeAll()
        pruneDeletionCutoffs()
    }

    /// Records, per deleted content key, the highest image admission sequence so
    /// far. A completion at or before that sequence is stale. Repeated deletion
    /// keeps the greatest cutoff, so a later deletion can only widen
    /// suppression, never authorize an older completion.
    func rememberDeleted(_ removedItems: [ClipboardItem]) {
        let cutoff = nextImageAdmissionSequence - 1
        for key in removedItems.map(\.contentKey) {
            deletedContentCutoffs[key] = max(deletedContentCutoffs[key] ?? cutoff, cutoff)
        }
        pruneDeletionCutoffs()
    }

    /// Drops deletion authority no outstanding request can be rejected by.
    /// A cutoff older than the oldest request still buffered protects nothing;
    /// newer requests cannot reach it, and with nothing outstanding every
    /// remaining cutoff is unreachable. Unlike a fixed-size FIFO this cannot
    /// evict protection an in-flight completion still depends on.
    private func pruneDeletionCutoffs() {
        guard let oldestOutstanding = oldestOutstandingImageSequence() else {
            deletedContentCutoffs.removeAll()
            return
        }
        deletedContentCutoffs = deletedContentCutoffs.filter { _, cutoff in
            cutoff >= oldestOutstanding
        }
    }

    private func oldestOutstandingImageSequence() -> Int? {
        let oldestWaiting = waitingImageCaptures.map(\.sequence).min()
        switch (activeImageCapture?.sequence, oldestWaiting) {
        case let (active?, waiting?):
            return min(active, waiting)
        case let (active?, nil):
            return active
        case let (nil, waiting?):
            return waiting
        case (nil, nil):
            return nil
        }
    }
}
