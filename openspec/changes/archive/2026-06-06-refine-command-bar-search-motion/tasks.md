## 1. Command Bar Height

- [x] 1.1 Introduce shared visible command-control metrics in `BottomPanelView`; verify search, expanded search, pinboard filters, and add-pinboard share a 26-point visible height while compact icon controls retain an approximately 32-point hit area.

## 2. Search Motion

- [x] 2.1 Replace the compact/expanded search branch swap with one trailing-anchored search pill that animates width from compact to expanded; verify the right edge stays fixed and adjacent command-bar controls do not move.
- [x] 2.2 Apply smooth 0.22-second expansion and collapse motion with delayed text/clear-button fade-in; verify search text remains focusable immediately and existing clear/search behavior is unchanged.

## 3. Verification

- [x] 3.1 Run `swift build` and `./script/verify_all.sh`; verify the project builds and all automated checks pass.
- [x] 3.2 Open the bottom panel in Aqua and Dark Aqua and manually verify matching visible heights, natural leftward expansion/collapse, empty-search collapse, persistent non-empty queries, clear button, add-pinboard popover, and constrained-width pinboard scrolling.
