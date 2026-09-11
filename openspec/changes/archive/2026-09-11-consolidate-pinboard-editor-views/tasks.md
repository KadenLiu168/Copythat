## 1. Consolidate the editor implementation

- [x] 1.1 Define the shared private editor configuration/mode and preserve create/edit titles, initial name/color, validation closure, and completion callbacks; verify the file compiles and both parent call sites provide the expected mode data.
- [x] 1.2 Move the common name field, color choices, action buttons, focus-on-appear, Return, Escape, padding, and frame behavior into the shared editor; verify the rendered form retains the existing labels, palette, focus, and keyboard shortcuts.
- [x] 1.3 Remove the duplicated `NewPinboardPopover` and `EditPinboardPopover` declarations without changing `BottomPanelView` mutation callbacks; verify repository search finds one editor implementation and existing pinboard store/settings tests still pass.

## 2. Regression verification

- [x] 2.1 Exercise create, edit, rename, recolor, invalid-name, cancel, Return, and Escape flows in focused tests or the native panel; verify assignments, selection migration, and persisted settings remain unchanged.
- [x] 2.2 Run `swift build`, `swift test`, `./script/verify_all.sh`, and `git diff --check`; verify no clipboard, pinboard persistence, search, or panel-layout regression is introduced.
