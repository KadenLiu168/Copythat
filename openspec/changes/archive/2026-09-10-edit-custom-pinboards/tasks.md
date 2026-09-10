# Tasks: Edit Custom Pinboards

## 1. Pinboard model/settings editing

- [x] 1.1 Add a narrow `AppSettings` API to update a custom pinboard's name and color (e.g. `updateCustomPinboard(named:newName:color:) -> Bool`): trims the new name, rejects empty names and names duplicating a *different* custom pinboard, allows the pinboard's own current name, updates `customPinboards` so the existing `didSet` persists. Verify with focused tests in `AppSettingsPinboardTests`: rename success, recolor success, rename+recolor success, name trimming, empty-name rejection, duplicate-name rejection, own-name allowed, missing pinboard no-op/failure, and persistence across an `AppSettings` recreation.
- [x] 1.2 Confirm validation semantics exactly match creation (same trim, same exact-match duplicate rule, no new case-insensitive rule); verify with a focused test that a case-only rename (e.g. `Work` → `work`) succeeds while an exact duplicate of another pinboard fails.

## 2. Clipboard assignment rename

- [x] 2.1 Add a narrow `ClipboardStore` API to rename pinboard assignments (e.g. `renamePinboardAssignments(from:to:)`): rewrites `pinboardName` old → new for all matching items, leaves other assignments and unassigned items untouched, preserves `isPinned` and item content, refreshes filtered items, and saves history. Verify with focused tests in `ClipboardStoreSelectionTests`: all matching assignments renamed, unrelated assignments untouched, unassigned items untouched, `isPinned` preserved, `filteredItems` refreshed, and the persistence closure called with migrated items.
- [x] 2.2 Migrate `selectedBoardID` from `Pinboard.custom(oldName).id` to `Pinboard.custom(newName).id` only when the renamed pinboard is currently selected; never touch `selectedBoardID` or `searchText` otherwise. Verify with focused tests: selected custom pinboard follows the rename, non-selected pinboard rename leaves selection unchanged, and `searchText` is preserved in both cases.
- [x] 2.3 Ensure a color-only edit path performs no assignment rewrite (store API is simply not called); verify with a focused test that items with `pinboardName == oldName` are byte-identical after a color-only settings update.

## 3. Edit Pinboard UI

- [x] 3.1 Add `Edit Pinboard...` (normal role) to the custom pinboard context menu above the existing `Delete Pinboard...` (destructive role); built-in Clipboard and Pinned filters keep no menu. Verify manually: right-click each filter kind.
- [x] 3.2 Add an edit popover reusing the `NewPinboardPopover` layout: title "Edit Pinboard", name field prefilled with the current name and focused on appear, palette with the current color selected, Cancel (cancelAction) and Save (defaultAction). Save is disabled for invalid names per Task 1.1/1.2 rules. Verify manually against the creation popover for visual parity.
- [x] 3.3 Wire Save to validate via the settings API first, then — only when the name changed — call the store rename API and migrate selection; color-only saves call only the settings API. Return commits, Escape cancels without mutating anything, and Escape inside the popover does not close the panel. Verify manually; cover commit/cancel state effects with focused tests where the existing test harness allows.

## 4. Integration / regression

- [x] 4.1 Exercise the full matrix with focused tests and manual verification: rename, recolor, rename+recolor, duplicate-name rejection, empty-name rejection, rename of the selected pinboard, rename of a non-selected pinboard, assignment migration, and search preservation throughout.
- [x] 4.2 Verify relaunch persistence manually: rename + recolor a pinboard with assigned clips, quit, relaunch — new name, new color, and migrated assignments are all intact.
- [x] 4.3 Regression-check neighboring flows manually: create pinboard, delete pinboard (confirm + cancel), pin/unpin, move to pinboard, search, paste — all unchanged.

## 5. Verification

- [x] 5.1 Run `swift build` and fix any compile errors.
- [x] 5.2 Run `./script/verify_all.sh` and fix any regressions.
- [x] 5.3 Manual end-to-end pass: create `Work`, assign multiple clips, select `Work`, open Edit, change `Work` → `Project` and amber → blue, Save. Confirm: header shows `Project` with the new marker color immediately, `Project` stays selected, all original clips still visible and unchanged, pin states unchanged, search query unchanged, and state survives relaunch.
