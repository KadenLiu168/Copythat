import AppKit
import Combine
import Foundation
import ImageIO
import UniformTypeIdentifiers

private struct PendingObservation {
    let changeCount: Int
    let firstObservedSource: ClipboardSource?
    let firstObservedUptime: TimeInterval
}

enum ClipboardPasteMaterializationError: Error {
    case undecodableImage
}

/// Registry for Store-owned link preview tasks so releasing the Store cancels
/// remaining preview work. Entries are removed when their completion is handled;
/// `cancelAll` is thread-safe so a nonisolated deinit can cancel stragglers.
final class LinkPreviewTaskRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var tasks: [UUID: Task<Void, Never>] = [:]

    func put(_ key: UUID, task: Task<Void, Never>) {
        lock.lock()
        tasks[key] = task
        lock.unlock()
    }

    func remove(_ key: UUID) {
        lock.lock()
        tasks[key] = nil
        lock.unlock()
    }

    func cancelAll() {
        lock.lock()
        let registered = Array(tasks.values)
        tasks.removeAll()
        lock.unlock()
        for task in registered {
            task.cancel()
        }
    }
}

/// Startup restoration lifecycle. One-shot and startup-specific: a Store built
/// with explicit items stays `ready` forever. Not a mutation journal.
enum HistoryRestoreState: Sendable, Equatable {
    case ready
    /// The loader is in flight; arrivals are buffered rather than inserted.
    case restoring
    /// Baseline installation and replay, in one synchronous MainActor turn.
    case applying
}

@MainActor
final class ClipboardStore: ObservableObject {
    @Published private(set) var items: [ClipboardItem] = []
    @Published private(set) var filteredItems: [ClipboardItem] = []
    @Published var selectedID: UUID? {
        didSet {
            guard !isMutatingHistoryState else { return }
            reconcileLinkPreviewFallback()
        }
    }
    @Published var searchText = "" {
        didSet { refreshFilteredItems() }
    }
    @Published var selectedBoardID = Pinboard.all.id {
        didSet { refreshFilteredItems() }
    }
    @Published var permissionMessage: String?

    /// Read-only loading publication: true from the synchronous
    /// `beginHistoryRestore(with:)` call until the baseline and every replayed
    /// capture are applied. State is internal so
    /// `ClipboardStore+HistoryRestore.swift` owns the lifecycle.
    @Published private(set) var isRestoringHistory = false
    var historyRestoreState: HistoryRestoreState = .ready
    /// Survives clearing the task handle, so a repeated begin cannot start a
    /// second restoration or invoke the loader twice.
    var didBeginHistoryRestore = false
    /// Handle for the in-flight restoration, so Quit can await real completion.
    var historyRestoreTask: Task<Void, Never>?
    /// Complete items deferred until the baseline existed, in `add` order.
    var startupCaptureBuffer: [ClipboardItem] = []
    /// Set by any pre-restoration save request and by an actual baseline trim.
    var isBootstrapDirty = false
    /// Normal-Quit admission pause. Unlike `stopMonitoring` it closes new
    /// admission without invalidating already accepted images, so the accepted
    /// set stays finite enough to drain. Paired with the monitoring flag below.
    @Published private(set) var isCaptureAdmissionPaused = false
    /// Whether scheduled monitoring was active when the pause began, so Cancel
    /// Quit restores exactly the prior activity and no more.
    var wasMonitoringBeforeAdmissionPause = false
    /// Continuations awaiting the image pipeline going idle. Control state only.
    var imageDrainWaiters: [CheckedContinuation<Void, Never>] = []

    let pasteboard: NSPasteboard
    // Internal so `ClipboardStore+HistoryRestore.swift` enforces limits with the
    // same current settings every other extension already reads.
    let settings: AppSettings
    // Shared with `ClipboardStore+SourceAttribution.swift`, like `pasteboard`,
    // `settings` and `mediaLoader` already are.
    let sourceTracker: CopySourceTracker
    let diagnostics: ClipboardDiagnostics
    /// Shared on-demand media access for card display, paste materialization
    /// and image drag, all reading the same persisted blob store.
    let mediaLoader: ClipboardHistoryMediaLoader
    private let persistItems: ([ClipboardItem]) -> Void
    private var historyLimitCancellable: AnyCancellable?
    var timer: Timer?
    var pollTask: Task<Void, Never>?
    private var lastChangeCount: Int
    private var pendingObservation: PendingObservation?
    var isMonitoring = false
    private var burstTask: Task<Void, Never>?
    private var burstDeadline: TimeInterval?
    private var burstGeneration = 0
    /// Admitted image captures that have not started encoding. They hold raw
    /// `CGImage` bytes but launch no work of their own.
    var waitingImageCaptures: [PendingImageCapture] = []
    /// The single request holding the sole physical encoding slot, if any. A
    /// request invalidated by Clear History or a stop keeps the slot until its
    /// encoder actually returns.
    var activeImageCapture: PendingImageCapture?
    /// Revokes insertion eligibility only. Clear History and monitoring stop
    /// advance it and drop waiting captures; a started encoder is untouched.
    var imageCaptureGeneration = 0
    /// Next admission sequence. One-based, so a deletion before any admission
    /// records a cutoff no real completion can reach.
    var nextImageAdmissionSequence = 1
    /// Buffered captures allowed, including active work. Production is four.
    let imageCaptureCapacity: Int
    let encodeImage: ImageCaptureEncoder
    /// Deterministic test seam: invoked on the main actor after every admitted
    /// image completion has been applied or rejected, letting tests await
    /// handled transitions without sleeps — including rejected ones.
    var imageCompletionHandledObserver: (() -> Void)?
    /// Highest image admission sequence each deleted content key has rejected.
    /// A completion at or before its cutoff is stale; a later intentional copy
    /// of the same content is not. Holds identities only, never clipboard bytes.
    var deletedContentCutoffs: [String: Int] = [:]
    let uptimeProvider: () -> TimeInterval
    private let minimumStabilityInterval: TimeInterval
    private let burstPollInterval: TimeInterval
    private let burstWindow: TimeInterval

    /// Blob identities one successful commit authorized for an item. Roles are
    /// independent: a receipt carrying only one role never clears the other.
    struct DurableMediaReferences: Equatable {
        var imageBlobID: String?
        var linkImageBlobID: String?
    }

    /// Committed heavy media awaiting release. Entries hold references only —
    /// an item's UUID plus the blob identities its commit covered — and never
    /// Data, prepared payloads, snapshots, or closures capturing them. Release
    /// handling lives in `ClipboardStore+DurableMediaRelease.swift`.
    var pendingDurableMediaRelease: [UUID: DurableMediaReferences] = [:]

    // Link preview orchestration state. Extensitivity lives in
    // `ClipboardStore+LinkPreview.swift`; visibility here stays internal so the
    // same-module extension can operate on the single source of truth.
    typealias LinkMetadataLoader = @Sendable (URL) async throws -> LinkPreviewMetadata
    typealias LinkSnapshotLoader = @Sendable (URL) async throws -> PreparedMedia

    /// Observable read-only panel visibility. Cards use it to gate their lazy
    /// media loading, so `close()` must publish even while the hosting view
    /// stays retained.
    @Published private(set) var panelVisible = false
    /// Advances on every visibility transition. A card request captures the
    /// generation it started under, so a close→reopen within one update cycle
    /// still invalidates the older request even if SwiftUI never rendered the
    /// hidden state.
    private(set) var panelAuthorizationGeneration = 0
    let fetchLinkMetadata: LinkMetadataLoader
    let fetchLinkSnapshot: LinkSnapshotLoader
    var linkMetadataStates: [UUID: LinkMetadataState] = [:]
    var metadataTasks: [UUID: Task<Void, Never>] = [:]
    var metadataRequestIDs: [UUID: UUID] = [:]
    var activeFallback: (request: LinkFallbackRequest, isCancelled: Bool)?
    var fallbackTask: Task<Void, Never>?
    var snapshotPositiveCache: [String: PreparedMedia] = [:]
    var snapshotPositiveCacheOrder: [String] = []
    var snapshotNegativeUntil: [String: TimeInterval] = [:]
    let snapshotCacheLimit = 64
    let snapshotRetryTTL: TimeInterval = 300
    var isMutatingHistoryState = false
    /// Deterministic test seam: invoked on the main actor after a
    /// settings-driven limit enforcement has been evaluated, so a test can await
    /// the deferred turn and assert what it did *not* save.
    var historyBoundsEnforcedObserver: (() -> Void)?
    /// Deterministic test seam: invoked on the main actor after processing each
    /// link preview completion, letting tests await checkpoints without sleeps.
    var linkPreviewHandledObserver: (() -> Void)?
    let linkPreviewTasks = LinkPreviewTaskRegistry()

    /// `items` keeps a private setter; preview enrichment updates through this
    /// internal helper so the orchestration extension can replace single items.
    func updateItem(at index: Int, transform: (ClipboardItem) -> ClipboardItem) {
        items[index] = transform(items[index])
    }

    /// Publishes the released copies produced by the durable-media extension,
    /// which cannot write these private setters from another file. A nil array
    /// changed nothing and is left untouched, so each is assigned at most once.
    func publishReleasedResidentMedia(
        items releasedItems: [ClipboardItem]?,
        filteredItems releasedFilteredItems: [ClipboardItem]?
    ) {
        if let releasedItems {
            items = releasedItems
        }
        if let releasedFilteredItems {
            filteredItems = releasedFilteredItems
        }
    }

    /// Publishes the restoration lifecycle's loading state, which the
    /// restoration extension cannot write behind the private setter.
    func publishHistoryRestoring(_ isRestoring: Bool) {
        isRestoringHistory = isRestoring
    }

    /// Installs the enforced persisted baseline, which the restoration
    /// extension cannot write behind the private `items` setter.
    func installRestoredBaseline(_ baseline: [ClipboardItem]) {
        items = baseline
    }
    init(
        settings: AppSettings,
        sourceTracker: CopySourceTracker,
        initialItems: [ClipboardItem] = [],
        pasteboard: NSPasteboard = .general,
        diagnostics: ClipboardDiagnostics = ClipboardDiagnostics(),
        mediaLoader: ClipboardHistoryMediaLoader = .shared,
        persistItems: @escaping ([ClipboardItem]) -> Void = ClipboardHistoryPersistence.save,
        uptimeProvider: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        fetchLinkMetadata: @escaping LinkMetadataLoader = { try await LinkPreviewFetcher.fetchMetadata(url: $0) },
        fetchLinkSnapshot: @escaping LinkSnapshotLoader = { try await LinkPreviewFetcher.fetchWebSnapshot(url: $0) },
        minimumStabilityInterval: TimeInterval = 0.15,
        burstPollInterval: TimeInterval = 0.06,
        burstWindow: TimeInterval = 0.6,
        imageCaptureCapacity: Int = 4,
        encodeImage: @escaping ImageCaptureEncoder = ClipboardStore.defaultImageEncoder
    ) {
        self.settings = settings
        self.sourceTracker = sourceTracker
        self.pasteboard = pasteboard
        self.diagnostics = diagnostics
        self.mediaLoader = mediaLoader
        self.persistItems = persistItems
        self.uptimeProvider = uptimeProvider
        self.fetchLinkMetadata = fetchLinkMetadata
        self.fetchLinkSnapshot = fetchLinkSnapshot
        self.minimumStabilityInterval = minimumStabilityInterval
        self.burstPollInterval = burstPollInterval
        self.burstWindow = burstWindow
        self.imageCaptureCapacity = imageCaptureCapacity
        // Eviction needs a waiting capture to replace. Below two, admission
        // would append past the bound instead of dropping one, so the seam
        // refuses to model a buffer it cannot enforce.
        precondition(imageCaptureCapacity >= 2, "the image capture buffer needs room for an active slot and one waiting capture")
        self.encodeImage = encodeImage
        lastChangeCount = pasteboard.changeCount
        // Construction is purely in memory: nothing here reads the manifest.
        // Startup bounds still apply to items the caller supplied, so an
        // explicit startup behaves exactly as it always did.
        let startupEnforcement = ClipboardHistoryPolicy.enforcingLimits(
            on: initialItems,
            limit: settings.historyLimit
        )
        items = startupEnforcement.items
        refreshFilteredItems()
        if !startupEnforcement.removedItemIDs.isEmpty {
            saveItems()
        }
        historyLimitCancellable = settings.$historyLimit
            .dropFirst()
            .sink { [weak self] _ in
                // `@Published` publishes in `willSet`, so defer to a later
                // main-actor turn and re-read the normalized current value.
                Task { @MainActor [weak self] in
                    self?.enforceHistoryBounds()
                }
            }
    }

    deinit {
        // Store release must cancel remaining preview work without touching
        // actor state; the registry itself is thread-safe.
        linkPreviewTasks.cancelAll()
    }

    var selectedItem: ClipboardItem? {
        filteredItems.first { $0.id == selectedID } ?? filteredItems.first
    }

    // Test seam replacement: real single-task burst scheduling.
    var isBurstPollingActive: Bool { burstTask != nil }
    var burstDeadlineUptime: TimeInterval? { burstDeadline }

    /// Copy-intent wake signal from `CopySourceTracker` (D2/D3): starts or extends
    /// the bounded burst loop; rejected while monitoring is stopped.
    func handleCopyIntentWake() {
        guard !isCaptureAdmissionPaused else { return }
        extendBurst()
    }

    // MARK: - Panel visibility

    /// Called by PanelWindowController once the window is displayed and its
    /// selection is ready. Authorizes fallback evaluation for the visible
    /// selected URL; metadata enrichment is independent of visibility.
    func panelDidOpen() {
        panelVisible = true
        panelAuthorizationGeneration += 1
        if let selectedID {
            diagnostics.logLinkPreview(itemID: selectedID, outcome: .panelOpened, uptime: uptimeProvider())
        }
        reconcileLinkPreviewFallback()
    }

    /// Called by PanelWindowController before the window is ordered out. Closing
    /// revokes eligibility first so NSHostingView retention cannot keep a
    /// fallback alive, and metadata enrichment continues. Revoking visibility is
    /// also the ownership boundary that releases committed heavy media deferred
    /// while the panel was visible.
    func panelDidClose() {
        panelVisible = false
        panelAuthorizationGeneration += 1
        consumePendingDurableMediaRelease()
        if let itemID = activeFallback?.request.target.itemID ?? selectedID {
            diagnostics.logLinkPreview(itemID: itemID, outcome: .panelClosed, uptime: uptimeProvider())
        }
        reconcileLinkPreviewFallback()
    }

    /// Latest-wins evaluation entry for the browser fallback and lazy metadata.
    /// All panel visibility, selection, filtering and completion paths funnel
    /// here; mid-mutation calls are deferred to the end of the mutation.
    func reconcileLinkPreviewFallback() {
        guard !isMutatingHistoryState else {
            return
        }
        performLinkPreviewReconcile()
    }
}

// MARK: - Selection and history mutations

extension ClipboardStore {
    func selectFirstVisibleItem() {
        selectID(filteredItems.first?.id)
    }

    func clearPermissionMessage() {
        permissionMessage = nil
    }

    func select(_ item: ClipboardItem) {
        selectID(item.id)
    }

    func moveSelection(_ delta: Int) {
        let visible = filteredItems
        guard !visible.isEmpty else {
            selectID(nil)
            return
        }
        let currentIndex = visible.firstIndex { $0.id == selectedID } ?? 0
        let nextIndex = min(max(currentIndex + delta, 0), visible.count - 1)
        selectID(visible[nextIndex].id)
    }

    func togglePin(_ item: ClipboardItem) {
        guard canMutateHistory else { return }
        withHistoryStateMutation {
            guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
            items[index].isPinned.toggle()
            refreshFilteredItems()
            saveItems()
        }
    }

    func move(_ item: ClipboardItem, toPinboard name: String?) {
        guard canMutateHistory else { return }
        withHistoryStateMutation {
            guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
            items[index].pinboardName = name
            refreshFilteredItems()
            saveItems()
        }
    }

    func pinboardAssignmentCount(named name: String) -> Int {
        items.filter { $0.pinboardName == name }.count
    }

    func clearPinboardAssignments(named name: String) {
        guard canMutateHistory else { return }
        withHistoryStateMutation {
            var didChange = false
            for index in items.indices where items[index].pinboardName == name {
                items[index].pinboardName = nil
                didChange = true
            }

            guard didChange else { return }
            refreshFilteredItems()
            saveItems()
        }
    }

    func renamePinboardAssignments(from oldName: String, to newName: String) {
        guard canMutateHistory else { return }
        withHistoryStateMutation {
            var didChange = false
            for index in items.indices where items[index].pinboardName == oldName {
                items[index].pinboardName = newName
                didChange = true
            }

            guard didChange else { return }
            refreshFilteredItems()
            saveItems()
        }
    }

    func migrateSelectionAfterPinboardRename(from oldName: String, to newName: String) {
        guard selectedBoardID == Pinboard.custom(oldName).id else { return }
        selectedBoardID = Pinboard.custom(newName).id
    }

    func selectClipboardIfViewingPinboard(named name: String) {
        guard selectedBoardID == Pinboard.custom(name).id else { return }
        selectedBoardID = Pinboard.all.id
    }

    func remove(_ item: ClipboardItem) {
        guard canMutateHistory else { return }
        withHistoryStateMutation {
            let removedItems = items.filter { $0.id == item.id }
            guard !removedItems.isEmpty else { return }
            rememberDeleted(removedItems)
            clearSystemPasteboardIfMatching(removedItems)
            items.removeAll { $0.id == item.id }
            let removedIDs = removedItems.map(\.id)
            cleanupLinkPreviewWork(forRemovedItemIDs: removedIDs)
            discardPendingDurableMediaRelease(forRemovedItemIDs: removedIDs)
            refreshFilteredItems()
            saveItems()
        }
    }

    @discardableResult
    func clearHistory(includePinnedAndPinboardItems: Bool) -> Int {
        // The rejection precedes the invalidation below: a refused clear must
        // not revoke already admitted images, not even on an empty history.
        guard canMutateHistory else { return 0 }
        // Invalidation precedes the removable-items guard: clearing an empty or
        // fully protected history must still revoke already admitted images.
        invalidateImageCaptures()
        return withHistoryStateMutation {
            let removedItems = items.filter { item in
                includePinnedAndPinboardItems || (!item.isPinned && item.pinboardName == nil)
            }
            guard !removedItems.isEmpty else { return 0 }
            rememberDeleted(removedItems)
            clearSystemPasteboardIfMatching(removedItems)

            if includePinnedAndPinboardItems {
                items.removeAll()
            } else {
                items.removeAll { !$0.isPinned && $0.pinboardName == nil }
            }

            cleanupLinkPreviewWork(forRemovedItemIDs: removedItems.map(\.id))
            discardPendingDurableMediaRelease(forRemovedItemIDs: removedItems.map(\.id))
            refreshFilteredItems()
            saveItems()
            return removedItems.count
        }
    }

    /// Existing persistence entry point for a validated preview. All snapshot
    /// and metadata updates keep flowing through this path so history save
    /// coordination and media blob handling stay in one place.
    func applyLinkPreview(itemID: UUID, title: String?, linkImage: PreparedMedia?) {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        let previousLinkImageBlobID = items[index].linkImageBlobID
        items[index] = items[index].withLinkPreview(title: title, linkImage: linkImage)
        if items[index].linkImageBlobID != previousLinkImageBlobID {
            // A replaced identity invalidates the old role's proof; the item's
            // image role and a later commit for the new pair are unaffected.
            discardPendingDurableMediaRelease(itemID: itemID, droppingLinkImage: true)
        }
        refreshFilteredItems()
        saveItems()
    }
}

// MARK: - Clipboard polling and capture

extension ClipboardStore {
    func pollPasteboard() {
        // An explicit poll outside scheduled monitoring is still an admission
        // path, so the Quit pause closes it too.
        guard !isCaptureAdmissionPaused else { return }
        let now = uptimeProvider()
        let currentChangeCount = pasteboard.changeCount
        guard currentChangeCount != lastChangeCount else {
            pendingObservation = nil
            return
        }

        guard let pending = pendingObservation, pending.changeCount == currentChangeCount else {
            let firstObservedSource = sourceTracker.frontmostSourceSnapshot(
                pasteboardChangeCount: currentChangeCount
            )
            pendingObservation = PendingObservation(
                changeCount: currentChangeCount,
                firstObservedSource: firstObservedSource,
                firstObservedUptime: now
            )
            diagnostics.logPasteboardObserved(
                changeCount: currentChangeCount,
                source: firstObservedSource,
                uptime: now
            )
            extendBurst()
            return
        }

        guard now - pending.firstObservedUptime >= minimumStabilityInterval else { return }

        pendingObservation = nil
        let changeCountDelta = max(1, currentChangeCount - lastChangeCount)
        let firstObservedSource = pending.firstObservedSource
        guard let newItem = readCurrentPasteboard(
            changeCountDelta: changeCountDelta,
            currentChangeCount: currentChangeCount,
            firstObservedSource: firstObservedSource
        ) else {
            lastChangeCount = currentChangeCount
            extendBurst()
            return
        }
        lastChangeCount = currentChangeCount
        extendBurst()
        guard !ignoredApplications.contains(newItem.sourceApp) else { return }
        add(newItem)
    }

    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        timer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.pollTask?.cancel()
                self.pollTask = Task { @MainActor [weak self] in
                    guard !Task.isCancelled else { return }
                    self?.pollPasteboard()
                }
            }
        }
    }

    func stopMonitoring() {
        isMonitoring = false
        timer?.invalidate()
        timer = nil
        pollTask?.cancel()
        pollTask = nil
        cancelBurstScheduling()
        invalidateImageCaptures()
    }

    /// Closes new capture admission at the first normal-Quit request.
    ///
    /// Unlike `stopMonitoring` it does not revoke image eligibility: admitted
    /// captures keep their generation, waiting FIFO and physical slot, which is
    /// what makes the accepted-work set finite enough to drain. Only scheduled
    /// observation stops, so a continuing copier cannot extend the drain.
    func pauseCaptureAdmission() {
        guard !isCaptureAdmissionPaused else { return }
        wasMonitoringBeforeAdmissionPause = isMonitoring
        isCaptureAdmissionPaused = true
        isMonitoring = false
        timer?.invalidate()
        timer = nil
        pollTask?.cancel()
        pollTask = nil
        // Drops the pending observation and burst loop, never an image capture.
        cancelBurstScheduling()
    }

    /// Ends the pause after Cancel Quit, restoring only the scheduled activity
    /// that was active when it began. In-memory history and image eligibility
    /// are untouched throughout.
    func resumeCaptureAdmission() {
        guard isCaptureAdmissionPaused else { return }
        isCaptureAdmissionPaused = false
        let shouldResumeMonitoring = wasMonitoringBeforeAdmissionPause
        wasMonitoringBeforeAdmissionPause = false
        if shouldResumeMonitoring {
            startMonitoring()
        }
    }
    private var ignoredApplications: [String] {
        settings.ignoredApplications
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    func add(_ item: ClipboardItem) {
        guard historyRestoreState == .ready else {
            // Restoration owns insertion until the baseline exists: arrivals
            // are retained complete and in order — no insertion, no link
            // registration, no policy — then replayed through the same body.
            startupCaptureBuffer.append(item)
            isBootstrapDirty = true
            return
        }
        withHistoryStateMutation {
            applyAdd(item)
        }
    }

    /// The single insertion body shared by ordinary capture and startup replay,
    /// so policy, diagnostics, cleanup, filtering, selection and metadata
    /// registration cannot drift between them.
    func applyAdd(_ item: ClipboardItem) {
        let beforeCount = items.count
        let insertion = ClipboardHistoryPolicy.adding(item, to: items, limit: settings.historyLimit)
        items = insertion.items
        diagnostics.logInsertion(
            item: item,
            beforeCount: beforeCount,
            afterCount: items.count,
            duplicateSummary: insertion.duplicateSummary
        )
        cleanupLinkPreviewWork(forRemovedItemIDs: insertion.removedItemIDs)
        discardPendingDurableMediaRelease(forRemovedItemIDs: insertion.removedItemIDs)
        refreshFilteredItems()
        if let selectedItemID = insertion.selectedItemID {
            selectedID = selectedItemID
        }
        saveItems()
        registerLinkMetadataIfNeeded(for: insertion.insertedItem)
    }

    /// Applies the configured bounds to existing history after a settings-driven
    /// limit change. Enforcement always re-reads the normalized current setting,
    /// so rapid or pre-normalization publications can never trim by a stale
    /// value. A trim assigns the final array once, cleans up removed preview and
    /// durable-media work, and saves once; automatic eviction is never a user
    /// deletion and keeps image-encoding work alive.
    func enforceHistoryBounds() {
        let enforcement = ClipboardHistoryPolicy.enforcingLimits(on: items, limit: settings.historyLimit)
        historyBoundsEnforcedObserver?()
        guard !enforcement.removedItemIDs.isEmpty else { return }
        withHistoryStateMutation {
            items = enforcement.items
            cleanupLinkPreviewWork(forRemovedItemIDs: enforcement.removedItemIDs)
            discardPendingDurableMediaRelease(forRemovedItemIDs: enforcement.removedItemIDs)
            refreshFilteredItems()
            saveItems()
        }
    }

    private func readCurrentPasteboard(
        changeCountDelta: Int,
        currentChangeCount: Int,
        firstObservedSource: ClipboardSource?
    ) -> ClipboardItem? {
        guard settings.recordSensitiveContent || !pasteboardContainsSensitiveContent() else {
            return nil
        }

        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !urls.isEmpty {
            let fileURLs = urls.filter(\.isFileURL)
            if !fileURLs.isEmpty {
                let source = sourceMetadata(
                    kind: .file,
                    changeCountDelta: changeCountDelta,
                    currentChangeCount: currentChangeCount,
                    firstObservedSource: firstObservedSource
                )
                return makeFileItem(fileURLs: fileURLs, source: source)
            }
        }

        if let images = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
           let image = images.first {
            // Materialize before resolving: an entry that cannot produce a
            // CGImage must not consume shortcut-source evidence or emit a
            // capture diagnostic for a card that will never exist.
            guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                return nil
            }
            let source = sourceMetadata(
                kind: .image,
                isSystemGeneratedContent: pasteboardContainsSystemScreenshot(),
                changeCountDelta: changeCountDelta,
                currentChangeCount: currentChangeCount,
                firstObservedSource: firstObservedSource
            )
            // An ignored source is rejected before the image is buffered, so it
            // can never occupy a capture slot or launch encoding work.
            guard !ignoredApplications.contains(source.appName) else { return nil }
            admitImageCapture(
                cgImage: cgImage,
                displaySize: image.size,
                source: source,
                currentChangeCount: currentChangeCount
            )
            return nil
        }

        guard let string = pasteboard.string(forType: .string), !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        if let url = URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines)),
           let scheme = url.scheme?.lowercased(),
           ["http", "https"].contains(scheme) {
            let source = sourceMetadata(
                kind: .url,
                changeCountDelta: changeCountDelta,
                currentChangeCount: currentChangeCount,
                firstObservedSource: firstObservedSource
            )
            return makeURLItem(url: url, rawString: string, source: source)
        }

        let possibleFile = URL(fileURLWithPath: string)
        if FileManager.default.fileExists(atPath: possibleFile.path) {
            let source = sourceMetadata(
                kind: .file,
                changeCountDelta: changeCountDelta,
                currentChangeCount: currentChangeCount,
                firstObservedSource: firstObservedSource
            )
            return makeFileItem(fileURLs: [possibleFile], source: source)
        }

        let firstLine = string.components(separatedBy: .newlines).first ?? string
        let source = sourceMetadata(
            kind: .text,
            changeCountDelta: changeCountDelta,
            currentChangeCount: currentChangeCount,
            firstObservedSource: firstObservedSource
        )
        return makeTextItem(text: string, title: firstLine.truncated(to: 42), source: source)
    }

    private func makeFileItem(fileURLs: [URL], source: ClipboardSource) -> ClipboardItem {
        ClipboardItem(
            id: UUID(),
            kind: .file,
            title: fileURLs.count == 1 ? fileURLs[0].lastPathComponent : "\(fileURLs.count) files",
            preview: fileURLs.map(\.path).joined(separator: "\n"),
            sourceApp: source.appName,
            sourceAppIconData: source.iconData,
            sourceAppIconBlobID: source.iconBlobID,
            createdAt: Date(),
            isPinned: false,
            pinboardName: nil,
            textValue: nil,
            fileURLs: fileURLs,
            imageData: nil
        )
    }

    private func makeURLItem(url: URL, rawString: String, source: ClipboardSource) -> ClipboardItem {
        ClipboardItem(
            id: UUID(),
            kind: .url,
            title: url.host(percentEncoded: false) ?? rawString,
            preview: rawString,
            sourceApp: source.appName,
            sourceAppIconData: source.iconData,
            sourceAppIconBlobID: source.iconBlobID,
            createdAt: Date(),
            isPinned: false,
            pinboardName: nil,
            textValue: rawString,
            fileURLs: [],
            imageData: nil
        )
    }

    private func makeTextItem(text: String, title: String, source: ClipboardSource) -> ClipboardItem {
        ClipboardItem(
            id: UUID(),
            kind: .text,
            title: title,
            preview: text.truncated(to: 240),
            sourceApp: source.appName,
            sourceAppIconData: source.iconData,
            sourceAppIconBlobID: source.iconBlobID,
            createdAt: Date(),
            isPinned: false,
            pinboardName: nil,
            textValue: text,
            fileURLs: [],
            imageData: nil
        )
    }

    private func clearSystemPasteboardIfMatching(_ removedItems: [ClipboardItem]) {
        guard removedItems.contains(where: pasteboardMatches) else { return }
        pasteboard.clearContents()
        markPasteboardProcessed()
    }

    func markPasteboardProcessed() {
        lastChangeCount = pasteboard.changeCount
        pendingObservation = nil
        cancelBurstScheduling()
    }

    private func pasteboardContainsSystemScreenshot() -> Bool {
        pasteboard.types?.contains { type in
            type.rawValue.localizedCaseInsensitiveContains("screenshot")
        } ?? false
    }

    private func pasteboardContainsSensitiveContent() -> Bool {
        pasteboard.types?.contains { type in
            let rawValue = type.rawValue.localizedLowercase
            return rawValue.contains("concealed") ||
                rawValue.contains("1password") ||
                rawValue.contains("bitwarden") ||
                rawValue.contains("keychain") ||
                rawValue.contains("keepass") ||
                rawValue.contains("lastpass") ||
                rawValue.contains("dashlane")
        } ?? false
    }

}

// MARK: - Bounded burst polling, filtering and persistence

extension ClipboardStore {
    /// D5: start or extend the burst window only for meaningful activity
    /// (copy intent, a newly observed external count, or a processed stable count).
    /// Repeated signals never accumulate the deadline beyond one window from now (D3):
    /// the loop stays bounded and cannot become a permanent fast poller.
    private func extendBurst() {
        guard isMonitoring else { return }
        let now = uptimeProvider()
        burstDeadline = max(burstDeadline ?? now, now + burstWindow)
        startBurstLoopIfNeeded()
    }

    /// D3: at most one effective burst loop; repeated signals only extend its deadline.
    private func startBurstLoopIfNeeded() {
        guard burstTask == nil else { return }
        burstGeneration += 1
        let generation = burstGeneration
        burstTask = Task { @MainActor [weak self] in
            await self?.runBurstLoop(generation: generation)
        }
    }

    /// Polls immediately, then at the private burst interval while the deadline is active.
    /// Unstable ticks read only `pasteboard.changeCount`; the payload path runs once
    /// after stability inside `pollPasteboard()`.
    private func runBurstLoop(generation: Int) async {
        while !Task.isCancelled {
            guard burstGeneration == generation,
                  isMonitoring,
                  let deadline = burstDeadline else {
                return
            }
            guard uptimeProvider() < deadline else { break }

            pollPasteboard()

            guard burstGeneration == generation, isMonitoring else { return }
            do {
                try await Task.sleep(nanoseconds: UInt64(burstPollInterval * 1_000_000_000))
            } catch {
                return
            }
        }
        // Only the current generation may clear the active task reference (D3).
        if burstGeneration == generation {
            burstTask = nil
            burstDeadline = nil
        }
    }

    /// D7: self-writes and stop invalidate burst state, including the pending
    /// observation, and bump the generation so stale tasks cannot clear newer state.
    func cancelBurstScheduling() {
        burstGeneration += 1
        burstTask?.cancel()
        burstTask = nil
        burstDeadline = nil
        pendingObservation = nil
    }

    func refreshFilteredItems() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
        let board = Pinboard(id: selectedBoardID)
        filteredItems = items.filter { item in
            switch board.kind {
            case .all, .unknown:
                break
            case .pinned:
                guard item.isPinned else { return false }
            case .custom:
                guard item.pinboardName == board.customName else { return false }
            }
            return query.isEmpty || item.searchText.contains(query)
        }
        if let selectedID, filteredItems.contains(where: { $0.id == selectedID }) {
            reconcileLinkPreviewFallback()
            return
        }
        selectID(filteredItems.first?.id)
    }

    /// The single Store save entry point. Every production history write — the
    /// capture buffer, an actual baseline trim, a deferred metadata save, a
    /// link-preview update — converges here, so this is the whole persistence
    /// barrier.
    func saveItems() {
        guard historyRestoreState == .ready else {
            // Before baseline installation and replay finish, nothing may start
            // a save transaction, write a capture blob or a replacement
            // manifest, or be collected as garbage. The deferred request is
            // committed once, after all replay and final reconciliation.
            isBootstrapDirty = true
            return
        }
        persistItems(items)
    }

    private func selectID(_ id: UUID?) {
        guard selectedID != id else {
            // Explicitly selecting the current item still reevaluates cache and
            // retry state; only duplicate Published updates are suppressed.
            reconcileLinkPreviewFallback()
            return
        }
        selectedID = id
    }
}
