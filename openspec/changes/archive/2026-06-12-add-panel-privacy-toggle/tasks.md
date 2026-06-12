## 1. Command Bar Toggle

- [x] 1.1 Add local panel state for hidden previews in `BottomPanelView`; verify the state is local to the panel and does not add defaults, persistence, or settings changes.
- [x] 1.2 Add a command-bar privacy button using the existing icon-button style with `eye` and `eye.slash`; verify the help text reflects the next action.
- [x] 1.3 Update the command-bar layout to keep the order `[Search] [Pinboards] [Privacy Toggle] [+]`; verify the privacy button remains fixed outside the scrollable pinboard region when custom pinboards overflow.

## 2. Card Preview Privacy Rendering

- [x] 2.1 Pass the hidden-preview state from `BottomPanelView` into each `ClipboardCardView`; verify existing selection, tap, double-click paste, context menu, and drag callbacks still compile and remain wired.
- [x] 2.2 Add a concealed card-body rendering path for hidden previews; verify text, URL, image, and file cards hide payload preview content while retaining item kind, timestamp, source context, card size, selection styling, and item actions.
- [x] 2.3 Restore normal card-body rendering when privacy mode is disabled; verify toggling does not mutate clipboard items, pin state, pinboard assignment, or search text.

## 3. Verification

- [x] 3.1 Add or update focused tests for `ClipboardCardView` and/or `BottomPanelView` covering visible and hidden preview states; verify tests assert user-observable privacy behavior without depending on unrelated styling.
- [x] 3.2 Run `swift build`; verify the macOS app target builds successfully.
- [x] 3.3 Run `./script/verify_all.sh`; verify the existing project verification suite passes.
- [x] 3.4 Manually check the bottom panel with enough custom pinboards to overflow; verify the layout order, fixed privacy button placement, preview hide/show behavior, search/filter behavior, and paste/card actions.
