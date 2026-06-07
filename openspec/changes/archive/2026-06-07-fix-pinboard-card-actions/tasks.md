## 1. Store Behavior

- [x] 1.1 Refresh filtered items after `togglePin(_:)`; verify unpinning the visible item in Pinned removes it immediately and updates selection.
- [x] 1.2 Refresh filtered items after `move(_:toPinboard:)`; verify removing the visible item from the active custom pinboard removes it immediately and updates selection.
- [x] 1.3 Decouple custom pinboard assignment from pinned state; verify assigning an unpinned item to a custom pinboard does not set `isPinned`, and assigning/removing a pinned item preserves `isPinned`.

## 2. Card Actions

- [x] 2.1 Confirm card menu labels remain state-driven from `item.isPinned` and `item.pinboardName`; verify unpinned cards show Pin, pinned cards show Unpin, and Remove from Pinboard appears only for assigned cards.

## 3. Verification

- [x] 3.1 Run `swift build` and fix any compile errors.
- [x] 3.2 Run `./script/verify_all.sh` and fix any regressions.
- [x] 3.3 Manually verify Pinned unpin, custom pinboard removal, menu label correctness, visible count updates, and search plus active-filter behavior.
