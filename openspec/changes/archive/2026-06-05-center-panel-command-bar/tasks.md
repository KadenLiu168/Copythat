## 1. Centered Command Bar Implementation

- [x] 1.1 Recompose the panel header as one centered command group containing search, the complete pinboard filter strip including Clipboard, and add-pinboard; verify default controls are centered without changing their actions.
- [x] 1.2 Apply a larger gap between the search, pinboard, and add-pinboard groups than between individual pinboard filters; verify the spacing hierarchy matches the intended compact command-bar rhythm.
- [x] 1.3 Increase non-Clipboard category marker circles from 8 by 8 points to 10 by 10 points and adjust marker-to-label spacing if needed; verify configured colors, filter height, and selected/unselected treatment remain unchanged.
- [x] 1.4 Keep search and add-pinboard visible while allowing only the pinboard strip to consume flexible width and scroll horizontally; verify the command group remains centered when search is expanded and when many custom pinboards exist.

## 2. Verification

- [x] 2.1 Run `swift build` and `./script/verify_all.sh`; verify the project builds and all automated checks pass.
- [x] 2.2 Open the bottom panel and manually verify default centering, spacing hierarchy, larger markers, search expansion, pinboard overflow scrolling, filter selection, and the add-pinboard popover in Aqua and Dark Aqua.
