## Why

Expanding the bottom-panel search field currently shifts the pinboard filters and add-pinboard action to the right, making the command bar feel unstable. An empty expanded search field can also remain open after the user interacts with another control, leaving unnecessary visual weight in the header.

## What Changes

- Make the search field expand leftward while keeping the pinboard filters and add-pinboard action in stable positions.
- Collapse the search field when it is empty and the user leaves search to interact with another panel control.
- Keep the search field expanded when it contains a query so the active search remains visible and editable.
- Preserve existing search filtering, pinboard filtering, horizontal overflow, and add-pinboard behavior.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `panel-and-search`: Define stable leftward search expansion and empty-search collapse behavior in the bottom-panel command bar.

## Impact

- Affects search layout and focus-driven presentation in `Sources/Copythat/Views/BottomPanelView.swift`.
- Updates the `panel-and-search` specification.
- Does not change stored clipboard data, search matching, pinboard persistence, dependencies, or public APIs.

## Non-goals

- Redesigning the search field, pinboard filters, add-pinboard control, panel surface, or cards.
- Changing search matching, keyboard submission, filtering results, or pinboard creation behavior.
- Changing command-bar centering, spacing, marker size, or horizontal overflow behavior beyond preventing search expansion from moving adjacent controls.
