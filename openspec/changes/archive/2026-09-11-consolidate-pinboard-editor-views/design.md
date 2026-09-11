## Context

`BottomPanelView` presents `NewPinboardPopover` and `EditPinboardPopover`. Both render the same name field, fixed color choices, Cancel action, default Return action, focus-on-appear behavior, and fixed compact frame. The edit form additionally seeds state from a `CustomPinboard`, validates against its current name, and emits a name/color pair for the parent to apply.

## Goals / Non-Goals

**Goals:**

- Have one private editor implementation with a small explicit mode/configuration surface.
- Keep mode-specific title, initial state, validation callback, and completion callback outside the shared field layout.
- Preserve the existing native SwiftUI interaction behavior exactly.

**Non-Goals:**

- Changing any `AppSettings` API or moving validation/mutation into the editor.
- Introducing a reusable public component or a generic form framework.

## Decisions

1. **Use one private `PinboardEditorPopover` with explicit mode data.**
   Pass the title, initial name/color, validation closure, save/create closure, and cancel closure from the parent. A small internal mode value may supply defaults, but the editor must not infer persistence behavior from UI state.

   *Alternative considered:* keep two views and extract only a color-picker subview. Rejected because the duplicated form lifecycle and keyboard/focus behavior would remain.

2. **Keep mutations in `BottomPanelView` and `AppSettings`.**
   The create callback continues selecting the new pinboard; the edit callback continues renaming assignments and migrating selection. The shared editor only returns validated user input.

   *Alternative considered:* let the editor call `AppSettings` directly. Rejected because it would couple a reusable form to persistence and make create/edit side effects less explicit.

3. **Preserve state initialization and shortcuts.**
   Create mode starts with an empty name and amber color; edit mode starts with the selected pinboard's values. Both focus the name field on appear, submit on Return, cancel on Escape, and disable the primary action using the existing settings validation methods.

## Risks / Trade-offs

- [State initialization can reset when SwiftUI recreates the popover] → keep `@State` initialization in the editor initializer and retain the existing stable presentation bindings.
- [A shared callback signature could accidentally trim or mutate names] → leave trimming and assignment logic in the existing parent callbacks and verify rename/create scenarios manually.
- [Visual drift during consolidation] → compare the rendered form dimensions, labels, palette, focus, and keyboard behavior before and after.

## Migration Plan

1. Introduce the shared private editor and wire create/edit call sites.
2. Remove the two duplicated private view declarations.
3. Run focused pinboard tests, build, full verification, and manual UI checks.
4. Roll back by restoring the two original popovers if any create/edit behavior or layout regresses.

## Open Questions

None. The current create/edit requirements and callback contracts provide the complete design input.
