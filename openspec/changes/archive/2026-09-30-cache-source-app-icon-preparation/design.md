## Context

See `proposal.md` for motivation and scope. `CopySourceTracker.source(for:)` currently validates the source candidate and name, obtains an icon from `NSWorkspace.icon(forFile:)` when a bundle URL exists or from `NSRunningApplication.icon` otherwise, and calls `appIconPNGData(maxPixel: 160)` on every observation. `ClipboardSource` hashes icon bytes when no known `iconBlobID` is supplied.

`start()` and the application activation observer already invoke this path. Shortcut observation, first-observed pasteboard snapshots, and source resolution also invoke it. These synchronous entry points already run within the existing tracker execution model; this change adds no concurrency boundary.

`PreparedMedia` already pairs final bytes with their content address. `ClipboardSource`, all four Store capture paths, `ClipboardItem`, and persistence already forward known identities. Existing main-spec requirements cover attribution ordering, per-item icon preservation, and identity propagation; the delta adds bounded reuse across independent observations without replacing those requirements.

## Goals / Non-Goals

**Goals:** Eliminate all icon acquisition, rendering, PNG encoding, and identity hashing on retained-entry hits while keeping every source observation's context independent. Make the operation counts, identity isolation, retry behavior, and LRU order deterministically testable through the production integration.

**Non-Goals:** See `proposal.md`. In particular, this design does not promise one preparation for an entire process lifetime: eviction, unsuccessful preparation, and unavailable process-generation metadata permit further attempts. It does not refresh a successfully cached icon during the same retained process generation.

## Decisions

### D1: Own the cache in CopySourceTracker

Add a private `sourceIconCache` member and small internal `SourceAppIconCacheKey` and `SourceAppIconCache` types in `Sources/Copythat/Services/CopySourceTracker.swift`. Cache lifetime ends with the tracker; no global state or separate observer is needed. Existing startup and activation calls naturally warm entries; no additional prewarm task is introduced.

Alternatives: a View cache risks replacing captured per-item icons; a Store or persistence cache couples preparation to the wrong owner; a global singleton extends ownership beyond source tracking. All are unnecessary.

### D2: Cache PreparedMedia and forward its known identity

The successful value is `PreparedMedia`, never raw `Data` or another media model. Place icon acquisition and PNG preparation entirely inside the lazy miss loader; wrap successful final PNG bytes with `PreparedMedia(hashing:)` once. On hit, return the retained value directly. Construct `ClipboardSource` with both `iconData: prepared?.data` and `iconBlobID: prepared?.id`, preventing its existing fallback hash from running.

Preserve the current icon selection and encoding branches exactly. `NSWorkspace.icon(forFile:)` returns an image; the optional result in this branch is PNG preparation. The `app.icon` branch can additionally be unavailable. Neither changes the retry contract.

Alternative: caching Data removes encoding but leaves `ClipboardSource` hashing on every observation. It fails the operation-count contract. Reusing `PreparedMedia(data:id:)` to invent or recompute identities is unnecessary; the miss already establishes the correct address.

### D3: Use process-generation identity and bypass incomplete identity

The key contains `processIdentifier`, a non-optional captured `launchDate`, and optional `bundleURL`. Construct it only when PID is positive and `NSRunningApplication.launchDate` is available. Equality uses all three fields. This distinguishes restart/PID reuse with different launch dates and distinguishes installations with different bundle locations, including shared bundle identifiers. A nil bundle URL is permitted when PID and launch date identify the generation.

When a reliable key cannot be constructed, prepare the icon normally and forward its known identity for that observation, but perform no cache lookup or insertion. Do not change candidate validation, substitute a display-name key, or reject attribution due to missing cache identity. This conservative policy closes the `(reused PID, nil launchDate, same bundleURL)` collision left by a fully optional key. If metadata later becomes available, the next observation can populate the cache.

Alternatives: PID alone can collide after reuse; app name and bundle identifier are not process identities; optional launch date plus bundle path cannot distinguish every restart. Retaining and comparing native NSRunningApplication objects is another identity approach, but the chosen value key keeps deterministic process-generation tests small and avoids retaining native objects. No platform identity registry or termination cleanup is added.

### D4: Bound successful entries with a small LRU

Use a source-specific dictionary of prepared values plus a recency array and internal capacity, defaulting to 32. Tests use capacity 2. Require positive capacity as an internal invariant; no user setting is introduced. A hit moves the key to most recent without invoking the loader. A successful miss inserts at most one value and evicts the least recent entry if needed; a failed miss changes neither successful entries nor recency. Keep at most one recency occurrence per key.

At 32 entries, linear recency maintenance is simple and bounded. Alternatives such as a generic cache, linked-list implementation, byte-cost policy, or termination observer add machinery beyond the requested entry bound. The bound applies to cache ownership, not all source-icon bytes retained by history or observation state.

### D5: Cache successful preparations only

The loader returns an optional prepared value. Nil returns an iconless observation while preserving app name and observation context; it creates no entry. The next request retries. Preparation is attempted at most once per miss or bypass, and hashing happens only once for successful bytes.

Alternative: negative caching could turn a temporary failure into a missing icon for an entire retained process identity. A retry TTL would add policy without addressing a demonstrated need.

### D6: Cache icon payloads only and construct fresh observations

After validation and cache resolution, create a new `ClipboardSource` using the current app name and the caller's `capturedAt` and `pasteboardChangeCount`. Preserve nil change counts rather than adding a new pasteboard read. Do not cache or reuse `ClipboardSource`, move timestamp creation, or alter the activation, shortcut, snapshot correction, or resolution ordering.

Prepared bytes and identity are immutable values owned by each created source and item. Removing cache ownership cannot mutate those existing values. Alternative: caching the complete source would freeze timestamp and change-count context and break attribution timing.

### D7: Exercise the production integration with existing hash observation

Reuse `MediaOperationCounters` and its task-local `MediaHashObservation` recorder to count actual identity hashes; separately count executions of the lazy icon preparation loader. Do not infer SHA256 counts from loader counts or timing. Keep fixture generation and assertion-side digests outside measured windows.

Existing `frontmostSourceProvider` replaces the entire source and therefore bypasses icon preparation. Add only the narrow internal seam needed to test the source assembly path actually called by `source(for:)`, accepting deterministic identity/name/context and a lazy preparation loader without duplicating source construction in tests. A small helper below the unchanged native candidate/name validation is sufficient; no general application-provider framework is needed. Ensure production calls that helper, and test repeated calls with different timestamps and counts, including nil.

Extend identity-forwarding coverage from a cached value through Store capture and real temporary persistence. Source-icon identity counts must stay zero after cache hit; an image capture's independent hash must be measured separately or explicitly accounted for. Verify matching blob references and bytes, including restore integrity verification, rather than only checking in-memory IDs.

## Risks / Trade-offs

- [Incomplete process metadata loses cache benefit] -> Bypass caching but keep normal icon preparation and attribution. Never trade icon isolation for an optimization.
- [LRU eviction causes another preparation for a live process] -> Define prepare-once only while retained, and test actual eviction order plus reloading.
- [An application's icon changes without restarting] -> A retained generation uses its prepared icon until eviction; no invalidation or icon-change monitoring is added. Existing history icons stay immutable.
- [Cache tests pass while production still prepares eagerly] -> Keep all icon acquisition inside the lazy loader and test the shared production source assembly path with both loader and hash counters.
- [Failure or eviction accidentally loses source context] -> Verify name attribution, independent timestamp/count inputs, retry success, and survival of previously created sources/items.
- [A broad gate touches user state] -> Inspect gate/live-driver isolation before execution; use temporary history/defaults and named pasteboards where supported, clean up child processes, and keep evidence under `.build/verification/` or outside the repository.
- [Integrity verification is mistaken for redundant identity hashing] -> Separate the two existing counter categories; preserve required disk-read checks.

## Migration Plan

No data migration is needed. The cache starts empty, fills through existing observations, and disappears with the tracker. Rollback removes the tracker-local reuse and its tests without changing stored data, permissions, or UI contracts.
