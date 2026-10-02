import Foundation

// Restoration state stays on ClipboardStore; this same-module extension shares
// its MainActor ownership, like the image capture and link preview extensions.
extension ClipboardStore {
    /// Current restoration phase, read-only. Presentation and guards consult it
    /// through `isRestoringHistory` and `canMutateHistory`.
    var restoreState: HistoryRestoreState { historyRestoreState }

    /// Whether history organization actions may run. Destructive entry points
    /// consult this before any side effect, so a rejected call cannot leave a
    /// half-applied history behind. A normal-Quit drain closes it too, so a
    /// drain cannot be undone by an action that invalidates accepted work.
    var canMutateHistory: Bool { historyRestoreState == .ready && !isCaptureAdmissionPaused }

    /// Begins one-shot startup restoration. The loading state is published
    /// before this returns, so a caller that observes the Store immediately
    /// afterwards already sees loading history rather than an empty timeline.
    ///
    /// Repeated calls are ignored — including after the completion handle has
    /// been cleared — so the loader can never be invoked twice.
    func beginHistoryRestore(with loader: any ClipboardHistoryLoading) {
        guard !didBeginHistoryRestore else { return }
        didBeginHistoryRestore = true
        historyRestoreState = .restoring
        publishHistoryRestoring(true)
        historyRestoreTask = Task { @MainActor [weak self] in
            // The Store is resolved only after the load, never before: an
            // awaited task must not hold the Store strongly across the load.
            let loaded: [ClipboardItem]
            do {
                loaded = try await loader.loadItems()
            } catch {
                // A failed load is an empty baseline. Buffered startup captures
                // still replay, and the failure itself requests no save and
                // overwrites no prior input.
                loaded = []
            }
            guard let self else { return }
            self.applyRestoredHistory(loaded)
        }
    }

    /// Awaits the existing restoration. A Store that never restored, or one
    /// that already finished, returns immediately.
    func finishHistoryRestore() async {
        guard let task = historyRestoreTask else { return }
        await task.value
    }

    /// Installs the persisted baseline and replays every buffered capture.
    ///
    /// The whole pass is one `withHistoryStateMutation`, so reconcile observes
    /// only the completed baseline-plus-replay history — never a transient
    /// baseline selection. The ordinary bool-based wrapper is therefore never
    /// nested: `applyAdd` is called directly, not through `add`.
    private func applyRestoredHistory(_ baseline: [ClipboardItem]) {
        historyRestoreState = .applying
        withHistoryStateMutation {
            // The current normalized limit wins over anything captured earlier.
            let enforcement = ClipboardHistoryPolicy.enforcingLimits(
                on: baseline,
                limit: settings.historyLimit
            )
            // Only an actual trim is dirty on its own; installing and filtering
            // an already-bounded baseline must not request a save.
            if !enforcement.removedItemIDs.isEmpty {
                isBootstrapDirty = true
            }
            installRestoredBaseline(enforcement.items)
            refreshFilteredItems()

            // Draining rather than snapshotting means an arrival that re-enters
            // during this synchronous turn is still replayed, in order.
            while !startupCaptureBuffer.isEmpty {
                applyAdd(startupCaptureBuffer.removeFirst())
            }
            refreshFilteredItems()
        }
        historyRestoreState = .ready
        publishHistoryRestoring(false)
        historyRestoreTask = nil
        if isBootstrapDirty {
            isBootstrapDirty = false
            saveItems()
        }
    }
}
