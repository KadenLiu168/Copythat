## Context

See `proposal.md` for motivation and `specs/panel-and-search/spec.md` for display contracts.

`ClipboardCardView` currently delegates equality to synthesized `ClipboardItem.Equatable`, stores image/link-image `Data?` in `MediaTaskIdentity`, and hashes source-icon bytes for `SourceLogoImageView` identity. `BottomPanelView` wraps cards in `.equatable()` and preserves their item IDs, making both render equality and task identity real reconciliation boundaries.

The model already establishes `imageBlobID`, `linkImageBlobID`, and `sourceAppIconBlobID` when payloads are finalized or restored. Resident bytes imply an address; supported transformations preserve matching bytes/addresses. Known prepared addresses are trusted upstream, not recomputed by the view.

`ClipboardCardMediaState.load()` first clears transient decoded media and failure flags, then loads only nonresident image/link-image references while eligible. Cancellation and a live panel authorization check reject late completions. No state-machine changes are needed.

This design is included because it coordinates UI task invalidation with the persistence residency boundary. Durable commits seed the existing bounded cache, defer history-byte release while the panel is visible, and release on panel close. A same-address transition on a visible test card validates the view contract; it does not authorize earlier production release or establish an existing visible-release bug.

## Goals / Non-Goals

**Goals:**

- Make SwiftUI reconciliation consume existing media addresses and item residency rather than media bytes.
- Keep render invalidation and task invalidation consistent for both media roles.
- Preserve the existing StateObject, loading, cancellation, authorization, geometry, source appearance and action behavior.

**Non-Goals:**

- Residency does not describe cache membership or decoded media in `ClipboardCardMediaState`; it describes bytes held by `ClipboardItem` only.
- Do not make the entire rendering pipeline byte-free: decoding and the existing `SourceThemeColor` NSData-keyed cache remain unchanged.
- Do not add payload validation or fallback hashing in the view; model finalization and blob-read integrity remain their existing owners.
- Do not widen production edits beyond `Sources/Copythat/Views/ClipboardCardView.swift` or introduce production-wide test infrastructure.

## Decisions

### D1: Share one local payload identity

Introduce `MediaPayloadIdentity: Hashable` containing only `blobID: String?` and `isResident: Bool`. Derive image, link-image and source-icon identities from their existing addresses and `Data != nil`; reuse the image/link-image projections in both render and task identities.

```text
(nil, false)   no payload
(A, true)      item owns resident bytes
(A, false)     item retains a persisted reference

(A, true) --> (A, false) --> task invalidated --> existing loader
(A, false) --> (A, true) --> task invalidated --> clear lazy state
```

Do not include `Data`, decoded images, cache state, or newly computed hashes. Blob ID alone is rejected because it cannot distinguish the two loading paths. Separate residency rules per identity are rejected because they can drift. Keep the type local to the card file, preferably nested; module-internal access is allowed only where direct identity tests need `@testable import Copythat`.

### D2: Project item inputs into render equality

Introduce local `CardRenderIdentity: Equatable` with this complete item projection:

| Input | Reason |
| --- | --- |
| `id`, `kind` | Card identity, rendering branch, media and drag role |
| `title`, `preview` | Text, file, URL and fallback presentation |
| `sourceApp`, source-icon payload identity | Source icon, fallback and header theme |
| `createdAt` | Relative timestamp |
| `isPinned`, `pinboardName` | Context-menu actions |
| `textValue`, `fileURLs` | Text counts, URL display, drag content |
| Image payload identity | Resident/reference display path |
| `linkTitle`, link-image payload identity | URL title and preview path |

Exclude `searchText` and all three media Data fields. `ClipboardCardView.==` compares this projection plus the existing `pinboards`, `isSelected`, `hidesPreview`, `panelVisible`, and `authorizationGeneration` inputs. It must not call full-item equality.

Keep existing handling of callbacks, store, loader and StateObject unchanged: production callers reuse the same store/loader and callbacks act on the same item ID. Residency remains represented even when previews are hidden because the captured item also supplies drag behavior. Do not change `ClipboardItem.Equatable` to serve this UI-specific projection. A stored full-item wrapper is rejected because synthesized equality would still compare bytes.

### D3: Retain task authorization semantics

`MediaTaskIdentity: Hashable` contains only `itemID`, image payload identity, link-image payload identity, `eligible`, and `authorizationGeneration`. Eligibility remains `panelVisible && !hidesPreview`.

Required identity changes include reference A to B, resident A to B, same-A reference/resident transitions in both directions, payload insertion/removal, eligible/ineligible changes, and reopening with a newer generation. Preserve the live authorization closure and existing cancellation checks. Do not change outer `.id(item.id)` or use media identity to recreate the whole card; task invalidation must work with retained StateObject ownership.

### D4: Separate icon content identity from render residency

Use `sourceAppIconBlobID` directly as `sourceIconIdentity: String?`. Update `SourceLogoImageView.identity` and `Coordinator.identity` to the same lightweight type. Keep the existing card-specific `sourceLogoIdentity`, incorporating item UUID and the optional address with an explicit absence representation; no bytes hash is involved.

Card render equality includes icon residency because absence of bytes produces fallback icon/theme. The representable's content identity needs only the address: an unavailable icon does not instantiate that branch, and resident availability creates the real icon branch again. This avoids adding residency to native icon content identity or introducing another identity abstraction. A recomputed Data hash is rejected as redundant and less explicit than the established address.

### D5: Verify both reconciliation boundaries with real hosting

Use the existing `CardMediaFixture`, `NSHostingView`, read recorder, injected media state, and bounded condition waits. Add a small test-local equatable host or equivalent `.equatable()` wrapper. Keep the same hosting instance, item ID and injected StateObject across updates; fix metadata and authorization generation for same-address tests. Do not manually invoke `load()`, clear state, or change outer card identity to force success.

- Highest priority: start with resident image A, no decoded lazy state and zero reads; use the existing `releasingResidentMedia(...)` transform to create reference A. With a cold fixture cache, update the equatable host, verify one recorded read, matching decoded content, spinner disappearance and unchanged geometry. The transform is exercised, not modified.
- Exercise equivalent same-address transitions for URL link-image media so both task fields are tested.
- Reference A to resident A: test already-loaded state clearing separately from a blocked pending completion. Verify direct resident content and no new read; release the old read and verify it cannot repopulate decoded state or failure flags.
- Preserve `replacedReferenceOnTheSameCardRejectsThePriorCompletion` and `inlineBytesReplacementOnTheSameCardRejectsThePriorCompletion`. The latter covers reference A to resident B, not resident A to resident B; add explicit resident replacement coverage rather than relying on its name.
- Preserve `closeReopenWithoutIntermediateRenderRejectsTheLateCompletion`, and separately verify rendering a newer generation starts a successful current request. Do not mistake old-result rejection for proof of reload.
- Retain hidden-panel, hidden-preview, hidden-scroll, disappearance, drag and layout regressions; include hidden residency updates with zero reads.
- Direct identity/equality tests cover all projection fields and external inputs independently; use copies of one fixture or fixed IDs/timestamps so an unrelated difference cannot make a missing-field test pass. Test both same-address residencies and payload presence/absence for every role.
- Source-icon tests cover equal/different addresses, per-card captured colors, unchanged header sizing, and same-address fallback/resident render invalidation. All fixtures use addresses matching their bytes, not deliberately inconsistent prepared identities.

Loader invocation and disk reads are distinct. The cold fixture proves entry into lazy loading through a read; real committed media may be served from the preseeded cache with zero reads. Do not add a loader seam or require disk reads on a cache hit. Source review verifies removal of bytes from identities and absence of new SHA256 identity work; timing benchmarks are not an acceptance substitute.

## Risks / Trade-offs

- [Omitting an item field suppresses real updates] --> Keep the explicit projection above and independent equality regressions, especially title, pin state, pinboard assignment and link title.
- [Task identity changes but `.equatable()` hides the update] --> Exercise same-address transitions through the actual equatable wrapper, not only direct state loading.
- [Same-address pending completion races with resident replacement] --> Keep task cancellation and live authorization checks; synchronize request replacement before releasing the blocked read and assert the final state.
- [A new identity test passes because UUID or timestamp changed] --> Hold unrelated metadata and external inputs constant in transition and equality fixtures.
- [Confusing fixture release with production policy] --> Preserve visible-panel deferral, seed-before-release ordering and all store tests; never change release timing to satisfy card tests.
- [Claiming all bytes-based render work is removed] --> Limit the claim to render equality, media task identity and source-icon view identity; theme cache and decoding remain out of scope.

## Migration Plan

No data migration or persistence change is required. Ship the bounded card/test changes only after `swift build`, full `swift test`, `./script/verify_all.sh`, and `git diff --check` pass. Manually check resident/lazy image and URL previews, privacy, close/reopen, source icons and card actions. Rollback consists of reverting the card/test change; stored histories remain compatible.
