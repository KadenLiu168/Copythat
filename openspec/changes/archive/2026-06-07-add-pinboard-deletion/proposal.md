## Why

Users can create custom pinboards from the bottom panel, but they cannot remove categories that are no longer useful. This leaves stale pinboards in the compact command bar and makes old organization choices feel permanent.

## What Changes

- Add a delete action for custom pinboards from the bottom-panel pinboard filter controls.
- Expose deletion through a right-click context menu on custom pinboard filters only.
- Require confirmation before deletion, including the pinboard name and the number of clips that will be moved out of it.
- Delete the custom pinboard without deleting any clipboard history items.
- Move clips assigned to the deleted pinboard out of that pinboard by clearing their pinboard assignment.
- If the user is viewing the deleted pinboard, return the panel to the Clipboard filter while preserving the current search query.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `panel-and-search`: add custom pinboard deletion behavior from the bottom panel, including confirmation, assignment cleanup, and selection fallback.

## Impact

- Affects the bottom-panel pinboard filter context menu and confirmation flow.
- Adds narrow settings and clipboard-store APIs for deleting a custom pinboard and clearing matching item assignments.
- Requires focused persistence, filtering, and selection tests, plus `swift build` and `./script/verify_all.sh` for implementation verification.

## Non-goals

- Rename, reorder, recolor, or undo deletion of custom pinboards.
- Add a full pinboard management screen or Settings-based management controls.
- Delete clipboard history items when a pinboard is deleted.
- Change the built-in Clipboard or Pinned identities, colors, or availability.
- Replace the existing name-based clipboard item pinboard association with stable pinboard IDs.
