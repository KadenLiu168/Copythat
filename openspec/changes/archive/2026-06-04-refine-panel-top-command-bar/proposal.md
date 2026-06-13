## Why

The bottom panel header currently places search, pinboard filters, and the add/settings action on one visual line without enough grouping. The result is a busy top area that competes with clipboard cards and makes the available actions harder to scan.

This change refines the top command bar so users can quickly identify search, filtering, and management controls while preserving the existing panel behavior.

## What Changes

- Rework the panel header into a clearer command bar with left search, center pinboard filters, and right add/settings action.
- Restyle the pinboard filter strip as a light rounded control group with lower-contrast selected state.
- Restyle the search and add buttons as matching compact toolbar controls with hover, pressed, and focus feedback.
- Preserve current search expansion, pinboard filtering, settings opening, keyboard shortcuts, horizontal timeline, and card behavior.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `panel-and-search`: refine the panel header command bar layout and visual states while preserving existing search and filtering behavior.

## Non-goals

- Do not change clipboard history storage, search matching, pinboard data, paste behavior, or card content layout.
- Do not add a new pinboard creation flow.
- Do not introduce new dependencies or migrate the UI framework.

## Impact

- Affected UI code: `Sources/Copythat/Views/BottomPanelView.swift`.
- Affected specs: `openspec/specs/panel-and-search/spec.md` via a delta spec.
- No API, persistence, entitlement, or dependency changes.
