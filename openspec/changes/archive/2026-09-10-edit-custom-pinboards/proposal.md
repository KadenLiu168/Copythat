# Proposal: Edit Custom Pinboards

## Why

Once a custom pinboard is created, its name and color are frozen. Users who want to fix a typo, rename a category, or re-balance colors must delete the pinboard and recreate it — which ejects every assigned clip and forces them to re-organize by hand. This completes the pinboard lifecycle (Create → Use → Edit → Delete) with a proper Edit capability instead of a destructive workaround.

## What Changes

- Add an `Edit Pinboard...` action to the context menu of custom pinboard filters in the bottom panel, alongside the existing `Delete Pinboard...` destructive action.
- Add a compact, native macOS edit popover that reuses the visual language of the current new-pinboard form: a name field prefilled with the current name and a fixed color palette with the current color selected. Users may change the name only, the color only, or both in one save.
- Validate edited names with the same semantics as creation: trimmed, non-empty, and not duplicating another custom pinboard name. The pinboard's own current name does not count as a duplicate.
- When a pinboard is renamed, migrate every clipboard item assigned to the old name so no clip is silently ejected from the category, without touching item content, pin state, or the active search query.
- When the renamed pinboard is the currently selected filter, keep the user on the renamed pinboard; renaming a non-selected pinboard leaves the current filter untouched.
- Persist edited names, colors, and migrated assignments so they survive app relaunch.
- Changing only the color updates the pinboard marker immediately and does not rewrite any clipboard item assignment.
- Built-in Clipboard and Pinned pinboards remain non-editable and non-deletable.

## Non-goals

- No editing of the built-in Clipboard or Pinned pinboards.
- No arbitrary custom colors: no RGB sliders, hex input, NSColorPicker, or new color model. The fixed `PinboardColorToken` palette stays as-is.
- No pinboard reordering, pinboard icons, nested pinboards, or assigning one clip to multiple pinboards.
- No migration of pinboard identity to UUIDs or another stable-ID scheme; the current name-based identity stays and the rename cascade is handled explicitly.
- No change to pinboard deletion behavior, item pinning semantics, creation behavior, or the overall command bar layout.

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `panel-and-search`: add an Edit-custom-pinboards requirement covering the context menu action, the edit popover, name validation, rename with assignment visibility, color-only changes, combined rename + recolor, cancel, selected vs non-selected pinboard behavior, and search preservation.
- `clipboard-history`: add a minimal requirement that renaming a custom pinboard migrates the `pinboardName` assignment of affected history items (preserving content and pin state) and that migrated assignments persist across relaunch.

## Impact

- `Sources/Copythat/Stores/AppSettings.swift`: new narrow API to update a custom pinboard's name and color with validation and persistence.
- `Sources/Copythat/Stores/ClipboardStore.swift`: new narrow API to rename pinboard assignments across history items, refresh filtered items, persist history, and migrate the selected board when needed.
- `Sources/Copythat/Views/BottomPanelView.swift`: edit popover presentation, context menu wiring, and orchestration of the two domain APIs. No persistence logic in the view.
- `Tests/CopythatTests/AppSettingsPinboardTests.swift` and `Tests/CopythatTests/ClipboardStoreSelectionTests.swift`: new focused tests for update validation, assignment migration, selection migration, and search preservation.
- No new dependencies, no schema or persistence-format changes (same UserDefaults keys and history file shape), no permission or pasteboard behavior changes.
