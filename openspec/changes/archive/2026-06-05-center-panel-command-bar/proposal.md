## Why

The bottom-panel header currently separates search, pinboard filters, and the add-pinboard action across the full panel width, so the controls do not read as one focused command group. Centering the complete command bar and strengthening its spacing hierarchy will make the header easier to scan and closer to the compact macOS utility-panel layout the product is targeting.

## What Changes

- Center search, Clipboard, pinboard filters, and the add-pinboard action together as one top command group.
- Use larger gaps between the search, pinboard-filter, and add-pinboard groups than between individual pinboard filters.
- Increase non-Clipboard category marker circles slightly while preserving their configured colors and vivid appearance.
- Keep search expansion, pinboard horizontal overflow, selection, filtering, and pinboard creation behavior unchanged.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `panel-and-search`: Change the command-bar layout from separated left, center, and right areas to one centered group with explicit spacing hierarchy and slightly larger category markers.

## Impact

- Affects the header composition, filter-strip sizing, spacing, and category marker size in `Sources/Copythat/Views/BottomPanelView.swift`.
- Updates the `panel-and-search` specification.
- Does not change stored clipboard data, pinboard persistence, search behavior, filtering behavior, pinboard creation, dependencies, or public APIs.

## Non-goals

- Redesigning the panel background, cards, footer, search field styling, or pinboard creation popover.
- Changing pinboard colors, names, ordering, persistence, or assignment behavior.
- Removing horizontal scrolling when the pinboard list exceeds available command-bar width.
