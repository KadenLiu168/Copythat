## 1. Pinboard Deletion Models

- [x] 1.1 Add `AppSettings.deleteCustomPinboard(named:) -> Bool` to remove matching custom pinboards and persist the updated list; verify successful deletion, relaunch persistence, and missing-name no-op behavior with focused settings tests.
- [x] 1.2 Add a narrow clipboard-store API to count and clear assignments for a pinboard name; verify matching items get `pinboardName = nil`, items are not deleted, and `isPinned` values are preserved.
- [x] 1.3 Ensure clearing assignments refreshes filtered items, saves clipboard history, and does not alter the active search query; verify with focused store tests.

## 2. Panel Deletion Flow

- [x] 2.1 Add a context menu to pinboard filter buttons that shows `Delete Pinboard...` only for custom pinboards; manually verify Clipboard and Pinned do not offer deletion.
- [x] 2.2 Wire the delete menu item to a confirmation alert that names the pinboard and includes the number of clips that will be moved out of it; manually verify empty and non-empty pinboard messages.
- [x] 2.3 On confirmation, delete the custom pinboard and clear matching clipboard item assignments without deleting clips or changing pinned state; verify with focused model/store tests and manual panel interaction.
- [x] 2.4 If the deleted pinboard is currently selected, switch to Clipboard; otherwise keep the active filter selected. Preserve the current search query in both cases; verify with focused selection/filter tests.

## 3. Verification

- [x] 3.1 Run `swift build` and fix any compile errors introduced by the deletion APIs or panel UI changes.
- [x] 3.2 Run `./script/verify_all.sh` and fix any regressions.
- [x] 3.3 Manually verify right-click delete, cancel, confirm, affected-count copy, deleting an empty pinboard, deleting the selected pinboard, deleting a non-selected pinboard, search preservation, horizontal pinboard scrolling, and unchanged Clipboard/Pinned behavior.
