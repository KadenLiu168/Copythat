# Design: Edit Custom Pinboards

## Context

Pinboard identity is name-based and that name is referenced from three places:

```text
CustomPinboard.name  (= CustomPinboard.id)
        |
        +-- Pinboard.custom(name).id  ==  "custom:<name>"   (selectedBoardID)
        |
        +-- ClipboardItem.pinboardName                      (persisted history)
```

A rename is therefore not a single-field update: it is a cascade across the settings model, the persisted history items, and the in-memory filter selection. Two persistence stores are involved — `UserDefaults` (custom pinboard list, via `AppSettings`) and the clipboard history file (via `ClipboardStore`'s `persistItems` closure). There is no transaction spanning them.

Current code facts that shape this design:

- `AppSettings.customPinboards` is `@Published private(set)` with a `didSet` that persists; creation already trims, rejects empty names, and rejects exact duplicates (case-sensitive).
- `ClipboardStore.selectedBoardID` is a plain `String` whose `didSet` calls `refreshFilteredItems()`; an unrecognized id decodes to `Pinboard.kind == .unknown`, which filters like "All" — so a stale `custom:<oldName>` id after a rename would silently show all items, i.e. the "jumped back to Clipboard" failure mode the spec forbids.
- `BottomPanelView` already owns the deletion flow (`requestPinboardDeletion` / `confirmPinboardDeletion`) and the `NewPinboardPopover` creation form; the edit flow should mirror both.
- Pinboard strip titles and colors in the header derive from `settings.customPinboards`, so a settings update refreshes the UI without extra wiring.

## Goals / Non-Goals

**Goals:**
- A rename is atomic from the user's perspective: one Save updates name, color, assignments, and selection consistently.
- Validation semantics are identical to creation (trim, non-empty, exact-match duplicate check), with the pinboard's own current name exempted from the duplicate check.
- A color-only edit is a fast path that never rewrites history items.
- Clear ownership: `AppSettings` owns pinboard config, `ClipboardStore` owns history assignments and selection, the view only orchestrates.

**Non-Goals:**
- No stable-ID / UUID migration (see Risks).
- No new color model, no reordering, no multi-assignment.
- No change to deletion flow; the edit flow only parallels it.

## Decisions

### 1. Keep name-based identity; implement an explicit rename cascade

Alternative considered: migrate pinboards to stable UUIDs now. Rejected — it expands a bounded UX feature into a persistence-schema and identity migration across settings, history items, and selection state. The cascade is small and fully enumerable (three reference sites, listed above), so handling it explicitly is the smaller change.

### 2. Two narrow domain APIs, orchestrated by the view

```text
BottomPanelView (Save)
        |
        +--> AppSettings.updateCustomPinboard(named:newName:color:) -> Bool
        |         trim + validate, update customPinboards (didSet persists)
        |
        +--> ClipboardStore.renamePinboardAssignments(from:to:)   [name changed only]
        |         rewrite pinboardName old -> new, refresh, saveItems()
        |
        +--> ClipboardStore: migrate selectedBoardID old -> new   [name changed only]
                  only if selectedBoardID == Pinboard.custom(oldName).id
```

Rationale: mirrors the existing deletion orchestration (`deleteCustomPinboard` + `clearPinboardAssignments` + `selectClipboardIfViewingPinboard`). The view never iterates items or writes persistence itself. Exact signatures are implementation details; the split is the contract.

Alternative considered: a single `AppSettings`-level "rename pinboard" that also mutates the store. Rejected — `AppSettings` has no reference to history items today and introducing that dependency crosses the store boundary for no benefit.

### 3. Validate before mutating anything

The update API returns success/failure (like `createCustomPinboard` / `deleteCustomPinboard`). The view runs validation first and only touches the store when the settings update succeeded. Invalid names (empty after trim, duplicate of a *different* pinboard) are rejected; the duplicate check compares trimmed names exactly, matching creation semantics — no new case-insensitive rule is introduced. Trimming the new name also means a rename never introduces a name that differs only by surrounding whitespace.

Edge case: saving with name and color both unchanged is a valid no-op success — the form closes and nothing is rewritten.

### 4. Color-only edit is a fast path

When the trimmed new name equals the current name, the view calls only the settings update. `renamePinboardAssignments` is not called, so history items are untouched — this is a spec-level guarantee, not just an optimization.

### 5. Persistence ordering: settings first, then history

On rename: update `AppSettings` (persists pinboard list to UserDefaults) → migrate assignments (persists history file) → migrate selection (in-memory only). Both stores are local and synchronous, but there is a crash window between the two writes.

Rationale for this order: if the app dies mid-save, the surviving inconsistency is "pinboard renamed, some items still referencing the old name." Orphaned items remain fully visible and usable under the Clipboard (all) filter and keep their pin state — degraded organization, zero data loss. The reverse order ("items migrated, pinboard not renamed") would leave items pointing at a name that no longer exists in the pinboard list, which is the same orphan state but with a stale pinboard still showing in the header. The chosen order is the less confusing failure shape. No self-healing sweep is added; the window is a sub-second local-write race and the failure is benign and user-recoverable via the same edit feature.

### 6. Selection migration lives in ClipboardStore, keyed off the exact id

`selectedBoardID` is migrated only when it equals `Pinboard.custom(oldName).id`, and it is set to `Pinboard.custom(newName).id`. Setting it reuses the existing `didSet` → `refreshFilteredItems()` path, and `searchText` is never touched. Renaming a non-selected pinboard does not touch `selectedBoardID` at all. This is the direct counterpart of `selectClipboardIfViewingPinboard(named:)` from the deletion flow.

### 7. Edit UI mirrors creation and deletion patterns

- Context menu on custom pinboard filters gains `Edit Pinboard...` (normal role) above the existing `Delete Pinboard...` (destructive role). Built-in filters keep no menu.
- The edit popover reuses the `NewPinboardPopover` layout and controls (same name field, same fixed palette circles, same Cancel/confirm buttons) with: title "Edit Pinboard", prefilled name and selected color, Save as the default-action button, and Save disabled when the name is invalid (same enablement rule as Create, plus the own-name exemption).
- Return commits, Escape cancels — matching the creation popover's keyboard behavior and the panel's existing `.onExitCommand` handling so Escape inside the popover does not close the whole panel while editing.

## Risks / Trade-offs

- [Name-based identity means every future pinboard mutation must remember the cascade] → Mitigated here by keeping the cascade in two narrow, test-covered APIs; a dedicated stable-ID change is the proper long-term fix and is explicitly deferred (see proposal Non-goals). Future consideration: pinboard identity currently depends on its mutable display name; a future dedicated migration may introduce a stable pinboard identifier.
- [Crash between the UserDefaults write and the history-file write leaves orphaned assignments] → Ordering per Decision 5 makes the failure shape benign (items still visible under Clipboard, pins intact); user can re-assign or rename back. No transactional store exists and adding one is out of scope.
- [Two pinboards could race toward the same name via legacy data or hand-edited defaults] → Validation on save rejects duplicates; loading already de-duplicates legacy names. No new invariant introduced by this change.
- [Case-only rename, e.g. `Work` → `work`, collides with nothing but may surprise users on case-sensitive matching] → Allowed intentionally: creation semantics are exact-match and stay unchanged; spec records this as "no new case-insensitive rule."
- [Partial update (settings updated, store call skipped on failure)] → Store migration only runs after a successful settings update; a failed validation mutates nothing. There is no path that migrates assignments without renaming the pinboard.

## Migration Plan

No data migration. Persistence formats are unchanged: the same `customPinboards` UserDefaults payload and the same history file shape. A rename simply writes new values into existing fields. Rollback is "revert the code"; existing renamed data remains valid because both stores only ever held strings.
