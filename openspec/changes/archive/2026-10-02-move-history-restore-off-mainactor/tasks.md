## 1. Restore worker boundary and deterministic seams

- [x] 1.1 Add structural Sendable conformances for ClipboardKind and ClipboardItem without unchecked conformance; verify `swift build` and existing model/media identity and Codable tests pass with unchanged V2 output.
- [x] 1.2 Add the narrow ClipboardHistoryLoading protocol and ClipboardHistoryRestoreWorker actor executing the throwing instance persistence load; verify a focused worker test uses the real persistence read hook outside the main thread and preserves thrown errors/backup behavior.
- [x] 1.3 Add a controllable loader with explicit started/release/completion gates and a snapshot/save recorder in focused `Tests/CopythatTests/ClipboardHistoryRestoreTests.swift`; verify success and failure gates terminate without sleeps, polling loops or wall-clock performance thresholds, and async cross-thread counters are synchronized.

## 2. In-memory construction and bootstrap ownership

- [x] 2.1 Remove synchronous persistence loading from ClipboardStore.init, make provided items purely in-memory, and preserve existing injected startup enforcement; verify construction without items does not read disk and existing history-limit/injected-item suites pass.
- [x] 2.2 Add explicit one-shot ready/restoring/applying state, read-only loading publication, a weak restore task and finishHistoryRestore await; verify loading is published before begin returns, duplicate begin cannot invoke the loader twice, ready finish returns immediately, and load failure always reaches ready.
- [x] 2.3 Wire AppModel's optional initialItems and injected/default loader after durable-media and copy-intent handlers are installed; verify production-style construction returns while the loader is gated, ordinary launch monitoring can start while loading, and explicit `[A, B]` or `[]` invokes the loader zero times.
- [x] 2.4 Preserve isolated verification startup and matching restore/save/media roots in integration fixtures; verify verification configuration never reads production history and injected persistence roots are shared by all three workers/consumers.

## 3. Arrival buffering, policy replay and persistence barrier

- [x] 3.1 Buffer full finalized ClipboardItems in add arrival order while restoring without formal insertion or eager link requests; verify gated adds preserve source/time/media identity and a blocked restore records zero persistence calls.
- [x] 3.2 Extract the single applyAdd body while keeping ordinary add's mutation wrapper and all existing policy, diagnostics, cleanup, filter/selection and metadata registration behavior; verify existing insertion, policy, preview and durable-release suites remain unchanged and bootstrap never nests the bool-based mutation wrapper.
- [x] 3.3 Add the saveItems barrier and dirty tracking for buffered capture, actual trim and legitimate deferred saves; verify save recorder stays zero before completion and no capture blob/manifest/GC write bypasses the barrier in production paths.
- [x] 3.4 Implement no-await baseline enforcement with current settings, sequential buffered replay, final filter/reconcile, ready publication and one final dirty snapshot; verify clean restore requests zero saves, trim alone requests one, capture alone requests one, and trim plus multiple captures still requests exactly one final bootstrap save.
- [x] 3.5 Add disk-level lost-update coverage with old `[A, C]` and gated new B; verify the old manifest and referenced blobs remain intact before loader release and the committed final snapshot equals policy-derived baseline plus B rather than either partial or overwritten history.
- [x] 3.6 Test duplicate replay against ClipboardHistoryPolicy results for unpinned duplicate, pinned duplicate, pinboard-assigned duplicate, pinned capacity exhaustion, configured limit and image bound; verify final items/selection and preserved IDs/source/time/assignments match policy rather than hand-written merge expectations.
- [x] 3.7 Test sequential A/B/C replay with deliberately contradictory createdAt values and mixed text/image completion order; verify Store arrival order determines replay and no global kind/timestamp scheduler or new duplicate rules appear.
- [x] 3.8 Apply failure through the same empty-baseline completion flow; verify capture A/B survives policy replay with one save, failure without mutation writes no replacement manifest, backup semantics remain intact, and no infinite loading state remains.
- [x] 3.9 Cover settings/query changes during the suspended loader; verify current normalized historyLimit wins, queued limit enforcement causes no redundant trim save, and current search/pinboard selection immediately filters final history.
- [x] 3.10 Cover visible-panel replay over a baseline URL and eager inserted-URL enrichment; verify no selection-driven request starts for a transient baseline selection, final reconcile uses completed history, and later metadata saves are tested independently from the bootstrap count.

## 4. Loading presentation and mutation protection

- [x] 4.1 Add minimal loading timeline/count presentation in BottomPanelView and SettingsView; verify controlled loading shows “Loading clipboard history…” rather than empty/search-zero claims, panel/menu/search/filter/privacy and unrelated settings remain usable, and completion restores existing cards/empty states.
- [x] 4.2 Guard Store clear, pin/unpin, remove, move and assignment mutation entry points before all side effects; verify direct calls during restoring/applying do not change history, system pasteboard, save count, image generation or waiting captures, particularly clear on otherwise empty history.
- [x] 4.3 Disable and guard whole BottomPanelView pinboard edit/delete confirmations before AppSettings mutation, plus Settings clear confirmations; verify rejected loading actions change neither pinboard settings nor assignments, stale callbacks cannot bypass readiness, and normal ready edit/delete/clear regressions pass.

## 5. Preserve the bounded image pipeline through restore

- [x] 5.1 Add controlled real-admission tests where image finalization completes during blocked restore; verify the item survives replay with admission source/icon/time and prepared media identity, is not re-encoded or re-hashed, and the startup buffer releases its ownership after application.
- [x] 5.2 Cover images completing after ready and capacity overflow during loading; verify post-ready images use ordinary saves, surviving images retain FIFO, maximum physical encoders stays one, raw capture depth stays at most four, and overflow/deletion/clear/stop-restart behavior remains covered by Change 12 regressions.

## 6. Quit admission pause, accepted-work drain and existing save resolution

- [x] 6.1 Add a focused Quit pause/resume boundary separate from stopMonitoring invalidation; verify timer/poll/burst/copy-wake/explicit-poll/raw-image-admission paths cannot admit new work during pause while active/waiting captures, generation and physical ownership remain intact, and Cancel Quit restores prior monitoring only.
- [x] 6.2 Add an awaitable drain for the existing admitted image pipeline without duplicating queue/payload state; verify active and waiting completion, nil finalization, rejected stale results and final physical-slot release all resolve/recheck waiters without encoder overlap or leaked continuation.
- [x] 6.3 Extend AppDelegate termination detection and resolution to pause admission, await restore, await accepted image work, then call existing SaveCoordinator.flush; verify no `.terminateNow` occurs with gated restore or eligible pending images even when hasUnsavedChanges is false, and successful reply follows merged committed history.
- [x] 6.4 Add gated Quit cases for restore-before-image, image-before-restore, multiple waiting images, and ready-with-pending-image; verify ordinary FIFO/eligibility, final persisted content and reply order in both completion orders without sleeps.
- [x] 6.5 Preserve Retry/Quit Anyway/Cancel Quit and repeated-Quit resolution after bootstrap/image drain; verify retry saves the latest state, Quit Anyway retains prior committed history, Cancel Quit retains in-memory captures and resumes prior monitoring/mutation eligibility, and repeated calls yield one resolution/reply with no second restore.
- [x] 6.6 Gate destructive Store and whole pinboard actions during the Quit pause; verify they cannot invalidate draining images or split settings from assignments, while ordinary ready actions return after Cancel Quit.

## 7. Production contracts and lifecycle verification

- [x] 7.1 Retain existing ClipboardHistoryPerformanceTests and add production-worker/bootstrap integration over 500 media-heavy V2 items; verify one restore manifest read, four deduplicated icon reads, zero heavy reads, absent heavy Data, retained IDs/content keys, schema version 2, and no persisted search corpus. Isolate save/GC counter windows from restore.
- [x] 7.2 Verify source-icon integrity and corpus counts across the real restore actor boundary; assert one corpus build per restored item, no rebuild during Store application/search and no redundant identity hashes, and review the caller chain to prove IO/decode/reference/icon/hash/model construction all occur inside worker isolation.
- [x] 7.3 Add Store-release and late-loader-completion tests, plus repeated finish/begin/error lifecycle coverage; verify weak Store becomes nil before release, late completion cannot publish/save, waiting clients complete appropriately, and no restore task holds Store strongly across loader await.
- [x] 7.4 Run focused restore, image-capture, termination, worker, policy, durable-release and performance suites; verify all pass and newly added race tests use explicit handled-transition gates rather than sleeps or guessed scheduling thresholds.

## 8. Adversarial review and complete acceptance

- [x] 8.1 Perform lost-update review across load-old/capture-new/completion/save permutations; verify every traced path preserves baseline and eligible startup arrivals through the existing policy, repair any discovered race and rerun its focused test.
- [x] 8.2 Perform persistence-race review of every saveItems, persistItems, requestSave, static save and GC caller; verify zero startup history-save writes before bootstrap completion and exactly one dirty bootstrap request with no production bypass, then rerun focused barrier/disk tests after any repair.
- [x] 8.3 Perform lifecycle review across restore/Quit, both image-completion orders, limit/query changes, load error, Cancel Quit, Store release and late completion; verify admission pause never calls invalidating stop behavior, duplicate resolution is safe, final reconcile sees completed state, and related regression tests pass after repairs.
- [x] 8.4 Run `swift build`, `swift test`, `./script/verify_all.sh` and `openspec validate move-history-restore-off-mainactor --strict` after the final implementation/test change; verify every gate passes, keep raw output only in `.build/verification/` or `/tmp/`, and report conclusions rather than committing run summaries.
- [x] 8.5 Manually verify production launch with persisted media-heavy history, panel/Settings loading and ready transitions, capture/search/pinboards/paste, Accessibility fallback, Quit/Retry/Cancel Quit and multi-display panel behavior; verify unchanged permissions and V2 compatibility, record any blocked required acceptance without marking it complete, and report remaining risks in the response.
