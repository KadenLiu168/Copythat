## Why

Clipboard cards still compare or hash resident media bytes during SwiftUI render/task reconciliation even though the model already carries content-addressed Blob IDs. Reusing those identities must also preserve residency transitions so responsive browsing does not regress into stale previews or indefinitely loading cards.

## What Changes

- Replace full-item card render equality with a local metadata identity that represents image, link-image, and source-icon payloads as Blob ID plus whether bytes reside in the item.
- Replace image/link-image bytes in media task identity with the same lightweight payload identities, retaining eligibility and panel authorization generation.
- Use the existing source-icon Blob ID for AppKit image-view identity instead of hashing icon bytes.
- Explicitly require correct same-address resident/reference transitions, metadata invalidation, stale-completion rejection, and hidden-preview behavior; verify transitions through real `.equatable()` hosting.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `panel-and-search`: Extend eligible lazy-media display to explicitly cover same-address residency changes; require lightweight card reconciliation without losing current rendering, actions, source icons, or authorization behavior.

## Impact

- Production changes are limited to `Sources/Copythat/Views/ClipboardCardView.swift`.
- Regression coverage belongs in `Tests/CopythatTests/ClipboardCardViewTests.swift` and `Tests/CopythatTests/ClipboardCardLazyMediaTests.swift`.
- No public API, dependency, persistence format, or migration changes. Existing model content-address invariants and lazy loading are reused.
- A visible residency transition is a card contract test, not a change to store policy: durable release currently defers history-byte release while the panel is visible.

## Non-goals

- Do not change `ClipboardItem.Equatable`, its model transformations, or persistence schema.
- Do not modify `PreparedMedia`, `ClipboardHistoryBlobStore`, `ClipboardHistoryMediaLoader`, `ClipboardCardMediaState`, `storageOptimized`, `releasingResidentMedia`, `materializedForPaste`, or `withLinkPreview`.
- Do not change durable-release timing, committed-media cache seeding, source attribution, image decoding, drag/paste behavior, or source-theme derivation/cache keys.
- Do not add media identity hashes, caches, actors, detached tasks, migrations, or a shared identity framework.
