## Why

The bottom panel has two nearly identical SwiftUI popovers for creating and editing custom pinboards. Their duplicated fields, color picker, focus handling, keyboard shortcuts, and layout can drift, increasing maintenance cost without adding user-visible capability.

## What Changes

- Replace the duplicated create/edit popover implementations with one private parameterized pinboard editor.
- Preserve create and edit titles, initial field values, validation rules, color selection, focus behavior, Return/Escape shortcuts, cancel behavior, and callbacks.
- Keep the existing `BottomPanelView` state and `AppSettings`/`ClipboardStore` mutation flow intact.
- Add focused coverage or compile-time/test fixtures for both editor modes and perform a manual panel interaction check.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

None. This is a view-only refactor that preserves the existing pinboard requirements and user-visible behavior.

## Impact

- **UI code:** `Sources/Copythat/Views/BottomPanelView.swift` consolidates the private editor views and keeps call sites explicit about create versus edit mode.
- **State and persistence:** no changes to pinboard validation, persistence, item assignments, selection migration, or clipboard history.
- **Tests:** existing pinboard settings/store tests remain authoritative; add only focused editor-mode coverage that is practical for the current SwiftUI test target.
- **Verification:** `swift build`, `swift test`, `./script/verify_all.sh`, and a manual create/edit/cancel/keyboard check must pass.

## Non-goals

- Changing the pinboard creation or edit requirements, labels, palette, or validation semantics.
- Moving pinboard mutation logic into a View or introducing a new UI framework.
- Refactoring unrelated command-bar, filter, delete, or card views.
- Changing persisted `pinboardsText` data or clipboard item assignments.
