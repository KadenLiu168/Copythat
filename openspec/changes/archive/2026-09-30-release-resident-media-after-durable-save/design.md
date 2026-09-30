## Context

See `proposal.md` for motivation and `specs/clipboard-history/spec.md` for the behavior contract. The existing capture and preview paths attach finalized bytes and stable addresses to `ClipboardItem`. V2 restore already produces reference-only heavy media, while source icons remain eager. `ClipboardHistoryMediaLoader` owns the shared 32 MiB byte-cost LRU used by card display, paste, and drag.

`ClipboardHistorySaveCoordinator` serializes one active save and one latest pending request. Its `latestItems` snapshot currently survives success. `ClipboardStore.items` and `filteredItems` independently retain value copies of media-bearing items. Clearing one owner does not clear the others.

`worker.save()` completes after the existing persistence transaction writes absent blobs and atomically replaces the manifest. Existing blob files are trusted during saves and verified on actual reads. This change uses that success boundary without altering its integrity or crash guarantees.

## Goals / Non-Goals

**Goals:**

- Transfer long-lived heavy-media residency from history snapshots to the existing bounded loader after successful commit.
- Keep generation ordering and per-item, per-role identity checks explicit across actor suspension points.
- Make flush wait for commit handling without requiring the panel to close.
- Make correctness observable through retained bytes, retry state, reads, hashes, and save counts rather than RSS.

**Non-Goals:**

- No new media manager, scheduler, event bus, disk metadata, or generic subscription lifecycle.
- No release of `sourceAppIconData`, no callback persistence, and no transformation of pending unsaved snapshots to reduce memory early.
- No promise that all committed media fits in the cache or that external consumers release their own Data/NSImage copies immediately.

## Decisions

### 1. Coordinator emits a scoped receipt after success

Define a small internal Sendable `ClipboardHistoryDurableMediaCommit` alongside the coordinator. It contains the committed generation and item entries consisting of UUID plus optional prepared image and link image. Include only roles with resident bytes in that committed request; exclude metadata and source icons. Construct each payload with `PreparedMedia(data:id:)`, forwarding the existing non-nil identity without hashing, comparing Data, decoding, or encoding. A missing identity must never be synthesized here; the existing persistence validation rejects resident bytes without identity before success.

Install a single nonthrowing `@MainActor (ClipboardHistoryDurableMediaCommit) async -> Void` handler. The drain sequence is:

1. Await `worker.save(request.items, generation:)`.
2. Advance `committedGeneration` and clear the failed-generation marker on success.
3. Clear `latestItems` only if `request.generation == nextGeneration` at this point.
4. Build the receipt from the successful request and await the handler.
5. Recheck `pendingRequest` after the callback; perform existing GC only when no pending request exists.
6. Continue draining the latest pending request.

Failure emits no receipt and keeps the latest retry snapshot. An older success cannot clear newer retry state. Receipt and successful request bytes are scoped to processing that request; do not retain receipts in coordinator properties or detached callback tasks. Add a read-only internal semantic accessor such as `hasRetainedRetrySnapshot` for deterministic ownership tests.

Direct callback matches the one-to-one owner relationship. NotificationCenter adds unnecessary lifecycle and ordering concerns; a timer or blob-existence check cannot prove manifest commit.

### 2. Awaited handling preserves flush semantics

Keep `drainTask` active through handler completion so `flush()` waits for seeding and the release-or-defer decision. `hasUnsavedChanges` can become false before handling completes; it must not replace the existing drain-task check in flush. The callback does not call flush, retry, or save, which would create self-waiting or persistence loops.

Do not wait inside the handler for panel closure. Visible-panel handling records references and returns, so normal Quit remains bounded by existing save/loader work rather than user interaction. New requests arriving during seeding stay pending and are processed in generation order after the handler returns.

### 3. Seed the existing loader cache

Add `seedCommitted` to `ClipboardHistoryMediaLoader`, taking prepared media and using its existing insertion, recency, and byte-cost accounting. This actor method needs no disk IO or suspension internally. It must not hash, read, decode, or encode bytes. Repeated identities occupy one cache entry; individually oversized media are skipped without evicting useful entries merely to attempt an impossible insertion.

Offer snapshot media oldest-to-newest so the newest history entries are seeded last and remain most recent when a batch exceeds the budget. Use the committed history order rather than introducing a second ordering structure. Both media roles use the same cache and budget. Cache hits are guaranteed only while an identity remains retained; oversized or evicted payloads remain releasable because the save transaction succeeded.

Trusted seeding extends the existing cache admission contract beyond verified disk loads. Read-time SHA256 verification remains unchanged on misses; cache admission relies on finalized identity forwarding and successful commit, not another verification pass.

### 4. Reference-only item transformation is narrowly scoped

Add `ClipboardItem.releasingResidentMedia(durableImageBlobID:durableLinkImageBlobID:)`. For each role independently, remove Data only when a supplied non-nil durable ID equals the current blob ID and resident bytes exist. Preserve every other field: UUID, kind, title, preview, source app, source icon bytes/address, timestamp, pin state, pinboard, text, file URLs, image address, link title, and link image address.

Use known IDs when reconstructing the item to avoid initializer hashing. No full-item equality comparison is needed to discover a change; explicit per-role match flags suffice. Test `contentKey`, `searchText`, both payload-presence properties, and all metadata. This helper keeps field copying out of Store orchestration.

### 5. Store owns deferred release by references only

`handleDurableMediaCommit` first awaits loader seeding. After the await it rechecks current Store state, merges only still-matching resident roles into `pendingDurableMediaRelease: [UUID: DurableMediaReferences]`, and decides whether to release based on current `panelVisible`. The pending structure contains only IDs, never Data, prepared media, snapshots, or closures capturing them. Merge image and link-image roles independently so an absent role in a receipt does not overwrite the other role's valid pending reference.

When hidden, immediately consume pending references. When visible, keep resident Store bytes until `panelDidClose()`. After visibility is revoked and `panelAuthorizationGeneration` advances, consume pending references before existing preview reconciliation. This is a synchronous ownership boundary: the current controller calls `panelDidClose()` before `orderOut(nil)`, so the design does not assume the window is already physically hidden. Preserve that call order and verify visual behavior through the actual close/reopen path.

Release maps `items` and `filteredItems` separately with the same UUID/role-ID checks, then assigns each changed array once. No match means no publication. Do not call `refreshFilteredItems()`, reconcile selection, trigger preview fetching, or call `saveItems()` from this transform. Consume pending entries even when identities no longer match; future commits establish new eligibility. Prune removed/evicted items and stale role references through the existing removal lifecycle or a focused pruning hook so an indefinitely open panel cannot accumulate obsolete IDs.

Rechecking after seeding handles deletion, replacement, and close/reopen during actor suspension. Pending entries store proof for specific identities, never blanket permission to clear an item. No generation check substitutes for UUID plus blob ID; unchanged identities remain eligible even when metadata has advanced.

### 6. AppModel installs production wiring

After Store construction, `AppModel` registers the coordinator handler with a weak Store capture and awaits Store handling directly. Reuse the loader injected into that Store so persistence, cache, display, paste, and drag share the same blob store. Set up the callback before normal capture begins. Standalone coordinator tests may omit the handler; latest-snapshot cleanup must still occur.

No worker-to-Store reference is introduced. Add an integration test exercising AppModel wiring, since existing tests that manually construct Store plus coordinator do not install a callback automatically. Keep the existing resident metadata-save acceptance fixtures meaningful rather than silently converting all of them into reference-only fixtures.

## Risks / Trade-offs

- **External corruption of an existing blob:** Existing saves trust its presence and do not repair it. A successful transaction is not fresh disk-integrity verification; seeded valid bytes can later be evicted and a corrupt disk read will fail locally under the existing contract. Do not claim corruption recovery or strengthen durability by adding forbidden reads/hashes.
- **Visible panel retains media longer:** This deliberately trades immediate release for preview stability. Pending state has only references, and panel close releases matching history ownership.
- **Transient snapshot ownership:** In-flight requests, pending/failed saves, callbacks, and active consumers can temporarily retain bytes. Validate eventual owner cleanup after drain, not immediate RSS reduction at `committedGeneration` advancement.
- **Large seeded batches:** The cache may evict older entries before the callback returns. Test budget and recency separately from zero-read reuse of a retained entry; never enlarge the budget to satisfy a cache-hit test.
- **MainActor reentrancy:** Seed suspension permits mutations and visibility changes. Use controlled continuations to prove post-await checks, and do not let stale receipt processing mutate newer media.
- **Published value copies and retained Views:** Transform both Store arrays with at most one assignment each, preserve existing media task identity and visibility gating, and test rendered close/reopen behavior. The contract concerns history/coordinator ownership, not all AppKit allocations or the bounded browser snapshot cache.

## Migration Plan

No storage migration or backfill is needed. Restored reference-only V2 items continue unchanged; legacy inline media become eligible after a normal successful V2 save. Roll out the internal helpers, callback, Store handling, and AppModel wiring together with their tests. Rollback restores previous residency behavior while all committed V2 data remains readable. Do not alter persistent user history to validate either direction.
