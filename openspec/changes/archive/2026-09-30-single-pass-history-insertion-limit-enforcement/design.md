## Context

See `proposal.md` for motivation and `specs/clipboard-history/spec.md` for behavior. `ClipboardStore.add` currently builds ID sets before and after insertion, calls a separate diagnostics duplicate scan, and delegates to a policy that repeatedly scans history during eviction. `AppSettings.historyLimit` is normalized in `didSet`, and `ClipboardStore` does not observe it. `refreshFilteredItems` repairs selection, while `withHistoryStateMutation` defers link-preview reconciliation until the final state. The same removal cleanup already serves explicit deletion and insertion-time eviction, but user-deletion pasteboard and recapture suppression must not run for automatic eviction.

## Goals / Non-Goals

**Goals:**
- Make insertion and existing-history enforcement O(n) in source history size, including large reductions; publish one final history array and request at most one save per actual trim.
- Produce duplicate diagnostics, retained insertion/selection, and IDs of removed *existing* items from the policy decision without a Store-level before/after ID diff.
- Retain current pinned precedence, first unpinned duplicate identity/metadata, stable duplicate diagnostics ordering, newest-first image cap, and preview/durable-media cleanup.

**Non-Goals:**
- A literal one-loop implementation, persistent indexing, changed history/pinboard semantics, altered media or save format, or wall-clock CI thresholds.

## Decisions

### One policy result owns classification and removal facts

`ClipboardHistoryPolicy.adding` returns final items, a duplicate summary (matching original IDs in history order and pinned count), IDs of removed original items, an optional preferred selected ID, and an optional retained newly inserted item. A separate `enforcingLimits(on:limit:)` returns final items and removed original IDs; it shares the same retention logic without duplicate classification. Compute the incoming content key once for classification; select the first unpinned matching entry and move that *existing value* to the logical head. Leave any other pre-existing matching ordinary entries alone: the current policy does not clean them up in this branch. With no unpinned match, place the incoming item at the head and keep pinned matches untouched. Distinguish a newly discarded head from a removed original ID. Do not expose diagnostics types from the policy.

Alternative: retain separate Store and diagnostics scans and optimize only eviction. Rejected because it leaves multiple sources of truth for one decision. A durable content-key index is unnecessary and complicates moves, pin changes, and restore.

### Linear retention with pinned capacity reserved

Use logical newest-first order (the chosen head plus originals, skipping the moved occurrence). Determine pinned count with a bounded scan, then process the logical sequence newest-first: retain at most 100 unpinned images, and among image-eligible ordinary items retain at most `max(0, effectiveLimit - pinnedCount)` total; retain every pinned item. Emit removed-original IDs when a candidate fails either bound, then compact retained items in original logical order. The original policy applies image cap before total cap, so an image rejected by the image cap must never consume the ordinary-item quota. The current policy clamps its `limit` argument to at least one; settings normalize to 100...1,000. Every source item is visited a constant number of times, without `while`/`filter`/`lastIndex` per eviction or repeated middle-array removal. `removedItemIDs` excludes an incoming item never retained. No `Set(before) - Set(after)` is required in the Store.

A forward algorithm that merely fills `limit` slots is incorrect: a later pinned item can displace a newer ordinary item. Reserving pinned capacity up front yields the same survivors as evicting the oldest retained unpinned item repeatedly, including fully pinned overflow. A two-pass classification/retention plus linear compaction is preferable to a highly stateful literal single loop. Include mixed pinned/image/ordinary ordering tests to check equivalence with the prior two-stage policy.

### Apply setting changes through the Store's final-state mutation boundary

Observe `settings.$historyLimit` with a Store-owned cancellable, skip the initial publisher value, and schedule weakly captured MainActor enforcement on a subsequent actor turn. Re-read `settings.historyLimit` there rather than trusting the publisher's `willSet` value, since normalization occurs in `didSet`. Rapid changes may schedule redundant evaluations but only a trim assigns `items`, cleans preview tasks and pending durable-media release proofs, refreshes visible items/selection, and calls `saveItems` once. If no item is removed, do none of these writes. A copy before delivery uses the current normalized limit; any later enforcement sees the already bounded state. Here “immediate” means the next MainActor turn, without another copy, not synchronous completion inside the settings setter.

On initialization, enforce the same bounds against loaded (or injected) items before presenting them. If any item is removed, initialize from retained items, refresh selection, and request one save through the injected persistence closure; otherwise do not save. Startup has no preview work or pending durable-media proofs yet. The existing save coordinator already accepts the injected persistence request; keep the V2 schema and save ordering unchanged.

Alternative: normalize a new backing setting or enforce synchronously from the publisher value. Rejected to keep AppSettings surgical and avoid acting on a pre-normalization publication. Debouncing enforcement is incompatible with the desired user-facing behavior.

### Preserve cleanup and selection contracts

`ClipboardStore.add` uses the policy result for logging, cleanup, selection and metadata registration; diagnostics format remains unchanged but its duplicate scan is removed. `refreshFilteredItems` already chooses a remaining visible ID or nil after eviction. Only set the preferred selection when the policy reports a retained item; never assign a discarded incoming ID. Metadata registration accepts only a retained insertion; keep the existing membership guard as defense. Runtime trimming uses `withHistoryStateMutation` and existing removal cleanup, never `rememberDeleted`, `clearSystemPasteboardIfMatching`, or `cancelPendingImageEncoding`. Neither retained-item moves nor empty trims should cancel their preview work.

### Deterministic complexity evidence

Add a count-only test observation seam around actual policy item classification/retention visits (including all policy passes), with no clipboard payload or log output. Test 1,000-item to 100-item reductions against a linear visit bound and exact survivors/removed IDs, alongside edge-case behavior. Do not use elapsed time as the primary CI gate. Count instrumentation must cover every visited item on each policy path, rather than incrementing just once per top-level call; structural review/tests also guard against uninstrumented eviction rescans.

## Risks / Trade-offs

- [A reserved pinned quota or image-first decision changes ordering] → Assert survivors against mixed pinned, image, and ordinary fixtures; keep the existing two-stage priority as the reference behavior.
- [Published setting arrives before normalization, or rapid changes deliver stale values] → Defer to the next MainActor turn and always read the current setting; test normalization and rapid updates.
- [Startup trim rewrites history unnecessarily or affects legacy restore] → Save only on actual removal through the existing persistence entry point; cover restored and injected history, including no-op startup.
- [Eviction cancels the wrong task or leaves stale selection/proof] → Consume only actual removed-original IDs, reconcile after the completed mutation, and test late preview callbacks and durable-release proofs.
- [Instrumentation counts miss a nested scan] → Count actual per-item inspection sites and pair operation-count tests with review of retention code; do not treat a count alone as a proof of complexity.

## Migration Plan

No data migration. On first launch after adoption, oversized restored history is compacted in memory and a normal final-state save is requested. Rollback to the previous build reads the same V2 history format; intentionally evicted cards cannot be recovered from a later successful trimmed save. No additional files or dependencies are required.
