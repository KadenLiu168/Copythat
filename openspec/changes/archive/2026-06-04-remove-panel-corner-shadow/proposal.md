## Why

The bottom floating panel currently shows rounded corners, but its outer shadow leaves visible rectangular corner artifacts. This makes the panel look visually clipped and undermines the intended native, polished appearance.

## What Changes

- Remove the panel container's outer SwiftUI shadows that create rectangular corner artifacts.
- Keep the panel's rounded content clipping, border treatment, search, pinboard filtering, item browsing, and paste behavior unchanged.

## Capabilities

### New Capabilities

- None.

### Modified Capabilities

- `panel-and-search`: The bottom floating panel should not render rectangular shadow artifacts at its four corners.

## Non-goals

- Redesigning clipboard cards, typography, colors, layout, or panel sizing.
- Adding a replacement custom shadow system.
- Changing paste, search, pinboard, selection, or settings behavior.

## Impact

- Affects the SwiftUI panel presentation in `Sources/Copythat/Views/BottomPanelView.swift`.
- No API, data model, persistence, dependency, or permission changes.
