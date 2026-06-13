## 1. Pinboard Category Marker Implementation

- [x] 1.1 Preserve each custom pinboard's configured persisted color and Pinned's built-in red while rendering category markers; verify no order-based color assignment remains.
- [x] 1.2 Replace the non-Clipboard short capsule marker and highlight with a compact strongly saturated circle while preserving the Clipboard history icon and existing selected-filter treatment; verify selected and unselected filters remain clear without changing layout or filtering behavior.

## 2. Verification

- [x] 2.1 Run `swift build` and `./script/verify_all.sh`; verify the project builds and all automated checks pass.
- [x] 2.2 Open the bottom panel in Aqua and Dark Aqua and manually verify vivid circular category markers, clear selected state, compact header layout, horizontal pinboard scrolling, and unchanged pinboard filtering behavior.
