import Foundation

// MARK: - Link preview orchestration
// The state itself lives in the main `ClipboardStore` class body.

extension ClipboardStore {
    enum LinkMetadataState {
        case pending
        case successWithoutImage
        case successWithImage
        case failure
    }

    struct LinkFallbackTarget: Equatable {
        let itemID: UUID
        let url: URL
    }

    struct LinkFallbackRequest {
        let id: UUID
        let target: LinkFallbackTarget
    }

    private struct VisibleLinkURL {
        let item: ClipboardItem
        var url: URL { target.url }
        let target: LinkFallbackTarget
    }

    private enum LinkSnapshotOutcome {
        case apply(PreparedMedia)
        case failure
        case discard
    }

    /// Wraps a history mutation so reconcile observes only the completed final
    /// filter/selection and metadata registration state, never a transient one.
    func withHistoryStateMutation<T>(_ body: () -> T) -> T {
        isMutatingHistoryState = true
        defer {
            isMutatingHistoryState = false
            performLinkPreviewReconcile()
        }
        return body()
    }

    func performLinkPreviewReconcile() {
        let visible = visibleSelectedLinkURL()

        // Restore-history eligibility: a visible selected URL without a
        // current-session outcome still needs its metadata, including items
        // that already carry a persisted link title.
        if let visible, linkMetadataStates[visible.item.id] == nil, metadataTasks[visible.item.id] == nil {
            startLinkMetadataTask(itemID: visible.item.id, url: visible.url)
        }

        let candidate: LinkFallbackTarget? = visible.flatMap { visible in
            guard linkMetadataStates[visible.item.id] == .successWithoutImage else { return nil }
            return visible.target
        }

        if activeFallback == nil {
            guard let candidate else { return }
            startFallback(for: candidate)
        } else if let active = activeFallback, let candidate, !active.isCancelled {
            if candidate == active.request.target {
                // Same target: reselecting the current item evaluates cache and
                // retry state but never restarts the active request.
                return
            }
            cancelActiveLinkFallback()
        } else if let active = activeFallback, candidate == nil, !active.isCancelled {
            cancelActiveLinkFallback()
        }
    }

    /// The currently selected item must be a URL that is visible in
    /// `filteredItems`, without a stored preview image. The `selectedItem`
    /// first-visible fallback never authorizes fallback work, and neither does
    /// an out-of-filter selection.
    private func visibleSelectedLinkURL() -> VisibleLinkURL? {
        guard panelVisible, let selectedID else { return nil }
        guard let item = filteredItems.first(where: { $0.id == selectedID }) else { return nil }
        guard item.kind == .url, !item.hasLinkImagePayload else { return nil }
        guard let url = previewURL(of: item) else { return nil }
        return VisibleLinkURL(item: item, target: LinkFallbackTarget(itemID: item.id, url: url))
    }

    private func previewURL(of item: ClipboardItem) -> URL? {
        let raw = (item.textValue ?? item.preview).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: raw) else { return nil }
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else {
            return nil
        }
        return url
    }

    // MARK: Eager + lazy metadata enrichment

    func registerLinkMetadataIfNeeded(for insertedItem: ClipboardItem?) {
        guard let item = insertedItem,
              item.kind == .url,
              items.contains(where: { $0.id == item.id }),
              !item.hasLinkImagePayload,
              linkMetadataStates[item.id] == nil,
              metadataTasks[item.id] == nil,
              let url = previewURL(of: item) else {
            return
        }
        startLinkMetadataTask(itemID: item.id, url: url)
    }

    private func startLinkMetadataTask(itemID: UUID, url: URL) {
        linkMetadataStates[itemID] = .pending
        let requestID = UUID()
        metadataRequestIDs[itemID] = requestID
        let loader = fetchLinkMetadata
        let task = Task { [weak self] in
            let result: Result<LinkPreviewMetadata, Error>
            do {
                result = .success(try await loader(url))
            } catch {
                result = .failure(error)
            }
            self?.completeLinkMetadata(itemID: itemID, requestID: requestID, url: url, result: result)
        }
        metadataTasks[itemID] = task
        linkPreviewTasks.put(requestID, task: task)
    }

    private func completeLinkMetadata(
        itemID: UUID,
        requestID: UUID,
        url: URL,
        result: Result<LinkPreviewMetadata, Error>
    ) {
        linkPreviewTasks.remove(requestID)
        guard metadataRequestIDs[itemID] == requestID else {
            linkPreviewHandledObserver?()
            return
        }
        metadataRequestIDs[itemID] = nil
        metadataTasks[itemID] = nil

        if isCancellationResult(result) {
            if linkMetadataStates[itemID] == .pending {
                linkMetadataStates[itemID] = nil
            }
            diagnostics.logLinkPreview(itemID: itemID, outcome: .metadataCancelled, uptime: uptimeProvider())
            linkPreviewHandledObserver?()
            return
        }

        guard let index = items.firstIndex(where: { $0.id == itemID }),
              items[index].kind == .url,
              previewURL(of: items[index]) == url else {
            // Item removed or its URL changed: transients were cleaned up, and
            // a late result can neither restore the item nor save anything.
            if linkMetadataStates[itemID] == .pending {
                linkMetadataStates[itemID] = nil
            }
            linkPreviewHandledObserver?()
            return
        }

        switch result {
        case .failure:
            linkMetadataStates[itemID] = .failure
            diagnostics.logLinkPreview(itemID: itemID, outcome: .metadataFailure, uptime: uptimeProvider())
        case .success(let metadata):
            applyLinkMetadata(itemID: itemID, index: index, metadata: metadata)
            logLinkMetadataOutcome(itemID: itemID, metadata: metadata)
        }
        linkPreviewHandledObserver?()
        reconcileLinkPreviewFallback()
    }

    private func logLinkMetadataOutcome(itemID: UUID, metadata: LinkPreviewMetadata) {
        let outcome: ClipboardDiagnostics.LinkPreviewOutcome
        if metadata.image != nil {
            outcome = .metadataImage
        } else if metadata.title != nil {
            outcome = .metadataTitleOnly
        } else {
            outcome = .metadataEmpty
        }
        diagnostics.logLinkPreview(itemID: itemID, outcome: outcome, uptime: uptimeProvider())
    }

    private func applyLinkMetadata(itemID: UUID, index: Int, metadata: LinkPreviewMetadata) {
        let existing = items[index]
        // A payload the item already has — resident or still persisted — keeps
        // its identity; absent metadata bytes must not overwrite an unloaded
        // preview, and neither outcome is classified as image-less. Only an
        // item without any payload accepts new metadata bytes.
        let replacementImage = existing.hasLinkImagePayload ? nil : metadata.image
        linkMetadataStates[itemID] = existing.hasLinkImagePayload || metadata.image != nil
            ? .successWithImage
            : .successWithoutImage
        let mergedTitle = metadata.title ?? existing.linkTitle
        guard mergedTitle != existing.linkTitle || replacementImage != nil else {
            // Empty metadata success: eligible for fallback, and empty results
            // clear neither title nor image, producing no update or save.
            return
        }

        // The payload is already finalized and bounded, so it is applied as it
        // is: no re-encoding and no new identity.
        updateItem(at: index) {
            $0.withLinkPreview(title: mergedTitle, linkImage: replacementImage)
        }
        refreshFilteredItems()
        saveItems()
    }

    // MARK: Browser fallback lifecycle

    private func startFallback(for target: LinkFallbackTarget) {
        let cacheKey = target.url.absoluteString
        if let cached = snapshotPositiveCache[cacheKey] {
            // Positive cache hits reuse the session image without a loader,
            // still subject to the same visibility/selection/eligibility checks.
            // Only a real apply may re-reconcile; otherwise stop here to keep
            // the cache-hit path free of re-entry loops.
            let applied = applyValidatedSnapshot(target: target, image: cached)
            diagnostics.logLinkPreview(
                itemID: target.itemID,
                outcome: applied ? .snapshotCacheApplied : .snapshotFailed,
                uptime: uptimeProvider()
            )
            if applied {
                reconcileLinkPreviewFallback()
            }
            return
        }
        purgeExpiredSnapshotRejections()
        guard snapshotNegativeUntil[cacheKey] == nil else { return }

        let request = LinkFallbackRequest(id: UUID(), target: target)
        activeFallback = (request: request, isCancelled: false)
        diagnostics.logLinkPreview(
            itemID: target.itemID,
            outcome: .snapshotStarted,
            uptime: uptimeProvider()
        )
        let loader = fetchLinkSnapshot
        let requestID = request.id
        let task = Task { [weak self] in
            let result: Result<PreparedMedia, Error>
            do {
                result = .success(try await loader(target.url))
            } catch {
                result = .failure(error)
            }
            self?.completeLinkFallback(requestID: requestID, target: target, result: result)
        }
        fallbackTask = task
        linkPreviewTasks.put(requestID, task: task)
    }

    private func completeLinkFallback(
        requestID: UUID,
        target: LinkFallbackTarget,
        result: Result<PreparedMedia, Error>
    ) {
        linkPreviewTasks.remove(requestID)
        guard let active = activeFallback, active.request.id == requestID else {
            linkPreviewHandledObserver?()
            return
        }
        // The finished (or cancelled-then-finished) request clears its own slot;
        // the restarted decision below re-reads the current UI state instead of
        // a target captured before cleanup.
        activeFallback = nil
        fallbackTask = nil

        if active.isCancelled || isCancellationResult(result) {
            // Cancelled and superseded: no apply, no cache write, no save.
            diagnostics.logLinkPreview(itemID: target.itemID, outcome: .snapshotCancelled, uptime: uptimeProvider())
            linkPreviewHandledObserver?()
            reconcileLinkPreviewFallback()
            return
        }

        let image: PreparedMedia?
        if case .success(let media) = result {
            image = media
        } else {
            image = nil
        }

        switch validatedSnapshotOutcome(target: target, image: image) {
        case .apply(let media):
            let applied = applyValidatedSnapshot(target: target, image: media)
            diagnostics.logLinkPreview(
                itemID: target.itemID,
                outcome: applied ? .snapshotApplied : .snapshotFailed,
                uptime: uptimeProvider()
            )
        case .failure:
            recordSnapshotRejection(for: target.url)
            diagnostics.logLinkPreview(itemID: target.itemID, outcome: .snapshotFailed, uptime: uptimeProvider())
        case .discard:
            break
        }
        linkPreviewHandledObserver?()
        reconcileLinkPreviewFallback()
    }

    /// Identity, kind, URL, eligibility, visibility, selection and image-nil
    /// checks for snapshot results (live and cached alike).
    private func validatedSnapshotOutcome(
        target: LinkFallbackTarget,
        image: PreparedMedia?
    ) -> LinkSnapshotOutcome {
        guard panelVisible,
              selectedID == target.itemID,
              let item = filteredItems.first(where: { $0.id == target.itemID }),
              item.kind == .url,
              previewURL(of: item) == target.url,
              !item.hasLinkImagePayload,
              linkMetadataStates[item.id] == .successWithoutImage else {
            return .discard
        }
        guard let image else { return .failure }
        return .apply(image)
    }

    /// Applies a validated snapshot through the existing persistence path.
    /// Returns whether anything was applied, so cache-hit reconcile can never
    /// re-enter itself.
    @discardableResult
    private func applyValidatedSnapshot(target: LinkFallbackTarget, image: PreparedMedia) -> Bool {
        switch validatedSnapshotOutcome(target: target, image: image) {
        case .apply:
            storeCachedSnapshot(image, for: target.url)
            if let item = filteredItems.first(where: { $0.id == target.itemID }) {
                applyLinkPreview(itemID: target.itemID, title: item.linkTitle, linkImage: image)
            }
            return true
        case .failure, .discard:
            return false
        }
    }

    private func cancelActiveLinkFallback() {
        guard let active = activeFallback, !active.isCancelled else { return }
        activeFallback = (request: active.request, isCancelled: true)
        fallbackTask?.cancel()
    }

    // MARK: Removal cleanup (delete, Clear History, history eviction)

    func cleanupLinkPreviewWork(forRemovedItemIDs removedIDs: [UUID]) {
        guard !removedIDs.isEmpty else { return }
        let removed = Set(removedIDs)
        for itemID in removedIDs {
            metadataTasks[itemID]?.cancel()
            metadataTasks[itemID] = nil
            linkMetadataStates[itemID] = nil
            if let requestID = metadataRequestIDs.removeValue(forKey: itemID) {
                linkPreviewTasks.remove(requestID)
            }
        }
        if let active = activeFallback, removed.contains(active.request.target.itemID) {
            cancelActiveLinkFallback()
        }
    }

    // MARK: Session snapshot caches

    private func storeCachedSnapshot(_ media: PreparedMedia, for url: URL) {
        let key = url.absoluteString
        if snapshotPositiveCache[key] != nil {
            snapshotPositiveCache[key] = media
            return
        }
        snapshotPositiveCache[key] = media
        snapshotPositiveCacheOrder.append(key)
        if snapshotPositiveCacheOrder.count > snapshotCacheLimit {
            let evictedKey = snapshotPositiveCacheOrder.removeFirst()
            snapshotPositiveCache[evictedKey] = nil
        }
    }

    /// Failure-only retry suppression. Cancellation and stale completions never
    /// create entries; expiry evaluation happens on read without a timer.
    private func recordSnapshotRejection(for url: URL) {
        purgeExpiredSnapshotRejections()
        snapshotNegativeUntil[url.absoluteString] = uptimeProvider() + snapshotRetryTTL
        if snapshotNegativeUntil.count > snapshotCacheLimit {
            if let earliestKey = snapshotNegativeUntil.min(by: { $0.value < $1.value })?.key {
                snapshotNegativeUntil[earliestKey] = nil
            }
        }
    }

    private func purgeExpiredSnapshotRejections() {
        let now = uptimeProvider()
        snapshotNegativeUntil = snapshotNegativeUntil.filter { $0.value > now }
    }

    // MARK: Cancellation classification

    private func isCancellationResult<Value>(_ result: Result<Value, Error>) -> Bool {
        if case .failure(let error) = result, error is CancellationError {
            return true
        }
        return Task.isCancelled
    }
}
