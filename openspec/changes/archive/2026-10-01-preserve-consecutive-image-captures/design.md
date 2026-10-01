## Context

See `proposal.md` for motivation and `specs/clipboard-history/spec.md` for the behavior contract. This change needs a design because it affects pasteboard admission, source context, asynchronous lifecycle ownership and resource bounds.

`ClipboardStore` is MainActor-owned. Its current `enqueueImageItem()` creates detached PNG/hash work for each image, cancels the previous completion wrapper, and inserts through `add()`. The detached task explicitly receives `MediaHashObservation.recorder`; cancelling the wrapper cannot forcibly stop synchronous CoreGraphics/ImageIO work. Source metadata is already resolved before encoding, but image creation time is currently assigned at completion.

`remove()` cancels all pending image work regardless of content. `clearHistory()` cancels only after a non-empty removable-items guard. The image path returns nil from pasteboard parsing before the outer ignored-app guard executes. `deletedContentKeys` is a content-only, 256-entry tombstone list: it rejects intentional same-image recopy through the real completion path, and arbitrary eviction can lose stale-result protection. Existing deletion tests partly exercise direct `add()` or predicate calls rather than pending encoder races.

Existing specs already promise ignored-source exclusion and recording an intentional recopy after deletion. The earlier capture-responsiveness design explicitly deferred consecutive-image preservation. This change addresses those image-path gaps without changing the observation scheduler. The existing responsive-capture wording is not a reason to introduce a cross-kind ordering scheduler here.

## Goals / Non-Goals

**Goals:**

- Separate result authorization from ownership of physical encoding work, including across clear and stop/restart.
- Establish invariants that controlled tests can prove without timing-dependent sleeps: one physical capture encoder, four buffered captures, FIFO among surviving images, matching-only deletion suppression, and exactly-once terminal handling.
- Preserve immutable admission context and prepared media identities through the existing insertion/save path.

**Non-Goals:**

- No general queue/actor subsystem or configurable queue UI. Use small image-specific Store state; extract a focused support file only if it demonstrably reduces lifecycle complexity.
- No attempt to forcibly terminate synchronous PNG work, no timeout that releases its slot while it still runs, and no larger production capacity without profiling evidence.
- No timestamp-based global history sorting. In a mixed image/text sequence, a delayed earlier image can still be inserted ahead of a later synchronous text item.
- No deletion-time pasteboard-matching optimization. Its existing MainActor normalization/hash path is outside the capture-finalization guarantee.

## Decisions

### 1. MainActor owns admission, queue transitions and completion authorization

Use a focused `PendingImageCapture` containing request identity, monotonically increasing admission sequence, generation, pasteboard change count, capture timestamp, original display size, immutable CGImage, resolved `ClipboardSource`, and the observation recorder captured for that request. Sequence remains monotonic across generation changes.

Store state comprises the waiting FIFO, optional physical active request, generation, next sequence and internal capacity. Image-specific transitions live in `Sources/Copythat/Stores/ClipboardStore+ImageCapture.swift`, sharing the Store's MainActor state through the existing same-module extension pattern. The runtime retains the completion waiter; no task handle is needed because physical ownership and authorization are represented by the active request and generation, not cancellation. Production capacity is four, including one active and at most three waiting; tests inject two. The capacity seam need not support one or zero.

Admission remains behind existing sensitive-content and stability gates. Materialize the CGImage, snapshot time/size/change count and resolve source using the existing attribution API, reject ignored source names using the current parsing semantics, then assign sequence and admit. No detached task is launched for an ignored or merely waiting image. Admission-time ignored filtering does not introduce a new completion-time source resolution or Settings interpretation.

All queue mutations are synchronous MainActor transitions. Evict the oldest waiting request before appending when full, so retained raw captures do not momentarily exceed capacity. Incoming pasteboard materialization can transiently exist before admission; the count bound describes pipeline-owned buffered captures, not a total-process byte ceiling.

**Alternatives:** A generic queue/actor adds ownership boundaries without solving a shared need. Latest-only cancellation loses accepted captures. Multiple workers complicate ordering and cause CPU/memory fan-out.

### 2. The physical slot survives logical invalidation

Only the idle-to-active transition may launch the default encoder. It uses `Task.detached(priority: .utility)` and the existing `pngData(cgImage:maxPixel: 1_200)` followed by `PreparedMedia(hashing:)`. Propagate each request's recorder explicitly; a long-lived worker must not reuse the recorder from its first request for later captures.

Generation changes revoke insertion eligibility, not physical occupancy. Clear/stop drops waiting requests immediately, but a started encoder and its completion owner remain until the actual operation ends. Do not set the physical active state/task to nil merely because a wrapper was cancelled. Prefer retaining the completion waiter through logical invalidation; task cancellation is not the authorization mechanism.

```text
active A [g1] --> clear/stop --> A invalid, slot still occupied
                                      |
new B [g2] admitted ----------------> waiting B
                                      |
A physically finishes --> reject A --> release A-owned slot
                                      |
                                      v
                                 start B [g2]
```

A terminal callback first verifies physical request ownership. It may release only that request's slot, even if its generation is stale. Result application separately requires current generation, valid prepared media and deletion authorization. It then schedules the next currently eligible waiting request. A stale callback never unconditionally clears worker state or authorizes an old result. Success, nil encoding and invalidated completion all drain the slot exactly once.

Do not hold a strong Store reference across the background await. The task can carry immutable request/encoder context and resolve a weak Store only for short MainActor transitions. Store release cannot leave a task/Store retain cycle; a detached synchronous operation may still finish, but cannot update a released Store.

**Alternatives:** Cancelling and forgetting the wrapper allows new detached work to overlap old CPU work. A generation-only guard prevents stale insertion but not physical overlap. Serializing only within each generation has the same flaw.

### 3. Overflow discards waiting work, never active work

At capacity, preserve the physical active capture even if its result was invalidated, remove the oldest waiting capture, and append the newest eligible capture. Survivors retain FIFO order. With test capacity two: active A, waiting B, new C becomes active A, waiting C. Overflow cleanup releases the discarded request's raw image, source snapshot and recorder ownership.

Emit exactly one `image_encoding_overflow` event for each discarded waiting request when diagnostics are enabled. Identify the discarded sequence/change count and define `queueDepth` as total active-plus-waiting depth after replacement. The active slot is not reclaimed to make room.

**Alternatives:** Drop-newest preserves older waits but is less useful for clipboard recency. Cancel-active wastes spent CPU and cannot safely free the physical slot. An unlimited queue retains unlimited original CGImages.

### 4. Preserve admission context and finalization identities

Construct the image item only after authorized finalization, using the request's `capturedAt`, display size, source name, icon bytes and icon blob ID. A new item uses that timestamp; an existing unpinned duplicate still retains its original creation time and source metadata through `ClipboardHistoryPolicy`.

Pass finalized image bytes and blob ID together. Route valid results through the unique `add()` entry point; do not introduce a special persistence path, second content hash, insertion-time PNG conversion or storage optimization pass. Source icon preparation stays owned by source tracking.

**Alternatives:** Completion-time foreground resolution attributes queue latency to another app. Completion-time timestamps misrepresent capture time. Sorting all history by timestamps changes duplicate/retention semantics and is outside scope.

### 5. Deletion authority includes content and admission time

Replace content-only completion authorization with matching content plus deletion sequence cutoff. At actual card deletion, associate each removed content key with the highest image admission sequence so far. Reject a completion when its matching cutoff is greater than or equal to its sequence; accept a newer intentional admission subject to all other guards. Repeated deletion keeps the greatest cutoff for a key.

```text
old A admitted seq 10
remove A --> matching cutoff 10
new A admitted seq 11
old completion 10 --> reject
new completion 11 --> ordinary add
```

`remove()` no longer invalidates the image pipeline. Keep matching system-pasteboard clearing and use resident or unloaded content keys without reading history blobs. Automatic retention eviction still creates no manual-deletion suppression.

Do not allow the old 256-entry FIFO policy to evict deletion authority needed by an outstanding request. Retain cutoff records over the outstanding admission window, then prune records once no outstanding request can be rejected by them; newer requests do not need older cutoffs. Any retained compatibility/recency tombstone bookkeeping is not the final async authorization authority. Cleanup after recording a deletion, on completion, overflow and lifecycle discard must release no-longer-needed cutoff protection. Deletion with no outstanding image capture retains no cutoff records. These records contain identities and sequences only, never clipboard bytes; their transient size follows deletions during outstanding work, rather than an unconditional 256-record cap that weakens correctness.

Update narrow predicate/testing helpers to carry temporal context rather than preserving an incorrect content-only contract. A direct `add()` test is not evidence that actual same-image recopy works.

**Alternatives:** Permanent tombstones reject legitimate recopy. Clearing a tombstone on a new copy also authorizes the old completion. Global cancellation suppresses unrelated content. Fixed-cap eviction alone loses necessary protection.

### 6. Clear and stop invalidate before any history no-op return

Every confirmed clear increments generation and discards waiting images before checking whether existing cards can be removed. Active work remains physically occupied but unauthorized. Existing pinned/pinboard retention and actual-card cleanup remain unchanged. Save only if stored cards changed; old completions cannot request an extra save. Newly admitted captures use the new generation and wait for any old physical work.

`stopMonitoring()` likewise invalidates the image generation and drops waiting captures, while retaining the existing timer/poll/burst invalidation behavior. Restart does not erase the old physical slot. Do not add an `isMonitoring` guard that breaks existing explicit stable-poll capture callers and tests; stopping scheduled monitoring and invalidating already admitted work is distinct from changing the contract of explicit `pollPasteboard()`.

**Alternatives:** Keeping the existing early return lets pending images reappear after clearing an empty history or a history with only protected cards. Clearing the active slot violates single-encoder ownership.

### 7. Narrow deterministic test seam and payload-free diagnostics

Inject an internal image encoder with the production default above. Tests hold and release individual requests, report started/finished checkpoints and await MainActor completion-handled checkpoints even when results are rejected. Combine this with existing virtual uptime/stability polling and injected persistence counting. Negative assertions follow a handled transition, not a sleep or arbitrary yield.

Exercise the real admission path in regressions, not just direct `add()` calls. The real production encoder also needs independent hash/background checks: mocked encoder tests cannot prove MainActor exclusion or real finalization behavior.

Extend `ClipboardDiagnostics` with a focused event/sink for testable overflow. Additional pipeline events are optional, not a requirement to build a tracing framework. Allowed fields are sequence, pasteboard change count, queue depth, source app, uptime and reason. Pipeline events contain no content hash or clipboard payload. Existing insertion diagnostic semantics remain unchanged. All emission continues behind the default-off flag.

**Alternatives:** Sleeps are scheduler-dependent and can assert before late completion is handled. A production scheduler framework is unnecessary for a single encoder seam. Hashes in pipeline logs are not needed to prove queue behavior.

## Risks / Trade-offs

- [Four original images can still be large] -> This is a capture-count bound, not a fixed byte budget. Keep production capacity four and PNG output bounded to 1200px; do not claim raw images are downsampled before buffering or increase capacity without profiling.
- [Invalidated PNG work delays a fresh capture] -> Accept the wait to preserve one physical encoder; never trade correctness for premature slot release. A pathological synchronous encoder has no new timeout/recovery guarantee in this change.
- [No-op clear strengthens existing behavior] -> Explicit scenarios cover empty history and protected-only history, with no unnecessary save.
- [Deletion bookkeeping outlives a recopy or evicts too early] -> Sequence cutoffs, outstanding-window pruning and churn tests preserve old-result suppression without permanent exclusion. Only transient identity metadata is retained.
- [Mixed-kind insertion can differ from capture-time order] -> Keep this known boundary explicit; do not silently sort history or change the policy.
- [Weak capture still becomes strong across await] -> Review closure capture lists and Store-release tests, not just success-path tests.
- [Green mocks hide production hashing/actor regressions] -> Run real-encoder media observation coverage and existing metadata-save performance tests separately.

## Migration Plan

No persisted migration, settings migration or new permission is needed. Implement seam/regressions first, then FIFO admission/finalization, deletion and lifecycle ownership, ignored-source filtering, and the remaining deterministic tests. Verify focused suites, full regression and three adversarial review passes before release. Rollback is a code revert with existing V2 history remaining readable; rollback would restore the documented capture limitations.
