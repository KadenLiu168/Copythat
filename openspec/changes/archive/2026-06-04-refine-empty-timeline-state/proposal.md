## Why

The empty timeline state currently reads like a card placed at the start of the horizontal list, so empty pinboards leave the lower panel visually weighted to the left. Its prominent app mark also competes with the user's task and feels abrupt in an otherwise quiet native panel.

## What Changes

- Rework the empty timeline presentation so it occupies the available timeline area and is visually centered within the panel content.
- Remove the prominent app logo from the empty state, or reduce any icon treatment to a subtle contextual symbol that does not dominate the message.
- Make empty-state copy reflect the current context, such as all history empty, selected pinboard empty, or search returning no matches.
- Preserve existing card browsing, search, pinboard filtering, footer status, and keyboard behavior.

## Non-goals

- Do not redesign the panel command bar, pinboard buttons, footer, or clipboard cards.
- Do not change how items are assigned to pinboards, pinned, searched, selected, or pasted.
- Do not add onboarding flows, illustrations, new assets, or external dependencies.

## Capabilities

### New Capabilities

- None.

### Modified Capabilities

- `panel-and-search`: Refine the no-visible-items behavior so empty timeline states are centered, visually quiet, and context-aware.

## Impact

- Affected code is expected to be limited to `Sources/Copythat/Views/BottomPanelView.swift`, `Sources/Copythat/Views/EmptyTimelineView.swift`, and focused view/model support needed to choose the empty-state copy.
- No persistence, pasteboard parsing, source tracking, paste execution, settings, or dependency changes are expected.
