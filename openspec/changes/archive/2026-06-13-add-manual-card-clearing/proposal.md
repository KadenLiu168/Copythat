## Why

Users can accumulate clipboard cards quickly, but Settings currently only lets them limit future history size. They need an explicit way to clear stored cards now without losing intentionally saved pinned or categorized cards by default.

## What Changes

- Add a manual clear-cards action to the native Settings surface.
- Show the current clipboard card count near the clear action.
- Confirm destructive clearing before deleting history.
- Provide a default clear mode that removes only unpinned and uncategorized cards.
- Provide an explicit clear-all mode that also removes pinned cards and cards assigned to custom pinboards.
- Refresh visible history, selection, and persisted history after clearing.

## Non-goals

- Do not add automatic or scheduled cleanup intervals in this change.
- Do not add undo, trash, export, or recovery for cleared cards.
- Do not change card capture, search matching, pinning, custom pinboard creation, paste behavior, or history limit semantics.
- Do not delete custom pinboards themselves when clearing cards.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `settings-and-launch`: Settings exposes a manual card-clearing control with destructive confirmation.
- `clipboard-history`: Clipboard history supports clearing eligible cards while protecting pinned and custom-pinboard cards by default, plus an explicit clear-all path.

## Impact

- Affects `SettingsView`, `SettingsWindowController`, `CopythatApp`, and `AppDelegate` so Settings can act on the shared clipboard store.
- Adds a focused `ClipboardStore` clearing API for manual Settings actions and future reuse.
- Adds store and settings-window tests for default protected clearing and clear-all behavior.
- No new dependencies or persistence format changes.
