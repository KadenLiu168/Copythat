## 1. Search Expansion Layout

- [x] 1.1 Keep the command bar's search layout footprint at the compact width and trailing-anchor the expanded field so it grows leftward; verify the pinboard filters, add-pinboard control, default command-bar position, and horizontal overflow do not move when search expands or collapses.

## 2. Empty Search Dismissal

- [x] 2.1 Add one local empty-search dismissal action in `BottomPanelView` and use it when pinboard filters or add-pinboard are activated; verify an empty search collapses while the chosen action completes, and a non-empty query remains expanded and continues filtering.

## 3. Verification

- [x] 3.1 Run `swift build` and `./script/verify_all.sh`; verify the project builds and all automated checks pass.
- [x] 3.2 Open the bottom panel in Aqua and Dark Aqua and manually verify leftward expansion, stationary adjacent controls, empty-search collapse from pinboard and add-pinboard actions, persistent non-empty queries, search clearing, pinboard selection, add-pinboard presentation, and constrained-width pinboard scrolling.
