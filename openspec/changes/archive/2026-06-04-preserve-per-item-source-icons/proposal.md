## Why

Text history cards can display the correct source logo when first captured, then show a later copied item's source logo after another text copy. This breaks the user's ability to trust source context in clipboard history, especially when multiple items are visible at once.

## What Changes

- Preserve each history card's source icon from the `ClipboardItem` captured for that item.
- Stop visible cards from borrowing a shared source icon keyed only by source application name when rendering the card logo and source accent.
- Add focused coverage for the regression where two text items with distinct captured icons remain visually independent after both are displayed.

## Non-goals

- Do not change how Copythat resolves the source application for new pasteboard changes.
- Do not add new source metadata fields, persistence formats, settings, or UI controls.
- Do not change duplicate-content behavior, pinboards, search, paste, or history retention.

## Capabilities

### New Capabilities

- None.

### Modified Capabilities

- `clipboard-history`: Source context display must preserve the source icon captured for each history item instead of allowing another visible item to replace it.

## Impact

- Affected code is expected to be limited to the history card rendering path around `BottomPanelView`, `ClipboardCardView`, and any now-unused `ClipboardStore.sourceIconByApp` support.
- Tests should cover per-item source icon rendering behavior or the store/view data contract that feeds it.
- No external APIs, app permissions, dependencies, or data migrations are expected.
