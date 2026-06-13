## Why

The bottom-panel command bar currently mixes 32-point search/add controls with 26-point pinboard filters, making the search and add buttons feel visually heavy. Search expansion also swaps between separate compact and expanded views, so the leftward expansion feels abrupt instead of fluid.

## What Changes

- Align the visible height of the search control, expanded search field, pinboard filters, and add-pinboard control at 26 points.
- Preserve approximately 32-point hit areas for the icon controls so the compact command bar remains easy to click.
- Replace the hard search-control swap with a continuous leftward pill expansion using a smooth 0.22-second animation.
- Slightly delay search text and clear-button visibility during expansion so the field feels like it opens before content appears.
- Preserve search matching, pinboard filtering, add-pinboard behavior, existing command-bar spacing, and the previous leftward expansion behavior.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `panel-and-search`: Refine command-bar visual consistency and search expansion motion.

## Impact

- Affects `Sources/Copythat/Views/BottomPanelView.swift` presentation and animation behavior.
- Updates the `panel-and-search` specification.
- Does not change stored clipboard data, search matching, pinboard persistence, dependencies, or public APIs.

## Non-goals

- Changing search matching, filtering, submission, or clear-button semantics.
- Changing pinboard names, colors, ordering, persistence, or assignment behavior.
- Changing command-bar horizontal spacing, panel background, card layout, or footer behavior.
