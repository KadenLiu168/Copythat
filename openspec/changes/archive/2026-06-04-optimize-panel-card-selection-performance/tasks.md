## 1. Selection State

- [x] 1.1 Update store selection methods to avoid publishing when the target selection is already selected; verify with focused unit tests.
- [x] 1.2 Keep selection valid after filtered items change; verify search/filter changes select a visible item or clear selection.

## 2. Panel Rendering

- [x] 2.1 Update the panel timeline to use `selectedID` directly for selection, z-index, and scroll observation; verify no repeated `selectedItem` lookup remains in card rendering.
- [x] 2.2 Make card rendering equatable by `item`, `pinboards`, and `isSelected`, and apply `.equatable()` in the timeline; verify source icon identity tests still pass.
- [x] 2.3 Replace competing tap handlers with immediate single-click selection and double-click paste; verify double-click still invokes paste.
- [x] 2.4 Avoid unnecessary AppKit source image reassignment when the icon identity is unchanged; verify source icons remain per-card.

## 3. Verification

- [x] 3.1 Run `swift build`.
- [x] 3.2 Run `swift test`.
- [x] 3.3 Run `./script/verify_all.sh`.
