## Why

The pinboard filters in the bottom-panel command bar currently use muted short capsules whose reduced opacity blends into the warm glass background. Users need clearer, more lively category markers that remain visually consistent with macOS.

## What Changes

- Replace non-Clipboard pinboard markers with compact circular dots.
- Keep category dots strongly saturated in selected and unselected states while preserving each pinboard's configured color and the existing filter selection treatment.
- Preserve the Clipboard history icon, filtering behavior, pinboard ordering, and compact command-bar layout.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `panel-and-search`: Clarify that non-Clipboard pinboard filters use vivid circular category markers that preserve their configured colors.

## Impact

- Affects pinboard marker presentation in `Sources/Copythat/Views/BottomPanelView.swift`.
- Updates the `panel-and-search` specification.
- Does not change stored clipboard data, configured pinboard colors, filtering behavior, dependencies, or public APIs.

## Non-goals

- Changing how pinboard colors are selected or persisted.
- Redesigning the panel background, item cards, settings UI, or filter selection behavior.
