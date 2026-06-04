## Why

Card selection in the bottom panel feels visibly sluggish when users move with the left/right keys or click a card. The selection path currently does more view and store work than needed for a single selected-card change, which makes a core browsing interaction feel less direct.

## What Changes

- Keep the existing selected-card visual treatment while reducing unnecessary selection updates and card redraw work.
- Make keyboard boundary movement and repeated selection of the same card no-op at the store level.
- Keep filtered results and selection in sync so the panel does not repeatedly resolve stale selection state.
- Avoid avoidable AppKit image assignments during unchanged source icon updates.

## Capabilities

### New Capabilities

### Modified Capabilities
- `panel-and-search`: bottom-panel card selection must remain responsive for keyboard movement and mouse selection.

## Non-goals

- No changes to card size, selected-card styling, panel layout, search behavior, pinboard behavior, or paste semantics.
- No new dependencies, persistence changes, settings, or public APIs.
- No broad performance work outside keyboard left/right movement and mouse card selection.

## Impact

- Affects `ClipboardStore`, `BottomPanelView`, `ClipboardCardView`, and focused tests.
- Updates the `panel-and-search` OpenSpec capability with selection responsiveness requirements.
