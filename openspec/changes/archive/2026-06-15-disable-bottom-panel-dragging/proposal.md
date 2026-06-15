## Why

The bottom panel is intended to behave as a transient launcher anchored near the bottom of the active screen. Allowing users to drag it away from that position makes it behave like a movable utility window and breaks the expected bottom-panel placement model.

## What Changes

- Prevent the bottom floating panel from being repositioned by mouse dragging.
- Preserve the current bottom placement calculation when the panel is shown.
- Preserve existing panel interactions, including card selection, search, horizontal scrolling, paste, pinboard controls, and Escape-to-close behavior.

## Capabilities

### New Capabilities

- None.

### Modified Capabilities

- `panel-and-search`: clarify that the bottom floating panel remains anchored near the bottom of the active visible screen area and cannot be repositioned by mouse dragging.

## Non-goals

- Redesigning the panel layout, materials, size, corner treatment, card presentation, or command bar.
- Changing the panel's screen-selection logic, multi-display behavior, or bottom frame calculation.
- Changing card drag, paste, search, pinboard, or privacy-preview behavior.

## Impact

- Affects the AppKit panel configuration in `Sources/Copythat/Services/PanelWindowController.swift`.
- Updates the `panel-and-search` OpenSpec capability.
- Requires `swift build`, `./script/verify_all.sh`, and panel verification that mouse dragging does not move the panel while existing controls remain interactive.
