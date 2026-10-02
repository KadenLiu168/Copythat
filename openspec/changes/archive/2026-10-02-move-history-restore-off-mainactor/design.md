## Context

See `proposal.md` for motivation and scope. The production chain is `AppDelegate.init -> AppModel.init -> @MainActor ClipboardStore.init -> ClipboardHistoryPersistence.loadItems()`. V2 decoding validates all blob references, reads and verifies deduplicated source icons, and constructs ClipboardItems with normalized runtime search text. Heavy image/link-image blobs are already represented by IDs without loading. The instance persistence API throws and preserves corrupt input through the existing backup path; the static wrapper translates errors into an empty baseline.

Store insertion currently owns policy, diagnostics, removed-item preview/durable cleanup, filtering, selection, save requests, and eager URL metadata registration. All production Store save requests converge on `saveItems()`. `withHistoryStateMutation` suppresses reconcile using a non-nesting bool, then reconciles in its defer. Reusing nested wrappers would reconcile intermediate bootstrap state.

AppModel already installs a weak durable-media handler and copy-intent wake callback. The delegate starts source tracking and monitoring in `applicationDidFinishLaunching`. Termination only considers SaveCoordinator.hasUnsavedChanges; it cannot see loading history or admitted images that have not yet become items. `stopMonitoring()` revokes image insertion eligibility and discards waiting images, so it is not a safe Quit drain operation. Explicit `pollPasteboard()` remains usable outside scheduled monitoring and therefore also needs a Quit-admission guard.

Pinboard rename/delete are owned by BottomPanelView and mutate AppSettings before migrating Store assignments. SettingsView owns Clear Cards. The existing specs also contain an unrelated discrepancy: one older pinboard scenario says assignment pins an item, while panel behavior and implementation keep assignment independent of pinning. This change preserves actual existing policy and does not repair that unrelated contract.

## Goals / Non-Goals

**Goals:**

- Define one startup linearization point: install baseline plus replay in a synchronous MainActor turn, then permit saving.
- Preserve existing insertion side effects through a single implementation while suppressing intermediate reconcile and persistence.
- Define a finite normal-Quit admission boundary that drains accepted image work without changing physical encoder ownership or generation authorization.
- Prove real persistence work is off MainActor, separately from mock-loader coordination tests.

**Non-Goals:**

- MainActor policy enforcement, filtered-array construction, selection, and publication remain synchronous; this is not a whole-history processing optimization.
- RestoreState is startup-specific, not a general transaction or mutation journal. A separate narrow Quit-admission lifecycle must not be represented by extra restore states.
- No timeout that reports restore/image work complete while it still runs, and no generic worker registry or persistence-manager rewrite.

## Decisions

### 1. Narrow actor loader and structural Sendable items

Add `ClipboardHistoryLoading: Sendable` with `loadItems() async throws -> [ClipboardItem]` and an actor `ClipboardHistoryRestoreWorker` holding the injected ClipboardHistoryPersistence instance (default `.shared`). Its actor-isolated method directly executes the synchronous throwing instance load. File IO, JSON, validation, icon integrity hashing, legacy decoding/identity establishment, and item/search construction therefore run on the worker executor, not in a MainActor helper before an await.

Add structural `Sendable` to ClipboardKind and ClipboardItem. Stored fields are value types; computed NSImage accessors do not imply stored AppKit object transfer. Do not add `@unchecked Sendable` to Item or Store. Preserve the existing persistence seam rather than expanding its unchecked conformance or mutating its closures concurrently; async test readers/counters must be thread-safe.

Alternatives: a Task inheriting MainActor does not move synchronous work off it; detached loading scattered through Store obscures ownership; a combined save/load actor is unnecessary when the startup save barrier supplies ordering.

### 2. Pure-memory Store construction; AppModel owns production bootstrap

Make Store `initialItems: [ClipboardItem] = []` and remove its disk-load fallback. Retain in-memory startup enforcement and synchronous injected tests. AppModel keeps its optional initialItems distinction: non-nil means already supplied memory and never invokes the loader; nil means production empty Store plus async restore.

AppModel creates settings, sourceTracker, saveCoordinator and Store, installs durable-media and copy-intent handlers, then synchronously calls beginHistoryRestore before returning. That call publishes restoring immediately and schedules a weak completion task. Do not construct a loader by eagerly loading items in a default argument. Verification startup continues injecting `[]` and using isolated persistence/media loaders. Custom production-style tests inject matching restore/save/media persistence roots.

Alternatives: starting restore later in the delegate exposes a ready-but-incomplete window; waiting for restore before monitoring recreates the capture blind window; making every injected test asynchronous removes an existing useful seam.

### 3. One-shot restore state and full-item arrival buffer

Store owns `HistoryRestoreState` (`ready`, `restoring`, `applying`), read-only Published `isRestoringHistory`, a Task<Void, Never> completion handle, a one-shot begin guard, full `[ClipboardItem]` startupCaptureBuffer, and a bootstrap dirty marker. The one-shot guard must reject repeated begin even after the completed task handle is cleared. `finishHistoryRestore()` awaits the existing task; a never-restoring ready Store returns immediately.

During restoring, add appends the complete item and marks capture dirtiness without inserting into formal items or registering link metadata. Keep add arrival order, never sort by createdAt, IDs, or contentKey. Image completion continues its current generation/deletion checks before calling add, carrying finalized bytes/address and admission-time source context. Encoding that completes after restore uses ordinary ready insertion; it is not part of the already-finished bootstrap save.

The task copies the loader and holds only a weak Store across await, resolving it after success/failure. Avoid `guard let self` before loading. Late completion after Store release cannot apply. No independent task cancellation is necessary for safety: synchronous IO need not be forcibly interruptible, and authorization/lifetime checks remain decisive.

Alternatives: assigning restored items over live items loses updates; reparsing pasteboard after restore loses overwritten captures and their source context; a Set merge changes duplicate metadata and pinned behavior.

### 4. Policy replay is one outer mutation with one persistence barrier

Extract applyAdd as the shared insertion body, not another wrapper. Ordinary add wraps it with withHistoryStateMutation; bootstrap uses exactly one outer wrapper for baseline installation and replay. Keep policy, diagnostics, removed-preview/durable cleanup, filtering/selection, and metadata registration in that one body. Do not nest the existing bool-based wrapper. Selection-driven reconcile runs only after final replay, never against transient selected baseline URLs. Eager registration for retained incoming URLs uses existing eligibility and late-result validation.

Completion performs, without await:

1. Set state applying; re-read the current normalized settings.historyLimit.
2. Enforce persisted baseline with ClipboardHistoryPolicy.enforcingLimits; baseline trim marks dirty. Install retained items and reconcile current filter/selection under the outer mutation.
3. Take and clear the startup buffer; replay each item through applyAdd in original order with current settings.
4. Complete final filtering and outer-wrapper reconcile while still applying.
5. Transition to ready and publish isRestoringHistory=false; if dirty, request one final snapshot through the ordinary save entry point.

Every saveItems call when not ready records dirtiness but does not call persistItems. applyAdd can retain its existing saveItems call; avoid a second requestPersistence flag unless required by a demonstrated contract. Dirty means any buffered add, actual baseline trim, or legitimate deferred save request, even when policy ultimately discards an incoming item. Clean baseline loading/filtering alone is not dirty.

The barrier covers all Store save paths, including link-preview helpers. Production should not bypass it through direct requestSave/static persistence calls. Normal corrupt-input backup remains permitted outside the manifest-save barrier. SaveCoordinator drain/GC can begin only after restore has released its disk baseline.

“At most one bootstrap save” counts the final request attributable to baseline/arrival replay, not every future manifest write. Metadata completion, post-restore image completion, new copies and retries remain independent normal saves. Tests gate these events rather than demanding the impossible absence of later saves.

Alternatives: per-add flags alone miss trim/preview/other save paths; SaveCoordinator coalescing alone can already commit partial history; a custom merge duplicates policy; moving policy/filtering into the restore actor uses stale settings and transfers UI ownership.

### 5. Failure is an empty baseline, not discarded capture or a save trigger

Catch loader errors in the completion task and enter the same applying pipeline with `[]`. Production worker preserves existing persistence backup/error semantics. Error alone creates no save request, but buffered capture still replays and saves once. Ready must be reached on error. Do not add raw-content diagnostics or overwrite corrupt input merely to clear loading.

Alternatives: leaving restoring on error disables history forever; replacing buffer with empty result loses new copies; unconditional empty save destroys useful prior evidence.

### 6. Loading UI and mutation guards cover whole actions

BottomPanel timeline prioritizes restoring over empty/search/pinboard copy and shows minimal “Loading clipboard history…” content. Search, filters, panel opening, privacy controls, safe new-board creation, status menu and unrelated settings remain usable. On completion reapply the current query/filter without needing user input. Counts shown while loading must be identified as loading rather than an authoritative zero.

Disable clear/pin/unpin/remove/move and pinboard edit/delete while loading. Store mutation entry points must reject before any side effect, especially before clearHistory invalidates captures. Do not queue destructive intent for replay. Whole pinboard confirmation actions must check readiness before modifying settings, then perform existing settings and history operations in the same synchronous action. UI disabled state is not the sole guard; stale confirmation callbacks also check readiness. The simplest policy disables the whole existing edit form, including color-only edits, rather than introducing a new special-case transaction.

History limit remains editable; completion uses its current value. Deferred history-limit tasks re-read current settings and cannot introduce a second save for an already-enforced limit. No restore-time journal for temporary settings values is introduced.

Alternatives: guarded Store methods alone let settings rename succeed with unmigrated assignments; disabled buttons alone miss direct callers/stale confirmations; silent deferred no-ops restore obsolete assignments.

### 7. Quit pauses admission without invalidation and drains existing work

This confirmed guarantee applies to normal Quit during bootstrap and after readiness: accepted eligible images must not disappear just because they have not reached add. Eligibility still follows existing overflow, generation, deletion and retention rules; invalidated physical work has no new retention entitlement.

At the first Quit request, close new Store capture admission synchronously. Suspend scheduled timer/poll/burst observation and reject copy wakes, explicit polls and raw image admission during this pause, without calling stopMonitoring's image invalidation. Preserve active slot, waiting FIFO, generation and completion wrappers. Track whether monitoring was active so Cancel Quit restores only prior scheduled activity. Direct external test injection through add is not a new pasteboard admission, and save coordination still handles any resulting new generation.

Return terminateLater if restore, eligible pending images, or requested save work require resolution, and check duplicate termination resolution before the fast path. The delegate waits for finishHistoryRestore, then a focused existing-image-pipeline drain await, then SaveCoordinator.flush. Either restore/image completion order is safe: images finalized while restoring enter the buffer; images finalized afterwards use ordinary insertion. A nil encoder result, stale completion, and final waiting completion must all wake/recheck drain waiters. Never release the physical slot early or instantiate another queue. Waiters contain continuation/control state only, not duplicated image payloads.

The pause makes the accepted-work set finite, so a continuing copier cannot extend the drain indefinitely. Guard destructive history/whole pinboard actions during the termination pause as well, so drain itself does not trigger image invalidation. Optional URL network enrichment is not added to the awaited capture set; the coordinator continues flushing any saves actually requested before final resolution.

On successful flush reply true; failure uses the existing Retry/Quit Anyway/Cancel Quit flow. Retry targets latest coordinator state. Cancel Quit clears termination pause, restores prior monitoring and keeps current in-memory history, restoring normal mutation eligibility once history is ready. Values copied while admission is paused have no per-copy retention promise; restarting observation can discover the current external pasteboard using existing stability behavior. No new unconditional lastChangeCount reset should hide it. Repeated Quit attempts and Cancel Quit must not create duplicate waiters/replies or restart restore.

Alternatives: restore-only waiting misses admitted images; stopMonitoring discards accepted work; continuing admission makes drain unbounded; waiting for all network tasks adds unrelated termination latency; a second quit persistence path loses existing reliable retry behavior.

## Risks / Trade-offs

- [Slow restore accumulates completed capture bytes] -> The four-capture image bound covers raw outstanding encoding, not finalized startup items. Preserve full arrival replay with no extra cap/drop/dedup/spill in this change; clear buffer ownership after replay and use normal durable release after commit. Do not claim a total startup byte bound. Any stricter resource policy needs explicit approval and compatibility tests.
- [Long restore or pathological physical encoding delays normal Quit] -> Await real completion without fabricated timeout/slot release. Existing worker operations are expected to terminate, not hard-deadline guaranteed; keep MainActor free. A cancel-during-pre-flush or hung-worker recovery UI would require a separate approved contract.
- [No await is mistaken for no reentrancy] -> Published/Combine delivery can be synchronous. Keep admission paths state-aware and destructive entry points guarded through applying; completion must not call extensible callbacks that can mutate half-installed state. Verify wrapper nesting and final reconcile order.
- [Clean restore starts legitimate preview work on an already-visible panel] -> Baseline installation itself requests zero saves; a later valid enrichment is an independent mutation. Test clean-save counts with controlled previews/panel state.
- [Different persistence instances name different roots] -> Inject matching loader/save/media roots in integration tests and preserve isolated verification; worker actor confinement does not itself serialize unrelated writers.
- [Mock-loader tests hide real MainActor IO] -> Use the production worker with synchronized read hooks proving reads are not on the main thread, plus caller-chain review for decode/hash/model construction and existing hash/corpus counters.
- [Large buffer replay still takes MainActor time] -> Policy and filter work remain in scope as synchronous final application, without claiming unlimited-capture responsiveness. Profile separately before any algorithm/scheduler expansion.

## Migration Plan

No V2 migration or new permission is required. Add the worker boundary and structural Sendable first, then pure-memory construction, bootstrap barrier/replay, UI guards, and Quit pause/drain integration. Add gated tests alongside each step, preserve existing lazy-media/performance coverage, and run the complete project gates after the final implementation change.

Before release, perform distinct lost-update, persistence-bypass and lifecycle reviews. Rollback is a focused code revert; the unchanged V2 manifest and media layout remain readable. Rollback restores synchronous startup and the older Quit-image limitation, so it is not equivalent to keeping the new lifecycle guarantee.
